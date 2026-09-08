
--[[
    PlayerCleanupHandler (Script)
    Ort: ServerScriptService > PlayerCleanupHandler
    
    Räumt auf, wenn ein Spieler das Spiel verlässt.
--]]

local Players = game:GetService("Players")

local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local ArmyData = require(script.Parent:WaitForChild("ArmyData"))
local UnitData = require(script.Parent:WaitForChild("UnitData"))
local MovementOrderData = require(script.Parent:WaitForChild("MovementOrderData"))
local ArmySpawner = require(script.Parent:WaitForChild("ArmySpawner"))
local CityData = require(script.Parent:WaitForChild("CityData"))
local CampData = require(script.Parent:WaitForChild("CampData"))
local ProvinceData = require(script.Parent:WaitForChild("ProvinceData"))
local ClaimSystem = require(script.Parent:WaitForChild("ClaimSystem"))
local CombatSystem = require(script.Parent:WaitForChild("CombatSystem"))

local LOG_PREFIX = "[PlayerCleanup]"

local CONFIG = {
	DESPAWN_ARMIES = true,
	REMOVE_UNITS = true,
	NEUTRALIZE_CITIES = false,
	NEUTRALIZE_CAMPS = false,
	UNCLAIM_PROVINCES = false,
}

local function cleanupPlayer(player)
	local stats = { armies = 0, units = 0, cities = 0, camps = 0, provinces = 0 }

	----------------------------------------------------------------------------
	-- 0) COMBAT FIRST: switch all running combats of this player to auto attack
	--    (3s timer) or close them when both sides are gone. Must happen BEFORE
	--    the armies are despawned, otherwise the combat references dead armies.
	----------------------------------------------------------------------------
	local combatOk, combatErr = pcall(function()
		CombatSystem.HandlePlayerDisconnect(player)
	end)
	if not combatOk then
		warn(LOG_PREFIX .. " Combat-Cleanup fehlgeschlagen: " .. tostring(combatErr))
	end

	if CONFIG.DESPAWN_ARMIES then
		local armies = ArmyData.GetArmiesByOwner(player)

		for _, army in ipairs(armies) do
			MovementOrderData.CancelOrder(army.id)
			ArmySpawner.DespawnArmy(army.id)
			stats.armies = stats.armies + 1
		end

		if CONFIG.REMOVE_UNITS then
			local units = UnitData.GetUnitsByOwner(player)
			for _, unit in ipairs(units) do
				UnitData.RemoveUnit(unit.id)
				stats.units = stats.units + 1
			end
		end
	end

	if CONFIG.NEUTRALIZE_CITIES then
		local cities = CityData.GetCitiesByOwner(player)
		for _, city in ipairs(cities) do
			CityData.SetOwner(city.id, nil)
			stats.cities = stats.cities + 1
		end
	end

	if CONFIG.NEUTRALIZE_CAMPS then
		local camps = CampData.GetCampsByOwner(player)
		for _, camp in ipairs(camps) do
			CampData.SetOwner(camp.id, nil)
			stats.camps = stats.camps + 1
		end
	end

	if CONFIG.UNCLAIM_PROVINCES then
		local provinces = ProvinceData.GetProvincesByOwner(player)
		for _, province in ipairs(provinces) do
			ClaimSystem.UnclaimProvince(province.id)
			stats.provinces = stats.provinces + 1
		end
	end

	PlayerData.RemovePlayer(player)

	-- Diplomatie-Zustand des Spielers (Beziehungen + Angebote) aufraeumen.
	local okDipl, DiplomacySystem = pcall(function()
		return require(script.Parent:WaitForChild("DiplomacySystem"))
	end)
	if okDipl and DiplomacySystem and DiplomacySystem.ClearPlayer then
		pcall(DiplomacySystem.ClearPlayer, player)
	end

	print(LOG_PREFIX .. " " .. player.Name .. " aufgeräumt: "
		.. stats.armies .. " Armeen, " .. stats.units .. " Units, "
		.. stats.cities .. " Städte, " .. stats.camps .. " Camps, "
		.. stats.provinces .. " Provinzen")
end

Players.PlayerRemoving:Connect(cleanupPlayer)

print(LOG_PREFIX .. " Bereit.")
