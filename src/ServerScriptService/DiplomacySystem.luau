--[[
    DiplomacySystem (ModuleScript)
    Ort: ServerScriptService > DiplomacySystem

    Diplomatie-Regeln + Benachrichtigungs-Events.

    BEZIEHUNGSSTUFEN (3)
        Allied   -> Verbündet: keine Kämpfe, Armeen koexistieren
        Neutral  -> Standard: alles möglich
        War      -> Krieg: aktive Kämpfe erlaubt
        Start jeder Paarung ist Neutral.

    AKTIONEN
        SendAllianceOffer(from, to)  Neutral->Verbündet (Zustimmung beider)
        SendPeaceOffer(from, to)     Krieg->Neutral     (Zustimmung beider)
        RespondOffer(player, ...)    Angebot annehmen/ablehnen
        DeclareWar(from, to)         einseitig auf Krieg (auch aus Verbündet)
        BreakAlliance(from, to)      einseitig Verbündet->Neutral

    BENACHRICHTIGUNGS-EVENTS (Server -> Client)
        DiplomacyNotification wird an den betroffenen Spieler gefeuert.
        DiplomacyUpdate wird an ALLE Spieler gefeuert (Status-Refresh).

    KOMPATIBILITAET (alte API bleibt):
        AreAllied  -> true nur bei "Allied"
        IsAtWar    -> true bei "War" ODER "Neutral" (alles ausser Verbündet)
        GetRelation/DeclareWar/MakePeace/ClearPlayer
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DiplomacyConfig = require(ReplicatedStorage:WaitForChild("DiplomacyConfig"))
local DiplomacyData = require(script.Parent:WaitForChild("DiplomacyData"))

local DiplomacySystem = {}

local dataRemotes = ReplicatedStorage:WaitForChild("DataRemotes", 30)

local function remote(name)
	return dataRemotes and dataRemotes:FindFirstChild(name) or nil
end

local function StateName(state)
	if state == DiplomacyConfig.STATE.ALLIED then return "Verbündet" end
	if state == DiplomacyConfig.STATE.WAR then return "Krieg" end
	return "Neutral"
end

--------------------------------------------------------------------------------
-- Benachrichtigung + Status-Update
--------------------------------------------------------------------------------
local function notify(player, payload)
	if not player then return end
	local rem = remote("DiplomacyNotification")
	if not rem then return end
	pcall(function()
		rem:FireClient(player, payload)
	end)
end

local function broadcastState(player)
	if not player then return end
	local rem = remote("DiplomacyUpdate")
	if not rem then return end
	pcall(function()
		rem:FireClient(player, {
			relations = DiplomacyData.GetRelationsByPlayer(player),
			pendingOffers = DiplomacyData.GetOffersFor(player),
		})
	end)
end

--------------------------------------------------------------------------------
-- KRIEGSERKLÄRUNG (einseitig, aus jeder Stufe)
--------------------------------------------------------------------------------
function DiplomacySystem.DeclareWar(playerA, playerB)
	if not playerA or not playerB or playerA == playerB then return false, "Ungültige Spieler" end

	local prev = DiplomacyData.GetRelation(playerA, playerB)
	DiplomacyData.SetRelation(playerA, playerB, DiplomacyConfig.STATE.WAR)
	-- Laufende Buendnis-/Friedensangebote zwischen den beiden entfernen.
	DiplomacyData.ClearOfferBetween(playerA, playerB, nil)

	print(("[Diplomacy] Krieg: %s erklärte %s den Krieg"):format(playerA.Name, playerB.Name))

	-- Benachrichtigungen an beide.
	if prev == DiplomacyConfig.STATE.ALLIED then
		-- Buendnisbruch (Typ 6, dunkelrot) an den betroffenen Verbündeten.
		notify(playerB, {
			targetPlayerId = playerB.UserId,
			type = DiplomacyConfig.NOTIFY.BROKEN,
			fromPlayerName = playerA.Name,
			offerType = nil,
			roundsLeft = nil,
		})
	else
		-- Kriegserklaerung (Typ 2, rot).
		notify(playerB, {
			targetPlayerId = playerB.UserId,
			type = DiplomacyConfig.NOTIFY.WAR,
			fromPlayerName = playerA.Name,
			offerType = nil,
			roundsLeft = nil,
		})
	end

	-- Status fuer beide refreshen.
	broadcastState(playerA)
	broadcastState(playerB)
	return true
end

--------------------------------------------------------------------------------
-- BÜNDNIS AUFLÖSEN (einseitig: Verbündet -> Neutral)
--------------------------------------------------------------------------------
function DiplomacySystem.BreakAlliance(playerA, playerB)
	if not playerA or not playerB or playerA == playerB then return false, "Ungültige Spieler" end
	local prev = DiplomacyData.GetRelation(playerA, playerB)
	if prev ~= DiplomacyConfig.STATE.ALLIED then
		return false, "Kein Bündnis"
	end
	DiplomacyData.SetRelation(playerA, playerB, DiplomacyConfig.STATE.NEUTRAL)
	DiplomacyData.ClearOfferBetween(playerA, playerB, nil)
	print(("[Diplomacy] Bündnis aufgelöst: %s - %s"):format(playerA.Name, playerB.Name))

	broadcastState(playerA)
	broadcastState(playerB)
	return true
end

--------------------------------------------------------------------------------
-- ANGEBOT SENDEN (Bündnis aus Neutral, Frieden aus Krieg)
--------------------------------------------------------------------------------
function DiplomacySystem.SendAllianceOffer(from, to)
	if not from or not to or from == to then return false, "Ungültige Spieler" end
	local state = DiplomacyData.GetRelation(from, to)
	if state ~= DiplomacyConfig.STATE.NEUTRAL then
		return false, "Bündnis nur aus Neutral möglich"
	end
	if DiplomacyData.FindOffer(from, to, DiplomacyConfig.OFFER.ALLIANCE) then
		return false, "Angebot bereits gesendet"
	end
	local offer = DiplomacyData.AddOffer(from, to, DiplomacyConfig.OFFER.ALLIANCE)
	print(("[Diplomacy] Bündnisangebot: %s -> %s"):format(from.Name, to.Name))

	notify(to, {
		targetPlayerId = to.UserId,
		type = DiplomacyConfig.NOTIFY.OFFER,
		fromPlayerName = from.Name,
		offerType = DiplomacyConfig.OFFER.ALLIANCE,
		offerId = offer.offerId,
		otherUserId = from.UserId,
		roundsLeft = offer.roundsLeft,
	})
	broadcastState(from)
	broadcastState(to)
	return true
end

function DiplomacySystem.SendPeaceOffer(from, to)
	if not from or not to or from == to then return false, "Ungültige Spieler" end
	local state = DiplomacyData.GetRelation(from, to)
	if state ~= DiplomacyConfig.STATE.WAR then
		return false, "Frieden nur im Krieg möglich"
	end
	if DiplomacyData.FindOffer(from, to, DiplomacyConfig.OFFER.PEACE) then
		return false, "Angebot bereits gesendet"
	end
	local offer = DiplomacyData.AddOffer(from, to, DiplomacyConfig.OFFER.PEACE)
	print(("[Diplomacy] Friedensangebot: %s -> %s"):format(from.Name, to.Name))

	notify(to, {
		targetPlayerId = to.UserId,
		type = DiplomacyConfig.NOTIFY.OFFER,
		fromPlayerName = from.Name,
		offerType = DiplomacyConfig.OFFER.PEACE,
		offerId = offer.offerId,
		otherUserId = from.UserId,
		roundsLeft = offer.roundsLeft,
	})
	broadcastState(from)
	broadcastState(to)
	return true
end

--------------------------------------------------------------------------------
-- ANGEBOT BEANTWORTEN
--------------------------------------------------------------------------------
function DiplomacySystem.RespondOffer(player, from, offerType, accept)
	if not player or not from then return false, "Ungültige Spieler" end

	local offer = DiplomacyData.FindOffer(from, player, offerType)
	if not offer then
		return false, "Kein Angebot gefunden"
	end

	local offerId = offer and offer.offerId or nil
	DiplomacyData.ClearOffer(offer)

	if not accept then
		-- Abgelehnt: Beziehungsstatus bleibt. (Typ 4)
		notify(from, {
			targetPlayerId = from.UserId,
			type = DiplomacyConfig.NOTIFY.DECLINED,
			fromPlayerName = player.Name,
			offerType = offerType,
			offerId = offerId,
			otherUserId = player.UserId,
			roundsLeft = nil,
		})
		broadcastState(from)
		broadcastState(player)
		return true, "abgelehnt"
	end

	if offerType == DiplomacyConfig.OFFER.ALLIANCE then
		DiplomacyData.SetRelation(from, player, DiplomacyConfig.STATE.ALLIED)
	elseif offerType == DiplomacyConfig.OFFER.PEACE then
		DiplomacyData.SetRelation(from, player, DiplomacyConfig.STATE.NEUTRAL)
	else
		return false, "Unbekannter Angebotstyp"
	end

	-- Angenommen: positives Banner an den Absender. (Typ 3)
	notify(from, {
		targetPlayerId = from.UserId,
		type = DiplomacyConfig.NOTIFY.ACCEPTED,
		fromPlayerName = player.Name,
		offerType = offerType,
		offerId = offerId,
		otherUserId = player.UserId,
		roundsLeft = nil,
	})
	print(("[Diplomacy] %s hat %s Angebot von %s angenommen"):format(
		player.Name, offerType, from.Name))

	broadcastState(from)
	broadcastState(player)
	return true, "angenommen"
end

--------------------------------------------------------------------------------
-- ABGELAUFENE ANGEBOTE (jede Runde)
-- Deaktiviert Angebote nach OFFER_TIMEOUT_ROUNDS Runden und feuert Typ-5.
--------------------------------------------------------------------------------
function DiplomacySystem.ProcessExpiredOffers()
	local expired = DiplomacyData.TickOffers()
	local count = 0
	for _, offer in pairs(expired) do
		count = count + 1
		notify(offer.from, {
			targetPlayerId = offer.from.UserId,
			type = DiplomacyConfig.NOTIFY.EXPIRED,
			fromPlayerName = offer.to.Name,
			offerType = offer.type,
			offerId = offer.offerId,
			otherUserId = offer.to.UserId,
			roundsLeft = nil,
		})
		broadcastState(offer.from)
		broadcastState(offer.to)
	end
	if count > 0 then
		print("[Diplomacy] " .. count .. " Angebot(e) abgelaufen.")
	end
	return count
end

--------------------------------------------------------------------------------
-- ABFRAGEN (Kompatibilität + neues Modell)
--------------------------------------------------------------------------------
function DiplomacySystem.GetRelation(playerA, playerB)
	return DiplomacyData.GetRelation(playerA, playerB)
end

function DiplomacySystem.StateName(state)
	return StateName(state)
end

-- Nur Verbündete koexistieren ohne Kampf.
function DiplomacySystem.AreAllied(playerA, playerB)
	if playerA == nil or playerB == nil then return false end
	if playerA == playerB then return true end
	return DiplomacyData.GetRelation(playerA, playerB) == DiplomacyConfig.STATE.ALLIED
end

-- "Im Krieg"/blockierend: alles ausser Verbündet (Neutral + War).
-- MovementSystem blockiert Bewegung auf Feind-/Neutral-Hexe.
function DiplomacySystem.IsAtWar(playerA, playerB)
	if playerA == nil or playerB == nil then return true end
	if playerA == playerB then return false end
	local state = DiplomacyData.GetRelation(playerA, playerB)
	return state ~= DiplomacyConfig.STATE.ALLIED
end

function DiplomacySystem.IsAllied(playerA, playerB)
	return DiplomacySystem.AreAllied(playerA, playerB)
end

function DiplomacySystem.IsNeutral(playerA, playerB)
	if playerA == playerB then return false end
	return DiplomacyData.GetRelation(playerA, playerB) == DiplomacyConfig.STATE.NEUTRAL
end

-- Zusammenfassung der Beziehungen eines Spielers (fuer das Empire-Overlay).
function DiplomacySystem.GetRelationsByPlayer(player)
	return DiplomacyData.GetRelationsByPlayer(player)
end

function DiplomacySystem.GetOffersFor(player)
	return DiplomacyData.GetOffersFor(player)
end

--------------------------------------------------------------------------------
-- CLEANUP
--------------------------------------------------------------------------------
function DiplomacySystem.ClearPlayer(player)
	DiplomacyData.ClearPlayer(player)
end

return DiplomacySystem
