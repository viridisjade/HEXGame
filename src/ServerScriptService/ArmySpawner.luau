--[[
    ArmySpawner (ModuleScript)
    Ort: ServerScriptService > ArmySpawner
    
    Spawnt Units in Armeen auf der Map.
    Kombiniert ArmySystem, UnitData, ArmyModelGiver und Hex-Positionierung.
--]]

local ArmySpawner = {}

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HexUtils = require(script.Parent:WaitForChild("HexUtils"))
local HexData = require(script.Parent:WaitForChild("HexData"))
local ArmyData = require(script.Parent:WaitForChild("ArmyData"))
local UnitData = require(script.Parent:WaitForChild("UnitData"))
local ArmySystem = require(script.Parent:WaitForChild("ArmySystem"))
local ArmyModelGiver = require(script.Parent:WaitForChild("ArmyModelGiver"))
local UnitConfig = require(ReplicatedStorage:WaitForChild("UnitConfig"))
local HexHeightUtil = require(ReplicatedStorage:WaitForChild("HexHeightUtil"))

--------------------------------------------------------------------------------
-- KONFIGURATION
--------------------------------------------------------------------------------
ArmySpawner.Config = {
	VISUAL_HEIGHT_OFFSET = 0.35,
}

--------------------------------------------------------------------------------
-- Workspace Folder für gespawnte Army-Models
--------------------------------------------------------------------------------
local armyModelsFolder = nil

function ArmySpawner.getArmyModelsFolder()
	if armyModelsFolder then return armyModelsFolder end

	local hexMap = workspace:FindFirstChild("HexMap")
	if not hexMap then
		hexMap = Instance.new("Folder")
		hexMap.Name = "HexMap"
		hexMap.Parent = workspace
	end

	armyModelsFolder = hexMap:FindFirstChild("ArmyModels")
	if not armyModelsFolder then
		armyModelsFolder = Instance.new("Folder")
		armyModelsFolder.Name = "ArmyModels"
		armyModelsFolder.Parent = hexMap
	end

	return armyModelsFolder
end

--------------------------------------------------------------------------------
-- findTopY(q, r) -> number
-- Zentral im HexHeightUtil implementiert (statt 6 Kopien).
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

