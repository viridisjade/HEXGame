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

local dataRemotes = ReplicatedStorage:WaitForChild("DataRemotes", 30)

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
	else
		warn("[WorldActions] Camp-Bau fehlgeschlagen: " .. tostring(reason))
	end
end)

print("[WorldActions] Bereit.")