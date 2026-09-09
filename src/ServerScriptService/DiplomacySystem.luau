--[[
    DiplomacySystem (ModuleScript)
    Ort: ServerScriptService > DiplomacySystem

    Diplomatie-Regeln + Benachrichtigungs-Events.

    BEZIEHUNGSSTUFEN (3)
        Alliance -> Allianz: keine Kämpfe, Armeen koexistieren
        Neutral  -> Standard: alles möglich
        War      -> Krieg: aktive Kämpfe erlaubt
        Start jeder Paarung ist Neutral.

    AKTIONEN
        SendAllianceOffer(from, to)  Neutral->Allianz (Zustimmung beider)
        SendPeaceOffer(from, to)     Krieg->Neutral     (Zustimmung beider)
        RespondOffer(player, ...)    Angebot annehmen/ablehnen
        DeclareWar(from, to)         einseitig auf Krieg (auch aus Allianz)
        BreakAlliance(from, to)      einseitig Allianz->Neutral

    BENACHRICHTIGUNGS-EVENTS (Server -> Client)
        DiplomacyNotification wird an den betroffenen Spieler gefeuert.
        DiplomacyUpdate wird an ALLE Spieler gefeuert (Status-Refresh).

    KOMPATIBILITAET (alte API bleibt):
        AreAllied  -> true nur bei "Alliance"
        IsAtWar    -> true bei "War" ODER "Neutral" (alles ausser Allianz)
        GetRelation/DeclareWar/MakePeace/ClearPlayer
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local DiplomacyConfig = require(ReplicatedStorage:WaitForChild("DiplomacyConfig"))
local VictoryConfig = require(ReplicatedStorage:WaitForChild("VictoryConfig"))
local DiplomacyData = require(script.Parent:WaitForChild("DiplomacyData"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local DiplomacySystem = {}

local dataRemotes = ReplicatedStorage:WaitForChild("DataRemotes", 30)

local function remote(name)
	return dataRemotes and dataRemotes:FindFirstChild(name) or nil
end

local function StateName(state)
	if state == DiplomacyConfig.STATE.ALLIANCE then return "Allianz" end
	if state == DiplomacyConfig.STATE.WAR then return "Krieg" end
	return "Neutral"
end

--------------------------------------------------------------------------------
-- ALLIANZ-GRUPPEN (max. MAX_ALLIANCE_MEMBERS Mitglieder, geteilte Punkte)
--------------------------------------------------------------------------------
local function allianceMembers(allianceId)
	local members = {}
	if not allianceId then return members end
	for _, player in ipairs(Players:GetPlayers()) do
		if not PlayerData.IsEliminated(player)
			and PlayerData.GetAllianceId(player) == allianceId then
			table.insert(members, player)
		end
	end
	return members
end

function DiplomacySystem.GetAllianceMembers(player)
	if not player then return {} end
	return allianceMembers(PlayerData.GetAllianceId(player))
end

-- Anzahl der Mitglieder in der Allianz, die der Spieler (bei Beitritt) hätte.
function DiplomacySystem.GetAllianceSize(player)
	if not player then return 0 end
	local id = PlayerData.GetAllianceId(player)
	if not id then return 1 end  -- nur der Spieler selbst (solo)
	return #allianceMembers(id)
end

-- Gesamtgroesse, wenn from und to in EINE Allianz zusammengefuehrt wuerden.
local function combinedAllianceSize(from, to)
	local idA = PlayerData.GetAllianceId(from)
	local idB = PlayerData.GetAllianceId(to)
	if idA and idA == idB then return #allianceMembers(idA) end

	local count = 1 -- from
	if idA then count = #allianceMembers(idA) end
	if idB then
		local b = #allianceMembers(idB)
		if idB ~= idA then count += b end
	end
	if not idA and not idB then return 2 end
	return count
end

-- Loesst eine Allianzgruppe auf, wenn nur noch <2 nicht-eliminierte Mitglieder
-- uebrig sind. Gibt true zurueck, wenn aufgeloest wurde.
function DiplomacySystem.CollapseAllianceGroup(allianceId)
	if not allianceId then return false end
	local members = allianceMembers(allianceId)
	if #members >= 2 then return false end
	for _, p in ipairs(allianceMembers(allianceId)) do
		PlayerData.SetAllianceId(p, nil)
	end
	print(("[Diplomacy] Allianz %s aufgeloest (nur %d Mitglied)"):format(tostring(allianceId), #members))
	return true
end

-- Scannt alle Allianzgruppen und loest Gruppen mit <2 Mitgliedern auf.
function DiplomacySystem.CleanupAlliances()
	local seen = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if not PlayerData.IsEliminated(player) then
			local id = PlayerData.GetAllianceId(player)
			if id and not seen[id] then
				seen[id] = true
				DiplomacySystem.CollapseAllianceGroup(id)
			end
		end
	end
end

-- Fuehrt die Allianz-Gruppen von from und to zusammen (mit Max-3-Check).
local function mergeAlliances(from, to)
	if not from or not to then return false, "Ungültige Spieler" end

	local maxMembers = VictoryConfig.MAX_ALLIANCE_MEMBERS
	local idA = PlayerData.GetAllianceId(from)
	local idB = PlayerData.GetAllianceId(to)

	if idA and idA == idB then return true end

	-- Max-3-Check fuer die kombinierte Gruppe.
	if combinedAllianceSize(from, to) > maxMembers then
		return false, ("Allianz ist voll (%d/%d)"):format(maxMembers, maxMembers)
	end

	-- Ziel-Id waehlen: vorhandene Id bevorzugen, sonst neu erzeugen.
	local targetId = idA or idB
	if not targetId then
		targetId = "alliance_" .. tostring(os.time()) .. "_" .. tostring(math.random(100000, 999999))
	end

	-- Allen Mitgliedern beider Gruppen die Ziel-Id zuweisen.
	local merged = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local pid = PlayerData.GetAllianceId(p)
		if pid == idA or pid == idB then
			table.insert(merged, p)
		end
	end
	-- Solospieler (fals sie nil id haben) ebenfalls zuordnen.
	for _, p in ipairs({ from, to }) do
		if not PlayerData.GetAllianceId(p) then
			table.insert(merged, p)
		end
	end

	for _, p in ipairs(merged) do
		PlayerData.SetAllianceId(p, targetId)
	end

	print(("[Diplomacy] Allianz %s: %d Mitglieder"):format(tostring(targetId), #merged))
	return true
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
	-- Laufende Allianz-/Friedensangebote zwischen den beiden entfernen.
	DiplomacyData.ClearOfferBetween(playerA, playerB, nil)

	print(("[Diplomacy] Krieg: %s erklärte %s den Krieg"):format(playerA.Name, playerB.Name))

	-- Wenn aus einer Allianz heraus Krieg erklaert wird, loest sich die Allianz
	-- fuer die beiden Beteiligten auf.
	if prev == DiplomacyConfig.STATE.ALLIANCE then
		PlayerData.SetAllianceId(playerA, nil)
		PlayerData.SetAllianceId(playerB, nil)
		DiplomacySystem.CleanupAlliances()
	end

	-- Benachrichtigungen an beide.
	if prev == DiplomacyConfig.STATE.ALLIANCE then
		-- Allianzbruch (Typ 6, dunkelrot) an den betroffenen Allianzmitglied.
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
-- ALLIANZ AUFLÖSEN (einseitig: Allianz -> Neutral)
--------------------------------------------------------------------------------
function DiplomacySystem.BreakAlliance(playerA, playerB)
	if not playerA or not playerB or playerA == playerB then return false, "Ungültige Spieler" end
	local prev = DiplomacyData.GetRelation(playerA, playerB)
	if prev ~= DiplomacyConfig.STATE.ALLIANCE then
		return false, "Keine Allianz"
	end
	DiplomacyData.SetRelation(playerA, playerB, DiplomacyConfig.STATE.NEUTRAL)
	DiplomacyData.ClearOfferBetween(playerA, playerB, nil)
	-- Die beiden verlassen die Allianzgruppe (verbleibende Mitglieder bleiben).
	PlayerData.SetAllianceId(playerA, nil)
	PlayerData.SetAllianceId(playerB, nil)
	DiplomacySystem.CleanupAlliances()
	print(("[Diplomacy] Allianz aufgelöst: %s - %s"):format(playerA.Name, playerB.Name))

	broadcastState(playerA)
	broadcastState(playerB)
	return true
end

--------------------------------------------------------------------------------
-- ANGEBOT SENDEN (Allianz aus Neutral, Frieden aus Krieg)
--------------------------------------------------------------------------------
function DiplomacySystem.SendAllianceOffer(from, to)
	if not from or not to or from == to then return false, "Ungültige Spieler" end
	local state = DiplomacyData.GetRelation(from, to)
	if state ~= DiplomacyConfig.STATE.NEUTRAL then
		return false, "Allianz nur aus Neutral möglich"
	end
	if DiplomacyData.FindOffer(from, to, DiplomacyConfig.OFFER.ALLIANCE) then
		return false, "Angebot bereits gesendet"
	end
	-- Max-3-Check: Wenn der Empfaenger bereits eine volle Allianz hat (oder die
	-- kombinierte Gruppe > MAX waere), wird der Antrag sofort abgelehnt.
	local maxMembers = VictoryConfig.MAX_ALLIANCE_MEMBERS
	if combinedAllianceSize(from, to) > maxMembers then
		local reasonText = ("Allianz ist voll (%d/%d)"):format(maxMembers, maxMembers)
		notify(from, {
			targetPlayerId = from.UserId,
			type = DiplomacyConfig.NOTIFY.DECLINED,
			fromPlayerName = to.Name,
			offerType = DiplomacyConfig.OFFER.ALLIANCE,
			declineReason = reasonText,
		})
		return false, reasonText
	end
	local offer = DiplomacyData.AddOffer(from, to, DiplomacyConfig.OFFER.ALLIANCE)
	print(("[Diplomacy] Allianzantrag: %s -> %s"):format(from.Name, to.Name))

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
		-- Max-3-Check beim ANNEHMEN: falls die Gruppe inzwischen voll ist, ablehnen.
		local maxMembers = VictoryConfig.MAX_ALLIANCE_MEMBERS
		if combinedAllianceSize(from, player) > maxMembers then
			local reasonText = ("Allianz ist voll (%d/%d)"):format(maxMembers, maxMembers)
			notify(from, {
				targetPlayerId = from.UserId,
				type = DiplomacyConfig.NOTIFY.DECLINED,
				fromPlayerName = player.Name,
				offerType = offerType,
				offerId = offerId,
				otherUserId = player.UserId,
				roundsLeft = nil,
				declineReason = reasonText,
			})
			broadcastState(from)
			broadcastState(player)
			return false, reasonText
		end
		DiplomacyData.SetRelation(from, player, DiplomacyConfig.STATE.ALLIANCE)
		-- Beide in EINE Allianzgruppe zusammenfuehren (geteilte Punkte).
		pcall(mergeAlliances, from, player)
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

-- Nur Allianz-Mitglieder koexistieren ohne Kampf.
function DiplomacySystem.AreInAlliance(playerA, playerB)
	if playerA == nil or playerB == nil then return false end
	if playerA == playerB then return true end
	return DiplomacyData.GetRelation(playerA, playerB) == DiplomacyConfig.STATE.ALLIANCE
end

-- "Im Krieg"/blockierend: alles ausser Allianz (Neutral + War).
-- MovementSystem blockiert Bewegung auf Feind-/Neutral-Hexe.
function DiplomacySystem.IsAtWar(playerA, playerB)
	if playerA == nil or playerB == nil then return true end
	if playerA == playerB then return false end
	local state = DiplomacyData.GetRelation(playerA, playerB)
	return state ~= DiplomacyConfig.STATE.ALLIANCE
end

-- Kompatibilitaet: alte Namen als Alias.
function DiplomacySystem.AreAllied(playerA, playerB)
	return DiplomacySystem.AreInAlliance(playerA, playerB)
end

function DiplomacySystem.IsAllied(playerA, playerB)
	return DiplomacySystem.AreInAlliance(playerA, playerB)
end

function DiplomacySystem.IsInAlliance(playerA, playerB)
	return DiplomacySystem.AreInAlliance(playerA, playerB)
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
