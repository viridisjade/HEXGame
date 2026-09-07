--[[
    CityBuildState (ModuleScript)
    Ort: ReplicatedStorage > CityBuildState

    Gemeinsamer client-seitiger Zustand für die Gebäudeplatzierung.
    Verbindet CityGuiController, CityPlacementController und CityInputHandler,
    ohne _G und ohne von der Ausführungsreihenfolge der LocalScripts abhängig zu sein.
--]]

local CityBuildState = {}

local placement = nil -- { cityId, buildingType }
local changedEvent = Instance.new("BindableEvent")

CityBuildState.OnChanged = changedEvent.Event

function CityBuildState.Start(cityId, buildingType)
	placement = {
		cityId = cityId,
		buildingType = buildingType,
	}
	changedEvent:Fire(placement)
end

function CityBuildState.Cancel()
	if not placement then return end
	placement = nil
	changedEvent:Fire(nil)
end

function CityBuildState.Get()
	return placement
end

function CityBuildState.IsPlacing()
	return placement ~= nil
end

return CityBuildState
