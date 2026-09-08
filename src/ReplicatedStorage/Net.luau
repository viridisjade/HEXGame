
--[[
    Net (ModuleScript)
    Ort: ReplicatedStorage > Net
    
    Der EINZIGE Weg, wie Client-Scripts Remotes benutzen.
    
    Kein Script sucht Remotes mehr selbst. Damit kann kein Script mehr
    beim Start blockieren, weil ein Remote noch nicht repliziert ist.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = {}

local TIMEOUT = 20
local cache = {}

-- Diese Remotes liegen direkt in ReplicatedStorage, nicht in DataRemotes
local ROOT = {
	RoundEnd = true, SkipRound = true,
	RequestRoute = true, ConfirmMove = true,
	CancelMove = true,
	-- Turn based combat (client -> server)
	CombatSelectUnit = true, CombatSelectTarget = true,
	CombatAutoResolve = true,
	-- Tech tree (client -> server)
	TechAddToQueue = true, TechRemoveFromQueue = true,
	TechReorderQueue = true,
	-- Diplomatie (client -> server)
	DiplomacySendOffer = true, DiplomacyRespondOffer = true,
	DiplomacyDeclareWar = true, DiplomacyBreakAlliance = true,
	-- NOTE: the server -> client combat events (CombatTurnStart,
	-- CombatAutoResolveStart, ...) live in the DataRemotes folder and are
	-- found through the fallback below - they must NOT be listed here.
}

function Net.Get(name)
	local hit = cache[name]
	if hit and hit.Parent then return hit end

	local remote
	if ROOT[name] then
		remote = ReplicatedStorage:WaitForChild(name, TIMEOUT)
	else
		local folder = ReplicatedStorage:FindFirstChild("DataRemotes")
			or ReplicatedStorage:WaitForChild("DataRemotes", TIMEOUT)
		if folder then
			remote = folder:FindFirstChild(name) or folder:WaitForChild(name, TIMEOUT)
		end
	end

	if remote then
		cache[name] = remote
	else
		warn("[Net] Remote fehlt: " .. tostring(name))
	end
	return remote
end

function Net.Invoke(name, ...)
	local remote = Net.Get(name)
	if not remote then return false, nil end

	local args = table.pack(...)
	local ok, result = pcall(function()
		return remote:InvokeServer(table.unpack(args, 1, args.n))
	end)

	if not ok then
		warn("[Net] " .. name .. " fehlgeschlagen: " .. tostring(result))
		return false, nil
	end
	return true, result
end

function Net.Fire(name, ...)
	local remote = Net.Get(name)
	if not remote then return false end
	remote:FireServer(...)
	return true
end

function Net.On(name, callback)
	local remote = Net.Get(name)
	if not remote then return nil end
	return remote.OnClientEvent:Connect(callback)
end

function Net.Warmup(names)
	task.spawn(function()
		for _, name in ipairs(names) do Net.Get(name) end
	end)
end

return Net
