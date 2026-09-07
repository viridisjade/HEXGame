--[[
    TerrainGenerator (ModuleScript)
    Ort: ServerScriptService > TerrainGenerator
    
    Generiert eine vielfältige Terrain-Map mit mehreren Noise-Oktaven.
    Liest Einstellungen aus MapConfig.
    
    Terrain-Typen:
      1 = Wasser        (Ozeane + Seen)
      2 = Ebene1        (flaches Land)
      3 = Ebene2        (leicht erhöhtes Land)
      4 = Ebene3        (Gebirge)
      5 = Ebene4        (Bergspitzen)
--]]

local TerrainGenerator = {}

local HexUtils = require(script.Parent:WaitForChild("HexUtils"))
local MapConfig = require(script.Parent:WaitForChild("MapConfig"))

--------------------------------------------------------------------------------
-- Interner State
--------------------------------------------------------------------------------
TerrainGenerator.Seed = 0

--------------------------------------------------------------------------------
-- Terrain-Typ Enum
--------------------------------------------------------------------------------
TerrainGenerator.TerrainType = {
	WATER = 1,
	PLAIN1 = 2,
	PLAIN2 = 3,
	MOUNTAIN = 4,
	PEAK = 5,
}

TerrainGenerator.TerrainNames = {
	[1] = "Water",
	[2] = "Ebene1",
	[3] = "Ebene2",
	[4] = "Ebene3_Gebirge",
	[5] = "Ebene4_Bergspitze",
}

--------------------------------------------------------------------------------
-- generateSeed()
--------------------------------------------------------------------------------
function TerrainGenerator.generateSeed()
	TerrainGenerator.Seed = math.random(1, 999999)
	return TerrainGenerator.Seed
end

--------------------------------------------------------------------------------
-- sampleNoise(q, r, scale, seedOffset) -> number (0 bis 1)
--------------------------------------------------------------------------------
function TerrainGenerator.sampleNoise(q, r, scale, seedOffset)
	local seed = TerrainGenerator.Seed + (seedOffset or 0)
	local value = math.noise(q * scale + seed, r * scale + seed * 0.7)
	return math.clamp(value + 0.5, 0, 1)
end

--------------------------------------------------------------------------------
-- multiOctaveNoise(q, r, seedOffset) -> number (0 bis 1)
-- Kombiniert 4 Noise-Oktaven basierend auf MapConfig.Advanced
--------------------------------------------------------------------------------
function TerrainGenerator.multiOctaveNoise(q, r, seedOffset)
	local adv = MapConfig.Advanced
	local detail = adv.WORLD_DETAIL
	local offset = seedOffset or 0

	-- Skalierungen basierend auf Detail-Level
	local baseScale = 0.035 + (detail * 0.02)

	local o1 = TerrainGenerator.sampleNoise(q, r, baseScale, offset)
	local o2 = TerrainGenerator.sampleNoise(q, r, baseScale * 2, offset + 1000)
	local o3 = TerrainGenerator.sampleNoise(q, r, baseScale * 4, offset + 2000)
	local o4 = TerrainGenerator.sampleNoise(q, r, baseScale * 7, offset + 3000)

	local combined = o1 * adv.LARGE_FEATURES_WEIGHT
		+ o2 * adv.MEDIUM_FEATURES_WEIGHT
		+ o3 * adv.SMALL_FEATURES_WEIGHT
		+ o4 * adv.MICRO_FEATURES_WEIGHT

	return math.clamp(combined, 0, 1)
end

--------------------------------------------------------------------------------
-- getIslandMask(q, r) -> number (0 bis 1)
--------------------------------------------------------------------------------
function TerrainGenerator.getIslandMask(q, r)
	local size = MapConfig.MapSize
	local lw = MapConfig.LandWater

	local nx = (q / size.WIDTH) * 2 - 1
	local ny = (r / size.HEIGHT) * 2 - 1

	local edgeDist = math.max(math.abs(nx), math.abs(ny))
	local falloff = 1 - math.pow(edgeDist, 1.8) * lw.EDGE_OCEAN_STRENGTH

	return math.clamp(falloff, 0, 1)
end

