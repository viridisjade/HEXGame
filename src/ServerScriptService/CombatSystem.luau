--[[
    CombatSystem (ModuleScript)
    Location: ServerScriptService > CombatSystem

    Turn based ("Pokemon style") combat.

    PING PONG FLOW
        The two sides simply alternate. The ATTACKER (the army that walked onto
        the enemy hex) always strikes first.

        StartCombat()  -> snapshot both armies, flanking, activeSide = "attacker"
        StartTurn()    -> broadcast "side X is up" + 10s selection timer
        SelectUnit()   -> player marks ANY of his living units (golden outline)
        SelectTarget() -> IMMEDIATELY resolves: timer cancelled, ExecuteAttack,
                          victory/morale check, side flips, next turn starts.
                          There is NO waiting for the timer.
        AutoAttack()   -> timer ran out: strongest own unit hits weakest enemy,
                          then the side flips as well.
        EndCombat()    -> loot, heal, winner advances, guarded cleanup

        There is NO turn order, NO combat round and NO "once per unit" limit:
        the same unit may attack every single turn.

    DAMAGE (see CombatConfig)
        Attack  = base damage of one hit  (UnitConfig.Stats.Attack)
        Defense = PERCENT absorption      (UnitConfig.Stats.Defense, capped 70)
        base     = Attack              (no LP malus: full power at any LP)
        absorbed = base * (Defense / 100)
        actual   = (base - absorbed) * classBonus * (1 - terrain) * flank
        counter  = absorbed * COUNTER_DAMPENING * (1 - attacker.Defense / 100)
        The counter never triggers another counter.

    Combats run ASYNCHRONOUS to the 30s game round - RoundSystem no longer
    drives them.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage:WaitForChild("CombatConfig"))
local UnitConfig = require(ReplicatedStorage:WaitForChild("UnitConfig"))

local CombatState = require(script.Parent:WaitForChild("CombatState"))
local CombatData = require(script.Parent:WaitForChild("CombatData"))
local HexData = require(script.Parent:WaitForChild("HexData"))
local HexUtils = require(script.Parent:WaitForChild("HexUtils"))
local ArmyData = require(script.Parent:WaitForChild("ArmyData"))
local UnitData = require(script.Parent:WaitForChild("UnitData"))
local ArmySystem = require(script.Parent:WaitForChild("ArmySystem"))
local ArmyStats = require(script.Parent:WaitForChild("ArmyStats"))
local ArmySpawner = require(script.Parent:WaitForChild("ArmySpawner"))
local ArmyModelMover = require(script.Parent:WaitForChild("ArmyModelMover"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local DiplomacySystem = require(script.Parent:WaitForChild("DiplomacySystem"))
local CityData = require(script.Parent:WaitForChild("CityData"))
local FogOfWarSystem = require(script.Parent:WaitForChild("FogOfWarSystem"))
local PointSystem = require(script.Parent:WaitForChild("PointSystem"))
local VictorySystem = require(script.Parent:WaitForChild("VictorySystem"))
local VictoryConfig = require(ReplicatedStorage:WaitForChild("VictoryConfig"))

-- Combat rule (was UnitConfig.MAX_DEFENSE_PERCENT): absorption is capped at 70%.
local MAX_DEFENSE_PERCENT = 70

-- Lazy tech access (avoids require cycles).
local _techSystem
local function Tech()
	if not _techSystem then
		local ok, mod = pcall(function()
			return require(script.Parent:WaitForChild("TechTreeSystem"))
		end)
		_techSystem = ok and mod or false
	end
	return _techSystem or nil
end

--------------------------------------------------------------------------------
-- TECH HELPERS
--------------------------------------------------------------------------------
-- Fortification: the defender gets +20% damage reduction when the
-- contested hex carries one of HIS buildings (city or camp).
local function fortificationBonus(combat, defenderSide)
	local tech = Tech()
	if not tech then return 0 end

	local owner = (defenderSide == "attacker")
		and combat.attackerOwner or combat.defenderOwner
	if not owner then return 0 end

	local bonus = tech.GetSpecial(owner, "FortificationBonus")
	if bonus <= 0 then return 0 end

	local hex = HexData.GetHex(combat.q, combat.r)
	if not hex or not hex.building then return 0 end
	if hex.owner ~= owner then return 0 end

	return bonus
end

-- Siege Engineering: +50% damage when the target hex holds a building.
local function siegeBonus(combat, attackerSide)
	local tech = Tech()
	if not tech then return 1 end

	local owner = (attackerSide == "attacker")
		and combat.attackerOwner or combat.defenderOwner
	if not owner then return 1 end

	local bonus = tech.GetSpecial(owner, "SiegeBonus")
	if bonus <= 0 then return 1 end

	local hex = HexData.GetHex(combat.q, combat.r)
	if not hex or not hex.building then return 1 end

	return 1 + bonus
end

local CombatSystem = {}

local Phase = CombatData.Phase

local dataRemotes = ReplicatedStorage:WaitForChild("DataRemotes", 30)

local function remote(name)
	return dataRemotes and dataRemotes:FindFirstChild(name) or nil
end

local function rootRemote(name)
	return ReplicatedStorage:FindFirstChild(name)
end

--------------------------------------------------------------------------------
-- SMALL HELPERS
--------------------------------------------------------------------------------
local function otherSide(side: string): string
	return side == "attacker" and "defender" or "attacker"
end

local function unitsOf(combat, side)
	return side == "attacker" and combat.attackerUnits or combat.defenderUnits
end

local function ownerOf(combat, side)
	return side == "attacker" and combat.attackerOwner or combat.defenderOwner
end

local function armyIdOf(combat, side)
	return side == "attacker" and combat.attackerArmyId or combat.defenderArmyId
end

local function findEntry(combat, unitId)
	for _, side in ipairs({ "attacker", "defender" }) do
		for _, entry in ipairs(unitsOf(combat, side)) do
			if entry.id == unitId then
				return entry, side
			end
		end
	end
	return nil, nil
end

-- Pull live LP / alive flags out of UnitData into the snapshot entries.
local function refreshUnits(combat)
	for _, side in ipairs({ "attacker", "defender" }) do
		for _, entry in ipairs(unitsOf(combat, side)) do
			local unit = UnitData.GetUnit(entry.id)
			if unit then
				entry.currentLP = unit.currentLP
				entry.maxLP = unit.maxLP
				entry.alive = unit.alive
			else
				entry.currentLP = 0
				entry.alive = false
			end
		end
	end
end

local function livingUnits(combat, side)
	local result = {}
	for _, entry in ipairs(unitsOf(combat, side)) do
		if entry.alive then
			table.insert(result, entry)
		end
	end
	return result
end

--------------------------------------------------------------------------------
-- buildUnitEntries(armyId, side) -> { UnitEntry }
--------------------------------------------------------------------------------
local function buildUnitEntries(armyId, side, wildlifeScale)
	local army = ArmyData.GetArmy(armyId)
	local entries = {}
	if not army then return entries end

	for _, unitId in ipairs(army.units or {}) do
		local unit = UnitData.GetUnit(unitId)
		if unit and unit.alive then
			local cfg = UnitConfig.GetUnit(unit.unitType)
			local wl = CombatConfig.WILDLIFE
			local scale = wildlifeScale or 1

			table.insert(entries, {
				id = unit.id,
				name = cfg and cfg.Name or wl.Name,
				icon = cfg and cfg.Icon or "",
				class = cfg and cfg.Class or wl.Class,
				-- Combat stats: instance value first, config as fallback.
				-- attack = base damage, defense = PERCENT absorption.
				attack = math.floor((unit.attack
					or (cfg and cfg.Stats.Attack)
					or wl.Attack) * (cfg and 1 or scale)),
				defense = math.clamp(unit.defense
					or (cfg and cfg.Stats.Defense)
					or wl.Defense, 0, MAX_DEFENSE_PERCENT),
				currentLP = unit.currentLP,
				maxLP = unit.maxLP,
				alive = true,
				armyId = armyId,
				side = side,
			})
		end
	end
	return entries
end

--------------------------------------------------------------------------------
-- SNAPSHOT / BROADCASTS
--------------------------------------------------------------------------------
local function sideSnapshot(combat, side)
	local owner = ownerOf(combat, side)
	local units = {}
	for _, entry in ipairs(unitsOf(combat, side)) do
		table.insert(units, {
			id = entry.id,
			name = entry.name,
			icon = entry.icon,
			class = entry.class,
			currentLP = entry.currentLP,
			maxLP = entry.maxLP,
			alive = entry.alive,
			attack = entry.attack,
			defense = entry.defense,
		})
	end
	return {
		armyId = armyIdOf(combat, side),
		-- UserId lets the client decide on its own which side it is looking at
		-- (player perspective view). nil = wildlife.
		ownerId = owner and owner.UserId or nil,
		playerName = owner and owner.Name or CombatConfig.WILDLIFE.Name,
		morale = combat.morale[side],
		units = units,
	}
end

local function buildSnapshot(combat)
	refreshUnits(combat)
	return {
		combatId = combat.id,
		phase = combat.phase,
		hexQ = combat.q,
		hexR = combat.r,
		isWildlife = combat.isWildlife,
		-- Top level owner ids: the GUI maps "my units" to the player frame.
		attackerOwnerId = combat.attackerOwner and combat.attackerOwner.UserId or nil,
		defenderOwnerId = combat.defenderOwner and combat.defenderOwner.UserId or nil,
		-- Ping pong: only the SIDE is fixed, the acting unit is free choice.
		activeSide = combat.activeSide,
		selectedUnitId = combat.selectedUnitId,
		flank = combat.flank,
		attacker = sideSnapshot(combat, "attacker"),
		defender = sideSnapshot(combat, "defender"),
		log = combat.log,
	}
end

-- Sends one payload per participating player, each tagged with their own side.
local function fireBoth(combat, remoteName, payload, perSide)
	local rem = remote(remoteName)
	if not rem then
		warn("[CombatSystem] Remote fehlt: " .. remoteName)
		return
	end

	for _, side in ipairs({ "attacker", "defender" }) do
		local owner = ownerOf(combat, side)
		if owner then
			local copy = table.clone(payload)
			copy.mySide = side
			if perSide then
				perSide(copy, side)
			end
			local ok, err = pcall(function()
				rem:FireClient(owner, copy)
			end)
			if not ok then
				warn("[CombatSystem] " .. remoteName .. " an " .. owner.Name .. " fehlgeschlagen: " .. tostring(err))
			end
		end
	end
end

CombatSystem.BroadcastSnapshot = function(combat, remoteName)
	fireBoth(combat, remoteName, buildSnapshot(combat))
end

--------------------------------------------------------------------------------
-- CalculateFlanking(combat)
-- Counts friendly armies on the six neighbours of the contested hex.
--------------------------------------------------------------------------------
function CombatSystem.CalculateFlanking(combat)
	local function countSupport(side)
		local owner = ownerOf(combat, side)
		if not owner then return 1 end

		local ownArmyId = armyIdOf(combat, side)
		local support = 0

		for _, n in ipairs(HexUtils.getNeighbors(combat.q, combat.r)) do
			local army = ArmyData.GetArmyOnHex(n.q, n.r)
			if army and army.id ~= ownArmyId and army.owner == owner then
				support += 1
			end
		end

		if support >= 2 then return CombatConfig.FLANK_BONUS_2 end
		if support == 1 then return CombatConfig.FLANK_BONUS_1 end
		return 1
	end

	-- Per spec only the attacking side profits from flanking support.
	combat.flank.attacker = countSupport("attacker")
	combat.flank.defender = 1

	if combat.flank.attacker > 1 then
		CombatState.AddLog(combat, ("Flankierung! Angreifer kaempft mit x%.2f")
			:format(combat.flank.attacker))
	end
end

--------------------------------------------------------------------------------
-- WILDLIFE SCALING: further away from any city == stronger creatures
--------------------------------------------------------------------------------
local function calculateWildlifeScale(q, r)
	local closest = math.huge
	for _, city in pairs(CityData.GetAllCities()) do
		local d = HexUtils.getDistance(q, r, city.q, city.r)
		if d < closest then closest = d end
	end
	if closest == math.huge then closest = 10 end

	local scale = 1 + closest * CombatConfig.WILDLIFE.SCALE_PER_HEX_DISTANCE
	return math.clamp(scale, 1, CombatConfig.WILDLIFE.SCALE_MAX)
end

--------------------------------------------------------------------------------
-- TURN TIMER
-- The timer is ONLY a selection deadline. Any resolved attack cancels it
-- immediately (cancelTurnTimer), so the fight never waits for it.
--------------------------------------------------------------------------------
local function cancelTurnTimer(combat)
	-- Token bump invalidates every timer callback that is already queued.
	combat.turnToken += 1

	local thread = combat.turnTimer
	combat.turnTimer = nil
	combat.turnDeadline = nil

	if thread and coroutine.status(thread) == "suspended" then
		pcall(task.cancel, thread)
	end
end

local function startTurnTimer(combat)
	cancelTurnTimer(combat)
	local token = combat.turnToken

	local side = combat.activeSide
	-- Hard fallbacks: a nil constant must never break the timer, otherwise the
	-- combat would stay ACTIVE forever and lock both armies permanently.
	local limit = tonumber(UnitConfig.TURN_TIMER) or 10
	if side and combat.disconnected[side] then
		limit = tonumber(UnitConfig.DISCONNECT_TURN_TIMER) or 3
	end

	combat.turnDeadline = os.clock() + limit
	combat.turnTimer = task.delay(limit, function()
		local live = CombatState.Get(combat.id)
		if not live then return end
		if live.turnToken ~= token then return end   -- turn already resolved
		if live.phase ~= Phase.ACTIVE then return end
		CombatSystem.AutoAttack(live)
	end)

	return limit
end

--------------------------------------------------------------------------------
-- StartTurn(combat)
-- Announces whose turn it is. No unit is pre-selected: the active player may
-- pick ANY of his living units (and may reuse the same one every turn).
--------------------------------------------------------------------------------
function CombatSystem.StartTurn(combat)
	if combat.phase ~= Phase.ACTIVE then return end

	refreshUnits(combat)

	local side = combat.activeSide or "attacker"
	combat.activeSide = side
	combat.selectedUnitId = nil

	-- A side without living units means the fight is already decided.
	if #livingUnits(combat, side) == 0 or #livingUnits(combat, otherSide(side)) == 0 then
		CombatSystem.CheckVictory(combat)
		return
	end

	local timeLimit = startTurnTimer(combat) or 10

	local payload = {
		combatId = combat.id,
		activeSide = side,
		timeLimit = timeLimit,
		snapshot = buildSnapshot(combat),
	}

	fireBoth(combat, "CombatTurnStart", payload, function(copy, playerSide)
		copy.isMyTurn = (playerSide == side)
	end)

	-- Wildlife has no player: it resolves its turn on its own after a beat.
	if ownerOf(combat, side) == nil then
		local token = combat.turnToken
		task.delay(1, function()
			local live = CombatState.Get(combat.id)
			if live and live.phase == Phase.ACTIVE and live.turnToken == token then
				CombatSystem.ProcessWildlifeCombat(live.id)
			end
		end)
	end
end

--------------------------------------------------------------------------------
-- NextTurn(combat) - flip the side and immediately announce the new turn
--------------------------------------------------------------------------------
function CombatSystem.NextTurn(combat)
	if combat.phase ~= Phase.ACTIVE then return end
	combat.activeSide = otherSide(combat.activeSide or "attacker")
	CombatSystem.StartTurn(combat)
end

--------------------------------------------------------------------------------
-- StartCombat(attackerArmyId, defenderArmyId, q, r) -> combatId?, reason?
--------------------------------------------------------------------------------
function CombatSystem.StartCombat(attackerArmyId, defenderArmyId, q, r)
	local attackerArmy = ArmyData.GetArmy(attackerArmyId)
	local defenderArmy = ArmyData.GetArmy(defenderArmyId)

	if not attackerArmy or not defenderArmy then
		return nil, "Armee nicht gefunden"
	end

	local isWildlife = (defenderArmy.owner == nil)

	-- Allianz-Mitglieder kaempfen nie gegeneinander. (Diplomacy: AreInAlliance
	-- gilt nur fuer "Alliance"; "Neutral"/"War" duerfen kaempfen. Wildlife
	-- (owner == nil) ist nie Allianz-Mitglied.)
	if not isWildlife and type(DiplomacySystem.AreInAlliance) == "function"
		and attackerArmy.owner and defenderArmy.owner
		and DiplomacySystem.AreInAlliance(attackerArmy.owner, defenderArmy.owner) then
		return nil, "Allianz - kein Angriff"
	end

	-- Guard: never stack two combats on the same hex or army.
	local existing = CombatState.GetByHex(q, r)
	if existing then
		if existing.phase ~= Phase.ENDED and existing.phase ~= Phase.CLEANED then
			return existing.id, nil
		end
		warn("[CombatSystem] Veralteter Kampf " .. existing.id .. " auf ("
			.. q .. ", " .. r .. ") wird bereinigt")
		CombatState.Remove(existing.id)
	end

	if CombatData.IsInCombat(attackerArmyId) or CombatData.IsInCombat(defenderArmyId) then
		return nil, "Armee kaempft bereits"
	end

	local wildlifeScale = isWildlife and calculateWildlifeScale(q, r) or 1

	local combat = CombatState.Create({
		q = q, r = r,
		attackerArmyId = attackerArmyId,
		defenderArmyId = defenderArmyId,
		attackerOwner = attackerArmy.owner,
		defenderOwner = defenderArmy.owner,
		attackerUnits = buildUnitEntries(attackerArmyId, "attacker", 1),
		defenderUnits = buildUnitEntries(defenderArmyId, "defender", wildlifeScale),
		isWildlife = isWildlife,
		wildlifeScale = wildlifeScale,
		phase = Phase.PENDING,
	})

	if #combat.attackerUnits == 0 or #combat.defenderUnits == 0 then
		CombatState.Remove(combat.id)
		return nil, "Leere Armee"
	end

	CombatSystem.CalculateFlanking(combat)
	CombatState.AddLog(combat, "Kampf beginnt auf (" .. q .. ", " .. r .. ")")

	if not CombatData.Transition(combat.id, Phase.PENDING, Phase.ACTIVE) then
		CombatState.Remove(combat.id)
		return nil, "State-Transition fehlgeschlagen"
	end

	-- Ping pong: the attacker (who walked into the hex) always strikes first.
	combat.activeSide = "attacker"

	fireBoth(combat, "CombatStart", buildSnapshot(combat))

	print(("[CombatSystem] Kampf %d gestartet: Army %d vs Army %d auf (%d, %d)")
		:format(combat.id, attackerArmyId, defenderArmyId, q, r))

	local turnOk, turnErr = pcall(CombatSystem.StartTurn, combat)
	if not turnOk then
		warn("[CombatSystem] StartTurn fehlgeschlagen - Kampf wird abgebrochen: " .. tostring(turnErr))
		-- Guarantee: no ACTIVE zombie combat may survive, otherwise
		-- CombatData.IsInCombat() would block both armies forever.
		pcall(function()
			CombatData.Transition(combat.id, nil, Phase.ENDED)
			CombatData.Transition(combat.id, Phase.ENDED, Phase.CLEANED)
		end)
		CombatState.Remove(combat.id)
		return nil, "Kampfstart fehlgeschlagen"
	end

	return combat.id, nil
end

--------------------------------------------------------------------------------
-- DAMAGE MATH
-- (No LP malus any more: a unit at 1 LP hits exactly as hard as a
--  fresh one. Fights are faster and more lethal.)
--------------------------------------------------------------------------------
local function classBonus(attackerClass, defenderClass)
	local row = CombatConfig.CLASS_BONUS[attackerClass]
	if not row then return 1 end
	return row[defenderClass] or 1
end

local function terrainDefense(q, r)
	local hex = HexData.GetHex(q, r)
	if not hex or not hex.soil then return 0 end
	return CombatConfig.TERRAIN_DEFENSE[hex.soil] or 0
end

--------------------------------------------------------------------------------
-- ExecuteAttack(combat, attackerEntry, targetEntry) -> result
--------------------------------------------------------------------------------
function CombatSystem.ExecuteAttack(combat, attackerEntry, targetEntry)
	refreshUnits(combat)

	local attackerSide = attackerEntry.side
	local defenderSide = targetEntry.side

	-- 1) base damage - ALWAYS full Attack, no LP malus any more
	local atkDamage = attackerEntry.attack

	-- 2) percentage absorption of the DEFENDER (Defense is a percent value)
	local defDef = math.min(targetEntry.defense, MAX_DEFENSE_PERCENT)
	local absorbed = atkDamage * (defDef / 100)

	-- 3) what gets through, modified by class triangle, terrain and flanking
	local actual = atkDamage - absorbed
	actual = actual * classBonus(attackerEntry.class, targetEntry.class)
	actual = actual * (1 - terrainDefense(combat.q, combat.r))
	actual = actual * (combat.flank[attackerSide] or 1)
	-- TECH Fortification: defender takes less damage on his own building hex.
	actual = actual * (1 - fortificationBonus(combat, defenderSide))
	-- TECH Siege Engineering: attacker hits buildings harder.
	actual = actual * siegeBonus(combat, attackerSide)

	local actualDamage = math.max(CombatConfig.MIN_ACTUAL_DAMAGE, math.floor(actual))

	-- 4) apply the hit to the DEFENDER first. A dead defender can never
	--    strike back, so the counter is only computed when he survived.
	local targetKilled = UnitData.DamageUnit(targetEntry.id, actualDamage)

	-- 5) counter: dampened absorption, reduced by the ATTACKER's own defense.
	--    Only while the defender is ALIVE - a killed unit cannot retaliate
	--    (this used to cause double KOs when both units were at 1 LP).
	--    Wildlife never counters and never receives a counter.
	--    Minimum of 1 whenever something was absorbed: math.floor used
	--    to round small counters (e.g. 2 absorbed -> floor(0.9) = 0)
	--    down to zero, silently cancelling the counter mechanic.
	local counterDamage = 0
	local attackerKilled = false
	if not targetKilled and not combat.isWildlife and absorbed > 0 then
		local counterRaw = absorbed * UnitConfig.COUNTER_DAMPENING
		local atkDef = math.min(attackerEntry.defense, MAX_DEFENSE_PERCENT)
		counterDamage = math.max(1, math.floor(counterRaw * (1 - atkDef / 100)))
		attackerKilled = UnitData.DamageUnit(attackerEntry.id, counterDamage)
	end

	refreshUnits(combat)

	if targetKilled then
		combat.stats[defenderSide].deaths += 1
		combat.stats[attackerSide].kills += 1
	end
	if attackerKilled then
		combat.stats[attackerSide].deaths += 1
		combat.stats[defenderSide].kills += 1
	end

	local result = {
		attackerId = attackerEntry.id,
		attackerName = attackerEntry.name,
		attackerSide = attackerSide,
		targetId = targetEntry.id,
		targetName = targetEntry.name,
		targetSide = defenderSide,
		baseDamage = math.floor(atkDamage),
		absorbed = math.floor(absorbed),
		actualDamage = actualDamage,
		counterDamage = counterDamage,
		targetLPAfter = targetEntry.currentLP,
		attackerLPAfter = attackerEntry.currentLP,
		targetKilled = targetKilled,
		attackerKilled = attackerKilled,
		classBonus = classBonus(attackerEntry.class, targetEntry.class),
		flank = combat.flank[attackerSide] or 1,
	}

	CombatState.AddLog(combat, ("%s trifft %s: %d Schaden (%d absorbiert)")
		:format(attackerEntry.name, targetEntry.name, actualDamage, math.floor(absorbed)))
	if counterDamage > 0 then
		CombatState.AddLog(combat, ("Konter: %s nimmt %d Schaden")
			:format(attackerEntry.name, counterDamage))
	end
	-- No counter log entry at all when the defender died: he never
	-- retaliated, so the log stays clean (no misleading 'counter 0').
	if targetKilled then
		CombatState.AddLog(combat, targetEntry.name .. " ist gefallen!")
	end
	if attackerKilled then
		CombatState.AddLog(combat, attackerEntry.name .. " faellt durch den Konter!")
	end

	-- While auto resolving we stay silent: dozens of hits are computed in
	-- one frame and the clients would be flooded. They receive the full
	-- log with the CombatEnd payload instead.
	if not combat.autoResolving then
		fireBoth(combat, "CombatAttackResult", {
			combatId = combat.id,
			result = result,
			snapshot = buildSnapshot(combat),
		})
	end

	return result
