--[[
    MapConfig (ModuleScript)
    Ort: ServerScriptService > MapConfig
    
    Zentrale Konfiguration für die Weltgenerierung.
    Alle Einstellungen an einem Ort – einfach anzupassen!
    
    Wird von TerrainGenerator und SoilGenerator verwendet.
--]]

local MapConfig = {}

--------------------------------------------------------------------------------
-- MAP GRÖSSE
--------------------------------------------------------------------------------
MapConfig.MapSize = {
	WIDTH = 60,                      -- Anzahl Hexes horizontal
	HEIGHT = 40,                     -- Anzahl Hexes vertikal
}

--------------------------------------------------------------------------------
-- LAND / WASSER BALANCE
-- Bestimmt wie viel der Karte Land vs Wasser ist
--------------------------------------------------------------------------------
MapConfig.LandWater = {
	-- Hauptschwelle: niedriger = mehr Land, höher = mehr Wasser
	-- Bereich: 0.0 (alles Land) bis 0.5 (halb/halb) bis 1.0 (alles Wasser)
	WATER_AMOUNT = 0.32,

	-- Randmaske: erzwingt Wasser am Kartenrand
	USE_EDGE_OCEAN = true,           -- Ozean am Rand?
	EDGE_OCEAN_STRENGTH = 0.35,      -- 0 = kein Rand-Ozean, 1 = starker Rand-Ozean
}

--------------------------------------------------------------------------------
-- SEEN (kleine Wasserflächen im Landesinneren)
--------------------------------------------------------------------------------
MapConfig.Lakes = {
	ENABLED = true,                  -- Seen aktivieren?

	-- Wie häufig Seen erscheinen
	-- Bereich: 0.5 (sehr viele) bis 0.95 (sehr wenige)
	FREQUENCY = 0.82,

	-- Größe der Seen: kleiner = größere zusammenhängende Seen
	-- Bereich: 0.1 (riesige Seen) bis 0.5 (winzige Tümpel)
	SIZE_VARIATION = 0.18,
}

--------------------------------------------------------------------------------
-- TERRAIN VERTEILUNG (Ebenen)
--------------------------------------------------------------------------------
MapConfig.Terrain = {
	-- Ebene2 vs Ebene1: höher = mehr Ebene2
	-- Bereich: 0.3 (fast alles Ebene2) bis 0.7 (fast alles Ebene1)
	PLAIN2_AMOUNT = 0.48,
}

--------------------------------------------------------------------------------
-- GEBIRGE (Ebene3)
--------------------------------------------------------------------------------
MapConfig.Mountains = {
	-- Wie häufig Gebirge erscheinen
	-- Bereich: 0.4 (sehr viele Berge) bis 0.8 (sehr wenige Berge)
	FREQUENCY = 0.61,

	-- Zerstreuung: wie "aufgebrochen" die Bergketten sind
	-- Bereich: 0.0 (große zusammenhängende Ketten) bis 1.0 (viele kleine Gruppen)
	SCATTER = 0.7,

	-- Cluster-Größe: kleiner = kleinere Berggruppen
	-- Bereich: 0.05 (winzige Gruppen) bis 0.2 (große Massive)
	CLUSTER_SIZE = 0.10,
}

--------------------------------------------------------------------------------
-- BERGSPITZEN (Ebene4)
--------------------------------------------------------------------------------
MapConfig.Peaks = {
	-- Wie selten Bergspitzen sind
	-- Bereich: 0.6 (häufig) bis 0.95 (extrem selten)
	RARITY = 0.88,
}

--------------------------------------------------------------------------------
-- WALD (Forest Soil)
--------------------------------------------------------------------------------
MapConfig.Forest = {
	-- Wie viel der Landfläche bewaldet ist
	-- Bereich: 0.3 (sehr viel Wald) bis 0.7 (wenig Wald)
	COVERAGE = 0.54,

	-- Cluster-Größe: kleiner = kleinere Waldgruppen
	-- Bereich: 0.03 (winzige Wäldchen) bis 0.15 (große Wälder)
	CLUSTER_SIZE = 0.065,

	-- Wie viele vereinzelte Bäume außerhalb der Cluster
	-- Bereich: 0.5 (keine) bis 0.9 (viele Einzelbäume)
	SCATTER_TREES = 0.72,
}

--------------------------------------------------------------------------------
-- GRAS / TROCKENES GRAS
--------------------------------------------------------------------------------
MapConfig.Grass = {
	-- Balance zwischen Grassland und DryGrass auf Ebene1
	-- Bereich: 0.3 (viel DryGrass) bis 0.8 (fast nur Grassland)
	EBENE1_GREEN = 0.62,

	-- Balance auf Ebene2 (typischerweise trockener)
	EBENE2_GREEN = 0.35,

	-- Balance auf Ebene3
	EBENE3_GREEN = 0.50,
}

