--[[
    VictoryConfig (ModuleScript)
    Ort: ReplicatedStorage > VictoryConfig

    Geteilte Konstanten fuer das Victory-System.
    Server (PointSystem/VictorySystem) und Client (GUIs) lesen daraus.

    REGELN:
        SOLO_WIN_POINTS       -> Punkte-Sieg fuer einen alleinstehenden Spieler
        ALLIANCE_WIN_POINTS   -> Punkte-Sieg fuer eine Allianz (Summe aller Mitglieder)
        MAX_ALLIANCE_MEMBERS  -> Max. 3 Mitglieder pro Allianz

    PUNKTE:
        PASSIVE_POINTS  - jede Runde am Rundenende (City/Camp/Provinz)
        ACTIVE_POINTS   - einmalig bei Ereignis
        LOSS_POINTS     - einmaliger Verlust bei Verlust
--]]

local VictoryConfig = {}

--------------------------------------------------------------------------------
-- SIEG-SCHWELLEN
--------------------------------------------------------------------------------
VictoryConfig.SOLO_WIN_POINTS      = 1000
VictoryConfig.ALLIANCE_WIN_POINTS  = 1500
VictoryConfig.MAX_ALLIANCE_MEMBERS = 3

--------------------------------------------------------------------------------
-- PASSIVE PUNKTE (pro Runde, am Rundenende)
--------------------------------------------------------------------------------
VictoryConfig.PASSIVE_POINTS = {
	City     = 10,
	Camp     = 3,
	Province = 1,
}

--------------------------------------------------------------------------------
-- AKTIVE PUNKTE (einmalig bei Ereignis)
--------------------------------------------------------------------------------
VictoryConfig.ACTIVE_POINTS = {
	CityFounded      = 75,
	ArmyDefeated     = 25,
	CityConquered    = 100,
	PlayerEliminated = 150,
	GoldTech         = 40,
	CampBuilt        = 25,
	ProvinceClaimed  = 15,

	-- NEU: Stadt-Besetzung mit Buergerwehr (siehe MovementHandler/CombatSystem).
	-- Getrennt von CityConquered/CityLost, da dieser Belagerungs-Ablauf ein
	-- eigenstaendiges Feature mit eigenen, explizit vorgegebenen Werten ist.
	CitySiegeWon     = 100,  -- Angreifer erobert eine belagerte Stadt/Camp
	CityDefended     = 25,   -- Verteidiger wehrt eine Belagerung erfolgreich ab
}

--------------------------------------------------------------------------------
-- VERLUST-PUNKTE (einmaliger Abzug, nie unter 0)
--------------------------------------------------------------------------------
VictoryConfig.LOSS_POINTS = {
	CityLost     = 75,
	CampLost     = 25,
	ProvinceLost = 10,

	-- NEU: Gegenstueck zu CitySiegeWon (Stadt-Besetzung mit Buergerwehr).
	CitySiegeLost = 100,
}

return VictoryConfig
