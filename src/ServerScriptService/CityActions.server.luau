--[[
    CityActions (Script)
    Ort: ServerScriptService > CityActions
    
    Stadt-Aktionen: Gebäude platzieren, Units rekrutieren,
    Bürger verschieben, Camp zu Stadt ausbauen.
    
    ERSETZT (in Studio LÖSCHEN!):
      - CityBuildHandler      (RequestPlaceBuilding)
      - UnitBuildHandler      (RequestRecruitUnit)
      - CityPopulationHandler (RequestMoveCitizen)
      - CampDataRemoteHandler (RequestFoundCity)
    
    WICHTIG: Nicht zusammen mit den alten Handlern laufen lassen!
    Sonst wird jede Aktion doppelt ausgeführt.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CityData = require(script.Parent:WaitForChild("CityData"))
local ConstructionSystem = require(script.Parent:WaitForChild("ConstructionSystem"))
local CityEconomySystem = require(script.Parent:WaitForChild("CityEconomySystem"))
local CitySystem = require(script.Parent:WaitForChild("CitySystem"))
local FogOfWarSystem = require(script.Parent:WaitForChild("FogOfWarSystem"))

local dataRemotes = ReplicatedStorage:WaitForChild("DataRemotes", 30)

--------------------------------------------------------------------------------
-- CityStatsNotifier integriert (frueher eigenes Script)
--
-- Feuert CityStatsChanged an alle Clients wenn sich Stadt-Daten aendern.
-- Aufrufbar ueber _G.NotifyCityStatsChanged(cityId) aus jedem Server-Script.
-- Alle Clients filtern selbst ob die Stadt ihnen gehoert.
--------------------------------------------------------------------------------
local statsChangedRemote = dataRemotes:FindFirstChild("CityStatsChanged")

_G.NotifyCityStatsChanged = function(cityId)
	if not statsChangedRemote then return end
	statsChangedRemote:FireAllClients(cityId)
end

--------------------------------------------------------------------------------
-- Eingabe-Validierung (Server-Sicherheit)
--------------------------------------------------------------------------------
local function isNumber(value, min, max)
	if type(value) ~= "number" then return false end
	if min and value < min then return false end
	if max and value > max then return false end
	return true
end

local function isString(value, maxLen)
	if type(value) ~= "string" then return false end
	if maxLen and #value > maxLen then return false end
	return #value > 0
end

local function isId(value)
	return isNumber(value, 1) and value % 1 == 0
end

--------------------------------------------------------------------------------
-- Hilfsfunktion
--------------------------------------------------------------------------------
local function onEvent(name, handler)
	local remote = dataRemotes:WaitForChild(name, 5)
	if not remote then
		warn("[CityActions] RemoteEvent fehlt: " .. name)
		return
	end
	remote.OnServerEvent:Connect(handler)
end

--------------------------------------------------------------------------------
-- RequestPlaceBuilding
--------------------------------------------------------------------------------
onEvent("RequestPlaceBuilding", function(player, cityId, buildingType, q, r)
	if not isId(cityId) then return end
	if not isString(buildingType, 50) then return end
	if not isNumber(q, -1000, 1000) or not isNumber(r, -1000, 1000) then return end

	local success, reason = ConstructionSystem.StartConstruction(player, cityId, buildingType, q, r)

	if not success then
		warn("[CityActions] Platzierung abgelehnt: " .. tostring(reason))
	end
end)

--------------------------------------------------------------------------------
-- RequestRecruitUnit
--------------------------------------------------------------------------------
onEvent("RequestRecruitUnit", function(player, cityId, unitType, spawnQ, spawnR)
	if not isId(cityId) then return end
	if not isString(unitType, 50) then return end
	if not isNumber(spawnQ, -1000, 1000) or not isNumber(spawnR, -1000, 1000) then return end

	local success, reason = ConstructionSystem.StartUnitRecruitment(player, cityId, unitType, spawnQ, spawnR)

	if success then
		print("[CityActions] Unit '" .. tostring(unitType) .. "' in die Warteschlange eingetragen")
	else
		warn("[CityActions] Rekrutierung abgelehnt: " .. tostring(reason))
	end
end)

--------------------------------------------------------------------------------
-- RequestMoveCitizen
--------------------------------------------------------------------------------
onEvent("RequestMoveCitizen", function(player, cityId, fromJob, toJob)
	if not isId(cityId) then return end
	if not isString(fromJob, 20) or not isString(toJob, 20) then return end

	local city = CityData.GetCity(cityId)
	if not city then return end

	if city.owner ~= player then
		warn("[CityActions] " .. player.Name .. " besitzt Stadt " .. tostring(cityId) .. " nicht")
		return
	end

	local success, reason = CityEconomySystem.MoveCitizen(cityId, fromJob, toJob)

	if success then
		print("[CityActions] " .. player.Name .. ": " .. tostring(fromJob) .. " -> " .. tostring(toJob))

		-- Nach der manuellen Verschiebung koennen an anderer Stelle noch
		-- freie Plaetze + arbeitslose Buerger uebrig sein (z.B. wenn der
		-- Spieler einen Farmer zu Scientist verschiebt und der frei
		-- gewordene Farmer-Platz durch einen arbeitslosen Buerger gefuellt
		-- werden kann). Das ueberschreibt NICHT die manuelle Wahl des
		-- Spielers, sondern fuellt nur zusaetzliche Luecken.
		CityEconomySystem.AutoAssignWorkers(cityId)
	else
		warn("[CityActions] Verschiebung fehlgeschlagen: " .. tostring(reason))
	end
end)

--------------------------------------------------------------------------------
-- RequestInstantBuy
-- Kauft das erste Item der Bau-/Rekrutierungs-Queue mit Gold sofort frei.
--------------------------------------------------------------------------------
onEvent("RequestInstantBuy", function(player, cityId)
	if not isId(cityId) then return end

	local success, reason = ConstructionSystem.BuyInstantComplete(cityId, player)

	if success then
		print("[CityActions] " .. player.Name .. " hat Bau-Item in Stadt " .. tostring(cityId) .. " sofort freigekauft")
	else
		warn("[CityActions] Sofortkauf abgelehnt: " .. tostring(reason))
	end
end)

--------------------------------------------------------------------------------
-- RequestFoundCity
-- Wandelt ein Camp in eine Stadt um
--------------------------------------------------------------------------------
onEvent("RequestFoundCity", function(player, campId)
	if not isId(campId) then return end

	local cityId, reason = CitySystem.FoundCity(player, campId)

	if cityId then
		print("[CityActions] City gegründet (ID: " .. cityId .. ") von " .. player.Name)
		-- Fog of War: Eine neue Stadt ist eine Sichtquelle (CITY_SIGHT).
		pcall(FogOfWarSystem.UpdateVision, player)
	else
		warn("[CityActions] City-Gründung fehlgeschlagen: " .. tostring(reason))
	end
end)

print("[CityActions] Bereit.")
