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
-- STUFEN-SYSTEM (exponentiell)
-- Ersetzt die alte lineare Skalierung. Mit steigender Gebäudeanzahl
-- springt die Stadt in höhere "Stufen", die jeweils einen höheren
-- (exponentiell wachsenden) Kosten-Multiplikator haben.
--
-- Stufe 1:  1–2 Gebäude    → ×1.0
-- Stufe 2:  3–4 Gebäude    → ×1.6
-- Stufe 3:  5–10 Gebäude   → ×2.7
-- Stufe 4:  11–15 Gebäude  → ×4.1
-- Stufe 5:  16–20 Gebäude  → ×5.8
-- ... (Stufe steigt danach alle 5 Gebäude um 1, kein Maximum)
--
-- tatsächlicheKosten = math.ceil(basisKosten * GetMultiplier(GetStage(anzahlGebäude)))
-- Siehe BuildingCostSystem.GetCost für die tatsächliche Berechnung.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- GetStage(buildingCount) -> number
-- Berechnet die aktuelle Stufe anhand der Gebäudeanzahl.
--------------------------------------------------------------------------------
function BuildingConfig.GetStage(buildingCount)
	buildingCount = tonumber(buildingCount) or 0

	if buildingCount <= 2 then
		return 1
	elseif buildingCount <= 4 then
		return 2
	elseif buildingCount <= 10 then
		return 3
	else
		return 4 + math.floor((buildingCount - 11) / 5)
	end
end

--------------------------------------------------------------------------------
-- GetMultiplier(stage) -> number
-- Berechnet den Kosten-Multiplikator für eine gegebene Stufe (exponentiell,
-- kein Maximum).
--------------------------------------------------------------------------------
function BuildingConfig.GetMultiplier(stage)
	stage = tonumber(stage) or 1

	if stage <= 1 then
		return 1.0
	end

	return 1 + math.pow(stage - 1, 1.5) * 0.6
end

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
