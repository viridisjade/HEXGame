--[[
    VictoryGuiController (LocalScript)
    Ort: StarterGui > VictoryGui > VictoryGuiController

    Sieg-Bildschirm. Erscheint, wenn der Server VictoryAchieved feiert.
    Zeigt Titel, Nachricht, Endpunktzahl und einen Neustart-Button.

    Der Server pusht VictoryAchieved an ALLE; dieser Controller befuellt die
    UI und schaltet das VictoryGui sichtbar. Der Neustart-Button feuert
    SkipRound (nächste Runde) und blendet das Fenster wieder aus.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Net = require(ReplicatedStorage:WaitForChild("Net"))
local ClientState = require(ReplicatedStorage:WaitForChild("ClientState"))
local VictoryConfig = require(ReplicatedStorage:WaitForChild("VictoryConfig"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = script.Parent:IsA("ScreenGui")
	and script.Parent
	or script.Parent:FindFirstAncestorWhichIsA("ScreenGui")
if not gui then return end

gui.Enabled = false
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true

--------------------------------------------------------------------------------
-- STATISCHE UI
--------------------------------------------------------------------------------
local function ensure(parent, class, name, setup)
	local existing = parent:FindFirstChild(name)
	if existing then return existing end
	local obj = Instance.new(class)
	obj.Name = name
	if setup then setup(obj) end
	obj.Parent = parent
	return obj
end

local overlay = ensure(gui, "Frame", "VictoryOverlay", function(f)
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = Color3.fromRGB(8, 10, 16)
	f.BackgroundTransparency = 0.15
	f.BorderSizePixel = 0
end)

local center = ensure(overlay, "Frame", "CenterFrame", function(f)
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.new(0.5, 0, 0.5, 0)
	f.Size = UDim2.fromOffset(480, 320)
	f.BackgroundColor3 = Color3.fromRGB(20, 22, 32)
	f.BackgroundTransparency = 0.15
	f.BorderSizePixel = 0
end)
ensure(center, "UICorner", "Corner", function(c)
	c.CornerRadius = UDim.new(0, 16)
end)

-- Titel
local titleLabel = ensure(center, "TextLabel", "TitleLabel", function(l)
	l.AnchorPoint = Vector2.new(0.5, 0)
	l.Position = UDim2.new(0.5, 0, 0, 34)
	l.Size = UDim2.new(1, -60, 0, 50)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextSize = 34
	l.TextColor3 = Color3.fromRGB(255, 205, 90)
	l.Text = "🏆 SIEG!"
end)

-- Gewinner-Typ
local typeLabel = ensure(center, "TextLabel", "WinnerTypeLabel", function(l)
	l.AnchorPoint = Vector2.new(0.5, 0)
	l.Position = UDim2.new(0.5, 0, 0, 92)
	l.Size = UDim2.new(1, -60, 0, 26)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextSize = 16
	l.TextColor3 = Color3.fromRGB(180, 190, 210)
	l.Text = "SOLO"
end)

-- Nachricht (Gewinner)
local messageLabel = ensure(center, "TextLabel", "MessageLabel", function(l)
	l.AnchorPoint = Vector2.new(0.5, 0)
	l.Position = UDim2.new(0.5, 0, 0, 128)
	l.Size = UDim2.new(1, -60, 0, 60)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.Gotham
	l.TextSize = 20
	l.TextColor3 = Color3.fromRGB(238, 240, 248)
	l.Text = ""
	l.TextWrapped = true
end)

-- Endpunktzahl
local scoreLabel = ensure(center, "TextLabel", "FinalScoreLabel", function(l)
	l.AnchorPoint = Vector2.new(0.5, 0)
	l.Position = UDim2.new(0.5, 0, 0, 196)
	l.Size = UDim2.new(1, -60, 0, 34)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextSize = 26
	l.TextColor3 = Color3.fromRGB(255, 205, 90)
	l.Text = ""
end)

-- Neustart-Button
local restartButton = ensure(center, "TextButton", "RestartButton", function(b)
	b.AnchorPoint = Vector2.new(0.5, 0)
	b.Position = UDim2.new(0.5, 0, 0, 248)
	b.Size = UDim2.new(0.6, 0, 0, 46)
	b.BackgroundColor3 = Color3.fromRGB(40, 110, 70)
	b.BorderSizePixel = 0
	b.Font = Enum.Font.GothamBold
	b.TextSize = 18
	b.TextColor3 = Color3.fromRGB(255, 255, 255)
	b.Text = "🔄 Neustart"
	b.Active = true
	b.AutoButtonColor = true
	b.Interactable = true
end)
ensure(restartButton, "UICorner", "Corner", function(c)
	c.CornerRadius = UDim.new(0, 8)
end)

--------------------------------------------------------------------------------
-- VICTORY ANZEIGEN
--------------------------------------------------------------------------------
local function showVictory(payload)
	if not payload then return end

	local winnerType = (payload.winnerType == "alliance") and "ALLIANZ-SIEG" or "SOLO-SIEG"
	titleLabel.Text = "🏆 SIEG!"
	typeLabel.Text = winnerType
	messageLabel.Text = payload.winnerName or "???"
	scoreLabel.Text = tostring(payload.finalPoints or 0) .. " Punkte"

	gui.Enabled = true
end

Net.On("VictoryAchieved", function(payload)
	showVictory(payload)
end)

-- Neustart: naechste Runde anstossen + Fenster ausblenden.
restartButton.Activated:Connect(function()
	Net.Fire("SkipRound")
	gui.Enabled = false
end)

print("[VictoryGuiController] Bereit.")
