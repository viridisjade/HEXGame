--[[
    ArmyPanel (LocalScript)
    Ort: StarterGui > ArmyGui > ArmyPanel

    KOMPLETT CODE-GENERIERTE ArmyGui im Fantasy-Stil (wie CityGui,
    DiplomacyGui, VictoryGui, TechTreeGui): alle Elemente werden per
    Instance.new() erzeugt, nichts wird mehr manuell in Studio gebaut.

    LAYOUT: schmale, NICHT-SPERRENDE Info-Tafel am rechten Bildschirmrand
    (kein zentriertes Vollbild-Menu, kein abdunkelndes Overlay - der Spieler
    kann weiterhin auf die Karte klicken, waehrend die GUI offen ist):
      Header      - Armee-Name + Close-Button
      StatsBar    - Gesamt-HP/Attack/Defense/Sight/Movement (Grid) + HP-Balken
      UnitSlots   - dynamisches Grid (3 pro Reihe, schmale Spalte),
                    Anzahl = maxUnits (Basis 8 + Logistics-Tech-Bonus,
                    siehe ArmySystem.GetMaxUnits)
      UnitDetails (oben im unteren Bereich) - Stats der ausgewaehlten Unit
      Actions     (darunter gestapelt) - Camp bauen / Auswahl aufheben /
                    Kampf ansehen / HoverUnitImage-Vorschau

    FUNKTIONALITAET (unveraendert zur Vorversion, nur neues Design/Layout):
      - Dynamische Unit-Slots, Anzahl passt sich an maxUnits an
        (UIGridLayout wird bei Aenderung neu gebaut, z.B. Logistics-Tech)
      - Klick auf belegten Slot -> Unit auswaehlen -> Details anzeigen
      - HoverUnitImage zeigt die ausgewaehlte Unit dauerhaft; ohne Auswahl
        zeigt es transient die Unit unter dem Mauszeiger
      - StopSelectButton hebt die Auswahl auf
      - BuildCampButton ist immer sichtbar/klickbar (ausser im Kampf)
      - Army-Stats aktualisieren sich live ueber ArmyDataCache
      - Kampf-Lock (InCombat-Label + "Kampf ansehen"-Button) bleibt erhalten
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local State = require(ReplicatedStorage:WaitForChild("ClientState"))
local ArmyDataCache = require(ReplicatedStorage:WaitForChild("ArmyDataCache"))
local Net = require(ReplicatedStorage:WaitForChild("Net"))

--------------------------------------------------------------------------------
-- GUI-Wurzel finden + alles Alte entfernen (CLEANUP)
--
-- Loescht ALLE Children von ArmyGui (Frames, Labels, Buttons, UICorners,
-- die alte MainframeArmy inkl. aller verschachtelten statischen Elemente)
-- - NUR dieses Script selbst bleibt erhalten. Ab hier darf NICHTS mehr auf
-- die alten Elemente zugreifen (z.B. frame:FindFirstChild("ArmyStatFrame")).
-- Alle GUI-Elemente werden im Folgenden komplett neu per Code erzeugt.
--------------------------------------------------------------------------------
local gui = script.Parent:IsA("ScreenGui")
	and script.Parent
	or script.Parent:FindFirstAncestorWhichIsA("ScreenGui")

if not gui then
	warn("[ArmyPanel] Keine ScreenGui gefunden!")
	return
end

gui.Enabled = false
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true

for _, child in ipairs(gui:GetChildren()) do
	if child ~= script then
		child:Destroy()
	end
end

--------------------------------------------------------------------------------
-- FANTASY-FARBSCHEMA (identisch zur CityGui)
--------------------------------------------------------------------------------
local COLORS = {
	windowBg     = Color3.fromRGB(35, 28, 22),
	panelBg      = Color3.fromRGB(50, 40, 32),
	panelBorder  = Color3.fromRGB(120, 90, 50),

	headerBg     = Color3.fromRGB(80, 60, 40),
	headerText   = Color3.fromRGB(255, 220, 150),

	hp        = Color3.fromRGB(200, 60, 60),
	attack    = Color3.fromRGB(220, 140, 60),
	defense   = Color3.fromRGB(100, 150, 200),
	sight     = Color3.fromRGB(150, 200, 100),
	movement  = Color3.fromRGB(200, 180, 100),

	slotFilledBg     = Color3.fromRGB(60, 50, 40),
	slotFilledBorder = Color3.fromRGB(120, 90, 50), -- bronze
	slotEmptyBg      = Color3.fromRGB(40, 35, 30),
	slotEmptyBorder  = Color3.fromRGB(70, 65, 60),
	slotSelectedBg   = Color3.fromRGB(80, 65, 45),
	slotSelectedBorder = Color3.fromRGB(255, 220, 150),

	hpBarGood    = Color3.fromRGB(120, 200, 110),
	hpBarWarn    = Color3.fromRGB(220, 200, 80),
	hpBarBad     = Color3.fromRGB(200, 70, 70),

	btnNormal    = Color3.fromRGB(70, 55, 40),
	btnHover     = Color3.fromRGB(100, 80, 55),
	btnPressed   = Color3.fromRGB(50, 40, 30),
	btnDisabled  = Color3.fromRGB(45, 40, 35),
	btnText      = Color3.fromRGB(255, 220, 150),

	textDim      = Color3.fromRGB(200, 185, 165),
}

local FONT_TITLE = Enum.Font.FredokaOne
local FONT_VALUE = Enum.Font.GothamBold
local FONT_DESC  = Enum.Font.Gotham

--------------------------------------------------------------------------------
-- SLOT-KONFIGURATION (zentral, anpassbar)
--------------------------------------------------------------------------------
local SLOT_CONFIG = {
	SLOTS_PER_ROW  = 3, -- schmales 280px-Fenster: 3 statt 5 Slots pro Reihe
	SLOT_SIZE      = UDim2.new(0, 74, 0, 78),
	SLOT_PADDING   = UDim2.new(0, 6, 0, 6),
	MAX_UNITS      = 99, -- harte Obergrenze gegen Spam
}

--------------------------------------------------------------------------------
-- HILFSFUNKTIONEN
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

local function makeCorner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = parent
	return c
end

local function makeStroke(parent, thickness, color, transparency)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness or 2
	s.Color = color or COLORS.panelBorder
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function wireButtonStyle(button, colorSet)
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.BackgroundColor3 = colorSet.normal

	button.MouseEnter:Connect(function()
		if button:GetAttribute("Disabled") then return end
		button.BackgroundColor3 = colorSet.hover
	end)
	button.MouseLeave:Connect(function()
		if button:GetAttribute("Disabled") then return end
		button.BackgroundColor3 = colorSet.normal
	end)
	button.MouseButton1Down:Connect(function()
		if button:GetAttribute("Disabled") then return end
		button.BackgroundColor3 = colorSet.pressed
	end)
	button.MouseButton1Up:Connect(function()
		if button:GetAttribute("Disabled") then return end
		button.BackgroundColor3 = colorSet.hover
	end)
end

local function setButtonEnabled(button, colorSet, enabled)
	button:SetAttribute("Disabled", not enabled)
	button.Active = enabled
	if enabled then
		button.BackgroundColor3 = colorSet.normal
		button.TextTransparency = 0
	else
		button.BackgroundColor3 = colorSet.disabled
		button.TextTransparency = 0.5
	end
end

local ACTION_COLORS = {
	normal = COLORS.btnNormal, hover = COLORS.btnHover,
	pressed = COLORS.btnPressed, disabled = COLORS.btnDisabled,
}

--------------------------------------------------------------------------------
-- ARMY-FENSTER
--
-- Schmale, nicht-sperrende Info-Tafel am rechten Bildschirmrand (kein
-- zentriertes Vollbild-Menu, kein abdunkelndes Overlay). Das Spiel laeuft
-- normal weiter, waehrend die GUI offen ist - der Spieler kann weiterhin
-- auf die Karte klicken.
--------------------------------------------------------------------------------
local armyWindow = Instance.new("Frame")
armyWindow.Name = "ArmyWindow"
armyWindow.Size = UDim2.new(0, 280, 0.55, 0)
armyWindow.Position = UDim2.new(1, -290, 0.5, 0)
armyWindow.AnchorPoint = Vector2.new(0, 0.5)
armyWindow.BackgroundColor3 = COLORS.windowBg
armyWindow.BackgroundTransparency = 0.15
armyWindow.BorderSizePixel = 0
armyWindow.Parent = gui
makeCorner(armyWindow, 12)
makeStroke(armyWindow, 3, COLORS.panelBorder)

--------------------------------------------------------------------------------
-- HEADER (kompakt, fuer die schmale Breite)
--------------------------------------------------------------------------------
local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 36)
header.Position = UDim2.new(0, 0, 0, 0)
header.BackgroundColor3 = COLORS.headerBg
header.BorderSizePixel = 0
header.Parent = armyWindow
makeCorner(header, 12)

-- Deckel-Frame, damit die untere Rundung des Headers nicht sichtbar ist.
local headerCornerFix = Instance.new("Frame")
headerCornerFix.Name = "CornerFix"
headerCornerFix.Size = UDim2.new(1, 0, 0, 12)
headerCornerFix.Position = UDim2.new(0, 0, 1, -12)
headerCornerFix.BackgroundColor3 = COLORS.headerBg
headerCornerFix.BorderSizePixel = 0
headerCornerFix.ZIndex = 0
headerCornerFix.Parent = header

local nameLabel = Instance.new("TextLabel")
nameLabel.Name = "ArmyNameLabel"
nameLabel.Size = UDim2.new(1, -40, 1, 0)
nameLabel.Position = UDim2.new(0, 10, 0, 0)
nameLabel.BackgroundTransparency = 1
nameLabel.Font = FONT_TITLE
nameLabel.TextSize = 15
nameLabel.TextColor3 = COLORS.headerText
nameLabel.TextXAlignment = Enum.TextXAlignment.Left
nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
nameLabel.Text = "⚔️ Armee"
nameLabel.Parent = header

local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.Size = UDim2.fromOffset(24, 24)
closeButton.Position = UDim2.new(1, -30, 0.5, -12)
closeButton.BackgroundColor3 = Color3.fromRGB(120, 55, 55)
closeButton.Font = FONT_VALUE
closeButton.TextSize = 13
closeButton.TextColor3 = Color3.new(1, 1, 1)
closeButton.Text = "✕"
closeButton.BorderSizePixel = 0
closeButton.Parent = header
makeCorner(closeButton, 6)

closeButton.Activated:Connect(function()
	State.Clear()
end)

--------------------------------------------------------------------------------
-- KAMPF-LOCK: Label (als erste Zeile im Body, ueber der ganzen Breite)
--------------------------------------------------------------------------------
local combatLabel = Instance.new("TextLabel")
combatLabel.Name = "InCombatLabel"
combatLabel.LayoutOrder = 0
combatLabel.Size = UDim2.new(1, 0, 0, 18)
combatLabel.BackgroundTransparency = 1
combatLabel.Font = FONT_VALUE
combatLabel.TextSize = 12
combatLabel.TextColor3 = Color3.fromRGB(255, 120, 90)
combatLabel.TextXAlignment = Enum.TextXAlignment.Center
combatLabel.Text = "⚔️ IM KAMPF"
combatLabel.Visible = false

--------------------------------------------------------------------------------
-- BODY-CONTAINER (scrollbar, da das Fenster jetzt schmal + niedrig ist)
--------------------------------------------------------------------------------
local body = Instance.new("ScrollingFrame")
body.Name = "Body"
body.Size = UDim2.new(1, -12, 1, -42)
body.Position = UDim2.new(0, 6, 0, 38)
body.BackgroundTransparency = 1
body.BorderSizePixel = 0
body.ScrollBarThickness = 4
body.ScrollBarImageColor3 = COLORS.panelBorder
body.CanvasSize = UDim2.new()
body.AutomaticCanvasSize = Enum.AutomaticSize.Y
body.Parent = armyWindow
combatLabel.Parent = body
ensure(body, "UIListLayout", "Layout", function(l)
	l.Padding = UDim.new(0, 6)
	l.SortOrder = Enum.SortOrder.LayoutOrder
end)

--------------------------------------------------------------------------------
-- STATS-BAR (Gesamt-Armee-Werte) - kompakt, 3 Werte pro Zeile (Grid statt
-- einer breiten horizontalen Reihe, damit alles in 280px Breite passt)
--------------------------------------------------------------------------------
local statsBar = Instance.new("Frame")
statsBar.Name = "StatsBar"
statsBar.LayoutOrder = 1
statsBar.Size = UDim2.new(1, 0, 0, 66)
statsBar.BackgroundColor3 = COLORS.panelBg
statsBar.BorderSizePixel = 0
statsBar.Parent = body
makeCorner(statsBar, 8)
makeStroke(statsBar, 2, COLORS.panelBorder)
ensure(statsBar, "UIPadding", "Padding", function(p)
	p.PaddingTop = UDim.new(0, 6)
	p.PaddingBottom = UDim.new(0, 6)
	p.PaddingLeft = UDim.new(0, 8)
	p.PaddingRight = UDim.new(0, 8)
end)

local statsRow = Instance.new("Frame")
statsRow.Name = "StatsRow"
statsRow.Size = UDim2.new(1, 0, 0, 36)
statsRow.BackgroundTransparency = 1
statsRow.Parent = statsBar
ensure(statsRow, "UIGridLayout", "Layout", function(l)
	l.FillDirection = Enum.FillDirection.Horizontal
	l.FillDirectionMaxCells = 3
	l.CellSize = UDim2.new(0, 82, 0, 16)
	l.CellPadding = UDim2.new(0, 4, 0, 4)
	l.SortOrder = Enum.SortOrder.LayoutOrder
end)

local function makeStatLabel(order, icon, color)
	local l = Instance.new("TextLabel")
	l.Name = "Stat_" .. order
	l.LayoutOrder = order
	l.BackgroundTransparency = 1
	l.Font = FONT_VALUE
	l.TextSize = 12
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = icon .. " 0"
	l.Parent = statsRow
	return l
end

local lblHealth   = makeStatLabel(1, "❤️", COLORS.hp)
local lblAttack   = makeStatLabel(2, "⚔️", COLORS.attack)
local lblDefense  = makeStatLabel(3, "🛡️", COLORS.defense)
local lblSight    = makeStatLabel(4, "👁️", COLORS.sight)
local lblMove     = makeStatLabel(5, "🏃", COLORS.movement)

local hpBarBg = Instance.new("Frame")
hpBarBg.Name = "HpBarBg"
hpBarBg.Size = UDim2.new(1, 0, 0, 12)
hpBarBg.Position = UDim2.new(0, 0, 0, 42)
hpBarBg.BackgroundColor3 = Color3.fromRGB(30, 25, 20)
hpBarBg.BorderSizePixel = 0
hpBarBg.Parent = statsBar
makeCorner(hpBarBg, 4)

local hpBarFill = Instance.new("Frame")
hpBarFill.Name = "Fill"
hpBarFill.Size = UDim2.new(0, 0, 1, 0)
hpBarFill.BackgroundColor3 = COLORS.hpBarGood
hpBarFill.BorderSizePixel = 0
hpBarFill.Parent = hpBarBg
makeCorner(hpBarFill, 4)

local hpBarText = Instance.new("TextLabel")
hpBarText.Name = "HpBarText"
hpBarText.Size = UDim2.fromScale(1, 1)
hpBarText.BackgroundTransparency = 1
hpBarText.Font = FONT_DESC
hpBarText.TextSize = 11
hpBarText.TextColor3 = Color3.new(1, 1, 1)
hpBarText.Text = ""
hpBarText.Parent = hpBarBg

--------------------------------------------------------------------------------
-- UNIT-SLOTS-CONTAINER (dynamisches Grid)
--------------------------------------------------------------------------------
local slotsPanel = Instance.new("Frame")
slotsPanel.Name = "UnitSlotsPanel"
slotsPanel.LayoutOrder = 2
slotsPanel.AutomaticSize = Enum.AutomaticSize.Y
slotsPanel.Size = UDim2.new(1, 0, 0, 0)
slotsPanel.BackgroundColor3 = COLORS.panelBg
slotsPanel.BorderSizePixel = 0
slotsPanel.Parent = body
makeCorner(slotsPanel, 8)
makeStroke(slotsPanel, 2, COLORS.panelBorder)
ensure(slotsPanel, "UIPadding", "Padding", function(p)
	p.PaddingTop = UDim.new(0, 10)
	p.PaddingBottom = UDim.new(0, 10)
	p.PaddingLeft = UDim.new(0, 10)
	p.PaddingRight = UDim.new(0, 10)
end)

local slotsHeader = Instance.new("TextLabel")
slotsHeader.Name = "SlotsHeader"
slotsHeader.LayoutOrder = 1
slotsHeader.Size = UDim2.new(1, 0, 0, 20)
slotsHeader.BackgroundTransparency = 1
slotsHeader.Font = FONT_VALUE
slotsHeader.TextSize = 12
slotsHeader.TextColor3 = COLORS.headerText
slotsHeader.TextXAlignment = Enum.TextXAlignment.Left
slotsHeader.Text = "🪖 UNITS"
slotsHeader.Parent = slotsPanel

local slotsContainer = Instance.new("Frame")
slotsContainer.Name = "UnitSlotsContainer"
slotsContainer.LayoutOrder = 2
slotsContainer.Position = UDim2.new(0, 0, 0, 24)
slotsContainer.AutomaticSize = Enum.AutomaticSize.Y
slotsContainer.Size = UDim2.new(1, 0, 0, 0)
slotsContainer.BackgroundTransparency = 1
slotsContainer.Parent = slotsPanel

local slotsLayout = Instance.new("UIGridLayout")
slotsLayout.FillDirection = Enum.FillDirection.Horizontal
slotsLayout.FillDirectionMaxCells = SLOT_CONFIG.SLOTS_PER_ROW
slotsLayout.CellSize = SLOT_CONFIG.SLOT_SIZE
slotsLayout.CellPadding = SLOT_CONFIG.SLOT_PADDING
slotsLayout.SortOrder = Enum.SortOrder.LayoutOrder
slotsLayout.Parent = slotsContainer

-- Der SlotsPanel selbst hat AutomaticSize.Y, aber der Container braucht
-- eine feste Hoehe abhaengig von der Zeilenzahl (Grid hat kein AutomaticSize
-- fuer den Elternteil in Studio zuverlaessig) - wir setzen die Hoehe manuell
-- bei jedem Grid-Rebuild (siehe renderUnitSlots).

--------------------------------------------------------------------------------
-- UNTERER BEREICH: UnitDetailsPanel + ActionsPanel UNTEREINANDER gestapelt
-- (statt nebeneinander) - passt so in die schmale 280px-Spalte.
--------------------------------------------------------------------------------
local lowerRow = Instance.new("Frame")
lowerRow.Name = "LowerRow"
lowerRow.LayoutOrder = 3
lowerRow.AutomaticSize = Enum.AutomaticSize.Y
lowerRow.Size = UDim2.new(1, 0, 0, 0)
lowerRow.BackgroundTransparency = 1
lowerRow.Parent = body
ensure(lowerRow, "UIListLayout", "Layout", function(l)
	l.FillDirection = Enum.FillDirection.Vertical
	l.Padding = UDim.new(0, 6)
	l.SortOrder = Enum.SortOrder.LayoutOrder
end)

-- UNIT-DETAILS-PANEL (oben)
local unitFrame = Instance.new("Frame")
unitFrame.Name = "UnitDetailsPanel"
unitFrame.LayoutOrder = 1
unitFrame.AutomaticSize = Enum.AutomaticSize.Y
unitFrame.Size = UDim2.new(1, 0, 0, 0)
unitFrame.BackgroundColor3 = COLORS.panelBg
unitFrame.BorderSizePixel = 0
unitFrame.Visible = false
unitFrame.Parent = lowerRow
makeCorner(unitFrame, 8)
makeStroke(unitFrame, 2, COLORS.panelBorder)
ensure(unitFrame, "UIPadding", "Padding", function(p)
	p.PaddingTop = UDim.new(0, 8)
	p.PaddingBottom = UDim.new(0, 8)
	p.PaddingLeft = UDim.new(0, 10)
	p.PaddingRight = UDim.new(0, 10)
end)
ensure(unitFrame, "UIListLayout", "Layout", function(l)
	l.Padding = UDim.new(0, 3)
	l.SortOrder = Enum.SortOrder.LayoutOrder
end)

local detailsHeader = Instance.new("TextLabel")
detailsHeader.Name = "DetailsHeader"
detailsHeader.LayoutOrder = 1
detailsHeader.Size = UDim2.new(1, 0, 0, 16)
detailsHeader.BackgroundTransparency = 1
detailsHeader.Font = FONT_VALUE
detailsHeader.TextSize = 11
detailsHeader.TextColor3 = COLORS.headerText
detailsHeader.TextXAlignment = Enum.TextXAlignment.Left
detailsHeader.Text = "📋 UNIT-DETAILS"
detailsHeader.Parent = unitFrame

local uName = Instance.new("TextLabel")
uName.Name = "UnitNameLabel"
uName.LayoutOrder = 2
uName.Size = UDim2.new(1, 0, 0, 18)
uName.BackgroundTransparency = 1
uName.Font = FONT_VALUE
uName.TextSize = 13
uName.TextColor3 = COLORS.headerText
uName.TextXAlignment = Enum.TextXAlignment.Left
uName.TextTruncate = Enum.TextTruncate.AtEnd
uName.Text = ""
uName.Parent = unitFrame

local uClass = Instance.new("TextLabel")
uClass.Name = "UnitClassLabel"
uClass.LayoutOrder = 3
uClass.Size = UDim2.new(1, 0, 0, 14)
uClass.BackgroundTransparency = 1
uClass.Font = FONT_DESC
uClass.TextSize = 10
uClass.TextColor3 = COLORS.textDim
uClass.TextXAlignment = Enum.TextXAlignment.Left
uClass.Text = ""
uClass.Parent = unitFrame

local uHealth = Instance.new("TextLabel")
uHealth.Name = "UnitHealthLabel"
uHealth.LayoutOrder = 4
uHealth.Size = UDim2.new(1, 0, 0, 16)
uHealth.BackgroundTransparency = 1
uHealth.Font = FONT_DESC
uHealth.TextSize = 12
uHealth.TextColor3 = COLORS.hp
uHealth.TextXAlignment = Enum.TextXAlignment.Left
uHealth.Text = ""
uHealth.Parent = unitFrame

local uStatsRow = Instance.new("Frame")
uStatsRow.Name = "UnitStatsRow"
uStatsRow.LayoutOrder = 5
uStatsRow.Size = UDim2.new(1, 0, 0, 16)
uStatsRow.BackgroundTransparency = 1
uStatsRow.Parent = unitFrame
ensure(uStatsRow, "UIListLayout", "Layout", function(l)
	l.FillDirection = Enum.FillDirection.Horizontal
	l.Padding = UDim.new(0, 8)
	l.SortOrder = Enum.SortOrder.LayoutOrder
end)

local function makeUnitStatLabel(order, color)
	local l = Instance.new("TextLabel")
	l.Name = "UStat_" .. order
	l.LayoutOrder = order
	l.Size = UDim2.new(0, 55, 1, 0)
	l.BackgroundTransparency = 1
	l.Font = FONT_DESC
	l.TextSize = 11
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = ""
	l.Parent = uStatsRow
	return l
end

local uAttack = makeUnitStatLabel(1, COLORS.attack)
local uDefense = makeUnitStatLabel(2, COLORS.defense)

local uStatsRow2 = Instance.new("Frame")
uStatsRow2.Name = "UnitStatsRow2"
uStatsRow2.LayoutOrder = 6
uStatsRow2.Size = UDim2.new(1, 0, 0, 16)
uStatsRow2.BackgroundTransparency = 1
uStatsRow2.Parent = unitFrame
ensure(uStatsRow2, "UIListLayout", "Layout", function(l)
	l.FillDirection = Enum.FillDirection.Horizontal
	l.Padding = UDim.new(0, 8)
	l.SortOrder = Enum.SortOrder.LayoutOrder
end)

local function makeUnitStatLabel2(order, color)
	local l = Instance.new("TextLabel")
	l.Name = "UStat2_" .. order
	l.LayoutOrder = order
	l.Size = UDim2.new(0, 55, 1, 0)
	l.BackgroundTransparency = 1
	l.Font = FONT_DESC
	l.TextSize = 11
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = ""
	l.Parent = uStatsRow2
	return l
end

local uSight = makeUnitStatLabel2(1, COLORS.sight)
local uMovement = makeUnitStatLabel2(2, COLORS.movement)

-- ACTIONS-PANEL (unten, unter dem UnitDetailsPanel gestapelt)
local actionsPanel = Instance.new("Frame")
actionsPanel.Name = "ActionsPanel"
actionsPanel.LayoutOrder = 2
actionsPanel.AutomaticSize = Enum.AutomaticSize.Y
actionsPanel.Size = UDim2.new(1, 0, 0, 0)
actionsPanel.BackgroundColor3 = COLORS.panelBg
actionsPanel.BorderSizePixel = 0
actionsPanel.Parent = lowerRow
makeCorner(actionsPanel, 8)
makeStroke(actionsPanel, 2, COLORS.panelBorder)
ensure(actionsPanel, "UIPadding", "Padding", function(p)
	p.PaddingTop = UDim.new(0, 8)
	p.PaddingBottom = UDim.new(0, 8)
	p.PaddingLeft = UDim.new(0, 8)
	p.PaddingRight = UDim.new(0, 8)
end)
ensure(actionsPanel, "UIListLayout", "Layout", function(l)
	l.Padding = UDim.new(0, 6)
	l.SortOrder = Enum.SortOrder.LayoutOrder
end)

local actionsHeader = Instance.new("TextLabel")
actionsHeader.Name = "ActionsHeader"
actionsHeader.LayoutOrder = 1
actionsHeader.Size = UDim2.new(1, 0, 0, 16)
actionsHeader.BackgroundTransparency = 1
actionsHeader.Font = FONT_VALUE
actionsHeader.TextSize = 11
actionsHeader.TextColor3 = COLORS.headerText
actionsHeader.TextXAlignment = Enum.TextXAlignment.Left
actionsHeader.Text = "🛠️ AKTIONEN"
actionsHeader.Parent = actionsPanel

local buildBtn = Instance.new("TextButton")
buildBtn.Name = "BuildCampButton"
buildBtn.LayoutOrder = 2
buildBtn.Size = UDim2.new(1, 0, 0, 28)
buildBtn.Font = FONT_VALUE
buildBtn.TextSize = 12
buildBtn.TextColor3 = COLORS.btnText
buildBtn.Text = "🏕️ Camp bauen"
buildBtn.Parent = actionsPanel
makeCorner(buildBtn, 6)
wireButtonStyle(buildBtn, ACTION_COLORS)

local stopSelectBtn = Instance.new("TextButton")
stopSelectBtn.Name = "StopSelectButton"
stopSelectBtn.LayoutOrder = 3
stopSelectBtn.Size = UDim2.new(1, 0, 0, 28)
stopSelectBtn.Font = FONT_VALUE
stopSelectBtn.TextSize = 12
stopSelectBtn.TextColor3 = COLORS.btnText
stopSelectBtn.Text = "❌ Auswahl aufheben"
stopSelectBtn.Parent = actionsPanel
makeCorner(stopSelectBtn, 6)
wireButtonStyle(stopSelectBtn, ACTION_COLORS)

local watchBtn = Instance.new("TextButton")
watchBtn.Name = "WatchCombatButton"
watchBtn.LayoutOrder = 4
watchBtn.Size = UDim2.new(1, 0, 0, 28)
watchBtn.Font = FONT_VALUE
watchBtn.TextSize = 12
watchBtn.TextColor3 = Color3.new(1, 1, 1)
watchBtn.Text = "👁️ Kampf ansehen"
watchBtn.Visible = false
watchBtn.Parent = actionsPanel
makeCorner(watchBtn, 6)
wireButtonStyle(watchBtn, { normal = Color3.fromRGB(150, 70, 60), hover = Color3.fromRGB(180, 90, 75), pressed = Color3.fromRGB(120, 55, 45), disabled = COLORS.btnDisabled })

local previewLabel = Instance.new("TextLabel")
previewLabel.Name = "PreviewLabel"
previewLabel.LayoutOrder = 5
previewLabel.Size = UDim2.new(1, 0, 0, 14)
previewLabel.BackgroundTransparency = 1
previewLabel.Font = FONT_DESC
previewLabel.TextSize = 10
previewLabel.TextColor3 = COLORS.textDim
previewLabel.TextXAlignment = Enum.TextXAlignment.Left
previewLabel.Text = "👁️ Vorschau"
previewLabel.Parent = actionsPanel

local hoverImageBg = Instance.new("Frame")
hoverImageBg.Name = "HoverUnitImageBg"
hoverImageBg.LayoutOrder = 6
hoverImageBg.Size = UDim2.new(0, 70, 0, 70)
hoverImageBg.BackgroundColor3 = COLORS.slotEmptyBg
hoverImageBg.BorderSizePixel = 0
hoverImageBg.Parent = actionsPanel
makeCorner(hoverImageBg, 8)
makeStroke(hoverImageBg, 2, COLORS.panelBorder)

local hoverImage = Instance.new("ImageLabel")
hoverImage.Name = "HoverUnitImage"
hoverImage.Size = UDim2.new(1, -8, 1, -8)
hoverImage.Position = UDim2.new(0, 4, 0, 4)
hoverImage.BackgroundTransparency = 1
hoverImage.ScaleType = Enum.ScaleType.Fit
hoverImage.Visible = false
hoverImage.Parent = hoverImageBg

--------------------------------------------------------------------------------
-- ZUSTAND
--------------------------------------------------------------------------------
local MAX_SLOTS = SLOT_CONFIG.MAX_UNITS
local slotGrid = {}          -- index -> { holder, icon, name, hpBarBg, hpBarFill, unitId }
local cachedMaxUnits = 0     -- letzter bekannter Wert, um Grid neu zu bauen
local shownUnitId = nil      -- aktuell ausgewaehlte Unit
local hoveredUnitId = nil    -- Slot, ueber dem die Maus gerade steht (transient)
local inCombat = false

-- Forward-Deklarationen (gegenseitige Referenzen)
local renderUnitSlots
local updateSlots
local renderStats
local showUnitDetail
local clearUnitDetail
local clearAll
local refreshHoverImage
local applyCombatLock

--------------------------------------------------------------------------------
-- HoverUnitImage-Update:
--   1) Wenn eine Unit ausgewaehlt ist (shownUnitId) -> immer diese anzeigen.
--   2) Sonst, wenn die Maus ueber einem belegten Slot steht -> gehoverte anzeigen.
--   3) Sonst -> ausblenden.
--------------------------------------------------------------------------------
refreshHoverImage = function()
	if not hoverImage then return end

	if shownUnitId then
		local unit = ArmyDataCache.GetUnit(shownUnitId)
		if unit and unit.icon and unit.icon ~= "" then
			hoverImage.Image = unit.icon
			hoverImage.Visible = true
			return
		end
	end

	if hoveredUnitId then
		local unit = ArmyDataCache.GetUnit(hoveredUnitId)
		if unit and unit.icon and unit.icon ~= "" then
			hoverImage.Image = unit.icon
			hoverImage.Visible = true
			return
		end
	end

	hoverImage.Visible = false
