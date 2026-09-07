--[[
    SoilGenerator (ModuleScript)
    Ort: ServerScriptService > SoilGenerator
    
    Weist jedem Hex einen Soil-Typ zu.
    Liest Einstellungen aus MapConfig.
    
    7 Soil-Typen:
      1. DeepWater    - Wasser ohne Küste
      2. CoastWater   - Wasser mit Land-Nachbar
      3. Grassland    - Grasland
      4. DryGrass     - Trockenes Gras
      5. Forest       - Wald
      6. Rocks        - Felsen (Ebene3)
      7. Mountain     - Bergspitze (Ebene4)
--]]

local SoilGenerator = {}

local HexUtils = require(script.Parent:WaitForChild("HexUtils"))
local MapConfig = require(script.Parent:WaitForChild("MapConfig"))

--------------------------------------------------------------------------------
-- SOIL STATS (Basis-Erträge pro Bodenart)
-- Diese Werte werden zur Stadt addiert, sobald ein Gebäude darauf fertiggestellt wird.
--------------------------------------------------------------------------------
SoilGenerator.Stats = {
	DeepWater   = { Nutrients = 2, Industry = 0, Gold = 1, Research = 0 },
	CoastWater  = { Nutrients = 3, Industry = 0, Gold = 2, Research = 1 },
	Grassland   = { Nutrients = 3, Industry = 1, Gold = 0, Research = 0 },
	DryGrass    = { Nutrients = 1, Industry = 1, Gold = 2, Research = 0 },
	Forest      = { Nutrients = 1, Industry = 2, Gold = 0, Research = 1 },
	Rocks       = { Nutrients = 0, Industry = 3, Gold = 1, Research = 0 },
	Mountain    = { Nutrients = 0, Industry = 2, Gold = 0, Research = 0 },
}

--------------------------------------------------------------------------------
-- Interner State
--------------------------------------------------------------------------------
SoilGenerator.Seed = 0

--------------------------------------------------------------------------------
-- Soil-Typ Enum
--------------------------------------------------------------------------------
SoilGenerator.SoilType = {
	DEEP_WATER = "DeepWater",
	COAST_WATER = "CoastWater",
	GRASSLAND = "Grassland",
	DRY_GRASS = "DryGrass",
	FOREST = "Forest",
	ROCKS = "Rocks",
	MOUNTAIN = "Mountain",
}

--------------------------------------------------------------------------------
-- generateSeed()
--------------------------------------------------------------------------------
function SoilGenerator.generateSeed()
	SoilGenerator.Seed = math.random(1, 999999)
	return SoilGenerator.Seed
end

--------------------------------------------------------------------------------
-- sampleNoise(q, r, scale, seedOffset) -> number (0 bis 1)
--------------------------------------------------------------------------------
function SoilGenerator.sampleNoise(q, r, scale, seedOffset)
	local seed = SoilGenerator.Seed + (seedOffset or 0)
	local value = math.noise(q * scale + seed, r * scale + seed * 0.7)
	return math.clamp(value + 0.5, 0, 1)
end

--------------------------------------------------------------------------------
-- Nachbar-Analyse
--------------------------------------------------------------------------------
function SoilGenerator.getNeighborTerrains(q, r, hexMap)
	local neighbors = HexUtils.getNeighbors(q, r)
	local terrains = {}
	for _, n in ipairs(neighbors) do
		local key = HexUtils.coordToKey(n.q, n.r)
		if hexMap[key] then
			table.insert(terrains, hexMap[key].terrainType)
		end
	end
	return terrains
end

function SoilGenerator.hasLandNeighbor(neighborTerrains)
	for _, terrain in ipairs(neighborTerrains) do
		if terrain >= 2 then return true end
	end
	return false
end

function SoilGenerator.countTerrainNeighbors(neighborTerrains, terrainType)
	local count = 0
	for _, t in ipairs(neighborTerrains) do
		if t == terrainType then count = count + 1 end
	end
	return count
end

--------------------------------------------------------------------------------
-- getForestValue(q, r) -> number
--------------------------------------------------------------------------------
function SoilGenerator.getForestValue(q, r)
	local forest = MapConfig.Forest

	local cluster = SoilGenerator.sampleNoise(q, r, forest.CLUSTER_SIZE, 300)
	local medium = SoilGenerator.sampleNoise(q, r, forest.CLUSTER_SIZE * 2, 400)
	local scatter = SoilGenerator.sampleNoise(q, r, forest.CLUSTER_SIZE * 4, 500)

	return cluster * 0.45 + medium * 0.35 + scatter * 0.20
end

--------------------------------------------------------------------------------
-- getGrassValue(q, r) -> number
--------------------------------------------------------------------------------
function SoilGenerator.getGrassValue(q, r)
	local g1 = SoilGenerator.sampleNoise(q, r, 0.09, 100)
	local g2 = SoilGenerator.sampleNoise(q, r, 0.18, 150)
	local g3 = SoilGenerator.sampleNoise(q, r, 0.35, 200)

	return g1 * 0.45 + g2 * 0.35 + g3 * 0.20
end

