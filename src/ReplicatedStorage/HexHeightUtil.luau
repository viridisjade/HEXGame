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

return HexHeightUtil