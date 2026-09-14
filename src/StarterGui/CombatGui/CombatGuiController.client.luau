--[[
    CombatGuiController (LocalScript)
    Location: StarterGui > CombatGui > CombatGuiController

    KOMPLETT CODE-GENERIERTE CombatGui im Fantasy-Stil (wie CityGui, ArmyGui,
    EmpireOverlayGui, DiplomacyGui, VictoryGui, TechTreeGui): alle Elemente
    werden per Instance.new() erzeugt, nichts wird mehr manuell in Studio
    gebaut.

    LAYOUT (zentriertes Kampf-Overlay, passend zum Ping-Pong-Combat-System):
        CombatWindow
          Header              - "⚔️ KAMPF" + FleeButton + CloseButton
          TurnPanel           - prominenter Turn-Indikator (gruen/rot) +
                                schrumpfender Timer-Balken
          ArmiesRow (2 Spalten nebeneinander)
            PlayerCombatFrame   (links, dunkelgruen)  - IMMER der lokale Spieler
              AttackerNameLabel / PlayerUnitsFrame (Grid) / AutoResolveButton
            EnemyCombatFrame    (rechts, dunkelrot)   - IMMER der Gegner
              DefenderNameLabel / EnemyUnitsFrame (Grid)
          CombatLogFrame      - ScrollingFrame, farbige Log-Eintraege

    PLAYER PERSPECTIVE
        The local player is ALWAYS rendered in PlayerCombatFrame, no matter
        whether he is the attacker or the defender server side. The mapping is
        resolved once per snapshot via the UserId (see resolvePerspective).
        Unit ids and army ids stay untouched - only the visual placement flips.

    PING PONG INTERACTION
        The two sides alternate, the attacker starts. On your turn you may pick
        ANY of your living units (even the same one every turn):
            own unit   -> click = confirm (golden outline) + "Waehle ein Ziel!"
            enemy unit -> click = attack resolves IMMEDIATELY (no timer wait)
            no input   -> after 10s the server auto attacks and hands over
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage:WaitForChild("Net"))
local ClientState = require(ReplicatedStorage:WaitForChild("ClientState"))

local localPlayer = Players.LocalPlayer

--------------------------------------------------------------------------------
-- GUI-Wurzel finden + alles Alte entfernen (CLEANUP)
--
-- Loescht ALLE Children von CombatGui (die alte CombatOverlay.rbxm inkl.
-- aller verschachtelten statischen Elemente) - NUR dieses Script selbst
-- bleibt erhalten. Alle GUI-Elemente werden im Folgenden komplett neu per
-- Code erzeugt.
--------------------------------------------------------------------------------
local gui = script.Parent
if not gui:IsA("ScreenGui") then
	gui = script.Parent:FindFirstAncestorWhichIsA("ScreenGui")
end
if not gui then
	warn("[CombatGui] Keine ScreenGui gefunden")
	return
end

for _, child in ipairs(gui:GetChildren()) do
	if child ~= script then
		child:Destroy()
	end
end

gui.Enabled = false
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true

--------------------------------------------------------------------------------
-- FANTASY-FARBSCHEMA (identisch zu CityGui/ArmyGui)
--------------------------------------------------------------------------------
local COLORS = {
	windowBg    = Color3.fromRGB(35, 28, 22),
	panelBorder = Color3.fromRGB(120, 90, 50),

	headerBg   = Color3.fromRGB(120, 30, 30),
	headerText = Color3.fromRGB(255, 220, 150),

	turnMine  = Color3.fromRGB(50, 120, 50),
	turnEnemy = Color3.fromRGB(120, 50, 50),
	timerBar  = Color3.fromRGB(255, 200, 80),

	playerPanelBg = Color3.fromRGB(40, 50, 40),
	enemyPanelBg  = Color3.fromRGB(50, 35, 35),

	portraitNormalBg     = Color3.fromRGB(60, 50, 40),
	portraitNormalBorder = Color3.fromRGB(120, 90, 50),
	portraitActiveBg     = Color3.fromRGB(80, 65, 45),
	portraitActiveBorder = Color3.fromRGB(255, 215, 0),
	portraitDeadBg       = Color3.fromRGB(40, 35, 35),
	portraitDeadBorder   = Color3.fromRGB(180, 60, 60),

	hpHigh = Color3.fromRGB(90, 220, 90),
	hpMid  = Color3.fromRGB(240, 200, 60),
	hpLow  = Color3.fromRGB(230, 70, 70),

	target    = Color3.fromRGB(255, 90, 90),
	damage    = Color3.fromRGB(255, 80, 80),
	counter   = Color3.fromRGB(255, 165, 0),
	absorbed  = Color3.fromRGB(120, 200, 255),
	dead      = Color3.fromRGB(150, 150, 150),

	logBg   = Color3.fromRGB(30, 25, 20),
	logText = Color3.fromRGB(200, 190, 170),

	btnNormal  = Color3.fromRGB(70, 55, 40),
	btnHover   = Color3.fromRGB(100, 80, 55),
	btnFlee    = Color3.fromRGB(150, 100, 30),
	btnFleeHov = Color3.fromRGB(180, 125, 50),
	btnAuto    = Color3.fromRGB(50, 80, 120),
	btnAutoHov = Color3.fromRGB(70, 105, 150),
	btnDisabled = Color3.fromRGB(90, 90, 100),
	btnText    = Color3.fromRGB(255, 220, 150),
}

-- Battle log colour per event type (Fantasy-Farbschema).
local LOG_COLORS = {
	damage  = Color3.fromRGB(255, 80, 80),    -- attack line
	counter = Color3.fromRGB(255, 165, 0),    -- counter attack
	death   = Color3.fromRGB(200, 50, 50),    -- unit killed
	flee    = Color3.fromRGB(255, 220, 80),   -- retreat / rout
	heal    = Color3.fromRGB(110, 230, 110),  -- healing / victory
	info    = Color3.fromRGB(200, 190, 170),  -- neutral
}

local FONT_TITLE = Enum.Font.FredokaOne
local FONT_VALUE = Enum.Font.GothamBold
local FONT_DESC  = Enum.Font.Gotham

local MAX_LOG_ENTRIES = 50

--------------------------------------------------------------------------------
-- HILFSFUNKTIONEN
--------------------------------------------------------------------------------
local function makeCorner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = parent
	return c
end

local function makeStroke(parent, thickness, color, transparency, name)
	local s = Instance.new("UIStroke")
	s.Name = name or "UIStroke"
	s.Thickness = thickness or 2
	s.Color = color or COLORS.panelBorder
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function wireButtonStyle(button, normalColor, hoverColor)
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.BackgroundColor3 = normalColor

	button.MouseEnter:Connect(function()
		if button:GetAttribute("Disabled") then return end
		button.BackgroundColor3 = hoverColor
	end)
	button.MouseLeave:Connect(function()
		if button:GetAttribute("Disabled") then return end
		button.BackgroundColor3 = normalColor
	end)
end

--------------------------------------------------------------------------------
-- COMBAT-WINDOW (zentriertes Overlay)
--------------------------------------------------------------------------------
local combatWindow = Instance.new("Frame")
combatWindow.Name = "CombatWindow"
combatWindow.Size = UDim2.new(0.65, 0, 0.75, 0)
combatWindow.Position = UDim2.new(0.5, 0, 0.5, 0)
combatWindow.AnchorPoint = Vector2.new(0.5, 0.5)
combatWindow.BackgroundColor3 = COLORS.windowBg
combatWindow.BackgroundTransparency = 0.05
combatWindow.BorderSizePixel = 0
combatWindow.Parent = gui
makeCorner(combatWindow, 12)
makeStroke(combatWindow, 3, COLORS.panelBorder)

--------------------------------------------------------------------------------
-- HEADER (dunkelrot) - Titel + Flee-Button + Close-Button
--------------------------------------------------------------------------------
local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 50)
header.Position = UDim2.new(0, 0, 0, 0)
header.BackgroundColor3 = COLORS.headerBg
header.BorderSizePixel = 0
header.Parent = combatWindow
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

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "TitleLabel"
titleLabel.Size = UDim2.new(1, -260, 1, 0)
titleLabel.Position = UDim2.new(0, 16, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = FONT_TITLE
titleLabel.TextSize = 22
titleLabel.TextColor3 = COLORS.headerText
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Text = "⚔️ KAMPF"
titleLabel.Parent = header

local fleeButton = Instance.new("TextButton")
fleeButton.Name = "FleeButton"
fleeButton.Size = UDim2.new(0, 140, 0, 34)
fleeButton.Position = UDim2.new(1, -190, 0.5, -17)
fleeButton.Font = FONT_VALUE
fleeButton.TextSize = 14
fleeButton.TextColor3 = COLORS.btnText
fleeButton.Text = "🏃 Flucht"
fleeButton.Parent = header
makeCorner(fleeButton, 6)
wireButtonStyle(fleeButton, COLORS.btnFlee, COLORS.btnFleeHov)

local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.Size = UDim2.fromOffset(36, 34)
closeButton.Position = UDim2.new(1, -46, 0.5, -17)
closeButton.BackgroundColor3 = Color3.fromRGB(70, 70, 82)
closeButton.Font = FONT_VALUE
closeButton.TextSize = 16
closeButton.TextColor3 = Color3.new(1, 1, 1)
closeButton.Text = "X"
closeButton.Visible = false
closeButton.BorderSizePixel = 0
closeButton.Parent = header
makeCorner(closeButton, 6)

--------------------------------------------------------------------------------
-- BODY (enthaelt TurnPanel, ArmiesRow und CombatLogFrame - manuell
-- positioniert, damit die drei Bloecke feste Hoehen behalten und die
-- ArmiesRow den restlichen Platz einnimmt).
--------------------------------------------------------------------------------
local body = Instance.new("Frame")
body.Name = "Body"
body.Size = UDim2.new(1, -20, 1, -60)
body.Position = UDim2.new(0, 10, 0, 54)
body.BackgroundTransparency = 1
body.Parent = combatWindow

local TURN_PANEL_HEIGHT = 64
local LOG_SECTION_HEIGHT = 170
local GAP = 8

--------------------------------------------------------------------------------
-- TURN-PANEL (prominent, zeigt wer dran ist + Timer-Balken)
--------------------------------------------------------------------------------
local turnPanel = Instance.new("Frame")
turnPanel.Name = "TurnPanel"
turnPanel.Size = UDim2.new(1, 0, 0, TURN_PANEL_HEIGHT)
turnPanel.Position = UDim2.new(0, 0, 0, 0)
turnPanel.BackgroundColor3 = COLORS.turnMine
turnPanel.BorderSizePixel = 0
turnPanel.Parent = body
makeCorner(turnPanel, 8)
makeStroke(turnPanel, 2, COLORS.panelBorder)

local turnIndicator = Instance.new("TextLabel")
turnIndicator.Name = "TurnIndicator"
turnIndicator.Size = UDim2.new(1, -16, 0, 32)
turnIndicator.Position = UDim2.new(0, 8, 0, 4)
turnIndicator.BackgroundTransparency = 1
turnIndicator.Font = FONT_TITLE
turnIndicator.TextSize = 20
turnIndicator.TextColor3 = Color3.new(1, 1, 1)
turnIndicator.Text = "KAMPF BEGINNT"
turnIndicator.Parent = turnPanel

local countdownBg = Instance.new("Frame")
countdownBg.Name = "CountdownBar"
countdownBg.Size = UDim2.new(1, -16, 0, 10)
countdownBg.Position = UDim2.new(0, 8, 1, -18)
countdownBg.BackgroundColor3 = Color3.fromRGB(25, 22, 18)
countdownBg.BorderSizePixel = 0
countdownBg.Parent = turnPanel
makeCorner(countdownBg, 4)

local countdownFill = Instance.new("Frame")
countdownFill.Name = "Fill"
countdownFill.Size = UDim2.fromScale(1, 1)
countdownFill.BackgroundColor3 = COLORS.timerBar
countdownFill.BorderSizePixel = 0
countdownFill.Parent = countdownBg
makeCorner(countdownFill, 4)

--------------------------------------------------------------------------------
-- ARMIES-ROW (2 Spalten nebeneinander)
--------------------------------------------------------------------------------
local armiesRow = Instance.new("Frame")
armiesRow.Name = "ArmiesRow"
armiesRow.Size = UDim2.new(1, 0, 1, -(TURN_PANEL_HEIGHT + LOG_SECTION_HEIGHT + GAP * 2))
armiesRow.Position = UDim2.new(0, 0, 0, TURN_PANEL_HEIGHT + GAP)
armiesRow.BackgroundTransparency = 1
armiesRow.Parent = body

--------------------------------------------------------------------------------
-- PLAYER-PANEL (links, dunkelgruen) - IMMER der lokale Spieler
--------------------------------------------------------------------------------
local myPanel = Instance.new("Frame")
myPanel.Name = "PlayerCombatFrame"
myPanel.Size = UDim2.new(0.5, -4, 1, 0)
myPanel.Position = UDim2.new(0, 0, 0, 0)
myPanel.BackgroundColor3 = COLORS.playerPanelBg
myPanel.BorderSizePixel = 0
myPanel.Parent = armiesRow
makeCorner(myPanel, 8)
makeStroke(myPanel, 2, COLORS.panelBorder)

local attackerNameLabel = Instance.new("TextLabel")
attackerNameLabel.Name = "AttackerNameLabel"
attackerNameLabel.Size = UDim2.new(1, -12, 0, 24)
attackerNameLabel.Position = UDim2.new(0, 6, 0, 4)
attackerNameLabel.BackgroundTransparency = 1
attackerNameLabel.Font = FONT_VALUE
attackerNameLabel.TextSize = 15
attackerNameLabel.TextColor3 = Color3.fromRGB(150, 230, 150)
attackerNameLabel.TextXAlignment = Enum.TextXAlignment.Left
attackerNameLabel.TextTruncate = Enum.TextTruncate.AtEnd
attackerNameLabel.Text = "🛡️ Deine Armee"
attackerNameLabel.Parent = myPanel

local myList = Instance.new("Frame")
myList.Name = "PlayerUnitsFrame"
myList.Size = UDim2.new(1, -12, 1, -72)
myList.Position = UDim2.new(0, 6, 0, 30)
myList.BackgroundTransparency = 1
myList.Parent = myPanel

local myGridLayout = Instance.new("UIGridLayout")
myGridLayout.CellSize = UDim2.new(0, 72, 0, 84)
myGridLayout.CellPadding = UDim2.new(0, 6, 0, 6)
myGridLayout.SortOrder = Enum.SortOrder.LayoutOrder
myGridLayout.Parent = myList

local autoResolveButton = Instance.new("TextButton")
autoResolveButton.Name = "AutoResolveButton"
autoResolveButton.Size = UDim2.new(1, -12, 0, 32)
autoResolveButton.Position = UDim2.new(0, 6, 1, -36)
autoResolveButton.Font = FONT_VALUE
autoResolveButton.TextSize = 14
autoResolveButton.TextColor3 = Color3.new(1, 1, 1)
autoResolveButton.Text = "⚡ Auto-Resolve"
autoResolveButton.Parent = myPanel
makeCorner(autoResolveButton, 6)
wireButtonStyle(autoResolveButton, COLORS.btnAuto, COLORS.btnAutoHov)

--------------------------------------------------------------------------------
-- ENEMY-PANEL (rechts, dunkelrot) - IMMER der Gegner
--------------------------------------------------------------------------------
local enemyPanel = Instance.new("Frame")
enemyPanel.Name = "EnemyCombatFrame"
enemyPanel.Size = UDim2.new(0.5, -4, 1, 0)
enemyPanel.Position = UDim2.new(0.5, 4, 0, 0)
enemyPanel.BackgroundColor3 = COLORS.enemyPanelBg
enemyPanel.BorderSizePixel = 0
enemyPanel.Parent = armiesRow
makeCorner(enemyPanel, 8)
makeStroke(enemyPanel, 2, COLORS.panelBorder)

local defenderNameLabel = Instance.new("TextLabel")
defenderNameLabel.Name = "DefenderNameLabel"
defenderNameLabel.Size = UDim2.new(1, -12, 0, 24)
defenderNameLabel.Position = UDim2.new(0, 6, 0, 4)
defenderNameLabel.BackgroundTransparency = 1
defenderNameLabel.Font = FONT_VALUE
defenderNameLabel.TextSize = 15
defenderNameLabel.TextColor3 = Color3.fromRGB(255, 150, 150)
defenderNameLabel.TextXAlignment = Enum.TextXAlignment.Left
defenderNameLabel.TextTruncate = Enum.TextTruncate.AtEnd
defenderNameLabel.Text = "💀 Feindliche Armee"
defenderNameLabel.Parent = enemyPanel

local enemyList = Instance.new("Frame")
enemyList.Name = "EnemyUnitsFrame"
enemyList.Size = UDim2.new(1, -12, 1, -36)
enemyList.Position = UDim2.new(0, 6, 0, 30)
enemyList.BackgroundTransparency = 1
enemyList.Parent = enemyPanel

local enemyGridLayout = Instance.new("UIGridLayout")
enemyGridLayout.CellSize = UDim2.new(0, 72, 0, 84)
enemyGridLayout.CellPadding = UDim2.new(0, 6, 0, 6)
enemyGridLayout.SortOrder = Enum.SortOrder.LayoutOrder
enemyGridLayout.Parent = enemyList

--------------------------------------------------------------------------------
-- COMBAT-LOG (unten, ScrollingFrame)
--------------------------------------------------------------------------------
local logSection = Instance.new("Frame")
logSection.Name = "LogSection"
logSection.Size = UDim2.new(1, 0, 0, LOG_SECTION_HEIGHT)
logSection.Position = UDim2.new(0, 0, 1, -LOG_SECTION_HEIGHT)
logSection.BackgroundTransparency = 1
logSection.Parent = body

local logTitle = Instance.new("TextLabel")
logTitle.Name = "LogTitle"
logTitle.Size = UDim2.new(1, 0, 0, 20)
logTitle.BackgroundTransparency = 1
logTitle.Font = FONT_VALUE
logTitle.TextSize = 14
logTitle.TextColor3 = COLORS.headerText
logTitle.TextXAlignment = Enum.TextXAlignment.Left
logTitle.Text = "📜 KAMPF-LOG"
logTitle.Parent = logSection

local logFrame = Instance.new("ScrollingFrame")
logFrame.Name = "CombatLogFrame"
logFrame.Size = UDim2.new(1, 0, 1, -24)
logFrame.Position = UDim2.new(0, 0, 0, 24)
logFrame.BackgroundColor3 = COLORS.logBg
logFrame.BorderSizePixel = 0
logFrame.ScrollBarThickness = 5
logFrame.ScrollBarImageColor3 = COLORS.panelBorder
logFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
logFrame.CanvasSize = UDim2.new()
logFrame.Parent = logSection
makeCorner(logFrame, 8)
makeStroke(logFrame, 1, COLORS.panelBorder)

local logLayout = Instance.new("UIListLayout")
logLayout.Padding = UDim.new(0, 2)
logLayout.SortOrder = Enum.SortOrder.LayoutOrder
logLayout.Parent = logFrame

local logPadding = Instance.new("UIPadding")
logPadding.PaddingLeft = UDim.new(0, 8)
logPadding.PaddingRight = UDim.new(0, 8)
logPadding.PaddingTop = UDim.new(0, 6)
logPadding.Parent = logFrame

--------------------------------------------------------------------------------
-- CLIENT STATE
--------------------------------------------------------------------------------
local currentCombatId: number? = nil
local mySide: string? = nil          -- "attacker" | "defender" (server naming)
local enemySide: string? = nil
local myArmyId: number? = nil
local enemyArmyId: number? = nil
local isMyTurn = false
-- Ping pong: no unit is pre-designated. selectedUnitId is the unit the local
-- player confirmed for the CURRENT turn (nil = none picked yet).
local selectedUnitId: number? = nil
-- Auto resolve: true once the server confirmed that BOTH sides agreed.
local autoResolving = false
local cards: { [number]: any } = {}  -- unitId -> card frame (either panel)
local unitOwnerSide: { [number]: string } = {} -- unitId -> "mine" | "enemy"
local countdownConn: RBXScriptConnection? = nil
local logCounter = 0

--------------------------------------------------------------------------------
-- BATTLE LOG
--------------------------------------------------------------------------------
local function ClearLog()
	logCounter = 0
	for _, child in ipairs(logFrame:GetChildren()) do
		if child:IsA("TextLabel") then child:Destroy() end
	end
end

-- AddLogEntry(text, kind) - kind: damage | counter | death | flee | heal | info
local function AddLogEntry(text, kind)
	if not text or text == "" then return end

	logCounter += 1

	local label = Instance.new("TextLabel")
	label.Name = "LogEntry_" .. logCounter
	label.Size = UDim2.new(1, -12, 0, 18)
	label.BackgroundTransparency = 1
	label.Font = FONT_DESC
	label.TextSize = 13
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.TextColor3 = LOG_COLORS[kind or "info"] or LOG_COLORS.info
	label.Text = text
	label.LayoutOrder = logCounter
	label.Parent = logFrame

	-- Trim: keep only the newest MAX_LOG_ENTRIES lines.
	local entries = {}
	for _, child in ipairs(logFrame:GetChildren()) do
		if child:IsA("TextLabel") then table.insert(entries, child) end
	end
	if #entries > MAX_LOG_ENTRIES then
		table.sort(entries, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
		for i = 1, #entries - MAX_LOG_ENTRIES do
			entries[i]:Destroy()
		end
	end

	-- Newest entry at the bottom -> always scroll down.
	task.defer(function()
		if logFrame and logFrame.Parent then
			logFrame.CanvasPosition = Vector2.new(0, logFrame.AbsoluteCanvasSize.Y)
		end
	end)
end

--------------------------------------------------------------------------------
-- PERSPECTIVE
-- The local player is ALWAYS "mine". Resolved via UserId, with the server
-- tagged mySide as fallback (wildlife combats have no defender UserId).
--------------------------------------------------------------------------------
local function resolvePerspective(snapshot)
	local myId = localPlayer.UserId

	if snapshot.attackerOwnerId == myId then
		return "attacker", "defender"
	elseif snapshot.defenderOwnerId == myId then
		return "defender", "attacker"
	end

	local side = snapshot.mySide or "attacker"
	return side, (side == "attacker") and "defender" or "attacker"
end

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------
local function hpColor(ratio: number): Color3
	if ratio > 0.5 then return COLORS.hpHigh end
	if ratio > 0.25 then return COLORS.hpMid end
	return COLORS.hpLow
end

local function clearList(container)
	for _, child in ipairs(container:GetChildren()) do
		if child:GetAttribute("CombatCard") then child:Destroy() end
	end
end

-- Sets the turn panel background + timer bar colour depending on whose turn
-- it is (grün = mine, rot = gegner).
local function updateTurnPanelColor(mine)
	turnPanel.BackgroundColor3 = mine and COLORS.turnMine or COLORS.turnEnemy
end

local function HighlightUnit(unitId, color)
	local card = cards[unitId]
	if not card then return end

	local stroke = card:FindFirstChild("Glow")
	local activeMark = card:FindFirstChild("ActiveMark")

	if not color then
		if stroke then stroke.Enabled = false end
		if activeMark then activeMark.Visible = false end
		return
	end

	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.Name = "Glow"
		stroke.Thickness = 3
		stroke.Parent = card
	end
	stroke.Enabled = true
	stroke.Color = color
	stroke.Transparency = 0

	TweenService:Create(stroke,
		TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Transparency = 0.55 }):Play()

	if activeMark then activeMark.Visible = true end
end

local function ShowFloatingText(unitId, text, color)
	local card = cards[unitId]
	if not card then return end

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, 90, 0, 24)
	label.Position = UDim2.new(0.5, -45, 0, -4)
	label.BackgroundTransparency = 1
	label.Font = FONT_VALUE
	label.TextSize = 18
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.3
	label.Text = text
	label.ZIndex = 30
	label.Parent = card

	TweenService:Create(label, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, -45, 0, -34),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()

	task.delay(1.2, function()
		if label and label.Parent then label:Destroy() end
	end)
