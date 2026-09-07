--[[
    ArmyModelMover (ModuleScript)
    Ort: ServerScriptService > ArmyModelMover
    
    Bewegt das sichtbare Armee-Model im Workspace
    von einem Hex zum nächsten.
--]]

local ArmyModelMover = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HexUtils = require(script.Parent:WaitForChild("HexUtils"))
local HexHeightUtil = require(ReplicatedStorage:WaitForChild("HexHeightUtil"))

--------------------------------------------------------------------------------
-- KONFIGURATION
--------------------------------------------------------------------------------
ArmyModelMover.Config = {
	STEP_DELAY = 0.35,
	HEIGHT_OFFSET = 0.35,
}

--------------------------------------------------------------------------------
-- getYOfObject(object) -> number
-- Oberkante eines Models/Parts (oder -unendlich wenn unbrauchbar)
--------------------------------------------------------------------------------
local function getYOfObject(object)
	if not object then return -math.huge end
	if object:IsA("Model") then
		if object.PrimaryPart then
			return object.PrimaryPart.Position.Y + object.PrimaryPart.Size.Y / 2
		end
		local cf, size = object:GetBoundingBox()
		return cf.Position.Y + size.Y / 2
	elseif object:IsA("BasePart") then
		return object.Position.Y + object.Size.Y / 2
	end
	return -math.huge
end

--------------------------------------------------------------------------------
-- findTopY(q, r) -> number
-- Findet die höchste Oberkante auf einem Hex:
--   1. Soil-Modell (Boden-Deckel)
--   2. Gebäude (City, Bastion, Camp)
--   3. Hex-Modell als Boden-Fallback
--
-- WICHTIG: Gebäude werden mitgerechnet, damit eine Army beim Bewegen auf ein
-- Gebäude-Hex NICHT im Gebäude versinkt. Das ist exakt dieselbe Regel wie
-- im ArmySpawner.findTopY - beide Module verhalten sich jetzt identisch.
--------------------------------------------------------------------------------
function ArmyModelMover.findTopY(q, r)
	local hexMapFolder = workspace:FindFirstChild("HexMap")
	if not hexMapFolder then
		return HexUtils.Config.SPAWN_Y + 2
	end

	local topY = HexUtils.Config.SPAWN_Y + 2

	-- 1) Soil suchen
	local soilsFolder = hexMapFolder:FindFirstChild("Soils")
	if soilsFolder then
		local soilPrefix = "Soil_" .. q .. "_" .. r .. "_"
		for _, subFolder in ipairs(soilsFolder:GetChildren()) do
			for _, child in ipairs(subFolder:GetChildren()) do
				if child.Name:sub(1, #soilPrefix) == soilPrefix then
					topY = math.max(topY, getYOfObject(child))
				end
			end
		end
	end

	-- 2) Gebäude prüfen (Geister/Baustellen ausgenommen)
	local buildingsFolder = hexMapFolder:FindFirstChild("Buildings")
	if buildingsFolder then
		local buildingSuffix = "_" .. q .. "_" .. r
		for _, child in ipairs(buildingsFolder:GetChildren()) do
			if child.Name:sub(-#buildingSuffix) == buildingSuffix
				and not child.Name:match("^Ghost_") then
				topY = math.max(topY, getYOfObject(child))
			end
		end
	end

	-- 3) Hex-Modell als Fallback
	local hexName = "Hex_" .. q .. "_" .. r
	for _, subFolder in ipairs(hexMapFolder:GetChildren()) do
		if subFolder:IsA("Folder")
			and subFolder.Name ~= "Soils"
			and subFolder.Name ~= "ArmyModels"
			and subFolder.Name ~= "ProvinceVisuals"
			and subFolder.Name ~= "Buildings" then
			local hex = subFolder:FindFirstChild(hexName)
			if hex then
				topY = math.max(topY, getYOfObject(hex))
			end
		end
	end

	return topY
end

--------------------------------------------------------------------------------
-- findArmyModel(armyId) -> Model or nil
--------------------------------------------------------------------------------
function ArmyModelMover.findArmyModel(armyId)
	local hexMap = workspace:FindFirstChild("HexMap")
	if not hexMap then return nil end

	local armyModels = hexMap:FindFirstChild("ArmyModels")
	if not armyModels then return nil end

	return armyModels:FindFirstChild("Army_" .. armyId)
end

--------------------------------------------------------------------------------
-- MoveModelToHex(armyId, q, r)
--------------------------------------------------------------------------------
function ArmyModelMover.MoveModelToHex(armyId, q, r)
	local model = ArmyModelMover.findArmyModel(armyId)
	if not model then
		warn("[ArmyModelMover] Model für Army " .. armyId .. " nicht gefunden")
		return
	end

	local worldPos = HexUtils.axialToWorld(q, r)
	local topY = HexHeightUtil.getTopY(q, r)
	local extraY = ArmyModelMover.Config.HEIGHT_OFFSET

	if model:IsA("Model") then
		local bboxCf, bboxSize = model:GetBoundingBox()
		local pivot = model:GetPivot()

		local pivotToBottom = pivot.Position.Y - (bboxCf.Position.Y - bboxSize.Y / 2)
		local targetPivotY = topY + extraY + pivotToBottom

		local originalRotation = pivot - pivot.Position
		local targetCFrame = CFrame.new(worldPos.X, targetPivotY, worldPos.Z) * originalRotation

		model:PivotTo(targetCFrame)
	elseif model:IsA("BasePart") then
		local halfY = model.Size.Y / 2
		model.Position = Vector3.new(worldPos.X, topY + extraY + halfY, worldPos.Z)
	end
end

--------------------------------------------------------------------------------
-- MoveModelAlongPath(armyId, path, startStep, endStep)
--------------------------------------------------------------------------------
function ArmyModelMover.MoveModelAlongPath(armyId, path, startStep, endStep)
	if not path or #path == 0 then return end

	startStep = startStep or 1
	endStep = endStep or #path

	for i = startStep, math.min(endStep, #path) do
		local hex = path[i]
		ArmyModelMover.MoveModelToHex(armyId, hex.q, hex.r)

		if i < endStep then
			task.wait(ArmyModelMover.Config.STEP_DELAY)
		end
	end
end

return ArmyModelMover