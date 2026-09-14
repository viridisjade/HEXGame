--[[
    DiplomacyGuiController (LocalScript)
    Location: StarterGui > DiplomacyGui > DiplomacyGuiController

    KOMPLETT CODE-GENERIERTE DiplomacyGui im Fantasy-Stil (wie CityGui,
    ArmyGui, EmpireOverlayGui, CombatGui, TechTreeGui): alle Elemente werden
    per Instance.new() erzeugt, nichts wird mehr manuell in Studio gebaut.

    LAYOUT: schmales, NICHT-SPERRENDES Panel am rechten Bildschirmrand
    (wie ArmyGui) - kein grosses Overlay, kein abdunkelnder Hintergrund,
    der Spieler kann waehrend das Panel offen ist normal weiterspielen:
      DiplomacyWindow (rechts, vertikal zentriert)
        Header       - "🤝 DIPLOMATIE" + Close-Button
        AllianceInfo - "Allianz: X/3 Mitglieder" + "Allianz-Punkte: X/1500"
                       (nur sichtbar, wenn relevant)
        PlayerList   - ScrollingFrame, ein PlayerEntry pro Gegenspieler:
                         Farb-Indikator (Kreis) + Name + Status
                         Aktions-Buttons je nach Beziehung:
                           Neutral -> [📜 Allianz] [⚔️ Krieg]
                           Allianz -> [⚔️ Krieg erklären] (Bund brechen)
                           Krieg   -> [🕊️ Frieden anbieten]

    FUNKTIONALITAET (unveraendert zur Vorversion, nur neues Design/Layout):
      - Spielerliste laedt ueber GetDiplomacyPlayers (RemoteFunction) und
        aktualisiert sich live bei DiplomacyUpdate (RemoteEvent).
      - Aktions-Buttons feuern DiplomacySendOffer / DiplomacyDeclareWar /
        DiplomacyBreakAlliance (RemoteEvents, siehe DiplomacyHandler).
      - Max-3-Allianz-Check: der Server liefert "allianceFull" pro Spieler
        (rein additives Anzeige-Feld); der Allianz-Button wird dann
        ausgegraut und ist nicht klickbar.
      - Angebote werden weiterhin ueber NotificationGui angezeigt (dieser
        Controller sendet nur, empfaengt aber keine Benachrichtigungen).
      - Oeffnen/Schliessen ueber ClientState.ToggleDiplomacy (Empire-Button),
        Panel togglet sein eigenes Enabled absolut (kein Doppel-Toggle).
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Net = require(ReplicatedStorage:WaitForChild("Net"))
local ClientState = require(ReplicatedStorage:WaitForChild("ClientState"))
local DiplomacyConfig = require(ReplicatedStorage:WaitForChild("DiplomacyConfig"))

local localPlayer = Players.LocalPlayer

--------------------------------------------------------------------------------
-- GUI-Wurzel finden + alles Alte entfernen (CLEANUP)
--
-- Loescht ALLE Children von DiplomacyGui - NUR dieses Script selbst bleibt
-- erhalten. Alle GUI-Elemente werden im Folgenden komplett neu per Code
-- erzeugt.
--------------------------------------------------------------------------------
local gui = script.Parent
if not gui:IsA("ScreenGui") then
	gui = script.Parent:FindFirstAncestorWhichIsA("ScreenGui")
end
if not gui then
	warn("[DiplomacyGui] Keine ScreenGui gefunden")
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

	entryBg = Color3.fromRGB(50, 40, 32),

	statusAlliance = Color3.fromRGB(100, 200, 100),
	statusNeutral  = Color3.fromRGB(180, 180, 180),
	statusWar      = Color3.fromRGB(200, 60, 60),

	btnNormal  = Color3.fromRGB(70, 55, 40),
	btnHover   = Color3.fromRGB(100, 80, 55),
	btnWar     = Color3.fromRGB(120, 40, 40),
	btnWarHov  = Color3.fromRGB(150, 55, 55),
	btnPeace   = Color3.fromRGB(50, 100, 50),
	btnPeaceHov = Color3.fromRGB(65, 130, 65),
	btnAlliance = Color3.fromRGB(50, 70, 120),
	btnAllianceHov = Color3.fromRGB(65, 90, 150),
	btnDisabled = Color3.fromRGB(60, 55, 50),
	btnText     = Color3.fromRGB(255, 220, 150),
	btnTextDim  = Color3.fromRGB(150, 140, 125),
}

local FONT_TITLE = Enum.Font.FredokaOne
local FONT_NAME  = Enum.Font.GothamBold
local FONT_STATUS = Enum.Font.Gotham
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
-- DIPLOMACY-WINDOW (schmales Panel rechts, wie ArmyGui - NICHT-SPERREND)
--------------------------------------------------------------------------------
local diplomacyWindow = Instance.new("Frame")
diplomacyWindow.Name = "DiplomacyWindow"
diplomacyWindow.Size = UDim2.new(0, 280, 0.55, 0)
diplomacyWindow.Position = UDim2.new(1, -290, 0.5, 0)
diplomacyWindow.AnchorPoint = Vector2.new(0, 0.5)
diplomacyWindow.BackgroundColor3 = COLORS.windowBg
diplomacyWindow.BackgroundTransparency = 0.15
diplomacyWindow.BorderSizePixel = 0
diplomacyWindow.Parent = gui
makeCorner(diplomacyWindow, 12)
makeStroke(diplomacyWindow, 3, COLORS.panelBorder)

--------------------------------------------------------------------------------
-- HEADER (goldbraun) - Titel + Close-Button
--------------------------------------------------------------------------------
local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 40)
header.Position = UDim2.new(0, 0, 0, 0)
header.BackgroundColor3 = COLORS.headerBg
header.BorderSizePixel = 0
header.Parent = diplomacyWindow
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
titleLabel.Size = UDim2.new(1, -50, 1, 0)
titleLabel.Position = UDim2.new(0, 12, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = FONT_TITLE
titleLabel.TextSize = 18
titleLabel.TextColor3 = COLORS.headerText
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Text = "🤝 DIPLOMATIE"
titleLabel.Parent = header

local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.Size = UDim2.fromOffset(30, 28)
closeButton.Position = UDim2.new(1, -36, 0.5, -14)
closeButton.BackgroundColor3 = Color3.fromRGB(70, 70, 82)
closeButton.Font = FONT_NAME
closeButton.TextSize = 14
closeButton.TextColor3 = Color3.new(1, 1, 1)
closeButton.Text = "X"
closeButton.BorderSizePixel = 0
closeButton.Parent = header
makeCorner(closeButton, 6)
wireButtonStyle(closeButton, Color3.fromRGB(70, 70, 82), Color3.fromRGB(95, 95, 108))

--------------------------------------------------------------------------------
-- ALLIANCE-INFO (Kopfzeile innerhalb der Liste - Mitglieder + Punkte)
-- Nur sichtbar, wenn der Spieler tatsaechlich in einer Allianz ist.
--------------------------------------------------------------------------------
local allianceInfo = Instance.new("Frame")
allianceInfo.Name = "AllianceInfo"
allianceInfo.Size = UDim2.new(1, -16, 0, 40)
allianceInfo.Position = UDim2.new(0, 8, 0, 46)
allianceInfo.BackgroundColor3 = COLORS.entryBg
allianceInfo.BorderSizePixel = 0
allianceInfo.Visible = false
allianceInfo.Parent = diplomacyWindow
makeCorner(allianceInfo, 6)
makeStroke(allianceInfo, 1, COLORS.panelBorder)

local allianceMembersLabel = Instance.new("TextLabel")
allianceMembersLabel.Name = "AllianceMembersLabel"
allianceMembersLabel.Size = UDim2.new(1, -12, 0, 18)
allianceMembersLabel.Position = UDim2.new(0, 6, 0, 3)
allianceMembersLabel.BackgroundTransparency = 1
allianceMembersLabel.Font = FONT_NAME
allianceMembersLabel.TextSize = 12
allianceMembersLabel.TextColor3 = COLORS.statusAlliance
allianceMembersLabel.TextXAlignment = Enum.TextXAlignment.Left
allianceMembersLabel.Text = "🤝 Allianz: 1/3 Mitglieder"
allianceMembersLabel.Parent = allianceInfo

local alliancePointsLabel = Instance.new("TextLabel")
alliancePointsLabel.Name = "AlliancePointsLabel"
alliancePointsLabel.Size = UDim2.new(1, -12, 0, 16)
alliancePointsLabel.Position = UDim2.new(0, 6, 0, 20)
alliancePointsLabel.BackgroundTransparency = 1
alliancePointsLabel.Font = FONT_DESC
alliancePointsLabel.TextSize = 11
alliancePointsLabel.TextColor3 = COLORS.headerText
alliancePointsLabel.TextXAlignment = Enum.TextXAlignment.Left
alliancePointsLabel.Text = "🏆 Allianz-Punkte: 0/1500"
alliancePointsLabel.Parent = allianceInfo

--------------------------------------------------------------------------------
-- PLAYER LIST (ScrollingFrame, vertikal)
-- Position/Groesse haengt davon ab, ob AllianceInfo sichtbar ist - wird in
-- updateAllianceInfoLayout() live angepasst.
--------------------------------------------------------------------------------
local playerList = Instance.new("ScrollingFrame")
playerList.Name = "PlayerList"
playerList.Size = UDim2.new(1, -16, 1, -54)
playerList.Position = UDim2.new(0, 8, 0, 46)
playerList.BackgroundTransparency = 1
playerList.BorderSizePixel = 0
playerList.ScrollBarThickness = 5
playerList.ScrollBarImageColor3 = COLORS.panelBorder
playerList.AutomaticCanvasSize = Enum.AutomaticSize.Y
playerList.CanvasSize = UDim2.new()
playerList.Parent = diplomacyWindow

local playerListLayout = Instance.new("UIListLayout")
playerListLayout.Padding = UDim.new(0, 6)
playerListLayout.SortOrder = Enum.SortOrder.LayoutOrder
playerListLayout.Parent = playerList

-- Passt PlayerList Size/Position an, je nachdem ob AllianceInfo sichtbar ist.
local function updateAllianceInfoLayout()
	if allianceInfo.Visible then
		allianceInfo.Position = UDim2.new(0, 8, 0, 46)
		playerList.Position = UDim2.new(0, 8, 0, 90)
		playerList.Size = UDim2.new(1, -16, 1, -98)
	else
		playerList.Position = UDim2.new(0, 8, 0, 46)
		playerList.Size = UDim2.new(1, -16, 1, -54)
	end
end

--------------------------------------------------------------------------------
-- CLIENT STATE
--------------------------------------------------------------------------------
local playersByUserId = {}   -- userId -> {name, color, relation, allianceFull}
local entryFrames = {}       -- userId -> row frame

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------
local function StateName(state)
	if state == DiplomacyConfig.STATE.ALLIANCE then return "Allianz" end
	if state == DiplomacyConfig.STATE.WAR then return "Krieg" end
	return "Neutral"
end

local function relationColor(state)
	if state == DiplomacyConfig.STATE.ALLIANCE then return COLORS.statusAlliance end
	if state == DiplomacyConfig.STATE.WAR then return COLORS.statusWar end
	return COLORS.statusNeutral
end

local function relationDot(state)
	if state == DiplomacyConfig.STATE.ALLIANCE then return "🟢" end
	if state == DiplomacyConfig.STATE.WAR then return "🔴" end
	return "⚪"
end

--------------------------------------------------------------------------------
-- makeActionButton(parent, name, text, layoutOrder, normalColor, hoverColor)
-- Small pill button used inside a player row. Two buttons share the row
-- width when both are visible (Neutral state).
--------------------------------------------------------------------------------
local function makeActionButton(parent, name, text, layoutOrder, normalColor, hoverColor)
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.Size = UDim2.new(0, 0, 0, 24) -- width set by caller via UIListLayout / manual sizing
	btn.LayoutOrder = layoutOrder
	btn.Font = FONT_NAME
	btn.TextSize = 11
	btn.TextColor3 = COLORS.btnText
	btn.Text = text
	btn.BorderSizePixel = 0
	btn.Parent = parent
	makeCorner(btn, 4)
	wireButtonStyle(btn, normalColor, hoverColor)
	return btn
end

--------------------------------------------------------------------------------
-- buildPlayerEntry(entry, index) - one row inside PlayerList
--------------------------------------------------------------------------------
local function buildPlayerEntry(entry, index)
	local row = Instance.new("Frame")
	row.Name = "PlayerEntry_" .. entry.userId
	row.Size = UDim2.new(1, 0, 0, 78)
	row.LayoutOrder = index
	row.BackgroundColor3 = COLORS.entryBg
	row.BorderSizePixel = 0
	row.Parent = playerList
	makeCorner(row, 6)
	makeStroke(row, 1, COLORS.panelBorder)

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.Parent = row

	-- Farb-Indikator (kleiner Kreis, Spielerfarbe) + Statuspunkt-Emoji.
	local dot = Instance.new("Frame")
	dot.Name = "ColorDot"
	dot.Size = UDim2.fromOffset(12, 12)
	dot.Position = UDim2.new(0, 0, 0, 3)
	dot.BackgroundColor3 = entry.color or Color3.fromRGB(128, 128, 128)
	dot.BorderSizePixel = 0
	dot.Parent = row
	makeCorner(dot, 6)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.new(1, -20, 0, 18)
	nameLabel.Position = UDim2.new(0, 18, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = FONT_NAME
	nameLabel.TextSize = 14
	nameLabel.TextColor3 = COLORS.headerText
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Text = entry.name
	nameLabel.Parent = row

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusLabel"
	statusLabel.Size = UDim2.new(1, 0, 0, 16)
	statusLabel.Position = UDim2.new(0, 18, 0, 18)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Font = FONT_STATUS
	statusLabel.TextSize = 12
	statusLabel.TextColor3 = relationColor(entry.relation)
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.Text = relationDot(entry.relation) .. " " .. StateName(entry.relation)
	statusLabel.Parent = row

	-- Aktions-Buttons (unten in der Kachel), je nach Beziehungsstatus.
	local actionsFrame = Instance.new("Frame")
	actionsFrame.Name = "ActionsFrame"
	actionsFrame.Size = UDim2.new(1, 0, 0, 26)
	actionsFrame.Position = UDim2.new(0, 0, 1, -26)
	actionsFrame.BackgroundTransparency = 1
	actionsFrame.Parent = row

	local actionsLayout = Instance.new("UIListLayout")
	actionsLayout.FillDirection = Enum.FillDirection.Horizontal
	actionsLayout.Padding = UDim.new(0, 6)
	actionsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	actionsLayout.Parent = actionsFrame

	local state = entry.relation

	if state == DiplomacyConfig.STATE.NEUTRAL then
		-- [📜 Allianz] [⚔️ Krieg] nebeneinander, je die Haelfte der Breite.
		local allianceBtn = makeActionButton(actionsFrame, "AllianceButton",
			"📜 Allianz", 1, COLORS.btnAlliance, COLORS.btnAllianceHov)
		allianceBtn.Size = UDim2.new(0.5, -3, 1, 0)

		if entry.allianceFull then
			allianceBtn:SetAttribute("Disabled", true)
			allianceBtn.BackgroundColor3 = COLORS.btnDisabled
			allianceBtn.TextColor3 = COLORS.btnTextDim
			allianceBtn.Text = "📜 Allianz voll"
		else
			allianceBtn.Activated:Connect(function()
				Net.Fire("DiplomacySendOffer", entry.userId, "Alliance")
			end)
		end

		local warBtn = makeActionButton(actionsFrame, "WarButton",
			"⚔️ Krieg", 2, COLORS.btnWar, COLORS.btnWarHov)
		warBtn.Size = UDim2.new(0.5, -3, 1, 0)
		warBtn.Activated:Connect(function()
			Net.Fire("DiplomacyDeclareWar", entry.userId)
		end)

	elseif state == DiplomacyConfig.STATE.ALLIANCE then
		-- [⚔️ Krieg erklären] (Bund brechen) - volle Breite.
		local breakBtn = makeActionButton(actionsFrame, "BreakButton",
			"⚔️ Krieg erklären", 1, COLORS.btnWar, COLORS.btnWarHov)
		breakBtn.Size = UDim2.new(1, 0, 1, 0)
		breakBtn.Activated:Connect(function()
			Net.Fire("DiplomacyDeclareWar", entry.userId)
		end)

	elseif state == DiplomacyConfig.STATE.WAR then
		-- [🕊️ Frieden anbieten] - volle Breite.
		local peaceBtn = makeActionButton(actionsFrame, "PeaceButton",
			"🕊️ Frieden anbieten", 1, COLORS.btnPeace, COLORS.btnPeaceHov)
		peaceBtn.Size = UDim2.new(1, 0, 1, 0)
		peaceBtn.Activated:Connect(function()
			Net.Fire("DiplomacySendOffer", entry.userId, "Peace")
		end)
	end

	entryFrames[entry.userId] = row
	return row
end

--------------------------------------------------------------------------------
-- renderPlayerList(data)
--------------------------------------------------------------------------------
local function renderPlayerList(data)
	-- Clear & rebuild.
	for _, child in ipairs(playerList:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
		if child:IsA("TextLabel") and child.Name == "EmptyLabel" then child:Destroy() end
	end
	playersByUserId = {}
	entryFrames = {}

	if not data or #data == 0 then
		local empty = Instance.new("TextLabel")
		empty.Name = "EmptyLabel"
		empty.Size = UDim2.new(1, -8, 0, 40)
		empty.BackgroundTransparency = 1
		empty.Font = FONT_DESC
		empty.TextSize = 13
		empty.TextColor3 = COLORS.btnTextDim
		empty.Text = "Keine anderen Spieler."
		empty.Parent = playerList
		return
	end

	for i, entry in ipairs(data) do
		playersByUserId[entry.userId] = entry
		buildPlayerEntry(entry, i)
	end
end

--------------------------------------------------------------------------------
-- renderAllianceInfo(info)
--------------------------------------------------------------------------------
local function renderAllianceInfo(info)
	if not info or not info.inAlliance then
		allianceInfo.Visible = false
		updateAllianceInfoLayout()
		return
	end

	allianceMembersLabel.Text = ("🤝 Allianz: %d/%d Mitglieder"):format(info.size or 1, info.maxSize or 3)
	alliancePointsLabel.Text = ("🏆 Allianz-Punkte: %d/%d"):format(info.points or 0, info.targetPoints or 0)
	allianceInfo.Visible = true
	updateAllianceInfoLayout()
end

--------------------------------------------------------------------------------
-- LOAD DATA (Spielerliste + Allianz-Info)
--------------------------------------------------------------------------------
local function loadDiplomacyData()
	task.spawn(function()
		local ok, data = Net.Invoke("GetDiplomacyPlayers")
		if ok and data then
			renderPlayerList(data)
		end
	end)
	task.spawn(function()
		local ok, info = Net.Invoke("GetDiplomacyAllianceInfo")
		if ok and info then
			renderAllianceInfo(info)
		end
	end)
end

--------------------------------------------------------------------------------
-- OPEN/CLOSE
--------------------------------------------------------------------------------
local function openDiplomacy()
	gui.Enabled = true
	loadDiplomacyData()
end

local function closeDiplomacy()
	gui.Enabled = false
end

closeButton.Activated:Connect(closeDiplomacy)

--------------------------------------------------------------------------------
-- TOGGLE + LIVE UPDATE
-- Toggle-Handler: reagiert auf den AKTUELLEN Zustand (gui.Enabled). Der
-- Empire-Button feuert nur noch das gemeinsame ClientState-Event; dieses
-- Script ist die alleinige Quelle der Wahrheit fuer sein eigenes Enabled.
--------------------------------------------------------------------------------
ClientState.ToggleDiplomacy:Connect(function()
	if gui.Enabled then
		closeDiplomacy()
	else
		openDiplomacy()
	end
end)

-- Statusaenderungen live aktualisieren (nur wenn das Panel gerade offen ist).
Net.On("DiplomacyUpdate", function(data)
	if not gui.Enabled then return end
	loadDiplomacyData()
end)

--------------------------------------------------------------------------------
-- BOOT
--------------------------------------------------------------------------------
print("[DiplomacyGuiController] Bereit (code-generiert, Fantasy-Stil, Panel rechts).")