end

local function ShowDamageNumber(unitId, damage, color)
	ShowFloatingText(unitId, "-" .. tostring(damage), color)
end

--------------------------------------------------------------------------------
-- UpdateUnitCard(unitId, currentLP, maxLP, alive)
-- Updates the LP bar in whichever frame the unit lives in. Because `cards`
-- is keyed by unitId the correct panel is hit automatically - a defender
-- unit that belongs to the local player updates in PlayerCombatFrame.
--------------------------------------------------------------------------------
local function UpdateUnitCard(unitId, currentLP, maxLP, alive)
	local card = cards[unitId]
	if not card then return end

	-- Fall back to the value stored on the card instead of assuming 1.
	if not maxLP or maxLP <= 0 then
		maxLP = card:GetAttribute("MaxLP") or 1
	end
	currentLP = math.max(0, currentLP or 0)
	local ratio = math.clamp(currentLP / maxLP, 0, 1)

	local bar = card:FindFirstChild("HPBar")
	if bar then
		local fill = bar:FindFirstChild("Fill")
		if fill then
			TweenService:Create(fill, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {
				Size = UDim2.fromScale(ratio, 1),
				BackgroundColor3 = hpColor(ratio),
			}):Play()
		end
		local hpText = bar:FindFirstChild("HPText")
		if hpText then hpText.Text = currentLP .. "/" .. maxLP end
	end

	if alive == false then
		card:SetAttribute("Dead", true)
		card.BackgroundColor3 = COLORS.portraitDeadBg
		card.BackgroundTransparency = 0.5

		local border = card:FindFirstChild("Border")
		if border then
			border.Color = COLORS.portraitDeadBorder
		end

		local nameLabel = card:FindFirstChild("UnitName")
		if nameLabel and not string.find(nameLabel.Text, "💀", 1, true) then
			nameLabel.TextColor3 = COLORS.dead
		end

		local deadMark = card:FindFirstChild("DeadMark")
		if deadMark then deadMark.Visible = true end

		HighlightUnit(unitId, nil)
	end
