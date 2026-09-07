
--[[
    UnitConfig (ModuleScript)
    Ort: ReplicatedStorage > UnitConfig
    
    Definiert alle Unit-Typen mit ihren Stats, Klassen, Fähigkeiten,
    Icons, Model-Namen sowie Industry- und Citizen-Kosten.
--]]

local UnitConfig = {}

UnitConfig.Classes = {
	MELEE = "Melee",
	SPEARMEN = "Spearmen",
	RIDER = "Rider",
}

UnitConfig.Abilities = {
	NONE = nil,
	COLLECTOR = "Collector",
}

UnitConfig.Units = {

	Tribe = {
		Name = "Tribe",
		Model = "Unit_Tribe",
		Icon = "rbxassetid://TRIBE_ICON_ID",
		Class = "Melee",
		Ability = "Collector",
		IndustryCost = 50,
		CitizenCost = 1,
		Stats = {
			LP = 20,
			Attack = 20,    -- base damage of a hit
			Defense = 10,   -- PERCENT damage absorption (0-70)
			Sight = 4,
			Movement = 4,
		},
	},

	StonespearFighter = {
		Name = "Stonespear Fighter",
		Model = "Unit_StonespearFighter",
		Icon = "rbxassetid://STONESPEARFIGHTER_ICON_ID",
		Class = "Spearmen",
		Ability = nil,
		IndustryCost = 80,
		CitizenCost = 1,
		Stats = {
			LP = 24,
			Attack = 25,    -- base damage of a hit
			Defense = 25,   -- PERCENT damage absorption (0-70)
			Sight = 3,
			Movement = 3,
		},
	},

	StoneWarrior = {
		Name = "StoneWarrior",
		Model = "Unit_StoneWarrior",
		Icon = "rbxassetid://STONEWARRIOR_ICON_ID",
		Class = "Melee",
		Ability = nil,
		IndustryCost = 80,
		CitizenCost = 1,
		Stats = {
			LP = 25,
			Attack = 30,    -- base damage of a hit
			Defense = 20,   -- PERCENT damage absorption (0-70)
			Sight = 3,
			Movement = 3,
		},
	},

	Rider = {
		Name = "Rider",
		Model = "Unit_Rider",
		Icon = "rbxassetid://RIDER_ICON_ID",
		Class = "Rider",
		Ability = nil,
		IndustryCost = 120,
		CitizenCost = 2,
		Stats = {
			LP = 30,
			Attack = 35,    -- base damage of a hit
			Defense = 5,    -- PERCENT damage absorption (0-70)
			Sight = 5,
			Movement = 6,
		},
	},
}

function UnitConfig.GetUnit(unitId)
	return UnitConfig.Units[unitId]
end

function UnitConfig.GetAllUnits()
	return UnitConfig.Units
end

function UnitConfig.GetUnitsByClass(className)
	local result = {}
	for id, unit in pairs(UnitConfig.Units) do
		if unit.Class == className then
			result[id] = unit
		end
	end
	return result
end

function UnitConfig.GetUnitsByAbility(abilityName)
	local result = {}
	for id, unit in pairs(UnitConfig.Units) do
		if unit.Ability == abilityName then
			result[id] = unit
		end
	end
	return result
end

function UnitConfig.GetAllClasses()
	local classes = {}
	local seen = {}
	for _, unit in pairs(UnitConfig.Units) do
		if not seen[unit.Class] then
			seen[unit.Class] = true
			table.insert(classes, unit.Class)
		end
	end
	return classes
end

function UnitConfig.GetUnitCount()
	local count = 0
	for _ in pairs(UnitConfig.Units) do
		count = count + 1
	end
	return count
end

--------------------------------------------------------------------------------
-- GLOBAL COMBAT CONSTANTS (turn based combat, see CombatSystem)
--------------------------------------------------------------------------------
-- NOTE: the 70% defense cap lives in CombatSystem / UnitData as a local
-- constant (MAX_DEFENSE_PERCENT) - it is a combat rule, not a unit stat.
UnitConfig.COUNTER_DAMPENING          = 0.5  -- absorbed damage -> counter factor
UnitConfig.TURN_TIMER                 = 10   -- seconds per turn
UnitConfig.DISCONNECT_TURN_TIMER      = 3    -- shortened timer after a disconnect
UnitConfig.MORALE_ROUT_THRESHOLD      = 20   -- below this a rout can happen
UnitConfig.MORALE_LOSS_PER_DEATH      = 15
UnitConfig.MORALE_LOSS_PER_LP_PERCENT = 0.3
UnitConfig.MORALE_GAIN_PER_KILL       = 5
UnitConfig.WILDLIFE_FLEE_LP_RATIO     = 0.5  -- wildlife flees below 50% total LP

return UnitConfig
