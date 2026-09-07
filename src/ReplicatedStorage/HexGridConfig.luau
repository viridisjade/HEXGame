--[[
    HexGridConfig (ModuleScript)
    Ort: ReplicatedStorage > HexGridConfig
    
    SINGLE SOURCE OF TRUTH für das gesamte Hex-Grid.
    
    ALLE Systeme lesen diese Werte:
      - HexUtils (Server)
      - MovementClient (Client)
      - HoverPreview (Client)
      - alle World/Screen Positionen
    
    WENN DU DEN GAP ÄNDERN WILLST:
      ÄNDERE IHN HIER.
    
    Nicht mehr in HexUtils ändern!
--]]

local HexGridConfig = {}

HexGridConfig.Config = {
	HEX_WIDTH = 10,
	HEX_HEIGHT = 8.66,
	GAP = 0.5,
	SPAWN_Y = -8,
}

HexGridConfig.HORIZONTAL_SPACING = 0
HexGridConfig.VERTICAL_SPACING = 0

function HexGridConfig.UpdateSpacing()
	local c = HexGridConfig.Config
	HexGridConfig.HORIZONTAL_SPACING = c.HEX_WIDTH * 0.75 + c.GAP
	HexGridConfig.VERTICAL_SPACING = c.HEX_HEIGHT + c.GAP
end

HexGridConfig.UpdateSpacing()

--------------------------------------------------------------------------------
-- axialToWorld(q, r) -> Vector3
--------------------------------------------------------------------------------
function HexGridConfig.axialToWorld(q, r)
	HexGridConfig.UpdateSpacing()

	local x = q * HexGridConfig.HORIZONTAL_SPACING
	local zOffset = 0
	if q % 2 ~= 0 then
		zOffset = HexGridConfig.VERTICAL_SPACING / 2
	end
	local z = r * HexGridConfig.VERTICAL_SPACING + zOffset
	return Vector3.new(x, HexGridConfig.Config.SPAWN_Y, z)
end

--------------------------------------------------------------------------------
-- worldToAxial(worldPos) -> q, r
--------------------------------------------------------------------------------
function HexGridConfig.worldToAxial(worldPos)
	HexGridConfig.UpdateSpacing()

	local q = math.round(worldPos.X / HexGridConfig.HORIZONTAL_SPACING)
	local zOffset = 0
	if q % 2 ~= 0 then
		zOffset = HexGridConfig.VERTICAL_SPACING / 2
	end
	local r = math.round((worldPos.Z - zOffset) / HexGridConfig.VERTICAL_SPACING)
	return q, r
end

return HexGridConfig
