
--[[
    UnitSpawner (ModuleScript)
    Ort: ServerScriptService > UnitSpawner
    
    Spawnt eine fertig rekrutierte Unit auf ihrem gespeicherten Spawn-Hex.
--]]

local UnitSpawner = {}

local HexData = require(script.Parent:WaitForChild("HexData"))
local ArmyData = require(script.Parent:WaitForChild("ArmyData"))
local ArmySystem = require(script.Parent:WaitForChild("ArmySystem"))
local ArmySpawner = require(script.Parent:WaitForChild("ArmySpawner"))
local UnitData = require(script.Parent:WaitForChild("UnitData"))
local FogOfWarSystem = require(script.Parent:WaitForChild("FogOfWarSystem"))

function UnitSpawner.CanSpawn(owner, q, r)
	local hex = HexData.GetHex(q, r)
	if not hex then
		return false, "InvalidHex"
	end

	local army = ArmyData.GetArmyOnHex(q, r)
	if not army then
		return true, "CreateArmy"
	end

	-- Wenn eine fremde Army dort steht, blockieren!
	if army.owner ~= owner then
		print("[UnitSpawner] Spawn blockiert: Fremde Army auf dem Hex!")
		return false, "WaitingEnemyArmy"
	end

	-- Wenn die eigene Army voll ist, blockieren!
	if ArmySystem.IsArmyFull(army.id) then
		print("[UnitSpawner] Spawn blockiert: Eigene Army ist voll!")
		return false, "WaitingArmyFull"
	end

	return true, "AddToArmy"
end

function UnitSpawner.Spawn(owner, unitType, q, r)
	print("[UnitSpawner] Versuche Spawn für Owner: " .. tostring(owner.Name) .. " | Unit: " .. tostring(unitType) .. " | Hex: (" .. q .. ", " .. r .. ")")

	local canSpawn, state = UnitSpawner.CanSpawn(owner, q, r)
	if not canSpawn then
		return false, state
	end

	-- ArmySpawner übernimmt die Army-Erstellung und Model-Platzierung
	local armyId, unitId = ArmySpawner.SpawnUnit(owner, unitType, q, r)

	-- NEW: guarantee the combat stats exist on the fresh unit
	-- (attack / defense / morale).
	if unitId then
		UnitData.EnsureCombatStats(unitId)
	end

	if not armyId or not unitId then
		print("[UnitSpawner] FEHLER: ArmySpawner hat keine Army/Unit zurückgegeben!")
		return false, "SpawnFailed"
	end

	-- Zur Kontrolle aus der Datenbank lesen
	local checkArmy = ArmyData.GetArmy(armyId)
	if checkArmy then
		print("[UnitSpawner] ERFOLG: Army " .. tostring(armyId) .. " erstellt. Owner in DB: " .. tostring(checkArmy.owner and checkArmy.owner.Name or "FEHLT"))
	else
		print("[UnitSpawner] WARNUNG: Army ID " .. tostring(armyId) .. " wurde nicht in ArmyData gefunden!")
	end

	-- Fog of War: Neue Unit erweitert die Sicht des Besitzers sofort.
	if owner then
		pcall(FogOfWarSystem.UpdateVision, owner)
	end

	return true, {
		armyId = armyId,
		unitId = unitId,
		mode = state,
	}
end

return UnitSpawner
