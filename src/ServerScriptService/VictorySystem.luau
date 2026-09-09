--[[
    VictorySystem (ModuleScript)
    Ort: ServerScriptService > VictorySystem

    Sieg + Elimination.
        CheckVictory()      -> prueft Punkte-Sieg (solo/allianz) und
                               Last-Man-Standing. Erklart den Sieger.
        EliminatePlayer()   -> loescht Units, neutralisiert Cities/Camps,
                               unclaimt Provinzen, zieht Punkte ab,
                               benachrichtigt alle.
        DeclareVictory()    -> sendet VictoryAchieved an alle, beendet Spiel.

    SIEG-BEDINGUNGEN (eine davon reicht):
        1. LETZTER UEBERLEBENDER: Nur noch Spieler EINER Allianz (oder ein
           Solo-Spieler) sind uebrig.
        2. PUNKTE-SIEG SOLO: Ein Spieler erreicht SOLO_WIN_POINTS.
        3. PUNKTE-SIEG ALLIANZ: Eine Allianz erreicht gemeinsam
           ALLIANCE_WIN_POINTS.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local PointSystem = require(script.Parent:WaitForChild("PointSystem"))
local CityData = require(script.Parent:WaitForChild("CityData"))
local CampData = require(script.Parent:WaitForChild("CampData"))
local ArmyData = require(script.Parent:WaitForChild("ArmyData"))
local UnitData = require(script.Parent:WaitForChild("UnitData"))
local ArmySystem = require(script.Parent:WaitForChild("ArmySystem"))
local ArmySpawner = require(script.Parent:WaitForChild("ArmySpawner"))
local ClaimSystem = require(script.Parent:WaitForChild("ClaimSystem"))
local DiplomacySystem = require(script.Parent:WaitForChild("DiplomacySystem"))
local VictoryConfig = require(ReplicatedStorage:WaitForChild("VictoryConfig"))

local VictorySystem = {}

local dataRemotes = ReplicatedStorage:WaitForChild("DataRemotes", 30)
local gameOver = false

local function remote(name)
	return dataRemotes and dataRemotes:FindFirstChild(name) or nil
end

local function notifyAllPlayers(remoteName, payload)
	local rem = remote(remoteName)
	if not rem then return end
	pcall(function()
		rem:FireAllClients(payload)
	end)
end

--------------------------------------------------------------------------------
-- DECLARE VICTORY
--------------------------------------------------------------------------------
function VictorySystem.DeclareVictory(winner)
	if gameOver then return end
	gameOver = true

	local payload
	if winner.isAlliance then
		payload = {
			winnerType = "alliance",
			winnerName = table.concat(winner.names, ", "),
			finalPoints = winner.points,
		}
		print(("[Victory] Allianz [%s] hat mit %d Punkten gewonnen!")
			:format(payload.winnerName, payload.finalPoints))
	else
		payload = {
			winnerType = "solo",
			winnerName = winner.name,
			finalPoints = winner.points,
		}
		print(("[Victory] Spieler %s hat mit %d Punkten gewonnen!")
			:format(winner.name, winner.points))
	end

	notifyAllPlayers("VictoryAchieved", payload)
end

--------------------------------------------------------------------------------
-- ELIMINIEREN
--------------------------------------------------------------------------------
function VictorySystem.EliminatePlayer(player, eliminator, reason)
	if not player then return end
	if PlayerData.IsEliminated(player) then return end

	PlayerData.SetEliminated(player, true)
	reason = reason or "Hauptstadt verloren"

	-- PUNKTE: eliminierten Spieler aus der Allianz entfernen (Pool sinkt).
	-- Der Eliminator erhaelt +150 (ACTIVE_POINTS.PlayerEliminated).
	if PlayerData.GetAllianceId(player) then
		PlayerData.SetAllianceId(player, nil)
	end
	if eliminator then
		PointSystem.AwardPoints(eliminator, "PlayerEliminated",
			VictoryConfig.ACTIVE_POINTS.PlayerEliminated)
	end
	-- Allianz loest sich auf, wenn nur noch <2 Mitglieder uebrig sind.
	pcall(DiplomacySystem.CleanupAlliances)

	-- UNITS loeschen.
	for _, army in ipairs(ArmyData.GetArmiesByOwner(player)) do
		local q, r = army.q, army.r
		for _, unitId in ipairs(army.units or {}) do
			UnitData.RemoveUnit(unitId)
		end
		army.units = {}
		ArmySpawner.DespawnArmy(army.id)
		pcall(ArmySystem.DeleteArmy, army.id)
	end

	-- CAMPS neutralisieren.
	for _, camp in ipairs(CampData.GetCampsByOwner(player)) do
		camp.owner = nil
	end

	-- CITIES neutralisieren (inkl. Hauptstadt-Marker entfernen).
	for _, city in ipairs(CityData.GetCitiesByOwner(player)) do
		city.owner = nil
	end
	if PlayerData.GetCapitalCityId(player) then
		PlayerData.SetCapitalCityId(player, nil)
	end

	-- PROVINZEN unclaimen (Kopie - UnclaimProvince mutiert die Provinzliste).
	local provinces = {}
	for _, provinceId in ipairs(PlayerData.GetProvinces(player)) do
		provinces[#provinces + 1] = provinceId
	end
	for _, provinceId in ipairs(provinces) do
		pcall(ClaimSystem.UnclaimProvince, provinceId)
	end

	-- Benachrichtigung an alle.
	notifyAllPlayers("PlayerEliminated", {
		playerId = player.UserId,
		playerName = player.Name,
		reason = reason,
	})

	print(("[Victory] Spieler %s wurde eliminiert (%s)"):format(player.Name, reason))
end

--------------------------------------------------------------------------------
-- CHECK VICTORY
--------------------------------------------------------------------------------
-- Sammelt alle nicht-eliminierten Spieler und gruppiert sie in Fraktionen
-- (Allianz oder Solo). Punkte-Sieg + Last-Man-Standing.
function VictorySystem.CheckVictory()
	if gameOver then return end

	local active = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if not PlayerData.IsEliminated(player) then
			table.insert(active, player)
		end
	end

	-- PUNKTE-SIEG SOLO.
	for _, player in ipairs(active) do
		local pts = PointSystem.GetPoints(player)
		if pts >= VictoryConfig.SOLO_WIN_POINTS then
			VictorySystem.DeclareVictory({
				isAlliance = false,
				name = player.Name,
				points = pts,
			})
			return
		end
	end

	-- PUNKTE-SIEG ALLIANZ + LAST-MAN-STANDING.
	local factions = {}   -- [key] = { players = {...}, allianceId = idOrNil }
	for _, player in ipairs(active) do
		local allianceId = PlayerData.GetAllianceId(player)
		local key = allianceId or ("solo_" .. player.UserId)
		local f = factions[key]
		if not f then
			f = { players = {}, allianceId = allianceId }
			factions[key] = f
		end
		table.insert(f.players, player)
	end

	-- Last-Man-Standing: nur EINE Fraktion uebrig.
	if #active > 0 and next(factions) then
		local count = 0
		local onlyFaction
		for _, f in pairs(factions) do
			count += 1
			onlyFaction = f
		end
		if count == 1 then
			local f = onlyFaction
			if f.allianceId and #f.players >= 2 then
				-- Allianz hat als Einzige ueberlebt.
				local points = PointSystem.GetAlliancePoints(f.allianceId)
				local names = {}
				for _, p in ipairs(f.players) do names[#names + 1] = p.Name end
				VictorySystem.DeclareVictory({
					isAlliance = true,
					names = names,
					points = points,
				})
			elseif f.players[1] then
				-- Solo-Spieler hat als Einziger ueberlebt.
				local player = f.players[1]
				VictorySystem.DeclareVictory({
					isAlliance = false,
					name = player.Name,
					points = PointSystem.GetPoints(player),
				})
			end
			return
		end

		-- Punkte-Sieg Allianz (bei >1 Fraktionen erlaubt).
		for _, f in pairs(factions) do
			if f.allianceId and #f.players >= 2 then
				local points = PointSystem.GetAlliancePoints(f.allianceId)
				if points >= VictoryConfig.ALLIANCE_WIN_POINTS then
					local names = {}
					for _, p in ipairs(f.players) do names[#names + 1] = p.Name end
					VictorySystem.DeclareVictory({
						isAlliance = true,
						names = names,
						points = points,
					})
					return
				end
			end
		end
	end
end

function VictorySystem.IsGameOver()
	return gameOver
end

return VictorySystem
