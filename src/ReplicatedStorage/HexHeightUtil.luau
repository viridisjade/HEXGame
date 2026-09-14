--[[
    HexHeightUtil (ModuleScript)
    Ort: ReplicatedStorage > HexHeightUtil
    
    EINE Funktion für die Oberkante eines Hexes.
    
    WARUM:
      Vorher existierten 6 Kopien desselben Algorithmus (ArmySpawner,
      ArmyModelMover, CitySystem, ConstructionSystem, BuildingSystem,
      CityPlacementController) - mit subtilen Unterschieden.
    
    REGEL: Gebäude und Armeen spawnen AUF DEM SOIL.
      Gebäude und Armeen dürfen sich gerne überlappen - beide stehen
      auf derselben Boden-Höhe. Kein Objekt wird auf ein anderes drauf
      gesetzt.
    
    getTopY(q, r) prüft zwei Ebenen und nimmt die HÖCHSTE Kante:
      1. Soil-Modell     (Soil_q_r_*)  <- der Boden-Deckel
      2. Hex-Modell      (Hex_q_r)     <- Fallback wenn kein Soil existiert
      3. SPAWN_Y + 2     wenn nichts gefunden
    
    getSpawnHeight(q, r) ist die Funktion für Unit-/Gebäude-Spawns:
      Sie liest AUSSCHLIESSLICH das TERRAIN-Model (Hex_q_r unter den
      Ebene-Ordnern), NICHT das Soil. Soil ist nur eine dünne Deko-Schicht
      oben auf dem Terrain und für die Spawn-Höhe irrelevant.
    
    Liegt in ReplicatedStorage, weil es Server UND Client brauchen
    (CityPlacementController ist ein LocalScript).
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HexGridConfig = require(ReplicatedStorage:WaitForChild("HexGridConfig"))

local HexHeightUtil = {}

--------------------------------------------------------------------------------
-- topOf(object) -> number
-- Oberkante eines Models oder Parts (-unendlich wenn unbrauchbar)
--------------------------------------------------------------------------------
function HexHeightUtil.topOf(object)
	if not object then return -math.huge end
	if object:IsA("Model") then
		if object.PrimaryPart then
			return object.PrimaryPart.Position.Y + object.PrimaryPart.Size.Y / 2
		end
		local cf, size = object:GetBoundingBox()
		return cf.Position.Y + size.Y / 2
	elseif object:IsA("BasePart") then
		return object.Position.Y + object.Size.Y / 2
	end
	return -math.huge
end

--------------------------------------------------------------------------------
-- getTopY(q, r) -> number
-- Die höchste Oberkante auf diesem Hex (Soil, Gebäude oder Hex-Modell).
--------------------------------------------------------------------------------
function HexHeightUtil.getTopY(q, r)
	local hexMap = workspace:FindFirstChild("HexMap")
	if not hexMap then
		return HexGridConfig.Config.SPAWN_Y + 2
	end

	local topY = HexGridConfig.Config.SPAWN_Y + 2

	-- 1) Soil-Modell (der Boden-Deckel auf dem ALLES steht)
	local soils = hexMap:FindFirstChild("Soils")
	if soils then
		local prefix = "Soil_" .. q .. "_" .. r .. "_"
		for _, folder in ipairs(soils:GetChildren()) do
			for _, object in ipairs(folder:GetChildren()) do
				if object.Name:sub(1, #prefix) == prefix then
					topY = math.max(topY, HexHeightUtil.topOf(object))
				end
			end
		end
	end

	-- 2) Hex-Modell als Fallback (falls kein Soil existiert)
	local hexName = "Hex_" .. q .. "_" .. r
	for _, folder in ipairs(hexMap:GetChildren()) do
		if folder:IsA("Folder")
			and folder.Name ~= "Soils"
			and folder.Name ~= "ArmyModels"
			and folder.Name ~= "ProvinceVisuals"
			and folder.Name ~= "Buildings" then
			local hex = folder:FindFirstChild(hexName)
			if hex then
				topY = math.max(topY, HexHeightUtil.topOf(hex))
			end
		end
	end

	return topY
end

--------------------------------------------------------------------------------
-- getSpawnHeight(q, r) -> number
-- Spawn-Höhe für Units und Gebäude: Oberkante des TERRAIN-Models (Ebene1,
-- Ebene2, Ebene3_Gebirge, Ebene4_Bergspitze, ...) + fester Sicherheitsabstand.
--
-- WICHTIG: Hier zählt NUR das Terrain, NICHT das Soil!
--   - Terrain (Hex_q_r unter Ebene1/Ebene2/...) ist die eigentliche Ebene
--     mit ihrer Stufen-Höhe.
--   - Soil (Soil_q_r_* unter Soils/...) ist nur eine dünne Deko-Schicht
--     OBEN AUF dem Terrain. Seine Y-Position ist bereits die Terrain-
--     Oberkante - würde man Soil + 0.5 nehmen, würden Units je nach
--     Soil-Dicke leicht über dem Boden schweben.
--
-- Deshalb sucht diese Funktion ausschließlich in den Terrain-Ordnern und
-- überspringt Soils/ProvinceVisuals/ArmyModels/Buildings bewusst.
--------------------------------------------------------------------------------
HexHeightUtil.SPAWN_HEIGHT_OFFSET = 0.5

function HexHeightUtil.getSpawnHeight(q, r)
	local hexMap = workspace:FindFirstChild("HexMap")
	if not hexMap then
		return HexGridConfig.Config.SPAWN_Y
	end

	local hexName = "Hex_" .. q .. "_" .. r
	local terrainModel = nil

	-- Nur durch die Terrain-Ordner suchen (Ebene1, Ebene2, Ebene3_Gebirge,
	-- Ebene4_Bergspitze, Water, ...). Soils/Gebäude/Armeen werden übersprungen.
	for _, folder in ipairs(hexMap:GetChildren()) do
		if folder:IsA("Folder")
			and folder.Name ~= "Soils"
			and folder.Name ~= "ProvinceVisuals"
			and folder.Name ~= "ArmyModels"
			and folder.Name ~= "Buildings" then
			local hex = folder:FindFirstChild(hexName)
			if hex then
				terrainModel = hex
				break
			end
		end
	end

	if not terrainModel then
		return HexGridConfig.Config.SPAWN_Y
	end

	-- Oberkante des TERRAIN-Models berechnen (Haupt-Part, nicht Soil).
	local topY
	if terrainModel:IsA("Model") then
		if terrainModel.PrimaryPart then
			topY = terrainModel.PrimaryPart.Position.Y + terrainModel.PrimaryPart.Size.Y / 2
		else
			local mainPart = terrainModel:FindFirstChildWhichIsA("BasePart")
			if not mainPart then
				return HexGridConfig.Config.SPAWN_Y
			end
			topY = mainPart.Position.Y + mainPart.Size.Y / 2
		end
	elseif terrainModel:IsA("BasePart") then
		topY = terrainModel.Position.Y + terrainModel.Size.Y / 2
	else
		return HexGridConfig.Config.SPAWN_Y
	end

	return topY + HexHeightUtil.SPAWN_HEIGHT_OFFSET
end

return HexHeightUtil
