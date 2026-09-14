--[[
    TechConfig (ModuleScript)
    Location: ReplicatedStorage > TechConfig

    Definition of all 16 technologies, each with 3 tiers:
        Bronze -> Silver -> Gold   (researched in order)

    Lives in ReplicatedStorage so the tech tree GUI can read names,
    costs and effect texts directly.

    TECH RECORD
        Id          : string   unique key
        Name        : string   display name
        Category    : string   see TechConfig.Category
        BaseCost    : number   research points for tier 1 (Bronze)
        Description : string   short line for the button
        Levels      : { [tier] = {
                           cost    = number   RP to reach THIS tier,
                           Desc    = string   short effect text,
                           Effect  = table    machine readable effect,
                       } }   -- tier 1 = Bronze, 2 = Silver, 3 = Gold

    LEVEL-SYSTEM
        A tech's tier is a number 0-3:
            0 = not researched, 1 = Bronze, 2 = Silver, 3 = Gold (max)
        Effects are CUMULATIVE-FREE: each tier holds the FULL effect for
        that tier (Silver = +20%, NOT +10% +10%). Upgrading replaces the
        previous tier's effect.

    EFFECT TYPES
        StatMod     -> flat / percent bonus on unit stats
        YieldMod    -> percent bonus on a city yield
        CostMod     -> percent discount on a cost
        MovementMod -> movement bonus
        Special     -> handled explicitly by the systems
--]]

local TechConfig = {}