end

--------------------------------------------------------------------------------
-- HP-Balken-Farbe nach Prozentsatz
--------------------------------------------------------------------------------
local function hpColorFor(ratio)
	if ratio > 0.5 then return COLORS.hpBarGood end
	if ratio > 0.25 then return COLORS.hpBarWarn end
	return COLORS.hpBarBad
end

--------------------------------------------------------------------------------
-- EINZELNE SLOT-KACHEL bauen
--------------------------------------------------------------------------------
local function buildSlot(index)
	local holder = Instance.new("Frame")
	holder.Name = "Slot_" .. index
	holder.BackgroundColor3 = COLORS.slotEmptyBg
	holder.BorderSizePixel = 0
	holder.LayoutOrder = index
	holder.Parent = slotsContainer
	makeCorner(holder, 6)
	local stroke = makeStroke(holder, 1.5, COLORS.slotEmptyBorder, 0.2)

	local icon = Instance.new("ImageButton")
	icon.Name = "Icon"
	icon.Size = UDim2.new(1, -8, 0, 40)
	icon.Position = UDim2.new(0, 4, 0, 4)
	icon.BackgroundTransparency = 1
	icon.ImageTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.AutoButtonColor = false
	icon.Parent = holder

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.Size = UDim2.new(1, -6, 0, 14)
	nameLabel.Position = UDim2.new(0, 3, 0, 46)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = FONT_DESC
	nameLabel.TextSize = 10
	nameLabel.TextColor3 = COLORS.headerText
	nameLabel.TextXAlignment = Enum.TextXAlignment.Center
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Text = ""
	nameLabel.Parent = holder

	local hpText = Instance.new("TextLabel")
	hpText.Name = "HpText"
	hpText.Size = UDim2.new(1, -6, 0, 12)
	hpText.Position = UDim2.new(0, 3, 0, 60)
	hpText.BackgroundTransparency = 1
	hpText.Font = FONT_DESC
	hpText.TextSize = 9
	hpText.TextColor3 = COLORS.hp
	hpText.TextXAlignment = Enum.TextXAlignment.Center
	hpText.Text = ""
	hpText.Parent = holder

	local slotHpBarBg = Instance.new("Frame")
	slotHpBarBg.Name = "HpBarBg"
	slotHpBarBg.Size = UDim2.new(1, -8, 0, 4)
	slotHpBarBg.Position = UDim2.new(0, 4, 1, -8)
	slotHpBarBg.BackgroundColor3 = Color3.fromRGB(25, 22, 18)
	slotHpBarBg.BorderSizePixel = 0
	slotHpBarBg.Parent = holder
	makeCorner(slotHpBarBg, 2)

	local slotHpBarFill = Instance.new("Frame")
	slotHpBarFill.Name = "Fill"
	slotHpBarFill.Size = UDim2.new(0, 0, 1, 0)
	slotHpBarFill.BackgroundColor3 = COLORS.hpBarGood
	slotHpBarFill.BorderSizePixel = 0
	slotHpBarFill.Parent = slotHpBarBg
	makeCorner(slotHpBarFill, 2)

	return { holder = holder, icon = icon, name = nameLabel, hpText = hpText,
		hpBarFill = slotHpBarFill, stroke = stroke, unitId = nil }