--------------------------------------------------------------------------------
-- FELSEN (Rocks Soil auf Ebene3)
--------------------------------------------------------------------------------
MapConfig.Rocks = {
	-- Wie häufig Felsen auf Gebirge erscheinen
	-- Bereich: 0.2 (wenige Felsen) bis 0.7 (fast alles Felsen)
	COVERAGE = 0.42,

	-- Bonus wenn Bergspitze (Ebene4) angrenzt
	PEAK_BONUS = 0.25,
}

--------------------------------------------------------------------------------
-- PROVINZEN
-- Regeln für die Provinz-Einteilung
--------------------------------------------------------------------------------
MapConfig.Provinces = {
	-- Anzahl der LAND-Provinzen
	-- Höhere Zahl = mehr aber kleinere Provinzen
	-- Niedrigere Zahl = weniger aber größere Provinzen
	-- Beispiele: 6 = große Reiche, 12 = mittel, 24 = viele kleine
	-- Ozean-Provinzen kommen zusätzlich automatisch dazu.
	LAND_PROVINCE_COUNT = 24,

	-- Wie viel Wasser eine Land-Provinz maximal enthalten soll
	-- 0.0 = kein Wasser, 0.25 = max 25% Wasser, 0.5 = max 50%
	MAX_WATER_RATIO = 0.22,

	-- Wie viele Wasser-Ringe um Land herum noch zu Land-Provinzen gehören dürfen
	-- 1 = nur Küste, 2 = Küste + etwas Ozean
	LAND_WATER_RINGS = 2,

	-- Seed-Platzierung für Land-Provinzen
	-- "grid" = gleichmäßig, "random" = zufällig
	SEED_PLACEMENT = "grid",
}

--------------------------------------------------------------------------------
-- WORLD GENERATION DETAIL
-- Fortgeschrittene Einstellungen für die Noise-Generierung
--------------------------------------------------------------------------------
MapConfig.Advanced = {
	-- Allgemeine Zerstreuung/Vielfalt der Landschaft
	-- Höhere Werte = mehr kleine Details, zerstreutere Features
	WORLD_DETAIL = 0.5,              -- 0.0 bis 1.0

	-- Noise-Oktaven Gewichtung
	LARGE_FEATURES_WEIGHT = 0.35,    -- Kontinente, große Landmassen
	MEDIUM_FEATURES_WEIGHT = 0.30,   -- Halbinseln, Buchten
	SMALL_FEATURES_WEIGHT = 0.20,    -- Küstenform, Details
	MICRO_FEATURES_WEIGHT = 0.15,    -- Kleine Inseln, Fjorde
}

--------------------------------------------------------------------------------
-- PRESETS
-- Vorgefertigte Konfigurationen für verschiedene Welten
--------------------------------------------------------------------------------

-- Archipelago: Viele kleine Inseln
MapConfig.Presets = {}

MapConfig.Presets.Archipelago = function()
	MapConfig.LandWater.WATER_AMOUNT = 0.42
	MapConfig.LandWater.EDGE_OCEAN_STRENGTH = 0.2
	MapConfig.Lakes.FREQUENCY = 0.75
	MapConfig.Mountains.SCATTER = 0.9
	MapConfig.Mountains.CLUSTER_SIZE = 0.08
	MapConfig.Advanced.MICRO_FEATURES_WEIGHT = 0.25
end

-- Kontinental: Große zusammenhängende Landmassen
MapConfig.Presets.Continental = function()
	MapConfig.LandWater.WATER_AMOUNT = 0.28
	MapConfig.LandWater.EDGE_OCEAN_STRENGTH = 0.5
	MapConfig.Lakes.FREQUENCY = 0.88
	MapConfig.Mountains.SCATTER = 0.4
	MapConfig.Mountains.CLUSTER_SIZE = 0.15
	MapConfig.Advanced.LARGE_FEATURES_WEIGHT = 0.45
end

-- Gebirgig: Viele Berge und Bergspitzen
MapConfig.Presets.Mountainous = function()
	MapConfig.Mountains.FREQUENCY = 0.50
	MapConfig.Mountains.SCATTER = 0.5
	MapConfig.Peaks.RARITY = 0.78
	MapConfig.Rocks.COVERAGE = 0.55
end

-- Bewaldet: Dichte Wälder überall
MapConfig.Presets.Forested = function()
	MapConfig.Forest.COVERAGE = 0.42
	MapConfig.Forest.CLUSTER_SIZE = 0.10
	MapConfig.Forest.SCATTER_TREES = 0.60
	MapConfig.Grass.EBENE1_GREEN = 0.75
end

-- Trocken: Wenig Wasser, viel DryGrass
MapConfig.Presets.Arid = function()
	MapConfig.LandWater.WATER_AMOUNT = 0.22
	MapConfig.Lakes.ENABLED = false
	MapConfig.Grass.EBENE1_GREEN = 0.40
	MapConfig.Grass.EBENE2_GREEN = 0.25
	MapConfig.Forest.COVERAGE = 0.68
end

return MapConfig
