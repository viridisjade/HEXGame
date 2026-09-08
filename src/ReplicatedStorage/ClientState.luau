
--[[
    ClientState (ModuleScript)
    Ort: ReplicatedStorage > ClientState
    
    DER Zustand des Clients an einem Ort:
      - Was ist ausgewählt?      (Army / Camp / City)
      - Wird gerade platziert?   (Gebäude / Unit)
    
    Es kann immer nur EINE Auswahl geben. Umschalten passiert atomar.
--]]

local ClientState = {}

ClientState.Kind = { ARMY = "army", CAMP = "camp", CITY = "city" }

local selKind, selId = nil, nil
local placement = nil

local selEvent = Instance.new("BindableEvent")
local placeEvent = Instance.new("BindableEvent")

ClientState.OnChanged = selEvent.Event
ClientState.OnPlacementChanged = placeEvent.Event

--------------------------------------------------------------------------------
-- AUSWAHL
--------------------------------------------------------------------------------
function ClientState.Get()
	return selKind, selId
end

function ClientState.GetId(kind)
	if selKind == kind then return selId end
	return nil
end

function ClientState.Is(kind, id)
	return selKind == kind and selId == id
end

function ClientState.Has(kind)
	if kind == nil then return selKind ~= nil end
	return selKind == kind
end

function ClientState.Select(kind, id)
	if kind == nil or id == nil then
		return ClientState.Clear()
	end
	if selKind == kind and selId == id then return end

	local pk, pi = selKind, selId
	selKind, selId = kind, id
	selEvent:Fire(kind, id, pk, pi)
end

function ClientState.Toggle(kind, id)
	if ClientState.Is(kind, id) then
		ClientState.Clear()
	else
		ClientState.Select(kind, id)
	end
end

function ClientState.Clear()
	if selKind == nil then return end
	local pk, pi = selKind, selId
	selKind, selId = nil, nil
	selEvent:Fire(nil, nil, pk, pi)
end

--------------------------------------------------------------------------------
-- PLATZIERUNG (Gebäude / Unit)
--------------------------------------------------------------------------------
function ClientState.StartPlacing(mode, cityId, itemType)
	placement = { mode = mode, cityId = cityId, itemType = itemType }
	placeEvent:Fire(placement)
end

function ClientState.StopPlacing()
	if not placement then return end
	placement = nil
	placeEvent:Fire(nil)
end

function ClientState.GetPlacement()
	return placement
end

function ClientState.IsPlacing(mode)
	if not placement then return false end
	if mode then return placement.mode == mode end
	return true
end

--------------------------------------------------------------------------------
-- COMBAT STATE (turn based combat overlay)
-- While InCombat is true the world input is suppressed (see InputRouter).
--------------------------------------------------------------------------------
local inCombat = false
local activeCombatId = nil

local combatEvent = Instance.new("BindableEvent")
ClientState.OnCombatChanged = combatEvent.Event

function ClientState.SetCombat(active, combatId)
	active = active == true
	if inCombat == active and activeCombatId == combatId then return end
	inCombat = active
	activeCombatId = active and combatId or nil
	combatEvent:Fire(inCombat, activeCombatId)
end

function ClientState.IsInCombat()
	return inCombat
end

function ClientState.GetCombatId()
	return activeCombatId
end

--------------------------------------------------------------------------------
-- PER ARMY COMBAT FLAGS
--
-- Purely local hint so the UI can grey out actions WITHOUT a blocking
-- RemoteFunction round trip. The server stays authoritative (MovementHandler
-- and ArmySystem both refuse movement of a fighting army).
--
-- Entries auto-expire so a missed CombatEnd can never lock an army forever.
--------------------------------------------------------------------------------
local ARMY_COMBAT_TTL = 120 -- seconds
local armiesInCombat = {}   -- [armyId] = os.clock() timestamp

-- Per-Army combat flags fire this event so UI (ArmyGui) can react without
-- polling. Fired with (armyId, active).
local armyCombatEvent = Instance.new("BindableEvent")
ClientState.OnArmyCombatChanged = armyCombatEvent.Event

function ClientState.SetArmyCombat(armyId, active)
	if type(armyId) ~= "number" then return end
	local wasActive = ClientState.IsArmyInCombat(armyId)
	if active then
		armiesInCombat[armyId] = os.clock()
	else
		armiesInCombat[armyId] = nil
	end
	-- Only fire when the flag actually changed (avoids redundant UI work).
	local nowActive = ClientState.IsArmyInCombat(armyId)
	if nowActive ~= wasActive then
		armyCombatEvent:Fire(armyId, nowActive)
	end
end

function ClientState.IsArmyInCombat(armyId)
	local stamp = armiesInCombat[armyId]
	if not stamp then return false end
	if os.clock() - stamp > ARMY_COMBAT_TTL then
		armiesInCombat[armyId] = nil -- safety net against a stale flag
		-- Notify the UI that the TTL expired.
		armyCombatEvent:Fire(armyId, false)
		return false
	end
	return true
end

function ClientState.ClearArmyCombat()
	armiesInCombat = {}
end

--------------------------------------------------------------------------------
-- DIPLOMATIE STATE (lokaler Client-Cache)
-- Der Server pusht DiplomacyUpdate/DiplomacyNotification; der Client speichert
-- hier den letzten Stand und feuert OnDiplomacyChanged an die GUIs.
--------------------------------------------------------------------------------
local diplomacyRelations = {}   -- [otherUserId] = "Allied"|"Neutral"|"War"
local diplomacyOffers = {}      -- [offerId] = offer

local diplomacyEvent = Instance.new("BindableEvent")
ClientState.OnDiplomacyChanged = diplomacyEvent.Event

function ClientState.SetDiplomacy(relations, offers)
	diplomacyRelations = relations or {}
	diplomacyOffers = offers or {}
	diplomacyEvent:Fire(diplomacyRelations, diplomacyOffers)
end

function ClientState.GetDiplomacyRelations()
	return diplomacyRelations
end

function ClientState.GetDiplomacyOffers()
	return diplomacyOffers
end

-- BindableEvent zum Oeffnen/Schliessen des Diplomatie-Fensters
local diplomacyToggle = Instance.new("BindableEvent")
ClientState.ToggleDiplomacy = diplomacyToggle.Event
function ClientState.FireToggleDiplomacy()
	diplomacyToggle:Fire()
end

return ClientState