end

--------------------------------------------------------------------------------
-- Hover-Handler auf einen Slot
--------------------------------------------------------------------------------
local function attachHover(slotFrame, getUnitId)
	slotFrame.MouseEnter:Connect(function()
		hoveredUnitId = getUnitId()
		refreshHoverImage()
	end)
	slotFrame.MouseLeave:Connect(function()
		hoveredUnitId = nil
		refreshHoverImage()
	end)
end

--------------------------------------------------------------------------------
-- SLOT-ZUSTAND setzen (leer / belegt / ausgewaehlt)
--------------------------------------------------------------------------------
local function styleSlot(slot, unit, isSelected)
	if not slot then return end

	slot.unitId = unit and unit.id or nil

	if unit then
		slot.icon.Image = unit.icon or ""
		slot.icon.ImageTransparency = (unit.icon and unit.icon ~= "") and 0 or 1
		slot.name.Text = unit.name or unit.unitType or ""

		local maxLP = math.max(1, unit.maxLP or 1)
		local ratio = math.clamp((unit.currentLP or 0) / maxLP, 0, 1)
		slot.hpText.Text = (unit.currentLP or 0) .. "/" .. maxLP
		slot.hpBarFill.Size = UDim2.new(ratio, 0, 1, 0)
		slot.hpBarFill.BackgroundColor3 = hpColorFor(ratio)

		if isSelected then
			slot.holder.BackgroundColor3 = COLORS.slotSelectedBg
			slot.stroke.Color = COLORS.slotSelectedBorder
			slot.stroke.Thickness = 2.5
			slot.stroke.Transparency = 0
		else
			slot.holder.BackgroundColor3 = COLORS.slotFilledBg
			slot.stroke.Color = COLORS.slotFilledBorder
			slot.stroke.Thickness = 1.5
			slot.stroke.Transparency = 0.1
		end
	else
		slot.icon.Image = ""
		slot.icon.ImageTransparency = 1
		slot.name.Text = ""
		slot.hpText.Text = ""
		slot.hpBarFill.Size = UDim2.new(0, 0, 1, 0)

		slot.holder.BackgroundColor3 = COLORS.slotEmptyBg
		slot.stroke.Color = COLORS.slotEmptyBorder
		slot.stroke.Thickness = 1.5
		slot.stroke.Transparency = 0.2
	end
