
--[[
    MovementController (LocalScript)
    Ort: StarterPlayer > StarterPlayerScripts > MovementController

    STADT-BESETZUNG MIT BÜRGERWEHR (Popup-Bestaetigung, siehe MovementHandler):
        Der Server sendet "CityAttackPopup", sobald ein bestaetigter
        Bewegungsbefehl auf ein feindliches Stadt-/Camp-Hex fuehren wuerde.
        Dieses Script zeigt dann ein code-generiertes Fantasy-Popup:
            "⚔️ Willst du die Stadt [Name] wirklich angreifen?"
            (+ Hauptstadt-Warnung, + "unbewohnt"-Variante bei 0 Buergern)
        [Abbrechen] -> RequestAttackCity(confirmed=false), Bewegung verworfen.
        [Angreifen] -> RequestAttackCity(confirmed=true), Server bewegt die
                       Armee 1 Hex vor die Stadt und startet den Belagerungs-
                       Kampf (oder uebernimmt sofort bei 0 Buergern).
        "CityAttackResult" zeigt danach eine kurze Erfolgs-/Misserfolgs-
        Meldung (auch fuer den blockierten Fall bei Neutral/Allianz).
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local State = require(ReplicatedStorage:WaitForChild("ClientState"))
local Net = require(ReplicatedStorage:WaitForChild("Net"))
local Grid = require(ReplicatedStorage:WaitForChild("HexGridConfig"))

local rightClick = ReplicatedStorage:WaitForChild("HexRightClick", 20)

Net.Warmup({ "RequestRoute", "ConfirmMove", "CancelMove", "RoundEnd", "RequestAttackCity" })

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

--------------------------------------------------------------------------------
-- STADT-BESETZUNG: Popup-GUI (code-generiert, Fantasy-Stil wie alle anderen
-- GUIs). Wird nur bei Bedarf einmal erzeugt und danach wiederverwendet.
--------------------------------------------------------------------------------
local COLORS = {
	windowBg    = Color3.fromRGB(35, 28, 22),
	panelBorder = Color3.fromRGB(120, 90, 50),
	headerBg    = Color3.fromRGB(120, 30, 30),
	headerText  = Color3.fromRGB(255, 220, 150),
	text        = Color3.fromRGB(230, 220, 205),
	warning     = Color3.fromRGB(255, 120, 90),
	btnCancel   = Color3.fromRGB(70, 55, 40),
	btnCancelHov = Color3.fromRGB(100, 80, 55),
	btnAttack   = Color3.fromRGB(120, 40, 40),
	btnAttackHov = Color3.fromRGB(150, 55, 55),
	btnText     = Color3.fromRGB(255, 220, 150),
}

local FONT_TITLE = Enum.Font.FredokaOne
local FONT_VALUE = Enum.Font.GothamBold
local FONT_DESC = Enum.Font.Gotham

local function makeCorner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = parent
	return c
end

local function makeStroke(parent, thickness, color)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness or 2
	s.Color = color or COLORS.panelBorder
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function wireButtonStyle(button, normalColor, hoverColor)
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.BackgroundColor3 = normalColor
	button.MouseEnter:Connect(function() button.BackgroundColor3 = hoverColor end)
	button.MouseLeave:Connect(function() button.BackgroundColor3 = normalColor end)
end

local attackPopupGui = Instance.new("ScreenGui")
attackPopupGui.Name = "CityAttackPopupGui"
attackPopupGui.ResetOnSpawn = false
attackPopupGui.IgnoreGuiInset = true
attackPopupGui.DisplayOrder = 50
attackPopupGui.Enabled = false
attackPopupGui.Parent = playerGui

local popupWindow = Instance.new("Frame")
popupWindow.Name = "PopupWindow"
popupWindow.Size = UDim2.new(0, 420, 0, 220)
popupWindow.Position = UDim2.new(0.5, 0, 0.5, 0)
popupWindow.AnchorPoint = Vector2.new(0.5, 0.5)
popupWindow.BackgroundColor3 = COLORS.windowBg
popupWindow.BackgroundTransparency = 0.05
popupWindow.BorderSizePixel = 0
popupWindow.Parent = attackPopupGui
makeCorner(popupWindow, 12)
makeStroke(popupWindow, 3, COLORS.panelBorder)

local popupHeader = Instance.new("Frame")
popupHeader.Name = "Header"
popupHeader.Size = UDim2.new(1, 0, 0, 44)
popupHeader.BackgroundColor3 = COLORS.headerBg
popupHeader.BorderSizePixel = 0
popupHeader.Parent = popupWindow
makeCorner(popupHeader, 12)

local popupHeaderFix = Instance.new("Frame")
popupHeaderFix.Size = UDim2.new(1, 0, 0, 12)
popupHeaderFix.Position = UDim2.new(0, 0, 1, -12)
popupHeaderFix.BackgroundColor3 = COLORS.headerBg
popupHeaderFix.BorderSizePixel = 0
popupHeaderFix.ZIndex = 0
popupHeaderFix.Parent = popupHeader

local popupTitle = Instance.new("TextLabel")
popupTitle.Size = UDim2.new(1, -16, 1, 0)
popupTitle.Position = UDim2.new(0, 8, 0, 0)
popupTitle.BackgroundTransparency = 1
popupTitle.Font = FONT_TITLE
popupTitle.TextSize = 18
popupTitle.TextColor3 = COLORS.headerText
popupTitle.Text = "⚔️ STADT ANGREIFEN"
popupTitle.Parent = popupHeader

local popupBody = Instance.new("TextLabel")
popupBody.Name = "Body"
popupBody.Size = UDim2.new(1, -32, 0, 90)
popupBody.Position = UDim2.new(0, 16, 0, 56)
popupBody.BackgroundTransparency = 1
popupBody.Font = FONT_DESC
popupBody.TextSize = 15
popupBody.TextColor3 = COLORS.text
popupBody.TextWrapped = true
popupBody.TextYAlignment = Enum.TextYAlignment.Top
popupBody.Text = ""
popupBody.Parent = popupWindow

local popupWarning = Instance.new("TextLabel")
popupWarning.Name = "Warning"
popupWarning.Size = UDim2.new(1, -32, 0, 40)
popupWarning.Position = UDim2.new(0, 16, 0, 130)
popupWarning.BackgroundTransparency = 1
popupWarning.Font = FONT_VALUE
popupWarning.TextSize = 13
popupWarning.TextColor3 = COLORS.warning
popupWarning.TextWrapped = true
popupWarning.Visible = false
popupWarning.Text = ""
popupWarning.Parent = popupWindow

local cancelButton = Instance.new("TextButton")
cancelButton.Name = "CancelButton"
cancelButton.Size = UDim2.new(0.45, -8, 0, 40)
cancelButton.Position = UDim2.new(0, 16, 1, -56)
cancelButton.Font = FONT_VALUE
cancelButton.TextSize = 15
cancelButton.TextColor3 = COLORS.btnText
cancelButton.Text = "Abbrechen"
cancelButton.Parent = popupWindow
makeCorner(cancelButton, 6)
wireButtonStyle(cancelButton, COLORS.btnCancel, COLORS.btnCancelHov)

local attackButton = Instance.new("TextButton")
attackButton.Name = "AttackButton"
attackButton.Size = UDim2.new(0.45, -8, 0, 40)
attackButton.Position = UDim2.new(0.55, -8, 1, -56)
attackButton.Font = FONT_VALUE
attackButton.TextSize = 15
attackButton.TextColor3 = COLORS.btnText
attackButton.Text = "⚔️ Angreifen"
attackButton.Parent = popupWindow
makeCorner(attackButton, 6)
wireButtonStyle(attackButton, COLORS.btnAttack, COLORS.btnAttackHov)

local pendingAttack = nil -- { armyId, targetQ, targetR }

local function closePopup()
	attackPopupGui.Enabled = false
	pendingAttack = nil
end

local function respondAttack(confirmed)
	if not pendingAttack then return end
	local attack = pendingAttack
	closePopup()
	Net.Fire("RequestAttackCity", attack.armyId, attack.targetQ, attack.targetR, confirmed)
end

cancelButton.Activated:Connect(function() respondAttack(false) end)
attackButton.Activated:Connect(function() respondAttack(true) end)

--------------------------------------------------------------------------------
-- CityAttackPopup (Server -> Client): oeffnet das Bestaetigungs-Popup.
--------------------------------------------------------------------------------
Net.On("CityAttackPopup", function(data)
	if not data then return end

	pendingAttack = {
		armyId = data.armyId,
		targetQ = data.targetQ,
		targetR = data.targetR,
	}

	if data.unopposed then
		popupTitle.Text = "🏳️ STADT UNBEWOHNT"
		popupBody.Text = ("Die Stadt %s ist unbewohnt. Einmarschieren?")
			:format(tostring(data.cityName))
		attackButton.Text = "🚩 Einmarschieren"
		popupWarning.Visible = false
	else
		popupTitle.Text = "⚔️ STADT ANGREIFEN"
		popupBody.Text = ("⚔️ Willst du die Stadt %s wirklich angreifen?\n(Verteidiger: %s, %d Buerger)")
			:format(tostring(data.cityName), tostring(data.defenderName), tonumber(data.citizenCount) or 0)
		attackButton.Text = "⚔️ Angreifen"

		if data.isCapital then
			popupWarning.Text = "⚠️ ACHTUNG: Dies ist die Hauptstadt! Bei Eroberung wird der Spieler eliminiert!"
			popupWarning.Visible = true
		else
			popupWarning.Visible = false
		end
	end

	attackPopupGui.Enabled = true
end)

--------------------------------------------------------------------------------
-- CityAttackResult (Server -> Client): kurze Ergebnis-/Blockade-Meldung.
--------------------------------------------------------------------------------
Net.On("CityAttackResult", function(data)
	if not data then return end

	if data.result == "blocked" then
		print("[Movement] " .. tostring(data.reason))
	elseif data.result == "win" then
		print("[Movement] Stadt erobert!" .. (data.unopposed and " (unbewohnt)" or ""))
	elseif data.result == "lose" then
		print("[Movement] Stadt verloren oder Angriff gescheitert.")
	end
end)

print("[MovementController] Bereit. Rechtsklick = Route, nochmal = ausführen.")
