--[[
    CityDataCache (ModuleScript)
    Ort: ReplicatedStorage > CityDataCache
    
    Zentrale Datenquelle für die CityGui auf dem Client.
    
    VORHER: CityGuiController, CityStatsSync, GrowthBarController und
            ResourceOverviewController haben JEDE eigene GetCity-Abfragen
            gestartet (zusammen ~4 InvokeServer pro Sekunde + 5 Polling-Loops).
    JETZT:  Ein Modul holt die Daten EINMAL und verteilt sie per
            BindableEvent an alle Listener.
    
    Aktualisiert wird automatisch:
      - wenn eine Stadt (neu) ausgewählt wird
      - wenn der Server CityStatsChanged feuert (Rundenende, Gebäude fertig, ...)
      - manuell per CityDataCache.Refresh()
    
    Verwendung:
        local CityDataCache = require(game.ReplicatedStorage:WaitForChild("CityDataCache"))
        
        CityDataCache.OnUpdated:Connect(function(city)
            -- city kann nil sein (Auswahl aufgehoben)
        end)
        
        CityDataCache.Get()      -- aktuell geladene Stadt (oder nil)
        CityDataCache.Refresh()  -- Daten neu laden
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local State = require(ReplicatedStorage:WaitForChild("ClientState"))
local Net = require(ReplicatedStorage:WaitForChild("Net"))

local CityDataCache = {}

local currentCity = nil
local currentBuildingCosts = nil
local updatedEvent = Instance.new("BindableEvent")
CityDataCache.OnUpdated = updatedEvent.Event

--------------------------------------------------------------------------------
-- Get() -> city or nil
--------------------------------------------------------------------------------
function CityDataCache.Get()
	return currentCity
end

--------------------------------------------------------------------------------
-- GetBuildingCosts() -> table or nil
-- Die zuletzt geladenen (SKALIERTEN, nicht Basis-) Baukosten der aktuell
-- ausgewählten Stadt. Kommt aus BuildingCostSystem.GetAllBuildingCosts
-- (Server) über das GetBuildingCosts-Remote.
--
-- Struktur: { [buildingType] = { name, baseCost, actualCost, stage, multiplier }, _info = { stage, multiplier, buildingCount } }
--------------------------------------------------------------------------------
function CityDataCache.GetBuildingCosts()
	return currentBuildingCosts
end

--------------------------------------------------------------------------------
-- Refresh() -> city or nil
-- Lädt die Daten der aktuell ausgewählten Stadt (inkl. skalierter
-- Baukosten) neu.
--------------------------------------------------------------------------------
function CityDataCache.Refresh()
	local cityId = State.GetId(State.Kind.CITY)

	if not cityId then
		if currentCity ~= nil then
			currentCity = nil
			currentBuildingCosts = nil
			updatedEvent:Fire(nil)
		end
		return nil
	end

	local ok, city = Net.Invoke("GetCity", cityId)
	if not ok or not city then
		return nil
	end

	-- Skalierte Baukosten mitladen (steigen mit der Anzahl Gebäude der Stadt).
	local costsOk, costs = Net.Invoke("GetBuildingCosts", cityId)
	currentBuildingCosts = (costsOk and costs) or nil

	currentCity = city
	updatedEvent:Fire(city)
	return city
end

--------------------------------------------------------------------------------
-- Auswahl geändert -> automatisch neu laden
--------------------------------------------------------------------------------
State.OnChanged:Connect(function(kind, id)
	if kind == State.Kind.CITY and id then
		task.spawn(CityDataCache.Refresh)
	else
		currentCity = nil
		updatedEvent:Fire(nil)
	end
end)

--------------------------------------------------------------------------------
-- Server meldet "Stadt hat sich geändert" -> neu laden (nur eigene Auswahl)
--------------------------------------------------------------------------------
Net.On("CityStatsChanged", function(cityId)
	if State.Is(State.Kind.CITY, cityId) then
		task.delay(0.1, CityDataCache.Refresh)
	end
end)

-- Falls beim Laden schon eine Stadt ausgewählt ist
if State.Has(State.Kind.CITY) then
	task.spawn(CityDataCache.Refresh)
end

return CityDataCache