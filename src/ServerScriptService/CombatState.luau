--[[
    CombatState (ModuleScript)
    Location: ServerScriptService > CombatState

    Pure in-memory store for every running combat. Holds NO game logic -
    CombatSystem drives the rules, CombatData owns the phase guards.

    combatData layout:
    {
        id              : number,
        phase           : string,   -- see CombatData.Phase
        q, r            : number,   -- the contested hex
        attackerArmyId  : number,
        defenderArmyId  : number,
        attackerOwner   : Player?,  -- nil = wildlife
        defenderOwner   : Player?,
        attackerUnits   : { UnitEntry },
        defenderUnits   : { UnitEntry },
        activeSide      : string?,  -- "attacker" | "defender" (ping pong)
        selectedUnitId  : number?,  -- unit the active player confirmed
        turnTimer       : thread?,  -- selection deadline (task.delay handle)
        turnToken       : number,   -- invalidates stale turn timers
        turnDeadline    : number?,  -- os.clock() timestamp
        morale          : { attacker: number, defender: number },
        flank           : { attacker: number, defender: number },  -- multipliers
        stats           : { attacker: {kills,deaths}, defender: {...} },
        initialUnitCount: { attacker: number, defender: number },
        disconnected    : { attacker: boolean, defender: boolean },
        isWildlife      : boolean,
        wildlifeScale   : number,
        log             : { string },
    }

    UnitEntry = { id, name, icon, class, attack, defense, currentLP, maxLP,
                  alive, armyId, side }
        attack  = base damage of one hit (UnitConfig.Stats.Attack)
        defense = PERCENT damage absorption (capped at 70)

    NOTE: there is no turn order / round counter any more. The two sides simply
    alternate (ping pong), the attacker starts.
--]]

local CombatState = {}

local combats: { [number]: any } = {}
local byArmy: { [number]: number } = {}
local byHex: { [string]: number } = {}
local nextId = 1

local MAX_LOG = 80

local function hexKey(q: number, r: number): string
	return q .. "_" .. r
end

--------------------------------------------------------------------------------
-- Create(data) -> combat
--------------------------------------------------------------------------------
function CombatState.Create(data)
	local id = nextId
	nextId = nextId + 1

	local combat = {
		id = id,
		phase = data.phase or "PENDING",
		q = data.q,
		r = data.r,

		attackerArmyId = data.attackerArmyId,
		defenderArmyId = data.defenderArmyId,
		attackerOwner = data.attackerOwner,
		defenderOwner = data.defenderOwner,

		attackerUnits = data.attackerUnits or {},
		defenderUnits = data.defenderUnits or {},

		-- Ping pong turn state: only the SIDE alternates, never a unit order.
		activeSide = data.activeSide or "attacker",
		selectedUnitId = nil,
		turnTimer = nil,
		turnToken = 0,
		turnDeadline = nil,

		morale = { attacker = 100, defender = 100 },
		flank = { attacker = 1, defender = 1 },
		stats = {
			attacker = { kills = 0, deaths = 0 },
			defender = { kills = 0, deaths = 0 },
		},
		initialUnitCount = {
			attacker = #(data.attackerUnits or {}),
			defender = #(data.defenderUnits or {}),
		},
		disconnected = { attacker = false, defender = false },
		-- Auto resolve: both sides have to agree before the server
		-- fast-forwards the whole fight. [side] = true
		autoResolveVotes = { attacker = false, defender = false },
		autoResolving = false,

		isWildlife = data.isWildlife or false,
		wildlifeScale = data.wildlifeScale or 1,
		log = {},
	}

	combats[id] = combat
	byArmy[combat.attackerArmyId] = id
	if combat.defenderArmyId then
		byArmy[combat.defenderArmyId] = id
	end
	byHex[hexKey(combat.q, combat.r)] = id

	return combat
end

function CombatState.Get(combatId)
	return combats[combatId]
end

function CombatState.GetAll()
	return combats
end

--------------------------------------------------------------------------------
-- GetCombatByArmy(armyId) -> combatId?, combat?
--------------------------------------------------------------------------------
function CombatState.GetCombatByArmy(armyId)
	local id = byArmy[armyId]
	if not id then return nil, nil end
	local combat = combats[id]
	if not combat then
		byArmy[armyId] = nil
		return nil, nil
	end
	return id, combat
end

function CombatState.GetByHex(q, r)
	local id = byHex[hexKey(q, r)]
	return id and combats[id] or nil
end

--------------------------------------------------------------------------------
-- GetActiveCombatsForPlayer(player) -> { combat }
--------------------------------------------------------------------------------
function CombatState.GetActiveCombatsForPlayer(player)
	local result = {}
	if not player then return result end

	for _, combat in pairs(combats) do
		if combat.attackerOwner == player or combat.defenderOwner == player then
			table.insert(result, combat)
		end
	end
	return result
end

--------------------------------------------------------------------------------
-- SideOfPlayer(combat, player) -> "attacker" | "defender" | nil
--------------------------------------------------------------------------------
function CombatState.SideOfPlayer(combat, player)
	if not combat or not player then return nil end
	if combat.attackerOwner == player then return "attacker" end
	if combat.defenderOwner == player then return "defender" end
	return nil
end

function CombatState.AddLog(combat, text)
	if not combat then return end
	table.insert(combat.log, text)
	while #combat.log > MAX_LOG do
		table.remove(combat.log, 1)
	end
end

--------------------------------------------------------------------------------
-- Remove(combatId) - clears the record AND both indexes
--------------------------------------------------------------------------------
function CombatState.Remove(combatId)
	local combat = combats[combatId]
	if not combat then return end

	byArmy[combat.attackerArmyId] = nil
	if combat.defenderArmyId then
		byArmy[combat.defenderArmyId] = nil
	end
	byHex[hexKey(combat.q, combat.r)] = nil
	combats[combatId] = nil
end

function CombatState.ClearAll()
	combats = {}
	byArmy = {}
	byHex = {}
	nextId = 1
	print("[CombatState] Alle Kampf-Daten geloescht.")
end

return CombatState
