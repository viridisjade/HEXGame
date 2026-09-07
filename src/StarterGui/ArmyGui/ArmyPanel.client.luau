
--[[
    ArmyPanel (LocalScript)
    Ort: StarterGui > ArmyGui > ArmyPanel
    
    Die komplette Army-Oberfläche in EINEM Script:
      - GUI öffnen/schließen bei Auswahl
      - Stats anzeigen
      - Unit-Slots füllen + Detailansicht beim Klick
      - BuildCampButton
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local State = require(ReplicatedStorage:WaitForChild("ClientState"))
local Net = require(ReplicatedStorage:WaitForChild("Net"))
local UnitConfig = require(ReplicatedStorage:WaitForChild("UnitConfig"))

--------------------------------------------------------------------------------
-- 1) REFERENZEN
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

--------------------------------------------------------------------------------
-- NEW (turn based combat): "in combat" indicator + "watch combat" button.
-- Both are created at runtime when they do not exist in the Studio GUI.
--------------------------------------------------------------------------------
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

local inCombat = false

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

local lastSignature = nil
local shownUnitId = nil

--------------------------------------------------------------------------------
-- 2) FUNKTIONEN
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
	lastSignature = nil
end

local function fillSlots(army)
	clearSlots()
	if not army.units then return end

	for i, unitId in ipairs(army.units) do
		if i > MAX_SLOTS then break end
		local s = slots[i]

		local ok, unit = Net.Invoke("GetUnit", unitId)
		if ok and unit then
			local cfg = UnitConfig.GetUnit(unit.unitType)
			if cfg then
				if s.image then s.image.Image = cfg.Icon or "" s.image.Visible = true end
				if s.name then s.name.Text = cfg.Name or unit.unitType s.name.Visible = true end
			end
		end
	end
end

local function showUnitDetail(unitId)
	local ok, unit = Net.Invoke("GetUnit", unitId)
	if not ok or not unit then clearUnitDetail() return end

	local cfg = UnitConfig.GetUnit(unit.unitType)
	if not cfg or not cfg.Stats then clearUnitDetail() return end

	shownUnitId = unitId

	if unitFrame then unitFrame.Visible = true end
	if unitImage then unitImage.Image = cfg.Icon or "" unitImage.Visible = true end
	if uName then uName.Text = cfg.Name or unit.unitType end
	if uHealth then uHealth.Text = (unit.currentLP or 0) .. "/" .. (unit.maxLP or cfg.Stats.LP) end
	if uAttack then uAttack.Text = cfg.Stats.Attack .. " Attack" end
	if uDefense then uDefense.Text = cfg.Stats.Defense .. " Defense" end
	if uSight then uSight.Text = cfg.Stats.Sight .. " Sight" end
	if uMovement then
		uMovement.Text = (unit.currentMovement or 0) .. "/"
			.. (unit.maxMovement or cfg.Stats.Movement) .. " Move"
	end
end

local function refresh(armyId)
	if not armyId then return end

	local ok, army = Net.Invoke("GetArmy", armyId)
	if not ok or not army then return end

	if lblName then lblName.Text = army.name or ("Army " .. armyId) end

	local sig = table.concat(army.units or {}, ",")
	if sig ~= lastSignature then
		fillSlots(army)
		lastSignature = sig
	end

	local st = army.stats or {}
	if lblAttack then lblAttack.Text = (st.Attack or 0) .. " Attack" end
	if lblDefense then lblDefense.Text = (st.Defense or 0) .. " Defense" end
	if lblHealth then lblHealth.Text = (st.LP or 0) .. "/" .. (st.MaxLP or 0) end
	if lblSight then lblSight.Text = (st.Sight or 0) .. " Sight" end
	if lblMove then
		local cur = st.Movement or 0
		lblMove.Text = cur .. "/" .. (st.MaxMovement or cur) .. " Move"
	end

	if shownUnitId then showUnitDetail(shownUnitId) end
end

--------------------------------------------------------------------------------
-- NEW: ask the server whether this army is locked in a combat and lock the
-- action buttons accordingly.
--------------------------------------------------------------------------------
local function applyCombatLock(armyId)
	-- Local, non blocking lookup. A RemoteFunction call here would spawn a
	-- new hanging thread every 0.5s poll if the server side is not bound.
	task.spawn(function()
		if State.GetId(State.Kind.ARMY) ~= armyId then return end

		inCombat = State.IsArmyInCombat ~= nil and State.IsArmyInCombat(armyId) == true

		if combatLabel then combatLabel.Visible = inCombat end
		if watchBtn then watchBtn.Visible = inCombat end
		if buildBtn then
			-- No camp building while fighting.
			buildBtn.Active = not inCombat
			buildBtn.AutoButtonColor = not inCombat
		end
	end)
end

local function show(armyId)
	gui.Enabled = true
	if buildBtn then
		buildBtn.Visible = true
		buildBtn.Active = true
		buildBtn.AutoButtonColor = true
	end
	if combatLabel then combatLabel.Visible = false end
	if watchBtn then watchBtn.Visible = false end
	inCombat = false

	task.spawn(refresh, armyId)
	applyCombatLock(armyId)
end

local function hide()
	gui.Enabled = false
	if buildBtn then buildBtn.Visible = false end
	clearAll()
end

--------------------------------------------------------------------------------
-- 3) VERBINDUNGEN
--------------------------------------------------------------------------------
State.OnChanged:Connect(function(kind, id)
	if kind == State.Kind.ARMY and id then
		show(id)
	else
		hide()
	end
end)

for i = 1, MAX_SLOTS do
	local btn = slots[i].image
	if btn and (btn:IsA("ImageButton") or btn:IsA("TextButton")) then
		btn.MouseButton1Click:Connect(function()
			local armyId = State.GetId(State.Kind.ARMY)
			if not armyId then return end

			local ok, army = Net.Invoke("GetArmy", armyId)
			if not ok or not army or not army.units then return end
			if i > #army.units then return end

			showUnitDetail(army.units[i])
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

task.spawn(function()
	while true do
		task.wait(0.5)
		if gui.Enabled then
			local armyId = State.GetId(State.Kind.ARMY)
			if armyId then
				refresh(armyId)
				applyCombatLock(armyId)
			end
		end
	end
end)

local kind, id = State.Get()
if kind == State.Kind.ARMY and id then show(id) else hide() end

print("[ArmyPanel] Bereit.")
