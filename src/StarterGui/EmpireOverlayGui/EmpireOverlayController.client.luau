
--[[
    EmpireOverlayController (LocalScript)
    Ort: StarterGui > EmpireOverlayGui > EmpireOverlayController
    
    Befüllt das EmpireOverlayGui mit den Spieler-Statistiken.
    Aktualisiert alle 1 Sekunde.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientState = require(ReplicatedStorage:WaitForChild("ClientState"))

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
-- DIPLOMATIE: der Diplomatie-Button togglet das Diplomatie-Fenster.
-- Der Button existiert nicht in der EmpireFrame.rbxm, daher wird er zur Laufzeit
-- erzeugt (neben dem Research-Button), falls er nicht gefunden wird.
--------------------------------------------------------------------------------
local diplomacyButton = empireFrame:FindFirstChild("DiplomacyOverlayButton")

if not diplomacyButton then
	local researchBtn = empireFrame:FindFirstChild("ResearchOverlayButton")
	local newBtn = Instance.new("TextButton")
	newBtn.Name = "DiplomacyOverlayButton"

	if researchBtn then
		-- Neben dem Research-Button: rechte Kante + Abstand.
		newBtn.Size = researchBtn.Size
		newBtn.Position = UDim2.new(
			researchBtn.Position.X.Scale,
			researchBtn.Position.X.Offset + researchBtn.Size.X.Offset + 8,
			researchBtn.Position.Y.Scale,
			researchBtn.Position.Y.Offset
		)
	else
		newBtn.Size = UDim2.fromOffset(140, 36)
		newBtn.Position = UDim2.new(1, -150, 0, 14)
	end

	newBtn.BackgroundColor3 = Color3.fromRGB(45, 90, 160)
	newBtn.BorderSizePixel = 0
	newBtn.Font = Enum.Font.GothamBold
	newBtn.TextSize = 14
	newBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	newBtn.Text = "🤝 Diplomatie"

	-- Sicherstellen, dass der Button Klicks empfangen kann.
	newBtn.Active = true
	newBtn.AutoButtonColor = true
	newBtn.Interactable = true

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = newBtn

	newBtn.Parent = empireFrame
	diplomacyButton = newBtn
	print("[EmpireOverlay] DiplomacyOverlayButton erzeugt (fehlte in EmpireFrame.rbxm)")
end

-- Falls der gefundene Button nicht klickbar war, reparieren.
diplomacyButton.Active = true
diplomacyButton.AutoButtonColor = true
diplomacyButton.Interactable = true

-- Toggle (oeffnen/schliessen): Das Diplomatie-Fenster wird DIREKT ueber die
-- PlayerGui > DiplomacyGui ScreenGui umgeschaltet (garantiert), damit der Klick
-- auch dann funktioniert, wenn der DiplomacyGuiController (aus irgendeinem
-- Grund) das BindableEvent noch nicht konsumiert. Das ClientState-Event wird
-- zusaetzlich gefeuert, damit der Controller beim Oeffnen die Daten nachlaedt.
diplomacyButton.Activated:Connect(function()
	local PlayersService = game:GetService("Players")
	local playerGui = PlayersService.LocalPlayer and PlayersService.LocalPlayer:FindFirstChild("PlayerGui")
	local dipGui = playerGui and playerGui:FindFirstChild("DiplomacyGui")

	if dipGui then
		dipGui.Enabled = not dipGui.Enabled
		print("[EmpireOverlay] DiplomacyGui direkt: Enabled = " .. tostring(dipGui.Enabled))
	else
		warn("[EmpireOverlay] DiplomacyGui nicht in PlayerGui gefunden - nutze nur Event-Pfad")
	end

	ClientState.FireToggleDiplomacy()
end)
print("[EmpireOverlay] DiplomacyOverlayButton mit DiplomatieGui verbunden")

--------------------------------------------------------------------------------
-- TECH TREE: der Research-Button togglet das TechTreeGui.
--------------------------------------------------------------------------------
local researchButton = empireFrame:FindFirstChild("ResearchOverlayButton")
if researchButton then
	researchButton.Active = true
	researchButton.AutoButtonColor = true
	researchButton.Interactable = true

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
