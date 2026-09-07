
--[[
    MovementController (LocalScript)
    Ort: StarterPlayer > StarterPlayerScripts > MovementController
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local State = require(ReplicatedStorage:WaitForChild("ClientState"))
local Net = require(ReplicatedStorage:WaitForChild("Net"))
local Grid = require(ReplicatedStorage:WaitForChild("HexGridConfig"))

local rightClick = ReplicatedStorage:WaitForChild("HexRightClick", 20)

Net.Warmup({ "RequestRoute", "ConfirmMove", "CancelMove", "RoundEnd" })

local orders = {}
local routeFolder = nil

local function clearRoute()
	if routeFolder and routeFolder.Parent then routeFolder:Destroy() end
	routeFolder = nil
end

local function drawRoute(path, reachable)
	clearRoute()
	if not path or #path <= 1 then return end

	routeFolder = Instance.new("Folder")
	routeFolder.Name = "RoutePreview"
	routeFolder.Parent = workspace

	local y = Grid.Config.SPAWN_Y + 5

	for i = 1, #path - 1 do
		local a = Grid.axialToWorld(path[i].q, path[i].r)
		local b = Grid.axialToWorld(path[i + 1].q, path[i + 1].r)
		local from = Vector3.new(a.X, y, a.Z)
		local to = Vector3.new(b.X, y, b.Z)

		local line = Instance.new("Part")
		line.Anchored = true
		line.CanCollide = false
		line.CanQuery = false
		line.Material = Enum.Material.Neon
		line.Size = Vector3.new(0.4, 0.4, (to - from).Magnitude)
		line.CFrame = CFrame.new((from + to) / 2, to)
		line.Color = (i <= reachable)
			and Color3.fromRGB(50, 150, 255)
			or Color3.fromRGB(255, 200, 50)
		line.Parent = routeFolder
	end

	local last = path[#path]
	local pos = Grid.axialToWorld(last.q, last.r)
	local marker = Instance.new("Part")
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.Shape = Enum.PartType.Cylinder
	marker.Size = Vector3.new(0.3, 6, 6)
	marker.CFrame = CFrame.new(pos.X, y, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
	marker.Material = Enum.Material.Neon
	marker.Transparency = 0.3
	marker.Color = (reachable >= #path - 1)
		and Color3.fromRGB(50, 255, 100)
		or Color3.fromRGB(255, 200, 50)
	marker.Parent = routeFolder
end

local function showRouteFor(armyId)
	local order = orders[armyId]
	if order and order.path then
		drawRoute(order.path, order.steps or 0)
	else
		clearRoute()
	end
end

local function requestRoute(armyId, q, r, isRefresh)
	local ok, result = Net.Invoke("RequestRoute", armyId, q, r, isRefresh == true)
	if not ok or not result or not result.path then
		if result and result.reason then
			print("[Movement] " .. result.reason)
		end
		return nil
	end
	return result
end

local function refreshOrder(armyId)
	local order = orders[armyId]
	if not order then return end

	local result = requestRoute(armyId, order.targetQ, order.targetR, true)
	if not result or not result.path or #result.path <= 1 then
		orders[armyId] = nil
		return
	end

	order.path = result.path
	order.steps = result.reachableSteps or 0
end

--------------------------------------------------------------------------------
-- Armies locked in a combat cannot receive route orders.
--
-- IMPORTANT: this check must NEVER block. It used to call
-- Net.Invoke("GetArmyInCombat", ...) right inside the click handler - an
-- unanswered RemoteFunction yields forever, which silently killed EVERY
-- right click. We now read the local ClientState hint only; the server
-- rejects illegal moves anyway (MovementHandler + ArmySystem).
--------------------------------------------------------------------------------
local function isArmyInCombat(armyId)
	return State.IsArmyInCombat ~= nil and State.IsArmyInCombat(armyId) == true
end

local function onRightClick(armyId, q, r)
	if isArmyInCombat(armyId) then
		print("[Movement] Army " .. tostring(armyId) .. " ist im Kampf - keine Route")
		clearRoute()
		return
	end

	local order = orders[armyId]

	if order and not order.confirmed
		and order.targetQ == q and order.targetR == r then

		Net.Fire("ConfirmMove", armyId)
		order.confirmed = true
		order.steps = 0
		print("[Movement] Bewegung bestätigt")

		task.delay(0.8, function()
			refreshOrder(armyId)
			showRouteFor(armyId)
		end)
		return
	end

	local result = requestRoute(armyId, q, r, false)
	if not result then
		orders[armyId] = nil
		clearRoute()
		return
	end

	orders[armyId] = {
		path = result.path,
		targetQ = q,
		targetR = r,
		steps = result.reachableSteps or 0,
		confirmed = false,
	}

	showRouteFor(armyId)
	print("[Movement] Route: " .. #result.path .. " Felder, "
		.. (result.reachableSteps or 0) .. " diese Runde")
end

if rightClick then
	rightClick.Event:Connect(function(armyId, q, r)
		local ok, err = pcall(onRightClick, armyId, q, r)
		if not ok then warn("[Movement] " .. tostring(err)) end
	end)
else
	warn("[Movement] HexRightClick Event fehlt - läuft der InputRouter?")
end

State.OnChanged:Connect(function(kind, id)
	if kind == State.Kind.ARMY and id then
		showRouteFor(id)
	else
		clearRoute()
	end
end)

State.OnChanged:Connect(function(kind, id, prevKind, prevId)
	if prevKind == State.Kind.ARMY and prevId and kind ~= State.Kind.ARMY then
		local order = orders[prevId]
		if order and not order.confirmed then
			Net.Fire("CancelMove", prevId)
			orders[prevId] = nil
		end
	end
end)

Net.On("RoundEnd", function(data)
	if type(data) ~= "table" then return end

	if data.type == "roundStart" then
		task.wait(1.2)

		for armyId in pairs(orders) do
			refreshOrder(armyId)
		end

		local kind, id = State.Get()
		if kind == State.Kind.ARMY then showRouteFor(id) end
	end
end)

print("[MovementController] Bereit. Rechtsklick = Route, nochmal = ausführen.")
