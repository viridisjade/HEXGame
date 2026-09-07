--[[
    CombatConfig (ModuleScript)
    Location: ReplicatedStorage > CombatConfig

    Tuning values for the turn-based ("Pokemon style") combat system.
    Lives in ReplicatedStorage so the combat GUI can read the same numbers.

    DAMAGE PIPELINE (see CombatSystem.ExecuteAttack):
        base      = attacker.Attack                    -- Attack  = base damage
        absorbed  = base * (target.Defense / 100)      -- Defense = percent absorption
        actual    = (base - absorbed) * classBonus * (1 - terrainDefense) * flankBonus
        counter   = (absorbed * COUNTER_DAMPENING) * (1 - attacker.Defense / 100)
--]]

local CombatConfig = {}

--------------------------------------------------------------------------------
-- CORE DAMAGE RULES
--------------------------------------------------------------------------------
-- Lowest possible damage of a landed hit (prevents 0-damage stalemates).
CombatConfig.MIN_ACTUAL_DAMAGE = 1

-- NOTE: the LP malus was removed. Units always attack with full power,
-- no matter how few LP they have left.

--------------------------------------------------------------------------------
-- FLANKING (evaluated once when the combat starts)
--------------------------------------------------------------------------------
CombatConfig.FLANK_BONUS_1 = 1.25   -- exactly one supporting army nearby
CombatConfig.FLANK_BONUS_2 = 1.50   -- two or more supporting armies nearby

--------------------------------------------------------------------------------
-- POST COMBAT
--------------------------------------------------------------------------------
CombatConfig.POST_COMBAT_HEAL_BASE = 0.05         -- 5% of MaxLP
CombatConfig.POST_COMBAT_HEAL_MORALE_SCALE = 0.005 -- +0.5% per morale point
CombatConfig.PLUNDER_GOLD_PER_KILL = 5

--------------------------------------------------------------------------------
-- TERRAIN (keys match HexData.soil, see SoilGenerator.SoilType)
-- Reduces the actual damage dealt to the DEFENDING unit.
--------------------------------------------------------------------------------
CombatConfig.TERRAIN_DEFENSE = {
	Forest   = 0.15,
	Rocks    = 0.25,
	Mountain = 0.35,
}

--------------------------------------------------------------------------------
-- CLASS TRIANGLE: Melee > Rider > Spearmen > Melee
-- CLASS_BONUS[attackerClass][defenderClass] -> multiplier on actual damage
--------------------------------------------------------------------------------
CombatConfig.CLASS_BONUS = {
	Melee    = { Melee = 1.0,  Spearmen = 0.75, Rider = 1.25 },
	Spearmen = { Melee = 1.25, Spearmen = 1.0,  Rider = 0.75 },
	Rider    = { Melee = 0.75, Spearmen = 1.25, Rider = 1.0  },
}

--------------------------------------------------------------------------------
-- WILDLIFE (neutral creatures, owner == nil)
-- Simplified fighter: fixed damage, deals no counter and receives no counter.
--------------------------------------------------------------------------------
CombatConfig.WILDLIFE = {
	Name    = "Wildtier",
	LP      = 20,
	Attack  = 10,   -- base damage of a hit
	Defense = 0,    -- percent absorption
	Class   = "Melee",
	-- Strength scaling by distance to the closest city (see CombatSystem).
	SCALE_PER_HEX_DISTANCE = 0.04,  -- +4% damage / LP per hex
	SCALE_MAX              = 2.0,   -- hard cap at 200%
}

return CombatConfig
