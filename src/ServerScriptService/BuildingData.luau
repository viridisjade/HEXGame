--[[
    BuildingData (ModuleScript)
    Ort: ServerScriptService > BuildingData
    
    Speichert alle gebauten Gebäude.
    
    Datenstruktur pro Gebäude:
    {
        id = number,              -- Eindeutige Gebäude-ID
        buildingType = string,    -- Typ aus BuildingConfig (z.B. "Camp")
        owner = Player,           -- Besitzer
        q = number,               -- Hex-Position
        r = number,
        provinceId = number,      -- Province auf der es steht
    }
--]]

local BuildingData = {}

local buildings = {}      -- buildings[id] = buildingData
local buildingsByHex = {} -- buildingsByHex["q_r"] = buildingId
local nextId = 1

local function hexKey(q, r)
	return q .. "_" .. r
end

--------------------------------------------------------------------------------
-- CreateBuilding(buildingType, owner, q, r, provinceId) -> id
--------------------------------------------------------------------------------
function BuildingData.CreateBuilding(buildingType, owner, q, r, provinceId)
	local id = nextId
	nextId = nextId + 1

	buildings[id] = {
		id = id,
		buildingType = buildingType,
		owner = owner,
		q = q,
		r = r,
		provinceId = provinceId,
	}

	buildingsByHex[hexKey(q, r)] = id

	return id
end

--------------------------------------------------------------------------------
-- GetBuilding(id) -> table or nil
--------------------------------------------------------------------------------
function BuildingData.GetBuilding(id)
	return buildings[id]
end

--------------------------------------------------------------------------------
-- GetBuildingOnHex(q, r) -> table or nil
--------------------------------------------------------------------------------
function BuildingData.GetBuildingOnHex(q, r)
	local id = buildingsByHex[hexKey(q, r)]
	if not id then return nil end
	return buildings[id]
end

--------------------------------------------------------------------------------
-- HasBuildingOnHex(q, r) -> boolean
--------------------------------------------------------------------------------
function BuildingData.HasBuildingOnHex(q, r)
	return buildingsByHex[hexKey(q, r)] ~= nil
end

--------------------------------------------------------------------------------
-- GetBuildingsByOwner(owner) -> table
--------------------------------------------------------------------------------
function BuildingData.GetBuildingsByOwner(owner)
	local result = {}
	for _, building in pairs(buildings) do
		if building.owner == owner then
			table.insert(result, building)
		end
	end
	return result
end

--------------------------------------------------------------------------------
-- GetBuildingsByType(buildingType) -> table
--------------------------------------------------------------------------------
function BuildingData.GetBuildingsByType(buildingType)
	local result = {}
	for _, building in pairs(buildings) do
		if building.buildingType == buildingType then
			table.insert(result, building)
		end
	end
	return result
end

--------------------------------------------------------------------------------
-- RemoveBuilding(id)
--------------------------------------------------------------------------------
function BuildingData.RemoveBuilding(id)
	local building = buildings[id]
	if not building then return end

	buildingsByHex[hexKey(building.q, building.r)] = nil
	buildings[id] = nil
end

--------------------------------------------------------------------------------
-- GetAllBuildings() -> table
--------------------------------------------------------------------------------
function BuildingData.GetAllBuildings()
	return buildings
end

--------------------------------------------------------------------------------
-- GetBuildingCount() -> number
--------------------------------------------------------------------------------
function BuildingData.GetBuildingCount()
	local count = 0
	for _ in pairs(buildings) do
		count = count + 1
	end
	return count
end

--------------------------------------------------------------------------------
-- ClearAll()
--------------------------------------------------------------------------------
function BuildingData.ClearAll()
	buildings = {}
	buildingsByHex = {}
	nextId = 1
	print("[BuildingData] Alle Gebäude-Daten gelöscht.")
end

return BuildingData
