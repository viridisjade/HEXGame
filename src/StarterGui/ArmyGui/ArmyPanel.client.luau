--[[
    ArmyPanel (LocalScript)
    Ort: StarterGui > ArmyGui > ArmyPanel

    Dynamische Army-Oberflaeche mit LIVE-Slot-Grid.

    VORHER:
      - 16 statische GUI-Elemente (UnitImage1-8 / UnitName1-8) in Studio
        modelliert, einzeln abgefragt. Brach ab einer Armee-Groesse > 8.
      - 0.5s Poll-Loop + N+1 RPC (1x GetArmy + 8x GetUnit).

    JETZT:
      - Die Unit-Slots werden per CODE in einem "UnitSlotsContainer" erzeugt.
        Anzahl richtet sich nach der maximalen Armee-Groesse
        (armyData.maxUnits = Basis 8 + Logistics-Tech-Bonus).
      - UIGridLayout bricht automatisch nach SLOTS_PER_ROW um
        (Reihe 1: 1-5, Reihe 2: 6-10, ...).
      - Leere Slots = leerer Rahmen (transparent + Stroke).
        Belegte Slots = Unit-Icon + Name.
      - Event-getrieben: keine Poll-Loops am Client.
        Die Daten kommen aus ArmyDataCache (1 Batch-Call GetArmyDetail).

    LIVE-TECH-UPDATE:
      - Erforscht der Spieler "Logistics" waehrend das Panel offen ist, feuert
        der Server (TechTreeSystem.ApplyEffect -> ArmyStats.Recalculate ->
        _G.NotifyArmyStatsChanged) -> ArmyDataCache.Refresh -> GetArmyDetail
        liefert neues maxUnits -> updateSlots() rendert das Grid neu.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local State = require(ReplicatedStorage:WaitForChild("ClientState"))
local ArmyDataCache = require(ReplicatedStorage:WaitForChild("ArmyDataCache"))
local Net = require(ReplicatedStorage:WaitForChild("Net"))

--------------------------------------------------------------------------------
-- SLOT-KONFIGURATION (zentral, anpassbar)
--------------------------------------------------------------------------------
local SLOT_CONFIG = {
	SLOTS_PER_ROW        = 5,
	SLOT_SIZE            = UDim2.new(0, 52, 0, 56),   -- an das MainframeArmy-Layout angepasst
	SLOT_PADDING         = UDim2.new(0, 6, 0, 6),
	-- Position des UnitSlotsContainer innerhalb MainframeArmy
	CONTAINER_POSITION   = UDim2.new(0.04, 0, 0.38, 0),
	CONTAINER_SIZE       = UDim2.new(0.72, 0, 0.42, 0),
	CONTAINER_NAME       = "UnitSlotsContainer",
	MAX_UNITS            = 99,                        -- harte Obergrenze gegen Spam
	EMPTY_SLOT_COLOR      = Color3.fromRGB(80, 80, 80),
	EMPTY_SLOT_TRANSPARENCY = 0.7,
	EMPTY_SLOT_BORDER_COLOR = Color3.fromRGB(150, 150, 150),
	SELECTED_SLOT_COLOR   = Color3.fromRGB(255, 215, 0), -- Gold
	SLOT_BORDER_COLOR     = Color3.fromRGB(255, 255, 255),
	SLOT_BORDER_SPEED     = 0.35,
}

--------------------------------------------------------------------------------
-- 1) GUI-REFERENZEN
--------------------------------------------------------------------------------
local gui = script.Parent:IsA("ScreenGui")
	and script.Parent
	or script.Parent:FindFirstAncestorWhichIsA("ScreenGui")

if not gui then
	warn("[ArmyPanel] Keine ScreenGui gefunden!")
	return
end

gui.Enabled = false

local frame = gui:FindFirstChild("MainframeArmy")
if not frame then
	warn("[ArmyPanel] MainframeArmy fehlt in " .. gui:GetFullName())
end

local function pick(parent, name)
	return parent and parent:FindFirstChild(name) or nil
end

-- Statische GUI-Elemente (bleiben UNVERAENDERT)
local statFrame      = pick(frame, "ArmyStatFrame")
local lblName        = pick(gui, "ArmyNameLable") or pick(frame, "ArmyNameLable")
local lblAttack      = pick(statFrame, "ArmyAttackLabel")
local lblDefense     = pick(statFrame, "ArmyDefensiveLabel")
local lblHealth      = pick(statFrame, "ArmyHealthbarLabel")
local lblMove        = pick(statFrame, "ArmyMoveLabel")
local lblSight       = pick(statFrame, "ArmySightLabel")
local unitFrame      = pick(frame, "UnitStatFrame")
local hoverImage     = pick(frame, "HoverUnitImage")
local uName          = pick(unitFrame, "UnitNameLable")
local uHealth        = pick(unitFrame, "HealthNumberLabel")
local uAttack        = pick(unitFrame, "UnitAttackLable")
local uDefense       = pick(unitFrame, "UnitDefenseLable")
local uSight         = pick(unitFrame, "UnitSightLable")
local uMovement      = pick(unitFrame, "UnitMovementLable")
local buildBtn       = pick(frame, "BuildCampButton")
local stopSelectBtn  = pick(frame, "StopSelectButton")

--------------------------------------------------------------------------------
-- OPEN/CLOSE + DYNAMISCHE SLOTS
--------------------------------------------------------------------------------
local MAX_SLOTS = SLOT_CONFIG.MAX_UNITS
local slotGrid = {}          -- index -> { frame, icon, name, unitId }
local cachedMaxUnits = 0     -- letzter bekannter Wert, um Grid neu zu bauen
local shownUnitId = nil      -- aktuell ausgewaehlte Unit
local hoveredUnitId = nil    -- Slot, ueber dem die Maus gerade steht (transient)

--------------------------------------------------------------------------------
-- Aufraeumen: alte statische Slots (UnitImage1-8 / UnitName1-8) entfernen.
-- Die Slots sitzen direkt in MainframeArmy (ausgestattet im alten Layout).
--------------------------------------------------------------------------------
local function cleanupLegacySlots()
	if not frame then return end
	for _, child in ipairs(frame:GetChildren()) do
		if child.Name:match("^UnitImage%d+$") or child.Name:match("^UnitName%d+$") then
			child:Destroy()
		end
	end
end

--------------------------------------------------------------------------------
-- UnitSlotsContainer erstellen (einmalig).
--------------------------------------------------------------------------------
local slotsContainer = frame and frame:FindFirstChild(SLOT_CONFIG.CONTAINER_NAME)
if frame and not slotsContainer then
	slotsContainer = Instance.new("Frame")
	slotsContainer.Name = SLOT_CONFIG.CONTAINER_NAME
	slotsContainer.BackgroundTransparency = 1
	slotsContainer.BorderSizePixel = 0
	slotsContainer.Position = SLOT_CONFIG.CONTAINER_POSITION
	slotsContainer.Size = SLOT_CONFIG.CONTAINER_SIZE
	slotsContainer.ZIndex = 2
	slotsContainer.Parent = frame

	local layout = Instance.new("UIGridLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.FillDirectionMaxCells = SLOT_CONFIG.SLOTS_PER_ROW
	layout.CellSize = SLOT_CONFIG.SLOT_SIZE
	layout.CellPadding = SLOT_CONFIG.SLOT_PADDING
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = slotsContainer
end

-- Forward-Deklarationen:
-- Diese Funktionen referenzieren sich gegenseitig. In Lua sind `local function`
-- nur ab ihrer Deklarationsstelle sichtbar, daher deklarieren wir die Namen vorab
-- und weisen sie spaeter zu (sonst wuerden Aufrufe auf `nil` laufen).
local renderUnitSlots
local updateSlots
local renderStats
local showUnitDetail
local clearUnitDetail
local clearAll

-- HoverUnitImage-Update (Bug-2-Fix):
-- Die AUSWAHL hat PRIORITAET ueber den HOVER.
--   1) Wenn eine Unit ausgewaehlt ist (shownUnitId) -> immer diese anzeigen.
--   2) Sonst, wenn die Maus ueber einem belegten Slot steht -> gehoverte anzeigen.
--   3) Sonst -> ausblenden.
-- MouseLeave loescht das Bild NUR, wenn keine Unit ausgewaehlt ist.
local function refreshHoverImage()
	if not hoverImage then return end

	-- Prio 1: ausgewaehlte Unit (bleibt permanent sichtbar).
	if shownUnitId then
		local unit = ArmyDataCache.GetUnit(shownUnitId)
		if unit and unit.icon and unit.icon ~= "" then
			hoverImage.Image = unit.icon
			hoverImage.Visible = true
			return
		end
	end

	-- Prio 2: gehoverte Unit (transient), nur wenn nichts ausgewaehlt ist.
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
-- EINZELNE SLOT-KACHEL bauen
--------------------------------------------------------------------------------
local function buildSlot(index)
	local holder = Instance.new("Frame")
	holder.Name = "Slot_" .. index
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 1, 0)  -- richtet sich nach UIGridLayout
	holder.LayoutOrder = index
	holder.Parent = slotsContainer

	-- Icon als ImageButton (leerer Rahmen wenn kein Bild)
	local icon = Instance.new("ImageButton")
	icon.Name = "Icon"
	icon.Size = UDim2.new(1, 0, 0.72, 0)
	icon.Position = UDim2.new(0, 0, 0, 0)
	icon.AnchorPoint = Vector2.new(0, 0)
	icon.BackgroundColor3 = SLOT_CONFIG.EMPTY_SLOT_COLOR
	icon.BackgroundTransparency = SLOT_CONFIG.EMPTY_SLOT_TRANSPARENCY
	icon.ImageTransparency = 1  -- kein Bild => transparenter Rahmen
	icon.ScaleType = Enum.ScaleType.Fit
	icon.BorderSizePixel = 0
	icon.AutoButtonColor = false
	icon.ZIndex = 3
	icon.Parent = holder

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = icon

	local stroke = Instance.new("UIStroke")
	stroke.Color = SLOT_CONFIG.EMPTY_SLOT_BORDER_COLOR
	stroke.Thickness = 1
	stroke.Transparency = 0.3
	stroke.Parent = icon

	-- Name darunter (kleiner Text)
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.Size = UDim2.new(1, 0, 0.28, 0)
	nameLabel.Position = UDim2.new(0, 0, 0.74, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.Gotham
	nameLabel.TextSize = 11
	nameLabel.TextColor3 = Color3.fromRGB(238, 240, 248)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Center
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Text = ""
	nameLabel.ZIndex = 3
	nameLabel.Parent = holder

	return { holder = holder, icon = icon, name = nameLabel, unitId = nil }
end

--------------------------------------------------------------------------------
-- Hover-Handler auf einen Slot (zeigt HoverUnitImage fuer belegte Slots)
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
-- SLOT-ZUSTAND setzen (leer oder belegt)
--------------------------------------------------------------------------------
local function styleSlot(slot, unit, isSelected)
	if not slot then return end

	slot.unitId = unit and unit.id or nil

	if unit then
		slot.icon.Image = unit.icon or ""
		slot.icon.ImageTransparency = (unit.icon and unit.icon ~= "") and 0 or 1
		slot.icon.BackgroundTransparency = 0.2
		slot.icon.BackgroundColor3 = Color3.fromRGB(40, 44, 56)
		slot.name.Text = unit.name or unit.unitType or ""
	else
		slot.icon.Image = ""
		slot.icon.ImageTransparency = 1
		slot.icon.BackgroundTransparency = SLOT_CONFIG.EMPTY_SLOT_TRANSPARENCY
		slot.icon.BackgroundColor3 = SLOT_CONFIG.EMPTY_SLOT_COLOR
		slot.name.Text = ""
	end

	-- Auswahl (Gold-Highlight)
	local stroke = slot.icon:FindFirstChildOfClass("UIStroke")
	if isSelected then
		if stroke then
			stroke.Color = SLOT_CONFIG.SELECTED_SLOT_COLOR
			stroke.Thickness = 2.5
			stroke.Transparency = 0
		end
	else
		if stroke then
			stroke.Color = SLOT_CONFIG.EMPTY_SLOT_BORDER_COLOR
			stroke.Thickness = 1
			stroke.Transparency = unit and 0.3 or 0.5
		end
	end
end

--------------------------------------------------------------------------------
-- renderUnitSlots(armyData): Grid neu bauen (wenn maxUnits sich aendert)
--------------------------------------------------------------------------------
renderUnitSlots = function(army)
	if not slotsContainer then return end

	local maxUnits = math.clamp(army and army.maxUnits or 8, 1, MAX_SLOTS)
	if maxUnits == cachedMaxUnits then return end   -- nichts geaendert -> ueberspringen
	cachedMaxUnits = maxUnits

	-- Alte Slots entfernen
	for i = #slotGrid, 1, -1 do
		if slotGrid[i].holder then slotGrid[i].holder:Destroy() end
	end
	slotGrid = {}

	-- Neue Slots ueber maxUnits erstellen
	for i = 1, maxUnits do
		local slot = buildSlot(i)
		-- Click -> Unit auswaehlen (nur wenn belegt)
		slot.icon.MouseButton1Click:Connect(function()
			local armyNow = ArmyDataCache.Get()
			local unit = armyNow and armyNow.units and armyNow.units[i] or nil
			if unit then showUnitDetail(unit.id, i) end
		end)
		attachHover(slot.holder, function() return slotGrid[i] and slotGrid[i].unitId or nil end)
		slotGrid[i] = slot
	end
end

--------------------------------------------------------------------------------
-- updateSlots(armyData): Icons/Namen auffrischen, nur selten Grid neu bauen
--------------------------------------------------------------------------------
updateSlots = function(army)
	if not army then
		clearAll()
		return
	end

	local maxUnits = math.clamp(army.maxUnits or 8, 1, MAX_SLOTS)
	-- Grid neu bauen falls sich die maximale Groesse geaendert hat (z.B. Logistics).
	if maxUnits ~= cachedMaxUnits then
		renderUnitSlots(army)
	end

	for i = 1, math.min(maxUnits, #slotGrid) do
		local slot = slotGrid[i]
		local unit = army.units and army.units[i] or nil
		-- Gold-Highlight bleibt an der Unit-ID haengen (auch nach Grid-Rebuild).
		styleSlot(slot, unit, unit ~= nil and unit.id == shownUnitId)
	end
end

--------------------------------------------------------------------------------
-- Army-Stat-Anzeige
--------------------------------------------------------------------------------
renderStats = function(army)
	if lblName then lblName.Text = army.name or ("Army " .. army.id) end
	local st = army.stats or {}
	if lblAttack then lblAttack.Text = (st.Attack or 0) .. " Attack" end
	if lblDefense then lblDefense.Text = (st.Defense or 0) .. " Defense" end
	if lblHealth then lblHealth.Text = (st.LP or 0) .. "/" .. (st.MaxLP or 0) end
	if lblSight then lblSight.Text = (st.Sight or 0) .. " Sight" end
	if lblMove then
		local cur = st.Movement or 0
		lblMove.Text = cur .. "/" .. (st.MaxMovement or cur) .. " Move"
	end
end

--------------------------------------------------------------------------------
-- Unit-Detailansicht (UnitStatFrame) bei Slot-Klick
--------------------------------------------------------------------------------
showUnitDetail = function(unitId, slotIndex)
	local army = ArmyDataCache.Get()
	local unit = army and army.units and army.units[slotIndex] or nil
	if not unit then
		clearUnitDetail()
		return
	end

	shownUnitId = unitId

	if unitFrame then unitFrame.Visible = true end
	refreshHoverImage()
	if uName then uName.Text = unit.name or unit.unitType end
	if uHealth then uHealth.Text = unit.currentLP .. "/" .. unit.maxLP end
	if uAttack then uAttack.Text = unit.attack .. " Attack" end
	if uDefense then uDefense.Text = unit.defense .. " Defense" end
	if uSight then uSight.Text = unit.sight .. " Sight" end
	if uMovement then uMovement.Text = unit.currentMovement .. "/" .. unit.maxMovement .. " Move" end

	-- Gold-Highlight auf dem ausgewaehlten Slot (nur belegte Slots)
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
	if unitFrame then unitFrame.Visible = false end
	refreshHoverImage()
end

clearAll = function()
	renderStats({})
	if slotsContainer then
		for i = 1, #slotGrid do
			local slot = slotGrid[i]
			if slot then
				slot.icon.Image = ""
				slot.icon.ImageTransparency = 1
				slot.icon.BackgroundTransparency = SLOT_CONFIG.EMPTY_SLOT_TRANSPARENCY
				slot.name.Text = ""
			end
		end
	end
	clearUnitDetail()
end

--------------------------------------------------------------------------------
-- Kampf-Lock (event-getrieben, wie zuvor)
--------------------------------------------------------------------------------
local inCombat = false
local combatLabel = frame and frame:FindFirstChild("InCombatLabel")
if frame and not combatLabel then
	combatLabel = Instance.new("TextLabel")
	combatLabel.Name = "InCombatLabel"
	combatLabel.Size = UDim2.new(1, -16, 0, 20)
	combatLabel.Position = UDim2.new(0, 8, 0, 2)
	combatLabel.BackgroundTransparency = 1
	combatLabel.Font = Enum.Font.GothamBold
	combatLabel.TextSize = 14
	combatLabel.TextColor3 = Color3.fromRGB(255, 120, 90)
	combatLabel.TextXAlignment = Enum.TextXAlignment.Right
	combatLabel.Text = "IM KAMPF"
	combatLabel.Visible = false
	combatLabel.Parent = frame
end

local watchBtn = frame and frame:FindFirstChild("WatchCombatButton")
if frame and not watchBtn then
	watchBtn = Instance.new("TextButton")
	watchBtn.Name = "WatchCombatButton"
	watchBtn.Size = UDim2.new(0, 150, 0, 30)
	watchBtn.Position = UDim2.new(0, 8, 1, -38)
	watchBtn.BackgroundColor3 = Color3.fromRGB(150, 70, 60)
	watchBtn.Font = Enum.Font.GothamBold
	watchBtn.TextSize = 14
	watchBtn.TextColor3 = Color3.new(1, 1, 1)
	watchBtn.Text = "Kampf ansehen"
	watchBtn.Visible = false
	watchBtn.BorderSizePixel = 0
	watchBtn.Parent = frame
end

local function applyCombatLock()
	local armyId = State.GetId(State.Kind.ARMY)
	inCombat = State.IsArmyInCombat ~= nil
		and State.IsArmyInCombat(armyId or 0)

	if combatLabel then combatLabel.Visible = inCombat end
	if watchBtn then watchBtn.Visible = inCombat end
	if buildBtn then
		buildBtn.Active = not inCombat
		buildBtn.AutoButtonColor = not inCombat
	end
end

--------------------------------------------------------------------------------
-- OEFFNEN / SCHLIESSEN
--------------------------------------------------------------------------------
local function show()
	gui.Enabled = true
	cleanupLegacySlots()
	-- BuildCampButton IMMER sichtbar/klickbar machen - unabhaengig von
	-- Auswahl oder dynamischem Slot-System (Bug-1-Fix).
	if buildBtn then
		buildBtn.Visible = true
		buildBtn.Active = true
		buildBtn.AutoButtonColor = true
	end
	applyCombatLock()
	ArmyDataCache.Refresh()
end

local function hide()
	gui.Enabled = false
	-- BuildCampButton NICHT verstecken: er soll dauerhaft sichtbar bleiben.
	-- Das Panel wird ueber gui.Enabled ein-/ausgeblendet, nicht ueber den Button.
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

-- StopSelectButton: aktuelle Unit deselektieren
if stopSelectBtn then
	stopSelectBtn.MouseButton1Click:Connect(function()
		clearUnitDetail()
	end)
end

if watchBtn then
	watchBtn.Activated:Connect(function()
		local openEvent = ReplicatedStorage:FindFirstChild("OpenCombatView")
		if openEvent then openEvent:Fire() end
	end)
end

if buildBtn then
	buildBtn.MouseButton1Click:Connect(function()
		local armyId = State.GetId(State.Kind.ARMY)
		if not armyId then return end
		if inCombat then
			print("[ArmyPanel] Army ist im Kampf - Camp-Bau blockiert")
			return
		end
		Net.Fire("RequestBuildCamp", armyId)
	end)
end

--------------------------------------------------------------------------------
-- BOOT
--------------------------------------------------------------------------------
cleanupLegacySlots()
local kind, id = State.Get()
if kind == State.Kind.ARMY and id then show() else hide() end

print("[ArmyPanel] Bereit (dynamische Unit-Slots, event-driven).")
