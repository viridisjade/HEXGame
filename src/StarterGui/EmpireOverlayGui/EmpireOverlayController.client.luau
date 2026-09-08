
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
-- DIPLOMATIE: der Diplomatie-Button togglet das Diplomatie-Fenster.
-- Der Button existiert nocht nicht in der EmpireFrame.rbxm, daher wird er zur
-- Laufzeit erzeugt (neben dem Research-Button), falls er fehlt.
local ClientState = require(ReplicatedStorage:WaitForChild("ClientState"))
local diplomacyButton = empireFrame:FindFirstChild("DiplomacyOverlayButton")
if not diplomacyButton then
	local researchBtn = empireFrame:FindFirstChild("ResearchOverlayButton")
	local newBtn = Instance.new("TextButton")
	newBtn.Name = "DiplomacyOverlayButton"
	newBtn.Size = researchBtn and researchBtn.Size or UDim2.fromOffset(140, 36)
	newBtn.Position = researchBtn
		and UDim2.new(researchBtn.Position.X.Scale, researchBtn.Position.X.Offset + researchBtn.Size.X.Offset + 8, researchBtn.Position.Y.Scale, researchBtn.Position.Y.Offset)
		or UDim2.new(1, -150, 0, 14)
	newBtn.BackgroundColor3 = Color3.fromRGB(45, 90, 160)
	newBtn.BorderSizePixel = 0
	newBtn.Font = Enum.Font.GothamBold
	newBtn.TextSize = 14
	newBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	newBtn.Text = "🤝 Diplomatie"
	newBtn.Parent = empireFrame
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = newBtn
	diplomacyButton = newBtn
	print("[EmpireOverlay] DiplomacyOverlayButton erzeugt (fehlte in EmpireFrame.rbxm)")
end
diplomacyButton.Activated:Connect(function()
	ClientState.FireToggleDiplomacy()
end)
print("[EmpireOverlay] DiplomacyOverlayButton mit DiplomatieGui verbunden")

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
