--[[
    RoundController (LocalScript)
    Ort: StarterGui > RoundTimerGui > RoundController
    
    Client-seitiger Runden-Controller.
    Zeigt Countdown, Rundennummer, Vote-Status an.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer

-- Remotes
local roundEndRemote = ReplicatedStorage:WaitForChild("RoundEnd")
local skipRoundRemote = ReplicatedStorage:WaitForChild("SkipRound")

-- GUI Referenzen
local gui = script.Parent

local countdownLabel = gui:FindFirstChild("RoundCountdownLable")
local roundCounterLabel = gui:FindFirstChild("RoundCounterLable")
local voteLabel = gui:FindFirstChild("VoteLable")
local endRoundButton = gui:FindFirstChild("EndRoundButton")

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------
local hasVoted = false
local currentRound = 0

--------------------------------------------------------------------------------
-- GUI aktualisieren
--------------------------------------------------------------------------------
local function updateCountdown(seconds)
	if countdownLabel then countdownLabel.Text = tostring(math.max(0, seconds)) end
end

local function updateRoundCounter(round)
	if roundCounterLabel then roundCounterLabel.Text = "Runde " .. round end
end

local function updateVoteLabel(votes, totalPlayers)
	if voteLabel then voteLabel.Text = votes .. "/" .. totalPlayers end
end

local function setButtonVoted(voted)
	if not endRoundButton then return end
	endRoundButton.ImageTransparency = voted and 0.5 or 0
end

-- Der EndRoundButton ist immer sichtbar, solange eine Runde läuft.
-- (Die frühere Kopplung an den ContinueMoveButton entfällt - Bewegungen
--  laufen jetzt automatisch zu Rundenbeginn weiter.)
local function updateEndRoundButtonVisibility()
	if not endRoundButton then return end

	-- Immer klickbar: ein zweiter Klick nimmt die Stimme zurück
	endRoundButton.Visible = true
	endRoundButton.Active = true
	endRoundButton.AutoButtonColor = true
end

--------------------------------------------------------------------------------
-- Runden-Events vom Server empfangen
--------------------------------------------------------------------------------
roundEndRemote.OnClientEvent:Connect(function(data)
	if not data or type(data) ~= "table" then return end

	if data.type == "roundStart" then
		currentRound = data.round or 0
		hasVoted = false
		setButtonVoted(false)

		updateRoundCounter(currentRound)
		updateCountdown(data.timeRemaining or 0)
		updateVoteLabel(0, data.totalPlayers or 0)

		task.delay(0.5, updateEndRoundButtonVisibility)

	elseif data.type == "tick" then
		updateCountdown(data.timeRemaining or 0)
		updateVoteLabel(data.skipVotes or 0, data.totalPlayers or 0)
		updateEndRoundButtonVisibility()

	elseif data.type == "voteUpdate" then
		updateCountdown(data.timeRemaining or 0)
		updateVoteLabel(data.skipVotes or 0, data.totalPlayers or 0)

	elseif data.type == "roundEnd" then
		currentRound = data.round or currentRound
		hasVoted = false
		setButtonVoted(false)
		updateCountdown(0)
	end
end)

--------------------------------------------------------------------------------
-- EndRound Button Handler
--------------------------------------------------------------------------------
if endRoundButton then
	endRoundButton.MouseButton1Click:Connect(function()
		-- TOGGLE: erneuter Klick zieht die Stimme zurück
		hasVoted = not hasVoted
		setButtonVoted(hasVoted)
		skipRoundRemote:FireServer()

		print(hasVoted
			and "[RoundController] Für Rundenende gestimmt"
			or "[RoundController] Stimme zurückgezogen")
	end)
end

--------------------------------------------------------------------------------
-- Initialer Zustand
--------------------------------------------------------------------------------
updateCountdown(0)
updateRoundCounter(0)
updateVoteLabel(0, 0)

local dataRemotes = ReplicatedStorage:FindFirstChild("DataRemotes")
if dataRemotes then
	local getRoundData = dataRemotes:FindFirstChild("GetRoundData")
	if getRoundData then
		local success, data = pcall(function()
			return getRoundData:InvokeServer()
		end)
		if success and data then
			currentRound = data.round or 0
			updateRoundCounter(currentRound)
			updateCountdown(data.timeRemaining or 0)
			updateVoteLabel(data.skipVotes or 0, data.totalPlayers or 0)
		end
	end
end

-- Initiale Sichtbarkeit setzen
updateEndRoundButtonVisibility()

print("[RoundController] Bereit.")