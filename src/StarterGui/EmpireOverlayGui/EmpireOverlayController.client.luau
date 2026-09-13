--[[
    EmpireOverlayController (LocalScript)
    Ort: StarterGui > EmpireOverlayGui > EmpireOverlayController

    KOMPLETT CODE-GENERIERTES EmpireOverlayGui im Fantasy-Stil (wie CityGui,
    ArmyGui, DiplomacyGui, VictoryGui, TechTreeGui): alle Elemente werden per
    Instance.new() erzeugt, nichts wird mehr manuell in Studio gebaut.

    LAYOUT: kompaktes, NICHT-SPERRENDES 2-Zeilen-Overlay oben rechts
    (kein Vollbild-Menu, kein abdunkelndes Overlay - der Spieler kann
    weiterhin normal spielen, waehrend das Overlay sichtbar ist):

      Zeile 1 (StatsRow):
        👑 Spielername | 💰 Gold | 🔬 Forschung/Runde | ⚔️ Armeen |
        🏛️ Staedte | 🏕️ Camps | 🏆 Punkte/Ziel

      Zeile 2 (ActionRow):
        Punkte-Fortschrittsbalken (links, fuellt den Platz) |
        ResearchOverlayButton | DiplomacyOverlayButton

    FUNKTIONALITAET (unveraendert zur Vorversion, nur neues Design):
      - Aktualisiert Gold/Forschung/Armeen/Staedte/Camps/Punkte 1x/Sekunde
        ueber GetEmpireData (RemoteFunction).
      - ResearchOverlayButton feuert das ToggleTechTree BindableEvent.
      - DiplomacyOverlayButton oeffnet/schliesst das DiplomacyGui (inkl.
        Platzhalter-Erzeugung, falls das DiplomacyGui/-Overlay fehlt).
      - Punkte-Fortschrittsbalken zeigt den Fortschritt zum Solo-Sieg
        (VictoryConfig.SOLO_WIN_POINTS).
      - PointsUpdate / CapitalCityMarked / PlayerEliminated Remote-Events
        werden weiterhin an ClientState weitergereicht.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientState = require(ReplicatedStorage:WaitForChild("ClientState"))
local VictoryConfig = require(ReplicatedStorage:WaitForChild("VictoryConfig"))
local Net = require(ReplicatedStorage:WaitForChild("Net"))

local dataRemotes = ReplicatedStorage:WaitForChild("DataRemotes")
local getEmpireData = dataRemotes:FindFirstChild("GetEmpireData")

local SOLO_WIN = VictoryConfig.SOLO_WIN_POINTS or 1000

--------------------------------------------------------------------------------
-- GUI-Wurzel finden + alles Alte entfernen (CLEANUP)
--
-- Loescht ALLE Children von EmpireOverlayGui (die alte EmpireFrame.rbxm inkl.
-- aller verschachtelten statischen Elemente) - NUR dieses Script selbst
-- bleibt erhalten. Alle GUI-Elemente werden im Folgenden komplett neu per
-- Code erzeugt.
--------------------------------------------------------------------------------
local gui = script.Parent

for _, child in ipairs(gui:GetChildren()) do
	if child ~= script then
		child:Destroy()
	end
end

gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true

--------------------------------------------------------------------------------
-- FANTASY-FARBSCHEMA (identisch zur CityGui)
--------------------------------------------------------------------------------
local COLORS = {
	windowBg    = Color3.fromRGB(35, 28, 22),
	panelBg     = Color3.fromRGB(50, 40, 32),
	panelBorder = Color3.fromRGB(120, 90, 50),

	playerName = Color3.fromRGB(255, 220, 150),
	gold       = Color3.fromRGB(255, 200, 80),
	research   = Color3.fromRGB(150, 180, 250),
	army       = Color3.fromRGB(220, 140, 60),
	city       = Color3.fromRGB(200, 170, 100),
	camp       = Color3.fromRGB(180, 140, 80),
	points     = Color3.fromRGB(255, 220, 150),

	barBg   = Color3.fromRGB(60, 50, 40),
	barFill = Color3.fromRGB(255, 200, 80),

	btnNormal = Color3.fromRGB(70, 55, 40),
	btnHover  = Color3.fromRGB(100, 80, 55),
	btnText   = Color3.fromRGB(255, 220, 150),
}

local FONT_TITLE = Enum.Font.FredokaOne
local FONT_VALUE = Enum.Font.GothamBold
local FONT_DESC  = Enum.Font.Gotham

--------------------------------------------------------------------------------
-- HILFSFUNKTIONEN
--------------------------------------------------------------------------------
local function makeCorner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = parent
	return c
end

local function makeStroke(parent, thickness, color, transparency)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness or 1
	s.Color = color or COLORS.panelBorder
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function wireButtonStyle(button)
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.BackgroundColor3 = COLORS.btnNormal

	button.MouseEnter:Connect(function()
		button.BackgroundColor3 = COLORS.btnHover
	end)
	button.MouseLeave:Connect(function()
		button.BackgroundColor3 = COLORS.btnNormal
	end)
end

--------------------------------------------------------------------------------
-- EMPIRE-FENSTER (Haupt-Container) - kompakt, oben rechts, nicht-sperrend
--------------------------------------------------------------------------------
local empireFrame = Instance.new("Frame")
empireFrame.Name = "EmpireFrame"
empireFrame.Size = UDim2.new(0.4, 0, 0, 110)
empireFrame.Position = UDim2.new(1, -10, 0, 10)
empireFrame.AnchorPoint = Vector2.new(1, 0)
empireFrame.BackgroundColor3 = COLORS.windowBg
empireFrame.BackgroundTransparency = 0.15
empireFrame.BorderSizePixel = 0
empireFrame.Parent = gui
makeCorner(empireFrame, 12)
makeStroke(empireFrame, 3, COLORS.panelBorder)

local outerPadding = Instance.new("UIPadding")
outerPadding.PaddingTop = UDim.new(0, 8)
outerPadding.PaddingBottom = UDim.new(0, 8)
outerPadding.PaddingLeft = UDim.new(0, 8)
outerPadding.PaddingRight = UDim.new(0, 8)
outerPadding.Parent = empireFrame

local outerLayout = Instance.new("UIListLayout")
outerLayout.Padding = UDim.new(0, 6)
outerLayout.SortOrder = Enum.SortOrder.LayoutOrder
outerLayout.Parent = empireFrame

--------------------------------------------------------------------------------
-- ZEILE 1: STATS-ROW
--------------------------------------------------------------------------------
local statsRow = Instance.new("Frame")
statsRow.Name = "StatsRow"
statsRow.LayoutOrder = 1
statsRow.Size = UDim2.new(1, 0, 0, 30)
statsRow.BackgroundColor3 = COLORS.panelBg
statsRow.BorderSizePixel = 0
statsRow.Parent = empireFrame
makeCorner(statsRow, 8)
makeStroke(statsRow, 1, COLORS.panelBorder)

local statsPadding = Instance.new("UIPadding")
statsPadding.PaddingLeft = UDim.new(0, 8)
statsPadding.PaddingRight = UDim.new(0, 8)
statsPadding.Parent = statsRow

local statsLayout = Instance.new("UIListLayout")
statsLayout.FillDirection = Enum.FillDirection.Horizontal
statsLayout.Padding = UDim.new(0, 14)
statsLayout.SortOrder = Enum.SortOrder.LayoutOrder
statsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
statsLayout.Parent = statsRow

local function makeStat(order, name, text, color, font)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.LayoutOrder = order
	l.AutomaticSize = Enum.AutomaticSize.X
	l.Size = UDim2.new(0, 0, 1, 0)
	l.BackgroundTransparency = 1
	l.Font = font or FONT_VALUE
	l.TextSize = 14
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.Parent = statsRow
	return l
end

local playerNameLabel = makeStat(1, "PlayerNameLable", "👑 Spieler", COLORS.playerName, FONT_TITLE)
local goldLabel        = makeStat(2, "PlayerGoldLable", "💰 0", COLORS.gold)
local researchLabel    = makeStat(3, "EmpireResearchLable", "🔬 0RP", COLORS.research)
local armyLabel        = makeStat(4, "PlayerArmyCountLable", "⚔️ 0", COLORS.army)
local cityLabel        = makeStat(5, "PlayerCityCountLable", "🏛️ 0", COLORS.city)
local campLabel        = makeStat(6, "PlayerCampCountLable", "🏕️ 0", COLORS.camp)
local pointsLabel      = makeStat(7, "PlayerPointsLable", "🏆 0/" .. SOLO_WIN, COLORS.points)

--------------------------------------------------------------------------------
-- ZEILE 2: ACTION-ROW (Fortschrittsbalken links + Buttons rechts)
--------------------------------------------------------------------------------
local actionRow = Instance.new("Frame")
actionRow.Name = "ActionRow"
actionRow.LayoutOrder = 2
actionRow.Size = UDim2.new(1, 0, 0, 36)
actionRow.BackgroundColor3 = COLORS.panelBg
actionRow.BorderSizePixel = 0
actionRow.Parent = empireFrame
makeCorner(actionRow, 8)
makeStroke(actionRow, 1, COLORS.panelBorder)

local actionPadding = Instance.new("UIPadding")
actionPadding.PaddingLeft = UDim.new(0, 8)
actionPadding.PaddingRight = UDim.new(0, 8)
actionPadding.Parent = actionRow

local actionLayout = Instance.new("UIListLayout")
actionLayout.FillDirection = Enum.FillDirection.Horizontal
actionLayout.Padding = UDim.new(0, 8)
actionLayout.SortOrder = Enum.SortOrder.LayoutOrder
actionLayout.VerticalAlignment = Enum.VerticalAlignment.Center
actionLayout.Parent = actionRow

-- Punkte-Fortschrittsbalken (links, fuellt den restlichen Platz)
local pointsBar = Instance.new("Frame")
pointsBar.Name = "VictoryProgressBar"
pointsBar.LayoutOrder = 1
pointsBar.Size = UDim2.new(1, -300, 0, 16)
pointsBar.BackgroundColor3 = COLORS.barBg
pointsBar.BorderSizePixel = 0
pointsBar.Parent = actionRow
makeCorner(pointsBar, 6)

local barInner = Instance.new("Frame")
barInner.Name = "Bar"
barInner.Size = UDim2.fromScale(0, 1)
barInner.BackgroundColor3 = COLORS.barFill
barInner.BorderSizePixel = 0
barInner.Parent = pointsBar
makeCorner(barInner, 6)

local barText = Instance.new("TextLabel")
barText.Name = "BarText"
barText.Size = UDim2.fromScale(1, 1)
barText.BackgroundTransparency = 1
barText.Font = FONT_DESC
barText.TextSize = 12
barText.TextColor3 = Color3.new(1, 1, 1)
barText.Text = "0%"
barText.Parent = pointsBar

-- ResearchOverlayButton
local researchButton = Instance.new("TextButton")
researchButton.Name = "ResearchOverlayButton"
researchButton.LayoutOrder = 2
researchButton.Size = UDim2.new(0, 140, 0, 30)
researchButton.Font = FONT_VALUE
researchButton.TextSize = 12
researchButton.TextColor3 = COLORS.btnText
researchButton.Text = "🔬 Forschung"
researchButton.Parent = actionRow
makeCorner(researchButton, 6)
makeStroke(researchButton, 1, COLORS.panelBorder)
wireButtonStyle(researchButton)

-- DiplomacyOverlayButton
local diplomacyButton = Instance.new("TextButton")
diplomacyButton.Name = "DiplomacyOverlayButton"
diplomacyButton.LayoutOrder = 3
diplomacyButton.Size = UDim2.new(0, 140, 0, 30)
diplomacyButton.Font = FONT_VALUE
diplomacyButton.TextSize = 12
diplomacyButton.TextColor3 = COLORS.btnText
diplomacyButton.Text = "🤝 Diplomatie"
diplomacyButton.Parent = actionRow
makeCorner(diplomacyButton, 6)
makeStroke(diplomacyButton, 1, COLORS.panelBorder)
wireButtonStyle(diplomacyButton)

--------------------------------------------------------------------------------
-- DIPLOMATIE: der Diplomatie-Button togglet das Diplomatie-Fenster.
-- Das DiplomacyGui (eigene ScreenGui) ist komplett code-generiert und
-- verwaltet sein Enabled/Toggle-Verhalten selbst (analog zu ToggleTechTree).
-- Der Button muss daher nur noch das gemeinsame ClientState-Event feuern.
--------------------------------------------------------------------------------
diplomacyButton.Active = true
diplomacyButton.AutoButtonColor = true
diplomacyButton.Interactable = true

diplomacyButton.Activated:Connect(function()
	ClientState.FireToggleDiplomacy()
end)
print("[EmpireOverlay] DiplomacyOverlayButton mit DiplomatieGui verbunden")

--------------------------------------------------------------------------------
-- TECH TREE: der Research-Button togglet das TechTreeGui.
--------------------------------------------------------------------------------
researchButton.Active = true
researchButton.AutoButtonColor = true
researchButton.Interactable = true

do
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
end

--------------------------------------------------------------------------------
-- DATEN-UPDATE (1x pro Sekunde)
--------------------------------------------------------------------------------
local function updateOverlay()
	if not getEmpireData then return end

	local success, data = pcall(function()
		return getEmpireData:InvokeServer()
	end)

	if not success or not data then
		return
	end

	playerNameLabel.Text = "👑 " .. (data.playerName or "???")
	goldLabel.Text = "💰 " .. tostring(data.gold or 0)
	researchLabel.Text = "🔬 " .. tostring(data.researchPerRound or 0) .. "RP"
	armyLabel.Text = "⚔️ " .. tostring(data.armyCount or 0)
	cityLabel.Text = "🏛️ " .. tostring(data.cityCount or 0)
	campLabel.Text = "🏕️ " .. tostring(data.campCount or 0)

	local points = data.points or 0
	pointsLabel.Text = "🏆 " .. tostring(points) .. "/" .. SOLO_WIN

	local frac = math.clamp(points / SOLO_WIN, 0, 1)
	barInner.Size = UDim2.fromScale(frac, 1)
	barText.Text = math.floor(frac * 100) .. "%"
end

task.spawn(function()
	while true do
		task.wait(1)
		updateOverlay()
	end
end)

updateOverlay()

--------------------------------------------------------------------------------
-- VICTORY REMOTES -> ClientState (lokal, fuer andere GUIs).
--------------------------------------------------------------------------------
Net.On("PointsUpdate", function(payload)
	if not payload then return end
	ClientState.SetPoints(payload.points, payload.reason, payload.delta)
end)
Net.On("CapitalCityMarked", function(payload)
	if not payload then return end
	ClientState.SetCapitalCityId(payload.cityId)
end)
Net.On("PlayerEliminated", function(payload)
	if not payload then return end
	if payload.playerId == game:GetService("Players").LocalPlayer.UserId then
		ClientState.SetEliminated(true)
	end
end)

print("[EmpireOverlay] Bereit (code-generiert, Fantasy-Stil, 2-Zeilen-Layout).")
