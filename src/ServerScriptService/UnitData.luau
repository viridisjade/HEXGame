
--[[
    UnitData (ModuleScript)
    Ort: ServerScriptService > UnitData
    
    Speichert alle gespawnten Units mit ihren aktuellen Daten.
--]]

local UnitData = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UnitConfig = require(ReplicatedStorage:WaitForChild("UnitConfig"))

local units = {}
local nextId = 1

-- Combat rule (was UnitConfig.MAX_DEFENSE_PERCENT): absorption is capped at 70%.
local MAX_DEFENSE_PERCENT = 70

--------------------------------------------------------------------------------
-- CreateUnit(unitType, owner) -> id
--------------------------------------------------------------------------------
function UnitData.CreateUnit(unitType, owner)
	local config = UnitConfig.GetUnit(unitType)
	if not config then
		warn("[UnitData] Unbekannter Unit-Typ: " .. tostring(unitType))
		return nil
	end

	local id = nextId
	nextId = nextId + 1

	units[id] = {
		id = id,
		unitType = unitType,
		owner = owner,
		armyId = nil,
		currentLP = config.Stats.LP,
		maxLP = config.Stats.LP,
		currentMovement = config.Stats.Movement,
		maxMovement = config.Stats.Movement,
		alive = true,

		-- Combat stats (copied from UnitConfig on spawn so they can be buffed).
		-- Attack  = base damage, Defense = PERCENT absorption (capped at 70).
		attack = config.Stats.Attack or 1,
		defense = math.clamp(config.Stats.Defense or 0, 0, MAX_DEFENSE_PERCENT),
		morale = 100,
	}

	return id
end

--------------------------------------------------------------------------------
-- GetUnit(id) -> table or nil
--------------------------------------------------------------------------------
function UnitData.GetUnit(id)
	return units[id]
end

--------------------------------------------------------------------------------
-- GetAllUnits() -> table
--------------------------------------------------------------------------------
function UnitData.GetAllUnits()
	return units
end

--------------------------------------------------------------------------------
-- GetUnitCount() -> number
--------------------------------------------------------------------------------
function UnitData.GetUnitCount()
	local count = 0
	for _ in pairs(units) do
		count = count + 1
	end
	return count
end

--------------------------------------------------------------------------------
-- GetAliveUnitCount() -> number
--------------------------------------------------------------------------------
function UnitData.GetAliveUnitCount()
	local count = 0
	for _, unit in pairs(units) do
		if unit.alive then
			count = count + 1
		end
	end
	return count
end

--------------------------------------------------------------------------------
-- GetUnitsByOwner(owner) -> table
--------------------------------------------------------------------------------
function UnitData.GetUnitsByOwner(owner)
	local result = {}
	for _, unit in pairs(units) do
		if unit.owner == owner and unit.alive then
			table.insert(result, unit)
		end
	end
	return result
end

--------------------------------------------------------------------------------
-- GetUnitsByType(unitType) -> table
--------------------------------------------------------------------------------
function UnitData.GetUnitsByType(unitType)
	local result = {}
	for _, unit in pairs(units) do
		if unit.unitType == unitType and unit.alive then
			table.insert(result, unit)
		end
	end
	return result
end

--------------------------------------------------------------------------------
-- SetArmyId(unitId, armyId)
--------------------------------------------------------------------------------
function UnitData.SetArmyId(unitId, armyId)
	local unit = units[unitId]
	if unit then
		unit.armyId = armyId
	end
end

--------------------------------------------------------------------------------
-- SetOwner(id, owner)
--------------------------------------------------------------------------------
function UnitData.SetOwner(id, owner)
	local unit = units[id]
	if unit then
		unit.owner = owner
	end
end

--------------------------------------------------------------------------------
-- SpendMovement(unitId, amount) -> spent
--------------------------------------------------------------------------------
function UnitData.SpendMovement(unitId, amount)
	local unit = units[unitId]
	if not unit or not unit.alive then return 0 end

	local spent = math.min(unit.currentMovement or 0, amount or 0)
	unit.currentMovement = math.max(0, (unit.currentMovement or 0) - spent)
	return spent
end

--------------------------------------------------------------------------------
-- ResetMovement(unitId)
--------------------------------------------------------------------------------
function UnitData.ResetMovement(unitId)
	local unit = units[unitId]
	if not unit or not unit.alive then return end
	unit.currentMovement = unit.maxMovement or 0
