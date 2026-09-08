--[[
    ArmyPanel (LocalScript)
    Ort: StarterGui > ArmyGui > ArmyPanel

    Komplette Army-Oberflaeche, jetzt EVENT-GETRIEBEN:

    VORHER (Performance-Probleme):
      - 0.5s Poll-Loop: Net.Invoke("GetArmy") alle 0.5s, dauerhaft.
      - N+1 RPC: fuer jeden Unit ein eigenes Net.Invoke("GetUnit").
      - applyCombatLock spawnte alle 0.5s eine Task.

    JETZT:
      - Die Daten kommen aus EINEM Modul (ArmyDataCache), das die komplette
        Army in EINEM Batch-Call (GetArmyDetail) laedt.
      - Refresh passiert nur bei Auswahl-Wechsel, Server-Push (ArmyStatsChanged)
        oder Kampfzustands-Aenderung - KEIN Polling.
      - Der Kampf-Lock hoert auf ein eigenes Event (OnArmyCombatChanged).

    Ablauf:
      1) ArmyDataCache.OnUpdated -> render(army)
      2) State.OnChanged (ARMY)  -> oeffnen/schliessen
      3) State.OnArmyCombatChanged -> Kampf-Lock setzen
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local State = require(ReplicatedStorage:WaitForChild("ClientState"))
local ArmyDataCache = require(ReplicatedStorage:WaitForChild("ArmyDataCache"))
local Net = require(ReplicatedStorage:WaitForChild("Net"))

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

local MAX_SLOTS = 8
local frame = gui:FindFirstChild("MainframeArmy")

if not frame then
	warn("[ArmyPanel] MainframeArmy fehlt in " .. gui:GetFullName())
end

local function pick(parent, name)
	return parent and parent:FindFirstChild(name) or nil
end

local statFrame = pick(frame, "ArmyStatFrame")

local lblName    = pick(gui, "ArmyNameLable") or pick(frame, "ArmyNameLable")
local lblAttack  = pick(statFrame, "ArmyAttackLabel")
local lblDefense = pick(statFrame, "ArmyDefensiveLabel")
local lblHealth  = pick(statFrame, "ArmyHealthbarLabel")
local lblMove    = pick(statFrame, "ArmyMoveLabel")
local lblSight   = pick(statFrame, "ArmySightLabel")

local buildBtn = pick(frame, "BuildCampButton")

-- "in combat" indicator + "watch combat" button (created at runtime if missing).
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

local unitFrame  = pick(frame, "UnitStatFrame")
local unitImage  = pick(frame, "HoverUnitImage")
local uName      = pick(unitFrame, "UnitNameLable")
local uHealth    = pick(unitFrame, "HealthNumberLabel")
local uAttack    = pick(unitFrame, "UnitAttackLable")
local uDefense   = pick(unitFrame, "UnitDefenseLable")
local uSight     = pick(unitFrame, "UnitSightLable")
local uMovement  = pick(unitFrame, "UnitMovementLable")

local slots = {}
for i = 1, MAX_SLOTS do
	slots[i] = {
		image = pick(frame, "UnitImage" .. i) or pick(gui, "UnitImage" .. i),
		name  = pick(frame, "UnitName" .. i)  or pick(gui, "UnitName" .. i),
	}
end

local shownUnitId = nil

--------------------------------------------------------------------------------
-- 2) RENDER-HILFEN
--------------------------------------------------------------------------------
local function clearSlots()
	for i = 1, MAX_SLOTS do
		local s = slots[i]
		if s.image then s.image.Image = "" s.image.Visible = false end
		if s.name then s.name.Text = "" s.name.Visible = false end
	end
end

local function clearUnitDetail()
	shownUnitId = nil
	if unitFrame then unitFrame.Visible = false end
	if unitImage then unitImage.Image = "" unitImage.Visible = false end
end

local function clearAll()
	if lblName then lblName.Text = "" end
	if lblAttack then lblAttack.Text = "0 Attack" end
	if lblDefense then lblDefense.Text = "0 Defense" end
	if lblHealth then lblHealth.Text = "0/0" end
	if lblMove then lblMove.Text = "0/0 Move" end
	if lblSight then lblSight.Text = "0 Sight" end
	clearSlots()
	clearUnitDetail()
end

local function fillSlots(army)
	clearSlots()
	if not army or not army.units then return end

	for i, unit in ipairs(army.units) do
		if i > MAX_SLOTS then break end
		local s = slots[i]
		if not s.image and not s.name then continue end
		if s.image then s.image.Image = unit.icon or "" s.image.Visible = true end
		if s.name then s.name.Text = unit.name or unit.unitType s.name.Visible = true end
	end
