--[[
    CombatHandler (Script)
    Location: ServerScriptService > CombatHandler

    Single server entry point for every combat remote.

    Bound remotes:
        ReplicatedStorage > CombatSelectUnit    (RemoteEvent,    C -> S)
        ReplicatedStorage > CombatSelectTarget  (RemoteEvent,    C -> S)
        ReplicatedStorage > CombatAutoResolve   (RemoteEvent,    C -> S)
        DataRemotes      > FleeRequest          (RemoteEvent,    C -> S)
        DataRemotes      > GetArmyInCombat      (RemoteFunction, C -> S)
        DataRemotes      > GetCombatSnapshot    (RemoteFunction, C -> S)

    !! ORDERING RULE !!
    RemoteFunctions are created and bound FIRST, before any heavy require.
    A RemoteFunction without OnServerInvoke makes InvokeServer() on the client
    yield FOREVER (no error, no output) - that once froze every right click.
    Therefore: bind first, require lazily, and always answer (never yield).
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

--------------------------------------------------------------------------------
-- REMOTE PLUMBING (self healing: creates anything RemoteSetup has not made yet)
--------------------------------------------------------------------------------
local dataRemotes = ReplicatedStorage:FindFirstChild("DataRemotes")
if not dataRemotes then
	dataRemotes = ReplicatedStorage:WaitForChild("DataRemotes", 10)
end
if not dataRemotes then
	dataRemotes = Instance.new("Folder")
	dataRemotes.Name = "DataRemotes"
	dataRemotes.Parent = ReplicatedStorage
	warn("[CombatHandler] DataRemotes fehlte - Ordner wurde angelegt")
end

local function ensureRemote(parent: Instance, className: string, name: string)
	local found = parent:FindFirstChild(name)
	if found and found.ClassName == className then
		return found
	end
	if found then
		warn(("[CombatHandler] '%s' ist ein %s, erwartet %s"):format(name, found.ClassName, className))
		return found
	end
	local obj = Instance.new(className)
	obj.Name = name
	obj.Parent = parent
	warn("[CombatHandler] Remote '" .. name .. "' fehlte - wurde angelegt")
	return obj
end

--------------------------------------------------------------------------------
-- LAZY MODULE ACCESS
-- Never require at the top: a failing/slow module must not stop us from
-- answering RemoteFunction calls.
--------------------------------------------------------------------------------
local _system, _state, _data

local function Sys()
	if not _system then
		_system = require(script.Parent:WaitForChild("CombatSystem"))
	end
	return _system
end

local function St()
	if not _state then
		_state = require(script.Parent:WaitForChild("CombatState"))
	end
	return _state
end

local function Dat()
	if not _data then
		_data = require(script.Parent:WaitForChild("CombatData"))
	end
	return _data
end

local function isId(value): boolean
	return type(value) == "number" and value >= 1 and value % 1 == 0
end

--------------------------------------------------------------------------------
-- 1) REMOTE FUNCTIONS - bound immediately, ALWAYS return a value
--------------------------------------------------------------------------------
local getArmyInCombat = ensureRemote(dataRemotes, "RemoteFunction", "GetArmyInCombat")
getArmyInCombat.OnServerInvoke = function(_player, armyId)
	if not isId(armyId) then return false end
	-- pcall: a broken combat module must answer "false", never yield or error.
	local ok, result = pcall(function()
		return Dat().IsInCombat(armyId)
	end)
	if not ok then
		warn("[CombatHandler] GetArmyInCombat fehlgeschlagen: " .. tostring(result))
		return false
	end
	return result == true
end

local getSnapshot = ensureRemote(dataRemotes, "RemoteFunction", "GetCombatSnapshot")
getSnapshot.OnServerInvoke = function(player, combatId)
	local ok, result = pcall(function()
		local state = St()
		local combat
		if isId(combatId) then
			combat = state.Get(combatId)
		else
			combat = state.GetActiveCombatsForPlayer(player)[1]
		end
		if not combat then return nil end

		local side = state.SideOfPlayer(combat, player)
		if not side then return nil end

		local snapshot = Sys().GetSnapshot(combat.id)
		if snapshot then
			snapshot.mySide = side
		end
		return snapshot
	end)
	if not ok then
		warn("[CombatHandler] GetCombatSnapshot fehlgeschlagen: " .. tostring(result))
		return nil
	end
	return result
end

--------------------------------------------------------------------------------
-- 2) REMOTE EVENTS
--------------------------------------------------------------------------------
local selectUnitRemote = ensureRemote(ReplicatedStorage, "RemoteEvent", "CombatSelectUnit")
selectUnitRemote.OnServerEvent:Connect(function(player, combatId, unitId)
	if not isId(combatId) or not isId(unitId) then return end

	local ok, reason = Sys().SelectUnit(combatId, player, unitId)
	if not ok then
		print("[CombatHandler] SelectUnit abgelehnt (" .. player.Name .. "): " .. tostring(reason))
	end
end)

local selectTargetRemote = ensureRemote(ReplicatedStorage, "RemoteEvent", "CombatSelectTarget")
selectTargetRemote.OnServerEvent:Connect(function(player, combatId, targetUnitId)
	if not isId(combatId) or not isId(targetUnitId) then return end

	local ok, reason = Sys().SelectTarget(combatId, player, targetUnitId)
	if not ok then
		print("[CombatHandler] SelectTarget abgelehnt (" .. player.Name .. "): " .. tostring(reason))
	end
end)

--------------------------------------------------------------------------------
-- CombatAutoResolve: both sides have to agree, then the server
-- fast-forwards the remaining fight in one go.
--------------------------------------------------------------------------------
local autoResolveRemote = ensureRemote(ReplicatedStorage, "RemoteEvent", "CombatAutoResolve")
autoResolveRemote.OnServerEvent:Connect(function(player, combatId)
	if not isId(combatId) then return end

	local ok, reason = Sys().RequestAutoResolve(combatId, player)
	if not ok then
		print("[CombatHandler] AutoResolve abgelehnt (" .. player.Name .. "): " .. tostring(reason))
	end
end)

local fleeRequest = ensureRemote(dataRemotes, "RemoteEvent", "FleeRequest")
local fleeResult = ensureRemote(dataRemotes, "RemoteEvent", "FleeResult")

fleeRequest.OnServerEvent:Connect(function(player, combatId)
	if not isId(combatId) then return end

	local state = St()
	local combat = state.Get(combatId)
	if not combat then return end

	local side = state.SideOfPlayer(combat, player)
	if not side then
		warn("[CombatHandler] " .. player.Name .. " ist nicht an Kampf " .. combatId .. " beteiligt")
		return
	end

	local success, reason = Sys().ProcessFlee(combatId, side)

	fleeResult:FireClient(player, {
		combatId = combatId,
		success = success,
		reason = reason,
	})
end)

print("[CombatHandler] Bereit - Combat-Remotes verbunden (RF zuerst gebunden).")
