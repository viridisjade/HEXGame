--[[
    UnitSpawnController (LocalScript)
    Ort: StarterPlayer > StarterPlayerScripts > UnitSpawnController

    Zeigt ausschließlich während der Unit-Spawn-Auswahl klickbare
    BillboardGuis über City- und Bastion-Spawnflächen.

    Trage hier die AssetID des Spawn-Buttons ein:
--]]

local SPAWN_BUTTON_IMAGE = "rbxassetid://71024849666002"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local UnitSpawnState = require(ReplicatedStorage:WaitForChild("UnitSpawnState"))
local HexGridConfig = require(ReplicatedStorage:WaitForChild("HexGridConfig"))

local remotes = ReplicatedStorage:WaitForChild("DataRemotes")
local getCitySpawnHexes = remotes:FindFirstChild("GetCitySpawnHexes")
local requestRecruitUnit = remotes:FindFirstChild("RequestRecruitUnit")

local markerFolder = workspace:FindFirstChild("LocalUnitSpawnMarkers")
if not markerFolder then
	markerFolder = Instance.new("Folder")
	markerFolder.Name = "LocalUnitSpawnMarkers"
	markerFolder.Parent = workspace
end

local guiFolder = playerGui:FindFirstChild("UnitSpawnBillboards")
if not guiFolder then
	guiFolder = Instance.new("Folder")
	guiFolder.Name = "UnitSpawnBillboards"
	guiFolder.Parent = playerGui
end

local spawnMarkers = {} -- { part = BasePart, billboard = BillboardGui }
local choosing = false

local function clearMarkers()
	choosing = false
	for _, marker in ipairs(spawnMarkers) do
		if marker.billboard then marker.billboard:Destroy() end
		if marker.part then marker.part:Destroy() end
	end
	spawnMarkers = {}
end

local function createSpawnButton(placement, q, r)
	local worldPos = HexGridConfig.axialToWorld(q, r)

	local anchor = Instance.new("Part")
	anchor.Name = "SpawnMarker_" .. q .. "_" .. r
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Position = Vector3.new(worldPos.X, HexGridConfig.Config.SPAWN_Y + 8, worldPos.Z)
	anchor.Parent = markerFolder

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "SpawnBillboard_" .. q .. "_" .. r
	billboard.Adornee = anchor
	billboard.Size = UDim2.fromOffset(72, 72)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 1.5, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 1000
	billboard.Active = true
	billboard.Enabled = true
	billboard.ZIndexBehavior = Enum.ZIndexBehavior.Global
	billboard.Parent = guiFolder

	local button = Instance.new("ImageButton")
	button.Name = "SpawnButton"
	button.Size = UDim2.fromScale(1, 1)
	button.BackgroundColor3 = Color3.fromRGB(45, 190, 80)
	button.BackgroundTransparency = 0.1
	button.BorderSizePixel = 0
	button.Image = SPAWN_BUTTON_IMAGE
	button.ScaleType = Enum.ScaleType.Fit
	button.Active = true
	button.Selectable = true
	button.Modal = true
	button.AutoButtonColor = true
	button.ZIndex = 10
	button.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button

	local label = Instance.new("TextLabel")
	label.Name = "SpawnText"
	label.Size = UDim2.new(1, 0, 0, 18)
	label.Position = UDim2.new(0, 0, 1, 2)
	label.BackgroundTransparency = 1
	label.Text = "Spawn"
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.TextSize = 14
	label.Active = false
	label.ZIndex = 11
	label.Parent = billboard

	-- Activated funktioniert für Maus, Touch und Gamepad.
	button.Activated:Connect(function()
		if not choosing or not UnitSpawnState.IsPlacing() then return end
		choosing = false

		print("[UnitSpawnController] Spawn gewählt: (" .. q .. ", " .. r .. ")")

		if requestRecruitUnit then
			requestRecruitUnit:FireServer(
				placement.cityId,
				placement.unitType,
				q,
				r
			)
		else
			warn("[UnitSpawnController] RequestRecruitUnit RemoteEvent fehlt")
		end

		UnitSpawnState.Cancel()
	end)

	table.insert(spawnMarkers, {
		part = anchor,
		billboard = billboard,
	})
end

UnitSpawnState.OnChanged:Connect(function(placement)
	clearMarkers()
	if not placement then return end

	if not getCitySpawnHexes then
		warn("[UnitSpawnController] GetCitySpawnHexes RemoteFunction fehlt")
		UnitSpawnState.Cancel()
		return
	end

	local success, hexes = pcall(function()
		return getCitySpawnHexes:InvokeServer(placement.cityId)
	end)

	if not success or type(hexes) ~= "table" then
		warn("[UnitSpawnController] Spawn-Hex-Abfrage fehlgeschlagen: " .. tostring(hexes))
		UnitSpawnState.Cancel()
		return
	end

	if #hexes == 0 then
		warn("[UnitSpawnController] Keine City-/Bastion-Spawnfläche vorhanden")
		UnitSpawnState.Cancel()
		return
	end

	choosing = true
	for _, hex in ipairs(hexes) do
		createSpawnButton(placement, hex.q, hex.r)
	end

	print("[UnitSpawnController] " .. #hexes .. " klickbare Spawn-Buttons erstellt")
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.Escape
		or input.UserInputType == Enum.UserInputType.MouseButton2 then
		if UnitSpawnState.IsPlacing() then
			UnitSpawnState.Cancel()
		end
	end
end)

print("[UnitSpawnController] Bereit")
