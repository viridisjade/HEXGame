--[[
    ProvinceVisualizer (ModuleScript)
    Ort: ServerScriptService > ProvinceVisualizer
    
    Visualisiert Provinzen durch farbige Boden-Hexes unter den Terrain-Hexes.
    Alle Hexes einer Provinz werden in ein Model pro Provinz gruppiert.
    
    Erwartete Struktur in ServerStorage:
      ServerStorage
        └── ProvinceHex    (Model oder Part) - Template für den Boden
    
    Das ProvinceHex wird unter jedes Terrain-Hex platziert und
    entsprechend der Provinz eingefärbt.
    Wenn das Template bereits transparent ist, bleibt diese Transparenz erhalten.
    
    Ergebnis in Workspace:
      HexMap > ProvinceVisuals
        ├── Province_1 (Model mit allen Hexes der Provinz 1)
        ├── Province_2 (Model mit allen Hexes der Provinz 2)
        └── ...
--]]

local ProvinceVisualizer = {}

local ServerStorage = game:GetService("ServerStorage")
local HexUtils = require(script.Parent:WaitForChild("HexUtils"))
local ProvinceData = require(script.Parent:WaitForChild("ProvinceData"))

--------------------------------------------------------------------------------
-- KONFIGURATION
--------------------------------------------------------------------------------
ProvinceVisualizer.Config = {
	-- Wie weit unter dem Terrain-Hex der Boden spawnt
	Y_OFFSET = 0,

	-- Transparenz für den Fallback-Part (nur wenn KEIN Template genutzt wird)
	TRANSPARENCY = 0,

	-- Wenn ein Template geklont wird, bleibt dessen eigene Transparenz erhalten
	PRESERVE_TEMPLATE_TRANSPARENCY = true,

	-- Ob ein Template aus ServerStorage verwendet wird
	USE_TEMPLATE = true,
	TEMPLATE_NAME = "ProvinceHex",

	-- Fallback Part-Größe wenn kein Template
	PART_SIZE = Vector3.new(10, 1, 8.66),
}

--------------------------------------------------------------------------------
-- Provinz-Farben (Fallback, wird von ProvinceData überschrieben)
--------------------------------------------------------------------------------
local provinceColors = {}

--------------------------------------------------------------------------------
-- Workspace Folder
--------------------------------------------------------------------------------
local provinceFolder = nil
local provinceModels = {}  -- Model pro Provinz

function ProvinceVisualizer.getProvinceFolder()
	if provinceFolder then return provinceFolder end

	local hexMap = workspace:FindFirstChild("HexMap")
	if not hexMap then
		hexMap = Instance.new("Folder")
		hexMap.Name = "HexMap"
		hexMap.Parent = workspace
	end

	provinceFolder = hexMap:FindFirstChild("ProvinceVisuals")
	if not provinceFolder then
		provinceFolder = Instance.new("Folder")
		provinceFolder.Name = "ProvinceVisuals"
		provinceFolder.Parent = hexMap
	end

	return provinceFolder
end

--------------------------------------------------------------------------------
-- getProvinceModel(provinceNumber) -> Model
-- Gibt das Model für eine Provinz zurück (erstellt es wenn nötig)
--------------------------------------------------------------------------------
function ProvinceVisualizer.getProvinceModel(provinceNumber)
	if provinceModels[provinceNumber] then
		return provinceModels[provinceNumber]
	end

	local folder = ProvinceVisualizer.getProvinceFolder()
	local model = Instance.new("Model")
	model.Name = "Province_" .. provinceNumber
	model.Parent = folder

	provinceModels[provinceNumber] = model
	return model
end

--------------------------------------------------------------------------------
-- generateProvinceColors(provinceCount)
--------------------------------------------------------------------------------
function ProvinceVisualizer.generateProvinceColors(provinceCount)
	provinceColors = {}

	local goldenAngle = 137.508

	for i = 1, provinceCount do
		local hue = ((i - 1) * goldenAngle) % 360 / 360
		local saturation = 0.6 + math.random() * 0.3
		local value = 0.7 + math.random() * 0.25
		provinceColors[i] = Color3.fromHSV(hue, saturation, value)
	end

	return provinceColors
end

--------------------------------------------------------------------------------
-- getProvinceColor(provinceNumber) -> Color3
--------------------------------------------------------------------------------
function ProvinceVisualizer.getProvinceColor(provinceNumber)
	local province = ProvinceData.GetProvince(provinceNumber)
	if province and province.color then
		return province.color
	end

	if provinceColors[provinceNumber] then
		return provinceColors[provinceNumber]
	end

	return Color3.fromRGB(128, 128, 128)
end

--------------------------------------------------------------------------------
-- getTemplate() -> BasePart or Model or nil
--------------------------------------------------------------------------------
function ProvinceVisualizer.getTemplate()
	local config = ProvinceVisualizer.Config

	if config.USE_TEMPLATE then
		local template = ServerStorage:FindFirstChild(config.TEMPLATE_NAME)
		if template then
			return template
		else
			warn("[ProvinceVisualizer] Template '" .. config.TEMPLATE_NAME .. "' nicht gefunden!")
		end
	end

	return nil
end

