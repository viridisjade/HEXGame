--[[
    TechTreeGuiController (LocalScript)
    Location: StarterGui > TechTreeGui > TechTreeGuiController

    KOMPLETT CODE-GENERIERTE TechTreeGui im Fantasy-Stil (wie CityGui, ArmyGui,
    EmpireOverlayGui, CombatGui): alle Elemente werden per Instance.new()
    erzeugt, nichts wird mehr manuell in Studio gebaut.

    TIER SYSTEM (Bronze -> Silber -> Gold)
        Every tech has 3 tiers. A tech's level (0-3) is stored on the server.
        The buttons show the CURRENT tier in their name; the queue shows the
        TARGET tier (the one currently being researched).

    BUTTON STATES
        grau   = not researched, not queued   -> click queues the NEXT tier
        blau   = in queue (tier being researched) -> click removes it
        bronze = tier 1 reached
        silber = tier 2 reached
        gold   = tier 3 reached (MAX, not clickable)
        gedimmt = queued but no RP income      -> would never finish

    LAYOUT (built entirely at runtime, nothing modelled in Studio)
        TechTreeGui > TechTreeWindow
          Header              - "🔬 TECHNOLOGIE-BAUM" + Close-Button
          CategoryContainer   (Frame, 4 columns side by side)
            MilitaryColumn (rot) / EconomyColumn (gold) /
            InfrastructureColumn (blau) / KnowledgeColumn (gruen)
              CategoryHeader  (icon + name)
              CategoryBar     (Frame)  > Fill        (X/12 Stufen)
              TechList        (ScrollingFrame)  > TechButton_<TechId>
          QueuePanel          (Frame, bottom, volle Breite)
            QueueTitle        (TextLabel)
            TotalRPLabel      (TextLabel)
            ActiveTechFrame   (queue position 1, large, gold Glow)
            WaitingQueueFrame (queue positions 2+, wrapping grid)
          Tooltip             (Frame, follows the mouse)
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage:WaitForChild("Net"))
local TechConfig = require(ReplicatedStorage:WaitForChild("TechConfig"))

local localPlayer = Players.LocalPlayer

--------------------------------------------------------------------------------
-- GUI-Wurzel finden + alles Alte entfernen (CLEANUP)
--
-- Loescht ALLE Children von TechTreeGui (die alte TechTreeOverlay.rbxm
-- inkl. aller verschachtelten statischen Elemente) - NUR dieses Script
-- selbst bleibt erhalten. Alle GUI-Elemente werden im Folgenden komplett
-- neu per Code erzeugt.
--------------------------------------------------------------------------------
local gui = script.Parent
if not gui:IsA("ScreenGui") then
	gui = script.Parent:FindFirstAncestorWhichIsA("ScreenGui")
end
if not gui then
	warn("[TechTreeGui] Keine ScreenGui gefunden")
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
-- FANTASY-FARBSCHEMA (identisch zu CityGui/ArmyGui/EmpireOverlayGui/CombatGui)
--------------------------------------------------------------------------------
local COLORS = {
	windowBg    = Color3.fromRGB(35, 28, 22),
	panelBorder = Color3.fromRGB(120, 90, 50),

	headerBg   = Color3.fromRGB(80, 60, 40),
	headerText = Color3.fromRGB(255, 220, 150),

	columnBg = Color3.fromRGB(50, 40, 32),

	categoryColors = {
		Military       = Color3.fromRGB(200, 60, 60),
		Economy        = Color3.fromRGB(255, 200, 80),
		Infrastructure = Color3.fromRGB(100, 150, 200),
		Knowledge      = Color3.fromRGB(150, 200, 100),
	},

	barBg = Color3.fromRGB(60, 50, 40),

	-- Tech-Button-States
	locked  = Color3.fromRGB(55, 48, 40),   -- grau  = unerforscht
	queued  = Color3.fromRGB(50, 60, 90),   -- blau  = in queue
	bronze  = Color3.fromRGB(120, 80, 40),
	silver  = Color3.fromRGB(140, 140, 150),
	gold    = Color3.fromRGB(180, 150, 50),
	stalled = Color3.fromRGB(38, 40, 48),   -- gedimmt = queued ohne RP

	strokeQueued = Color3.fromRGB(90, 120, 200),
	strokeBronze = Color3.fromRGB(180, 120, 60),
	strokeSilver = Color3.fromRGB(180, 180, 190),
	strokeGold   = Color3.fromRGB(255, 210, 60),

	badgeBronze = Color3.fromRGB(180, 120, 60),
	badgeSilver = Color3.fromRGB(180, 180, 190),
	badgeGold   = Color3.fromRGB(255, 210, 60),

	text    = Color3.fromRGB(238, 235, 225),
	textDim = Color3.fromRGB(170, 160, 145),
	barFill = Color3.fromRGB(255, 200, 80),
	accent  = Color3.fromRGB(255, 220, 150),

	queuePanelBg = Color3.fromRGB(45, 38, 30),
	activeBg     = Color3.fromRGB(60, 50, 40),
	activeGlow   = Color3.fromRGB(255, 200, 80),
	tileBg       = Color3.fromRGB(55, 48, 40),
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

local function lighten(color, amount)
	local h, s, v = color:ToHSV()
	v = math.clamp(v + amount, 0, 1)
	return Color3.fromHSV(h, s, v)
end

local function wireButtonStyle(button, normalColor, hoverColor)
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.BackgroundColor3 = normalColor

	button.MouseEnter:Connect(function()
		button.BackgroundColor3 = hoverColor
	end)
	button.MouseLeave:Connect(function()
		button.BackgroundColor3 = normalColor
	end)
end

--------------------------------------------------------------------------------
-- TECH-TREE-WINDOW (zentriertes Overlay)
--------------------------------------------------------------------------------
local techTreeWindow = Instance.new("Frame")
techTreeWindow.Name = "TechTreeWindow"
techTreeWindow.Size = UDim2.new(0.85, 0, 0.8, 0)
techTreeWindow.Position = UDim2.new(0.5, 0, 0.5, 0)
techTreeWindow.AnchorPoint = Vector2.new(0.5, 0.5)
techTreeWindow.BackgroundColor3 = COLORS.windowBg
techTreeWindow.BackgroundTransparency = 0.05
techTreeWindow.BorderSizePixel = 0
techTreeWindow.Parent = gui
makeCorner(techTreeWindow, 12)
makeStroke(techTreeWindow, 3, COLORS.panelBorder)

--------------------------------------------------------------------------------
-- HEADER (goldbraun) - Titel + Close-Button
--------------------------------------------------------------------------------
local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 50)
header.Position = UDim2.new(0, 0, 0, 0)
header.BackgroundColor3 = COLORS.headerBg
header.BorderSizePixel = 0
header.Parent = techTreeWindow
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
titleLabel.Size = UDim2.new(1, -70, 1, 0)
titleLabel.Position = UDim2.new(0, 16, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = FONT_TITLE
titleLabel.TextSize = 22
titleLabel.TextColor3 = COLORS.headerText
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Text = "🔬 TECHNOLOGIE-BAUM"
titleLabel.Parent = header

local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.Size = UDim2.fromOffset(36, 34)
closeButton.Position = UDim2.new(1, -46, 0.5, -17)
closeButton.BackgroundColor3 = Color3.fromRGB(70, 70, 82)
closeButton.Font = FONT_VALUE
closeButton.TextSize = 16
closeButton.TextColor3 = Color3.new(1, 1, 1)
closeButton.Text = "X"
closeButton.BorderSizePixel = 0
closeButton.Parent = header
makeCorner(closeButton, 6)
wireButtonStyle(closeButton, Color3.fromRGB(70, 70, 82), Color3.fromRGB(95, 95, 108))

--------------------------------------------------------------------------------
-- BODY (enthaelt CategoryContainer + QueuePanel, manuell positioniert damit
-- QueuePanel eine feste Hoehe behaelt und CategoryContainer den Rest nutzt).
--------------------------------------------------------------------------------
local body = Instance.new("Frame")
body.Name = "Body"
body.Size = UDim2.new(1, -20, 1, -60)
body.Position = UDim2.new(0, 10, 0, 54)
body.BackgroundTransparency = 1
body.Parent = techTreeWindow

local QUEUE_PANEL_HEIGHT = 200
local GAP = 8

--------------------------------------------------------------------------------
-- CATEGORY-CONTAINER (4 Spalten nebeneinander)
--------------------------------------------------------------------------------
local categoryContainer = Instance.new("Frame")
categoryContainer.Name = "CategoryContainer"
categoryContainer.Size = UDim2.new(1, 0, 1, -(QUEUE_PANEL_HEIGHT + GAP))
categoryContainer.Position = UDim2.new(0, 0, 0, 0)
categoryContainer.BackgroundTransparency = 1
categoryContainer.Parent = body

local categoryListLayout = Instance.new("UIListLayout")
categoryListLayout.FillDirection = Enum.FillDirection.Horizontal
categoryListLayout.Padding = UDim.new(0, 8)
categoryListLayout.SortOrder = Enum.SortOrder.LayoutOrder
categoryListLayout.Parent = categoryContainer

--------------------------------------------------------------------------------
-- QUEUE-PANEL (unten, volle Breite)
--------------------------------------------------------------------------------
local queuePanel = Instance.new("Frame")
queuePanel.Name = "QueuePanel"
queuePanel.Size = UDim2.new(1, 0, 0, QUEUE_PANEL_HEIGHT)
queuePanel.Position = UDim2.new(0, 0, 1, -QUEUE_PANEL_HEIGHT)
queuePanel.BackgroundColor3 = COLORS.queuePanelBg
queuePanel.BorderSizePixel = 0
queuePanel.Parent = body
makeCorner(queuePanel, 8)
makeStroke(queuePanel, 2, COLORS.panelBorder)

local queueTitle = Instance.new("TextLabel")
queueTitle.Name = "QueueTitle"
queueTitle.Size = UDim2.new(0, 320, 0, 24)
queueTitle.Position = UDim2.new(0, 12, 0, 6)
queueTitle.BackgroundTransparency = 1
queueTitle.Font = FONT_VALUE
queueTitle.TextSize = 16
queueTitle.TextColor3 = COLORS.headerText
queueTitle.TextXAlignment = Enum.TextXAlignment.Left
queueTitle.Text = "🔬 FORSCHUNGS-QUEUE"
queueTitle.Parent = queuePanel

local totalRPLabel = Instance.new("TextLabel")
totalRPLabel.Name = "TotalRPLabel"
totalRPLabel.Size = UDim2.new(0, 220, 0, 24)
totalRPLabel.Position = UDim2.new(1, -232, 0, 6)
totalRPLabel.BackgroundTransparency = 1
totalRPLabel.Font = FONT_VALUE
totalRPLabel.TextSize = 15
totalRPLabel.TextColor3 = COLORS.barFill
totalRPLabel.TextXAlignment = Enum.TextXAlignment.Right
totalRPLabel.Text = "RP/Runde: 0"
totalRPLabel.Parent = queuePanel

--------------------------------------------------------------------------------
-- AREA 1: the tech currently being researched (queue position 1)
--------------------------------------------------------------------------------
local activeTechFrame = Instance.new("Frame")
activeTechFrame.Name = "ActiveTechFrame"
activeTechFrame.Size = UDim2.new(1, -24, 0, 62)
activeTechFrame.Position = UDim2.new(0, 12, 0, 32)
activeTechFrame.BackgroundColor3 = COLORS.activeBg
activeTechFrame.BorderSizePixel = 0
activeTechFrame.Parent = queuePanel
makeCorner(activeTechFrame, 8)
makeStroke(activeTechFrame, 2, COLORS.activeGlow, 0, "Glow")

local activeTechCategory = Instance.new("TextLabel")
activeTechCategory.Name = "ActiveTechCategory"
activeTechCategory.Size = UDim2.fromOffset(32, 26)
activeTechCategory.Position = UDim2.new(0, 10, 0, 6)
activeTechCategory.BackgroundTransparency = 1
activeTechCategory.Font = FONT_VALUE
activeTechCategory.TextSize = 18
activeTechCategory.Text = ""
activeTechCategory.ZIndex = 3
activeTechCategory.Parent = activeTechFrame

local activeTechName = Instance.new("TextLabel")
activeTechName.Name = "ActiveTechName"
activeTechName.Size = UDim2.new(1, -260, 0, 20)
activeTechName.Position = UDim2.new(0, 48, 0, 4)
activeTechName.BackgroundTransparency = 1
activeTechName.Font = FONT_VALUE
activeTechName.TextSize = 15
activeTechName.TextColor3 = COLORS.text
activeTechName.TextXAlignment = Enum.TextXAlignment.Left
activeTechName.TextTruncate = Enum.TextTruncate.AtEnd
activeTechName.Text = "Keine Tech in der Queue"
activeTechName.Parent = activeTechFrame

local activeTechRounds = Instance.new("TextLabel")
activeTechRounds.Name = "ActiveTechRoundsLeft"
activeTechRounds.Size = UDim2.new(0, 180, 0, 18)
activeTechRounds.Position = UDim2.new(1, -192, 0, 4)
activeTechRounds.BackgroundTransparency = 1
activeTechRounds.Font = FONT_VALUE
activeTechRounds.TextSize = 12
activeTechRounds.TextColor3 = COLORS.accent
activeTechRounds.TextXAlignment = Enum.TextXAlignment.Right
activeTechRounds.Text = ""
activeTechRounds.Parent = activeTechFrame

local activeProgressBar = Instance.new("Frame")
activeProgressBar.Name = "ActiveTechProgressBar"
activeProgressBar.Size = UDim2.new(1, -280, 0, 12)
activeProgressBar.Position = UDim2.new(0, 48, 0, 30)
activeProgressBar.BackgroundColor3 = Color3.fromRGB(25, 22, 18)
activeProgressBar.BorderSizePixel = 0
activeProgressBar.Parent = activeTechFrame
makeCorner(activeProgressBar, 4)

local activeProgressFill = Instance.new("Frame")
activeProgressFill.Name = "Fill"
activeProgressFill.Size = UDim2.fromScale(0, 1)
activeProgressFill.BackgroundColor3 = COLORS.activeGlow
activeProgressFill.BorderSizePixel = 0
activeProgressFill.Parent = activeProgressBar
makeCorner(activeProgressFill, 4)

local activeProgressText = Instance.new("TextLabel")
activeProgressText.Name = "ActiveTechProgressText"
activeProgressText.Size = UDim2.new(0, 210, 0, 14)
activeProgressText.Position = UDim2.new(1, -222, 0, 30)
activeProgressText.BackgroundTransparency = 1
activeProgressText.Font = FONT_DESC
activeProgressText.TextSize = 12
activeProgressText.TextColor3 = COLORS.textDim
activeProgressText.TextXAlignment = Enum.TextXAlignment.Right
activeProgressText.Text = ""
activeProgressText.Parent = activeTechFrame

-- Remove button for the active tech (top right corner).
local activeRemoveButton = Instance.new("TextButton")
activeRemoveButton.Name = "ActiveRemoveButton"
activeRemoveButton.Size = UDim2.fromOffset(20, 20)
activeRemoveButton.Position = UDim2.new(1, -24, 0, 4)
activeRemoveButton.BackgroundColor3 = Color3.fromRGB(140, 60, 60)
activeRemoveButton.Font = FONT_VALUE
activeRemoveButton.TextSize = 12
activeRemoveButton.TextColor3 = Color3.new(1, 1, 1)
activeRemoveButton.Text = "X"
activeRemoveButton.BorderSizePixel = 0
activeRemoveButton.Visible = false
activeRemoveButton.ZIndex = 5
activeRemoveButton.Parent = activeTechFrame
makeCorner(activeRemoveButton, 4)

--------------------------------------------------------------------------------
-- AREA 2: waiting queue (positions 2+) as small tiles in a wrapping grid
--------------------------------------------------------------------------------
local waitingQueueFrame = Instance.new("Frame")
waitingQueueFrame.Name = "WaitingQueueFrame"
waitingQueueFrame.Size = UDim2.new(1, -24, 1, -104)
waitingQueueFrame.Position = UDim2.new(0, 12, 0, 100)
waitingQueueFrame.BackgroundTransparency = 1
waitingQueueFrame.BorderSizePixel = 0
waitingQueueFrame.Parent = queuePanel

local waitingGridLayout = Instance.new("UIGridLayout")
waitingGridLayout.CellSize = UDim2.fromOffset(120, 82)
waitingGridLayout.CellPadding = UDim2.fromOffset(8, 8)
waitingGridLayout.FillDirection = Enum.FillDirection.Horizontal
waitingGridLayout.FillDirectionMaxCells = 0 -- unlimited cells per row
waitingGridLayout.SortOrder = Enum.SortOrder.LayoutOrder
waitingGridLayout.Parent = waitingQueueFrame

--------------------------------------------------------------------------------
-- TOOLTIP
--------------------------------------------------------------------------------
local tooltip = Instance.new("Frame")
tooltip.Name = "Tooltip"
tooltip.Size = UDim2.fromOffset(300, 110)
tooltip.BackgroundColor3 = COLORS.windowBg
tooltip.BackgroundTransparency = 0.05
tooltip.BorderSizePixel = 0
tooltip.Visible = false
tooltip.ZIndex = 50
tooltip.Parent = techTreeWindow
makeCorner(tooltip, 8)
makeStroke(tooltip, 2, COLORS.panelBorder)

local tooltipTitle = Instance.new("TextLabel")
tooltipTitle.Name = "Title"
tooltipTitle.Size = UDim2.new(1, -16, 0, 22)
tooltipTitle.Position = UDim2.new(0, 8, 0, 6)
tooltipTitle.BackgroundTransparency = 1
tooltipTitle.Font = FONT_VALUE
tooltipTitle.TextSize = 15
tooltipTitle.TextColor3 = COLORS.accent
tooltipTitle.TextXAlignment = Enum.TextXAlignment.Left
tooltipTitle.ZIndex = 51
tooltipTitle.Text = ""
tooltipTitle.Parent = tooltip

local tooltipBody = Instance.new("TextLabel")
tooltipBody.Name = "Body"
tooltipBody.Size = UDim2.new(1, -16, 1, -34)
tooltipBody.Position = UDim2.new(0, 8, 0, 28)
tooltipBody.BackgroundTransparency = 1
tooltipBody.Font = FONT_DESC
tooltipBody.TextSize = 13
tooltipBody.TextColor3 = COLORS.text
tooltipBody.TextXAlignment = Enum.TextXAlignment.Left
tooltipBody.TextYAlignment = Enum.TextYAlignment.Top
tooltipBody.TextWrapped = true
tooltipBody.ZIndex = 51
tooltipBody.Text = ""
tooltipBody.Parent = tooltip

--------------------------------------------------------------------------------
-- CLIENT STATE
--------------------------------------------------------------------------------
local state = {
	techLevels = {},
	researchQueue = {},
	currentProgress = {},
	totalRPPerRound = 0,
}

local techButtons = {}     -- techId -> button frame
local categoryBars = {}    -- category -> fill frame
local categoryLabels = {}  -- category -> header label

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------
local function GetLevel(techId)
	return state.techLevels[techId] or 0
end

local function isMaxed(techId)
	return GetLevel(techId) >= TechConfig.MAX_LEVEL
end

local function queueIndex(techId)
	for i, id in ipairs(state.researchQueue) do
		if id == techId then return i end
	end
	return nil
end

local function TierLabel(techId, level)
	local name = TechConfig.GetLevelName(level)
	local tech = TechConfig.GetTech(techId)
	if (not name) or name == "" then return tech and tech.Name or techId end
	return ("[%s] %s"):format(name, tech and tech.Name or techId)
end

-- LevelBadgeColor(level) -> the badge colour for a reached tier.
local function LevelBadgeColor(level)
	if level == 1 then return COLORS.badgeBronze end
	if level == 2 then return COLORS.badgeSilver end
	if level == 3 then return COLORS.badgeGold end
	return nil
end

--------------------------------------------------------------------------------
-- FormatTechEffect(techId) -> readable multi line text (for the tooltip)
--------------------------------------------------------------------------------
local function FormatTechEffect(techId)
	local tech = TechConfig.GetTech(techId)
	if not tech then return "" end

	local level = GetLevel(techId)
	local lines = { tech.Description }

	-- Current tier effect (only when at least tier 1 reached).
	if level >= 1 then
		local cur = TechConfig.GetTechLevel(techId, level)
		if cur then
			table.insert(lines, ("Aktuell [%s]: %s"):format(
				TechConfig.GetLevelName(level), cur.Desc))
		end
	end

	-- Next tier (cost of the tier currently / next to be researched).
	local nextLevel = TechConfig.GetNextLevel(level)
	if nextLevel then
		local nxt = TechConfig.GetTechLevel(techId, nextLevel)
		if nxt then
			table.insert(lines, ("Naechste Stufe [%s]: %s"):format(
				TechConfig.GetLevelName(nextLevel), nxt.Desc))
			table.insert(lines, ("Kosten: %d RP"):format(nxt.cost))
		end
	else
		table.insert(lines, "Bereits auf Gold (max)")
	end

	-- If it is being researched, add the live progress.
	local progress = state.currentProgress[techId]
	if progress then
		local cur = progress.current or 0
		local max = progress.max or 0
		if (progress.roundsLeft or -1) >= 0 then
			table.insert(lines, ("Fortschritt: %d / %d RP (noch %d Runden)")
				:format(cur, max, progress.roundsLeft))
		else
			table.insert(lines, ("Fortschritt: %d / %d RP"):format(cur, max))
		end
	end

	return table.concat(lines, "\n")
end

local function ShowTooltip(techId, button)
	local tech = TechConfig.GetTech(techId)
	if not tech then return end

	tooltipTitle.Text = TierLabel(techId, GetLevel(techId))
	tooltipBody.Text = FormatTechEffect(techId)
	tooltip.Visible = true

	-- Place the tooltip next to the button, clamped to the window.
	local abs = button.AbsolutePosition
	local windowAbs = techTreeWindow.AbsolutePosition
	local windowSize = techTreeWindow.AbsoluteSize
	local relX = abs.X - windowAbs.X
	local relY = abs.Y - windowAbs.Y
	local x = math.clamp(relX + 10, 10, math.max(10, windowSize.X - 310))
	local y = math.clamp(relY - 100, 10, math.max(10, windowSize.Y - 120))
	tooltip.Position = UDim2.fromOffset(x, y)
end

local function HideTooltip()
	tooltip.Visible = false
end

--------------------------------------------------------------------------------
-- UpdateTechButtonState(techId)
--------------------------------------------------------------------------------
local function UpdateTechButtonState(techId)
	local button = techButtons[techId]
	if not button then return end

	local tech = TechConfig.GetTech(techId)
	if not tech then return end

	local level = GetLevel(techId)
	local idx = queueIndex(techId)
	local statusLabel = button:FindFirstChild("Status")
	local nameLabel = button:FindFirstChild("TechName")
	local progressFill = button:FindFirstChild("Progress")
		and button.Progress:FindFirstChild("Fill")
	local badge = button:FindFirstChild("Badge")
	local stroke = button:FindFirstChild("Border")

	if nameLabel then
		nameLabel.Text = tech.Name
	end

	local prog = state.currentProgress[techId]

	-- GOLD (max) - not clickable.
	if isMaxed(techId) then
		button.BackgroundColor3 = COLORS.gold
		if stroke then
			stroke.Color = COLORS.strokeGold
			stroke.Enabled = true
		end
		if badge then
			badge.Visible = true
			badge.Text = "Gold"
			badge.BackgroundColor3 = COLORS.badgeGold
		end
		if statusLabel then statusLabel.Text = "Max erreicht" end
		if progressFill then progressFill.Size = UDim2.fromScale(1, 1) end

	-- IN QUEUE - the NEXT tier is being researched.
	elseif idx then
		local stalled = (state.totalRPPerRound or 0) <= 0
		button.BackgroundColor3 = stalled and COLORS.stalled or COLORS.queued
		if stroke then
			stroke.Color = COLORS.strokeQueued
			stroke.Enabled = true
		end

		local levelBadgeColor = LevelBadgeColor(level)
		if badge then
			badge.Visible = levelBadgeColor ~= nil
			if levelBadgeColor then
				badge.Text = TechConfig.GetLevelName(level)
				badge.BackgroundColor3 = levelBadgeColor
			end
		end

		local cur = prog and prog.current or 0
		local max = prog and prog.max or TechConfig.GetLevelCost(techId, level + 1)
		local rounds = prog and prog.roundsLeft or -1

		if statusLabel then
			if stalled or rounds < 0 then
				statusLabel.Text = ("%d/%d RP"):format(cur, max)
			else
				statusLabel.Text = ("%d/%d RP (%d Rd.)"):format(cur, max, rounds)
			end
		end
		if progressFill then
			progressFill.Size = UDim2.fromScale(math.clamp(cur / math.max(1, max), 0, 1), 1)
		end

	-- TIER REACHED (bronze / silber), not queued.
	elseif level >= 1 then
		if level == 1 then
			button.BackgroundColor3 = COLORS.bronze
			if stroke then stroke.Color = COLORS.strokeBronze end
		elseif level == 2 then
			button.BackgroundColor3 = COLORS.silver
			if stroke then stroke.Color = COLORS.strokeSilver end
		end
		if stroke then stroke.Enabled = true end

		local levelBadgeColor = LevelBadgeColor(level)
		if badge then
			badge.Visible = levelBadgeColor ~= nil
			if levelBadgeColor then
				badge.Text = TechConfig.GetLevelName(level)
				badge.BackgroundColor3 = levelBadgeColor
			end
		end

		local nextLevel = TechConfig.GetNextLevel(level)
		if statusLabel then
			local nextCost = nextLevel and TechConfig.GetLevelCost(techId, nextLevel) or 0
			statusLabel.Text = nextLevel and ("Naechste: %d RP"):format(nextCost) or ""
		end
		if progressFill then
			local ratio = (prog and (prog.current or 0) > 0)
				and math.clamp((prog.current or 0) / math.max(1, prog.max or 1), 0, 1)
				or 1
			progressFill.Size = UDim2.fromScale(ratio, 1)
		end

	-- NOT RESEARCHED.
	else
		button.BackgroundColor3 = COLORS.locked
		if stroke then stroke.Enabled = false end
		if badge then badge.Visible = false end
		if statusLabel then
			local nextCost = TechConfig.GetLevelCost(techId, 1)
			if prog and (prog.current or 0) > 0 then
				statusLabel.Text = ("%d RP (%d/%d)"):format(
					nextCost, prog.current, prog.max or nextCost)
			else
				statusLabel.Text = ("%d RP"):format(nextCost)
			end
		end
		if progressFill then
			local cur = prog and prog.current or 0
			progressFill.Size = UDim2.fromScale(
				math.clamp(cur / math.max(1, TechConfig.GetLevelCost(techId, 1)), 0, 1), 1)
		end
	end
end

--------------------------------------------------------------------------------
-- UpdateCategoryBars()
-- Progress is based on ALL tiers: 4 techs x 3 tiers = 12 possible upgrades.
--------------------------------------------------------------------------------
local function UpdateCategoryBars()
	for _, entry in ipairs(TechConfig.CategoryOrder) do
		local techs = TechConfig.GetTechsByCategory(entry.key)
		local total = #techs * TechConfig.MAX_LEVEL   -- 12 per category
		local done = 0
		for _, tech in ipairs(techs) do
			done += GetLevel(tech.Id)
		end

		local fill = categoryBars[entry.key]
		if fill then
			local ratio = (total > 0) and (done / total) or 0
			TweenService:Create(fill, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
				Size = UDim2.fromScale(ratio, 1),
			}):Play()
		end

		local header = categoryLabels[entry.key]
		if header then
			header.Text = ("%s %s"):format(entry.icon, entry.label)
		end
	end
end

--------------------------------------------------------------------------------
-- OnTechClicked(techId)
--------------------------------------------------------------------------------
local function OnTechClicked(techId)
	if isMaxed(techId) then return end   -- gold: nothing to do

	if queueIndex(techId) then
		Net.Fire("TechRemoveFromQueue", techId)
	else
		Net.Fire("TechAddToQueue", techId)
	end
end

-- Removing the active tech makes the next one advance to the active slot;
-- the server pushes a fresh TechTreeUpdate which re-renders everything.
local function OnQueueRemoveClicked(techId)
	Net.Fire("TechRemoveFromQueue", techId)
end

-- The active tech has its own remove button (created with the static UI,
-- before this function exists - hence the late binding).
activeRemoveButton.Activated:Connect(function()
	if state.researchQueue[1] then
		OnQueueRemoveClicked(state.researchQueue[1])
	end
end)

--------------------------------------------------------------------------------
-- buildTechButton(parent, tech, index) - one tech tile inside a category
-- column's TechList.
--------------------------------------------------------------------------------
local function buildTechButton(parent, tech, index)
	local button = Instance.new("TextButton")
	button.Name = "TechButton_" .. tech.Id
	button.Size = UDim2.new(1, -8, 0, 66)
	button.LayoutOrder = index
	button.BackgroundColor3 = COLORS.locked
	button.AutoButtonColor = false
	button.Text = ""
	button.BorderSizePixel = 0
	button.Parent = parent
	makeCorner(button, 6)
	local border = makeStroke(button, 2, COLORS.panelBorder, 0.3, "Border")
	border.Enabled = false

	-- Level badge (top right): Bronze / Silber / Gold
	local badge = Instance.new("TextLabel")
	badge.Name = "Badge"
	badge.Size = UDim2.fromOffset(46, 16)
	badge.Position = UDim2.new(1, -50, 0, 4)
	badge.BackgroundColor3 = COLORS.badgeBronze
	badge.Font = FONT_VALUE
	badge.TextSize = 10
	badge.TextColor3 = Color3.fromRGB(30, 25, 20)
	badge.Text = ""
	badge.Visible = false
	badge.Parent = button
	makeCorner(badge, 4)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "TechName"
	nameLabel.Size = UDim2.new(1, -60, 0, 18)
	nameLabel.Position = UDim2.new(0, 6, 0, 5)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = FONT_VALUE
	nameLabel.TextSize = 13
	nameLabel.TextColor3 = COLORS.text
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Text = tech.Name
	nameLabel.Parent = button

	local descLabel = Instance.new("TextLabel")
	descLabel.Name = "TechDesc"
	descLabel.Size = UDim2.new(1, -12, 0, 22)
	descLabel.Position = UDim2.new(0, 6, 0, 22)
	descLabel.BackgroundTransparency = 1
	descLabel.Font = FONT_DESC
	descLabel.TextSize = 10
	descLabel.TextColor3 = COLORS.textDim
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.TextYAlignment = Enum.TextYAlignment.Top
	descLabel.TextWrapped = true
	descLabel.Text = tech.Description
	descLabel.Parent = button

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.Size = UDim2.new(1, -12, 0, 13)
	statusLabel.Position = UDim2.new(0, 6, 0, 44)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Font = FONT_VALUE
	statusLabel.TextSize = 11
	statusLabel.TextColor3 = COLORS.barFill
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.Text = ("%d RP"):format(TechConfig.GetLevelCost(tech.Id, 1))
	statusLabel.Parent = button

	local progressBg = Instance.new("Frame")
	progressBg.Name = "Progress"
	progressBg.Size = UDim2.new(1, -12, 0, 4)
	progressBg.Position = UDim2.new(0, 6, 1, -8)
	progressBg.BackgroundColor3 = Color3.fromRGB(25, 22, 18)
	progressBg.BorderSizePixel = 0
	progressBg.Parent = button
	makeCorner(progressBg, 2)

	local progressFill = Instance.new("Frame")
	progressFill.Name = "Fill"
	progressFill.Size = UDim2.fromScale(0, 1)
	progressFill.BackgroundColor3 = COLORS.barFill
	progressFill.BorderSizePixel = 0
	progressFill.Parent = progressBg
	makeCorner(progressFill, 2)

	button.Activated:Connect(function()
		OnTechClicked(tech.Id)
	end)
	button.MouseEnter:Connect(function()
		ShowTooltip(tech.Id, button)
		if not isMaxed(tech.Id) then
			button.BackgroundColor3 = lighten(button.BackgroundColor3, 0.15)
		end
	end)
	button.MouseLeave:Connect(function()
		HideTooltip()
		UpdateTechButtonState(tech.Id)
	end)

	techButtons[tech.Id] = button
	return button
end

--------------------------------------------------------------------------------
-- RenderCategoryColumns() - built once at startup
--------------------------------------------------------------------------------
local function RenderCategoryColumns()
	for index, entry in ipairs(TechConfig.CategoryOrder) do
		local categoryColor = COLORS.categoryColors[entry.key] or COLORS.accent

		local column = Instance.new("Frame")
		column.Name = entry.key .. "Column"
		column.Size = UDim2.new(0.25, -6, 1, 0)
		column.BackgroundColor3 = COLORS.columnBg
		column.BorderSizePixel = 0
		column.LayoutOrder = index
		column.Parent = categoryContainer
		makeCorner(column, 8)
		makeStroke(column, 2, COLORS.panelBorder)

		local header = Instance.new("TextLabel")
		header.Name = "CategoryHeader"
		header.Size = UDim2.new(1, -12, 0, 26)
		header.Position = UDim2.new(0, 6, 0, 6)
		header.BackgroundTransparency = 1
		header.Font = FONT_TITLE
		header.TextSize = 16
		header.TextColor3 = categoryColor
		header.TextXAlignment = Enum.TextXAlignment.Left
		header.Text = entry.icon .. " " .. entry.label
		header.Parent = column
		categoryLabels[entry.key] = header

		local barBg = Instance.new("Frame")
		barBg.Name = "CategoryBar"
		barBg.Size = UDim2.new(1, -12, 0, 8)
		barBg.Position = UDim2.new(0, 6, 0, 34)
		barBg.BackgroundColor3 = COLORS.barBg
		barBg.BorderSizePixel = 0
		barBg.Parent = column
		makeCorner(barBg, 4)

		local barFill = Instance.new("Frame")
		barFill.Name = "Fill"
		barFill.Size = UDim2.fromScale(0, 1)
		barFill.BackgroundColor3 = categoryColor
		barFill.BorderSizePixel = 0
		barFill.Parent = barBg
		makeCorner(barFill, 4)
		categoryBars[entry.key] = barFill

		local list = Instance.new("ScrollingFrame")
		list.Name = "TechList"
		list.Size = UDim2.new(1, -12, 1, -50)
		list.Position = UDim2.new(0, 6, 0, 46)
		list.BackgroundTransparency = 1
		list.BorderSizePixel = 0
		list.ScrollBarThickness = 5
		list.ScrollBarImageColor3 = COLORS.panelBorder
		list.AutomaticCanvasSize = Enum.AutomaticSize.Y
		list.CanvasSize = UDim2.new()
		list.Parent = column

		local listLayout = Instance.new("UIListLayout")
		listLayout.Padding = UDim.new(0, 6)
		listLayout.SortOrder = Enum.SortOrder.LayoutOrder
		listLayout.Parent = list

		for i, tech in ipairs(TechConfig.GetTechsByCategory(entry.key)) do
			if not techButtons[tech.Id] then
				buildTechButton(list, tech, i)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- CategoryIcon(category) -> string emoji
--------------------------------------------------------------------------------
local function CategoryIcon(category)
	for _, entry in ipairs(TechConfig.CategoryOrder) do
		if entry.key == category then return entry.icon end
	end
	return ""
end

--------------------------------------------------------------------------------
-- RenderQueue()
--
-- Queue position 1  -> ActiveTechFrame   (large, full width, progress bar)
-- Queue position 2+ -> WaitingQueueFrame (small tiles, wrapping UIGridLayout)
--
-- Both show the TARGET tier (the tier currently being researched).
--------------------------------------------------------------------------------
local function RenderQueue()
	totalRPLabel.Text = ("RP/Runde: %d"):format(state.totalRPPerRound or 0)

	------------------------------------------------------------------
	-- 1) ACTIVE TECH (queue position 1)
	------------------------------------------------------------------
	local activeId = state.researchQueue[1]
	local activeTech = activeId and TechConfig.GetTech(activeId) or nil

	-- Clear the waiting tiles, they are rebuilt below.
	for _, child in ipairs(waitingQueueFrame:GetChildren()) do
		if child:IsA("GuiObject") then child:Destroy() end
	end

	if not activeTech then
		activeTechName.Text = "Keine Tech in der Queue"
		activeTechCategory.Text = ""
		activeTechRounds.Text = ""
		activeProgressText.Text = ""
		activeProgressFill.Size = UDim2.fromScale(0, 1)
		activeRemoveButton.Visible = false
		activeTechFrame.BackgroundColor3 = COLORS.activeBg
		return
	end

	activeTechFrame.BackgroundColor3 = COLORS.activeBg
	activeTechCategory.Text = CategoryIcon(activeTech.Category)
	activeRemoveButton.Visible = true

	local prog = state.currentProgress[activeId] or {}
	local level = prog.level or GetLevel(activeId)
	local targetLevel = prog.targetLevel or (level + 1)
	local cur = prog.current or 0
	local max = prog.max or TechConfig.GetLevelCost(activeId, targetLevel)
	local rounds = prog.roundsLeft or -1
	local ratio = math.clamp(cur / math.max(1, max), 0, 1)

	activeTechName.Text = TierLabel(activeId, targetLevel)
	activeProgressFill.Size = UDim2.fromScale(ratio, 1)
	activeProgressText.Text = ("%d/%d RP (%d%%)")
		:format(cur, max, math.floor(ratio * 100))

	if rounds >= 0 then
		activeTechRounds.TextColor3 = COLORS.accent
		activeTechRounds.Text = (rounds == 1) and "1 Runde" or (rounds .. " Runden")
	else
		activeTechRounds.TextColor3 = Color3.fromRGB(220, 110, 110)
		activeTechRounds.Text = "kein Ertrag!"
	end

	------------------------------------------------------------------
	-- 2) WAITING QUEUE (positions 2+)
	------------------------------------------------------------------
	for i = 2, #state.researchQueue do
		local techId = state.researchQueue[i]
		local tech = TechConfig.GetTech(techId)
		if tech then
			local wProg = state.currentProgress[techId] or {}
			local wLevel = wProg.level or GetLevel(techId)
			local wTarget = wProg.targetLevel or (wLevel + 1)
			local wCur = wProg.current or 0
			local wMax = wProg.max or TechConfig.GetLevelCost(techId, wTarget)
			local wRatio = math.clamp(wCur / math.max(1, wMax), 0, 1)

			local tile = Instance.new("Frame")
			tile.Name = "QueueTile_" .. techId
			tile.LayoutOrder = i          -- keeps the queue order in the grid
			tile.BackgroundColor3 = COLORS.tileBg
			tile.BorderSizePixel = 0
			tile.Parent = waitingQueueFrame
			makeCorner(tile, 6)
			makeStroke(tile, 1, COLORS.panelBorder)

			-- Position badge (top left)
			local pos = Instance.new("TextLabel")
			pos.Name = "QueuePosition"
			pos.Size = UDim2.fromOffset(24, 16)
			pos.Position = UDim2.new(0, 5, 0, 3)
			pos.BackgroundTransparency = 1
			pos.Font = FONT_VALUE
			pos.TextSize = 12
			pos.TextColor3 = COLORS.accent
			pos.TextXAlignment = Enum.TextXAlignment.Left
			pos.Text = i .. "."
			pos.Parent = tile

			-- Category icon
			local icon = Instance.new("TextLabel")
			icon.Name = "QueueTechIcon"
			icon.Size = UDim2.fromOffset(20, 20)
			icon.Position = UDim2.new(0, 24, 0, 2)
			icon.BackgroundTransparency = 1
			icon.Font = FONT_VALUE
			icon.TextSize = 14
			icon.Text = CategoryIcon(tech.Category)
			icon.Parent = tile

			-- Tech name (with TARGET tier prefix)
			local name = Instance.new("TextLabel")
			name.Name = "QueueTechName"
			name.Size = UDim2.new(1, -12, 0, 30)
			name.Position = UDim2.new(0, 5, 0, 20)
			name.BackgroundTransparency = 1
			name.Font = FONT_VALUE
			name.TextSize = 11
			name.TextColor3 = COLORS.text
			name.TextXAlignment = Enum.TextXAlignment.Left
			name.TextYAlignment = Enum.TextYAlignment.Top
			name.TextWrapped = true
			name.Text = TierLabel(techId, wTarget)
			name.Parent = tile

			-- Small progress bar so partial progress stays visible
			local barBg = Instance.new("Frame")
			barBg.Name = "TileProgress"
			barBg.Size = UDim2.new(1, -10, 0, 5)
			barBg.Position = UDim2.new(0, 5, 1, -12)
			barBg.BackgroundColor3 = Color3.fromRGB(25, 22, 18)
			barBg.BorderSizePixel = 0
			barBg.Parent = tile
			makeCorner(barBg, 2)

			local barFill = Instance.new("Frame")
			barFill.Size = UDim2.fromScale(wRatio, 1)
			barFill.BackgroundColor3 = COLORS.barFill
			barFill.BorderSizePixel = 0
			barFill.Parent = barBg
			makeCorner(barFill, 2)

			-- Stored RP (bottom left, small)
			local rpText = Instance.new("TextLabel")
			rpText.Name = "TileRP"
			rpText.Size = UDim2.new(1, -10, 0, 11)
			rpText.Position = UDim2.new(0, 5, 1, -7)
			rpText.BackgroundTransparency = 1
			rpText.Font = FONT_DESC
			rpText.TextSize = 9
			rpText.TextColor3 = COLORS.textDim
			rpText.TextXAlignment = Enum.TextXAlignment.Right
			rpText.Text = (wCur > 0) and ("%d RP"):format(wCur) or ""
			rpText.Parent = tile

			-- Remove button
			local removeBtn = Instance.new("TextButton")
			removeBtn.Name = "TileRemove"
			removeBtn.Size = UDim2.fromOffset(16, 16)
			removeBtn.Position = UDim2.new(1, -19, 0, 2)
			removeBtn.BackgroundColor3 = Color3.fromRGB(120, 55, 55)
			removeBtn.Font = FONT_VALUE
			removeBtn.TextSize = 10
			removeBtn.TextColor3 = Color3.new(1, 1, 1)
			removeBtn.Text = "X"
			removeBtn.BorderSizePixel = 0
			removeBtn.ZIndex = 5
			removeBtn.Parent = tile
			makeCorner(removeBtn, 3)

			removeBtn.Activated:Connect(function()
				OnQueueRemoveClicked(techId)
			end)

			-- Clicking the tile itself also removes it (same as the big list).
			tile.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch then
					OnQueueRemoveClicked(techId)
				end
			end)
		end
	end
