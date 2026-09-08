--[[
    FogOfWarData (ModuleScript)
    Ort: ServerScriptService > FogOfWarData

    Zentraler Server-State fuer das Fog-of-War-System. Haelt KEINE Logik
    (die liegt in FogOfWarSystem) - nur den Zustand pro Spieler:
        - visible  = Menge der Hex-Keys, die der Spieler JETZT sieht
        - explored = Menge der Hex-Keys, die der Spieler je erkundet hat

    Mengen werden als `{ [key] = true }` Maps gespeichert und beim Senden an
    den Client als Arrays von Keys konvertiert.

    Kompatibilitaet: Fuer die Datenmodule wird das PLAYER-OBJEKT als Schluessel
    verwendet (die Owner-Felder in ArmyData/CampData/CityData/BuildingData
    vergleichen per Referenz). Intern wird zusaetzlich ein userIndex fuer den
    Boolean-Fallback gepflegt.
--]]

local FogOfWarData = {}

local states = {}       -- [userId] = { visible = {}, explored = {} }

--------------------------------------------------------------------------------
-- CREATE / GET / REMOVE
--------------------------------------------------------------------------------
function FogOfWarData.Create(player)
	if not player then return nil end
	local id = player.UserId
	if not states[id] then
		states[id] = { visible = {}, explored = {} }
	end
	return states[id]
end

function FogOfWarData.Get(player)
	if not player then return nil end
	return states[player.UserId]
end

function FogOfWarData.GetOrCreate(player)
	return FogOfWarData.Create(player) or FogOfWarData.Get(player)
end

function FogOfWarData.Remove(player)
	if not player then return end
	states[player.UserId] = nil
end

function FogOfWarData.ClearAll()
	states = {}
end

--------------------------------------------------------------------------------
-- VISIBLE
--------------------------------------------------------------------------------
-- Setzt die aktuelle sichtbare Menge (ersetzt die alte vollstaendig).
-- Liefert das alte visible zum Differenzieren zurueck.
function FogOfWarData.SetVisible(player, keys)
	local state = FogOfWarData.GetOrCreate(player)
	if not state then return {} end
	local old = state.visible
	state.visible = keys or {}
	return old
end

function FogOfWarData.GetVisible(player)
	local state = FogOfWarData.Get(player)
	return state and state.visible or {}
end

function FogOfWarData.ClearVisible(player)
	local state = FogOfWarData.Get(player)
	if state then state.visible = {} end
end

--------------------------------------------------------------------------------
-- EXPLORED
--------------------------------------------------------------------------------
function FogOfWarData.AddExplored(player, keys)
	local state = FogOfWarData.GetOrCreate(player)
	if not state then return {} end
	local newly = {}
	for key in pairs(keys or {}) do
		if not state.explored[key] then
			state.explored[key] = true
			newly[key] = true
		end
	end
	return newly
end

function FogOfWarData.GetExplored(player)
	local state = FogOfWarData.Get(player)
	return state and state.explored or {}
end

--------------------------------------------------------------------------------
-- HELFER: Mengen in Arrays konvertieren (fuer die Remote-Payload)
--------------------------------------------------------------------------------
function FogOfWarData.setToArray(set)
	local arr = {}
	for key in pairs(set or {}) do
		table.insert(arr, key)
	end
	return arr
end

return FogOfWarData
