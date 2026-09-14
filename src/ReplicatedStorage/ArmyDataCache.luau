--[[
    ArmyDataCache (ModuleScript)
    Ort: ReplicatedStorage > ArmyDataCache

    Zentrale Datenquelle fuer die ArmyGui auf dem Client.

    VORHER: ArmyPanel erzeugte pro 0.5s ein GetArmy und fuer jeden Unit ein
            eigenes GetUnit (N+1 RPC). JETZT: Ein Modul holt die komplette
            Army in EINEM Batch-Call (GetArmyDetail) und verteilt sie per
            BindableEvent an Listener.

    Aktualisiert wird automatisch:
      - wenn eine Army (neu) ausgewaehlt wird
      - wenn der Server ArmyStatsChanged feuert (Kampf, Bewegung, Runde, ...)
      - wenn sich der Kampfzustand aendert

    Verwendung:
        local ArmyDataCache = require(game.ReplicatedStorage:WaitForChild("ArmyDataCache"))

        ArmyDataCache.OnUpdated:Connect(function(army)
            -- army kann nil sein (Auswahl aufgehoben)
        end)

        ArmyDataCache.Get()       -- aktuell geladene Army (oder nil)
        ArmyDataCache.GetUnit(id) -- aufgeloester Unit (oder nil)
        ArmyDataCache.Refresh()   -- Daten neu laden
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local State = require(ReplicatedStorage:WaitForChild("ClientState"))
local Net = require(ReplicatedStorage:WaitForChild("Net"))

local ArmyDataCache = {}

local currentArmy = nil
local updatedEvent = Instance.new("BindableEvent")
ArmyDataCache.OnUpdated = updatedEvent.Event

--------------------------------------------------------------------------------
-- Get() -> army or nil
-- Ein Army-Snapshot ist von der Form:
--   { id, name, q, r, ownerName, stats = {LP,MaxLP,Attack,Defense,Sight,Movement,MaxMovement},
--     units = { { id, unitType, name, class, icon, currentLP, maxLP, attack, defense, sight,
--                 currentMovement, maxMovement, alive } } }
--------------------------------------------------------------------------------
function ArmyDataCache.Get()
	return currentArmy
end

--------------------------------------------------------------------------------
-- GetUnit(unitId) -> resolved unit or nil
--------------------------------------------------------------------------------
function ArmyDataCache.GetUnit(unitId)
	if not currentArmy or not currentArmy.units then return nil end
	for _, unit in ipairs(currentArmy.units) do
		if unit.id == unitId then return unit end
	end
	return nil
end

--------------------------------------------------------------------------------
-- Refresh() -> army or nil
-- Holt die aktuell ausgewaehlte Army in einem einzigen Batch-Call.
--------------------------------------------------------------------------------
function ArmyDataCache.Refresh()
	local armyId = State.GetId(State.Kind.ARMY)

	if not armyId then
		if currentArmy ~= nil then
			currentArmy = nil
			updatedEvent:Fire(nil)
		end
		return nil
	end

	local ok, detail = Net.Invoke("GetArmyDetail", armyId)
	if not ok or not detail then
		return currentArmy
	end

	currentArmy = detail
	updatedEvent:Fire(detail)
	return detail
end

--------------------------------------------------------------------------------
-- Auswahl geaendert -> automatisch neu laden
--------------------------------------------------------------------------------
State.OnChanged:Connect(function(kind, id)
	if kind == State.Kind.ARMY and id then
		task.spawn(ArmyDataCache.Refresh)
	else
		currentArmy = nil
		updatedEvent:Fire(nil)
	end
end)

--------------------------------------------------------------------------------
-- Server meldet "Army hat sich geaendert" -> neu laden (nur eigene Auswahl)
--------------------------------------------------------------------------------
Net.On("ArmyStatsChanged", function(armyId)
	if State.Is(State.Kind.ARMY, armyId) then
		task.delay(0.1, ArmyDataCache.Refresh)
	end
end)

--------------------------------------------------------------------------------
-- Kampfzustand aendert sich (LP / Bewegung im Kampf) -> neu laden
--------------------------------------------------------------------------------
State.OnCombatChanged:Connect(function()
	if State.Has(State.Kind.ARMY) then
		task.delay(0.15, ArmyDataCache.Refresh)
	end
end)

-- Falls beim Laden schon eine Army ausgewaehlt ist
if State.Has(State.Kind.ARMY) then
	task.spawn(ArmyDataCache.Refresh)
end

return ArmyDataCache