end

--------------------------------------------------------------------------------
-- renderUnitSlots(armyData): Grid neu bauen (wenn maxUnits sich aendert)
--------------------------------------------------------------------------------
renderUnitSlots = function(army)
	if not slotsContainer then return end

	local maxUnits = math.clamp(army and army.maxUnits or 8, 1, MAX_SLOTS)
	if maxUnits == cachedMaxUnits then return end
	cachedMaxUnits = maxUnits

	for i = #slotGrid, 1, -1 do
		if slotGrid[i].holder then slotGrid[i].holder:Destroy() end
	end
	slotGrid = {}

	for i = 1, maxUnits do
		local slot = buildSlot(i)
		slot.icon.MouseButton1Click:Connect(function()
			local armyNow = ArmyDataCache.Get()
			local unit = armyNow and armyNow.units and armyNow.units[i] or nil
			if unit then showUnitDetail(unit.id, i) end
		end)
		attachHover(slot.holder, function() return slotGrid[i] and slotGrid[i].unitId or nil end)
		slotGrid[i] = slot
	end

	-- Container-Hoehe manuell an die Zeilenzahl anpassen (Grid selbst hat
	-- kein zuverlaessiges AutomaticSize fuer den Elternteil).
	local rows = math.ceil(maxUnits / SLOT_CONFIG.SLOTS_PER_ROW)
	local rowHeight = SLOT_CONFIG.SLOT_SIZE.Y.Offset + SLOT_CONFIG.SLOT_PADDING.Y.Offset
	slotsContainer.Size = UDim2.new(1, 0, 0, rows * rowHeight)