end

--------------------------------------------------------------------------------
-- SetCurrentMovement(unitId, value)
--------------------------------------------------------------------------------
function UnitData.SetCurrentMovement(unitId, value)
	local unit = units[unitId]
	if not unit then return end
	local maxMove = unit.maxMovement or 0
	unit.currentMovement = math.clamp(value or 0, 0, maxMove)
end

--------------------------------------------------------------------------------
-- DamageUnit(id, amount) -> boolean
--------------------------------------------------------------------------------
function UnitData.DamageUnit(id, amount)
	local unit = units[id]
	if not unit or not unit.alive then return false end

	unit.currentLP = math.max(0, unit.currentLP - amount)

	if unit.currentLP <= 0 then
		unit.alive = false
		unit.currentMovement = 0
		return true
	end

	return false
end

--------------------------------------------------------------------------------
-- HealUnit(id, amount)
--------------------------------------------------------------------------------
function UnitData.HealUnit(id, amount)
	local unit = units[id]
	if not unit or not unit.alive then return end
	unit.currentLP = math.min(unit.maxLP, unit.currentLP + amount)
end

--------------------------------------------------------------------------------
-- KillUnit(id)
--------------------------------------------------------------------------------
function UnitData.KillUnit(id)
	local unit = units[id]
	if not unit then return end

	unit.currentLP = 0
	unit.currentMovement = 0
	unit.alive = false
end

--------------------------------------------------------------------------------
-- RemoveUnit(id)
--------------------------------------------------------------------------------
function UnitData.RemoveUnit(id)
	units[id] = nil
end

--------------------------------------------------------------------------------
-- GetUnitStats(id) -> table or nil
--------------------------------------------------------------------------------
function UnitData.GetUnitStats(id)
	local unit = units[id]
	if not unit then return nil end
	local config = UnitConfig.GetUnit(unit.unitType)
	if not config then return nil end
	return config.Stats
end

--------------------------------------------------------------------------------
-- GetUnitConfig(id) -> table or nil
--------------------------------------------------------------------------------
function UnitData.GetUnitConfig(id)
	local unit = units[id]
	if not unit then return nil end
	return UnitConfig.GetUnit(unit.unitType)
end

--------------------------------------------------------------------------------
-- ClearAll()
--------------------------------------------------------------------------------
function UnitData.ClearAll()
	units = {}
	nextId = 1
	print("[UnitData] Alle Unit-Daten gelöscht.")
end

--------------------------------------------------------------------------------
-- PrintStats()
--------------------------------------------------------------------------------
function UnitData.PrintStats()
	print("[UnitData] === Unit Statistik ===")

	local alive = 0
	local dead = 0
	local byType = {}

	for _, unit in pairs(units) do
		if unit.alive then alive = alive + 1 else dead = dead + 1 end
		byType[unit.unitType] = (byType[unit.unitType] or 0) + 1
	end

	print("  Lebend: " .. alive .. " | Tot: " .. dead)
	for unitType, count in pairs(byType) do
		print("    " .. unitType .. ": " .. count)
	end
end

--------------------------------------------------------------------------------
-- EnsureCombatStats(unitId) -> unit?
-- Back-fills the combat stats (attack / defense / morale) for units that were
-- created before the stat cleanup or by a system that bypassed CreateUnit.
--------------------------------------------------------------------------------
function UnitData.EnsureCombatStats(unitId)
	local unit = units[unitId]
	if not unit then return nil end

	local config = UnitConfig.GetUnit(unit.unitType)
	if not config then return unit end

	unit.attack = unit.attack or config.Stats.Attack or 1
	unit.defense = math.clamp(unit.defense or config.Stats.Defense or 0, 0, MAX_DEFENSE_PERCENT)
	unit.morale = unit.morale or 100
	return unit
end

--------------------------------------------------------------------------------
-- MORALE (per unit, only meaningful while a combat is running)
--------------------------------------------------------------------------------
function UnitData.GetMorale(unitId)
	local unit = units[unitId]
	return unit and (unit.morale or 100) or 0
end

function UnitData.SetMorale(unitId, value)
	local unit = units[unitId]
	if not unit then return false end
	unit.morale = math.clamp(value or 100, 0, 100)
	return true
end

return UnitData