TechConfig.MAX_LEVEL = 3

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
-- TECHNOLOGIES (3 tiers each)
--------------------------------------------------------------------------------
TechConfig.Techs = {

	----------------------------------------------------------------------------
	-- MILITARY
	----------------------------------------------------------------------------
	BronzeWeapons = {
		Id = "BronzeWeapons",
		Name = "Bronzewaffen",
		Category = "Military",
		BaseCost = 20,
		Description = "Angriff fuer Nahkampf-Einheiten",
		Levels = {
			[1] = { cost = 20, Desc = "+5 Angriff (Nahkampf)",      Effect = { Type = "StatMod", Stat = "Attack", Mode = "Flat",    Value = 5,  UnitClass = "Melee" } },
			[2] = { cost = 40, Desc = "+10 Angriff (Nahkampf)",     Effect = { Type = "StatMod", Stat = "Attack", Mode = "Flat",    Value = 10, UnitClass = "Melee" } },
			[3] = { cost = 60, Desc = "+15 Angriff (Nahkampf)",     Effect = { Type = "StatMod", Stat = "Attack", Mode = "Flat",    Value = 15, UnitClass = "Melee" } },
		},
	},

	IronArmor = {
		Id = "IronArmor",
		Name = "Eisenruestung",
		Category = "Military",
		BaseCost = 25,
		Description = "Verteidigung fuer alle Einheiten",
		Levels = {
			[1] = { cost = 25, Desc = "+10% Verteidigung", Effect = { Type = "StatMod", Stat = "Defense", Mode = "Percent", Value = 0.10 } },
			[2] = { cost = 50, Desc = "+20% Verteidigung", Effect = { Type = "StatMod", Stat = "Defense", Mode = "Percent", Value = 0.20 } },
			[3] = { cost = 75, Desc = "+30% Verteidigung", Effect = { Type = "StatMod", Stat = "Defense", Mode = "Percent", Value = 0.30 } },
		},
	},

	CavalryTactics = {
		Id = "CavalryTactics",
		Name = "Kavallerie-Taktik",
		Category = "Military",
		BaseCost = 20,
		Description = "Bewegung fuer Reiter",
		Levels = {
			[1] = { cost = 20, Desc = "+1 Bewegung (Reiter)", Effect = { Type = "MovementMod", Mode = "Flat", Value = 1, UnitClass = "Rider" } },
			[2] = { cost = 40, Desc = "+2 Bewegung (Reiter)", Effect = { Type = "MovementMod", Mode = "Flat", Value = 2, UnitClass = "Rider" } },
			[3] = { cost = 60, Desc = "+3 Bewegung (Reiter)", Effect = { Type = "MovementMod", Mode = "Flat", Value = 3, UnitClass = "Rider" } },
		},
	},

	SiegeEngineering = {
		Id = "SiegeEngineering",
		Name = "Belagerungstechnik",
		Category = "Military",
		BaseCost = 30,
		Description = "Schaden gegen Staedte und Camps",
		Levels = {
			[1] = { cost = 30, Desc = "+25% Schaden gegen Gebaeude", Effect = { Type = "Special", Key = "SiegeBonus",         Value = 0.25 } },
			[2] = { cost = 60, Desc = "+50% Schaden gegen Gebaeude", Effect = { Type = "Special", Key = "SiegeBonus",         Value = 0.50 } },
			[3] = { cost = 90, Desc = "+75% Schaden gegen Gebaeude", Effect = { Type = "Special", Key = "SiegeBonus",         Value = 0.75 } },
		},
	},

	----------------------------------------------------------------------------
	-- ECONOMY
	----------------------------------------------------------------------------
	AdvancedFarming = {
		Id = "AdvancedFarming",
		Name = "Fortschrittliche Landwirtschaft",
		Category = "Economy",
		BaseCost = 20,
		Description = "Nahrung aus Farmen",
		Levels = {
			[1] = { cost = 20, Desc = "+25% Nahrung (Farmen)", Effect = { Type = "YieldMod", Yield = "food", Value = 0.25, BuildingType = "Farm" } },
			[2] = { cost = 40, Desc = "+50% Nahrung (Farmen)", Effect = { Type = "YieldMod", Yield = "food", Value = 0.50, BuildingType = "Farm" } },
			[3] = { cost = 60, Desc = "+75% Nahrung (Farmen)", Effect = { Type = "YieldMod", Yield = "food", Value = 0.75, BuildingType = "Farm" } },
		},
	},

	MiningTechniques = {
		Id = "MiningTechniques",
		Name = "Bergbautechnik",
		Category = "Economy",
		BaseCost = 20,
		Description = "Industrie-Ertrag",
		Levels = {
			[1] = { cost = 20, Desc = "+15% Industrie-Ertrag", Effect = { Type = "YieldMod", Yield = "work", Value = 0.15 } },
			[2] = { cost = 40, Desc = "+30% Industrie-Ertrag", Effect = { Type = "YieldMod", Yield = "work", Value = 0.30 } },
			[3] = { cost = 60, Desc = "+45% Industrie-Ertrag", Effect = { Type = "YieldMod", Yield = "work", Value = 0.45 } },
		},
	},

	TradeNetworks = {
		Id = "TradeNetworks",
		Name = "Handelsnetze",
		Category = "Economy",
		BaseCost = 25,
		Description = "Gold aus Maerkten",
		Levels = {
			[1] = { cost = 25, Desc = "+15% Gold (Maerkte)", Effect = { Type = "YieldMod", Yield = "gold", Value = 0.15, BuildingType = "Market" } },
			[2] = { cost = 50, Desc = "+25% Gold (Maerkte)", Effect = { Type = "YieldMod", Yield = "gold", Value = 0.25, BuildingType = "Market" } },
			[3] = { cost = 75, Desc = "+40% Gold (Maerkte)", Effect = { Type = "YieldMod", Yield = "gold", Value = 0.40, BuildingType = "Market" } },
		},
	},

	MassProduction = {
		Id = "MassProduction",
		Name = "Massenproduktion",
		Category = "Economy",
		BaseCost = 25,
		Description = "Industriekosten fuer Einheiten",
		Levels = {
			[1] = { cost = 25, Desc = "-10% Industriekosten (Einheiten)", Effect = { Type = "CostMod", Target = "UnitRecruitment", Value = 0.10 } },
			[2] = { cost = 50, Desc = "-20% Industriekosten (Einheiten)", Effect = { Type = "CostMod", Target = "UnitRecruitment", Value = 0.20 } },
			[3] = { cost = 75, Desc = "-30% Industriekosten (Einheiten)", Effect = { Type = "CostMod", Target = "UnitRecruitment", Value = 0.30 } },
		},
	},

	----------------------------------------------------------------------------
	-- INFRASTRUCTURE
	----------------------------------------------------------------------------
	RoadBuilding = {
		Id = "RoadBuilding",
		Name = "Strassenbau",
		Category = "Infrastructure",
		BaseCost = 20,
		Description = "Bewegung im eigenen Gebiet",
		Levels = {
			[1] = { cost = 20, Desc = "+1 Bewegung (eigenes Gebiet)", Effect = { Type = "MovementMod", Mode = "Flat", Value = 1, OwnTerritoryOnly = true } },
			[2] = { cost = 40, Desc = "+2 Bewegung (eigenes Gebiet)", Effect = { Type = "MovementMod", Mode = "Flat", Value = 2, OwnTerritoryOnly = true } },
			[3] = { cost = 60, Desc = "+3 Bewegung (eigenes Gebiet)", Effect = { Type = "MovementMod", Mode = "Flat", Value = 3, OwnTerritoryOnly = true } },
		},
	},

	Fortification = {
		Id = "Fortification",
		Name = "Befestigung",
		Category = "Infrastructure",
		BaseCost = 25,
		Description = "Verteidigung in Staedten und Camps",
		Levels = {
			[1] = { cost = 25, Desc = "+10% Verteidigung (Staedte/Camps)", Effect = { Type = "Special", Key = "FortificationBonus",    Value = 0.10 } },
			[2] = { cost = 50, Desc = "+20% Verteidigung (Staedte/Camps)", Effect = { Type = "Special", Key = "FortificationBonus",    Value = 0.20 } },
			[3] = { cost = 75, Desc = "+30% Verteidigung (Staedte/Camps)", Effect = { Type = "Special", Key = "FortificationBonus",    Value = 0.30 } },
		},
	},

	Logistics = {
		Id = "Logistics",
		Name = "Logistik",
		Category = "Infrastructure",
		BaseCost = 30,
		Description = "Maximale Einheiten pro Armee (Basis 8)",
		Levels = {
			[1] = { cost = 30, Desc = "+1 max. Einheiten/Armee (8->9)",  Effect = { Type = "Special", Key = "MaxUnitsBonus", Value = 1 } },
			[2] = { cost = 60, Desc = "+2 max. Einheiten/Armee (8->10)", Effect = { Type = "Special", Key = "MaxUnitsBonus", Value = 2 } },
			[3] = { cost = 90, Desc = "+4 max. Einheiten/Armee (8->12)", Effect = { Type = "Special", Key = "MaxUnitsBonus", Value = 4 } },
		},
	},

	SupplyLines = {
		Id = "SupplyLines",
		Name = "Nachschublinien",
		Category = "Infrastructure",
		BaseCost = 25,
		Description = "Heilung pro Runde im eigenen Gebiet",
		Levels = {
			[1] = { cost = 25, Desc = "3% Heilung/Runde (eigenes Gebiet)", Effect = { Type = "Special", Key = "SupplyHeal", Value = 0.03 } },
			[2] = { cost = 50, Desc = "5% Heilung/Runde (eigenes Gebiet)", Effect = { Type = "Special", Key = "SupplyHeal", Value = 0.05 } },
			[3] = { cost = 75, Desc = "8% Heilung/Runde (eigenes Gebiet)", Effect = { Type = "Special", Key = "SupplyHeal", Value = 0.08 } },
		},
	},

	----------------------------------------------------------------------------
	-- KNOWLEDGE
	----------------------------------------------------------------------------
	Cartography = {
		Id = "Cartography",
		Name = "Kartographie",
		Category = "Knowledge",
		BaseCost = 15,
		Description = "Sichtweite fuer alle Einheiten",
		Levels = {
			[1] = { cost = 15, Desc = "+1 Sichtweite", Effect = { Type = "StatMod", Stat = "Sight", Mode = "Flat", Value = 1 } },
			[2] = { cost = 30, Desc = "+2 Sichtweite", Effect = { Type = "StatMod", Stat = "Sight", Mode = "Flat", Value = 2 } },
			[3] = { cost = 45, Desc = "+3 Sichtweite", Effect = { Type = "StatMod", Stat = "Sight", Mode = "Flat", Value = 3 } },
		},
	},

	Engineering = {
		Id = "Engineering",
		Name = "Ingenieurwesen",
		Category = "Knowledge",
		BaseCost = 25,
		Description = "Bauzeit fuer Gebaeude",
		Levels = {
			[1] = { cost = 25, Desc = "-1 Runde Bauzeit", Effect = { Type = "Special", Key = "BuildSpeedRounds", Value = 1 } },
			[2] = { cost = 50, Desc = "-2 Runden Bauzeit", Effect = { Type = "Special", Key = "BuildSpeedRounds", Value = 2 } },
			[3] = { cost = 75, Desc = "-3 Runden Bauzeit", Effect = { Type = "Special", Key = "BuildSpeedRounds", Value = 3 } },
		},
	},

	Medicine = {
		Id = "Medicine",
		Name = "Medizin",
		Category = "Knowledge",
		BaseCost = 20,
		Description = "Heilung nach Kaempfen",
		Levels = {
			[1] = { cost = 20, Desc = "+10% Heilung", Effect = { Type = "Special", Key = "PostCombatHealBonus", Value = 0.10 } },
			[2] = { cost = 40, Desc = "+20% Heilung", Effect = { Type = "Special", Key = "PostCombatHealBonus", Value = 0.20 } },
			[3] = { cost = 60, Desc = "+30% Heilung", Effect = { Type = "Special", Key = "PostCombatHealBonus", Value = 0.30 } },
		},
	},

	AdvancedResearch = {
		Id = "AdvancedResearch",
		Name = "Fortgeschrittene Forschung",
		Category = "Knowledge",
		BaseCost = 30,
		Description = "Forschungs-Ertrag aller Staedte",
		Levels = {
			[1] = { cost = 30, Desc = "+25% Forschungs-Ertrag", Effect = { Type = "YieldMod", Yield = "research", Value = 0.25 } },
			[2] = { cost = 60, Desc = "+50% Forschungs-Ertrag", Effect = { Type = "YieldMod", Yield = "research", Value = 0.50 } },
			[3] = { cost = 90, Desc = "+75% Forschungs-Ertrag", Effect = { Type = "YieldMod", Yield = "research", Value = 0.75 } },
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
-- LEVEL HELPERS
--------------------------------------------------------------------------------
-- GetLevelName(level) -> "Bronze" | "Silber" | "Gold" | ""
function TechConfig.GetLevelName(level)
	if level == 1 then return "Bronze" end
	if level == 2 then return "Silber" end
	if level == 3 then return "Gold" end
	return ""
end

-- GetNextLevel(currentLevel) -> next tier number, or nil when maxed.
function TechConfig.GetNextLevel(currentLevel)
	local current = tonumber(currentLevel) or 0
	if current >= TechConfig.MAX_LEVEL then return nil end
	return current + 1
end

-- GetTechLevel(techId, level) -> { cost, Desc, Effect } (or nil)
-- Returns the effect record for ONE tier of a tech.
function TechConfig.GetTechLevel(techId, level)
	local tech = TechConfig.GetTech(techId)
	if not tech then return nil end
	local tier = tonumber(level) or 0
	return tech.Levels and tech.Levels[tier] or nil
end

-- GetLevelCost(techId, targetLevel) -> number (BaseCost * tier)
-- Cost is always BaseCost x tier (Bronze x1, Silver x2, Gold x3).
function TechConfig.GetLevelCost(techId, targetLevel)
	local tech = TechConfig.GetTech(techId)
	if not tech then return 0 end
	local tier = tonumber(targetLevel) or 0
	return math.floor(math.max(0, tech.BaseCost * tier))
end

-- GetTechEffect(techId, level) -> machine readable effect table (or nil)
function TechConfig.GetTechEffect(techId, level)
	local lvl = TechConfig.GetTechLevel(techId, level)
	return lvl and lvl.Effect or nil
end

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
	table.sort(result, function(a, b) return a.BaseCost < b.BaseCost end)
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