end

--------------------------------------------------------------------------------
-- TARGET PICKERS (auto attack)
--------------------------------------------------------------------------------
local function weakestEnemy(combat, side)
	local best, bestLP = nil, math.huge
	for _, entry in ipairs(livingUnits(combat, otherSide(side))) do
		if entry.currentLP < bestLP then
			bestLP = entry.currentLP
			best = entry
		end
	end
	return best
end

local function strongestOwn(combat, side)
	local best, bestPower = nil, -1
	for _, entry in ipairs(livingUnits(combat, side)) do
		local power = entry.attack * (entry.currentLP / math.max(1, entry.maxLP))
		if power > bestPower then
			bestPower = power
			best = entry
		end
	end
	return best
end

--------------------------------------------------------------------------------
-- SelectUnit(combatId, player, unitId) -> boolean, reason
--------------------------------------------------------------------------------
function CombatSystem.SelectUnit(combatId, player, unitId)
	local combat = CombatState.Get(combatId)
	if not combat or combat.phase ~= Phase.ACTIVE then
		return false, "Kampf laeuft nicht"
	end

	local side = CombatState.SideOfPlayer(combat, player)
	if not side then return false, "Nicht beteiligt" end
	if combat.activeSide ~= side then
		return false, "Nicht dein Zug"
	end

	-- Ping pong: ANY living unit of the active side may act, and the same unit
	-- may be picked again every single turn.
	local entry, entrySide = findEntry(combat, unitId)
	if not entry or not entry.alive then return false, "Einheit nicht verfuegbar" end
	if entrySide ~= side then return false, "Das ist keine deiner Einheiten" end

	combat.selectedUnitId = unitId

	fireBoth(combat, "CombatUnitSelected", {
		combatId = combat.id,
		unitId = unitId,
		side = side,
		playerName = player and player.Name or "?",
	})

	return true, nil
