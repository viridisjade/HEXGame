--[[
    BuildingCostSystem (ModuleScript)
    Ort: ServerScriptService > BuildingCostSystem
    
    Berechnet dynamische Baukosten basierend auf der Stadtgröße.
    Die Basiskosten bleiben fix in der BuildingConfig.

    SKALIERUNG (linear, pro Gebäude):
        Mit jedem Gebäude, das die Stadt bereits besitzt, steigen die
        Kosten für das NÄCHSTE Gebäude um COST_SCALE_PER_BUILDING (5%).

        tatsächlicheKosten = basisKosten * (1 + COST_SCALE_PER_BUILDING * anzahlGebäude)

        Beispiele (5% pro Gebäude):
            0 Gebäude  -> x1.00
            1 Gebäude  -> x1.05
            2 Gebäude  -> x1.10
            5 Gebäude  -> x1.25
            10 Gebäude -> x1.50

        Kein Maximal-Aufschlag - die Kosten steigen unbegrenzt weiter.
        Ergebnis wird IMMER auf ganze Zahlen aufgerundet (math.ceil).
--]]

local BuildingCostSystem = {}

local CityData = require(script.Parent:WaitForChild("CityData"))
local BuildingConfig = require(script.Parent:WaitForChild("BuildingConfig"))

--------------------------------------------------------------------------------
-- KONFIGURATION
--------------------------------------------------------------------------------
BuildingCostSystem.Config = {
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
-- GetMarkup(cityId) -> number (z.B. 0.05, 0.10, 0.25, ... theoretisch unbegrenzt)
-- Berechnet den aktuellen Aufschlag: COST_SCALE_PER_BUILDING pro Gebäude,
-- kein Maximum.
--------------------------------------------------------------------------------
function BuildingCostSystem.GetMarkup(cityId)
	local buildingCount = BuildingCostSystem.GetBuildingCount(cityId)
	return BuildingConfig.COST_SCALE_PER_BUILDING * buildingCount
end

--------------------------------------------------------------------------------
-- GetMarkupPercent(cityId) -> number (0, 5, 10, 15, ...)
-- Gibt den Aufschlag als ganze Prozentzahl
--------------------------------------------------------------------------------
function BuildingCostSystem.GetMarkupPercent(cityId)
	local markup = BuildingCostSystem.GetMarkup(cityId)
	return math.floor(markup * 100 + 0.5)
end

--------------------------------------------------------------------------------
-- GetBuildingCost(cityId, buildingType) -> number
-- Berechnet die TATSÄCHLICHEN Industrie-Kosten:
--   baseCost * (1 + COST_SCALE_PER_BUILDING * anzahlGebäude), aufgerundet.
--------------------------------------------------------------------------------
function BuildingCostSystem.GetBuildingCost(cityId, buildingType)
	local config = BuildingConfig.GetBuilding(buildingType)
	if not config then return 0 end

	local baseCost = tonumber(config.IndustryCost) or 0
	local markup = BuildingCostSystem.GetMarkup(cityId)

	local actualCost = math.ceil(baseCost * (1 + markup))

	return actualCost
end

-- Alias (gleiche Berechnung, kürzerer Name für externe Aufrufer).
BuildingCostSystem.GetCost = BuildingCostSystem.GetBuildingCost

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
	local markupPercent = BuildingCostSystem.GetMarkupPercent(cityId)
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
	local markupPercent = BuildingCostSystem.GetMarkupPercent(cityId)
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
