--[[
    ProvinceGenerator (ModuleScript)
    Ort: ServerScriptService > ProvinceGenerator
    
    Unterteilt die Map in Provinzen mittels Flood Fill (Flut-Methode).
    
    Neue Logik:
      1. LAND-Provinzen werden zuerst auf Land-Hexes erzeugt
      2. Multi-Source Flood Fill expandiert möglichst gleichmäßig
      3. Land-Provinzen dürfen Küste + etwas Ozean bekommen,
         aber nur bis zu einem Wasser-Limit
      4. Übrig gebliebene Ozeane werden zu eigenen Ozean-Provinzen
    
    Ergebnis:
      - Land-Provinzen sind ähnlich groß
      - Keine Land-Provinz besteht größtenteils aus Ozean
      - Die ganze Map ist vollständig in Provinzen eingeteilt
--]]

local ProvinceGenerator = {}

local HexUtils = require(script.Parent:WaitForChild("HexUtils"))
local MapConfig = require(script.Parent:WaitForChild("MapConfig"))

--------------------------------------------------------------------------------
-- KOMPATIBILITÄTS-KONFIGURATION
-- Die eigentlichen Werte kommen aus MapConfig.Provinces
--------------------------------------------------------------------------------
ProvinceGenerator.Config = {
	PROVINCE_COUNT = 24,        -- Fallback wenn MapConfig.Provinces fehlt
	SEEDS_ON_LAND_ONLY = true,
}

--------------------------------------------------------------------------------
-- Interner State
--------------------------------------------------------------------------------
local provinceMap = {}
local seeds = {}
local generatedProvinceCount = 0
local provinceStats = {}

--------------------------------------------------------------------------------
-- Hilfsfunktionen
--------------------------------------------------------------------------------
function ProvinceGenerator.getTargetLandProvinceCount()
	if MapConfig.Provinces and MapConfig.Provinces.LAND_PROVINCE_COUNT then
		return MapConfig.Provinces.LAND_PROVINCE_COUNT
	end
	return ProvinceGenerator.Config.PROVINCE_COUNT
end

function ProvinceGenerator.getSeedPlacementMode()
	if MapConfig.Provinces and MapConfig.Provinces.SEED_PLACEMENT then
		return MapConfig.Provinces.SEED_PLACEMENT
	end
	return "grid"
end

function ProvinceGenerator.isWater(hex)
	return hex and hex.terrainType == 1
end

function ProvinceGenerator.isLand(hex)
	return hex and hex.terrainType >= 2
end

function ProvinceGenerator.hasLandNeighbor(q, r, hexMap)
	local neighbors = HexUtils.getNeighbors(q, r)
	for _, n in ipairs(neighbors) do
		local key = HexUtils.coordToKey(n.q, n.r)
		if ProvinceGenerator.isLand(hexMap[key]) then
			return true
		end
	end
	return false
end

function ProvinceGenerator.shuffleTable(t)
	for i = #t, 2, -1 do
		local j = math.random(1, i)
		t[i], t[j] = t[j], t[i]
	end
end

function ProvinceGenerator.ensureProvinceStats(id)
	if not provinceStats[id] then
		provinceStats[id] = {
			land = 0,
			water = 0,
			total = 0,
			isOceanProvince = false,
		}
	end
	return provinceStats[id]
end

function ProvinceGenerator.assignHexToProvince(key, hex, provinceId)
	if provinceMap[key] then return false end

	provinceMap[key] = provinceId
	local stats = ProvinceGenerator.ensureProvinceStats(provinceId)

	if ProvinceGenerator.isWater(hex) then
		stats.water = stats.water + 1
	else
		stats.land = stats.land + 1
	end
	stats.total = stats.total + 1

	return true
end

function ProvinceGenerator.getWaterRatio(provinceId)
	local stats = provinceStats[provinceId]
	if not stats or stats.total == 0 then return 0 end
	return stats.water / stats.total
end

--------------------------------------------------------------------------------
-- getHexPools(hexMap)
-- Trennt die Map in Land, Küstenwasser und tiefen Ozean
--------------------------------------------------------------------------------
function ProvinceGenerator.getHexPools(hexMap)
	local landKeys = {}
	local coastalWaterKeys = {}
	local deepOceanKeys = {}

	for key, hex in pairs(hexMap) do
		if ProvinceGenerator.isLand(hex) then
			table.insert(landKeys, key)
		else
			if ProvinceGenerator.hasLandNeighbor(hex.q, hex.r, hexMap) then
				table.insert(coastalWaterKeys, key)
			else
				table.insert(deepOceanKeys, key)
			end
		end
	end

	return landKeys, coastalWaterKeys, deepOceanKeys
end