function ArmySpawner.findTopY(q, r)
	local hexMapFolder = workspace:FindFirstChild("HexMap")
	if not hexMapFolder then
		return HexUtils.Config.SPAWN_Y + 2
	end

	local topY = HexUtils.Config.SPAWN_Y + 2

	local soilPrefix = "Soil_" .. q .. "_" .. r .. "_"
	local soilsFolder = hexMapFolder:FindFirstChild("Soils")
	if soilsFolder then
		for _, subFolder in ipairs(soilsFolder:GetChildren()) do
			for _, child in ipairs(subFolder:GetChildren()) do
				if child.Name:sub(1, #soilPrefix) == soilPrefix then
					topY = math.max(topY, getYOfObject(child))
				end
			end
		end
	end

	-- Auch Gebäude (City, Bastion etc.) prüfen
	local buildingsFolder = hexMapFolder:FindFirstChild("Buildings")
	if buildingsFolder then
		local buildingSuffix = "_" .. q .. "_" .. r
		for _, child in ipairs(buildingsFolder:GetChildren()) do
			if child.Name:sub(-#buildingSuffix) == buildingSuffix and not child.Name:match("^Ghost_") then
				topY = math.max(topY, getYOfObject(child))
			end
		end
	end

	-- Hex-Model als absoluter Boden-Fallback
	local hexName = "Hex_" .. q .. "_" .. r
	for _, subFolder in ipairs(hexMapFolder:GetChildren()) do
		if subFolder:IsA("Folder") and subFolder.Name ~= "Soils" and subFolder.Name ~= "ArmyModels" and subFolder.Name ~= "ProvinceVisuals" and subFolder.Name ~= "Buildings" then
			local hex = subFolder:FindFirstChild(hexName)
			if hex then
				topY = math.max(topY, getYOfObject(hex))
			end
		end
	end

	return topY
end

--------------------------------------------------------------------------------
-- removeArmyModel(armyId)
--------------------------------------------------------------------------------
function ArmySpawner.removeArmyModel(armyId)
	local folder = ArmySpawner.getArmyModelsFolder()
	local modelName = "Army_" .. armyId

	local existing = folder:FindFirstChild(modelName)
	if existing then
		existing:Destroy()
	end
end

--------------------------------------------------------------------------------
-- placeArmyModel(armyId, q, r)
--------------------------------------------------------------------------------
function ArmySpawner.placeArmyModel(armyId, q, r)
	ArmySpawner.removeArmyModel(armyId)

	local model = ArmyModelGiver.GetModel(armyId)
	if not model then
		warn("[ArmySpawner] Kein Model für Army " .. armyId)
		return nil
	end

	model.Name = "Army_" .. armyId

	-- Owner-Info als Attribut setzen, damit der FogOfWarController (Client)
	-- eigene Armeen immer sichtbar halten und feindliche nach Sichtfeld blenden
	-- kann.
	local army = ArmyData.GetArmy(armyId)
	if army and army.owner then
		model:SetAttribute("OwnerUserId", army.owner.UserId)
	else
		model:SetAttribute("OwnerUserId", nil)
	end

	-- ZUERST in Workspace packen (GetBoundingBox / GetPivot brauchen Parent)
	local folder = ArmySpawner.getArmyModelsFolder()
	model.Parent = folder

	-- SICHERSTELLEN, dass die Army von der Maus getroffen werden kann!
	local function setClickable(obj)
		if obj:IsA("BasePart") then
			obj.CanQuery = true
		end
	end

	if model:IsA("Model") then
		for _, part in ipairs(model:GetDescendants()) do
			setClickable(part)
		end
	elseif model:IsA("BasePart") then
		setClickable(model)
	end

	-- Position berechnen
	local worldPos = HexUtils.axialToWorld(q, r)
	local topY = HexHeightUtil.getTopY(q, r)
	local extraY = ArmySpawner.Config.VISUAL_HEIGHT_OFFSET

	-- Model platzieren: Unterkante exakt auf topY + extraY
	if model:IsA("Model") then
		local bboxCf, bboxSize = model:GetBoundingBox()
		local pivot = model:GetPivot()

		local pivotToBottomOffset = pivot.Position.Y - (bboxCf.Position.Y - bboxSize.Y / 2)
		local targetPivotY = topY + extraY + pivotToBottomOffset

		local originalRotation = pivot - pivot.Position
		local targetCFrame = CFrame.new(worldPos.X, targetPivotY, worldPos.Z) * originalRotation

		model:PivotTo(targetCFrame)
	elseif model:IsA("BasePart") then
		local halfY = model.Size.Y / 2
		model.Position = Vector3.new(worldPos.X, topY + extraY + halfY, worldPos.Z)
	end

	return model
end

--------------------------------------------------------------------------------
-- SpawnUnit(owner, unitType, q, r) -> armyId, unitId
--------------------------------------------------------------------------------
function ArmySpawner.SpawnUnit(owner, unitType, q, r)
	local config = UnitConfig.GetUnit(unitType)
	if not config then
		warn("[ArmySpawner] Unbekannter UnitType: " .. tostring(unitType))
		return nil, nil
	end

	-- 1. Hex prüfen
	local hex = HexData.GetHex(q, r)
	if not hex then
		warn("[ArmySpawner] Hex (" .. q .. ", " .. r .. ") existiert nicht")
		return nil, nil
	end

	local armyId = nil
	local existingArmy = false

	-- WICHTIG: Nicht blind hex.army vertrauen!
	local actualArmyOnHex = ArmyData.GetArmyOnHex(q, r)

	if hex.army and (not actualArmyOnHex or actualArmyOnHex.id ~= hex.army) then
		print("[ArmySpawner] Veralteten HexData.army Eintrag auf (" .. q .. ", " .. r .. ") bereinigt: " .. tostring(hex.army))
		HexData.UpdateHex(q, r, { army = actualArmyOnHex and actualArmyOnHex.id or nil })
	end

	if actualArmyOnHex then
		if actualArmyOnHex.owner ~= owner then
			warn("[ArmySpawner] Hex (" .. q .. ", " .. r .. ") hat eine fremde Army")
			return nil, nil
		end

		if ArmySystem.IsArmyFull(actualArmyOnHex.id) then
			warn("[ArmySpawner] Army " .. actualArmyOnHex.id .. " auf Hex (" .. q .. ", " .. r .. ") ist voll")
			return nil, nil
		end

		armyId = actualArmyOnHex.id
		existingArmy = true
	end

	-- 2. Armee erstellen falls keine da
	if not armyId then
		armyId = ArmySystem.SpawnArmy(owner, q, r)
		if not armyId then
			warn("[ArmySpawner] Konnte keine Army auf (" .. q .. ", " .. r .. ") erstellen")
			return nil, nil
		end
	end

	-- 3. Unit erstellen
	local unitId = UnitData.CreateUnit(unitType, owner)
	if not unitId then
		if not existingArmy then
			ArmySystem.DeleteArmy(armyId)
		end
		warn("[ArmySpawner] Konnte Unit '" .. unitType .. "' nicht erstellen")
		return nil, nil
	end

	-- 4. Unit in Armee legen
	local added = ArmySystem.AddUnit(armyId, unitId)
	if not added then
		UnitData.RemoveUnit(unitId)
		if not existingArmy then
			ArmySystem.DeleteArmy(armyId)
		end
		warn("[ArmySpawner] Konnte Unit nicht zur Army hinzufügen")
		return nil, nil
	end

	-- 5+6. Model holen und auf Hex platzieren
	ArmySpawner.placeArmyModel(armyId, q, r)

	print("[ArmySpawner] Unit '" .. unitType .. "' gespawnt in Army " .. armyId .. " auf (" .. q .. ", " .. r .. ")")
	return armyId, unitId
end

--------------------------------------------------------------------------------
-- RefreshArmyModel(armyId)
--------------------------------------------------------------------------------
function ArmySpawner.RefreshArmyModel(armyId)
	local army = ArmyData.GetArmy(armyId)
	if not army then return end

	if #army.units == 0 then
		ArmySpawner.removeArmyModel(armyId)
		return
	end

	ArmySpawner.placeArmyModel(armyId, army.q, army.r)
end

--------------------------------------------------------------------------------
-- DespawnArmy(armyId)
--------------------------------------------------------------------------------
function ArmySpawner.DespawnArmy(armyId)
	ArmySpawner.removeArmyModel(armyId)
	ArmySystem.DeleteArmy(armyId)
	print("[ArmySpawner] Army " .. armyId .. " despawnt")
end

--------------------------------------------------------------------------------
-- ClearAllArmyModels()
--------------------------------------------------------------------------------
function ArmySpawner.ClearAllArmyModels()
	local folder = workspace:FindFirstChild("HexMap")
	if folder then
		local models = folder:FindFirstChild("ArmyModels")
		if models then
			models:Destroy()
			armyModelsFolder = nil
			print("[ArmySpawner] Alle Army-Models gelöscht")
		end
	end
end

return ArmySpawner