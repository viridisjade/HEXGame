--[[
    TechTreeGuiController (LocalScript)
    Location: StarterGui > TechTreeGui > TechTreeGuiController

    Complete tech tree UI. The whole layout is built at runtime
    (ensure pattern), so nothing has to be modelled in Studio.

    LAYOUT (full paths, auto created when missing)
        TechTreeGui > TechTreeOverlay
          TitleLabel          (TextLabel)
          CloseButton         (TextButton, top right)
          CategoryContainer   (Frame, 4 columns side by side)
            MilitaryColumn / EconomyColumn / InfrastructureColumn / KnowledgeColumn
              CategoryHeader  (TextLabel)
              CategoryBar     (Frame)  > Fill
              TechList        (ScrollingFrame)  > TechButton_<TechId>
          QueuePanel          (Frame, bottom)
            QueueTitle        (TextLabel)
            QueueList         (ScrollingFrame, horizontal)
            TotalRPLabel      (TextLabel)
          Tooltip             (Frame, follows the mouse)

    BUTTON STATES
        grey   = not researched, not queued   -> click adds to the queue
        blue   = queued (being researched)    -> click removes it
        green  = researched                   -> click does nothing
        dimmed = queued but no RP income      -> would never finish
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage:WaitForChild("Net"))
local TechConfig = require(ReplicatedStorage:WaitForChild("TechConfig"))

local localPlayer = Players.LocalPlayer

--------------------------------------------------------------------------------
-- ROOT GUI
--------------------------------------------------------------------------------
local gui = script.Parent
if not gui:IsA("ScreenGui") then
	gui = script.Parent:FindFirstAncestorWhichIsA("ScreenGui")
end
if not gui then
	warn("[TechTreeGui] Keine ScreenGui gefunden")
	return
end

gui.Enabled = false
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true

local COLORS = {
	locked     = Color3.fromRGB(52, 56, 68),   -- grey  = available
	queued     = Color3.fromRGB(48, 96, 170),  -- blue  = in queue
	done       = Color3.fromRGB(46, 130, 62),  -- green = researched
	stalled    = Color3.fromRGB(38, 40, 48),   -- dark  = queued without RP
	text       = Color3.fromRGB(238, 240, 248),
	textDim    = Color3.fromRGB(168, 174, 190),
	barFill    = Color3.fromRGB(120, 200, 255),
	accent     = Color3.fromRGB(255, 205, 90),
}

local function ensure(parent, class, name, setup)
	local existing = parent:FindFirstChild(name)
	if existing then return existing end
	local obj = Instance.new(class)
	obj.Name = name
	if setup then setup(obj) end
	obj.Parent = parent
	return obj
end

--------------------------------------------------------------------------------
-- STATIC UI
--------------------------------------------------------------------------------
local overlay = ensure(gui, "Frame", "TechTreeOverlay", function(f)
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = Color3.fromRGB(8, 10, 16)
	f.BackgroundTransparency = 0.15
	f.BorderSizePixel = 0
end)

local titleLabel = ensure(overlay, "TextLabel", "TitleLabel", function(l)
	l.Size = UDim2.new(0, 460, 0, 42)
	l.Position = UDim2.new(0.5, -230, 0, 14)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextSize = 26
	l.TextColor3 = COLORS.accent
	l.Text = "Technologie-Baum"
end)

local closeButton = ensure(overlay, "TextButton", "CloseButton", function(b)
	b.Size = UDim2.fromOffset(40, 40)
	b.Position = UDim2.new(1, -54, 0, 14)
	b.BackgroundColor3 = Color3.fromRGB(70, 70, 82)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 20
	b.TextColor3 = COLORS.text
	b.Text = "\u{2715}"
	b.BorderSizePixel = 0
end)
ensure(closeButton, "UICorner", "Corner")

local categoryContainer = ensure(overlay, "Frame", "CategoryContainer", function(f)
	f.Size = UDim2.new(1, -60, 1, -260)
	f.Position = UDim2.new(0, 30, 0, 66)
	f.BackgroundTransparency = 1
end)
ensure(categoryContainer, "UIListLayout", "Layout", function(l)
	l.FillDirection = Enum.FillDirection.Horizontal
	l.Padding = UDim.new(0, 12)
	l.SortOrder = Enum.SortOrder.LayoutOrder
end)

--------------------------------------------------------------------------------
-- QUEUE PANEL (bottom)
--
-- Split into two areas:
--   1. ActiveTechFrame    - the FIRST queue entry, large, full width,
--                           glowing background, progress bar + rounds left
--   2. WaitingQueueFrame  - queue positions 2+, small tiles arranged by a
--                           UIGridLayout that wraps into new rows
--------------------------------------------------------------------------------
local queuePanel = ensure(overlay, "Frame", "QueuePanel", function(f)
	f.Size = UDim2.new(1, -60, 0, 240)
	f.Position = UDim2.new(0, 30, 1, -256)
	f.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
	f.BackgroundTransparency = 0.1
	f.BorderSizePixel = 0
end)
ensure(queuePanel, "UICorner", "Corner")

local queueTitle = ensure(queuePanel, "TextLabel", "QueueTitle", function(l)
	l.Size = UDim2.new(0, 320, 0, 26)
	l.Position = UDim2.new(0, 12, 0, 6)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextSize = 17
	l.TextColor3 = COLORS.text
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = "\u{1F52C} Forschungs-Queue"
end)

local totalRPLabel = ensure(queuePanel, "TextLabel", "TotalRPLabel", function(l)
	l.Size = UDim2.new(0, 320, 0, 26)
	l.Position = UDim2.new(1, -332, 0, 6)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextSize = 16
	l.TextColor3 = COLORS.barFill
	l.TextXAlignment = Enum.TextXAlignment.Right
	l.Text = "RP pro Runde: 0"
end)

--------------------------------------------------------------------------------
-- AREA 1: the tech currently being researched (queue position 1)
--------------------------------------------------------------------------------
local activeTechFrame = ensure(queuePanel, "Frame", "ActiveTechFrame", function(f)
	f.Size = UDim2.new(1, -24, 0, 70)
	f.Position = UDim2.new(0, 12, 0, 36)
	f.BackgroundColor3 = Color3.fromRGB(32, 62, 112)
	f.BackgroundTransparency = 0.05
	f.BorderSizePixel = 0
end)
ensure(activeTechFrame, "UICorner", "Corner")
-- Subtle glow so the active tech stands out from the waiting tiles.
ensure(activeTechFrame, "UIStroke", "Glow", function(s)
	s.Thickness = 2
	s.Color = Color3.fromRGB(110, 180, 255)
	s.Transparency = 0.45
end)

local activeTechCategory = ensure(activeTechFrame, "TextLabel", "ActiveTechCategory", function(l)
	l.Size = UDim2.fromOffset(36, 28)
	l.Position = UDim2.new(0, 10, 0, 8)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextSize = 20
	l.Text = ""
	l.ZIndex = 3
end)

local activeTechName = ensure(activeTechFrame, "TextLabel", "ActiveTechName", function(l)
	l.Size = UDim2.new(1, -260, 0, 24)
	l.Position = UDim2.new(0, 52, 0, 8)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextSize = 18
	l.TextColor3 = COLORS.text
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Text = "Keine Tech in der Queue"
end)

local activeTechRounds = ensure(activeTechFrame, "TextLabel", "ActiveTechRoundsLeft", function(l)
	l.Size = UDim2.new(0, 190, 0, 20)
	l.Position = UDim2.new(1, -200, 0, 8)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextSize = 14
	l.TextColor3 = COLORS.accent
	l.TextXAlignment = Enum.TextXAlignment.Right
	l.Text = ""
end)

local activeProgressBar = ensure(activeTechFrame, "Frame", "ActiveTechProgressBar", function(f)
	f.Size = UDim2.new(1, -290, 0, 14)
	f.Position = UDim2.new(0, 52, 0, 38)
	f.BackgroundColor3 = Color3.fromRGB(16, 18, 26)
	f.BorderSizePixel = 0
end)
local activeProgressFill = ensure(activeProgressBar, "Frame", "Fill", function(f)
	f.Size = UDim2.fromScale(0, 1)
	f.BackgroundColor3 = COLORS.barFill
	f.BorderSizePixel = 0
end)

local activeProgressText = ensure(activeTechFrame, "TextLabel", "ActiveTechProgressText", function(l)
	l.Size = UDim2.new(0, 220, 0, 16)
	l.Position = UDim2.new(1, -230, 0, 38)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.Gotham
	l.TextSize = 13
	l.TextColor3 = COLORS.textDim
	l.TextXAlignment = Enum.TextXAlignment.Right
	l.Text = ""
end)

-- Remove button for the active tech (top right corner).
local activeRemoveButton = ensure(activeTechFrame, "TextButton", "ActiveRemoveButton", function(b)
	b.Size = UDim2.fromOffset(22, 22)
	b.Position = UDim2.new(1, -26, 0, 4)
	b.BackgroundColor3 = Color3.fromRGB(140, 60, 60)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 13
	b.TextColor3 = COLORS.text
	b.Text = "\u{2715}"
	b.BorderSizePixel = 0
	b.Visible = false
	b.ZIndex = 5
end)
ensure(activeRemoveButton, "UICorner", "Corner")

--------------------------------------------------------------------------------
-- AREA 2: waiting queue (positions 2+) as small tiles in a wrapping grid
--------------------------------------------------------------------------------
local waitingQueueFrame = ensure(queuePanel, "Frame", "WaitingQueueFrame", function(f)
	f.Size = UDim2.new(1, -24, 1, -118)
	f.Position = UDim2.new(0, 12, 0, 112)
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.AutomaticSize = Enum.AutomaticSize.Y
end)
-- UIGridLayout fills one row after another and wraps automatically.
ensure(waitingQueueFrame, "UIGridLayout", "GridLayout", function(g)
	g.CellSize = UDim2.fromOffset(140, 52)
	g.CellPadding = UDim2.fromOffset(8, 8)
	g.FillDirection = Enum.FillDirection.Horizontal
	g.FillDirectionMaxCells = 0          -- unlimited cells per row
	g.SortOrder = Enum.SortOrder.LayoutOrder
end)
ensure(waitingQueueFrame, "UIPadding", "Padding", function(p)
	p.PaddingTop = UDim.new(0, 4)
end)

--------------------------------------------------------------------------------
-- TOOLTIP
--------------------------------------------------------------------------------
local tooltip = ensure(overlay, "Frame", "Tooltip", function(f)
	f.Size = UDim2.fromOffset(280, 96)
	f.BackgroundColor3 = Color3.fromRGB(24, 26, 34)
	f.BorderSizePixel = 0
	f.Visible = false
	f.ZIndex = 50
end)
ensure(tooltip, "UICorner", "Corner")
local tooltipTitle = ensure(tooltip, "TextLabel", "Title", function(l)
	l.Size = UDim2.new(1, -16, 0, 22)
	l.Position = UDim2.new(0, 8, 0, 6)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextSize = 15
	l.TextColor3 = COLORS.accent
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.ZIndex = 51
	l.Text = ""
end)
local tooltipBody = ensure(tooltip, "TextLabel", "Body", function(l)
	l.Size = UDim2.new(1, -16, 1, -34)
	l.Position = UDim2.new(0, 8, 0, 28)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.Gotham
	l.TextSize = 13
	l.TextColor3 = COLORS.text
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Top
	l.TextWrapped = true
	l.ZIndex = 51
	l.Text = ""
end)

--------------------------------------------------------------------------------
-- CLIENT STATE
--------------------------------------------------------------------------------
local state = {
	researchedTechs = {},
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
local function isResearched(techId)
	return state.researchedTechs[techId] == true
end

local function queueIndex(techId)
	for i, id in ipairs(state.researchQueue) do
		if id == techId then return i end
	end
	return nil
end

-- FormatTechEffect(techId) -> readable multi line text
local function FormatTechEffect(techId)
	local tech = TechConfig.GetTech(techId)
	if not tech then return "" end

	local lines = { tech.Description }
	table.insert(lines, ("Kosten: %d RP"):format(tech.Cost))

	local progress = state.currentProgress[techId]
	if isResearched(techId) then
		table.insert(lines, "Status: erforscht")
	elseif progress then
		table.insert(lines, ("Fortschritt: %d / %d RP")
			:format(progress.current or 0, progress.max or tech.Cost))
		if (progress.roundsLeft or -1) >= 0 then
			table.insert(lines, ("Noch ca. %d Runden"):format(progress.roundsLeft))
		end
	end
	return table.concat(lines, "\n")
end

local function ShowTooltip(techId, button)
	local tech = TechConfig.GetTech(techId)
	if not tech then return end

	tooltipTitle.Text = tech.Name
	tooltipBody.Text = FormatTechEffect(techId)
	tooltip.Visible = true

	-- Place the tooltip next to the button, clamped to the screen.
	local abs = button.AbsolutePosition
	local screen = overlay.AbsoluteSize
	local x = math.clamp(abs.X + 10, 10, math.max(10, screen.X - 290))
	local y = math.clamp(abs.Y - 100, 10, math.max(10, screen.Y - 110))
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

	local idx = queueIndex(techId)
	local statusLabel = button:FindFirstChild("Status")
	local progressFill = button:FindFirstChild("Progress")
		and button.Progress:FindFirstChild("Fill")

	if isResearched(techId) then
		button.BackgroundColor3 = COLORS.done
		if statusLabel then statusLabel.Text = "\u{2705} erforscht" end
		if progressFill then progressFill.Size = UDim2.fromScale(1, 1) end

	elseif idx then
		-- Queued: dim it when there is no RP income at all.
		local stalled = (state.totalRPPerRound or 0) <= 0
		button.BackgroundColor3 = stalled and COLORS.stalled or COLORS.queued

		local prog = state.currentProgress[techId]
		local cur = prog and prog.current or 0
		local max = prog and prog.max or tech.Cost
		local rounds = prog and prog.roundsLeft or -1

		if statusLabel then
			if stalled or rounds < 0 then
				statusLabel.Text = ("#%d  %d/%d RP"):format(idx, cur, max)
			else
				statusLabel.Text = ("#%d  %d/%d RP  (%d Rd.)"):format(idx, cur, max, rounds)
			end
		end
		if progressFill then
			progressFill.Size = UDim2.fromScale(math.clamp(cur / math.max(1, max), 0, 1), 1)
		end

	else
		button.BackgroundColor3 = COLORS.locked
		local prog = state.currentProgress[techId]
		if statusLabel then
			if prog and (prog.current or 0) > 0 then
				statusLabel.Text = ("%d RP  (%d/%d gespeichert)")
					:format(tech.Cost, prog.current, prog.max or tech.Cost)
			else
				statusLabel.Text = ("%d RP"):format(tech.Cost)
			end
		end
		if progressFill then
			local cur = prog and prog.current or 0
			progressFill.Size = UDim2.fromScale(
				math.clamp(cur / math.max(1, tech.Cost), 0, 1), 1)
		end
	end
end

--------------------------------------------------------------------------------
-- UpdateCategoryBars()
--------------------------------------------------------------------------------
local function UpdateCategoryBars()
	for _, entry in ipairs(TechConfig.CategoryOrder) do
		local techs = TechConfig.GetTechsByCategory(entry.key)
		local total = #techs
		local done = 0
		for _, tech in ipairs(techs) do
			if isResearched(tech.Id) then done += 1 end
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
			header.Text = ("%s %s  (%d/%d)"):format(entry.icon, entry.label, done, total)
		end
	end
end

--------------------------------------------------------------------------------
-- OnTechClicked(techId)
--------------------------------------------------------------------------------
local function OnTechClicked(techId)
	if isResearched(techId) then return end   -- green: nothing to do

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
-- RenderCategoryColumns() - built once at startup
--------------------------------------------------------------------------------
local function buildTechButton(parent, tech, index)
	local button = Instance.new("TextButton")
	button.Name = "TechButton_" .. tech.Id
	button.Size = UDim2.new(1, -8, 0, 76)
	button.LayoutOrder = index
	button.BackgroundColor3 = COLORS.locked
	button.AutoButtonColor = false
	button.Text = ""
	button.BorderSizePixel = 0
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = button

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "TechName"
	nameLabel.Size = UDim2.new(1, -12, 0, 20)
	nameLabel.Position = UDim2.new(0, 6, 0, 5)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 14
	nameLabel.TextColor3 = COLORS.text
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Text = tech.Name
	nameLabel.Parent = button

	local descLabel = Instance.new("TextLabel")
	descLabel.Name = "TechDesc"
	descLabel.Size = UDim2.new(1, -12, 0, 26)
	descLabel.Position = UDim2.new(0, 6, 0, 24)
	descLabel.BackgroundTransparency = 1
	descLabel.Font = Enum.Font.Gotham
	descLabel.TextSize = 11
	descLabel.TextColor3 = COLORS.textDim
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.TextYAlignment = Enum.TextYAlignment.Top
	descLabel.TextWrapped = true
	descLabel.Text = tech.Description
	descLabel.Parent = button

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.Size = UDim2.new(1, -12, 0, 14)
	statusLabel.Position = UDim2.new(0, 6, 0, 52)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Font = Enum.Font.GothamBold
	statusLabel.TextSize = 11
	statusLabel.TextColor3 = COLORS.barFill
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.Text = ("%d RP"):format(tech.Cost)
	statusLabel.Parent = button

	local progressBg = Instance.new("Frame")
	progressBg.Name = "Progress"
	progressBg.Size = UDim2.new(1, -12, 0, 4)
	progressBg.Position = UDim2.new(0, 6, 1, -8)
	progressBg.BackgroundColor3 = Color3.fromRGB(24, 26, 32)
	progressBg.BorderSizePixel = 0
	progressBg.Parent = button

	local progressFill = Instance.new("Frame")
	progressFill.Name = "Fill"
	progressFill.Size = UDim2.fromScale(0, 1)
	progressFill.BackgroundColor3 = COLORS.barFill
	progressFill.BorderSizePixel = 0
	progressFill.Parent = progressBg

	button.Activated:Connect(function()
		OnTechClicked(tech.Id)
	end)
	button.MouseEnter:Connect(function()
		ShowTooltip(tech.Id, button)
	end)
	button.MouseLeave:Connect(HideTooltip)

	techButtons[tech.Id] = button
	return button
end

local function RenderCategoryColumns()
	for index, entry in ipairs(TechConfig.CategoryOrder) do
		local column = ensure(categoryContainer, "Frame", entry.key .. "Column", function(f)
			f.Size = UDim2.new(0.25, -9, 1, 0)
			f.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
			f.BackgroundTransparency = 0.1
			f.BorderSizePixel = 0
		end)
		column.LayoutOrder = index
		ensure(column, "UICorner", "Corner")

		local header = ensure(column, "TextLabel", "CategoryHeader", function(l)
			l.Size = UDim2.new(1, -12, 0, 28)
			l.Position = UDim2.new(0, 6, 0, 6)
			l.BackgroundTransparency = 1
			l.Font = Enum.Font.GothamBold
			l.TextSize = 15
			l.TextColor3 = COLORS.text
			l.TextXAlignment = Enum.TextXAlignment.Left
			l.Text = entry.icon .. " " .. entry.label
		end)
		categoryLabels[entry.key] = header

		local barBg = ensure(column, "Frame", "CategoryBar", function(f)
			f.Size = UDim2.new(1, -12, 0, 6)
			f.Position = UDim2.new(0, 6, 0, 36)
			f.BackgroundColor3 = Color3.fromRGB(30, 32, 40)
			f.BorderSizePixel = 0
		end)
		local barFill = ensure(barBg, "Frame", "Fill", function(f)
			f.Size = UDim2.fromScale(0, 1)
			f.BackgroundColor3 = COLORS.done
			f.BorderSizePixel = 0
		end)
		categoryBars[entry.key] = barFill

		local list = ensure(column, "ScrollingFrame", "TechList", function(f)
			f.Size = UDim2.new(1, -12, 1, -52)
			f.Position = UDim2.new(0, 6, 0, 48)
			f.BackgroundTransparency = 1
			f.BorderSizePixel = 0
			f.ScrollBarThickness = 5
			f.AutomaticCanvasSize = Enum.AutomaticSize.Y
			f.CanvasSize = UDim2.new()
		end)
		ensure(list, "UIListLayout", "Layout", function(l)
			l.Padding = UDim.new(0, 6)
			l.SortOrder = Enum.SortOrder.LayoutOrder
		end)

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
--------------------------------------------------------------------------------
local function RenderQueue()
	totalRPLabel.Text = ("RP pro Runde: %d"):format(state.totalRPPerRound or 0)

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
		activeTechFrame.BackgroundColor3 = Color3.fromRGB(26, 28, 36)
		return
	end

	activeTechFrame.BackgroundColor3 = Color3.fromRGB(32, 62, 112)
	activeTechCategory.Text = CategoryIcon(activeTech.Category)
	activeTechName.Text = activeTech.Name
	activeRemoveButton.Visible = true

	local prog = state.currentProgress[activeId] or {}
	local cur = prog.current or 0
	local max = prog.max or activeTech.Cost
	local rounds = prog.roundsLeft or -1
	local ratio = math.clamp(cur / math.max(1, max), 0, 1)

	activeProgressFill.Size = UDim2.fromScale(ratio, 1)
	activeProgressText.Text = ("%d / %d RP  (%d%%)")
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
			local wCur = wProg.current or 0
			local wMax = wProg.max or tech.Cost
			local wRatio = math.clamp(wCur / math.max(1, wMax), 0, 1)

			local tile = Instance.new("Frame")
			tile.Name = "QueueTile_" .. techId
			tile.LayoutOrder = i          -- keeps the queue order in the grid
			tile.BackgroundColor3 = Color3.fromRGB(30, 33, 42)
			tile.BorderSizePixel = 0
			tile.Parent = waitingQueueFrame

			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 5)
			corner.Parent = tile

			-- Position badge (top left)
			local pos = Instance.new("TextLabel")
			pos.Name = "QueuePosition"
			pos.Size = UDim2.fromOffset(26, 18)
			pos.Position = UDim2.new(0, 5, 0, 3)
			pos.BackgroundTransparency = 1
			pos.Font = Enum.Font.GothamBold
			pos.TextSize = 13
			pos.TextColor3 = COLORS.accent
			pos.TextXAlignment = Enum.TextXAlignment.Left
			pos.Text = i .. "."
			pos.Parent = tile

			-- Category icon
			local icon = Instance.new("TextLabel")
			icon.Name = "QueueTechIcon"
			icon.Size = UDim2.fromOffset(22, 22)
			icon.Position = UDim2.new(0, 26, 0, 3)
			icon.BackgroundTransparency = 1
			icon.Font = Enum.Font.GothamBold
			icon.TextSize = 15
			icon.Text = CategoryIcon(tech.Category)
			icon.Parent = tile

			-- Tech name (two lines, truncated)
			local name = Instance.new("TextLabel")
			name.Name = "QueueTechName"
			name.Size = UDim2.new(1, -58, 0, 18)
			name.Position = UDim2.new(0, 52, 0, 3)
			name.BackgroundTransparency = 1
			name.Font = Enum.Font.GothamBold
			name.TextSize = 11
			name.TextColor3 = COLORS.text
			name.TextXAlignment = Enum.TextXAlignment.Left
			name.TextTruncate = Enum.TextTruncate.AtEnd
			name.Text = tech.Name
			name.Parent = tile

			-- Small progress bar so partial progress stays visible
			local barBg = Instance.new("Frame")
			barBg.Name = "TileProgress"
			barBg.Size = UDim2.new(1, -10, 0, 5)
			barBg.Position = UDim2.new(0, 5, 1, -12)
			barBg.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
			barBg.BorderSizePixel = 0
			barBg.Parent = tile

			local barFill = Instance.new("Frame")
			barFill.Size = UDim2.fromScale(wRatio, 1)
			barFill.BackgroundColor3 = COLORS.barFill
			barFill.BorderSizePixel = 0
			barFill.Parent = barBg

			-- Stored RP (bottom left, small)
			local rpText = Instance.new("TextLabel")
			rpText.Name = "TileRP"
			rpText.Size = UDim2.new(1, -10, 0, 11)
			rpText.Position = UDim2.new(0, 5, 1, -7)
			rpText.BackgroundTransparency = 1
			rpText.Font = Enum.Font.Gotham
			rpText.TextSize = 9
			rpText.TextColor3 = COLORS.textDim
			rpText.TextXAlignment = Enum.TextXAlignment.Right
			rpText.Text = (wCur > 0) and ("%d RP"):format(wCur) or ""
			rpText.Parent = tile

			-- Remove button
			local removeBtn = Instance.new("TextButton")
			removeBtn.Name = "TileRemove"
			removeBtn.Size = UDim2.fromOffset(18, 18)
			removeBtn.Position = UDim2.new(1, -20, 0, 2)
			removeBtn.BackgroundColor3 = Color3.fromRGB(120, 55, 55)
			removeBtn.Font = Enum.Font.GothamBold
			removeBtn.TextSize = 11
			removeBtn.TextColor3 = COLORS.text
			removeBtn.Text = "\u{2715}"
			removeBtn.BorderSizePixel = 0
			removeBtn.ZIndex = 5
			removeBtn.Parent = tile
			ensure(removeBtn, "UICorner", "Corner")

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

	state.researchedTechs = data.researchedTechs or {}
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
			print("[TechTreeGui] Erforscht: " .. tech.Name)
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

print("[TechTreeGuiController] Bereit - 'T' oeffnet den Technologie-Baum.")
