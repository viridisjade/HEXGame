--[[
    SoilSpawner (ModuleScript)
    Ort: ServerScriptService > SoilSpawner
    
    Spawnt Soil-Modelle OBEN AUF den Hex-Tiles.
    
    Ermittelt die tatsächliche Oberkante jedes Hex-Models in der Workspace
    und platziert das Soil direkt darauf. Funktioniert mit unterschiedlich
    hohen Ebenen-Models.
    
    Erwartete Struktur in ServerStorage:
      ServerStorage
        └── SoilTemplates
            ├── DeepWater       (Model mit PrimaryPart)
            ├── CoastWater      (Model mit PrimaryPart)
            ├── Grassland       (Model mit PrimaryPart)
            ├── DryGrass        (Model mit PrimaryPart)
            ├── Forest          (Model mit PrimaryPart)
            ├── Rocks           (Model mit PrimaryPart)
            └── Mountain        (Model mit PrimaryPart)
    
    FEHLT das Mountain-Template, erzeugt der Spawner automatisch einen
    einfachen Fallback-Stein (kein Fehler, kein Warn-Spam). Sobald du ein
    eigenes Modell unter SoilTemplates > Mountain ablegst, wird dieses
    automatisch bevorzugt.
--]]

local SoilSpawner = {}

local ServerStorage = game:GetService("ServerStorage")
local HexUtils = require(script.Parent:WaitForChild("HexUtils"))

-- Referenz auf die Soil-Templates
local soilTemplatesFolder = ServerStorage:WaitForChild("SoilTemplates")

--------------------------------------------------------------------------------
-- Workspace Folder erstellen / abrufen
--------------------------------------------------------------------------------
local soilFolder = nil

function SoilSpawner.getSoilFolder()
	if soilFolder then return soilFolder end

	local hexMap = workspace:FindFirstChild("HexMap")
	if not hexMap then
		hexMap = Instance.new("Folder")
		hexMap.Name = "HexMap"
		hexMap.Parent = workspace
	end

	soilFolder = hexMap:FindFirstChild("Soils")
	if not soilFolder then
		soilFolder = Instance.new("Folder")
		soilFolder.Name = "Soils"
		soilFolder.Parent = hexMap
	end

	return soilFolder
end

function SoilSpawner.getSoilTypeFolder(soilType)
	local parent = SoilSpawner.getSoilFolder()

	local folder = parent:FindFirstChild(soilType)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = soilType
		folder.Parent = parent
	end

	return folder
end

--------------------------------------------------------------------------------
-- getTemplate(soilType) -> Model
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- MOUNTAIN-FALLBACK
-- Bergspitzen (Ebene4) bekommen den Soil-Typ "Mountain". Fehlt das Template
-- in ServerStorage, erzeugen wir einen einfachen Stein-Marker statt einen
-- Fehler zu werfen. Sobald ein richtiges Template existiert, wird es
-- automatisch bevorzugt (FindFirstChild läuft immer zuerst).
--------------------------------------------------------------------------------
local mountainFallbackTemplate = nil
local mountainFallbackHintShown = false

local function getMountainFallbackTemplate()
	-- Gecachtes Fallback-Template wiederverwenden
	if mountainFallbackTemplate and mountainFallbackTemplate.Parent then
		return mountainFallbackTemplate
	end

	local model = Instance.new("Model")
	model.Name = "Mountain_Fallback"

	local rock = Instance.new("Part")
	rock.Name = "Rock"
	rock.Size = Vector3.new(4, 3, 4)
	rock.Color = Color3.fromRGB(125, 125, 130)
	rock.Material = Enum.Material.Slate
	rock.Anchored = true
	rock.CanCollide = false
	rock.CanQuery = false      -- blockiert keine Raycasts (Klicks gehen zum Hex durch)
	rock.TopSurface = Enum.SurfaceType.Smooth
	rock.BottomSurface = Enum.SurfaceType.Smooth
	rock.Parent = model

	model.PrimaryPart = rock
	-- Unter dem Script parken, damit es nicht im Workspace auftaucht
	model.Parent = script

	mountainFallbackTemplate = model
	return model
end

--------------------------------------------------------------------------------
-- getTemplate(soilType) -> Model
--------------------------------------------------------------------------------
function SoilSpawner.getTemplate(soilType)
	-- Echtes Template immer zuerst suchen
	local template = soilTemplatesFolder:FindFirstChild(soilType)

	if template then
		return template
	end

	-- Bergspitzen: Fallback-Stein statt Fehler
	if soilType == "Mountain" then
		if not mountainFallbackHintShown then
			mountainFallbackHintShown = true
			print("[SoilSpawner] Mountain-Template fehlt in ServerStorage > SoilTemplates - "
				.. "nutze Fallback-Steine. Eigenes Modell ablegen, um sie zu ersetzen.")
		end
		return getMountainFallbackTemplate()
	end

	warn("[SoilSpawner] Template nicht gefunden: " .. tostring(soilType))
	return nil
end

--------------------------------------------------------------------------------
-- findHexModel(q, r) -> Model/Part or nil
-- Sucht das gespawnte Hex-Model in Workspace > HexMap anhand des Namens.
-- Hex-Models heißen "Hex_q_r", z.B. "Hex_5_12"
--------------------------------------------------------------------------------
function SoilSpawner.findHexModel(q, r)
	local hexMapFolder = workspace:FindFirstChild("HexMap")
	if not hexMapFolder then return nil end

	local hexName = "Hex_" .. q .. "_" .. r

	-- Suche in allen Terrain-Unterordnern
	for _, subFolder in ipairs(hexMapFolder:GetChildren()) do
		if subFolder:IsA("Folder") and subFolder.Name ~= "Soils" then
			local hex = subFolder:FindFirstChild(hexName)
			if hex then
				return hex
			end
		end
	end

	return nil