end

--------------------------------------------------------------------------------
-- UNIT PORTRAIT-KACHEL - parent is PlayerUnitsFrame (isMine) or
-- EnemyUnitsFrame. Everything downstream (HighlightUnit, ShowDamageNumber,
-- UpdateUnitCard) looks the card up via the cards[unitId] table, so it
-- always hits the correct frame automatically.
--
-- Fantasy-Stil: Normal = bronze Rahmen, Aktiv = goldener Rahmen + Glow,
-- Tot = roter Rahmen + 💀-Overlay + Transparency 0.5.
--------------------------------------------------------------------------------
local function buildCard(parent, unit, isMine, index)
	local alive = unit.alive ~= false

	local card = Instance.new("Frame")
	card.Name = "Unit_" .. unit.id
	card:SetAttribute("CombatCard", true)
	card.LayoutOrder = index
	card.BackgroundColor3 = alive and COLORS.portraitNormalBg or COLORS.portraitDeadBg
	card.BackgroundTransparency = alive and 0 or 0.5
	card.BorderSizePixel = 0
	card.Parent = parent

	makeCorner(card, 6)
	local border = makeStroke(card, 1.5,
		alive and COLORS.portraitNormalBorder or COLORS.portraitDeadBorder,
		0.1, "Border")

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.new(1, -8, 0, 40)
	icon.Position = UDim2.new(0, 4, 0, 4)
	icon.BackgroundTransparency = 1
	icon.Image = unit.icon or ""
	icon.Parent = card

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "UnitName"
	nameLabel.Size = UDim2.new(1, -6, 0, 14)
	nameLabel.Position = UDim2.new(0, 3, 0, 46)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = FONT_DESC
	nameLabel.TextSize = 10
	nameLabel.TextXAlignment = Enum.TextXAlignment.Center
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.TextColor3 = alive and Color3.new(1, 1, 1) or COLORS.dead
	nameLabel.Text = unit.name or ""
	nameLabel.Parent = card

	local barBg = Instance.new("Frame")
	barBg.Name = "HPBar"
	barBg.Size = UDim2.new(1, -8, 0, 12)
	barBg.Position = UDim2.new(0, 4, 0, 62)
	barBg.BackgroundColor3 = Color3.fromRGB(25, 22, 18)
	barBg.BorderSizePixel = 0
	barBg.Parent = card
	makeCorner(barBg, 3)

	local ratio = (unit.maxLP or 0) > 0 and math.clamp(unit.currentLP / unit.maxLP, 0, 1) or 0
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(ratio, 1)
	fill.BackgroundColor3 = hpColor(ratio)
	fill.BorderSizePixel = 0
	fill.Parent = barBg
	makeCorner(fill, 3)

	local hpText = Instance.new("TextLabel")
	hpText.Name = "HPText"
	hpText.Size = UDim2.new(1, 0, 1, 0)
	hpText.BackgroundTransparency = 1
	hpText.Font = FONT_VALUE
	hpText.TextSize = 9
	hpText.TextColor3 = Color3.new(1, 1, 1)
	hpText.Text = unit.currentLP .. "/" .. unit.maxLP
	hpText.ZIndex = 3
	hpText.Parent = barBg

	-- ✅ Aktiv-Markierung: sichtbar, waehrend die Unit ausgewaehlt/aktiv ist
	-- (getoggled von HighlightUnit).
	local activeMark = Instance.new("TextLabel")
	activeMark.Name = "ActiveMark"
	activeMark.Size = UDim2.fromOffset(16, 16)
	activeMark.Position = UDim2.new(1, -16, 0, 0)
	activeMark.BackgroundTransparency = 1
	activeMark.Font = FONT_VALUE
	activeMark.TextSize = 14
	activeMark.Text = "✅"
	activeMark.Visible = false
	activeMark.ZIndex = 5
	activeMark.Parent = card

	-- 💀 Tot-Overlay: bleibt sichtbar bis das Ende des Kampfs, sobald die
	-- Unit stirbt.
	local deadMark = Instance.new("TextLabel")
	deadMark.Name = "DeadMark"
	deadMark.Size = UDim2.fromOffset(20, 20)
	deadMark.Position = UDim2.new(0, 0, 0, 0)
	deadMark.BackgroundTransparency = 1
	deadMark.Font = FONT_VALUE
	deadMark.TextSize = 16
	deadMark.Text = "💀"
	deadMark.Visible = not alive
	deadMark.ZIndex = 5
	deadMark.Parent = card

	-- Remembered so a partial update (only currentLP known) keeps the ratio.
	card:SetAttribute("MaxLP", unit.maxLP or 1)
	card:SetAttribute("Dead", unit.alive == false)

	-- Click surface (Activated works with mouse, touch and gamepad)
	local button = Instance.new("TextButton")
	button.Name = "ClickArea"
	button.Size = UDim2.fromScale(1, 1)
	button.BackgroundTransparency = 1
	button.Text = ""
	button.AutoButtonColor = false
	button.ZIndex = 20
	button.Parent = card

	button.Activated:Connect(function()
		CombatGui_OnUnitClicked(unit.id, isMine)
	end)

	cards[unit.id] = card
	unitOwnerSide[unit.id] = isMine and "mine" or "enemy"
	return card
