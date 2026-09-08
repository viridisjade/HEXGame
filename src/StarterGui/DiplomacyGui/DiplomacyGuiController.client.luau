--[[
    DiplomacyGuiController (LocalScript)
    Ort: StarterGui > DiplomacyGui > DiplomacyGuiController

    Diplomatie-Fenster. Baut die UI zur Laufzeit (ensure-Muster) und zeigt:
      - PlayerList (links): alle anderen Spieler mit Farbe + Beziehungsstatus.
      - ActionPanel (rechts): Aktionen je nach Beziehung.
        Neutral   -> Bündnis anbieten + Krieg erklären
        Verbündet -> Krieg erklären (Bündnis brechen)
        Krieg     -> Frieden anbieten

    Oeffnen/Schliessen ueber ClientState.ToggleDiplomacy (empire-Button).
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Net = require(ReplicatedStorage:WaitForChild("Net"))
local ClientState = require(ReplicatedStorage:WaitForChild("ClientState"))
local DiplomacyConfig = require(ReplicatedStorage:WaitForChild("DiplomacyConfig"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = script.Parent:IsA("ScreenGui")
	and script.Parent
	or script.Parent:FindFirstAncestorWhichIsA("ScreenGui")
if not gui then return end

gui.Enabled = false
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true

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
-- STATISCHE UI
--------------------------------------------------------------------------------
local overlay = ensure(gui, "Frame", "DiplomacyOverlay", function(f)
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = Color3.fromRGB(8, 10, 16)
	f.BackgroundTransparency = 0.25
	f.BorderSizePixel = 0
end)

local title = ensure(overlay, "TextLabel", "TitleLabel", function(l)
	l.Size = UDim2.new(0, 460, 0, 42)
	l.Position = UDim2.new(0.5, -230, 0, 14)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextSize = 26
	l.TextColor3 = Color3.fromRGB(255, 205, 90)
	l.Text = "Diplomatie"
	l.TextXAlignment = Enum.TextXAlignment.Center
end)

local closeBtn = ensure(overlay, "TextButton", "CloseButton", function(b)
	b.Size = UDim2.fromOffset(40, 40)
	b.Position = UDim2.new(1, -54, 0, 14)
	b.BackgroundColor3 = Color3.fromRGB(70, 70, 82)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 20
	b.TextColor3 = Color3.fromRGB(238, 240, 248)
	b.Text = "✕"
	b.BorderSizePixel = 0
end)
ensure(closeBtn, "UICorner", "Corner")

local playerList = ensure(overlay, "ScrollingFrame", "PlayerList", function(f)
	f.Size = UDim2.new(0.48, -8, 1, -90)
	f.Position = UDim2.new(0, 24, 0, 66)
	f.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
	f.BackgroundTransparency = 0.2
	f.BorderSizePixel = 0
	f.ScrollBarThickness = 6
	f.AutomaticCanvasSize = Enum.AutomaticSize.Y
	f.CanvasSize = UDim2.new()
end)
ensure(playerList, "UICorner", "Corner")
ensure(playerList, "UIListLayout", "Layout", function(l)
	l.Padding = UDim.new(0, 6)
	l.SortOrder = Enum.SortOrder.LayoutOrder
end)

local actionPanel = ensure(overlay, "Frame", "ActionPanel", function(f)
	f.Size = UDim2.new(0.48, -8, 1, -90)
	f.Position = UDim2.new(0.52, 8, 0, 66)
	f.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
	f.BackgroundTransparency = 0.2
	f.BorderSizePixel = 0
end)
ensure(actionPanel, "UICorner", "Corner")

local selectedName = ensure(actionPanel, "TextLabel", "SelectedPlayerName", function(l)
	l.Size = UDim2.new(1, -24, 0, 30)
	l.Position = UDim2.new(0, 12, 0, 14)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextSize = 20
	l.TextColor3 = Color3.fromRGB(255, 205, 90)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = "Kein Spieler ausgewählt"
end)

local currentRelation = ensure(actionPanel, "TextLabel", "CurrentRelationLabel", function(l)
	l.Size = UDim2.new(1, -24, 0, 26)
	l.Position = UDim2.new(0, 12, 0, 50)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.Gotham
	l.TextSize = 15
	l.TextColor3 = Color3.fromRGB(238, 240, 248)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = ""
end)

local function makeActionButton(name, text, y, color)
	local btn = ensure(actionPanel, "TextButton", name, function(b)
		b.Size = UDim2.new(1, -24, 0, 40)
		b.Position = UDim2.new(0, 12, 0, y)
		b.BackgroundColor3 = color
		b.Font = Enum.Font.GothamBold
		b.TextSize = 15
		b.TextColor3 = Color3.fromRGB(255, 255, 255)
		b.Text = text
		b.BorderSizePixel = 0
		b.Visible = false
	end)
	ensure(btn, "UICorner", "Corner")
	return btn
end

local allianceBtn = makeActionButton("AllianceButton", "🤝 Bündnis anbieten", 90, Color3.fromRGB(40, 110, 70))
local warBtn = makeActionButton("WarButton", "⚔️ Krieg erklären", 140, Color3.fromRGB(150, 60, 60))
local peaceBtn = makeActionButton("PeaceButton", "🕊️ Frieden anbieten", 90, Color3.fromRGB(60, 90, 150))
local breakBtn = makeActionButton("BreakButton", "💔 Bündnis auflösen", 140, Color3.fromRGB(120, 50, 50))

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------
local playersByUserId = {}   -- userId -> {name, color, relation}
local selectedUserId = nil

-- Forward-Deklaration (renderActionPanel wird in renderPlayerList genutzt).
local renderActionPanel

local function StateName(state)
	if state == DiplomacyConfig.STATE.ALLIED then return "Verbündet" end
	if state == DiplomacyConfig.STATE.WAR then return "Krieg" end
	return "Neutral"
end

local function relationColor(state)
	if state == DiplomacyConfig.STATE.ALLIED then return Color3.fromRGB(60, 170, 90) end
	if state == DiplomacyConfig.STATE.WAR then return Color3.fromRGB(200, 70, 70) end
	return Color3.fromRGB(170, 170, 180)
end

--------------------------------------------------------------------------------
-- RENDER: PLAYER LIST
--------------------------------------------------------------------------------
local function renderPlayerList(data)
	-- Clear & rebuild.
	for _, child in ipairs(playerList:GetChildren()) do
		if child:IsA("Frame") and child:GetAttribute("PlayerEntry") then child:Destroy() end
	end
	playersByUserId = {}

	if not data or #data == 0 then
		local empty = ensure(playerList, "TextLabel", "EmptyLabel", function(l)
			l.Size = UDim2.new(1, -12, 0, 40)
			l.BackgroundTransparency = 1
			l.Font = Enum.Font.Gotham
			l.TextSize = 14
			l.TextColor3 = Color3.fromRGB(170, 174, 190)
			l.Text = "Keine anderen Spieler."
		end)
		empty.Visible = true
		return
	end

	for i, entry in ipairs(data) do
		local row = Instance.new("Frame")
		row.Name = "PlayerEntry_" .. entry.userId
		row.Size = UDim2.new(1, -8, 0, 44)
		row.BackgroundColor3 = Color3.fromRGB(28, 30, 40)
		row.BackgroundTransparency = 0.15
		row.BorderSizePixel = 0
		row.LayoutOrder = i
		row.Parent = playerList
		row:SetAttribute("PlayerEntry", true)

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = row

		local dot = Instance.new("Frame")
		dot.Name = "ColorDot"
		dot.Size = UDim2.fromOffset(14, 14)
		dot.Position = UDim2.new(0, 12, 0.5, -7)
		dot.AnchorPoint = Vector2.new(0, 0.5)
		dot.BackgroundColor3 = entry.color or Color3.fromRGB(128, 128, 128)
		dot.BorderSizePixel = 0
		dot.Parent = row
		ensure(dot, "UICorner", "Corner")

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "NameLabel"
		nameLabel.Size = UDim2.new(0.5, -8, 1, 0)
		nameLabel.Position = UDim2.new(0, 32, 0, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextSize = 14
		nameLabel.TextColor3 = Color3.fromRGB(238, 240, 248)
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.Text = entry.name
		nameLabel.Parent = row

		local status = Instance.new("TextLabel")
		status.Name = "StatusLabel"
		status.Size = UDim2.new(0.42, -8, 1, 0)
		status.Position = UDim2.new(0.58, 6, 0, 0)
		status.BackgroundTransparency = 1
		status.Font = Enum.Font.Gotham
		status.TextSize = 13
		status.TextColor3 = relationColor(entry.relation)
		status.TextXAlignment = Enum.TextXAlignment.Right
		status.Text = StateName(entry.relation)
		status.Parent = row

		local selectBtn = Instance.new("TextButton")
		selectBtn.Name = "ActionButton"
		selectBtn.Size = UDim2.new(1, 0, 1, 0)
		selectBtn.BackgroundTransparency = 1
		selectBtn.Text = ""
		selectBtn.BorderSizePixel = 0
		selectBtn.Parent = row

		playersByUserId[entry.userId] = { name = entry.name, color = entry.color, relation = entry.relation }

		selectBtn.Activated:Connect(function()
			selectedUserId = entry.userId
			renderActionPanel(entry.userId)
		end)
	end
end

--------------------------------------------------------------------------------
-- RENDER: ACTION PANEL
--------------------------------------------------------------------------------
renderActionPanel = function(userId)
	local entry = playersByUserId[userId]
	if not entry then return end

	selectedName.Text = entry.name
	currentRelation.Text = "Beziehung: " .. StateName(entry.relation)
	currentRelation.TextColor3 = relationColor(entry.relation)

	local state = entry.relation
	allianceBtn.Visible = (state == DiplomacyConfig.STATE.NEUTRAL)
	warBtn.Visible = (state ~= DiplomacyConfig.STATE.WAR)  -- Krieg erklären aus Neutral oder Verbündet
	peaceBtn.Visible = (state == DiplomacyConfig.STATE.WAR)
	breakBtn.Visible = (state == DiplomacyConfig.STATE.ALLIED)
end

--------------------------------------------------------------------------------
-- ACTIONS (senden an Server)
--------------------------------------------------------------------------------
allianceBtn.Activated:Connect(function()
	if selectedUserId then Net.Fire("DiplomacySendOffer", selectedUserId, "Alliance") end
end)
peaceBtn.Activated:Connect(function()
	if selectedUserId then Net.Fire("DiplomacySendOffer", selectedUserId, "Peace") end
end)
warBtn.Activated:Connect(function()
	if selectedUserId then Net.Fire("DiplomacyDeclareWar", selectedUserId) end
end)
breakBtn.Activated:Connect(function()
	if selectedUserId then Net.Fire("DiplomacyBreakAlliance", selectedUserId) end
end)

closeBtn.Activated:Connect(function()
	gui.Enabled = false
end)

--------------------------------------------------------------------------------
-- OPEN/CLOSE + DATA LOADING
--------------------------------------------------------------------------------
local function openDiplomacy()
	gui.Enabled = true
	task.spawn(function()
		local ok, data = Net.Invoke("GetDiplomacyPlayers")
		if ok and data then
			renderPlayerList(data)
			if selectedUserId and playersByUserId[selectedUserId] then
				renderActionPanel(selectedUserId)
			elseif next(playersByUserId) then
				-- ersten Spieler vorwaehlen.
				for uid in pairs(playersByUserId) do
					selectedUserId = uid
					break
				end
				renderActionPanel(selectedUserId)
			end
		end
	end)
end

local function closeDiplomacy()
	gui.Enabled = false
end

-- Toggle-Handler: reagiert IDEMPOTENT auf den aktuellen Zustand. Der
-- Empire-Button schaltet DiplomacyGui.Enabled bereits direkt um; dieses Event
-- laedt beim Oeffnen die Daten nach (openDiplomacy) und raeumt beim Schliessen
-- auf (closeDiplomacy). Beide setzen den Zustand absolut, nie inkrementell,
-- damit es nicht zu Doppel-Toggles kommt.
ClientState.ToggleDiplomacy:Connect(function()
	if gui.Enabled then
		openDiplomacy()
	else
		closeDiplomacy()
	end
end)

-- Statusanderungen live aktualisieren.
Net.On("DiplomacyUpdate", function(data)
	if not gui.Enabled then return end
	if not data then return end
	local relations = data.relations or {}
	for uid, entry in pairs(playersByUserId) do
		local state = relations[uid]
		if state then entry.relation = state end
	end
	task.spawn(function()
		local ok, list = Net.Invoke("GetDiplomacyPlayers")
		if ok and list then renderPlayerList(list) end
	end)
end)

--------------------------------------------------------------------------------
-- BOOT
--------------------------------------------------------------------------------
print("[DiplomacyGuiController] Bereit.")
