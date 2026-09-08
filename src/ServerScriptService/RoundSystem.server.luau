
--[[
    RoundSystem (Script)
    Ort: ServerScriptService > RoundSystem
    
    Server-seitiges Runden-System.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ArmyStats = require(script.Parent:WaitForChild("ArmyStats"))
local ConstructionSystem = require(script.Parent:WaitForChild("ConstructionSystem"))
local CityEconomySystem = require(script.Parent:WaitForChild("CityEconomySystem"))
local FogOfWarSystem = require(script.Parent:WaitForChild("FogOfWarSystem"))
-- NOTE: combats no longer tick with the game round. They run asynchronously
-- and are driven by CombatSystem's own turn timers (see CombatSystem.StartTurn).

local CONFIG = {
	ROUND_DURATION = 30,
}

local currentRound = 0
local timeRemaining = 0
local roundActive = false
local skipVotes = {}

local function getVoteCount()
	local count = 0
	for _, voted in pairs(skipVotes) do
		if voted then
			count = count + 1
		end
	end
	return count
end

local roundEndRemote = ReplicatedStorage:WaitForChild("RoundEnd")
local skipRoundRemote = ReplicatedStorage:WaitForChild("SkipRound")

local dataRemotes = ReplicatedStorage:WaitForChild("DataRemotes", 20)
local getRoundDataRemote = dataRemotes and dataRemotes:WaitForChild("GetRoundData", 10)

if getRoundDataRemote then
	getRoundDataRemote.OnServerInvoke = function(player)
		return {
			round = currentRound,
			timeRemaining = math.ceil(timeRemaining),
			roundActive = roundActive,
			skipVotes = getVoteCount(),
			totalPlayers = #Players:GetPlayers(),
		}
	end
end

local function getPlayerCount()
	return #Players:GetPlayers()
end

local function resetVotes()
	skipVotes = {}
end

local function allPlayersVoted()
	local playerCount = getPlayerCount()
	if playerCount == 0 then return false end
	return getVoteCount() >= playerCount
end

local function broadcastRoundInfo()
	for _, player in ipairs(Players:GetPlayers()) do
		roundEndRemote:FireClient(player, {
			type = "tick",
			round = currentRound,
			timeRemaining = math.ceil(timeRemaining),
			skipVotes = getVoteCount(),
			totalPlayers = getPlayerCount(),
		})
	end
end

local function broadcastRoundEnd()
	for _, player in ipairs(Players:GetPlayers()) do
		roundEndRemote:FireClient(player, {
			type = "roundEnd",
			round = currentRound,
		})
	end
end

local function broadcastRoundStart()
	for _, player in ipairs(Players:GetPlayers()) do
		roundEndRemote:FireClient(player, {
			type = "roundStart",
			round = currentRound,
			timeRemaining = math.ceil(timeRemaining),
			skipVotes = 0,
			totalPlayers = getPlayerCount(),
		})
	end
end

local function broadcastVoteUpdate()
	for _, player in ipairs(Players:GetPlayers()) do
		roundEndRemote:FireClient(player, {
			type = "voteUpdate",
			round = currentRound,
			timeRemaining = math.ceil(timeRemaining),
			skipVotes = getVoteCount(),
			totalPlayers = getPlayerCount(),
		})
	end
end

skipRoundRemote.OnServerEvent:Connect(function(player)
	if not roundActive then return end

	if skipVotes[player] then
		skipVotes[player] = nil
		print("[RoundSystem] " .. player.Name .. " zieht die Stimme zurück ("
			.. getVoteCount() .. "/" .. getPlayerCount() .. ")")
		broadcastVoteUpdate()
		return
	end

	skipVotes[player] = true
	print("[RoundSystem] " .. player.Name .. " stimmt für Rundenende ("
		.. getVoteCount() .. "/" .. getPlayerCount() .. ")")

	broadcastVoteUpdate()

	if allPlayersVoted() then
		print("[RoundSystem] Alle haben zugestimmt - Runde endet sofort.")
		timeRemaining = 0
	end
end)

Players.PlayerAdded:Connect(function()
	if roundActive then
		broadcastVoteUpdate()
	end
end)

Players.PlayerRemoving:Connect(function(player)
	if skipVotes[player] == nil and not roundActive then return end

	skipVotes[player] = nil

	if not roundActive then return end

	broadcastVoteUpdate()

	if allPlayersVoted() then
		print("[RoundSystem] Alle verbleibenden Spieler haben zugestimmt - Runde endet.")
		timeRemaining = 0
	end
end)

local function startRound()
	currentRound = currentRound + 1
	timeRemaining = CONFIG.ROUND_DURATION
	roundActive = true
	resetVotes()

	ArmyStats.ResetAllMovement()

	-- REMOVED: CombatSystem.ProcessAllCombats()
	-- Turn based combats are asynchronous now - they must NOT be advanced
	-- by the 30s round loop any more.

	if _G.ContinueAllMovementOrders then
		local ok, err = pcall(_G.ContinueAllMovementOrders)
		if not ok then
			warn("[RoundSystem] Bewegungs-Fortsetzung fehlgeschlagen: " .. tostring(err))
		end
	end

	CityEconomySystem.ProcessAllCities()

	ConstructionSystem.ProcessAllConstruction()

	-- Fog of War: Beim Rundenstart die Sicht aller Spieler auffrischen
	-- (Bewegung/Bau/Kampf koennen Sichtquellen veraendert haben).
	for _, player in ipairs(Players:GetPlayers()) do
		pcall(FogOfWarSystem.UpdateVision, player)
	end

	print("[RoundSystem] === Runde " .. currentRound .. " gestartet (" .. CONFIG.ROUND_DURATION .. "s) ===")
	broadcastRoundStart()
end

local function endRound()
	roundActive = false

	print("[RoundSystem] === Runde " .. currentRound .. " beendet ===")
	broadcastRoundEnd()

	-- Diplomatie: abgelaufene Angebote (Bündnis-/Friedensantraege) verarbeiten.
	local okDipl, DiplomacySystem = pcall(function()
		return require(script.Parent:WaitForChild("DiplomacySystem"))
	end)
	if okDipl and DiplomacySystem then
		pcall(DiplomacySystem.ProcessExpiredOffers)
	end

	task.wait(2)
end

local function runRoundTimer()
	local lastBroadcast = tick()

	while timeRemaining > 0 do
		task.wait(0.1)
		timeRemaining = timeRemaining - 0.1

		if tick() - lastBroadcast >= 1 then
			lastBroadcast = tick()
			broadcastRoundInfo()
		end
	end

	timeRemaining = 0
end

print("[RoundSystem] Warte auf Spieler...")

while getPlayerCount() == 0 do
	task.wait(1)
end

print("[RoundSystem] Spieler gefunden! Starte Runden-System.")
task.wait(3)

while true do
	startRound()
	runRoundTimer()
	endRound()
end
