--[[
    TechConfig (ModuleScript)
    Location: ReplicatedStorage > TechConfig

    Definition of all 16 technologies. Lives in ReplicatedStorage so the
    tech tree GUI can read names, costs and effect texts directly.

    TECH RECORD
        Id          : string   unique key
        Name        : string   display name
        Category    : string   see TechConfig.Category
        Cost        : number   research points needed
        Description : string   short line for the button
        Effect      : table    machine readable effect (see EffectType)

    EFFECT TYPES
        StatMod     -> flat / percent bonus on unit stats
        YieldMod    -> percent bonus on a city yield
        CostMod     -> percent discount on a cost
        MovementMod -> movement bonus
        Special     -> handled explicitly by the systems
--]]

local TechConfig = {}

--------------------------------------------------------------------------------
-- ENUMS
--------------------------------------------------------------------------------
TechConfig.Category = {
	MILITARY       = "Military",
	ECONOMY        = "Economy",
	INFRASTRUCTURE = "Infrastructure",
	KNOWLEDGE      = "Knowledge",
}

-- Display order + labels for the four GUI columns.
TechConfig.CategoryOrder = {
	{ key = "Military",       label = "Militaer",      icon = "\u{2694}\u{FE0F}" },
	{ key = "Economy",        label = "Wirtschaft",    icon = "\u{1F4B0}" },
	{ key = "Infrastructure", label = "Infrastruktur", icon = "\u{1F3D7}\u{FE0F}" },
	{ key = "Knowledge",      label = "Wissen",        icon = "\u{1F4DA}" },
}

TechConfig.EffectType = {
	STAT_MOD     = "StatMod",
	YIELD_MOD    = "YieldMod",
	COST_MOD     = "CostMod",
	MOVEMENT_MOD = "MovementMod",
	SPECIAL      = "Special",
}

