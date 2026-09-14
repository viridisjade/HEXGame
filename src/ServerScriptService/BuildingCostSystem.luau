--[[
    BuildingCostSystem (ModuleScript)
    Ort: ServerScriptService > BuildingCostSystem
    
    Berechnet dynamische Baukosten basierend auf der Stadtgröße.
    Die Basiskosten bleiben fix in der BuildingConfig.

    SKALIERUNG (Stufen-System, exponentiell):
        Die Anzahl der bereits gebauten Gebäude (ohne Stadtzentrum/Camp)
        bestimmt die aktuelle "Stufe" der Stadt. Jede Stufe hat einen
        eigenen (exponentiell wachsenden) Kosten-Multiplikator.
        Siehe BuildingConfig.GetStage / BuildingConfig.GetMultiplier.

        tatsächlicheKosten = math.ceil(basisKosten * GetMultiplier(GetStage(anzahlGebäude)))

        Beispiele (Farm, Basis 15):
            1. Gebäude  (Stufe 1)  -> x1.0  -> 15
            3. Gebäude  (Stufe 2)  -> x1.6  -> 24
            7. Gebäude  (Stufe 3)  -> x2.7  -> 41
            12. Gebäude (Stufe 4)  -> x4.1  -> 62
            50. Gebäude (Stufe 11) -> x20.0 -> 300

        Kein Maximal-Multiplikator - die Kosten steigen unbegrenzt weiter.
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
-- GetStage(cityId) -> number
-- Aktuelle Stufe der Stadt anhand ihrer Gebäudeanzahl.
--------------------------------------------------------------------------------
function BuildingCostSystem.GetStage(cityId)
	local buildingCount = BuildingCostSystem.GetBuildingCount(cityId)
	return BuildingConfig.GetStage(buildingCount)
end

--------------------------------------------------------------------------------
-- GetMultiplier(cityId) -> number (z.B. 1.0, 1.6, 2.7, ... theoretisch unbegrenzt)
-- Der aktuelle Kosten-Multiplikator der Stadt-Stufe.
--------------------------------------------------------------------------------
function BuildingCostSystem.GetMultiplier(cityId)
	local stage = BuildingCostSystem.GetStage(cityId)
	return BuildingConfig.GetMultiplier(stage)
end

--------------------------------------------------------------------------------
-- GetBuildingCost(cityId, buildingType) -> number
-- Berechnet die TATSÄCHLICHEN Industrie-Kosten:
--   math.ceil(baseCost * GetMultiplier(GetStage(anzahlGebäude)))
--------------------------------------------------------------------------------
function BuildingCostSystem.GetBuildingCost(cityId, buildingType)
	local config = BuildingConfig.GetBuilding(buildingType)
	if not config then return 0 end

	local baseCost = tonumber(config.IndustryCost) or 0
	local buildingCount = BuildingCostSystem.GetBuildingCount(cityId)
	local stage = BuildingConfig.GetStage(buildingCount)
	local multiplier = BuildingConfig.GetMultiplier(stage)

	local actualCost = math.ceil(baseCost * multiplier)

	return actualCost
end

-- Alias (gleiche Berechnung, kürzerer Name für externe Aufrufer).
BuildingCostSystem.GetCost = BuildingCostSystem.GetBuildingCost

--------------------------------------------------------------------------------
-- GetCostBreakdown(cityId, buildingType) -> table
-- Gibt Base, Stufe, Multiplikator und tatsächliche Kosten zurück (für GUI)
--------------------------------------------------------------------------------
function BuildingCostSystem.GetCostBreakdown(cityId, buildingType)
	local config = BuildingConfig.GetBuilding(buildingType)
	if not config then
		return { baseCost = 0, stage = 1, multiplier = 1.0, actualCost = 0, buildingCount = 0 }
	end

	local baseCost = tonumber(config.IndustryCost) or 0
	local buildingCount = BuildingCostSystem.GetBuildingCount(cityId)
	local stage = BuildingConfig.GetStage(buildingCount)
	local multiplier = BuildingConfig.GetMultiplier(stage)
	local actualCost = math.ceil(baseCost * multiplier)

	return {
		baseCost = baseCost,
		stage = stage,
		multiplier = multiplier,
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
	local buildingCount = BuildingCostSystem.GetBuildingCount(cityId)
	local stage = BuildingConfig.GetStage(buildingCount)
	local multiplier = BuildingConfig.GetMultiplier(stage)

	for buildingType, config in pairs(allBuildings) do
		-- Stadtzentrum und Camp überspringen
		if not BuildingCostSystem.Config.EXCLUDED_BUILDING_TYPES[buildingType] then
			local baseCost = tonumber(config.IndustryCost) or 0
			local actualCost = math.ceil(baseCost * multiplier)

			result[buildingType] = {
				name = config.Name,
				baseCost = baseCost,
				actualCost = actualCost,
				stage = stage,
				multiplier = multiplier,
			}
		end
	end

	result._info = {
		stage = stage,
		multiplier = multiplier,
		buildingCount = buildingCount,
	}

	return result
end

return BuildingCostSystem
