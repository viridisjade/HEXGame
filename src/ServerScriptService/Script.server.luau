--[[
    TechHandler (Script)
    Location: ServerScriptService > TechHandler

    Server entry point for every tech tree remote.

    Bound remotes:
        ReplicatedStorage > TechAddToQueue       (RemoteEvent,    C -> S)
        ReplicatedStorage > TechRemoveFromQueue  (RemoteEvent,    C -> S)
        ReplicatedStorage > TechReorderQueue     (RemoteEvent,    C -> S)
        DataRemotes      > GetTechState          (RemoteFunction, C -> S)

    Same ordering rule as CombatHandler: RemoteFunctions are bound FIRST and
    the modules are required lazily, so an unanswered InvokeServer can never
    freeze a client.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--------------------------------------------------------------------------------
-- REMOTE PLUMBING (self healing)
--------------------------------------------------------------------------------
local dataRemotes = ReplicatedStorage:FindFirstChild("DataRemotes")
	or ReplicatedStorage:WaitForChild("DataRemotes", 10)

if not dataRemotes then
	dataRemotes = Instance.new("Folder")
	dataRemotes.Name = "DataRemotes"
	dataRemotes.Parent = ReplicatedStorage
	warn("[TechHandler] DataRemotes fehlte - Ordner wurde angelegt")
end

local function ensureRemote(parent: Instance, className: string, name: string)
	local found = parent:FindFirstChild(name)
	if found and found.ClassName == className then return found end
	if found then
		warn(("[TechHandler] '%s' ist ein %s, erwartet %s")
			:format(name, found.ClassName, className))
		return found
	end
	local obj = Instance.new(className)
	obj.Name = name
	obj.Parent = parent
	warn("[TechHandler] Remote '" .. name .. "' fehlte - wurde angelegt")
	return obj
end

--------------------------------------------------------------------------------
-- LAZY MODULE ACCESS
--------------------------------------------------------------------------------
local _system, _data

local function Sys()
	if not _system then
		_system = require(script.Parent:WaitForChild("TechTreeSystem"))
	end
	return _system
end

local function Dat()
	if not _data then
		_data = require(script.Parent:WaitForChild("TechData"))
	end
	return _data
end

local function isTechId(value): boolean
	return type(value) == "string" and #value > 0 and #value <= 64
end

--------------------------------------------------------------------------------
-- 1) REMOTE FUNCTION - bound first, always answers
--------------------------------------------------------------------------------
local getTechState = ensureRemote(dataRemotes, "RemoteFunction", "GetTechState")
getTechState.OnServerInvoke = function(player)
	local ok, result = pcall(function()
		Dat().Create(player)
		Dat().SetTotalRP(player, Sys().GetTotalRP(player))
		return Dat().BuildClientPayload(player)
	end)
	if not ok then
		warn("[TechHandler] GetTechState fehlgeschlagen: " .. tostring(result))
		return nil
	end
	return result
end

--------------------------------------------------------------------------------
-- 2) REMOTE EVENTS
--------------------------------------------------------------------------------
local addRemote = ensureRemote(ReplicatedStorage, "RemoteEvent", "TechAddToQueue")
addRemote.OnServerEvent:Connect(function(player, techId)
	if not isTechId(techId) then return end

	local ok, reason = Sys().AddToQueue(player, techId)
	if not ok then
		print("[TechHandler] AddToQueue abgelehnt (" .. player.Name .. "): " .. tostring(reason))
	end
end)

local removeRemote = ensureRemote(ReplicatedStorage, "RemoteEvent", "TechRemoveFromQueue")
removeRemote.OnServerEvent:Connect(function(player, techId)
	if not isTechId(techId) then return end

	local ok, reason = Sys().RemoveFromQueue(player, techId)
	if not ok then
		print("[TechHandler] RemoveFromQueue abgelehnt (" .. player.Name .. "): " .. tostring(reason))
	end
end)

local reorderRemote = ensureRemote(ReplicatedStorage, "RemoteEvent", "TechReorderQueue")
reorderRemote.OnServerEvent:Connect(function(player, newOrder)
	if type(newOrder) ~= "table" then return end
	if #newOrder > 32 then return end   -- sanity guard against spam payloads

	local clean = {}
	for _, id in ipairs(newOrder) do
		if isTechId(id) then table.insert(clean, id) end
	end

	local ok, reason = Sys().ReorderQueue(player, clean)
	if not ok then
		print("[TechHandler] ReorderQueue abgelehnt (" .. player.Name .. "): " .. tostring(reason))
	end
end)

--------------------------------------------------------------------------------
-- 3) PLAYER LIFECYCLE
--------------------------------------------------------------------------------
Players.PlayerAdded:Connect(function(player)
	Dat().Create(player)
	-- Give the client a moment to load its scripts before the first push.
	task.delay(2, function()
		if player.Parent then
			pcall(Sys().Broadcast, player)
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	Dat().Remove(player)
end)

for _, player in ipairs(Players:GetPlayers()) do
	Dat().Create(player)
end

print("[TechHandler] Bereit - Tech-Remotes verbunden.")