end

--------------------------------------------------------------------------------
-- SelectTarget(combatId, player, targetUnitId) -> boolean, reason
--------------------------------------------------------------------------------
function CombatSystem.SelectTarget(combatId, player, targetUnitId)
	local combat = CombatState.Get(combatId)
	if not combat or combat.phase ~= Phase.ACTIVE then
		return false, "Kampf laeuft nicht"
	end

	local side = CombatState.SideOfPlayer(combat, player)
	if not side then return false, "Nicht beteiligt" end
	if combat.activeSide ~= side then
		return false, "Nicht dein Zug"
	end

	-- Attacker = the confirmed unit. If the player skipped the confirmation
	-- (clicked an enemy right away) the strongest own unit steps in.
	local attackerEntry = combat.selectedUnitId and findEntry(combat, combat.selectedUnitId) or nil
	if not attackerEntry or not attackerEntry.alive or attackerEntry.side ~= side then
		attackerEntry = strongestOwn(combat, side)
	end
	if not attackerEntry then
		return false, "Keine einsatzbereite Einheit"
	end

	local targetEntry, targetSide = findEntry(combat, targetUnitId)
	if not targetEntry or not targetEntry.alive then
		return false, "Ziel nicht verfuegbar"
	end
	if targetSide == side then
		return false, "Eigene Einheit kann nicht angegriffen werden"
	end

	-- IMMEDIATE resolution: stop the selection timer, hit, then hand over.
	cancelTurnTimer(combat)

	CombatSystem.ExecuteAttack(combat, attackerEntry, targetEntry)
	CombatSystem.AfterTurn(combat)
	return true, nil