end

--------------------------------------------------------------------------------
-- RenderUnits(container, units, isMine)
-- container is PlayerUnitsFrame or EnemyUnitsFrame (see above).
--------------------------------------------------------------------------------
local function RenderUnits(container, units, isMine)
	clearList(container)
	for i, unit in ipairs(units or {}) do
		buildCard(container, unit, isMine, i)
	end
end

--------------------------------------------------------------------------------
-- renderSnapshot(snapshot)
-- Rebuilds both unit panels. Does NOT touch the battle log - that one is
-- filled incrementally by the event handlers.
--------------------------------------------------------------------------------
local function renderSnapshot(snapshot)
	if not snapshot then return end

	mySide, enemySide = resolvePerspective(snapshot)

	local mine = snapshot[mySide]
	local enemy = snapshot[enemySide]
	if not mine or not enemy then return end

	myArmyId = mine.armyId
	enemyArmyId = enemy.armyId

	attackerNameLabel.Text = ("🛡️ %s  -  Moral %d"):format(mine.playerName or "Du", mine.morale or 100)
	defenderNameLabel.Text = ("💀 %s  -  Moral %d"):format(enemy.playerName or "Gegner", enemy.morale or 100)

	cards = {}
	unitOwnerSide = {}

	-- ALWAYS: own units left, enemy units right.
	-- Both unit frames are wiped first so no stale portrait survives
	-- (for example a unit that died between two snapshots).
	clearList(myList)
	clearList(enemyList)
	RenderUnits(myList, mine.units, true)
	RenderUnits(enemyList, enemy.units, false)

	-- Keep the golden outline of the unit the player already confirmed.
	if selectedUnitId then
		HighlightUnit(selectedUnitId, COLORS.portraitActiveBorder)
	end
