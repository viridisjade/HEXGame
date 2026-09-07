--[[
    FunktioniertLabel (LocalScript)
    Ort: StarterPlayerScripts > FunktioniertLabel

    Test-Skript: Erzeugt ein TextLabel in der Mitte des Bildschirms
    mit dem Text "funktioniert".

    Der LocalScript läuft clientseitig und erstellt die GUI komplett
    per Code (kein ScreenGui in Studio noetig).
--]]

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- 1. ScreenGui erstellen und ins PlayerGui haengen
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "FunktioniertGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true  -- Label wirklich mittig, ohne Topbar-Versatz
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- 2. TextLabel in der Bildschirmmitte
local textLabel = Instance.new("TextLabel")
textLabel.Name = "FunktioniertLabel"
textLabel.AnchorPoint = Vector2.new(0.5, 0.5)   -- Verankerung in der Mitte
textLabel.Position = UDim2.fromScale(0.5, 0.5)  -- exakt in der Mitte
textLabel.Size = UDim2.fromScale(0.5, 0.1)      -- Halbe Breite, 10% Hoehe
textLabel.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
textLabel.BackgroundTransparency = 0.2
textLabel.BorderColor3 = Color3.fromRGB(0, 200, 80)
textLabel.BorderSizePixel = 2
textLabel.Text = "funktioniert"
textLabel.TextColor3 = Color3.fromRGB(0, 255, 120)
textLabel.Font = Enum.Font.GothamBold
textLabel.TextScaled = true
textLabel.TextWrapped = true
textLabel.Parent = screenGui

print("[FunktioniertLabel] TextLabel 'funktioniert' erstellt.")