end

--------------------------------------------------------------------------------
-- AutoAttack(combat) - timeout, disconnect or AI fallback
--------------------------------------------------------------------------------
function CombatSystem.AutoAttack(combat)
	if not combat or combat.phase ~= Phase.ACTIVE then return end
	if not combat.activeSide then return end

	local side = combat.activeSide
	refreshUnits(combat)

	-- Already confirmed unit wins, otherwise the strongest own unit attacks.
	local attackerEntry = combat.selectedUnitId and findEntry(combat, combat.selectedUnitId) or nil
	if not attackerEntry or not attackerEntry.alive or attackerEntry.side ~= side then
		attackerEntry = strongestOwn(combat, side)
	end

	-- Auto target: the weakest enemy unit.
	local targetEntry = weakestEnemy(combat, side)

	if not attackerEntry or not targetEntry then
		CombatSystem.CheckVictory(combat)
		return
	end

	cancelTurnTimer(combat)
	CombatState.AddLog(combat, "Auto-Angriff: " .. attackerEntry.name)
	CombatSystem.ExecuteAttack(combat, attackerEntry, targetEntry)
	CombatSystem.AfterTurn(combat)
end

--------------------------------------------------------------------------------
-- ProcessWildlifeCombat(combatId)
-- Simplified wildlife turn: flat damage, no counter, flees below 50% total LP.
--------------------------------------------------------------------------------
function CombatSystem.ProcessWildlifeCombat(combatId)
	local combat = CombatState.Get(combatId)
	if not combat or combat.phase ~= Phase.ACTIVE then return end

	local side = combat.activeSide or "defender"
	refreshUnits(combat)

	-- Flee check: total LP of the wildlife side.
	local current, max = 0, 0
	for _, entry in ipairs(unitsOf(combat, side)) do
		current += entry.currentLP
		max += entry.maxLP
	end
	if max > 0 and (current / max) < UnitConfig.WILDLIFE_FLEE_LP_RATIO then
		CombatState.AddLog(combat, "Das Wildtier flieht!")
		CombatSystem.EndCombat(combat, otherSide(side), true)
		return
	end

	CombatSystem.AutoAttack(combat)
