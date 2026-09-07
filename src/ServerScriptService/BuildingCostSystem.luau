--[[
    BuildingCostSystem (ModuleScript)
    Ort: ServerScriptService > BuildingCostSystem
    
    Berechnet dynamische Baukosten basierend auf der Stadtgröße.
    Die Basiskosten bleiben fix in der BuildingConfig.
    
    Aufschlag-Tabelle:
        0-4 Gebäude    → +0%
        5-9 Gebäude    → +10%
        10-14 Gebäude  → +20%
        15-19 Gebäude  → +30%
        20-24 Gebäude  → +40%
        25-29 Gebäude  → +50%
        30-34 Gebäude  → +60%
        35-39 Gebäude  → +70%
        40+ Gebäude    → +80% (Maximum)
--]]

local BuildingCostSystem = {}

local CityData = require(script.Parent:WaitForChild("CityData"))
local BuildingConfig = require(script.Parent:WaitForChild("BuildingConfig"))

--------------------------------------------------------------------------------
-- KONFIGURATION
--------------------------------------------------------------------------------
BuildingCostSystem.Config = {
	BUILDING_MARKUP_PER_TIER = 0.10,   -- 10% pro Stufe
	BUILDING_TIER_SIZE = 5,            -- Alle 5 Gebäude eine Stufe
	BUILDING_MAX_MARKUP = 0.80,        -- Maximum +80%

	-- Diese Gebäude zählen NICHT mit:
	EXCLUDED_BUILDING_TYPES = {
		["City"] = true,     -- Stadtzentrum
		["Camp"] = true,     -- Lager
	},
}

--------------------------------------------------------------------------------
-- GetBuildingCount(cityId) -> number
-- Zählt alle FERTIGGESTELLTEN Gebäude (ohne Stadtzentrum/Camp)
--------------------------------------------------------------------------------
function BuildingCostSystem.GetBuildingCount(cityId)
	local city = CityData.GetCity(cityId)
	if not city or not city.buildings then return 0 end

	local count = 0
	for _, building in ipairs(city.buildings) do
		if not BuildingCostSystem.Config.EXCLUDED_BUILDING_TYPES[building.buildingType] then
			count = count + 1
		end
	end

	return count
end

--------------------------------------------------------------------------------
-- GetMarkup(cityId) -> number (0.0 bis 0.8)
-- Berechnet den aktuellen Aufschlag
--------------------------------------------------------------------------------
function BuildingCostSystem.GetMarkup(cityId)
	local config = BuildingCostSystem.Config
	local buildingCount = BuildingCostSystem.GetBuildingCount(cityId)

	local tier = math.floor(buildingCount / config.BUILDING_TIER_SIZE)
	local markup = tier * config.BUILDING_MARKUP_PER_TIER

	-- Auf Maximum begrenzen
	markup = math.min(markup, config.BUILDING_MAX_MARKUP)

	return markup
end

--------------------------------------------------------------------------------
-- GetMarkupPercent(cityId) -> number (0, 10, 20, ... 80)
-- Gibt den Aufschlag als ganze Prozentzahl
--------------------------------------------------------------------------------
function BuildingCostSystem.GetMarkupPercent(cityId)
	local markup = BuildingCostSystem.GetMarkup(cityId)
	return math.floor(markup * 100)
end

--------------------------------------------------------------------------------
-- GetBuildingCost(cityId, buildingType) -> number
-- Berechnet die TATSÄCHLICHEN Kosten (Base × Markup)
--------------------------------------------------------------------------------
function BuildingCostSystem.GetBuildingCost(cityId, buildingType)
	local config = BuildingConfig.GetBuilding(buildingType)
	if not config then return 0 end

	local baseCost = tonumber(config.IndustryCost) or 0
	local markup = BuildingCostSystem.GetMarkup(cityId)

	local actualCost = math.ceil(baseCost * (1 + markup))

	return actualCost
end

--------------------------------------------------------------------------------
-- GetCostBreakdown(cityId, buildingType) -> table
-- Gibt Base, Markup und tatsächliche Kosten zurück (für GUI)
--------------------------------------------------------------------------------
function BuildingCostSystem.GetCostBreakdown(cityId, buildingType)
	local config = BuildingConfig.GetBuilding(buildingType)
	if not config then
		return { baseCost = 0, markup = 0, actualCost = 0, markupPercent = 0, buildingCount = 0 }
	end

	local baseCost = tonumber(config.IndustryCost) or 0
	local markup = BuildingCostSystem.GetMarkup(cityId)
	local actualCost = math.ceil(baseCost * (1 + markup))
	local markupPercent = math.floor(markup * 100)
	local buildingCount = BuildingCostSystem.GetBuildingCount(cityId)

	return {
		baseCost = baseCost,
		markup = markup,
		markupPercent = markupPercent,
		actualCost = actualCost,
		buildingCount = buildingCount,
	}
end

--------------------------------------------------------------------------------
-- GetAllBuildingCosts(cityId) -> table
-- Berechnet die Kosten für ALLE Gebäude (für das Baumenü)
--------------------------------------------------------------------------------
function BuildingCostSystem.GetAllBuildingCosts(cityId)
	local result = {}
	local allBuildings = BuildingConfig.GetAllBuildings()
	local markup = BuildingCostSystem.GetMarkup(cityId)
	local markupPercent = math.floor(markup * 100)
	local buildingCount = BuildingCostSystem.GetBuildingCount(cityId)

	for buildingType, config in pairs(allBuildings) do
		-- Stadtzentrum und Camp überspringen
		if not BuildingCostSystem.Config.EXCLUDED_BUILDING_TYPES[buildingType] then
			local baseCost = tonumber(config.IndustryCost) or 0
			local actualCost = math.ceil(baseCost * (1 + markup))

			result[buildingType] = {
				name = config.Name,
				baseCost = baseCost,
				actualCost = actualCost,
				markupPercent = markupPercent,
			}
		end
	end

	result._info = {
		markupPercent = markupPercent,
		buildingCount = buildingCount,
	}

	return result
end

return BuildingCostSystem
