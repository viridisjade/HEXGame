--[[
    CampData (ModuleScript)
    Ort: ServerScriptService > CampData
    
    Speichert alle Daten über Camps und deren geclaimte Provinzen.
    
    Datenstruktur pro Camp:
    {
        id = number,              -- Eindeutige Camp-ID
        buildingId = number,      -- Referenz auf BuildingData
        provinceId = number,      -- Province die durch das Camp geclaimed wurde
        owner = Player,           -- Besitzer
        q = number,               -- Hex-Position
        r = number,
        
        name = string,            -- Camp-Name (z.B. "Nordlager")
        citizenCount = number,    -- Anzahl der Bevölkerung
        
        -- Ertrag pro Runde
        foodPerRound = number,
        industryPerRound = number,
        goldPerRound = number,
        researchPerRound = number,
        
        -- Alle Gebäude in der geclaimten Province (inkl. dem Camp selbst)
        buildings = {
            { buildingId = number, buildingType = string, q = number, r = number },
            ...
        },
    }
    
    Verwendung:
        local CampData = require(script.Parent:WaitForChild("CampData"))
        
        local campId = CampData.CreateCamp(buildingId, provinceId, player, q, r)
        CampData.AddCitizens(campId, 5)
        CampData.SetGoldPerRound(campId, 3)
        
        local camp = CampData.GetCamp(campId)
        print(camp.name)
        print(camp.citizenCount)
--]]

local CampData = {}

--------------------------------------------------------------------------------
-- STANDARDWERTE für neue Camps
--------------------------------------------------------------------------------
CampData.Defaults = {
	CITIZEN_COUNT = 1,
	FOOD_PER_ROUND = 1,
	INDUSTRY_PER_ROUND = 50,
	GOLD_PER_ROUND = 1,
	RESEARCH_PER_ROUND = 0,
}

--------------------------------------------------------------------------------
-- Camp-Namen (werden zufällig vergeben)
--------------------------------------------------------------------------------
local defaultCampNames = {
	"Nordlager", "Südlager", "Ostlager", "Westlager",
	"Steinlager", "Waldlager", "Bergfeste", "Talwacht",
	"Flusslager", "Hügelposten", "Grenzwacht", "Altlager",
	"Neulager", "Sturmlager", "Sonnenlager", "Nebellager",
	"Eichenlager", "Felsenlager", "Weidenlager", "Moorlager",
}

local usedCampNames = {}

--------------------------------------------------------------------------------
-- Interne Daten
--------------------------------------------------------------------------------
local camps = {}              -- camps[id] = campData
local campsByProvince = {}    -- campsByProvince[provinceId] = campId
local campsByHex = {}         -- campsByHex["q_r"] = campId
local nextId = 1

local function hexKey(q, r)
	return q .. "_" .. r
end

