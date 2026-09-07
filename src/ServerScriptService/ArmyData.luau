--[[
    ArmyData (ModuleScript)
    Ort: ServerScriptService > ArmyData
    
    Speichert alle Armee-Daten in einer zentralen Tabelle.
    
    Datenstruktur pro Army:
    {
        id = number,              -- Eindeutige Army-ID
        name = string,            -- Anzeigename pro Besitzer (z.B. "1. Army", "2. Army")
        owner = Player or nil,    -- Besitzer
        q = number,               -- Hex-Position (Spalte)
        r = number,               -- Hex-Position (Reihe)
        units = {},               -- Liste von Unit-IDs { 1, 4, 7, ... }
        stats = {                 -- Berechnete Army-Stats (via ArmyStats.Recalculate)
            LP = 0,               -- Summe aller Unit-LP
            Attack = 0,           -- Summe aller Unit-Attack
            Defense = 0,          -- Summe aller Unit-Defense
            Sight = 0,            -- Höchste Sight aller Units
            Movement = 0,         -- Niedrigste Movement aller Units
        },
    }
    
    Verwendung:
        local ArmyData = require(game.ServerScriptService:WaitForChild("ArmyData"))
        
        local army = ArmyData.GetArmy(1)
        print(army.owner)
        print(#army.units)
--]]

local ArmyData = {}

--------------------------------------------------------------------------------
-- Interne Daten
--------------------------------------------------------------------------------
local armies = {}        -- armies[id] = armyData
local nextId = 1         -- Nächste freie Army-ID

--------------------------------------------------------------------------------
-- refreshOwnerArmyNames(owner)
-- Benennt alle Armeen EINES Besitzers neu:
--   1. Army, 2. Army, 3. Army, ...
-- Sortierung erfolgt nach Army-ID für stabile Reihenfolge.
--------------------------------------------------------------------------------
local function refreshOwnerArmyNames(owner)
	if owner == nil then return end

	local ownerArmies = {}
	for id, army in pairs(armies) do
		if army.owner == owner then
			table.insert(ownerArmies, army)
		end
	end

	table.sort(ownerArmies, function(a, b)
		return a.id < b.id
	end)

	for index, army in ipairs(ownerArmies) do
		army.name = index .. ". Army"
	end
end

--------------------------------------------------------------------------------
-- CreateArmy(owner, q, r) -> armyId
--------------------------------------------------------------------------------
function ArmyData.CreateArmy(owner, q, r)
	local id = nextId
	nextId = nextId + 1

	armies[id] = {
		id = id,
		name = "1. Army", -- Wird sofort unten korrekt neu nummeriert
		owner = owner,
		q = q,
		r = r,
		units = {},
		stats = {
			LP = 0,
			MaxLP = 0,
			Attack = 0,
			Defense = 0,
			Sight = 0,
			Movement = 0,
			MaxMovement = 0,
		},
	}

	refreshOwnerArmyNames(owner)

	return id
end

--------------------------------------------------------------------------------
-- GetArmy(id) -> table or nil
--------------------------------------------------------------------------------
function ArmyData.GetArmy(id)
	return armies[id]
end

--------------------------------------------------------------------------------
-- GetAllArmies() -> table
--------------------------------------------------------------------------------
function ArmyData.GetAllArmies()
	return armies
end

--------------------------------------------------------------------------------
-- GetArmyCount() -> number
--------------------------------------------------------------------------------
function ArmyData.GetArmyCount()
	local count = 0
	for _ in pairs(armies) do
		count = count + 1
	end
	return count
end

--------------------------------------------------------------------------------
-- SetArmyName(id, newName)
--------------------------------------------------------------------------------
function ArmyData.SetArmyName(id, newName)
	local army = armies[id]
	if not army then return false end
	army.name = newName
	return true
end

--------------------------------------------------------------------------------
-- RemoveArmy(id)
--------------------------------------------------------------------------------
function ArmyData.RemoveArmy(id)
	local army = armies[id]
	if not army then return end

	local owner = army.owner
	armies[id] = nil

	refreshOwnerArmyNames(owner)
end

--------------------------------------------------------------------------------
-- UpdateArmy(id, updates)
--------------------------------------------------------------------------------
function ArmyData.UpdateArmy(id, updates)
	local army = armies[id]
	if not army then return false end

	local oldOwner = army.owner

	for field, value in pairs(updates) do
		army[field] = value
	end

	-- Falls der Besitzer geändert wurde: beide Seiten neu nummerieren
	if updates.owner ~= nil and updates.owner ~= oldOwner then
		refreshOwnerArmyNames(oldOwner)
		refreshOwnerArmyNames(updates.owner)
	end

	return true
end

--------------------------------------------------------------------------------
-- GetArmiesByOwner(owner) -> table
--------------------------------------------------------------------------------
function ArmyData.GetArmiesByOwner(owner)
	local result = {}
	for id, army in pairs(armies) do
		if army.owner == owner then
			table.insert(result, army)
		end
	end
	return result
end

--------------------------------------------------------------------------------
-- GetArmyOnHex(q, r) -> army or nil
-- Findet eine Army auf einem bestimmten Hex
--------------------------------------------------------------------------------
function ArmyData.GetArmyOnHex(q, r)
	for id, army in pairs(armies) do
		if army.q == q and army.r == r then
			return army
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- GetUnitCount(armyId) -> number
--------------------------------------------------------------------------------
function ArmyData.GetUnitCount(armyId)
	local army = armies[armyId]
	if army then
		return #army.units
	end
	return 0
end

--------------------------------------------------------------------------------
-- ClearAll()
--------------------------------------------------------------------------------
function ArmyData.ClearAll()
	armies = {}
	nextId = 1
	print("[ArmyData] Alle Army-Daten gelöscht.")
end

return ArmyData
