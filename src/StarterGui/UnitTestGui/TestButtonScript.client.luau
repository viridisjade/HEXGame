--[[
    TestButtonScript (LocalScript)
    Ort: StarterGui > UnitTestGui > TestButtonScript
    
    Test-Script zum Spawnen von Tribe-Units.
    
    Klick auf Button → nächster Klick auf ein Hex spawnt dort eine Tribe.
    Wenn schon eine eigene Army auf dem Hex ist → Unit wird dazu gepackt.
    Wenn Hex frei → neue Army wird erstellt.
    
    Benötigt:
      ReplicatedStorage > DataRemotes > RequestSpawnUnit (RemoteEvent)
      ReplicatedStorage > HexGridConfig (ModuleScript)
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local HexGridConfig = require(ReplicatedStorage:WaitForChild("HexGridConfig"))

-- Button suchen
local button = script.Parent:FindFirstChildWhichIsA("TextButton")
	or script.Parent:FindFirstChildWhichIsA("ImageButton")

if not button then
	warn("[TestButtonScript] Kein Button gefunden!")
	return
end

-- Remote suchen
local remotesFolder = ReplicatedStorage:FindFirstChild("DataRemotes")
if not remotesFolder then
	warn("[TestButtonScript] DataRemotes nicht gefunden!")
	return
end

local remote = remotesFolder:FindFirstChild("RequestSpawnUnit")
if not remote then
	warn("[TestButtonScript] RequestSpawnUnit nicht gefunden!")
	return
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------
local waitingForHexClick = false

--------------------------------------------------------------------------------
-- Button klicken → Spawn-Modus aktivieren
--------------------------------------------------------------------------------
button.MouseButton1Click:Connect(function()
	waitingForHexClick = true
	button.Text = "Klicke auf ein Hex..."
	print("[TestButtonScript] Klicke jetzt auf ein Hex zum Spawnen!")
end)

--------------------------------------------------------------------------------
-- Hex anklicken → Tribe dort spawnen
--------------------------------------------------------------------------------
mouse.Button1Down:Connect(function()
	if not waitingForHexClick then return end

	local target = mouse.Target
	if not target then return end

	local q, r = HexGridConfig.worldToAxial(mouse.Hit.Position)

	waitingForHexClick = false
	button.Text = "Spawn Tribe"

	print("[TestButtonScript] Spawne Tribe auf (" .. q .. ", " .. r .. ")...")
	remote:FireServer("Tribe", q, r)
end)

-- Initial
button.Text = "Spawn Tribe"

print("[TestButtonScript] Bereit. Klicke Button, dann Hex.")