--------------------------------------------------------------------------------
-- determineSoil(q, r, hexData, hexMap) -> string (SoilType)
--------------------------------------------------------------------------------
function SoilGenerator.determineSoil(q, r, hexData, hexMap)
	local soil = SoilGenerator.SoilType
	local forest = MapConfig.Forest
	local grass = MapConfig.Grass
	local rocks = MapConfig.Rocks
	local terrainType = hexData.terrainType

	local neighborTerrains = SoilGenerator.getNeighborTerrains(q, r, hexMap)

	----------------------------------------------------------------------------
	-- WASSER (Ozeane + Seen)
	----------------------------------------------------------------------------
	if terrainType == 1 then
		if SoilGenerator.hasLandNeighbor(neighborTerrains) then
			return soil.COAST_WATER
		else
			return soil.DEEP_WATER
		end
	end

	----------------------------------------------------------------------------
	-- EBENE 4 (Bergspitze): Immer Mountain
	----------------------------------------------------------------------------
	if terrainType == 5 then
		return soil.MOUNTAIN
	end

	----------------------------------------------------------------------------
	-- EBENE 3 (Gebirge)
	----------------------------------------------------------------------------
	if terrainType == 4 then
		local rocksBase = SoilGenerator.sampleNoise(q, r, 0.11, 600)
		local rocksDetail = SoilGenerator.sampleNoise(q, r, 0.22, 650)
		local rocksValue = rocksBase * 0.6 + rocksDetail * 0.4

		local peakCount = SoilGenerator.countTerrainNeighbors(neighborTerrains, 5)
		local rocksChance = rocks.COVERAGE + (peakCount * rocks.PEAK_BONUS)

		local mountainCount = SoilGenerator.countTerrainNeighbors(neighborTerrains, 4)
		if mountainCount >= 4 then
			rocksChance = rocksChance + 0.1
		end

		if rocksValue < rocksChance then
			return soil.ROCKS
		end

		-- Forest auf Gebirge (seltener)
		local forestValue = SoilGenerator.getForestValue(q, r) - 0.08
		if forestValue > forest.COVERAGE + 0.08 then
			return soil.FOREST
		end

		-- Grass auf Gebirge
		local grassValue = SoilGenerator.getGrassValue(q, r)
		if grassValue > grass.EBENE3_GREEN then
			return soil.DRY_GRASS
		end
		return soil.GRASSLAND
	end

	----------------------------------------------------------------------------
	-- EBENE 1 und 2
	----------------------------------------------------------------------------
	if terrainType == 2 or terrainType == 3 then

		-- Forest Check
		local terrainBoost = 0
		if terrainType == 2 then
			terrainBoost = 0.05
		end

		local forestValue = SoilGenerator.getForestValue(q, r) + terrainBoost

		-- Hauptwald-Gebiete
		if forestValue > forest.COVERAGE then
			return soil.FOREST
		end

		-- Vereinzelte Bäume
		local scatter = SoilGenerator.sampleNoise(q, r, forest.CLUSTER_SIZE * 4, 500)
		if scatter > forest.SCATTER_TREES then
			local waterCount = SoilGenerator.countTerrainNeighbors(neighborTerrains, 1)
			if waterCount <= 1 then
				return soil.FOREST
			end
		end

		-- Grassland vs DryGrass
		local grassValue = SoilGenerator.getGrassValue(q, r)

		-- Küsten-Effekt
		local waterNeighbors = SoilGenerator.countTerrainNeighbors(neighborTerrains, 1)
		if waterNeighbors >= 2 then
			grassValue = grassValue - 0.1
		end

		-- Gebirgs-Effekt
		local mountainNeighbors = SoilGenerator.countTerrainNeighbors(neighborTerrains, 4)
		local peakNeighbors = SoilGenerator.countTerrainNeighbors(neighborTerrains, 5)
		if mountainNeighbors + peakNeighbors >= 2 then
			grassValue = grassValue + 0.1
		end

		if terrainType == 2 then
			if grassValue > grass.EBENE1_GREEN then
				return soil.DRY_GRASS
			end
			return soil.GRASSLAND
		else
			if grassValue > grass.EBENE2_GREEN then
				return soil.DRY_GRASS
			end
			return soil.GRASSLAND
		end
	end

	return soil.GRASSLAND
end

--------------------------------------------------------------------------------
-- generateSoilMap(hexMap) -> soilMap
--------------------------------------------------------------------------------
function SoilGenerator.generateSoilMap(hexMap)
	local soilMap = {}
	local stats = {}

	local seed = SoilGenerator.generateSeed()
	print("[SoilGenerator] Seed: " .. seed)
	print("[SoilGenerator] Generiere Soil-Typen...")

	local total = 0

	for key, hexData in pairs(hexMap) do
		local soilType = SoilGenerator.determineSoil(hexData.q, hexData.r, hexData, hexMap)
		soilMap[key] = soilType

		stats[soilType] = (stats[soilType] or 0) + 1
		total = total + 1
	end

	print("[SoilGenerator] === Soil Statistik ===")
	for soilType, count in pairs(stats) do
		local pct = math.floor((count / total) * 100)
		print("  " .. soilType .. ": " .. count .. " (" .. pct .. "%)")
	end

	return soilMap
end

return SoilGenerator
