--[[
    CityData (ModuleScript)
    Ort: ServerScriptService > CityData
    
    Speichert alle Daten über Städte.
--]]

local CityData = {}

local defaultCityNames = {
	"Königsstadt", "Silberburg", "Goldhafen", "Steinfeste",
	"Eichenstadt", "Nordburg", "Südhafen", "Ostwacht",
	"Westtor", "Hochstadt", "Tiefental", "Bergstadt",
	"Flussstadt", "Seehafen", "Waldheim", "Sonnenstadt",
	"Mondhafen", "Sternenfels", "Drachenstein", "Löwenburg",
}

local usedCityNames = {}

local cities = {}              
local citiesByProvince = {}    
local citiesByHex = {}         
local nextId = 1
local nextBuildOrderId = 1

local function hexKey(q, r)
	return q .. "_" .. r
end

function CityData.getRandomCityName()
	local available = {}
	for _, name in ipairs(defaultCityNames) do
		if not usedCityNames[name] then
			table.insert(available, name)
		end
	end

	if #available > 0 then
		local name = available[math.random(1, #available)]
		usedCityNames[name] = true
		return name
	end

	return "Stadt " .. tostring(nextId)
end

function CityData.CreateCityFromCamp(campData)
	if not campData then return nil end

	local id = nextId
	nextId = nextId + 1

	-- NUR die Grunddaten vom Camp übernehmen
	-- Ressourcen werden NICHT übernommen (City berechnet alles neu!)
	cities[id] = {
		id = id,
		-- ÜBERNOMMEN vom Camp:
		provinceId = campData.provinceId,
		owner = campData.owner,
		q = campData.q,
		r = campData.r,
		name = CityData.getRandomCityName(),
		formerCampId = campData.id,

		-- NEU mit Startwerten (nicht vom Camp übernommen!):
		population = 4,
		growthBar = 0,
		growthThreshold = 30, -- 10 + (4 x 5)
		jobs = { farmer = 1, worker = 1, trader = 1, scientist = 1 },
		jobSlots = { farmer = 1, worker = 1, trader = 1, scientist = 1 },

		-- Ressourcen starten bei 0 (werden vom ResourceSystem berechnet):
		foodPerRound = 0,
		industryPerRound = 0,
		goldPerRound = 0,
		researchPerRound = 0,
		foodStorage = 0,
		foodSurplus = 0,
		currentFoodProduction = 0,
		currentFoodConsumption = 0,
		currentIndustryProduction = 0,
		currentGoldProduction = 0,
		currentResearchProduction = 0,

		-- WICHTIG: Das Stadtzentrum muss als Gebäude eingetragen werden!
		-- Sonst findet GetValidSpawnHexes() keine Spawn-Fläche!
		buildings = {
			{
				buildingId = campData.buildingId or 0,
				buildingType = "City",
				q = campData.q,
				r = campData.r,
			}
		},
		buildQueue = {},
		-- NEU: Arbeits-Queue für das Building-System (Ist neben der Produktions-Warteschlange für Gebäude/Units)
		industryQueue = {},
	}

	if campData.provinceId then
		citiesByProvince[campData.provinceId] = id
	end
	citiesByHex[hexKey(campData.q, campData.r)] = id

	print("[CityData] City '" .. cities[id].name .. "' erstellt (frische Werte, keine Camp-Ressourcen)")
	return id
end

--------------------------------------------------------------------------------
-- InitializeJobs(cityId)
-- Verteilt alle Einwohner direkt auf Jobs bei der Gründung.
--------------------------------------------------------------------------------
function CityData.InitializeJobs(cityId)
	local city = cities[cityId]
	if not city then return end

	local pop = city.population or 0
	local assignedTotal = 0
	for _, count in pairs(city.jobs) do assignedTotal = assignedTotal + count end
	local unassigned = pop - assignedTotal

	if unassigned > 0 then
		for jobType, slots in pairs(city.jobSlots) do
			while unassigned > 0 and (city.jobs[jobType] or 0) < slots do
				city.jobs[jobType] = (city.jobs[jobType] or 0) + 1
				unassigned = unassigned - 1
			end
		end
	end
end

function CityData.CreateCity(buildingId, provinceId, owner, q, r, optionalName)
	local id = nextId
	nextId = nextId + 1

	cities[id] = {
		id = id, buildingId = buildingId, provinceId = provinceId, owner = owner, q = q, r = r,
		name = optionalName or CityData.getRandomCityName(),
		citizenCount = 1, foodPerRound = 2, industryPerRound = 1, goldPerRound = 2, researchPerRound = 1,
		buildings = { { buildingId = buildingId, buildingType = "City", q = q, r = r } },
		buildQueue = {},
		formerCampId = nil,
	}

	if provinceId then citiesByProvince[provinceId] = id end
	citiesByHex[hexKey(q, r)] = id
	return id
end

function CityData.GetCity(id) return cities[id] end
function CityData.GetCityByProvince(provinceId) local id = citiesByProvince[provinceId]; return id and cities[id] end
function CityData.GetCityOnHex(q, r) local id = citiesByHex[hexKey(q, r)]; return id and cities[id] end
function CityData.GetAllCities() return cities end

function CityData.GetCitiesByOwner(owner)
	local result = {}
	for _, city in pairs(cities) do
		if city.owner == owner then table.insert(result, city) end
	end
	return result
end

function CityData.GetCityCount()
	local count = 0
	for _ in pairs(cities) do count = count + 1 end
	return count
end

function CityData.GetName(cityId) local city = cities[cityId]; return city and city.name end
function CityData.SetName(cityId, newName) local city = cities[cityId]; if city then city.name = newName end end

function CityData.GetCitizenCount(cityId) local city = cities[cityId]; return city and city.citizenCount or 0 end
function CityData.SetCitizenCount(cityId, count) local city = cities[cityId]; if city then city.citizenCount = math.max(0, count) end end
function CityData.AddCitizens(cityId, amount) local city = cities[cityId]; if city then city.citizenCount = math.max(0, city.citizenCount + amount) end end

function CityData.SetFoodPerRound(cityId, v) local c=cities[cityId]; if c then c.foodPerRound=math.max(0,v) end end
function CityData.SetIndustryPerRound(cityId, v) local c=cities[cityId]; if c then c.industryPerRound=math.max(0,v) end end
function CityData.SetGoldPerRound(cityId, v) local c=cities[cityId]; if c then c.goldPerRound=math.max(0,v) end end
function CityData.SetResearchPerRound(cityId, v) local c=cities[cityId]; if c then c.researchPerRound=math.max(0,v) end end

-- Addiert ein Stats-Table (z.B. {Nutrients=2, Industry=1, Gold=1}) auf die Stadt
function CityData.AddStats(cityId, stats)
	local city = cities[cityId]
	if not city or not stats then return end

	city.foodPerRound = (city.foodPerRound or 0) + (stats.Nutrients or 0)
	city.industryPerRound = (city.industryPerRound or 0) + (stats.Industry or 0)
	city.goldPerRound = (city.goldPerRound or 0) + (stats.Gold or 0)
	city.researchPerRound = (city.researchPerRound or 0) + (stats.Research or 0)

	print("[CityData] Stadt " .. tostring(city.name) .. " Erträge aktualisiert: Food " .. city.foodPerRound .. " | Ind " .. city.industryPerRound .. " | Gold " .. city.goldPerRound)
end

function CityData.GetBuildings(cityId) local c=cities[cityId]; return c and c.buildings or {} end

function CityData.AddBuilding(cityId, buildingId, buildingType, q, r, optionalData)
	local city = cities[cityId]
	if not city then return false end

	city.buildings = city.buildings or {}

	for _, entry in ipairs(city.buildings) do
		if entry.q == q and entry.r == r then return false end
	end

	local newBuilding = {
		buildingId = buildingId,
		buildingType = buildingType,
		q = q,
		r = r,
	}

	if optionalData then
		for key, value in pairs(optionalData) do
			newBuilding[key] = value
		end
	end

	table.insert(city.buildings, newBuilding)
	return true
end

function CityData.HasBuildingOnHex(cityId, q, r)
	local city = cities[cityId]
	if not city or not city.buildings then return false end
	for _, entry in ipairs(city.buildings) do
		if entry.q == q and entry.r == r then return true end
	end
	return false
end

--------------------------------------------------------------------------------
-- BUILD QUEUE
-- Es wird immer nur der erste Auftrag der Queue aktiv mit Industry versorgt.
--------------------------------------------------------------------------------
function CityData.GetBuildQueue(cityId)
	local city = cities[cityId]
	return city and city.buildQueue or {}
end

function CityData.GetActiveBuildOrder(cityId)
	local city = cities[cityId]
	if not city or not city.buildQueue then return nil end
	return city.buildQueue[1]
end

function CityData.HasQueuedBuildingOnHex(cityId, q, r)
	local city = cities[cityId]
	if not city or not city.buildQueue then return false end

	for _, order in ipairs(city.buildQueue) do
		-- Nur Gebäude blockieren das Bauen auf einem Hex, keine Units!
		if order.orderType == "Building" and order.q == q and order.r == r then
			return true
		end
	end
	return false
end

function CityData.AddBuildOrder(cityId, data)
	local city = cities[cityId]
	if not city then return nil end

	city.buildQueue = city.buildQueue or {}

	-- Block-Check nur für Gebäude
	if data.orderType == nil or data.orderType == "Building" then
		if CityData.HasBuildingOnHex(cityId, data.q, data.r)
			or CityData.HasQueuedBuildingOnHex(cityId, data.q, data.r) then
			return nil
		end
	end

	local order = {
		id = nextBuildOrderId,
		orderType = data.orderType or "Building",
		buildingType = data.buildingType,
		unitType = data.unitType,
		q = data.q,
		r = data.r,
		spawnQ = data.spawnQ,
		spawnR = data.spawnR,
		industryProgress = 0,
		industryCost = data.industryCost,
		citizenCost = data.citizenCost or 0,
		status = (#city.buildQueue == 0) and "Building" or "Queued",
	}
	nextBuildOrderId = nextBuildOrderId + 1

	table.insert(city.buildQueue, order)
	return order
end

function CityData.CompleteActiveBuildOrder(cityId)
	local city = cities[cityId]
	if not city or not city.buildQueue or #city.buildQueue == 0 then
		return nil
	end

	local completed = table.remove(city.buildQueue, 1)
	if city.buildQueue[1] then
		city.buildQueue[1].status = "Building"
	end
	return completed
end

function CityData.RemoveBuildOrder(cityId, orderId)
	local city = cities[cityId]
	if not city or not city.buildQueue then return nil end

	for index, order in ipairs(city.buildQueue) do
		if order.id == orderId then
			local removed = table.remove(city.buildQueue, index)
			if city.buildQueue[1] then
				city.buildQueue[1].status = "Building"
			end
			return removed
		end
	end
	return nil
end

function CityData.RemoveCity(cityId)
	local city = cities[cityId]
	if not city then return end
	if city.provinceId then citiesByProvince[city.provinceId] = nil end
	citiesByHex[hexKey(city.q, city.r)] = nil
	cities[cityId] = nil
end

function CityData.ClearAll()
	cities = {}
	citiesByProvince = {}
	citiesByHex = {}
	usedCityNames = {}
	nextId = 1
	nextBuildOrderId = 1
end

return CityData
