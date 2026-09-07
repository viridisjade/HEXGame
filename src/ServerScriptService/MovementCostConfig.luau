--[[
    MovementCostConfig (ModuleScript)
    Ort: ServerScriptService > MovementCostConfig
    
    Speichert die Bewegungskosten pro Bodentyp (Soil).
    Wird von MovementSystem gelesen, nie verändert.
    
    nil = nicht betretbar
--]]

local MovementCostConfig = {}

MovementCostConfig.Costs = {
	Grassland = 1,
	DryGrass = 1,
	Forest = 2,
	Rocks = 2,
	CoastWater = nil,      -- nicht betretbar
	DeepWater = nil,        -- nicht betretbar
	Mountain = nil,         -- nicht betretbar
}

--------------------------------------------------------------------------------
-- GetCost(soilType) -> number or nil
-- nil = nicht betretbar
--------------------------------------------------------------------------------
function MovementCostConfig.GetCost(soilType)
	return MovementCostConfig.Costs[soilType]
end

--------------------------------------------------------------------------------
-- IsPassable(soilType) -> boolean
--------------------------------------------------------------------------------
function MovementCostConfig.IsPassable(soilType)
	return MovementCostConfig.Costs[soilType] ~= nil
end

return MovementCostConfig
