
--[[
    InputRouter (LocalScript)
    Ort: StarterPlayer > StarterPlayerScripts > InputRouter
    
    DER EINZIGE Ort, an dem Maus- und Tastatureingaben verarbeitet werden.
--]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local State = require(ReplicatedStorage:WaitForChild("ClientState"))
local Net = require(ReplicatedStorage:WaitForChild("Net"))
local Grid = require(ReplicatedStorage:WaitForChild("HexGridConfig"))

Net.Warmup({ "GetHexInfo" })

local CLICK_COOLDOWN = 0.08
local lastClick = 0

local rayParams = RaycastParams.new()
rayParams.RespectCanCollide = false
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function buildIgnoreList()
	local ignore = {}
	for _, name in ipairs({ "LocalUnitSpawnMarkers", "RoutePreview", "PreviewClone" }) do
		local obj = workspace:FindFirstChild(name)
		if obj then table.insert(ignore, obj) end
	end
	if player.Character then table.insert(ignore, player.Character) end
	return ignore
end

local function raycastArmyId()
	rayParams.FilterDescendantsInstances = buildIgnoreList()
	local ray = mouse.UnitRay
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 1000, rayParams)
	if not hit or not hit.Instance then return nil end

	local node = hit.Instance
	while node and node ~= workspace do
		local id = node.Name:match("^Army_(%d+)$")
		if id then return tonumber(id) end
		node = node.Parent
	end
	return nil
end

local function handleLeftClick()
	if State.IsPlacing() then return end

	-- NEW: while a turn based combat overlay is open the world selection is
	-- suppressed. Unit clicks are handled inside CombatGuiController.
	if State.IsInCombat and State.IsInCombat() then return end

	local now = tick()
	if now - lastClick < CLICK_COOLDOWN then return end
	lastClick = now

	local q, r = Grid.worldToAxial(mouse.Hit.Position)
	if q == nil then
		State.Clear()
		return
	end

	local ok, info = Net.Invoke("GetHexInfo", q, r)
	if not ok or not info or not info.exists then
		State.Clear()
		return
	end

	if info.army and info.army.isMine then
		State.Toggle(State.Kind.ARMY, info.army.id)
		return
	end
	if info.army then
		State.Clear()
		return
	end
	if info.city and info.city.isMine then
		State.Toggle(State.Kind.CITY, info.city.id)
		return
	end
	if info.camp and info.camp.isMine then
		State.Toggle(State.Kind.CAMP, info.camp.id)
		return
	end

	State.Clear()
end

local rightClickEvent = Instance.new("BindableEvent")
rightClickEvent.Name = "HexRightClick"
rightClickEvent.Parent = ReplicatedStorage

local function handleRightClick()
	if State.IsPlacing() then return end

	-- NEW: no movement orders while the combat overlay is open.
	if State.IsInCombat and State.IsInCombat() then return end

	local armyId = State.GetId(State.Kind.ARMY)
	if not armyId then return end

	local q, r = Grid.worldToAxial(mouse.Hit.Position)
	if q == nil then return end

	rightClickEvent:Fire(armyId, q, r)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		local ok, err = pcall(handleLeftClick)
		if not ok then warn("[InputRouter] Linksklick: " .. tostring(err)) end

	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		local ok, err = pcall(handleRightClick)
		if not ok then warn("[InputRouter] Rechtsklick: " .. tostring(err)) end

	elseif input.KeyCode == Enum.KeyCode.T then
		-- Tech tree hotkey. The GUI owns the toggle logic, we only ping it.
		local toggle = ReplicatedStorage:FindFirstChild("ToggleTechTree")
		if toggle then toggle:Fire() end

	elseif input.KeyCode == Enum.KeyCode.Escape then
		if State.IsPlacing() then
			State.StopPlacing()
		else
			State.Clear()
		end
	end
end)

State.OnChanged:Connect(function(kind, id, prevKind, prevId)
	local from = prevKind and (prevKind .. " " .. tostring(prevId)) or "nichts"
	local to = kind and (kind .. " " .. tostring(id)) or "nichts"
	print("[Auswahl] " .. from .. " -> " .. to)
end)

print("[InputRouter] Bereit.")
