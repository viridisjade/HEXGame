--[[
    FogOfWarConfig (ModuleScript)
    Ort: ReplicatedStorage > FogOfWarConfig

    Konstanten fuer das Fog-of-War-System.
    Geteilt zwischen Server (FogOfWarSystem/FogOfWarData) und Client
    (FogOfWarController).

    SICHT-ZUSTAENDE PRO HEX & SPIELER
        unexplored  - nicht erkundet: alles unsichtbar
        explored    - erkundet: Terrain/Soil/Province 50% transparent,
                      Gebaeude und Units UNSICHTBAR (Transparency = 1)
        visible     - aktuell sichtbar: alles voll, Units sichtbar

    SICHTQUELLEN (Reichweite in Hexfeldern):
        Tribe          = UnitConfig.Stats.Sight (4)
        StonespearF.   = UnitConfig.Stats.Sight (3)
        StoneWarrior   = UnitConfig.Stats.Sight (3)
        Rider          = UnitConfig.Stats.Sight (5)
        Camp           = CAMP_SIGHT   (2)
        City           = CITY_SIGHT   (3)
        Bastion        = BASTION_SIGHT (4)
--]]

local FogOfWarConfig = {}

--------------------------------------------------------------------------------
-- SICHT-REICHWEITEN DER GEBÄUDE (Units nutzen UnitConfig.Stats.Sight)
--------------------------------------------------------------------------------
FogOfWarConfig.CAMP_SIGHT    = 2
FogOfWarConfig.CITY_SIGHT    = 3
FogOfWarConfig.BASTION_SIGHT = 4

--------------------------------------------------------------------------------
-- SICHT-ZUSTÄNDE (kanonische Werte)
--------------------------------------------------------------------------------
FogOfWarConfig.STATE = {
	UNEXPLORED = "unexplored",
	EXPLORED   = "explored",
	VISIBLE    = "visible",
}

--------------------------------------------------------------------------------
-- BASEPLATE (neutrale graue/beige Farbe fuer die unerforschte Map)
--------------------------------------------------------------------------------
FogOfWarConfig.BASEPLATE_COLOR = Color3.fromRGB(180, 175, 165)

--------------------------------------------------------------------------------
-- TRANSPARENZEN
--------------------------------------------------------------------------------
FogOfWarConfig.EXPLORED_TRANSPARENCY = 0.5
FogOfWarConfig.VISIBLE_TRANSPARENCY  = 0.0

return FogOfWarConfig
