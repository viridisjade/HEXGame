--[[
    UnitSpawnState (ModuleScript)
    Ort: ReplicatedStorage > UnitSpawnState
    
    Speichert, welche Unit gerade platziert werden soll.
--]]

local UnitSpawnState = {}

local placement = nil
local changedEvent = Instance.new("BindableEvent")
UnitSpawnState.OnChanged = changedEvent.Event

function UnitSpawnState.Start(cityId, unitType)
	placement = {
		cityId = cityId,
		unitType = unitType,
	}
	changedEvent:Fire(placement)
end

function UnitSpawnState.Cancel()
	if not placement then return end
	placement = nil
	changedEvent:Fire(nil)
end

function UnitSpawnState.Get()
	return placement
end

function UnitSpawnState.IsPlacing()
	return placement ~= nil
end

return UnitSpawnState