--------------------------------------------------------------------------------
-- determineTerrain(q, r) -> terrainType (number)
--------------------------------------------------------------------------------
function TerrainGenerator.determineTerrain(q, r)
	local types = TerrainGenerator.TerrainType
	local lw = MapConfig.LandWater
	local lakes = MapConfig.Lakes
	local terrain = MapConfig.Terrain
	local mountains = MapConfig.Mountains
	local peaks = MapConfig.Peaks

	-- Multi-Oktaven Höhenwert
	local elevation = TerrainGenerator.multiOctaveNoise(q, r, 0)

	-- Randmaske
	if lw.USE_EDGE_OCEAN then
		local mask = TerrainGenerator.getIslandMask(q, r)
		elevation = elevation * mask
	end

	-- Ozean-Wasser
	if elevation < lw.WATER_AMOUNT then
		return types.WATER
	end

	-- Seen im Landesinneren
	if lakes.ENABLED then
		local lakeNoise = TerrainGenerator.sampleNoise(q, r, lakes.SIZE_VARIATION, 10000)
		local lakeDetail = TerrainGenerator.sampleNoise(q, r, lakes.SIZE_VARIATION * 2, 11000)
		local lakeValue = lakeNoise * 0.6 + lakeDetail * 0.4

		if lakeValue > lakes.FREQUENCY then
			return types.WATER
		end
	end

	-- Gebirge
	local mtnScatter = mountains.SCATTER
	local mtnSize = mountains.CLUSTER_SIZE

	local mountainBase = TerrainGenerator.sampleNoise(q, r, mtnSize, 5000)
	local mountainDetail = TerrainGenerator.sampleNoise(q, r, mtnSize * 2, 6000)
	local mountainMicro = TerrainGenerator.sampleNoise(q, r, mtnSize * 4, 6500)

	-- Zerstreuung beeinflusst Gewichtung
	local baseWeight = 0.5 - (mtnScatter * 0.2)
	local detailWeight = 0.3 + (mtnScatter * 0.1)
	local microWeight = 0.2 + (mtnScatter * 0.1)

	local mountainValue = mountainBase * baseWeight + mountainDetail * detailWeight + mountainMicro * microWeight
	local mountainChance = mountainValue + (elevation - 0.5) * 0.08

	if mountainChance > mountains.FREQUENCY then
		-- Bergspitzen
		local peakNoise = TerrainGenerator.sampleNoise(q, r, 0.15, 7000)
		local peakChance = peakNoise + (mountainChance - mountains.FREQUENCY) * 0.1

		if peakChance > peaks.RARITY then
			return types.PEAK
		end

		return types.MOUNTAIN
	end

	-- Ebene1 vs Ebene2
	local plainNoise = TerrainGenerator.sampleNoise(q, r, 0.09, 8000)
	local plainDetail = TerrainGenerator.sampleNoise(q, r, 0.18, 9000)
	local plainValue = plainNoise * 0.6 + plainDetail * 0.4
	local ebene2Chance = plainValue + (elevation - lw.WATER_AMOUNT) * 0.2

	if ebene2Chance > terrain.PLAIN2_AMOUNT then
		return types.PLAIN2
	end

	return types.PLAIN1
end

--------------------------------------------------------------------------------
-- generateMap() -> table
--------------------------------------------------------------------------------
function TerrainGenerator.generateMap()
	local size = MapConfig.MapSize
	local map = {}
	local stats = { [1] = 0, [2] = 0, [3] = 0, [4] = 0, [5] = 0 }

	local seed = TerrainGenerator.generateSeed()
	print("[TerrainGenerator] Seed: " .. seed)
	print("[TerrainGenerator] Generating " .. size.WIDTH .. "x" .. size.HEIGHT .. " map...")

	for q = 0, size.WIDTH - 1 do
		for r = 0, size.HEIGHT - 1 do
			local terrainType = TerrainGenerator.determineTerrain(q, r)
			local key = HexUtils.coordToKey(q, r)

			map[key] = {
				q = q,
				r = r,
				terrainType = terrainType,
				terrainName = TerrainGenerator.TerrainNames[terrainType],
			}

			stats[terrainType] = stats[terrainType] + 1
		end
	end

	local total = size.WIDTH * size.HEIGHT
	print("[TerrainGenerator] === Map Statistik ===")
	for i = 1, 5 do
		local pct = math.floor((stats[i] / total) * 100)
		print("  " .. TerrainGenerator.TerrainNames[i] .. ": " .. stats[i] .. " (" .. pct .. "%)")
	end
	print("[TerrainGenerator] Total: " .. total .. " Hexes")

	return map
end

--------------------------------------------------------------------------------
-- postProcessMap(map) -> map
--------------------------------------------------------------------------------
function TerrainGenerator.postProcessMap(map)
	local size = MapConfig.MapSize
	local types = TerrainGenerator.TerrainType
	local changed = 0

	for q = 0, size.WIDTH - 1 do
		for r = 0, size.HEIGHT - 1 do
			local key = HexUtils.coordToKey(q, r)
			local hex = map[key]
			if not hex then continue end

			local neighbors = HexUtils.getNeighbors(q, r)

			-- Bergspitzen: mind. 2 Berg/Spitzen-Nachbarn
			if hex.terrainType == types.PEAK then
				local mountainNeighbors = 0
				for _, n in ipairs(neighbors) do
					local nKey = HexUtils.coordToKey(n.q, n.r)
					if map[nKey] then
						local nType = map[nKey].terrainType
						if nType == types.MOUNTAIN or nType == types.PEAK then
							mountainNeighbors = mountainNeighbors + 1
						end
					end
				end
				if mountainNeighbors < 2 then
					hex.terrainType = types.MOUNTAIN
					hex.terrainName = TerrainGenerator.TerrainNames[types.MOUNTAIN]
					changed = changed + 1
				end
			end

			-- Einsames Wasser entfernen
			if hex.terrainType == types.WATER then
				local landNeighbors = 0
				local totalNeighbors = 0
				for _, n in ipairs(neighbors) do
					local nKey = HexUtils.coordToKey(n.q, n.r)
					if map[nKey] then
						totalNeighbors = totalNeighbors + 1
						if map[nKey].terrainType >= 2 then
							landNeighbors = landNeighbors + 1
						end
					end
				end
				if totalNeighbors > 0 and landNeighbors >= 5 then
					hex.terrainType = types.PLAIN1
					hex.terrainName = TerrainGenerator.TerrainNames[types.PLAIN1]
					changed = changed + 1
				end
			end
		end
	end

	if changed > 0 then
		print("[TerrainGenerator] Post-Processing: " .. changed .. " Hexes angepasst")
	end

	return map
end

return TerrainGenerator