end

--------------------------------------------------------------------------------
-- OnTechTreeUpdate(data)
--------------------------------------------------------------------------------
local function OnTechTreeUpdate(data)
	if not data then return end

	state.techLevels = data.techLevels or {}
	state.researchQueue = data.researchQueue or {}
	state.currentProgress = data.currentProgress or {}
	state.totalRPPerRound = data.totalRPPerRound or 0

	for techId in pairs(TechConfig.GetAllTechs()) do
		UpdateTechButtonState(techId)
	end
	UpdateCategoryBars()
	RenderQueue()
end

--------------------------------------------------------------------------------
-- OPEN / CLOSE
--------------------------------------------------------------------------------
local function OpenTechTree()
	gui.Enabled = true
	-- Pull a fresh state so the panel is never stale after reopening.
	task.spawn(function()
		local ok, payload = Net.Invoke("GetTechState")
		if ok and payload then
			OnTechTreeUpdate(payload)
		end
	end)
end

local function CloseTechTree()
	gui.Enabled = false
	HideTooltip()
end

closeButton.Activated:Connect(CloseTechTree)

--------------------------------------------------------------------------------
-- REMOTE + HOTKEY
--------------------------------------------------------------------------------
Net.On("TechTreeUpdate", function(data)
	local ok, err = pcall(OnTechTreeUpdate, data)
	if not ok then
		warn("[TechTreeGui] Update-Fehler: " .. tostring(err))
	end
end)