end

--------------------------------------------------------------------------------
-- COUNTDOWN
--------------------------------------------------------------------------------
local function StartCountdown(seconds)
	if countdownConn then countdownConn:Disconnect() end
	seconds = tonumber(seconds) or 10
	local startedAt = os.clock()

	countdownConn = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - startedAt
		local left = math.max(0, seconds - elapsed)
		countdownFill.Size = UDim2.fromScale(left / seconds, 1)

		if isMyTurn then
			if selectedUnitId then
				turnIndicator.Text = ("Waehle ein Ziel!  -  %.0fs"):format(left)
			else
				turnIndicator.Text = ("🎯 DEIN ZUG! (%.0fs)"):format(left)
			end
			if left <= 0 then
				turnIndicator.Text = "Auto-Angriff..."
			end
		end

		if left <= 0 and countdownConn then
			countdownConn:Disconnect()
			countdownConn = nil
		end
	end)
end

--------------------------------------------------------------------------------
-- SELECTION HANDLING
--------------------------------------------------------------------------------
-- NOTE: must be declared BEFORE CombatGui_OnUnitClicked. Lua upvalues
-- are only visible after their declaration - the old position below
-- the click handler made the enemy-click branch call a nil global.
local function EnableUnitSelection(enabled)
	for _, card in pairs(cards) do
		local button = card:FindFirstChild("ClickArea")
		if button then button.Active = enabled end
	end
