--[[
    PointSystem (ModuleScript)
    Ort: ServerScriptService > PointSystem

    Vermaltet die Sieg-Punkte der Spieler.

    PASSIVE PUNKTE (jede Runde am Rundenende):
        City +10, Camp +3, Province +1     (siehe VictoryConfig.PASSIVE_POINTS)

    AKTIVE PUNKTE (einmalig bei Ereignis):
        CityFounded, ArmyDefeated, CityConquered, PlayerEliminated,
        GoldTech, CampBuilt, ProvinceClaimed   (siehe VictoryConfig.ACTIVE_POINTS)

    VERLUST-PUNKTE (einmalig):
        CityLost, CampLost, ProvinceLost       (siehe VictoryConfig.LOSS_POINTS)
        Punkte fallen nie unter 0.

    ALLIANZ-PUNKTE = Summe aller (nicht eliminierten) Mitglieder der Allianz.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local CityData = require(script.Parent:WaitForChild("CityData"))
local CampData = require(script.Parent:WaitForChild("CampData"))
local VictoryConfig = require(ReplicatedStorage:WaitForChild("VictoryConfig"))

local PointSystem = {}

local dataRemotes = ReplicatedStorage:WaitForChild("DataRemotes", 30)

local function remote(name)
	return dataRemotes and dataRemotes:FindFirstChild(name) or nil
end

local function firePoints(player, points, reason, delta)
	if not player then return end
	local rem = remote("PointsUpdate")
	if not rem then return end
	pcall(function()
		rem:FireClient(player, {
			playerId = player.UserId,
			points = points,
			reason = reason,
			delta = delta,
		})
	end)
end

--------------------------------------------------------------------------------
-- GETTER
--------------------------------------------------------------------------------
function PointSystem.GetPoints(player)
	return PlayerData.GetPoints(player) or 0
end

function PointSystem.GetPointsByUserId(userId)
	for _, player in ipairs(Players:GetPlayers()) do
		if player.UserId == userId then
			return PointSystem.GetPoints(player)
		end
	end
	return 0
end

-- Punkte aller Mitglieder einer Allianz (nur nicht-eliminierte Spieler).
function PointSystem.GetAlliancePoints(allianceId)
	if not allianceId then return 0 end
	local total = 0
	for _, player in ipairs(Players:GetPlayers()) do
		if not PlayerData.IsEliminated(player)
			and PlayerData.GetAllianceId(player) == allianceId then
			total += PointSystem.GetPoints(player)
		end
	end
	return total
end

--------------------------------------------------------------------------------
-- AKTIVE PUNKTE VERGEBEN
--------------------------------------------------------------------------------
function PointSystem.AwardPoints(player, reason, amount)
	if not player then return end
	if PlayerData.IsEliminated(player) then return end

	local pts = PointSystem.GetPoints(player)
	pts = pts + (amount or 0)
	PlayerData.SetPoints(player, pts)

	local rem = remote("PointsUpdate")
	if rem then
		firePoints(player, pts, reason, amount)
	end
	return pts
end

--------------------------------------------------------------------------------
-- PUNKTE ABZIEHEN (nie unter 0)
--------------------------------------------------------------------------------
function PointSystem.DeductPoints(player, reason, amount)
	if not player then return end

	local pts = PointSystem.GetPoints(player)
	local before = pts
	pts = math.max(0, pts - (amount or 0))
	PlayerData.SetPoints(player, pts)

	local delta = pts - before
	if delta ~= 0 then
		firePoints(player, pts, reason, delta)
	end
	return pts
end

--------------------------------------------------------------------------------
-- PASSIVE PUNKTE (jede Runde am Rundenende)
--------------------------------------------------------------------------------
-- Summiert City/Camp/Provinz und vergibt sie. Gibt die vergebenen Punkte zurueck.
function PointSystem.CalculateRoundPoints(player)
	if not player then return 0 end
	if PlayerData.IsEliminated(player) then return 0 end

	local cfg = VictoryConfig.PASSIVE_POINTS
	local gained = 0

	-- Cities: jede eigene City +City.
	for _, city in ipairs(CityData.GetCitiesByOwner(player)) do
		gained += cfg.City or 0
	end

	-- Camps: jedes eigene Camp +Camp.
	for _, camp in ipairs(CampData.GetCampsByOwner(player)) do
		gained += cfg.Camp or 0
	end

	-- Provinzen: jede eigene Provinz +Province.
	gained += (PlayerData.GetProvinceCount(player) or 0) * (cfg.Province or 0)

	if gained > 0 then
		local pts = PointSystem.GetPoints(player)
		PlayerData.SetPoints(player, pts + gained)
		local rem = remote("PointsUpdate")
		if rem then
			firePoints(player, pts + gained, "RoundPassive", gained)
		end
	end

	return gained
end

return PointSystem
