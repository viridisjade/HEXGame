--[[
    BuildingConfig (ModuleScript)
    Ort: ServerScriptService > BuildingConfig
    
    Definiert alle Gebäude-Typen mit Kosten und Model-Namen.
    
    StatMultiplier: Bestimmt, wie stark die Erträge des Bodens (Soil) multipliziert werden.
      Farm       -> 3x Nutrients
      Factory    -> 3x Industry
      Market     -> 3x Gold
      Laboratory -> 3x Research
      City       -> 2x überall (Zentrum)
--]]

local BuildingConfig = {}

--------------------------------------------------------------------------------
-- GEBÄUDE-DEFINITIONEN
--------------------------------------------------------------------------------
BuildingConfig.Buildings = {

	Camp = {
		Name = "Camp",
		Model = "Camp",
		Cost = 20,
		CostType = "Gold",
		ClaimsProvince = true,
		StatMultiplier = { Nutrients = 1, Industry = 1, Gold = 1, Research = 1 },
		Description = "Einfaches Lager.",
	},

	City = {
		Name = "City",
		Model = "City",
		Cost = 0,
		CostType = "Gold",
		ClaimsProvince = false,
		StatMultiplier = { Nutrients = 2, Industry = 2, Gold = 2, Research = 2 },
		Description = "Das Stadtzentrum. Erzeugt den 2-fachen Ertrag des Bodens.",
	},

	Farm = {
		Name = "Farm",
		Model = "Farm",
		Cost = 15,
		CostType = "Gold",
		ClaimsProvince = false,
		IndustryCost = 15,
		StatMultiplier = { Nutrients = 3, Industry = 1, Gold = 1, Research = 1 },
		Description = "Zieht 3x so viel Nahrung aus dem Boden.",
	},

	Factory = {
		Name = "Factory",
		Model = "Factory",
		Cost = 30,
		CostType = "Gold",
		ClaimsProvince = false,
		IndustryCost = 15,
		StatMultiplier = { Nutrients = 1, Industry = 3, Gold = 1, Research = 1 },
		Description = "Zieht 3x so viel Industrie aus dem Boden.",
	},

	Market = {
		Name = "Market",
		Model = "Market",
		Cost = 25,
		CostType = "Gold",
		ClaimsProvince = false,
		IndustryCost = 20,
		StatMultiplier = { Nutrients = 1, Industry = 1, Gold = 3, Research = 1 },
		Description = "Zieht 3x so viel Gold aus dem Boden.",
	},

	Laboratory = {
		Name = "Laboratory",
		Model = "Laboratory",
		Cost = 40,
		CostType = "Gold",
		ClaimsProvince = false,
		IndustryCost = 20,
		StatMultiplier = { Nutrients = 1, Industry = 1, Gold = 1, Research = 3 },
		Description = "Zieht 3x so viel Forschung aus dem Boden.",
	},

	Bastion = {
		Name = "Bastion",
		Model = "Bastion",
		Cost = 50,
		CostType = "Gold",
		ClaimsProvince = false,
		IndustryCost = 30,
		StatMultiplier = { Nutrients = 1, Industry = 1, Gold = 1, Research = 1 },
		Description = "Verteidigungsanlage. Bringt Basis-Ertrag.",
	},
}

--------------------------------------------------------------------------------
-- COST_SCALE_PER_BUILDING
-- Mit jedem Gebäude, das eine Stadt bereits besitzt, steigen die
-- Industrie-Kosten für das NÄCHSTE Gebäude um diesen Faktor (5%).
-- tatsächlicheKosten = basisKosten * (1 + COST_SCALE_PER_BUILDING * anzahlGebäude)
-- Siehe BuildingCostSystem.GetBuildingCost für die tatsächliche Berechnung.
--------------------------------------------------------------------------------
BuildingConfig.COST_SCALE_PER_BUILDING = 0.05

--------------------------------------------------------------------------------
-- Ordner-Name in ServerStorage
--------------------------------------------------------------------------------
BuildingConfig.FOLDER_NAME = "Buildings"

--------------------------------------------------------------------------------
-- GetBuilding(buildingType) -> table or nil
--------------------------------------------------------------------------------
function BuildingConfig.GetBuilding(buildingType)
	return BuildingConfig.Buildings[buildingType]
end

--------------------------------------------------------------------------------
-- GetAllBuildings() -> table
--------------------------------------------------------------------------------
function BuildingConfig.GetAllBuildings()
	return BuildingConfig.Buildings
end

--------------------------------------------------------------------------------
-- GetCost(buildingType) -> number
--------------------------------------------------------------------------------
function BuildingConfig.GetCost(buildingType)
	local building = BuildingConfig.Buildings[buildingType]
	return building and building.Cost or 0
end

return BuildingConfig