end

function CombatGui_OnUnitClicked(unitId, isMine)
	if not currentCombatId or not isMyTurn then return end
	-- All manual input is dead once the server is auto resolving.
	if autoResolving then return end

	if isMine then
		-- Any living own unit may act - and may be reused every turn.
		local card = cards[unitId]
		if card and card:GetAttribute("Dead") then
			ShowFloatingText(unitId, "gefallen", COLORS.absorbed)
			return
		end

		-- Clear the outline of a previously confirmed unit.
		if selectedUnitId and selectedUnitId ~= unitId then
			HighlightUnit(selectedUnitId, nil)
		end

		selectedUnitId = unitId
		HighlightUnit(unitId, COLORS.portraitActiveBorder)
		turnIndicator.Text = "Waehle ein Ziel!"

		Net.Fire("CombatSelectUnit", currentCombatId, unitId)
	else
		-- Enemy click resolves the attack IMMEDIATELY on the server.
		-- Without a confirmed unit the server picks the strongest own unit.
		HighlightUnit(unitId, COLORS.target)
		Net.Fire("CombatSelectTarget", currentCombatId, unitId)

		-- Lock the input until the next CombatTurnStart arrives.
		isMyTurn = false
		EnableUnitSelection(false)
	end
end

--------------------------------------------------------------------------------
-- OPEN / CLOSE
--------------------------------------------------------------------------------
local function closeOverlay()
	gui.Enabled = false
	-- Remove every portrait from both unit frames so the next combat
	-- starts from a clean state.
	clearList(myList)
	clearList(enemyList)
	currentCombatId = nil
	selectedUnitId = nil
	isMyTurn = false
	closeButton.Visible = false
	if countdownConn then countdownConn:Disconnect() countdownConn = nil end
	ClientState.SetCombat(false, nil)