--------------------------------------------------------------------------------
-- createProvincePart(color) -> BasePart
--------------------------------------------------------------------------------
function ProvinceVisualizer.createProvincePart(color)
	local config = ProvinceVisualizer.Config

	local part = Instance.new("Part")
	part.Size = config.PART_SIZE
	part.Color = color
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = config.TRANSPARENCY
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth

	return part
end

--------------------------------------------------------------------------------
-- spawnProvinceHex(q, r, provinceNumber) -> Instance
-- Spawnt ein Provinz-Hex unter dem Terrain-Hex.
-- Wird direkt in das Province-Model der jeweiligen Provinz gepackt.
--------------------------------------------------------------------------------
function ProvinceVisualizer.spawnProvinceHex(q, r, provinceNumber)
	local config = ProvinceVisualizer.Config
	local color = ProvinceVisualizer.getProvinceColor(provinceNumber)

	-- Template oder Fallback Part
	local template = ProvinceVisualizer.getTemplate()
	local provinceHex

	if template then
		provinceHex = template:Clone()
	else
		provinceHex = ProvinceVisualizer.createProvincePart(color)
	end

	-- Namen setzen
	provinceHex.Name = "Hex_" .. q .. "_" .. r

	-- Position berechnen
	local worldPos = HexUtils.axialToWorld(q, r)
	local yPos = worldPos.Y + config.Y_OFFSET

	-- Position und Farbe setzen
	if provinceHex:IsA("Model") then
		local modelHeight = 0
		if provinceHex.PrimaryPart then
			modelHeight = provinceHex.PrimaryPart.Size.Y
		else
			local _, size = provinceHex:GetBoundingBox()
			modelHeight = size.Y
		end

		local centerY = yPos - modelHeight / 2

		-- Original-Rotation beibehalten
		local originalCFrame = provinceHex:GetPivot()
		local originalRotation = originalCFrame - originalCFrame.Position
		local targetCFrame = CFrame.new(worldPos.X, centerY, worldPos.Z) * originalRotation

		provinceHex:PivotTo(targetCFrame)

		-- Farbe anwenden, Transparenz beibehalten
		for _, part in ipairs(provinceHex:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Color = color
				if not config.PRESERVE_TEMPLATE_TRANSPARENCY then
					part.Transparency = config.TRANSPARENCY
				end
				part.CanCollide = false
			end
		end
	elseif provinceHex:IsA("BasePart") then
		local halfY = provinceHex.Size.Y / 2
		provinceHex.Position = Vector3.new(worldPos.X, yPos - halfY, worldPos.Z)
		provinceHex.Color = color
		if not template or not config.PRESERVE_TEMPLATE_TRANSPARENCY then
			provinceHex.Transparency = config.TRANSPARENCY
		end
		provinceHex.CanCollide = false
	end

	-- In das Province-Model packen (gruppiert nach Provinz)
	local provinceModel = ProvinceVisualizer.getProvinceModel(provinceNumber)
	provinceHex.Parent = provinceModel

	return provinceHex
end

--------------------------------------------------------------------------------
-- visualizeProvinces(hexMap, provinceMap, provinceCount)
-- Hauptfunktion: Spawnt alle Provinz-Hexes, gruppiert in Models pro Provinz
--------------------------------------------------------------------------------
function ProvinceVisualizer.visualizeProvinces(hexMap, provinceMap, provinceCount)
	print("[ProvinceVisualizer] Starte Provinz-Visualisierung...")

	-- Farben generieren (Fallback)
	ProvinceVisualizer.generateProvinceColors(provinceCount)

	local count = 0
	local errors = 0
	local startTime = tick()

	for key, provinceNumber in pairs(provinceMap) do
		local hexData = hexMap[key]
		if hexData and provinceNumber and provinceNumber > 0 then
			local success = ProvinceVisualizer.spawnProvinceHex(hexData.q, hexData.r, provinceNumber)

			if success then
				count = count + 1
			else
				errors = errors + 1
			end

			if count % 100 == 0 then
				task.wait()
			end
		end
	end

	local elapsed = math.floor((tick() - startTime) * 100) / 100
	print("[ProvinceVisualizer] === Visualisierung abgeschlossen ===")
	print("[ProvinceVisualizer] Gespawnt: " .. count .. " Provinz-Hexes")
	print("[ProvinceVisualizer] Gruppiert in " .. provinceCount .. " Province-Models")
	if errors > 0 then
		warn("[ProvinceVisualizer] Fehler: " .. errors)
	end
	print("[ProvinceVisualizer] Dauer: " .. elapsed .. " Sekunden")

	return count
end

--------------------------------------------------------------------------------
-- clearVisualization()
--------------------------------------------------------------------------------
function ProvinceVisualizer.clearVisualization()
	local hexMap = workspace:FindFirstChild("HexMap")
	if hexMap then
		local visuals = hexMap:FindFirstChild("ProvinceVisuals")
		if visuals then
			visuals:Destroy()
			provinceFolder = nil
			print("[ProvinceVisualizer] Visualisierung gelöscht.")
		end
	end
	provinceModels = {}
end

--------------------------------------------------------------------------------
-- getProvinceColors() -> table
--------------------------------------------------------------------------------
function ProvinceVisualizer.getProvinceColors()
	return provinceColors
end

return ProvinceVisualizer
