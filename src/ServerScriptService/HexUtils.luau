--[[
    HexUtils (ModuleScript)
    Ort: ServerScriptService > HexUtils
    
    Hilfsfunktionen für Hexagonal-Grid-Berechnungen.
    Verwendet Axial-Koordinaten (q, r) für Hex-Grids.
    
    WICHTIG:
      Die eigentliche Grid-Konfiguration liegt jetzt in:
        ReplicatedStorage > HexGridConfig
    
      Dort änderst du:
        HEX_WIDTH
        HEX_HEIGHT
        GAP
        SPAWN_Y
    
      HexUtils liest diese Werte automatisch daraus.
--]]

local HexUtils = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HexGridConfig = require(ReplicatedStorage:WaitForChild("HexGridConfig"))

--------------------------------------------------------------------------------
-- SHARED CONFIG
-- Nutzt dieselbe Config wie der Client
--------------------------------------------------------------------------------
HexUtils.Config = HexGridConfig.Config
HexUtils.HORIZONTAL_SPACING = 0
HexUtils.VERTICAL_SPACING = 0

--------------------------------------------------------------------------------
-- updateSpacing()
-- Berechnet die Abstände neu basierend auf der shared Config.
--------------------------------------------------------------------------------
function HexUtils.updateSpacing()
	HexGridConfig.UpdateSpacing()
	HexUtils.HORIZONTAL_SPACING = HexGridConfig.HORIZONTAL_SPACING
	HexUtils.VERTICAL_SPACING = HexGridConfig.VERTICAL_SPACING
end

-- Initial berechnen
HexUtils.updateSpacing()

--------------------------------------------------------------------------------
-- axialToWorld(q, r) -> Vector3
--------------------------------------------------------------------------------
function HexUtils.axialToWorld(q, r)
	-- Immer sicherstellen dass die aktuellen Shared-Werte genutzt werden
	HexUtils.updateSpacing()

	local x = q * HexUtils.HORIZONTAL_SPACING
	local zOffset = 0

	if q % 2 ~= 0 then
		zOffset = HexUtils.VERTICAL_SPACING / 2
	end

	local z = r * HexUtils.VERTICAL_SPACING + zOffset

	return Vector3.new(x, HexUtils.Config.SPAWN_Y, z)
end

--------------------------------------------------------------------------------
-- getNeighbors(q, r) -> table
--------------------------------------------------------------------------------
function HexUtils.getNeighbors(q, r)
	local neighbors = {}

	if q % 2 == 0 then
		neighbors = {
			{q = q + 1, r = r - 1},
			{q = q + 1, r = r},
			{q = q, r = r + 1},
			{q = q - 1, r = r},
			{q = q - 1, r = r - 1},
			{q = q, r = r - 1},
		}
	else
		neighbors = {
			{q = q + 1, r = r},
			{q = q + 1, r = r + 1},
			{q = q, r = r + 1},
			{q = q - 1, r = r + 1},
			{q = q - 1, r = r},
			{q = q, r = r - 1},
		}
	end

	return neighbors
end

--------------------------------------------------------------------------------
-- getDistance(q1, r1, q2, r2) -> number
--------------------------------------------------------------------------------
function HexUtils.getDistance(q1, r1, q2, r2)
	local function offsetToCube(q, r)
		local x = q
		local z = r - (q - (q % 2)) / 2
		local y = -x - z
		return x, y, z
	end

	local x1, y1, z1 = offsetToCube(q1, r1)
	local x2, y2, z2 = offsetToCube(q2, r2)

	return math.max(math.abs(x1 - x2), math.abs(y1 - y2), math.abs(z1 - z2))
end

--------------------------------------------------------------------------------
-- coordToKey(q, r) -> string
--------------------------------------------------------------------------------
function HexUtils.coordToKey(q, r)
	return q .. "_" .. r
end