--------------------------------------------------------------------------------
-- getRandomCampName() -> string
--------------------------------------------------------------------------------
function CampData.getRandomCampName()
	local available = {}
	for _, name in ipairs(defaultCampNames) do
		if not usedCampNames[name] then
			table.insert(available, name)
		end
	end

	if #available > 0 then
		local name = available[math.random(1, #available)]
		usedCampNames[name] = true
		return name
	end

	return "Lager " .. tostring(nextId)
end

--------------------------------------------------------------------------------
-- CreateCamp(buildingId, provinceId, owner, q, r, optionalName) -> campId
--------------------------------------------------------------------------------
function CampData.CreateCamp(buildingId, provinceId, owner, q, r, optionalName)
	local id = nextId
	nextId = nextId + 1

	camps[id] = {
		id = id,
		buildingId = buildingId,
		provinceId = provinceId,
		owner = owner,
		q = q,
		r = r,

		name = optionalName or CampData.getRandomCampName(),
		citizenCount = CampData.Defaults.CITIZEN_COUNT,

		foodPerRound = CampData.Defaults.FOOD_PER_ROUND,
		industryPerRound = CampData.Defaults.INDUSTRY_PER_ROUND,
		goldPerRound = CampData.Defaults.GOLD_PER_ROUND,
		researchPerRound = CampData.Defaults.RESEARCH_PER_ROUND,

		-- Gebäude in dieser Province (das Camp selbst wird direkt eingetragen)
		buildings = {
			{
				buildingId = buildingId,
				buildingType = "Camp",
				q = q,
				r = r,
			},
		},
	}

	if provinceId then
		campsByProvince[provinceId] = id
	end
	campsByHex[hexKey(q, r)] = id

	print("[CampData] Camp '" .. camps[id].name .. "' erstellt (ID: " .. id .. ", Province: " .. tostring(provinceId) .. ")")
	return id
end

--------------------------------------------------------------------------------
-- GetCamp(id) -> table or nil
--------------------------------------------------------------------------------
function CampData.GetCamp(id)
	return camps[id]
end

--------------------------------------------------------------------------------
-- GetCampByProvince(provinceId) -> table or nil
--------------------------------------------------------------------------------
function CampData.GetCampByProvince(provinceId)
	local id = campsByProvince[provinceId]
	if not id then return nil end
	return camps[id]
end

--------------------------------------------------------------------------------
-- GetCampOnHex(q, r) -> table or nil
--------------------------------------------------------------------------------
function CampData.GetCampOnHex(q, r)
	local id = campsByHex[hexKey(q, r)]
	if not id then return nil end
	return camps[id]
end

--------------------------------------------------------------------------------
-- GetAllCamps() -> table
--------------------------------------------------------------------------------
function CampData.GetAllCamps()
	return camps
end

--------------------------------------------------------------------------------
-- GetCampsByOwner(owner) -> table
--------------------------------------------------------------------------------
function CampData.GetCampsByOwner(owner)
	local result = {}
	for _, camp in pairs(camps) do
		if camp.owner == owner then
			table.insert(result, camp)
		end
	end
	return result
end

--------------------------------------------------------------------------------
-- GetCampCount() -> number
--------------------------------------------------------------------------------
function CampData.GetCampCount()
	local count = 0
	for _ in pairs(camps) do
		count = count + 1
	end
	return count
end

--------------------------------------------------------------------------------
-- NAME
--------------------------------------------------------------------------------
function CampData.GetName(campId)
	local camp = camps[campId]
	return camp and camp.name or nil
end

function CampData.SetName(campId, newName)
	local camp = camps[campId]
	if not camp then return false end
	camp.name = newName
	return true
end

--------------------------------------------------------------------------------
-- CITIZENS
--------------------------------------------------------------------------------
function CampData.GetCitizenCount(campId)
	local camp = camps[campId]
	return camp and camp.citizenCount or 0
end

function CampData.SetCitizenCount(campId, count)
	local camp = camps[campId]
	if not camp then return false end
	camp.citizenCount = math.max(0, count)
	return true
end

function CampData.AddCitizens(campId, amount)
	local camp = camps[campId]
	if not camp then return false end
	camp.citizenCount = math.max(0, camp.citizenCount + amount)
	return true
end

function CampData.RemoveCitizens(campId, amount)
	return CampData.AddCitizens(campId, -amount)
end

--------------------------------------------------------------------------------
-- ERTRÄGE PRO RUNDE
--------------------------------------------------------------------------------
function CampData.GetFoodPerRound(campId)
	local camp = camps[campId]
	return camp and camp.foodPerRound or 0
end

function CampData.SetFoodPerRound(campId, amount)
	local camp = camps[campId]
	if not camp then return false end
	camp.foodPerRound = math.max(0, amount)
	return true
end

function CampData.GetIndustryPerRound(campId)
	local camp = camps[campId]
	return camp and camp.industryPerRound or 0
end

function CampData.SetIndustryPerRound(campId, amount)
	local camp = camps[campId]
	if not camp then return false end
	camp.industryPerRound = math.max(0, amount)
	return true
end

function CampData.GetGoldPerRound(campId)
	local camp = camps[campId]
	return camp and camp.goldPerRound or 0
end

function CampData.SetGoldPerRound(campId, amount)
	local camp = camps[campId]
	if not camp then return false end
	camp.goldPerRound = math.max(0, amount)
	return true
end

function CampData.GetResearchPerRound(campId)
	local camp = camps[campId]
	return camp and camp.researchPerRound or 0
end

function CampData.SetResearchPerRound(campId, amount)
	local camp = camps[campId]
	if not camp then return false end
	camp.researchPerRound = math.max(0, amount)
	return true
end

--------------------------------------------------------------------------------
-- GetAllYields(campId) -> table
-- Gibt alle Erträge auf einmal zurück
--------------------------------------------------------------------------------
function CampData.GetAllYields(campId)
	local camp = camps[campId]
	if not camp then return nil end

	return {
		food = camp.foodPerRound,
		industry = camp.industryPerRound,
		gold = camp.goldPerRound,
		research = camp.researchPerRound,
	}
end

--------------------------------------------------------------------------------
-- GetTotalYieldsByOwner(owner) -> table
-- Summiert alle Erträge aller Camps eines Spielers
--------------------------------------------------------------------------------
function CampData.GetTotalYieldsByOwner(owner)
	local total = {
		food = 0,
		industry = 0,
		gold = 0,
		research = 0,
		citizens = 0,
	}

	for _, camp in pairs(camps) do
		if camp.owner == owner then
			total.food = total.food + camp.foodPerRound
			total.industry = total.industry + camp.industryPerRound
			total.gold = total.gold + camp.goldPerRound
			total.research = total.research + camp.researchPerRound
			total.citizens = total.citizens + camp.citizenCount
		end
	end

	return total
end

--------------------------------------------------------------------------------
-- GEBÄUDE IN DER PROVINCE
--------------------------------------------------------------------------------

-- GetBuildings(campId) -> table
function CampData.GetBuildings(campId)
	local camp = camps[campId]
	if not camp then return {} end
	return camp.buildings or {}
end

-- GetBuildingCount(campId) -> number
function CampData.GetBuildingCount(campId)
	local camp = camps[campId]
	if not camp or not camp.buildings then return 0 end
	return #camp.buildings
end

-- AddBuilding(campId, buildingId, buildingType, q, r) -> boolean
function CampData.AddBuilding(campId, buildingId, buildingType, q, r)
	local camp = camps[campId]
	if not camp then return false end

	camp.buildings = camp.buildings or {}

	-- Doppelte Einträge auf demselben Hex vermeiden
	for _, entry in ipairs(camp.buildings) do
		if entry.q == q and entry.r == r then
			return false
		end
	end

	table.insert(camp.buildings, {
		buildingId = buildingId,
		buildingType = buildingType,
		q = q,
		r = r,
	})

	return true
end

-- RemoveBuildingByHex(campId, q, r) -> boolean
function CampData.RemoveBuildingByHex(campId, q, r)
	local camp = camps[campId]
	if not camp or not camp.buildings then return false end

	for i, entry in ipairs(camp.buildings) do
		if entry.q == q and entry.r == r then
			table.remove(camp.buildings, i)
			return true
		end
	end

	return false
end

-- RemoveBuildingById(campId, buildingId) -> boolean
function CampData.RemoveBuildingById(campId, buildingId)
	local camp = camps[campId]
	if not camp or not camp.buildings then return false end

	for i, entry in ipairs(camp.buildings) do
		if entry.buildingId == buildingId then
			table.remove(camp.buildings, i)
			return true
		end
	end

	return false
end

-- HasBuildingOnHex(campId, q, r) -> boolean
function CampData.HasBuildingOnHex(campId, q, r)
	local camp = camps[campId]
	if not camp or not camp.buildings then return false end

	for _, entry in ipairs(camp.buildings) do
		if entry.q == q and entry.r == r then
			return true
		end
	end

	return false
end

-- AddBuildingToProvince(provinceId, buildingId, buildingType, q, r) -> boolean
-- Komfortfunktion: findet automatisch das Camp der Province
function CampData.AddBuildingToProvince(provinceId, buildingId, buildingType, q, r)
	local camp = CampData.GetCampByProvince(provinceId)
	if not camp then return false end
	return CampData.AddBuilding(camp.id, buildingId, buildingType, q, r)
end

--------------------------------------------------------------------------------
-- UpdateCamp(campId, updates)
--------------------------------------------------------------------------------
function CampData.UpdateCamp(campId, updates)
	local camp = camps[campId]
	if not camp then return false end

	for field, value in pairs(updates) do
		camp[field] = value
	end
	return true
end

--------------------------------------------------------------------------------
-- RemoveCamp(campId)
--------------------------------------------------------------------------------
function CampData.RemoveCamp(campId)
	local camp = camps[campId]
	if not camp then return false end

	if camp.provinceId then
		campsByProvince[camp.provinceId] = nil
	end
	campsByHex[hexKey(camp.q, camp.r)] = nil
	camps[campId] = nil

	print("[CampData] Camp " .. campId .. " entfernt")
	return true
end

--------------------------------------------------------------------------------
-- ClearAll()
--------------------------------------------------------------------------------
function CampData.ClearAll()
	camps = {}
	campsByProvince = {}
	campsByHex = {}
	usedCampNames = {}
	nextId = 1
	print("[CampData] Alle Camp-Daten gelöscht.")
end

--------------------------------------------------------------------------------
-- PrintStats(campId)
--------------------------------------------------------------------------------
function CampData.PrintStats(campId)
	local camp = camps[campId]
	if not camp then
		warn("[CampData] Camp " .. tostring(campId) .. " nicht gefunden")
		return
	end

	print("[CampData] === " .. camp.name .. " (ID: " .. camp.id .. ") ===")
	print("  Position: (" .. camp.q .. ", " .. camp.r .. ")")
	print("  Province: " .. tostring(camp.provinceId))
	print("  Besitzer: " .. (camp.owner and camp.owner.Name or "niemand"))
	print("  Bevölkerung: " .. camp.citizenCount)
	print("  Erträge/Runde:")
	print("    Food: " .. camp.foodPerRound)
	print("    Industry: " .. camp.industryPerRound)
	print("    Gold: " .. camp.goldPerRound)
	print("    Research: " .. camp.researchPerRound)

	local buildings = camp.buildings or {}
	print("  Gebäude in Province: " .. #buildings)
	for _, entry in ipairs(buildings) do
		print("    - " .. tostring(entry.buildingType) .. " @ (" .. tostring(entry.q) .. ", " .. tostring(entry.r) .. ")")
	end
end

--------------------------------------------------------------------------------
-- PrintAll()
--------------------------------------------------------------------------------
function CampData.PrintAll()
	print("[CampData] === Alle Camps (" .. CampData.GetCampCount() .. ") ===")
	for id, _ in pairs(camps) do
		CampData.PrintStats(id)
	end
end

return CampData
