--[[
    DiplomacyConfig (ModuleScript)
    Ort: ReplicatedStorage > DiplomacyConfig

    Konstanten fuer das Diplomatie-System.
    Geteilt zwischen Server (DiplomacyData/DiplomacySystem), Client-GUIs
    (DiplomacyGuiController, NotificationGuiController) und Empire-Overlay.

    BEZIEHUNGSSTUFEN
        Allied   -> Verbündet: keine Kämpfe, Armeen koexistieren
        Neutral  -> Standard: alles möglich
        War      -> Krieg: aktive Kämpfe erlaubt

    ANGEBOTS-TYPEN
        Alliance -> Bündnis (Neutral -> Verbündet, Zustimmung beider)
        Peace    -> Frieden (Krieg -> Neutral, Zustimmung beider)

    BENACHRICHTIGUNGSTYPEN
        Offer     (Typ 1, interaktiv, blau)   Angebot eingegangen
        War       (Typ 2, dringend, rot)      Kriegserklaerung
        Accepted  (Typ 3, positiv, gruen)     Angebot angenommen
        Declined  (Typ 4, negativ, orange)    Angebot abgelehnt
        Expired   (Typ 5, info, grau)         Angebot abgelaufen
        Broken    (Typ 6, warnung, dunkelrot) Buendnis gebrochen
--]]

local DiplomacyConfig = {}

--------------------------------------------------------------------------------
-- BEZIEHUNGSSTUFEN
--------------------------------------------------------------------------------
DiplomacyConfig.RELATION_STATES = { "Allied", "Neutral", "War" }

DiplomacyConfig.STATE = {
	ALLIED  = "Allied",
	NEUTRAL = "Neutral",
	WAR     = "War",
}

-- Alte Keys (fuer Kompatibilitaet mit bestehendem Code). Mapping zu neuem Modell.
DiplomacyConfig.LEGACY_MAP = {
	peace = "Allied",
	war   = "War",
}

--------------------------------------------------------------------------------
-- ANGEBOT
--------------------------------------------------------------------------------
-- Zeitlimit in Runden fuer nicht beantwortete Angebote.
DiplomacyConfig.OFFER_TIMEOUT_ROUNDS = 3

DiplomacyConfig.OFFER = {
	ALLIANCE = "Alliance",
	PEACE    = "Peace",
}

-- Ein Angebot gilt nur aus bestimmter Ausgangslage.
DiplomacyConfig.OFFER_ALLOWED_FROM = {
	Alliance = "Neutral",  -- Buendnis nur aus Neutral
	Peace    = "War",      -- Frieden nur aus Krieg
}

--------------------------------------------------------------------------------
-- BENACHRICHTIGUNG
--------------------------------------------------------------------------------
DiplomacyConfig.NOTIFY = {
	OFFER    = "Offer",
	WAR      = "War",
	ACCEPTED = "Accepted",
	DECLINED = "Declined",
	EXPIRED  = "Expired",
	BROKEN   = "Broken",
}

-- Auto-Dismiss-Dauern in Sekunden (Typ 1 bleibt bis Reaktion/Ablauf).
DiplomacyConfig.DISMISS = {
	Offer    = nil,      -- bleibt bis Reaktion oder Ablauf (3 Runden)
	War      = 10,
	Accepted = 5,
	Declined = 5,
	Expired  = 5,
	Broken   = 8,
}

-- Maximale gleichzeitig sichtbare Banner.
DiplomacyConfig.MAX_BANNERS = 4

--------------------------------------------------------------------------------
-- FARBEN
--------------------------------------------------------------------------------
DiplomacyConfig.COLOR = {
	Offer    = Color3.fromRGB(45, 90, 160),      -- blau
	War      = Color3.fromRGB(180, 40, 40),      -- rot
	Broken   = Color3.fromRGB(120, 20, 20),      -- dunkelrot
	Accepted = Color3.fromRGB(40, 130, 60),      -- gruen
	Declined = Color3.fromRGB(200, 120, 30),     -- orange
	Expired  = Color3.fromRGB(110, 110, 120),    -- grau
}

return DiplomacyConfig