end

--------------------------------------------------------------------------------
-- updateSlots(armyData): Icons/Namen/HP auffrischen, nur selten Grid neu bauen
--------------------------------------------------------------------------------
updateSlots = function(army)
	if not army then
		clearAll()
		return
	end

	local maxUnits = math.clamp(army.maxUnits or 8, 1, MAX_SLOTS)
	if maxUnits ~= cachedMaxUnits then
		renderUnitSlots(army)
	end

	for i = 1, math.min(maxUnits, #slotGrid) do
		local slot = slotGrid[i]
		local unit = army.units and army.units[i] or nil
		styleSlot(slot, unit, unit ~= nil and unit.id == shownUnitId)
	end
end

--------------------------------------------------------------------------------
-- Army-Stat-Anzeige (Gesamt-Stats-Bar)
--------------------------------------------------------------------------------
renderStats = function(army)
	nameLabel.Text = "⚔️ Armee: " .. (army.name and ("\"" .. army.name .. "\"") or ("Army " .. tostring(army.id or "?")))

	local st = army.stats or {}
	local curLP = st.LP or 0
	local maxLP = st.MaxLP or 0

	lblHealth.Text = "❤️ " .. curLP .. "/" .. maxLP
	lblAttack.Text = "⚔️ " .. (st.Attack or 0)
	lblDefense.Text = "🛡️ " .. (st.Defense or 0)
	lblSight.Text = "👁️ " .. (st.Sight or 0)
	local curMove = st.Movement or 0
	lblMove.Text = "🏃 " .. curMove .. "/" .. (st.MaxMovement or curMove)

	local ratio = (maxLP > 0) and math.clamp(curLP / maxLP, 0, 1) or 0
	hpBarFill.Size = UDim2.new(ratio, 0, 1, 0)
	hpBarFill.BackgroundColor3 = hpColorFor(ratio)
	hpBarText.Text = curLP .. "/" .. maxLP .. " (" .. math.floor(ratio * 100) .. "%)"
end

--------------------------------------------------------------------------------
-- Unit-Detailansicht bei Slot-Klick
--------------------------------------------------------------------------------
showUnitDetail = function(unitId, slotIndex)
	local army = ArmyDataCache.Get()
	local unit = army and army.units and army.units[slotIndex] or nil
	if not unit then
		clearUnitDetail()
		return
	end

	shownUnitId = unitId

	unitFrame.Visible = true
	refreshHoverImage()
	uName.Text = unit.name or unit.unitType or ""
	uClass.Text = (unit.class and unit.class ~= "") and ("Klasse: " .. unit.class) or ""
	uHealth.Text = "❤️ " .. (unit.currentLP or 0) .. "/" .. (unit.maxLP or 0)
	uAttack.Text = "⚔️ " .. (unit.attack or 0)
	uDefense.Text = "🛡️ " .. (unit.defense or 0)
	uSight.Text = "👁️ " .. (unit.sight or 0)
	uMovement.Text = "🏃 " .. (unit.currentMovement or 0) .. "/" .. (unit.maxMovement or 0)

	for i = 1, #slotGrid do
		if slotGrid[i] then
			local sUnit = army.units[i]
			styleSlot(slotGrid[i], sUnit, sUnit ~= nil and i == slotIndex)
		end
	end
end

clearUnitDetail = function()
	shownUnitId = nil
	hoveredUnitId = nil
	unitFrame.Visible = false
	refreshHoverImage()

	local army = ArmyDataCache.Get()
	if army then
		for i = 1, #slotGrid do
			if slotGrid[i] then
				styleSlot(slotGrid[i], army.units and army.units[i] or nil, false)
			end
		end
	end
end

clearAll = function()
	renderStats({ name = nil, id = nil, stats = {} })
	for i = 1, #slotGrid do
		if slotGrid[i] then
			styleSlot(slotGrid[i], nil, false)
		end
	end
	clearUnitDetail()
end

--------------------------------------------------------------------------------
-- Kampf-Lock
--------------------------------------------------------------------------------
applyCombatLock = function()
	local armyId = State.GetId(State.Kind.ARMY)
	inCombat = State.IsArmyInCombat ~= nil
		and State.IsArmyInCombat(armyId or 0)

	combatLabel.Visible = inCombat
	watchBtn.Visible = inCombat
	setButtonEnabled(buildBtn, ACTION_COLORS, not inCombat)
end

--------------------------------------------------------------------------------
-- OEFFNEN / SCHLIESSEN
--------------------------------------------------------------------------------
local function show()
	gui.Enabled = true
	setButtonEnabled(buildBtn, ACTION_COLORS, true)
	applyCombatLock()
	ArmyDataCache.Refresh()
end

local function hide()
	gui.Enabled = false
	clearAll()
end

--------------------------------------------------------------------------------
-- VERBINDUNGEN
--------------------------------------------------------------------------------
ArmyDataCache.OnUpdated:Connect(function(army)
	if not army then
		clearAll()
		return
	end
	renderStats(army)
	updateSlots(army)
end)

State.OnChanged:Connect(function(kind, id)
	if kind == State.Kind.ARMY and id then
		show()
	else
		hide()
	end
end)

if State.OnArmyCombatChanged then
	State.OnArmyCombatChanged:Connect(function(armyId)
		if State.GetId(State.Kind.ARMY) == armyId then applyCombatLock() end
	end)
end

stopSelectBtn.Activated:Connect(function()
	clearUnitDetail()
end)

watchBtn.Activated:Connect(function()
	local openEvent = ReplicatedStorage:FindFirstChild("OpenCombatView")
	if openEvent then openEvent:Fire() end
end)

buildBtn.Activated:Connect(function()
	if buildBtn:GetAttribute("Disabled") then return end
	local armyId = State.GetId(State.Kind.ARMY)
	if not armyId then return end
	if inCombat then
		print("[ArmyPanel] Army ist im Kampf - Camp-Bau blockiert")
		return
	end
	Net.Fire("RequestBuildCamp", armyId)
end)

--------------------------------------------------------------------------------
-- BOOT
--------------------------------------------------------------------------------
gui.Enabled = false
clearAll()

local kind, id = State.Get()
if kind == State.Kind.ARMY and id then show() else hide() end

print("[ArmyPanel] Bereit (code-generiert, Fantasy-Stil, dynamische Unit-Slots).")