--------------------------------------------------------------------------------
-- keyToCoord(key) -> q, r
--------------------------------------------------------------------------------
function HexUtils.keyToCoord(key)
	local parts = string.split(key, "_")
	return tonumber(parts[1]), tonumber(parts[2])
end

--------------------------------------------------------------------------------
-- TERRAIN-HÖHEN (gemeinsame Tabelle für Bewegung UND Fog-of-War-Sichtlinien)
--------------------------------------------------------------------------------
-- Mappt den Terrain-String (siehe HexData.terrain, gesetzt aus
-- TerrainGenerator.TerrainNames) auf ein Höhenlevel:
--   Water           -> 0  (Referenz, unbetretbar)
--   Ebene1          -> 1
--   Ebene2          -> 2
--   Ebene3_Gebirge  -> 3
--   Ebene4_Bergspitze -> 4
--------------------------------------------------------------------------------
local TERRAIN_HEIGHTS = {
	Water = 0,
	Ebene1 = 1,
	Ebene2 = 2,
	Ebene3_Gebirge = 3,
	Ebene4_Bergspitze = 4,
	Ebene0 = 0,
	Unknown = 0,
}

--------------------------------------------------------------------------------
-- GetTerrainHeight(terrainType) -> number
--------------------------------------------------------------------------------
function HexUtils.GetTerrainHeight(terrainType)
	return TERRAIN_HEIGHTS[terrainType] or 0
end

--------------------------------------------------------------------------------
-- offsetToCube(q, r) / cubeToOffset(x, y, z)
-- Konvertierung zwischen Axial-Offset-Koordinaten (odd-q Layout, wie im
-- Rest von HexUtils verwendet) und Cube-Koordinaten.
--------------------------------------------------------------------------------
local function offsetToCube(q, r)
	local x = q
	local z = r - (q - (q % 2)) / 2
	local y = -x - z
	return x, y, z
end

local function cubeToOffset(x, y, z)
	local q = x
	local r = z + (x - (x % 2)) / 2
	return q, r
end

--------------------------------------------------------------------------------
-- cubeRound(x, y, z) -> x, y, z (gerundet, x+y+z bleibt 0)
--------------------------------------------------------------------------------
local function cubeRound(x, y, z)
	local rx = math.floor(x + 0.5)
	local ry = math.floor(y + 0.5)
	local rz = math.floor(z + 0.5)

	local xDiff = math.abs(rx - x)
	local yDiff = math.abs(ry - y)
	local zDiff = math.abs(rz - z)

	if xDiff > yDiff and xDiff > zDiff then
		rx = -ry - rz
	elseif yDiff > zDiff then
		ry = -rx - rz
	else
		rz = -rx - ry
	end

	return rx, ry, rz
end

--------------------------------------------------------------------------------
-- getLine(q1, r1, q2, r2) -> table { {q, r}, {q, r}, ... }
-- Berechnet die Hexes auf der geraden Linie von (q1, r1) nach (q2, r2)
-- (Cube-Coordinate-Line-Draw, inklusive Start- und Ziel-Hex).
-- Wird für die Sichtlinien-Prüfung im Fog of War benötigt.
--------------------------------------------------------------------------------
function HexUtils.getLine(q1, r1, q2, r2)
	local dist = HexUtils.getDistance(q1, r1, q2, r2)
	if dist == 0 then
		return { { q = q1, r = r1 } }
	end

	local x1, y1, z1 = offsetToCube(q1, r1)
	local x2, y2, z2 = offsetToCube(q2, r2)

	local line = {}
	for i = 0, dist do
		local t = i / dist
		local x = x1 + (x2 - x1) * t
		local y = y1 + (y2 - y1) * t
		local z = z1 + (z2 - z1) * t

		local rx, ry, rz = cubeRound(x, y, z)
		local rq, rr = cubeToOffset(rx, ry, rz)

		table.insert(line, { q = rq, r = rr })
	end
	return line
end

return HexUtils