end

--------------------------------------------------------------------------------
-- Feeds the per army combat flags in ClientState (used by ArmyPanel and
-- MovementController). Without this the clients would need a blocking
-- RemoteFunction for every click.
--------------------------------------------------------------------------------
local function markArmies(snapshot, active)
	if not snapshot then return end
	-- Defensive: an older ClientState without SetArmyCombat must NEVER crash
	-- this handler, otherwise the combat state would never be cleaned up.
	if type(ClientState.SetArmyCombat) ~= "function" then return end

	local a = snapshot.attacker and snapshot.attacker.armyId
	local d = snapshot.defender and snapshot.defender.armyId
	if a then ClientState.SetArmyCombat(a, active) end
	if d then ClientState.SetArmyCombat(d, active) end
end

--------------------------------------------------------------------------------
-- safeOn(name, fn)
-- Wraps every remote handler in a pcall. A rendering error inside the UI must
-- never stop the state cleanup (that once left armies permanently locked).
--------------------------------------------------------------------------------
local function safeOn(remoteName, handler)
	Net.On(remoteName, function(data)
		local ok, err = pcall(handler, data)
		if not ok then
			warn("[CombatGui] " .. remoteName .. " Handler-Fehler: " .. tostring(err))
		end
	end)
end

--------------------------------------------------------------------------------
-- REMOTE HANDLERS
--------------------------------------------------------------------------------
safeOn("CombatStart", function(data)
	if not data then return end
	markArmies(data, true)

	currentCombatId = data.combatId
	selectedUnitId = nil
	autoResolving = false
	autoResolveButton.Visible = true
	autoResolveButton:SetAttribute("Disabled", false)
	autoResolveButton.BackgroundColor3 = COLORS.btnAuto
	autoResolveButton.Text = "⚡ Auto-Resolve"
	gui.Enabled = true
	-- Always closable: closing only hides the view, the combat keeps running
	-- on the server. This lets the player move OTHER armies meanwhile.
	closeButton.Visible = true
	turnIndicator.Text = "KAMPF BEGINNT"
	updateTurnPanelColor(true)

	ClientState.SetCombat(true, data.combatId)

	-- Fresh log for every new combat.
	ClearLog()
	renderSnapshot(data)

	local enemyName = data[enemySide] and data[enemySide].playerName or "Gegner"
	AddLogEntry("⚔️ Kampf gegen " .. enemyName .. " beginnt!", "info")
end)

safeOn("CombatTurnStart", function(data)
	if not data or data.combatId ~= currentCombatId then return end

	-- activeSide decides everything: am I the side that has to act?
	isMyTurn = (data.isMyTurn == true)
		or (data.activeSide ~= nil and data.activeSide == mySide)
	selectedUnitId = nil

	if data.snapshot then renderSnapshot(data.snapshot) end

	updateTurnPanelColor(isMyTurn)
	if isMyTurn then
		turnIndicator.Text = "🎯 DEIN ZUG! Waehle eine Unit."
	else
		turnIndicator.Text = "⏳ GEGNER IST DRAN..."
	end

	-- Only the active player may click; the other side watches the timer.
	if autoResolving then
		isMyTurn = false
		EnableUnitSelection(false)
	else
		EnableUnitSelection(isMyTurn)
		StartCountdown(data.timeLimit or 10)
	end
end)

safeOn("CombatUnitSelected", function(data)
	if not data or data.combatId ~= currentCombatId then return end
	selectedUnitId = data.unitId
	HighlightUnit(data.unitId, COLORS.portraitActiveBorder)
end)

safeOn("CombatAttackResult", function(data)
	if not data or data.combatId ~= currentCombatId then return end
	local r = data.result
	if not r then return end

	------------------------------------------------------------------
	-- 1) Battle log (own vs enemy is irrelevant here - names say it all)
	------------------------------------------------------------------
	local line = ("⚔️ %s → %s: %d Schaden"):format(
		tostring(r.attackerName), tostring(r.targetName), r.actualDamage or 0)

	local extras = {}
	if (r.absorbed or 0) > 0 then
		table.insert(extras, r.absorbed .. " abs.")
	end
	if (r.counterDamage or 0) > 0 then
		table.insert(extras, r.counterDamage .. " K.")
	end
	if #extras > 0 then
		line = line .. " (" .. table.concat(extras, ", ") .. ")"
	end
	AddLogEntry(line, "damage")

	if (r.counterDamage or 0) > 0 then
		AddLogEntry(("⚡ Konter: %s erleidet %d Schaden")
			:format(tostring(r.attackerName), r.counterDamage), "counter")
	end
	if r.targetKilled then
		AddLogEntry(("💀 %s wurde getötet!"):format(tostring(r.targetName)), "death")
	end
	if r.attackerKilled then
		AddLogEntry(("💀 %s wurde getötet!"):format(tostring(r.attackerName)), "death")
	end

	------------------------------------------------------------------
	-- 2) Floating numbers + immediate LP bar update.
	--    cards[] is keyed by unitId, so the bar is updated in the frame the
	--    unit actually lives in (player frame for own units, even when the
	--    unit is the server side "defender").
	------------------------------------------------------------------
	ShowDamageNumber(r.targetId, r.actualDamage, COLORS.damage)
	if (r.absorbed or 0) > 0 then
		ShowFloatingText(r.targetId, "abs " .. r.absorbed, COLORS.absorbed)
	end
	UpdateUnitCard(r.targetId, r.targetLPAfter, nil, r.targetKilled ~= true)

	if (r.counterDamage or 0) > 0 then
		task.delay(0.25, function()
			ShowDamageNumber(r.attackerId, r.counterDamage, COLORS.counter)
			UpdateUnitCard(r.attackerId, r.attackerLPAfter, nil,
				r.attackerKilled ~= true)
		end)
	end

	-- 3) Full re-sync a moment later (keeps morale / order in sync).
	task.delay(0.55, function()
		if data.snapshot then renderSnapshot(data.snapshot) end
	end)
