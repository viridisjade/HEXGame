
--[[
    EmpireOverlayController (LocalScript)
    Ort: StarterGui > EmpireOverlayGui > EmpireOverlayController
    
    Befüllt das EmpireOverlayGui mit den Spieler-Statistiken.
    Aktualisiert alle 1 Sekunde.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local dataRemotes = ReplicatedStorage:WaitForChild("DataRemotes")
local getEmpireData = dataRemotes:FindFirstChild("GetEmpireData")

local gui = script.Parent
local empireFrame = gui:WaitForChild("EmpireFrame")

local playerNameLabel = empireFrame:FindFirstChild("PlayerNameLable")
local goldLabel = empireFrame:FindFirstChild("PlayerGoldLable")
local armyLabel = empireFrame:FindFirstChild("PlayerArmyCountLable")
local campLabel = empireFrame:FindFirstChild("PlayerCampCountLable")
local cityLabel = empireFrame:FindFirstChild("PlayerCityCountLable")

--------------------------------------------------------------------------------
-- TECH TREE: the research button toggles the TechTreeGui.
-- Communication runs through the 'ToggleTechTree' BindableEvent in
-- ReplicatedStorage - the same decoupling pattern used by HexRightClick
-- and OpenCombatView. This keeps the two GUIs free of requires.
--------------------------------------------------------------------------------
local researchButton = empireFrame:FindFirstChild("ResearchOverlayButton")
if researchButton then
	local toggleTechTree = ReplicatedStorage:FindFirstChild("ToggleTechTree")
		or ReplicatedStorage:WaitForChild("ToggleTechTree", 10)
	if toggleTechTree then
		-- Activated works with mouse, touch and gamepad.
		researchButton.Activated:Connect(function()
			toggleTechTree:Fire()
		end)
		print("[EmpireOverlay] ResearchOverlayButton mit TechTreeGui verbunden")
	else
		warn("[EmpireOverlay] ToggleTechTree BindableEvent fehlt - TechTreeGuiController geladen?")
	end
else
	warn("[EmpireOverlay] ResearchOverlayButton fehlt in EmpireFrame")
end

print("[EmpireOverlay] === GUI Debug ===")
print("  EmpireFrame: " .. (empireFrame and "OK" or "FEHLT"))
print("  PlayerNameLable: " .. (playerNameLabel and "OK" or "FEHLT"))
print("  PlayerGoldLable: " .. (goldLabel and "OK" or "FEHLT"))
print("  PlayerArmyCountLable: " .. (armyLabel and "OK" or "FEHLT"))
print("  PlayerCampCountLable: " .. (campLabel and "OK" or "FEHLT"))
print("  PlayerCityCountLable: " .. (cityLabel and "OK" or "FEHLT"))

local function updateOverlay()
	if not getEmpireData then return end

	local success, data = pcall(function()
		return getEmpireData:InvokeServer()
	end)

	if not success or not data then
		return
	end

	if playerNameLabel then
		playerNameLabel.Text = data.playerName or "???"
	end
	if goldLabel then
		goldLabel.Text = "Gold: " .. tostring(data.gold or 0)
	end
	if armyLabel then
		armyLabel.Text = "Armeen: " .. tostring(data.armyCount or 0)
	end
	if campLabel then
		campLabel.Text = "Camps: " .. tostring(data.campCount or 0)
	end
	if cityLabel then
		cityLabel.Text = "Städte: " .. tostring(data.cityCount or 0)
	end
end

task.spawn(function()
	while true do
		task.wait(1)
		updateOverlay()
	end
end)

updateOverlay()

print("[EmpireOverlay] Bereit.")