--------------------------------------------------------------------------------
-- TECHNOLOGIES
--------------------------------------------------------------------------------
TechConfig.Techs = {

	----------------------------------------------------------------------------
	-- MILITARY
	----------------------------------------------------------------------------
	BronzeWeapons = {
		Id = "BronzeWeapons",
		Name = "Bronzewaffen",
		Category = "Military",
		Cost = 20,
		Description = "+5 Angriff fuer alle Nahkampf-Einheiten",
		Effect = {
			Type = "StatMod",
			Stat = "Attack",
			Mode = "Flat",
			Value = 5,
			UnitClass = "Melee",   -- only melee units
		},
	},

	IronArmor = {
		Id = "IronArmor",
		Name = "Eisenruestung",
		Category = "Military",
		Cost = 35,
		Description = "+10% Verteidigung fuer alle Einheiten",
		Effect = {
			Type = "StatMod",
			Stat = "Defense",
			Mode = "Percent",
			Value = 0.10,
		},
	},

	CavalryTactics = {
		Id = "CavalryTactics",
		Name = "Kavallerie-Taktik",
		Category = "Military",
		Cost = 45,
		Description = "+2 Bewegung fuer Reiter",
		Effect = {
			Type = "MovementMod",
			Mode = "Flat",
			Value = 2,
			UnitClass = "Rider",
		},
	},

	SiegeEngineering = {
		Id = "SiegeEngineering",
		Name = "Belagerungstechnik",
		Category = "Military",
		Cost = 60,
		Description = "+50% Schaden gegen Staedte und Camps",
		Effect = {
			Type = "Special",
			Key = "SiegeBonus",
			Value = 0.50,
		},
	},

	----------------------------------------------------------------------------
	-- ECONOMY
	----------------------------------------------------------------------------
	AdvancedFarming = {
		Id = "AdvancedFarming",
		Name = "Fortschrittliche Landwirtschaft",
		Category = "Economy",
		Cost = 25,
		Description = "+50% Nahrung aus Farmen",
		Effect = {
			Type = "YieldMod",
			Yield = "food",
			Value = 0.50,
			BuildingType = "Farm",
		},
	},

	MiningTechniques = {
		Id = "MiningTechniques",
		Name = "Bergbautechnik",
		Category = "Economy",
		Cost = 35,
		Description = "+30% Industrie-Ertrag",
		Effect = {
			Type = "YieldMod",
			Yield = "work",
			Value = 0.30,
		},
	},

	TradeNetworks = {
		Id = "TradeNetworks",
		Name = "Handelsnetze",
		Category = "Economy",
		Cost = 45,
		Description = "+25% Gold aus Maerkten",
		Effect = {
			Type = "YieldMod",
			Yield = "gold",
			Value = 0.25,
			BuildingType = "Market",
		},
	},

	MassProduction = {
		Id = "MassProduction",
		Name = "Massenproduktion",
		Category = "Economy",
		Cost = 60,
		Description = "-20% Industriekosten fuer Einheiten",
		Effect = {
			Type = "CostMod",
			Target = "UnitRecruitment",
			Value = 0.20,
		},
	},

	----------------------------------------------------------------------------
	-- INFRASTRUCTURE
	----------------------------------------------------------------------------
	RoadBuilding = {
		Id = "RoadBuilding",
		Name = "Strassenbau",
		Category = "Infrastructure",
		Cost = 25,
		Description = "+1 Bewegung im eigenen Gebiet",
		Effect = {
			Type = "MovementMod",
			Mode = "Flat",
			Value = 1,
			OwnTerritoryOnly = true,
		},
	},

	Fortification = {
		Id = "Fortification",
		Name = "Befestigung",
		Category = "Infrastructure",
		Cost = 40,
		Description = "+20% Verteidigung in Staedten und Camps",
		Effect = {
			Type = "Special",
			Key = "FortificationBonus",
			Value = 0.20,
		},
	},

	Logistics = {
		Id = "Logistics",
		Name = "Logistik",
		Category = "Infrastructure",
		Cost = 50,
		Description = "+2 maximale Einheiten pro Armee (8 -> 10)",
		Effect = {
			Type = "Special",
			Key = "MaxUnitsBonus",
			Value = 2,
		},
	},

	SupplyLines = {
		Id = "SupplyLines",
		Name = "Nachschublinien",
		Category = "Infrastructure",
		Cost = 65,
		Description = "Armeen heilen 5% LP pro Runde im eigenen Gebiet",
		Effect = {
			Type = "Special",
			Key = "SupplyHeal",
			Value = 0.05,
		},
	},

	----------------------------------------------------------------------------
	-- KNOWLEDGE
	----------------------------------------------------------------------------
	Cartography = {
		Id = "Cartography",
		Name = "Kartographie",
		Category = "Knowledge",
		Cost = 20,
		Description = "+2 Sichtweite fuer alle Einheiten",
		Effect = {
			Type = "StatMod",
			Stat = "Sight",
			Mode = "Flat",
			Value = 2,
		},
	},

	Engineering = {
		Id = "Engineering",
		Name = "Ingenieurwesen",
		Category = "Knowledge",
		Cost = 40,
		Description = "Gebaeude sind 1 Runde schneller fertig",
		Effect = {
			Type = "Special",
			Key = "BuildSpeedRounds",
			Value = 1,
		},
	},

	Medicine = {
		Id = "Medicine",
		Name = "Medizin",
		Category = "Knowledge",
		Cost = 50,
		Description = "+10% Heilung nach Kaempfen",
		Effect = {
			Type = "Special",
			Key = "PostCombatHealBonus",
			Value = 0.10,
		},
	},

	AdvancedResearch = {
		Id = "AdvancedResearch",
		Name = "Fortgeschrittene Forschung",
		Category = "Knowledge",
		Cost = 70,
		Description = "+50% Forschungs-Ertrag aller Staedte",
		Effect = {
			Type = "YieldMod",
			Yield = "research",
			Value = 0.50,
		},
	},
}

--------------------------------------------------------------------------------
-- Display order inside a category (cheapest first).
--------------------------------------------------------------------------------
TechConfig.TechOrder = {
	Military       = { "BronzeWeapons", "IronArmor", "CavalryTactics", "SiegeEngineering" },
	Economy        = { "AdvancedFarming", "MiningTechniques", "TradeNetworks", "MassProduction" },
	Infrastructure = { "RoadBuilding", "Fortification", "Logistics", "SupplyLines" },
	Knowledge      = { "Cartography", "Engineering", "Medicine", "AdvancedResearch" },
}

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------
function TechConfig.GetTech(techId)
	if type(techId) ~= "string" then return nil end
	return TechConfig.Techs[techId]
end

function TechConfig.GetAllTechs()
	return TechConfig.Techs
end

-- Returns the techs of one category IN DISPLAY ORDER.
function TechConfig.GetTechsByCategory(category)
	local result = {}
	local order = TechConfig.TechOrder[category]

	if order then
		for _, techId in ipairs(order) do
			local tech = TechConfig.Techs[techId]
			if tech then table.insert(result, tech) end
		end
		return result
	end

	-- Fallback for a category without an explicit order.
	for _, tech in pairs(TechConfig.Techs) do
		if tech.Category == category then table.insert(result, tech) end
	end
	table.sort(result, function(a, b) return a.Cost < b.Cost end)
	return result
end

function TechConfig.GetTechCount(category)
	if not category then
		local n = 0
		for _ in pairs(TechConfig.Techs) do n += 1 end
		return n
	end
	return #TechConfig.GetTechsByCategory(category)
end

function TechConfig.IsValidTech(techId)
	return TechConfig.GetTech(techId) ~= nil
end

return TechConfig
