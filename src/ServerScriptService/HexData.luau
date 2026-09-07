--[[
    HexData (ModuleScript)
    Ort: ServerScriptService > HexData
    
    Speichert alle Hex-Daten in einer zentralen Tabelle.
    
    Datenstruktur pro Hex:
    {
        q = number,           -- Spalte (Axial-Koordinate)
        r = number,           -- Reihe (Axial-Koordinate)
        terrain = string,     -- Terrain-Typ ("Water", "Ebene1", etc.)
        soil = string,        -- Bodentyp ("Grassland", "Forest", etc.)
        province = number,    -- Provinz-Nummer (1, 2, 3, ...)
        owner = nil,          -- [Zukünftig] Besitzer (Player)
        army = nil,           -- Army-ID auf diesem Hex (number oder nil)
        building = nil,       -- [Zukünftig] Gebäude auf dem Hex
    }
    
    Verwendung:
        local HexData = require(game.ServerScriptService:WaitForChild("HexData"))
        
        HexData.SetHex(3, -2, {
            q = 3,
            r = -2,
            terrain = "Ebene1",
            soil = nil,
            owner = nil,
            army = nil,
            building = nil,
        })
        
        local hex = HexData.GetHex(3, -2)
        print(hex.terrain)  -- "Ebene1"
--]]

local HexData = {}

--------------------------------------------------------------------------------
-- Interne Daten-Tabelle
-- Struktur: hexMap[key] = { q, r, terrain, soil, province, owner, army, building }
--------------------------------------------------------------------------------
local hexMap = {}

--------------------------------------------------------------------------------
-- coordToKey(q, r) -> string
--------------------------------------------------------------------------------
local function coordToKey(q, r)
	return q .. "_" .. r
end

--------------------------------------------------------------------------------
-- SetHex(q, r, data)
-- Speichert Hex-Daten für die angegebenen Koordinaten.
--------------------------------------------------------------------------------
function HexData.SetHex(q, r, data)
	local key = coordToKey(q, r)

	data.q = q
	data.r = r
	data.terrain = data.terrain or "Unknown"
	data.soil = data.soil or nil
	data.province = data.province or nil
	data.owner = data.owner or nil
	data.army = data.army or nil
	data.building = data.building or nil

	hexMap[key] = data
end

--------------------------------------------------------------------------------
-- GetHex(q, r) -> table or nil
--------------------------------------------------------------------------------
function HexData.GetHex(q, r)
	local key = coordToKey(q, r)
	return hexMap[key]
end

--------------------------------------------------------------------------------
-- HasHex(q, r) -> boolean
--------------------------------------------------------------------------------
function HexData.HasHex(q, r)
	local key = coordToKey(q, r)
	return hexMap[key] ~= nil
end

--------------------------------------------------------------------------------
-- UpdateHex(q, r, updates)
-- Aktualisiert einzelne Felder eines Hexes.
--
-- Beispiel:
--   HexData.UpdateHex(3, -2, { owner = player, unit = soldierUnit })
--------------------------------------------------------------------------------
function HexData.UpdateHex(q, r, updates)
	local key = coordToKey(q, r)
	local hex = hexMap[key]

	if not hex then
		warn("[HexData] UpdateHex: Kein Hex bei (" .. q .. ", " .. r .. ")")
		return false
	end

	for field, value in pairs(updates) do
		hex[field] = value
	end

	return true
end

--------------------------------------------------------------------------------
-- ClearHexField(q, r, field)
-- Entfernt ein Feld (z.B. "army", "owner" oder "building") sauber auf nil.
--
-- WICHTIG: UpdateHex(q, r, { army = nil }) tut NICHTS! Lua legt bei
-- { feld = nil } das Feld gar nicht erst an, deshalb sieht die pairs()-Schleife
-- in UpdateHex nichts. Zum Leeren IMMER ClearHexField benutzen.
--------------------------------------------------------------------------------
function HexData.ClearHexField(q, r, field)
	local key = coordToKey(q, r)
	local hex = hexMap[key]
	if not hex then return false end
	hex[field] = nil
	return true
end

--------------------------------------------------------------------------------
-- RemoveHex(q, r)
--------------------------------------------------------------------------------
function HexData.RemoveHex(q, r)
	local key = coordToKey(q, r)
	hexMap[key] = nil
end

--------------------------------------------------------------------------------
-- GetAllHexes() -> table
--------------------------------------------------------------------------------
function HexData.GetAllHexes()
	return hexMap
end

--------------------------------------------------------------------------------
-- GetHexCount() -> number
--------------------------------------------------------------------------------
function HexData.GetHexCount()
	local count = 0
	for _ in pairs(hexMap) do
		count = count + 1
	end
	return count
end

--------------------------------------------------------------------------------
-- GetHexesByTerrain(terrainType) -> table
--------------------------------------------------------------------------------
function HexData.GetHexesByTerrain(terrainType)
	local result = {}
	for key, hex in pairs(hexMap) do
		if hex.terrain == terrainType then
			table.insert(result, hex)
		end
	end
	return result
end

--------------------------------------------------------------------------------
-- GetHexesByOwner(owner) -> table
-- [Für zukünftige Verwendung]
--------------------------------------------------------------------------------
function HexData.GetHexesByOwner(owner)
	local result = {}
	for key, hex in pairs(hexMap) do
		if hex.owner == owner then
			table.insert(result, hex)
		end
	end
	return result
end

--------------------------------------------------------------------------------
-- ClearAll()
--------------------------------------------------------------------------------
function HexData.ClearAll()
	hexMap = {}
	print("[HexData] Alle Hex-Daten gelöscht.")
end

--------------------------------------------------------------------------------
-- PrintStats()
--------------------------------------------------------------------------------
function HexData.PrintStats()
	local stats = {}
	local total = 0

	for key, hex in pairs(hexMap) do
		local terrain = hex.terrain or "Unknown"
		stats[terrain] = (stats[terrain] or 0) + 1
		total = total + 1
	end

	print("[HexData] === Hex-Statistik ===")
	for terrain, count in pairs(stats) do
		local pct = total > 0 and math.floor((count / total) * 100) or 0
		print("  " .. terrain .. ": " .. count .. " (" .. pct .. "%)")
	end
	print("[HexData] Total: " .. total .. " Hexes")
end

return HexData