end)

safeOn("CombatEnd", function(data)
	if not data then return end
	if currentCombatId and data.combatId ~= currentCombatId then return end

	local result = data.result

	-- STATE CLEANUP FIRST - rendering may fail, the unlock must not.
	markArmies(result, false)
	ClientState.SetCombat(false, nil)

	if result then renderSnapshot(result) end

	-- Auto resolve computes many hits without single broadcasts, so the
	-- complete server log is replayed into the panel here.
	if data.log then
		ClearLog()
		for _, line in ipairs(data.log) do
			AddLogEntry(line, "info")
		end
	end

	local won = result and (result.winner == mySide)
	local byFlight = result and result.byFlight

	if byFlight then
		turnIndicator.Text = "KAMPF BEENDET - Rueckzug"
		turnPanel.BackgroundColor3 = Color3.fromRGB(110, 95, 40)
		AddLogEntry(won and "🏳️ Gegner flieht!" or "🏳️ Rueckzug!", "flee")
	elseif won then
		turnIndicator.Text = "🏆 SIEG!"
		turnPanel.BackgroundColor3 = COLORS.turnMine
		AddLogEntry("🏆 Sieg!", "heal")
	else
		turnIndicator.Text = "💀 NIEDERLAGE"
		turnPanel.BackgroundColor3 = COLORS.turnEnemy
		AddLogEntry("💀 Niederlage!", "death")
	end

	isMyTurn = false
	autoResolving = false
	EnableUnitSelection(false)
	closeButton.Visible = true
	autoResolveButton.Visible = false
	if countdownConn then countdownConn:Disconnect() countdownConn = nil end
	countdownFill.Size = UDim2.fromScale(0, 1)

	local closingId = data.combatId
	task.delay(5, function()
		if currentCombatId == nil or currentCombatId == closingId then
			closeOverlay()
		end
	end)
end)

--------------------------------------------------------------------------------
-- AUTO RESOLVE
--------------------------------------------------------------------------------
safeOn("CombatAutoResolveVote", function(data)
	if not data or data.combatId ~= currentCombatId then return end
	if autoResolving then return end

	local votes = data.votes or {}
	local iAgreed = mySide and votes[mySide] == true

	if iAgreed then
		autoResolveButton.Text = "⏳ Warte auf Gegner..."
		autoResolveButton:SetAttribute("Disabled", true)
		autoResolveButton.BackgroundColor3 = COLORS.btnDisabled
	else
		-- The opponent wants to skip: highlight our button.
		autoResolveButton.Text = "⚡ Auto-Resolve (Gegner bereit)"
		autoResolveButton.BackgroundColor3 = Color3.fromRGB(90, 130, 70)
	end
end)

safeOn("CombatAutoResolveStart", function(data)
	if not data or data.combatId ~= currentCombatId then return end

	autoResolving = true
	autoResolveButton.Text = "⚡ Wird berechnet..."
	autoResolveButton:SetAttribute("Disabled", true)
	autoResolveButton.BackgroundColor3 = COLORS.btnDisabled

	-- Freeze the manual UI: no clicks, no countdown.
	isMyTurn = false
	EnableUnitSelection(false)
	if countdownConn then countdownConn:Disconnect() countdownConn = nil end
	countdownFill.Size = UDim2.fromScale(0, 1)

	turnIndicator.Text = "⚡ Auto-Resolve laeuft..."
	AddLogEntry("⚡ Auto-Resolve: Kampf wird ausgerechnet...", "info")
end)

autoResolveButton.Activated:Connect(function()
	if not currentCombatId or autoResolving then return end
	if autoResolveButton:GetAttribute("Disabled") then return end

	Net.Fire("CombatAutoResolve", currentCombatId)

	-- Optimistic feedback; the server confirms via CombatAutoResolveVote.
	autoResolveButton.Text = "⏳ Warte auf Gegner..."
	autoResolveButton:SetAttribute("Disabled", true)
	autoResolveButton.BackgroundColor3 = COLORS.btnDisabled
end)

safeOn("FleeResult", function(data)
	if data and not data.success then
		turnIndicator.Text = "Rueckzug nicht moeglich: " .. tostring(data.reason)
		AddLogEntry("🏳️ Rueckzug nicht moeglich: " .. tostring(data.reason), "flee")
	end
end)

--------------------------------------------------------------------------------
-- BUTTONS
--------------------------------------------------------------------------------
fleeButton.Activated:Connect(function()
	if not currentCombatId then return end
	Net.Fire("FleeRequest", currentCombatId)
	fleeButton.Text = "Rueckzug laeuft..."
end)

closeButton.Activated:Connect(closeOverlay)

--------------------------------------------------------------------------------
-- PUBLIC HOOK for ArmyPanel ("Kampf ansehen")
--------------------------------------------------------------------------------
local openEvent = ReplicatedStorage:FindFirstChild("OpenCombatView")
if not openEvent then
	openEvent = Instance.new("BindableEvent")
	openEvent.Name = "OpenCombatView"
	openEvent.Parent = ReplicatedStorage
end

openEvent.Event:Connect(function()
	local ok, snapshot = Net.Invoke("GetCombatSnapshot", currentCombatId)
	if ok and snapshot then
		currentCombatId = snapshot.combatId
		gui.Enabled = true
		closeButton.Visible = true
		markArmies(snapshot, true)
		ClientState.SetCombat(true, snapshot.combatId)
		renderSnapshot(snapshot)
		isMyTurn = (snapshot.activeSide ~= nil and snapshot.activeSide == mySide)
		updateTurnPanelColor(isMyTurn)
		EnableUnitSelection(isMyTurn)
		AddLogEntry("⚔️ Kampf-Ansicht geoeffnet", "info")
	end
end)

print("[CombatGuiController] Bereit (code-generiert, Fantasy-Stil, Ping-Pong-Layout).")
