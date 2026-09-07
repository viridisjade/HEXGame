--[[
    ArmyModelGiver (ModuleScript)
    Ort: ServerScriptService > ArmyModelGiver
    
    Gibt ein geklontes Unit-Model zurück das die Army repräsentiert.
    Die Unit mit den höchsten MaxHP bestimmt das Aussehen der Army.
    
    Ablauf:
      1. ArmyId bekommen
      2. Alle Units der Armee durchgehen
      3. Unit mit höchsten MaxHP finden
      4. UnitType dieser Unit holen
      5. ModelName aus UnitConfig holen
      6. Model in ServerStorage > Units finden
      7. Model klonen
      8. Geklontes Model zurückgeben
    
    Verwendung:
        local ArmyModelGiver = require(script.Parent:WaitForChild("ArmyModelGiver"))
        
        local model = ArmyModelGiver.GetModel(armyId)
        if model then
            model.Parent = workspace
        end
--]]

local ArmyModelGiver = {}

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArmyData = require(script.Parent:WaitForChild("ArmyData"))
local UnitData = require(script.Parent:WaitForChild("UnitData"))
local UnitConfig = require(ReplicatedStorage:WaitForChild("UnitConfig"))

-- Referenz auf den Units-Folder (Sucht in ServerStorage UND ReplicatedStorage)
local unitsFolder = ServerStorage:FindFirstChild("Units") or ReplicatedStorage:FindFirstChild("Units")
if not unitsFolder then
	warn("[ArmyModelGiver] FEHLER: 'Units' Ordner weder in ServerStorage noch ReplicatedStorage gefunden!")
end

--------------------------------------------------------------------------------
-- GetModel(armyId) -> Model (geklont) or nil
-- Gibt ein geklontes Model zurück das die Army repräsentiert.
-- Die Unit mit den höchsten MaxHP bestimmt das Aussehen.
--------------------------------------------------------------------------------
function ArmyModelGiver.GetModel(armyId)
	-- 1. Army holen
	local army = ArmyData.GetArmy(armyId)
	if not army then
		warn("[ArmyModelGiver] Army " .. tostring(armyId) .. " nicht gefunden")
		return nil
	end

	if #army.units == 0 then
		warn("[ArmyModelGiver] Army " .. armyId .. " hat keine Units")
		return nil
	end

	-- 2+3. Alle Units durchgehen, Unit mit höchsten MaxHP finden
	local bestUnit = nil
	local highestMaxHP = 0

	for _, unitId in ipairs(army.units) do
		local unit = UnitData.GetUnit(unitId)
		if unit and unit.alive then
			if unit.maxLP > highestMaxHP then
				highestMaxHP = unit.maxLP
				bestUnit = unit
			end
		end
	end

	if not bestUnit then
		warn("[ArmyModelGiver] Army " .. armyId .. " hat keine lebenden Units")
		return nil
	end

	-- 4. UnitType holen
	local unitType = bestUnit.unitType

	-- 5. ModelName aus UnitConfig holen
	local config = UnitConfig.GetUnit(unitType)
	if not config then
		warn("[ArmyModelGiver] UnitConfig für '" .. unitType .. "' nicht gefunden")
		return nil
	end

	local modelName = config.Model

	-- 6. Model in ServerStorage > Units finden
	local template = unitsFolder:FindFirstChild(modelName)
	if not template then
		warn("[ArmyModelGiver] Model '" .. modelName .. "' nicht gefunden in ServerStorage > Units")
		return nil
	end

	-- 7. Model klonen
	local clone = template:Clone()

	-- 8. Geklontes Model zurückgeben
	return clone
end

--------------------------------------------------------------------------------
-- GetModelName(armyId) -> string or nil
-- Gibt nur den Model-Namen zurück ohne zu klonen.
-- Nützlich für Vorschau / UI.
--------------------------------------------------------------------------------
function ArmyModelGiver.GetModelName(armyId)
	local army = ArmyData.GetArmy(armyId)
	if not army or #army.units == 0 then return nil end

	local bestUnit = nil
	local highestMaxHP = 0

	for _, unitId in ipairs(army.units) do
		local unit = UnitData.GetUnit(unitId)
		if unit and unit.alive then
			if unit.maxLP > highestMaxHP then
				highestMaxHP = unit.maxLP
				bestUnit = unit
			end
		end
	end

	if not bestUnit then return nil end

	local config = UnitConfig.GetUnit(bestUnit.unitType)
	if not config then return nil end

	return config.Model
end

return ArmyModelGiver