Net.On("TechResearched", function(data)
	if not data or not data.techIds then return end
	for _, techId in ipairs(data.techIds) do
		local tech = TechConfig.GetTech(techId)
		if tech then
			local level = GetLevel(techId)
			print(("[TechTreeGui] Erforscht: [%s] %s"):format(
				TechConfig.GetLevelName(level), tech.Name))
		end
	end
end)

-- Public hook so other scripts (InputRouter hotkey "T") can toggle the panel.
local toggleEvent = ReplicatedStorage:FindFirstChild("ToggleTechTree")
if not toggleEvent then
	toggleEvent = Instance.new("BindableEvent")
	toggleEvent.Name = "ToggleTechTree"
	toggleEvent.Parent = ReplicatedStorage
end

toggleEvent.Event:Connect(function()
	if gui.Enabled then
		CloseTechTree()
	else
		OpenTechTree()
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.T then
		toggleEvent:Fire()
	elseif input.KeyCode == Enum.KeyCode.Escape and gui.Enabled then
		CloseTechTree()
	end
end)

--------------------------------------------------------------------------------
-- BOOT
--------------------------------------------------------------------------------
RenderCategoryColumns()
RenderQueue()
UpdateCategoryBars()
task.spawn(function()
	local ok, payload = Net.Invoke("GetTechState")
	if ok and payload then
		OnTechTreeUpdate(payload)
	end
end)

print("[TechTreeGuiController] Bereit (code-generiert, Fantasy-Stil) - 'T' oeffnet den Technologie-Baum.")
