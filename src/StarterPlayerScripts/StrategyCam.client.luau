--[[
    StrategyCam (LocalScript)
    Ort: StarterPlayer > StarterPlayerScripts > StrategyCam
    
    Kameramodi:
      - strategyMode = true/false   → nur Kamera/Steuerung
      - provinceVision = true/false → nur Provinz-Hex Overlay
    
    WICHTIG:
      Q schaltet NUR zwischen Spieler- und Strategie-Kamera.
      Q verändert NICHT die ProvinceVision.
      E / ProvinceVisionButton steuert NUR die ProvinceVision.
    
    GUI-Buttons in StarterGui > CameraGui:
      TerrainVisionButton   → Strategie-Kamera + ProvinceVision AUS
      ProvinceVisionButton  → Strategie-Kamera + ProvinceVision AN
      PlayerVisionButton    → Spieler-Kamera (ProvinceVision bleibt intern erhalten,
                             wird aber optisch korrekt angewendet sobald man wieder
                             in den Strategie-Modus geht)
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local HexGridConfig = require(ReplicatedStorage:WaitForChild("HexGridConfig"))

-- Remotes für Province-Daten
local dataRemotes = ReplicatedStorage:WaitForChild("DataRemotes")
local getProvinceRemote = dataRemotes:WaitForChild("GetProvince")

--------------------------------------------------------------------------------
-- KONFIGURATION
--------------------------------------------------------------------------------
local CONFIG = {
	START_X = 100,
	START_Z = 100,
	CAMERA_ANGLE = 55,
	DEFAULT_ZOOM = 80,
	MIN_ZOOM = 20,
	MAX_ZOOM = 200,
	ZOOM_SPEED = 8,
	MOVE_SPEED = 60,
	SHIFT_MULTIPLIER = 2.5,

	-- ProvinceVision: von normalem Boden-Niveau aus anheben
	-- Frühere Logik war -3 -> +5, also +8 Delta
	PROVINCE_RAISE_DELTA = 8,
}

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------
local strategyMode = true           -- true = Strategie-Kamera, false = Spieler-Kamera
local provinceVision = false        -- true = ProvinceHexes angehoben

local currentX = CONFIG.START_X
local currentZ = CONFIG.START_Z
local currentZoom = CONFIG.DEFAULT_ZOOM
local cameraAngleRad = math.rad(CONFIG.CAMERA_ANGLE)

local keysDown = {
	W = false, A = false, S = false, D = false, Shift = false,
}

-- Originale ProvinceHex Y-Positionen lokal cachen
local originalProvinceY = {} -- [BasePart] = originalY
local hoveredProvinceModel = nil
local hoveredProvinceOriginalColors = nil -- [BasePart] = Color3 vor dem Hover

-- Farb-Konfiguration für lokale Province-Hover-Visualisierung
local PROVINCE_HOVER_COLOR = Color3.fromRGB(190, 190, 190)

--------------------------------------------------------------------------------
-- GUI REFERENZEN
--------------------------------------------------------------------------------
local cameraGui = nil
local terrainButton = nil
local provinceButton = nil
local playerButton = nil

task.spawn(function()
	local playerGui = player:WaitForChild("PlayerGui")
	cameraGui = playerGui:WaitForChild("CameraGui", 10)
	if cameraGui then
		terrainButton = cameraGui:FindFirstChild("TerrainVisionButton")
		provinceButton = cameraGui:FindFirstChild("ProvinceVisionButton")
		playerButton = cameraGui:FindFirstChild("PlayerVisionButton")
	end
end)

--------------------------------------------------------------------------------
-- CHARAKTER SICHTBARKEIT / STEUERUNG
--------------------------------------------------------------------------------
local function setCharacterVisible(visible)
	local character = player.Character
	if not character then return end

	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Transparency = visible and 0 or 1
		elseif part:IsA("Decal") or part:IsA("Texture") then
			part.Transparency = visible and 0 or 1
		end
	end

	local humanoid = character:FindFirstChildWhichIsA("Humanoid")
	if humanoid then
		humanoid.NameDisplayDistance = visible and 100 or 0
		humanoid.HealthDisplayDistance = visible and 100 or 0
	end
end

local function setControlsEnabled(enabled)
	local playerModule = player:FindFirstChild("PlayerScripts")
	if playerModule then
		local controlModule = playerModule:FindFirstChild("PlayerModule")
		if controlModule then
			pcall(function()
				local module = require(controlModule)
				if enabled then
					module:GetControls():Enable()
				else
					module:GetControls():Disable()
				end
			end)
		end
	end
end

--------------------------------------------------------------------------------
-- PROVINCE HEXES
--------------------------------------------------------------------------------
local function getProvinceVisualParts()
	local parts = {}
	local hexMap = workspace:FindFirstChild("HexMap")
	if not hexMap then return parts end

	local provinceVisuals = hexMap:FindFirstChild("ProvinceVisuals")
	if not provinceVisuals then return parts end

	for _, child in ipairs(provinceVisuals:GetDescendants()) do
		if child:IsA("BasePart") then
			table.insert(parts, child)
		end
	end

	return parts
end

local function cacheOriginalProvincePositions()
	for _, part in ipairs(getProvinceVisualParts()) do
		if originalProvinceY[part] == nil then
			originalProvinceY[part] = part.Position.Y
		end
	end
end

local function applyProvinceVision()
	-- Originalpositionen cachen
	cacheOriginalProvincePositions()

	for _, part in ipairs(getProvinceVisualParts()) do
		local originalY = originalProvinceY[part]
		if originalY ~= nil then
			local targetY = provinceVision and (originalY + CONFIG.PROVINCE_RAISE_DELTA) or originalY
			part.Position = Vector3.new(part.Position.X, targetY, part.Position.Z)
		end
	end
end

local function setProvinceModelColor(model, color)
	if not model then return end
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Color = color
		end
	end
end

local function cacheProvinceModelColors(model)
	local colors = {}
	if not model then return colors end

	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			colors[part] = part.Color
		end
	end

	return colors
end

local function getProvinceIdFromModel(model)
	if not model then return nil end
	local idStr = model.Name:match("^Province_(%d+)$")
	return idStr and tonumber(idStr) or nil
end

local function restoreProvinceModelColorFromData(model, fallbackColors)
	if not model then return end

	local provinceId = getProvinceIdFromModel(model)
	if provinceId then
		local success, province = pcall(function()
			return getProvinceRemote:InvokeServer(provinceId)
		end)

		if success and province and province.color then
			setProvinceModelColor(model, province.color)
			return
		end
	end

	-- Fallback: zuletzt bekannte Farben wiederherstellen
	if fallbackColors then
		for part, color in pairs(fallbackColors) do
			if part and part.Parent then
				part.Color = color
			end
		end
	end
end

local function clearProvinceHover()
	if hoveredProvinceModel then
		restoreProvinceModelColorFromData(hoveredProvinceModel, hoveredProvinceOriginalColors)
		hoveredProvinceModel = nil
		hoveredProvinceOriginalColors = nil
	end
end

local function getProvinceModelFromHex(q, r)
	local hexMap = workspace:FindFirstChild("HexMap")
	if not hexMap then return nil end

	local provinceVisuals = hexMap:FindFirstChild("ProvinceVisuals")
	if not provinceVisuals then return nil end

	local hexName = "Hex_" .. q .. "_" .. r

	for _, provinceModel in ipairs(provinceVisuals:GetChildren()) do
		if provinceModel:IsA("Model") and provinceModel.Name:match("^Province_%d+$") then
			local match = provinceModel:FindFirstChild(hexName, true)
			if match then
				return provinceModel
			end
		end
	end

	return nil
end

local function updateProvinceHover()
	if not provinceVision or not strategyMode then
		clearProvinceHover()
		return
	end

	local mouse = player:GetMouse()
	if not mouse.Target then
		clearProvinceHover()
		return
	end

	local q, r = HexGridConfig.worldToAxial(mouse.Hit.Position)
	local provinceModel = getProvinceModelFromHex(q, r)

	if provinceModel == hoveredProvinceModel then
		return
	end

	clearProvinceHover()

	if provinceModel then
		hoveredProvinceModel = provinceModel
		hoveredProvinceOriginalColors = cacheProvinceModelColors(provinceModel)
		setProvinceModelColor(hoveredProvinceModel, PROVINCE_HOVER_COLOR)
	end
end

--------------------------------------------------------------------------------
-- KAMERA
--------------------------------------------------------------------------------
local function updateStrategyCamera()
	local lookAtPoint = Vector3.new(currentX, 0, currentZ)
	local heightOffset = currentZoom * math.sin(cameraAngleRad)
	local sideOffset = currentZoom * math.cos(cameraAngleRad)

	local cameraPos = Vector3.new(
		currentX - sideOffset,
		heightOffset,
		currentZ
	)

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.new(cameraPos, lookAtPoint)
end

--------------------------------------------------------------------------------
-- BUTTON-STATES
--------------------------------------------------------------------------------
local function updateButtonStates()
	if not cameraGui then return end

	local function setBtn(btn, active)
		if not btn then return end
		btn.ImageTransparency = active and 0 or 0.5
	end

	setBtn(terrainButton, strategyMode and not provinceVision)
	setBtn(provinceButton, strategyMode and provinceVision)
	setBtn(playerButton, not strategyMode)
end

--------------------------------------------------------------------------------
-- MODI
--------------------------------------------------------------------------------
local function enterStrategyMode()
	strategyMode = true

	setCharacterVisible(false)
	setControlsEnabled(false)
	camera.CameraType = Enum.CameraType.Scriptable

	-- ProvinceVision bleibt wie sie ist, nur anwenden
	applyProvinceVision()
	updateStrategyCamera()
	updateButtonStates()
	print("[StrategyCam] Strategie-Modus aktiviert")
end

local function enterPlayerMode()
	strategyMode = false

	setCharacterVisible(true)
	setControlsEnabled(true)
	camera.CameraType = Enum.CameraType.Custom

	-- Hover-Effekt entfernen, ProvinceVision-Zustand aber NICHT ändern
	clearProvinceHover()

	updateButtonStates()
	print("[StrategyCam] Spieler-Modus aktiviert")
end

local function setTerrainVision()
	provinceVision = false
	clearProvinceHover()
	if strategyMode then
		applyProvinceVision()
		updateStrategyCamera()
	end
	updateButtonStates()
	print("[StrategyCam] TerrainVision aktiviert")
end

local function setProvinceVision()
	provinceVision = true
	if not strategyMode then
		enterStrategyMode()
	else
		applyProvinceVision()
		updateStrategyCamera()
		updateButtonStates()
	end
	updateProvinceHover()
	print("[StrategyCam] ProvinceVision aktiviert")
end

--------------------------------------------------------------------------------
-- GLOBALS
--------------------------------------------------------------------------------
_G.GetViewMode = function()
	if not strategyMode then return "player" end
	return provinceVision and "province" or "terrain"
end

_G.IsStrategyMode = function()
	return strategyMode
end

--------------------------------------------------------------------------------
-- INPUT
--------------------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.KeyCode == Enum.KeyCode.W then
		keysDown.W = true
	elseif input.KeyCode == Enum.KeyCode.A then
		keysDown.A = true
	elseif input.KeyCode == Enum.KeyCode.S then
		keysDown.S = true
	elseif input.KeyCode == Enum.KeyCode.D then
		keysDown.D = true
	elseif input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		keysDown.Shift = true
	elseif input.KeyCode == Enum.KeyCode.Q then
		-- Q betrifft NUR Kamera/Steuerung, nicht ProvinceVision
		if strategyMode then
			enterPlayerMode()
		else
			enterStrategyMode()
		end
	elseif input.KeyCode == Enum.KeyCode.E then
		-- E toggelt NUR ProvinceVision
		if provinceVision then
			setTerrainVision()
		else
			setProvinceVision()
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.W then keysDown.W = false
	elseif input.KeyCode == Enum.KeyCode.A then keysDown.A = false
	elseif input.KeyCode == Enum.KeyCode.S then keysDown.S = false
	elseif input.KeyCode == Enum.KeyCode.D then keysDown.D = false
	elseif input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then keysDown.Shift = false
	end
end)

--------------------------------------------------------------------------------
-- ZOOM
--------------------------------------------------------------------------------
UserInputService.InputChanged:Connect(function(input, gameProcessed)
	if not strategyMode then return end
	if gameProcessed then return end

	if input.UserInputType == Enum.UserInputType.MouseWheel then
		local scrollDir = input.Position.Z
		currentZoom = math.clamp(
			currentZoom - (scrollDir * CONFIG.ZOOM_SPEED),
			CONFIG.MIN_ZOOM,
			CONFIG.MAX_ZOOM
		)
	end
end)

--------------------------------------------------------------------------------
-- KAMERA-UPDATE LOOP
--------------------------------------------------------------------------------
RunService.RenderStepped:Connect(function(dt)
	if not strategyMode then return end

	local speed = CONFIG.MOVE_SPEED * dt
	if keysDown.Shift then speed = speed * CONFIG.SHIFT_MULTIPLIER end

	local zoomFactor = currentZoom / CONFIG.DEFAULT_ZOOM
	speed = speed * zoomFactor

	if keysDown.W then currentX = currentX + speed end
	if keysDown.S then currentX = currentX - speed end
	if keysDown.A then currentZ = currentZ - speed end
	if keysDown.D then currentZ = currentZ + speed end

	updateStrategyCamera()
	updateProvinceHover()
end)

--------------------------------------------------------------------------------
-- GUI BUTTONS
--------------------------------------------------------------------------------
task.spawn(function()
	task.wait(2)

	if terrainButton then
		terrainButton.MouseButton1Click:Connect(function()
			if not strategyMode then
				enterStrategyMode()
			end
			setTerrainVision()
		end)
	end

	if provinceButton then
		provinceButton.MouseButton1Click:Connect(function()
			setProvinceVision()
		end)
	end

	if playerButton then
		playerButton.MouseButton1Click:Connect(function()
			enterPlayerMode()
		end)
	end

	updateButtonStates()
end)

--------------------------------------------------------------------------------
-- CHARAKTER-RESPAWN
--------------------------------------------------------------------------------
player.CharacterAdded:Connect(function()
	if strategyMode then
		task.wait(0.5)
		setCharacterVisible(false)
	end
end)

--------------------------------------------------------------------------------
-- START
--------------------------------------------------------------------------------
task.wait(1)
enterStrategyMode()
setTerrainVision()
