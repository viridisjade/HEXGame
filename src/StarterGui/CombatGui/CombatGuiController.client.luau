--[[
    CombatGuiController (LocalScript)
    Location: StarterGui > CombatGui > CombatGuiController

    Pokemon style combat overlay. The whole GUI is built at runtime
    (ensure-pattern), so nothing has to be modelled in Studio.

    LAYOUT (full paths, auto-created when missing)
        CombatGui > CombatOverlay
          TurnIndicator        (TextLabel, top centre)
          CountdownBar         (Frame, top)
          PlayerCombatFrame    (Frame, bottom left)  - ALWAYS the local player
            PlayerUnitsFrame   (Frame)               <- own unit portraits
          EnemyCombatFrame     (Frame, top right)    - ALWAYS the opponent
            EnemyUnitsFrame    (Frame)               <- enemy unit portraits
          CombatLogFrame       (ScrollingFrame, right)
          AutoResolveButton    (TextButton, below the countdown bar)
          FleeButton / CloseButton

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
-- ROOT GUI
--------------------------------------------------------------------------------
local gui = script.Parent
if not gui:IsA("ScreenGui") then
	gui = script.Parent:FindFirstAncestorWhichIsA("ScreenGui")
end
if not gui then
	warn("[CombatGui] Keine ScreenGui gefunden")
	return
end

gui.Enabled = false
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true

local COLORS = {
	myTurn    = Color3.fromRGB(255, 215, 80),
	enemyTurn = Color3.fromRGB(255, 120, 120),
	selected  = Color3.fromRGB(255, 200, 40),
	target    = Color3.fromRGB(255, 90, 90),
	damage    = Color3.fromRGB(255, 70, 70),
	counter   = Color3.fromRGB(255, 165, 40),
	absorbed  = Color3.fromRGB(120, 200, 255),
	dead      = Color3.fromRGB(90, 90, 90),
	hpHigh    = Color3.fromRGB(90, 220, 90),
	hpMid     = Color3.fromRGB(240, 200, 60),
	hpLow     = Color3.fromRGB(230, 70, 70),
}

-- Battle log colour per event type.
local LOG_COLORS = {
	damage  = Color3.fromRGB(255, 90, 90),    -- attack line
	counter = Color3.fromRGB(255, 165, 40),   -- counter attack
	death   = Color3.fromRGB(170, 30, 30),    -- unit killed
	flee    = Color3.fromRGB(255, 220, 70),   -- retreat / rout
	heal    = Color3.fromRGB(110, 230, 110),  -- healing / victory
	info    = Color3.fromRGB(200, 200, 210),  -- neutral
}

local MAX_LOG_ENTRIES = 50

local function ensure(parent, class, name, setup)
	local existing = parent:FindFirstChild(name)
	if existing then return existing end
	local obj = Instance.new(class)
	obj.Name = name
	if setup then setup(obj) end
	obj.Parent = parent
	return obj
end

-- Migrates the frame names of the previous version so an existing Studio GUI
-- keeps working (MyArmyPanel -> PlayerCombatFrame, ...).
local function renameLegacy(parent, oldName, newName)
	local old = parent:FindFirstChild(oldName)
	if old and not parent:FindFirstChild(newName) then
		old.Name = newName
		warn(("[CombatGui] '%s' wurde zu '%s' umbenannt"):format(oldName, newName))
	end
end

--------------------------------------------------------------------------------
-- STATIC UI
--------------------------------------------------------------------------------
local overlay = ensure(gui, "Frame", "CombatOverlay", function(f)
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = Color3.fromRGB(10, 12, 18)
	f.BackgroundTransparency = 0.35
	f.BorderSizePixel = 0
end)

renameLegacy(overlay, "MyArmyPanel", "PlayerCombatFrame")
renameLegacy(overlay, "EnemyArmyPanel", "EnemyCombatFrame")
renameLegacy(overlay, "CombatLog", "CombatLogFrame")

local turnIndicator = ensure(overlay, "TextLabel", "TurnIndicator", function(l)
	l.Size = UDim2.new(0, 460, 0, 44)
	l.Position = UDim2.new(0.5, -230, 0, 18)
	l.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
	l.BackgroundTransparency = 0.2
	l.Font = Enum.Font.GothamBold
	l.TextSize = 24
	l.TextColor3 = COLORS.myTurn
	l.Text = "KAMPF"
	l.BorderSizePixel = 0
end)
ensure(turnIndicator, "UICorner", "Corner")

local countdownBg = ensure(overlay, "Frame", "CountdownBar", function(f)
	f.Size = UDim2.new(0, 460, 0, 8)
	f.Position = UDim2.new(0.5, -230, 0, 66)
	f.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
	f.BorderSizePixel = 0
end)
local countdownFill = ensure(countdownBg, "Frame", "Fill", function(f)
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = COLORS.myTurn
	f.BorderSizePixel = 0
end)

--------------------------------------------------------------------------------
-- AUTO RESOLVE BUTTON - both players have to agree, then the server
-- fast-forwards the whole fight.
--------------------------------------------------------------------------------
local autoResolveButton = ensure(overlay, "TextButton", "AutoResolveButton", function(b)
	b.Size = UDim2.new(0, 220, 0, 34)
	b.Position = UDim2.new(0.5, -110, 0, 82)
	b.BackgroundColor3 = Color3.fromRGB(70, 90, 150)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 15
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = "\u{26A1} Auto-Resolve"
	b.AutoButtonColor = true
	b.BorderSizePixel = 0
end)
ensure(autoResolveButton, "UICorner", "Corner")

--------------------------------------------------------------------------------
-- ENEMY FRAME (top right) - ALWAYS the opponent
--------------------------------------------------------------------------------
local enemyPanel = ensure(overlay, "Frame", "EnemyCombatFrame", function(f)
	f.Size = UDim2.new(0, 430, 0, 250)
	f.Position = UDim2.new(1, -450, 0, 90)
	f.BackgroundColor3 = Color3.fromRGB(48, 30, 30)
	f.BackgroundTransparency = 0.15
	f.BorderSizePixel = 0
end)
ensure(enemyPanel, "UICorner", "Corner")
local enemyTitle = ensure(enemyPanel, "TextLabel", "Title", function(l)
	l.Size = UDim2.new(1, 0, 0, 26)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextSize = 16
	l.TextColor3 = Color3.fromRGB(255, 150, 150)
	l.Text = "Gegner"
end)
-- Enemy portraits live in here. Full path:
--   CombatOverlay > EnemyCombatFrame > EnemyUnitsFrame
-- A legacy 'UnitList' child is renamed automatically.
renameLegacy(enemyPanel, "UnitList", "EnemyUnitsFrame")
local enemyList = ensure(enemyPanel, "Frame", "EnemyUnitsFrame", function(f)
	f.Size = UDim2.new(1, -12, 1, -34)
	f.Position = UDim2.new(0, 6, 0, 30)
	f.BackgroundTransparency = 1
end)
ensure(enemyList, "UIListLayout", "Layout", function(l)
	l.Padding = UDim.new(0, 4)
	l.SortOrder = Enum.SortOrder.LayoutOrder
end)

--------------------------------------------------------------------------------
-- PLAYER FRAME (bottom left) - ALWAYS the local player
--------------------------------------------------------------------------------
local myPanel = ensure(overlay, "Frame", "PlayerCombatFrame", function(f)
	f.Size = UDim2.new(0, 430, 0, 250)
	f.Position = UDim2.new(0, 20, 1, -270)
	f.BackgroundColor3 = Color3.fromRGB(30, 40, 52)
	f.BackgroundTransparency = 0.15
	f.BorderSizePixel = 0
end)
ensure(myPanel, "UICorner", "Corner")
local myTitle = ensure(myPanel, "TextLabel", "Title", function(l)
	l.Size = UDim2.new(1, 0, 0, 26)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextSize = 16
	l.TextColor3 = Color3.fromRGB(150, 210, 255)
	l.Text = "Deine Armee"
end)
-- Own portraits live in here. Full path:
--   CombatOverlay > PlayerCombatFrame > PlayerUnitsFrame
-- A legacy 'UnitList' child is renamed automatically.
renameLegacy(myPanel, "UnitList", "PlayerUnitsFrame")
local myList = ensure(myPanel, "Frame", "PlayerUnitsFrame", function(f)
	f.Size = UDim2.new(1, -12, 1, -34)
	f.Position = UDim2.new(0, 6, 0, 30)
	f.BackgroundTransparency = 1
end)
ensure(myList, "UIListLayout", "Layout", function(l)
	l.Padding = UDim.new(0, 4)
	l.SortOrder = Enum.SortOrder.LayoutOrder
end)

--------------------------------------------------------------------------------
-- BATTLE LOG (right, below the enemy frame)
--------------------------------------------------------------------------------
local logFrame = ensure(overlay, "ScrollingFrame", "CombatLogFrame", function(f)
	f.Size = UDim2.new(0, 430, 0, 220)
	f.Position = UDim2.new(1, -450, 0, 360)
	f.BackgroundColor3 = Color3.fromRGB(14, 16, 22)
	f.BackgroundTransparency = 0.2
	f.BorderSizePixel = 0
	f.ScrollBarThickness = 5
	f.AutomaticCanvasSize = Enum.AutomaticSize.Y
	f.CanvasSize = UDim2.new()
end)
ensure(logFrame, "UIListLayout", "Layout", function(l)
	l.Padding = UDim.new(0, 2)
	l.SortOrder = Enum.SortOrder.LayoutOrder
end)
ensure(logFrame, "UIPadding", "Padding", function(p)
	p.PaddingLeft = UDim.new(0, 6)
	p.PaddingRight = UDim.new(0, 6)
	p.PaddingTop = UDim.new(0, 4)
end)

local fleeButton = ensure(overlay, "TextButton", "FleeButton", function(b)
	b.Size = UDim2.new(0, 150, 0, 38)
	b.Position = UDim2.new(0, 20, 1, -312)
	b.BackgroundColor3 = Color3.fromRGB(150, 80, 40)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 16
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = "Rueckzug"
	b.BorderSizePixel = 0
end)
ensure(fleeButton, "UICorner", "Corner")

-- "X" closes the VIEW only (combat continues in the background on auto attack).
local closeButton = ensure(overlay, "TextButton", "CloseButton", function(b)
	b.Size = UDim2.fromOffset(38, 38)
	b.Position = UDim2.new(1, -50, 0, 18)
	b.BackgroundColor3 = Color3.fromRGB(70, 70, 82)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 18
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = "X"
	b.Visible = false
	b.BorderSizePixel = 0
end)
ensure(closeButton, "UICorner", "Corner")

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
	label.Font = Enum.Font.Gotham
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

local function HighlightUnit(unitId, color)
	local card = cards[unitId]
	if not card then return end

	local stroke = card:FindFirstChild("Glow")
	if not color then
		if stroke then stroke.Enabled = false end
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
end

local function ShowFloatingText(unitId, text, color)
	local card = cards[unitId]
	if not card then return end

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, 120, 0, 28)
	label.Position = UDim2.new(1, -130, 0, 4)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 22
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.3
	label.Text = text
	label.ZIndex = 30
	label.Parent = card

	TweenService:Create(label, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(1, -130, 0, -34),
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
		card.BackgroundColor3 = Color3.fromRGB(58, 30, 30)
		card.BackgroundTransparency = 0.4
		local nameLabel = card:FindFirstChild("UnitName")
		if nameLabel and not string.find(nameLabel.Text, "(tot)", 1, true) then
			nameLabel.Text = nameLabel.Text .. " (tot)"
			nameLabel.TextColor3 = COLORS.dead
		end
		HighlightUnit(unitId, nil)
	end
end

--------------------------------------------------------------------------------
-- UNIT CARD - parent is PlayerUnitsFrame (isMine) or EnemyUnitsFrame.
-- Everything downstream (HighlightUnit, ShowDamageNumber, UpdateUnitCard)
-- looks the card up via the cards[unitId] table, so it always hits the
-- correct frame automatically.
--------------------------------------------------------------------------------
local function buildCard(parent, unit, isMine, index)
	local card = Instance.new("Frame")
	card.Name = "Unit_" .. unit.id
	card:SetAttribute("CombatCard", true)
	card.Size = UDim2.new(1, 0, 0, 46)
	card.LayoutOrder = index
	card.BackgroundColor3 = unit.alive
		and Color3.fromRGB(42, 46, 58)
		or Color3.fromRGB(58, 30, 30)
	card.BackgroundTransparency = unit.alive and 0 or 0.4
	card.BorderSizePixel = 0
	card.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = card

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.fromOffset(38, 38)
	icon.Position = UDim2.new(0, 4, 0, 4)
	icon.BackgroundTransparency = 1
	icon.Image = unit.icon or ""
	icon.Parent = card

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "UnitName"
	nameLabel.Size = UDim2.new(1, -160, 0, 18)
	nameLabel.Position = UDim2.new(0, 48, 0, 4)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 14
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextColor3 = unit.alive and Color3.new(1, 1, 1) or COLORS.dead
	nameLabel.Text = unit.name .. (unit.alive and "" or " (tot)")
	nameLabel.Parent = card

	local statLabel = Instance.new("TextLabel")
	statLabel.Name = "Stats"
	statLabel.Size = UDim2.new(0, 110, 0, 18)
	statLabel.Position = UDim2.new(1, -114, 0, 4)
	statLabel.BackgroundTransparency = 1
	statLabel.Font = Enum.Font.Gotham
	statLabel.TextSize = 12
	statLabel.TextXAlignment = Enum.TextXAlignment.Right
	statLabel.TextColor3 = Color3.fromRGB(190, 190, 200)
	statLabel.Text = ("DMG %d | DEF %d%%")
		:format(unit.attack or 0, unit.defense or 0)
	statLabel.Parent = card

	local barBg = Instance.new("Frame")
	barBg.Name = "HPBar"
	barBg.Size = UDim2.new(1, -56, 0, 10)
	barBg.Position = UDim2.new(0, 48, 0, 26)
	barBg.BackgroundColor3 = Color3.fromRGB(26, 26, 32)
	barBg.BorderSizePixel = 0
	barBg.Parent = card

	local ratio = (unit.maxLP or 0) > 0 and math.clamp(unit.currentLP / unit.maxLP, 0, 1) or 0
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(ratio, 1)
	fill.BackgroundColor3 = hpColor(ratio)
	fill.BorderSizePixel = 0
	fill.Parent = barBg

	local hpText = Instance.new("TextLabel")
	hpText.Name = "HPText"
	hpText.Size = UDim2.new(1, 0, 1, 0)
	hpText.BackgroundTransparency = 1
	hpText.Font = Enum.Font.GothamBold
	hpText.TextSize = 10
	hpText.TextColor3 = Color3.new(1, 1, 1)
	hpText.Text = unit.currentLP .. "/" .. unit.maxLP
	hpText.ZIndex = 3
	hpText.Parent = barBg

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

	myTitle.Text = ("%s  -  Moral %d"):format(mine.playerName or "Du", mine.morale or 100)
	enemyTitle.Text = ("%s  -  Moral %d"):format(enemy.playerName or "Gegner", enemy.morale or 100)

	cards = {}
	unitOwnerSide = {}

	-- ALWAYS: own units bottom left, enemy units top right.
	-- Both unit frames are wiped first so no stale portrait survives
	-- (for example a unit that died between two snapshots).
	clearList(myList)
	clearList(enemyList)
	RenderUnits(myList, mine.units, true)
	RenderUnits(enemyList, enemy.units, false)

	-- Keep the golden outline of the unit the player already confirmed.
	if selectedUnitId then
		HighlightUnit(selectedUnitId, COLORS.selected)
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
		countdownFill.BackgroundColor3 = isMyTurn and COLORS.myTurn or COLORS.enemyTurn

		if isMyTurn then
			if selectedUnitId then
				turnIndicator.Text = ("Waehle ein Ziel!  -  %.0fs"):format(left)
			else
				turnIndicator.Text = ("🎯 Dein Zug!  -  %.0fs"):format(left)
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
		HighlightUnit(unitId, COLORS.selected)
		turnIndicator.Text = "Waehle ein Ziel!"
		turnIndicator.TextColor3 = COLORS.selected

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
	autoResolveButton.Active = true
	autoResolveButton.AutoButtonColor = true
	autoResolveButton.BackgroundColor3 = Color3.fromRGB(70, 90, 150)
	autoResolveButton.Text = "\u{26A1} Auto-Resolve"
	gui.Enabled = true
	-- Always closable: closing only hides the view, the combat keeps running
	-- on the server. This lets the player move OTHER armies meanwhile.
	closeButton.Visible = true
	turnIndicator.Text = "KAMPF BEGINNT"
	turnIndicator.TextColor3 = COLORS.myTurn

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

	if isMyTurn then
		turnIndicator.Text = "🎯 Dein Zug! Waehle eine Unit."
		turnIndicator.TextColor3 = COLORS.myTurn
	else
		turnIndicator.Text = "⏳ Gegner ist dran..."
		turnIndicator.TextColor3 = COLORS.enemyTurn
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
	HighlightUnit(data.unitId, COLORS.selected)
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
		table.insert(extras, r.absorbed .. " absorbiert")
	end
	if (r.counterDamage or 0) > 0 then
		table.insert(extras, r.counterDamage .. " Konter")
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
		turnIndicator.TextColor3 = LOG_COLORS.flee
		AddLogEntry(won and "🏳️ Gegner flieht!" or "🏳️ Rueckzug!", "flee")
	elseif won then
		turnIndicator.Text = "SIEG!"
		turnIndicator.TextColor3 = Color3.fromRGB(120, 255, 120)
		AddLogEntry("🏆 Sieg!", "heal")
	else
		turnIndicator.Text = "NIEDERLAGE"
		turnIndicator.TextColor3 = Color3.fromRGB(255, 120, 120)
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
		autoResolveButton.Text = "\u{23F3} Warte auf Gegner..."
		autoResolveButton.Active = false
		autoResolveButton.AutoButtonColor = false
		autoResolveButton.BackgroundColor3 = Color3.fromRGB(90, 90, 100)
	else
		-- The opponent wants to skip: highlight our button.
		autoResolveButton.Text = "\u{26A1} Auto-Resolve (Gegner bereit)"
		autoResolveButton.BackgroundColor3 = Color3.fromRGB(90, 130, 70)
	end
end)

safeOn("CombatAutoResolveStart", function(data)
	if not data or data.combatId ~= currentCombatId then return end

	autoResolving = true
	autoResolveButton.Text = "\u{26A1} Wird berechnet..."
	autoResolveButton.Active = false
	autoResolveButton.AutoButtonColor = false
	autoResolveButton.BackgroundColor3 = Color3.fromRGB(90, 90, 100)

	-- Freeze the manual UI: no clicks, no countdown.
	isMyTurn = false
	EnableUnitSelection(false)
	if countdownConn then countdownConn:Disconnect() countdownConn = nil end
	countdownFill.Size = UDim2.fromScale(0, 1)

	turnIndicator.Text = "\u{26A1} Auto-Resolve laeuft..."
	turnIndicator.TextColor3 = COLORS.selected
	AddLogEntry("\u{26A1} Auto-Resolve: Kampf wird ausgerechnet...", "info")
end)

autoResolveButton.Activated:Connect(function()
	if not currentCombatId or autoResolving then return end

	Net.Fire("CombatAutoResolve", currentCombatId)

	-- Optimistic feedback; the server confirms via CombatAutoResolveVote.
	autoResolveButton.Text = "\u{23F3} Warte auf Gegner..."
	autoResolveButton.Active = false
	autoResolveButton.AutoButtonColor = false
	autoResolveButton.BackgroundColor3 = Color3.fromRGB(90, 90, 100)
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
		EnableUnitSelection(isMyTurn)
		AddLogEntry("⚔️ Kampf-Ansicht geoeffnet", "info")
	end
end)

print("[CombatGuiController] Bereit (Pokemon-Style, Spieler-Perspektive).")
