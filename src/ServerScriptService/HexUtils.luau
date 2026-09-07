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

return HexUtils