end

local function showUnitDetail(unitId)
	local unit = ArmyDataCache.GetUnit(unitId)
	if not unit then clearUnitDetail() return end

	shownUnitId = unitId

	if unitFrame then unitFrame.Visible = true end
	if unitImage then unitImage.Image = unit.icon or "" unitImage.Visible = true end
	if uName then uName.Text = unit.name or unit.unitType end
	if uHealth then uHealth.Text = unit.currentLP .. "/" .. unit.maxLP end
	if uAttack then uAttack.Text = unit.attack .. " Attack" end
	if uDefense then uDefense.Text = unit.defense .. " Defense" end
	if uSight then uSight.Text = unit.sight .. " Sight" end
	if uMovement then uMovement.Text = unit.currentMovement .. "/" .. unit.maxMovement .. " Move" end
end

local function render(army)
	if not army then
		clearAll()
		return
	end

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

	fillSlots(army)
	if shownUnitId then showUnitDetail(shownUnitId) end
end

--------------------------------------------------------------------------------
-- 3) KAMPF-LOCK (event-getrieben)
--------------------------------------------------------------------------------
local inCombat = false

local function applyCombatLock()
	local armyId = State.GetId(State.Kind.ARMY)
	inCombat = State.IsArmyInCombat ~= nil
		and State.IsArmyInCombat(armyId or 0)

	if combatLabel then combatLabel.Visible = inCombat end
	if watchBtn then watchBtn.Visible = inCombat end
	if buildBtn then
		-- No camp building while fighting.
		buildBtn.Active = not inCombat
		buildBtn.AutoButtonColor = not inCombat
	end
end

--------------------------------------------------------------------------------
-- 4) OEFFNEN / SCHLIESSEN
--------------------------------------------------------------------------------
local function show()
	gui.Enabled = true
	-- Combat-Status direkt beim Oeffnen setzen (kein Warten auf Poll).
	applyCombatLock()
	-- Daten frisch laden (oder aus Cache), dann rendern.
	ArmyDataCache.Refresh()
end

local function hide()
	gui.Enabled = false
	if buildBtn then buildBtn.Visible = false end
	clearAll()
end

--------------------------------------------------------------------------------
-- 5) VERBINDUNGEN
--------------------------------------------------------------------------------
-- Army-Daten sind da (oder Auswahl aufgehoben).
ArmyDataCache.OnUpdated:Connect(function(army)
	render(army)
end)

-- Auswahl: Army -> anzeigen, sonst -> verstecken.
State.OnChanged:Connect(function(kind, id)
	if kind == State.Kind.ARMY and id then
		show()
	else
		hide()
	end
end)

-- Kampf-Lock reagiert sofort, ohne Polling.
if State.OnArmyCombatChanged then
	State.OnArmyCombatChanged:Connect(function(armyId)
		if State.GetId(State.Kind.ARMY) == armyId then
			applyCombatLock()
		end
	end)
end

-- Unit-Kacheln: Klick -> Detailansicht.
for i = 1, MAX_SLOTS do
	local btn = slots[i].image
	if btn and (btn:IsA("ImageButton") or btn:IsA("TextButton")) then
		btn.MouseButton1Click:Connect(function()
			local army = ArmyDataCache.Get()
			if not army or not army.units then return end
			local unit = army.units[i]
			if unit then showUnitDetail(unit.id) end
		end)
	end
end

if watchBtn then
	-- Re-opens the combat overlay for a fight that is already running.
	watchBtn.Activated:Connect(function()
		local openEvent = ReplicatedStorage:FindFirstChild("OpenCombatView")
		if openEvent then
			openEvent:Fire()
		else
			warn("[ArmyPanel] OpenCombatView BindableEvent fehlt")
		end
	end)
end

if buildBtn then
	buildBtn.MouseButton1Click:Connect(function()
		local armyId = State.GetId(State.Kind.ARMY)
		if not armyId then
			print("[ArmyPanel] Keine Army ausgewählt")
			return
		end
		if inCombat then
			print("[ArmyPanel] Army ist im Kampf - Camp-Bau blockiert")
			return
		end
		print("[ArmyPanel] Camp-Bau angefordert für Army " .. armyId)
		Net.Fire("RequestBuildCamp", armyId)
	end)
else
	warn("[ArmyPanel] BuildCampButton fehlt in MainframeArmy")
end

--------------------------------------------------------------------------------
-- 6) BOOT
--------------------------------------------------------------------------------
local kind, id = State.Get()
if kind == State.Kind.ARMY and id then
	show()
else
	hide()
end

print("[ArmyPanel] Bereit (event-driven).")
