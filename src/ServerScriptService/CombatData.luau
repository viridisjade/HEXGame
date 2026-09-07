--[[
    CombatData (ModuleScript)
    Location: ServerScriptService > CombatData

    Phase definitions + transition guard for the combat state machine.
    The actual records live in CombatState; this module is the safety layer
    that every other system talks to (ArmySystem, MovementSystem, ...).

    STATE MACHINE
        PENDING        -> ACTIVE          (first turn starts)
        ACTIVE         -> ROUTING         (morale break / wildlife flees)
        ACTIVE         -> AUTO_RESOLVING  (both players agreed to auto resolve)
        ACTIVE         -> ENDED           (one side wiped out)
        ROUTING        -> ENDED
        AUTO_RESOLVING -> ENDED
        ENDED          -> CLEANED         (record about to be removed)

    Any other transition is rejected with a warning. This is what makes
    "ghost combats" impossible - a half dead record can never become ACTIVE
    again, and StartCombat refuses to reuse a hex that still holds a record.
--]]

local CombatState = require(script.Parent:WaitForChild("CombatState"))

local CombatData = {}

--------------------------------------------------------------------------------
-- PHASES
--------------------------------------------------------------------------------
CombatData.Phase = {
	PENDING        = "PENDING",
	ACTIVE         = "ACTIVE",
	ROUTING        = "ROUTING",
	AUTO_RESOLVING = "AUTO_RESOLVING",
	ENDED          = "ENDED",
	CLEANED        = "CLEANED",
}

local ALLOWED = {
	PENDING        = { ACTIVE = true, ENDED = true },
	ACTIVE         = { ROUTING = true, AUTO_RESOLVING = true, ENDED = true },
	ROUTING        = { ENDED = true },
	AUTO_RESOLVING = { ENDED = true },
	ENDED          = { CLEANED = true },
	CLEANED        = {},
}

--------------------------------------------------------------------------------
-- Transition(combatId, expectedPhase, newPhase) -> boolean
-- Guarded state change. Returns false (and warns) on any illegal move.
--------------------------------------------------------------------------------
function CombatData.Transition(combatId, expectedPhase, newPhase)
	local combat = CombatState.Get(combatId)
	if not combat then
		warn("[CombatData] Transition: Kampf " .. tostring(combatId) .. " existiert nicht")
		return false
	end

	if expectedPhase ~= nil and combat.phase ~= expectedPhase then
		warn(("[CombatData] Transition abgelehnt: Kampf %s ist '%s', erwartet '%s'")
			:format(tostring(combatId), tostring(combat.phase), tostring(expectedPhase)))
		return false
	end

	local allowedFromHere = ALLOWED[combat.phase]
	if not allowedFromHere or not allowedFromHere[newPhase] then
		warn(("[CombatData] Transition abgelehnt: '%s' -> '%s' ist nicht erlaubt")
			:format(tostring(combat.phase), tostring(newPhase)))
		return false
	end

	combat.phase = newPhase
	return true
end

function CombatData.GetPhase(combatId)
	local combat = CombatState.Get(combatId)
	return combat and combat.phase or nil
end

--------------------------------------------------------------------------------
-- LOOKUPS (thin wrappers so callers never touch CombatState directly)
--------------------------------------------------------------------------------
function CombatData.Get(combatId)
	return CombatState.Get(combatId)
end

function CombatData.GetAll()
	return CombatState.GetAll()
end

-- Returns the combat ID (not the record) so callers can guard cheaply.
function CombatData.GetCombatByArmy(armyId)
	local id = CombatState.GetCombatByArmy(armyId)
	return id
end

function CombatData.GetByArmy(armyId)
	local _, combat = CombatState.GetCombatByArmy(armyId)
	return combat
end

function CombatData.GetByHex(q, r)
	return CombatState.GetByHex(q, r)
end

--------------------------------------------------------------------------------
-- IsInCombat(armyId) -> boolean
-- True while the army is bound to a combat that is not finished yet.
-- Used by ArmySystem / MovementSystem / ConstructionSystem to block actions.
--------------------------------------------------------------------------------
function CombatData.IsInCombat(armyId)
	local _, combat = CombatState.GetCombatByArmy(armyId)
	if not combat then return false end
	return combat.phase ~= CombatData.Phase.ENDED
		and combat.phase ~= CombatData.Phase.CLEANED
end

-- True when the hex itself is contested (blocks spawning reinforcements).
function CombatData.IsHexContested(q, r)
	local combat = CombatState.GetByHex(q, r)
	if not combat then return false end
	return combat.phase ~= CombatData.Phase.ENDED
		and combat.phase ~= CombatData.Phase.CLEANED
end

function CombatData.AddLog(combatId, text)
	CombatState.AddLog(CombatState.Get(combatId), text)
end

function CombatData.Remove(combatId)
	CombatState.Remove(combatId)
end

function CombatData.ClearAll()
	CombatState.ClearAll()
end

return CombatData