end

--------------------------------------------------------------------------------
-- MORALE
--------------------------------------------------------------------------------
function CombatSystem.UpdateMorale(combat, side)
	refreshUnits(combat)

	local current, max = 0, 0
	for _, entry in ipairs(unitsOf(combat, side)) do
		current += entry.currentLP
		max += entry.maxLP
	end

	local lpLostPercent = 0
	if max > 0 then
		lpLostPercent = (1 - current / max) * 100
	end

	local stats = combat.stats[side]
	local value = 100
	- stats.deaths * UnitConfig.MORALE_LOSS_PER_DEATH
	- lpLostPercent * UnitConfig.MORALE_LOSS_PER_LP_PERCENT
		+ stats.kills * UnitConfig.MORALE_GAIN_PER_KILL

	combat.morale[side] = math.clamp(math.floor(value), 0, 100)
	return combat.morale[side]
end

--------------------------------------------------------------------------------
-- CheckRoute(combat, side) -> boolean (true = the side breaks and runs)
--------------------------------------------------------------------------------
function CombatSystem.CheckRoute(combat, side)
	if combat.isWildlife and side == "defender" then return false end

	local morale = combat.morale[side]
	if morale >= UnitConfig.MORALE_ROUT_THRESHOLD then return false end

	local chance = 0.3 + (UnitConfig.MORALE_ROUT_THRESHOLD - morale) / 100
	if math.random() >= chance then return false end

	CombatState.AddLog(combat, ("Moral gebrochen (%d) - die Armee zieht sich zurueck!")
		:format(morale))
	CombatSystem.RouteArmy(combat, side)
	return true