end

--------------------------------------------------------------------------------
-- getHexTopY(hexModel) -> number
-- Ermittelt die Y-Position der OBERKANTE eines Hex-Models.
-- Funktioniert mit Models (PrimaryPart/BoundingBox) und einzelnen Parts.
--------------------------------------------------------------------------------
function SoilSpawner.getHexTopY(hexModel)
	if hexModel:IsA("Model") then
		-- Methode 1: Über PrimaryPart
		if hexModel.PrimaryPart then
			local pos = hexModel.PrimaryPart.Position
			local size = hexModel.PrimaryPart.Size
			return pos.Y + size.Y / 2
		end

		-- Methode 2: Über GetBoundingBox
		local success, cf, size = pcall(function()
			return hexModel:GetBoundingBox()
		end)
		if success then
			return cf.Position.Y + size.Y / 2
		end

		-- Methode 3: Fallback über alle Parts
		local maxY = -math.huge
		for _, part in ipairs(hexModel:GetDescendants()) do
			if part:IsA("BasePart") then
				local topY = part.Position.Y + part.Size.Y / 2
				if topY > maxY then
					maxY = topY
				end
			end
		end
		if maxY > -math.huge then
			return maxY
		end

	elseif hexModel:IsA("BasePart") then
		return hexModel.Position.Y + hexModel.Size.Y / 2
	end

	-- Absoluter Fallback
	warn("[SoilSpawner] Konnte Oberkante nicht ermitteln, nutze Fallback")
	return HexUtils.Config.SPAWN_Y + 2
end

--------------------------------------------------------------------------------
-- spawnSoil(q, r, soilType) -> Model/Part or nil
-- Spawnt ein Soil-Model auf dem Hex an Position (q, r).
-- Ermittelt die echte Oberkante des Hex-Models für die Y-Position.
--------------------------------------------------------------------------------
function SoilSpawner.spawnSoil(q, r, soilType)
	-- Template holen
	local template = SoilSpawner.getTemplate(soilType)
	if not template then return nil end

	-- Hex-Model in Workspace finden
	local hexModel = SoilSpawner.findHexModel(q, r)

	-- Oberkante des Hex ermitteln
	local hexTopY
	if hexModel then
		hexTopY = SoilSpawner.getHexTopY(hexModel)
	else
		-- Fallback wenn Hex-Model nicht gefunden
		hexTopY = HexUtils.Config.SPAWN_Y + 2
	end

	-- Template klonen
	local soil = template:Clone()
	soil.Name = "Soil_" .. q .. "_" .. r .. "_" .. soilType

	-- Welt-Position (X, Z vom Hex-Grid)
	local worldPos = HexUtils.axialToWorld(q, r)

	-- Position setzen: UNTERKANTE des Soil-Models exakt auf Hex-Oberkante
	if soil:IsA("Model") then
		-- BoundingBox + Pivot nutzen damit auch gedrehte/komplexe Models korrekt sitzen
		local bboxCf, bboxSize = soil:GetBoundingBox()
		local pivot = soil:GetPivot()

		-- Abstand vom Pivot zur Unterkante des Models
		local pivotToBottom = pivot.Position.Y - (bboxCf.Position.Y - bboxSize.Y / 2)
		local targetPivotY = hexTopY + pivotToBottom

		-- Original-Rotation beibehalten
		local rotation = pivot - pivot.Position
		local targetCFrame = CFrame.new(worldPos.X, targetPivotY, worldPos.Z) * rotation

		soil:PivotTo(targetCFrame)
	elseif soil:IsA("BasePart") then
		local soilHalfY = soil.Size.Y / 2
		local finalPos = Vector3.new(worldPos.X, hexTopY + soilHalfY, worldPos.Z)
		soil.Position = finalPos
	end

	-- In den richtigen Folder packen
	local folder = SoilSpawner.getSoilTypeFolder(soilType)
	soil.Parent = folder

	return soil
end

--------------------------------------------------------------------------------
-- spawnAllSoils(hexMap, soilMap) -> number
--------------------------------------------------------------------------------
function SoilSpawner.spawnAllSoils(hexMap, soilMap)
	print("[SoilSpawner] Starte Soil-Spawning...")

	local count = 0
	local errors = 0
	local startTime = tick()

	for key, soilType in pairs(soilMap) do
		local hexData = hexMap[key]
		if hexData then
			local success = SoilSpawner.spawnSoil(hexData.q, hexData.r, soilType)

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
	print("[SoilSpawner] === Spawning abgeschlossen ===")
	print("[SoilSpawner] Gespawnt: " .. count .. " Soils")
	if errors > 0 then
		warn("[SoilSpawner] Fehler: " .. errors .. " Soils konnten nicht gespawnt werden")
	end
	print("[SoilSpawner] Dauer: " .. elapsed .. " Sekunden")

	return count
end

--------------------------------------------------------------------------------
-- clearSoils()
--------------------------------------------------------------------------------
function SoilSpawner.clearSoils()
	local hexMap = workspace:FindFirstChild("HexMap")
	if hexMap then
		local soils = hexMap:FindFirstChild("Soils")
		if soils then
			soils:Destroy()
			soilFolder = nil
			print("[SoilSpawner] Alle Soils gelöscht.")
		end
	end
end

return SoilSpawner