--------------------------------------------------------------------------------
-- placeSeeds(hexMap, count, landKeys) -> seeds
-- Platziert Seeds möglichst gleichmäßig auf Land-Hexes
--------------------------------------------------------------------------------
function ProvinceGenerator.placeSeeds(hexMap, count, landKeys)
	local size = MapConfig.MapSize
	local placementMode = ProvinceGenerator.getSeedPlacementMode()
	seeds = {}

	local used = {}

	if placementMode == "grid" then
		local cols = math.ceil(math.sqrt(count * (size.WIDTH / size.HEIGHT)))
		local rows = math.ceil(count / cols)
		local cellWidth = size.WIDTH / cols
		local cellHeight = size.HEIGHT / rows

		local placed = 0
		for row = 0, rows - 1 do
			for col = 0, cols - 1 do
				if placed >= count then break end

				local targetQ = col * cellWidth + cellWidth / 2
				local targetR = row * cellHeight + cellHeight / 2

				-- Nächstes unbenutztes Land-Hex zur Zellenmitte suchen
				local bestHex = nil
				local bestDist = math.huge

				for _, key in ipairs(landKeys) do
					if not used[key] then
						local hex = hexMap[key]
						local dq = hex.q - targetQ
						local dr = hex.r - targetR
						local dist = dq * dq + dr * dr

						if dist < bestDist then
							bestDist = dist
							bestHex = hex
						end
					end
				end

				if bestHex then
					local key = HexUtils.coordToKey(bestHex.q, bestHex.r)
					used[key] = true
					placed = placed + 1
					table.insert(seeds, {
						q = bestHex.q,
						r = bestHex.r,
						province = placed,
					})
				end
			end
			if placed >= count then break end
		end
	else
		-- Random fallback
		local shuffled = {}
		for _, key in ipairs(landKeys) do
			table.insert(shuffled, key)
		end
		ProvinceGenerator.shuffleTable(shuffled)

		for i = 1, math.min(count, #shuffled) do
			local hex = hexMap[shuffled[i]]
			table.insert(seeds, {
				q = hex.q,
				r = hex.r,
				province = i,
			})
		end
	end

	print("[ProvinceGenerator] " .. #seeds .. " Land-Seeds platziert")
	return seeds
end

--------------------------------------------------------------------------------
-- expandOneLand(frontier, provinceId, hexMap) -> boolean
-- Weist genau EIN weiteres Land-Hex zu (Round Robin für ähnliche Größe)
--------------------------------------------------------------------------------
function ProvinceGenerator.expandOneLand(frontier, provinceId, hexMap)
	while frontier.head <= #frontier.items do
		local current = frontier.items[frontier.head]
		local neighbors = HexUtils.getNeighbors(current.q, current.r)
		ProvinceGenerator.shuffleTable(neighbors)

		for _, n in ipairs(neighbors) do
			local key = HexUtils.coordToKey(n.q, n.r)
			local hex = hexMap[key]

			if hex and not provinceMap[key] and ProvinceGenerator.isLand(hex) then
				ProvinceGenerator.assignHexToProvince(key, hex, provinceId)
				table.insert(frontier.items, {q = n.q, r = n.r})
				return true
			end
		end

		frontier.head = frontier.head + 1
	end

	return false
end

--------------------------------------------------------------------------------
-- floodFillBalancedLand(hexMap, landKeys, landProvinceCount)
-- Multi-Source Flood Fill, aber round-robin pro Provinz → ähnliche Größe
--------------------------------------------------------------------------------
function ProvinceGenerator.floodFillBalancedLand(hexMap, landKeys, landProvinceCount)
	provinceMap = {}
	provinceStats = {}

	local frontiers = {}
	local assignedLand = 0

	-- Seeds initialisieren
	for _, seed in ipairs(seeds) do
		local key = HexUtils.coordToKey(seed.q, seed.r)
		if not provinceMap[key] then
			ProvinceGenerator.assignHexToProvince(key, hexMap[key], seed.province)
			frontiers[seed.province] = { items = { {q = seed.q, r = seed.r} }, head = 1 }
			assignedLand = assignedLand + 1
		end
	end

	local totalLand = #landKeys
	local progress = true

	while assignedLand < totalLand and progress do
		progress = false

		for provinceId = 1, landProvinceCount do
			local frontier = frontiers[provinceId]
			if frontier then
				local expanded = ProvinceGenerator.expandOneLand(frontier, provinceId, hexMap)
				if expanded then
					assignedLand = assignedLand + 1
					progress = true
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- absorbRemainingLand(hexMap)
-- Hängt verbleibende unzugeordnete Land-Hexes an benachbarte Provinzen an.
-- Falls komplett isoliert: neue Provinz erzeugen.
--------------------------------------------------------------------------------
function ProvinceGenerator.absorbRemainingLand(hexMap)
	local size = MapConfig.MapSize
	local changed = true

	while changed do
		changed = false

		for q = 0, size.WIDTH - 1 do
			for r = 0, size.HEIGHT - 1 do
				local key = HexUtils.coordToKey(q, r)
				local hex = hexMap[key]

				if ProvinceGenerator.isLand(hex) and not provinceMap[key] then
					local neighbors = HexUtils.getNeighbors(q, r)
					local bestProvince = nil
					local bestSize = math.huge

					for _, n in ipairs(neighbors) do
						local nKey = HexUtils.coordToKey(n.q, n.r)
						local p = provinceMap[nKey]
						if p then
							local stats = provinceStats[p]
							if stats and stats.total < bestSize then
								bestSize = stats.total
								bestProvince = p
							end
						end
					end

					if bestProvince then
						ProvinceGenerator.assignHexToProvince(key, hex, bestProvince)
						changed = true
					end
				end
			end
		end
	end

	-- Isolierte Inseln ohne Seed → eigene Zusatz-Provinzen
	for q = 0, size.WIDTH - 1 do
		for r = 0, size.HEIGHT - 1 do
			local key = HexUtils.coordToKey(q, r)
			local hex = hexMap[key]

			if ProvinceGenerator.isLand(hex) and not provinceMap[key] then
				generatedProvinceCount = generatedProvinceCount + 1
				local newProvince = generatedProvinceCount

				local queue = { {q = q, r = r} }
				local head = 1
				ProvinceGenerator.assignHexToProvince(key, hex, newProvince)

				while head <= #queue do
					local current = queue[head]
					head = head + 1

					for _, n in ipairs(HexUtils.getNeighbors(current.q, current.r)) do
						local nKey = HexUtils.coordToKey(n.q, n.r)
						local nHex = hexMap[nKey]
						if ProvinceGenerator.isLand(nHex) and not provinceMap[nKey] then
							ProvinceGenerator.assignHexToProvince(nKey, nHex, newProvince)
							table.insert(queue, {q = n.q, r = n.r})
						end
					end
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- assignNearWaterToLandProvinces(hexMap)
-- Gibt Land-Provinzen Küste + etwas Ozean, aber mit Wasser-Limit.
--------------------------------------------------------------------------------
function ProvinceGenerator.assignNearWaterToLandProvinces(hexMap, landProvinceCount)
	local size = MapConfig.MapSize
	local pConfig = MapConfig.Provinces or {}
	local maxWaterRatio = pConfig.MAX_WATER_RATIO or 0.22
	local waterRings = pConfig.LAND_WATER_RINGS or 2

	-- Zielgröße nur für Land-Provinzen
	local totalLand = 0
	for _, stats in pairs(provinceStats) do
		totalLand = totalLand + (stats.land or 0)
	end
	local targetLandPerProvince = math.max(1, math.ceil(totalLand / math.max(1, landProvinceCount)))
	local maxWaterPerProvince = math.max(1, math.floor(targetLandPerProvince * maxWaterRatio))

	for ring = 1, waterRings do
		local assignments = {}

		for q = 0, size.WIDTH - 1 do
			for r = 0, size.HEIGHT - 1 do
				local key = HexUtils.coordToKey(q, r)
				local hex = hexMap[key]

				if ProvinceGenerator.isWater(hex) and not provinceMap[key] then
					local neighbors = HexUtils.getNeighbors(q, r)
					local bestProvince = nil
					local bestScore = math.huge

					for _, n in ipairs(neighbors) do
						local nKey = HexUtils.coordToKey(n.q, n.r)
						local provinceId = provinceMap[nKey]

						if provinceId and provinceId <= landProvinceCount then
							local stats = provinceStats[provinceId]
							if stats then
								if stats.water < maxWaterPerProvince and ProvinceGenerator.getWaterRatio(provinceId) <= maxWaterRatio then
									local score = stats.total + stats.water * 3
									if score < bestScore then
										bestScore = score
										bestProvince = provinceId
									end
								end
							end
						end
					end

					if bestProvince then
						assignments[key] = bestProvince
					end
				end
			end
		end

		local changed = 0
		for key, provinceId in pairs(assignments) do
			local hex = hexMap[key]
			if ProvinceGenerator.assignHexToProvince(key, hex, provinceId) then
				changed = changed + 1
			end
		end

		if changed == 0 then
			break
		end
	end
end

--------------------------------------------------------------------------------
-- createOceanProvinces(hexMap)
-- Alle übrigen Wasser-Hexes werden als reine Ozean-Provinzen erzeugt.
-- Jede zusammenhängende Wasserfläche = eine Ozean-Provinz.
--------------------------------------------------------------------------------
function ProvinceGenerator.createOceanProvinces(hexMap)
	local size = MapConfig.MapSize

	for q = 0, size.WIDTH - 1 do
		for r = 0, size.HEIGHT - 1 do
			local key = HexUtils.coordToKey(q, r)
			local hex = hexMap[key]

			if ProvinceGenerator.isWater(hex) and not provinceMap[key] then
				generatedProvinceCount = generatedProvinceCount + 1
				local oceanProvince = generatedProvinceCount
				local stats = ProvinceGenerator.ensureProvinceStats(oceanProvince)
				stats.isOceanProvince = true

				local queue = { {q = q, r = r} }
				local head = 1
				ProvinceGenerator.assignHexToProvince(key, hex, oceanProvince)

				while head <= #queue do
					local current = queue[head]
					head = head + 1

					for _, n in ipairs(HexUtils.getNeighbors(current.q, current.r)) do
						local nKey = HexUtils.coordToKey(n.q, n.r)
						local nHex = hexMap[nKey]
						if ProvinceGenerator.isWater(nHex) and not provinceMap[nKey] then
							ProvinceGenerator.assignHexToProvince(nKey, nHex, oceanProvince)
							table.insert(queue, {q = n.q, r = n.r})
						end
					end
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- generateProvinces(hexMap) -> provinceMap
--------------------------------------------------------------------------------
function ProvinceGenerator.generateProvinces(hexMap)
	local requestedLandProvinceCount = ProvinceGenerator.getTargetLandProvinceCount()
	generatedProvinceCount = 0

	print("[ProvinceGenerator] Starte Provinz-Generierung...")
	print("[ProvinceGenerator] Gewünschte Land-Provinzen: " .. requestedLandProvinceCount)

	local landKeys = select(1, ProvinceGenerator.getHexPools(hexMap))

	-- 1. Seeds auf Land platzieren
	ProvinceGenerator.placeSeeds(hexMap, requestedLandProvinceCount, landKeys)

	-- Tatsächliche Startanzahl an Land-Provinzen = Seed-Anzahl
	local landProvinceCount = #seeds
	generatedProvinceCount = landProvinceCount
	print("[ProvinceGenerator] Tatsächliche Start-Provinzen auf Land: " .. landProvinceCount)

	-- 2. Land möglichst gleichmäßig auf Provinzen verteilen
	ProvinceGenerator.floodFillBalancedLand(hexMap, landKeys, landProvinceCount)

	-- 3. Verbliebenes Land absorbieren / isolierte Inseln behandeln
	ProvinceGenerator.absorbRemainingLand(hexMap)

	-- Nach absorbRemainingLand können zusätzliche Land-Provinzen entstanden sein
	landProvinceCount = generatedProvinceCount

	-- 4. Küste + etwas Ozean an Land-Provinzen geben (begrenzt)
	ProvinceGenerator.assignNearWaterToLandProvinces(hexMap, landProvinceCount)

	-- 5. Alle übrigen Ozeane zu reinen Ozean-Provinzen machen
	ProvinceGenerator.createOceanProvinces(hexMap)

	-- Statistik
	local total = 0
	print("[ProvinceGenerator] === Provinz Statistik ===")
	for province = 1, generatedProvinceCount do
		local stats = provinceStats[province]
		if stats then
			local kind = stats.isOceanProvince and "Ozean" or "Land"
			local waterPct = stats.total > 0 and math.floor((stats.water / stats.total) * 100) or 0
			print("  Provinz " .. province .. " [" .. kind .. "]: " .. stats.total .. " Hexes, Wasser: " .. waterPct .. "%")
			total = total + stats.total
		end
	end
	print("[ProvinceGenerator] Total: " .. total .. " Hexes in Provinzen")
	print("[ProvinceGenerator] Gesamt-Provinzen: " .. generatedProvinceCount)

	return provinceMap
end

--------------------------------------------------------------------------------
-- getProvinceMap() -> table
--------------------------------------------------------------------------------
function ProvinceGenerator.getProvinceMap()
	return provinceMap
end

--------------------------------------------------------------------------------
-- getSeeds() -> table
--------------------------------------------------------------------------------
function ProvinceGenerator.getSeeds()
	return seeds
end

--------------------------------------------------------------------------------
-- getProvinceCount() -> number
-- Gibt die TATSÄCHLICH generierte Gesamtzahl zurück
-- (Land-Provinzen + zusätzliche Ozean-Provinzen)
--------------------------------------------------------------------------------
function ProvinceGenerator.getProvinceCount()
	return generatedProvinceCount
end

return ProvinceGenerator