end

--------------------------------------------------------------------------------
-- RouteArmy(combat, side) - flee: -20% LP + retreat to a free neighbour hex
--------------------------------------------------------------------------------
function CombatSystem.RouteArmy(combat, side)
	if not CombatData.Transition(combat.id, Phase.ACTIVE, Phase.ROUTING) then
		return
	end

	local armyId = armyIdOf(combat, side)
	local army = ArmyData.GetArmy(armyId)

	if army then
		-- 20% LP loss for the routing units.
		for _, unitId in ipairs(army.units or {}) do
			local unit = UnitData.GetUnit(unitId)
			if unit and unit.alive then
				local loss = math.floor(unit.currentLP * 0.2)
				if loss > 0 then
					UnitData.DamageUnit(unitId, loss)
				end
			end
		end

		-- Retreat to a random free, walkable neighbour hex.
		local candidates = {}
		for _, n in ipairs(HexUtils.getNeighbors(army.q, army.r)) do
			local hex = HexData.GetHex(n.q, n.r)
			if hex and not hex.army and hex.terrain ~= "Water" then
				table.insert(candidates, n)
			end
		end

		if #candidates > 0 then
			local target = candidates[math.random(1, #candidates)]
			ArmySystem.MoveArmy(armyId, target.q, target.r, true) -- force: bypass combat lock
			ArmyModelMover.MoveModelToHex(armyId, target.q, target.r)
		else
			CombatState.AddLog(combat, "Rueckzug gescheitert - kein freies Feld!")
		end

		ArmyStats.Recalculate(armyId)
	end

	CombatSystem.EndCombat(combat, otherSide(side), true)
end

--------------------------------------------------------------------------------
-- AfterTurn(combat) - morale, victory, route, next turn
--------------------------------------------------------------------------------
function CombatSystem.AfterTurn(combat)
	if combat.phase ~= Phase.ACTIVE then return end

	CombatSystem.UpdateMorale(combat, "attacker")
	CombatSystem.UpdateMorale(combat, "defender")

	if CombatSystem.CheckVictory(combat) then return end

	if CombatSystem.CheckRoute(combat, "attacker") then return end
	if CombatSystem.CheckRoute(combat, "defender") then return end

	-- Ping pong: the other side is up IMMEDIATELY.
	CombatSystem.NextTurn(combat)
end

--------------------------------------------------------------------------------
-- GetAliveUnits(combat, side) -> { UnitEntry }
-- Public wrapper around the internal livingUnits helper.
--------------------------------------------------------------------------------
function CombatSystem.GetAliveUnits(combat, side)
	refreshUnits(combat)
	return livingUnits(combat, side)
end

--------------------------------------------------------------------------------
-- AUTO RESOLVE
--
-- Both sides have to agree. A wildlife side and a disconnected player
-- count as agreeing automatically, so a single human can always finish
-- a fight against creatures or against someone who left.
--------------------------------------------------------------------------------
local function autoResolveSideReady(combat, side)
	if combat.autoResolveVotes[side] then return true end
	if ownerOf(combat, side) == nil then return true end   -- wildlife
	if combat.disconnected[side] then return true end      -- left the game
	return false
end

--------------------------------------------------------------------------------
-- RequestAutoResolve(combatId, player) -> boolean, reason
--------------------------------------------------------------------------------
function CombatSystem.RequestAutoResolve(combatId, player)
	local combat = CombatState.Get(combatId)
	if not combat then return false, "Kampf existiert nicht" end
	if combat.phase ~= Phase.ACTIVE then
		return false, "Kampf laeuft nicht"
	end

	local side = CombatState.SideOfPlayer(combat, player)
	if not side then return false, "Nicht beteiligt" end

	if combat.autoResolveVotes[side] then
		return false, "Bereits zugestimmt"
	end

	combat.autoResolveVotes[side] = true
	CombatState.AddLog(combat, ("%s stimmt fuer Auto-Resolve")
		:format(player and player.Name or side))

	-- Tell everyone about the current vote state (button feedback).
	fireBoth(combat, "CombatAutoResolveVote", {
		combatId = combat.id,
		votes = {
			attacker = combat.autoResolveVotes.attacker,
			defender = combat.autoResolveVotes.defender,
		},
	})

	if autoResolveSideReady(combat, "attacker")
		and autoResolveSideReady(combat, "defender") then
		CombatSystem.ExecuteAutoResolve(combat.id)
		return true, nil
	end

	return true, "Warte auf Gegner"
end

--------------------------------------------------------------------------------
-- ExecuteAutoResolve(combatId)
-- Fast-forwards the whole fight: strongest own unit hits the weakest
-- enemy unit, sides alternate, until one side is wiped out.
--------------------------------------------------------------------------------
function CombatSystem.ExecuteAutoResolve(combatId)
	local combat = CombatState.Get(combatId)
	if not combat or combat.phase ~= Phase.ACTIVE then return end

	if not CombatData.Transition(combat.id, Phase.ACTIVE, Phase.AUTO_RESOLVING) then
		return
	end

	cancelTurnTimer(combat)
	combat.autoResolving = true
	combat.selectedUnitId = nil

	CombatState.AddLog(combat, "Auto-Resolve: der Kampf wird ausgerechnet...")
	fireBoth(combat, "CombatAutoResolveStart", { combatId = combat.id })

	-- Hard iteration cap: even with a broken damage config the loop can
	-- never hang the server thread.
	local MAX_ITERATIONS = 500
	local iterations = 0
	local side = combat.activeSide or "attacker"

	while iterations < MAX_ITERATIONS do
		iterations += 1
		refreshUnits(combat)

		local mine = livingUnits(combat, side)
		local foes = livingUnits(combat, otherSide(side))
		if #mine == 0 or #foes == 0 then break end

		-- Strongest own unit (highest attack, LP as tie break).
		table.sort(mine, function(a, b)
			if a.attack == b.attack then return a.currentLP > b.currentLP end
			return a.attack > b.attack
		end)
		-- Weakest enemy unit (lowest LP).
		table.sort(foes, function(a, b) return a.currentLP < b.currentLP end)

		combat.activeSide = side
		CombatSystem.ExecuteAttack(combat, mine[1], foes[1])

		CombatSystem.UpdateMorale(combat, "attacker")
		CombatSystem.UpdateMorale(combat, "defender")

		side = otherSide(side)
	end

	if iterations >= MAX_ITERATIONS then
		warn("[CombatSystem] Auto-Resolve Limit erreicht - Kampf wird beendet")
		CombatState.AddLog(combat, "Auto-Resolve abgebrochen (Limit erreicht)")
	end

	combat.autoResolving = false
	refreshUnits(combat)

	-- Decide the winner. CheckVictory ends the combat when a side is
	-- wiped out; otherwise (iteration cap) the healthier side wins.
	local attackerAlive = #livingUnits(combat, "attacker")
	local defenderAlive = #livingUnits(combat, "defender")

	if attackerAlive > 0 and defenderAlive > 0 then
		local winner = (attackerAlive >= defenderAlive) and "attacker" or "defender"
		CombatSystem.EndCombat(combat, winner, false)
	else
		local winner = (attackerAlive > 0) and "attacker" or "defender"
		CombatSystem.EndCombat(combat, winner, false)
	end
end

--------------------------------------------------------------------------------
-- CheckVictory(combat) -> boolean (true = combat is over)
--------------------------------------------------------------------------------
function CombatSystem.CheckVictory(combat)
	refreshUnits(combat)

	local attackerAlive = #livingUnits(combat, "attacker")
	local defenderAlive = #livingUnits(combat, "defender")

	if attackerAlive > 0 and defenderAlive > 0 then
		return false
	end

	local winner = "attacker"
	if attackerAlive == 0 and defenderAlive == 0 then
		winner = "defender" -- mutual destruction: the defender holds the hex
	elseif attackerAlive == 0 then
		winner = "defender"
	end

	CombatSystem.EndCombat(combat, winner, false)
	return true
end

--------------------------------------------------------------------------------
-- ApplyPostCombat(combat, winnerSide) - heal scales with the winner's morale
--------------------------------------------------------------------------------
function CombatSystem.ApplyPostCombat(combat, winnerSide)
	local winnerArmyId = armyIdOf(combat, winnerSide)
	local army = ArmyData.GetArmy(winnerArmyId)
	if not army then return end

	local morale = combat.morale[winnerSide] or 0
	local healPercent = CombatConfig.POST_COMBAT_HEAL_BASE
		+ morale * CombatConfig.POST_COMBAT_HEAL_MORALE_SCALE

	-- TECH Medicine: +10% on the post combat healing.
	local tech = Tech()
	local owner = ownerOf(combat, winnerSide)
	if tech and owner then
		healPercent = healPercent * (1 + tech.GetSpecial(owner, "PostCombatHealBonus"))
	end

	for _, unitId in ipairs(army.units or {}) do
		local unit = UnitData.GetUnit(unitId)
		if unit and unit.alive then
			UnitData.HealUnit(unitId, math.floor(unit.maxLP * healPercent))
		end
		UnitData.SetCurrentMovement(unitId, 0) -- fighting costs the whole turn
	end

	ArmyStats.Recalculate(winnerArmyId)

	-- Plunder gold for every enemy unit killed.
	local owner = ownerOf(combat, winnerSide)
	local kills = combat.stats[winnerSide].kills
	if owner and kills > 0 then
		PlayerData.AddGold(owner, kills * CombatConfig.PLUNDER_GOLD_PER_KILL)
		CombatState.AddLog(combat, ("+%d Gold Beute")
			:format(kills * CombatConfig.PLUNDER_GOLD_PER_KILL))
	end

	CombatState.AddLog(combat, ("Ueberlebende heilen %d%% ihrer LP")
		:format(math.floor(healPercent * 100)))
end

--------------------------------------------------------------------------------
-- EndCombat(combat, winnerSide, byFlight)
--------------------------------------------------------------------------------
function CombatSystem.EndCombat(combat, winnerSide, byFlight)
	if not combat then return end

	-- Idempotent: a finished combat is only ever cleaned up once.
	if combat.phase == Phase.ENDED or combat.phase == Phase.CLEANED then
		CombatState.Remove(combat.id)
		return
	end

	if not CombatData.Transition(combat.id, combat.phase, Phase.ENDED) then
		-- Last resort: never leave a zombie behind.
		combat.phase = Phase.ENDED
	end

	cancelTurnTimer(combat) -- stop any pending selection timer
	combat.activeSide = nil
	combat.selectedUnitId = nil

	local loserSide = otherSide(winnerSide)
	local winnerArmyId = armyIdOf(combat, winnerSide)
	local loserArmyId = armyIdOf(combat, loserSide)

	local snapshot = buildSnapshot(combat)
	snapshot.winner = winnerSide
	snapshot.byFlight = byFlight or false

	local ok, err = pcall(function()
		if not byFlight then
			-- Wipe out the defeated army (units + model + hex marker).
			local loser = ArmyData.GetArmy(loserArmyId)
			if loser then
				local lq, lr = loser.q, loser.r
				for _, unitId in ipairs(loser.units or {}) do
					UnitData.RemoveUnit(unitId)
				end
				loser.units = {}
				ArmySpawner.DespawnArmy(loserArmyId)
				HexData.ClearHexField(lq, lr, "army")
			end
		end

		CombatSystem.ApplyPostCombat(combat, winnerSide)
	end)
	if not ok then
		warn("[CombatSystem] Aufraeumen fehlgeschlagen: " .. tostring(err))
	end

	-- Tell both clients BEFORE the record disappears.
	fireBoth(combat, "CombatEnd", {
		combatId = combat.id,
		result = snapshot,
		log = combat.log,
	})

	-- Hand the contested hex to the winner, then release the record.
	local hexQ, hexR = combat.q, combat.r
	CombatData.Transition(combat.id, Phase.ENDED, Phase.CLEANED)
	CombatState.Remove(combat.id)

	if not byFlight and winnerSide == "attacker" then
		local winner = ArmyData.GetArmy(winnerArmyId)
		if winner and (winner.q ~= hexQ or winner.r ~= hexR) then
			if ArmySystem.MoveArmy(winnerArmyId, hexQ, hexR, true) then
				ArmyModelMover.MoveModelToHex(winnerArmyId, hexQ, hexR)
			end
		end
	end
	if ArmyData.GetArmy(winnerArmyId) then
		ArmySpawner.RefreshArmyModel(winnerArmyId)
	end

	-- Fog of War: Nach einem Kampf koennen Units gestorben sein -> Sicht beider
	-- Beteiligten neu berechnen (weniger Sicht, Gebaeude bleiben als Quelle).
	if combat.attackerOwner then pcall(FogOfWarSystem.UpdateVision, combat.attackerOwner) end
	if combat.defenderOwner then pcall(FogOfWarSystem.UpdateVision, combat.defenderOwner) end

	-- VICTORY: Punkte + City-Eroberung + Hauptstadt-Eliminierung.
	pcall(function()
		if not byFlight then
			local winnerOwner = ownerOf(combat, winnerSide)
			local loserOwner = ownerOf(combat, loserSide)

			if winnerOwner then
				-- Besiegte feindliche Armee (+25), nur wenn der Verlierer ein
				-- Spieler ist (kein Wildtier).
				if loserOwner and loserOwner ~= winnerOwner then
					pcall(PointSystem.AwardPoints, winnerOwner, "ArmyDefeated",
						VictoryConfig.ACTIVE_POINTS.ArmyDefeated)
				end

				-- City-Eroberung: nur wenn der Angreifer das Hex einnimmt.
				if winnerSide == "attacker" and loserOwner then
					local city = CityData.GetCityOnHex(hexQ, hexR)
					if city and city.owner == loserOwner then
						if PlayerData.GetCapitalCityId(loserOwner) == city.id then
							-- HAUPTSTADT erobert -> Eliminierung des Besitzers.
							pcall(VictorySystem.EliminatePlayer, loserOwner, winnerOwner,
								"Hauptstadt erobert")
						else
							pcall(PointSystem.AwardPoints, winnerOwner, "CityConquered",
								VictoryConfig.ACTIVE_POINTS.CityConquered)
							pcall(PointSystem.DeductPoints, loserOwner, "CityLost",
								VictoryConfig.LOSS_POINTS.CityLost)
							-- Stadt an den Eroberer uebertragen.
							city.owner = winnerOwner
						end
					end
				end
			end

			pcall(VictorySystem.CheckVictory)
		end
	end)

	print(("[CombatSystem] Kampf %d beendet - Sieger: %s%s")
		:format(combat.id, tostring(winnerSide), byFlight and " (Flucht)" or ""))
end

--------------------------------------------------------------------------------
-- HandlePlayerDisconnect(player)
-- All combats of the leaving player switch to auto attack with a 3s timer.
-- If BOTH sides are gone the combat stops immediately (armies stay put).
--------------------------------------------------------------------------------
function CombatSystem.HandlePlayerDisconnect(player)
	if not player then return end

	for _, combat in ipairs(CombatState.GetActiveCombatsForPlayer(player)) do
		local side = CombatState.SideOfPlayer(combat, player)
		if side then
			combat.disconnected[side] = true
			CombatState.AddLog(combat, "Spieler getrennt - Auto-Angriff aktiv")

			local otherOwner = ownerOf(combat, otherSide(side))
			local otherGone = combat.disconnected[otherSide(side)] or otherOwner == nil

			if otherGone and combat.isWildlife == false then
				-- Nobody left to watch: stop the fight, both armies stay alive.
				CombatSystem.EndCombat(combat, otherSide(side), true)
			elseif combat.phase == Phase.ACTIVE and combat.activeSide == side then
				task.defer(function()
					local live = CombatState.Get(combat.id)
					if live and live.phase == Phase.ACTIVE then
						CombatSystem.AutoAttack(live)
					end
				end)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- PUBLIC QUERIES (used by handlers / GUI)
--------------------------------------------------------------------------------
function CombatSystem.GetArmyInCombat(armyId)
	return CombatData.IsInCombat(armyId)
end

function CombatSystem.GetSnapshot(combatId)
	local combat = CombatState.Get(combatId)
	if not combat then return nil end
	return buildSnapshot(combat)
end

function CombatSystem.ProcessFlee(combatId, side)
	local combat = CombatState.Get(combatId)
	if not combat or combat.phase ~= Phase.ACTIVE then
		return false, "Kampf laeuft nicht mehr"
	end
	if combat.isWildlife and side == "defender" then
		return false, "Wildtiere fliehen nicht"
	end
	CombatSystem.RouteArmy(combat, side)
	return true, nil
end

-- Legacy no-op: combats no longer tick with the game round.
function CombatSystem.ProcessAllCombats()
	return 0
end

return CombatSystem
