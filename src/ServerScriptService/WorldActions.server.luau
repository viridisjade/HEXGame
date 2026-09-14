--[[
    WorldActions (Script)
    Ort: ServerScriptService > WorldActions
    
    Welt-Aktionen: Province claimen, Camp bauen, Unit spawnen.
    
    ERSETZT (in Studio LÖSCHEN!):
      - ClaimProvinceHandler  (RequestClaimProvince)
      - SpawnUnitHandler      (RequestSpawnUnit, Test-Remote)
      - BuildCampHandler      (RequestBuildCamp)
    
    WICHTIG: Nicht zusammen mit den alten Handlern laufen lassen!
    RemoteEvents verhalten sich wie normale Events - sind alte UND neue
    Handler verbunden, wird jede Aktion ZWEIMAL ausgeführt.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HexData = require(script.Parent:WaitForChild("HexData"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local ArmyData = require(script.Parent:WaitForChild("ArmyData"))
local ClaimSystem = require(script.Parent:WaitForChild("ClaimSystem"))
local ArmySpawner = require(script.Parent:WaitForChild("ArmySpawner"))
local BuildingSystem = require(script.Parent:WaitForChild("BuildingSystem"))
local FogOfWarSystem = require(script.Parent:WaitForChild("FogOfWarSystem"))
local PointSystem = require(script.Parent:WaitForChild("PointSystem"))
local VictoryConfig = require(ReplicatedStorage:WaitForChild("VictoryConfig"))

local dataRemotes = ReplicatedStorage:WaitForChild("DataRemotes", 30)

--------------------------------------------------------------------------------
-- ArmyStatsNotifier (analog zu _G.NotifyCityStatsChanged)
--
-- Feuert ArmyStatsChanged an den Besitzer, wenn sich eine Army geaendert hat
-- (Kampf, Bewegung, Runde, Einheiten hinzugefuegt/entfernt, Kampfbeginn/-ende).
-- Aufrufbar ueber _G.NotifyArmyStatsChanged(armyId) aus jedem Server-Script.
-- Der Client filtert selbst ob diese Army gerade ausgewaehlt ist.
--------------------------------------------------------------------------------
local armyStatsChangedRemote = dataRemotes:FindFirstChild("ArmyStatsChanged")

_G.NotifyArmyStatsChanged = function(armyId)
	if not armyStatsChangedRemote then return end
	local army = ArmyData.GetArmy(armyId)
	if not army or not army.owner then return end
	armyStatsChangedRemote:FireClient(army.owner, armyId)
end

--------------------------------------------------------------------------------
-- Hilfsfunktionen
--------------------------------------------------------------------------------
local function onEvent(name, handler)
	local remote = dataRemotes:WaitForChild(name, 5)
	if not remote then
		warn("[WorldActions] RemoteEvent fehlt: " .. name)
		return
	end
	remote.OnServerEvent:Connect(handler)
end

-- Spielerdaten sicherstellen (Lazy-Init wie in den alten Handlern)
local function ensurePlayerData(player)
	if not PlayerData.GetPlayerData(player) then
		PlayerData.InitPlayer(player)
	end
end

--------------------------------------------------------------------------------
-- RequestClaimProvince
-- Client sendet (q, r) -> Server claimt die Province dieses Hexes
--------------------------------------------------------------------------------
onEvent("RequestClaimProvince", function(player, q, r)
	ensurePlayerData(player)

	local hex = HexData.GetHex(q, r)
	if not hex then
		warn("[WorldActions] Hex nicht gefunden: (" .. tostring(q) .. ", " .. tostring(r) .. ")")
		return
	end

	local provinceId = hex.province
	if not provinceId or provinceId <= 0 then
		warn("[WorldActions] Hex (" .. tostring(q) .. ", " .. tostring(r) .. ") gehört zu keiner Province")
		return
	end

	if ClaimSystem.ClaimProvince(player, provinceId) then
		print("[WorldActions] Province " .. provinceId .. " von " .. player.Name .. " geclaimt")
		-- VICTORY: ProvinceClaimed +15 Punkte.
		pcall(PointSystem.AwardPoints, player, "ProvinceClaimed",
			VictoryConfig.ACTIVE_POINTS.ProvinceClaimed)
	else
		warn("[WorldActions] Claim fehlgeschlagen für Province " .. provinceId)
	end
end)

--------------------------------------------------------------------------------
-- RequestSpawnUnit (Test-Remote)
--------------------------------------------------------------------------------
onEvent("RequestSpawnUnit", function(player, unitType, q, r)
	local armyId, unitId = ArmySpawner.SpawnUnit(player, unitType, q, r)

	if armyId and unitId then
		print("[WorldActions] Unit '" .. tostring(unitType) .. "' gespawnt (Army " .. armyId .. ")")
		-- Fog of War: neue Unit erweitert die Sicht des Besitzers.
		pcall(FogOfWarSystem.UpdateVision, player)
	else
		warn("[WorldActions] Spawn fehlgeschlagen: '" .. tostring(unitType)
			.. "' auf (" .. tostring(q) .. ", " .. tostring(r) .. ")")
	end
end)

--------------------------------------------------------------------------------
-- RequestBuildCamp
-- Baut ein Camp auf dem Hex, auf dem die Armee des Spielers steht
--------------------------------------------------------------------------------
onEvent("RequestBuildCamp", function(player, armyId)
	ensurePlayerData(player)

	local army = ArmyData.GetArmy(armyId)
	if not army then
		warn("[WorldActions] Army " .. tostring(armyId) .. " nicht gefunden")
		return
	end

	if army.owner ~= player then
		warn("[WorldActions] " .. player.Name .. " besitzt Army " .. tostring(armyId) .. " nicht")
		return
	end

	local buildingId, reason = BuildingSystem.BuildBuilding(player, "Camp", army.q, army.r)

	if buildingId then
		print("[WorldActions] Camp gebaut (ID: " .. buildingId .. ") von " .. player.Name)
		-- Fog of War: ein Camp ist eine Sichtquelle (CAMP_SIGHT).
		pcall(FogOfWarSystem.UpdateVision, player)
		-- VICTORY: CampBuilt +25 Punkte.
		pcall(PointSystem.AwardPoints, player, "CampBuilt",
			VictoryConfig.ACTIVE_POINTS.CampBuilt)
	else
		warn("[WorldActions] Camp-Bau fehlgeschlagen: " .. tostring(reason))
	end
end)

print("[WorldActions] Bereit.")