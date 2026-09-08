--[[
    DiplomacyData (ModuleScript)
    Ort: ServerScriptService > DiplomacyData

    Zentraler Server-State fuer das Diplomatie-System. Haelt KEINE Spielregeln
    (die liegen in DiplomacySystem) - nur den Zustand:
        - Beziehungen zwischen Spieler-Paaren
        - Laufende (unbeantwortete) Angebote mit Timeout-Zaehler

    Beziehungs-Modell (3 Stufen):
        "Allied" | "Neutral" | "War"
    Start-Zustand jedes Paares ist "Neutral".

    Angebot-Struktur:
        {
            offerId  = number,
            from     = Player,
            to       = Player,
            type     = "Alliance" | "Peace",
            roundsLeft = number,   -- wird jede Runde dekrementiert
        }

    Kompatibilitaet: das alte DiplomacySystem nutzte "peace"/"war". Wir mappen
    altes "peace" -> "Allied", "war" -> "War". Aufrufer wie CombatSystem
    (AreAllied) und MovementSystem (IsAtWar) bleiben unveraendert.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DiplomacyConfig = require(ReplicatedStorage:WaitForChild("DiplomacyConfig"))

local DiplomacyData = {}

-- Zentraler State (alternativ koennte er in PlayerData liegen; hier zentral,
-- damit beide Seiten (Beziehung + Angebote) atomar zusammen bleiben).
local relations = {}        -- [keyA_B] = "Allied" | "Neutral" | "War"
local pendingOffers = {}    -- [offerId] = offer
local nextOfferId = 1

--------------------------------------------------------------------------------
-- KEYS
--------------------------------------------------------------------------------
local function keyFor(playerA, playerB)
	if not playerA or not playerB then return nil end
	local idA, idB = playerA.UserId, playerB.UserId
	if idA == idB then return nil end
	if idA > idB then idA, idB = idB, idA end
	return idA .. "_" .. idB
end

--------------------------------------------------------------------------------
-- OHNE LOGIK: Zugriff + Inline-Operationen
--------------------------------------------------------------------------------
function DiplomacyData.GetRelation(playerA, playerB)
	if not playerA or not playerB then return DiplomacyConfig.STATE.NEUTRAL end
	if playerA == playerB then return "self" end
	local key = keyFor(playerA, playerB)
	if not key then return DiplomacyConfig.STATE.NEUTRAL end
	local v = relations[key]
	-- Alte Werte kompatibel mappen.
	v = DiplomacyConfig.LEGACY_MAP[v] or v
	return v or DiplomacyConfig.STATE.NEUTRAL
end

function DiplomacyData.SetRelation(playerA, playerB, state)
	if state == DiplomacyConfig.STATE.NEUTRAL then
		return DiplomacyData.ClearRelation(playerA, playerB)
	end
	local key = keyFor(playerA, playerB)
	if not key then return false end
	relations[key] = state
	return true
end

function DiplomacyData.ClearRelation(playerA, playerB)
	local key = keyFor(playerA, playerB)
	if not key then return false end
	relations[key] = nil
	return true
end

-- Gibt alle Beziehungen eines Spielers als { [otherUserId] = state } zurueck.
function DiplomacyData.GetRelationsByPlayer(player)
	if not player then return {} end
	local id = player.UserId
	local result = {}
	for key, state in pairs(relations) do
		local a, b = key:match("^(%d+)_(%d+)$")
		if a then
			state = DiplomacyConfig.LEGACY_MAP[state] or state
			if tonumber(a) == id then
				result[tonumber(b)] = state
			elseif tonumber(b) == id then
				result[tonumber(a)] = state
			end
		end
	end
	return result
end

--------------------------------------------------------------------------------
-- ANGEBOTE
--------------------------------------------------------------------------------
function DiplomacyData.GetPendingOffers()
	return pendingOffers
end

function DiplomacyData.GetOffersFor(player)
	if not player then return {} end
	local id = player.UserId
	local result = {}
	for offerId, offer in pairs(pendingOffers) do
		if offer.to == player or offer.from == player then
			result[offerId] = offer
		end
	end
	return result
end

function DiplomacyData.GetIncomingOffers(player)
	if not player then return {} end
	local result = {}
	for offerId, offer in pairs(pendingOffers) do
		if offer.to == player then
			result[offerId] = offer
		end
	end
	return result
end

-- AddOffer -> offer. Bestehendes Angebot zwischen denselben Spielern/Typ wird
-- zuerst entfernt (keine Doppel-Antraege).
function DiplomacyData.AddOffer(from, to, offerType)
	DiplomacyData.ClearOfferBetween(from, to, offerType)
	local offer = {
		offerId = nextOfferId,
		from = from,
		to = to,
		type = offerType,
		roundsLeft = DiplomacyConfig.OFFER_TIMEOUT_ROUNDS,
	}
	nextOfferId = nextOfferId + 1
	pendingOffers[offer.offerId] = offer
	return offer
end

function DiplomacyData.GetOffer(offerId)
	return pendingOffers[offerId]
end

function DiplomacyData.FindOffer(from, to, offerType)
	for _, offer in pairs(pendingOffers) do
		if offer.from == from and offer.to == to and offer.type == offerType then
			return offer
		end
	end
	return nil
end

function DiplomacyData.ClearOffer(offer)
	if offer then pendingOffers[offer.offerId] = nil end
end

function DiplomacyData.ClearOfferBetween(from, to, offerType)
	for offerId, offer in pairs(pendingOffers) do
		if offer.from == from and offer.to == to and (not offerType or offer.type == offerType) then
			pendingOffers[offerId] = nil
		end
	end
end

-- Dekrementiere alle Angebote um 1 Runde. Liefert die abgelaufenen Angebote.
function DiplomacyData.TickOffers()
	local expired = {}
	for offerId, offer in pairs(pendingOffers) do
		offer.roundsLeft = (offer.roundsLeft or 0) - 1
		if offer.roundsLeft <= 0 then
			expired[offerId] = offer
			pendingOffers[offerId] = nil
		end
	end
	return expired
end

function DiplomacyData.ClearPlayer(player)
	if not player then return end
	local id = player.UserId
	-- Beziehungen
	for key in pairs(relations) do
		local a, b = key:match("^(%d+)_(%d+)$")
		if a and (tonumber(a) == id or tonumber(b) == id) then
			relations[key] = nil
		end
	end
	-- Angebote
	for offerId, offer in pairs(pendingOffers) do
		if offer.from == player or offer.to == player then
			pendingOffers[offerId] = nil
		end
	end
end

--------------------------------------------------------------------------------
-- KOMPATIBILITAET (alte DiplomacySystem-API auf DiplomacyData umgeleitet)
--------------------------------------------------------------------------------
function DiplomacyData.IsAtWar(playerA, playerB)
	if playerA == nil or playerB == nil then return true end
	if playerA == playerB then return false end
	return DiplomacyData.GetRelation(playerA, playerB) == DiplomacyConfig.STATE.WAR
end

function DiplomacyData.AreAllied(playerA, playerB)
	if playerA == nil or playerB == nil then return false end
	if playerA == playerB then return true end
	return DiplomacyData.GetRelation(playerA, playerB) == DiplomacyConfig.STATE.ALLIED
end

return DiplomacyData
