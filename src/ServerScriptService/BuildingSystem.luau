--[[
    BuildingSystem (ModuleScript)
    Ort: ServerScriptService > BuildingSystem
    
    Baut Gebäude auf Hexes.
    
    Ablauf beim Bauen:
      1. Prüfen ob Spieler genug Gold hat
      2. Prüfen ob Hex frei ist (kein Gebäude drauf)
      3. Gold abziehen
      4. Model aus ReplicatedStorage > Buildings klonen
      5. Model auf Hex platzieren (oben auf Soil/Terrain)
      6. In BuildingData speichern
      7. Wenn ClaimsProvince: Province automatisch claimen
--]]

local BuildingSystem = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HexUtils = require(script.Parent:WaitForChild("HexUtils"))
local HexData = require(script.Parent:WaitForChild("HexData"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local BuildingConfig = require(script.Parent:WaitForChild("BuildingConfig"))
local BuildingData = require(script.Parent:WaitForChild("BuildingData"))
local ClaimSystem = require(script.Parent:WaitForChild("ClaimSystem"))
local CampData = require(script.Parent:WaitForChild("CampData"))
local HexHeightUtil = require(ReplicatedStorage:WaitForChild("HexHeightUtil"))

--------------------------------------------------------------------------------
-- KONFIGURATION
--------------------------------------------------------------------------------
-- HINWEIS: Die Spawn-Höhe kommt jetzt zentral aus HexHeightUtil.getSpawnHeight
-- (Terrain-Oberkante + 0.5 Studs). HEIGHT_OFFSET bleibt als Kompatibilitätswert.
BuildingSystem.Config = {
	HEIGHT_OFFSET = HexHeightUtil.SPAWN_HEIGHT_OFFSET,
}

--------------------------------------------------------------------------------
-- Workspace Folder
--------------------------------------------------------------------------------
local buildingsFolder = nil

function BuildingSystem.getBuildingsFolder()
	if buildingsFolder and buildingsFolder.Parent then return buildingsFolder end

	local hexMap = workspace:FindFirstChild("HexMap")
	if not hexMap then
		hexMap = Instance.new("Folder")
		hexMap.Name = "HexMap"
		hexMap.Parent = workspace
	end

	buildingsFolder = hexMap:FindFirstChild("Buildings")
	if not buildingsFolder then
		buildingsFolder = Instance.new("Folder")
		buildingsFolder.Name = "Buildings"
		buildingsFolder.Parent = hexMap
	end

	return buildingsFolder
end

--------------------------------------------------------------------------------
-- findTopY(q, r) -> number
--------------------------------------------------------------------------------
function BuildingSystem.findTopY(q, r)
	local hexMapFolder = workspace:FindFirstChild("HexMap")
	if not hexMapFolder then
		return HexUtils.Config.SPAWN_Y + 2
	end

	-- Soil suchen
	local soilsFolder = hexMapFolder:FindFirstChild("Soils")
	if soilsFolder then
		local soilPrefix = "Soil_" .. q .. "_" .. r .. "_"
		for _, subFolder in ipairs(soilsFolder:GetChildren()) do
			for _, child in ipairs(subFolder:GetChildren()) do
				if child.Name:sub(1, #soilPrefix) == soilPrefix then
					if child:IsA("Model") and child.PrimaryPart then
						return child.PrimaryPart.Position.Y + child.PrimaryPart.Size.Y / 2
					elseif child:IsA("Model") then
						local cf, size = child:GetBoundingBox()
						return cf.Position.Y + size.Y / 2
					elseif child:IsA("BasePart") then
						return child.Position.Y + child.Size.Y / 2
					end
				end
			end
		end
	end

	-- Hex-Model suchen
	local hexName = "Hex_" .. q .. "_" .. r
	for _, subFolder in ipairs(hexMapFolder:GetChildren()) do
		if subFolder:IsA("Folder")
			and subFolder.Name ~= "Soils"
			and subFolder.Name ~= "ArmyModels"
			and subFolder.Name ~= "ProvinceVisuals"
			and subFolder.Name ~= "Buildings" then

			local hex = subFolder:FindFirstChild(hexName)
			if hex then
				if hex:IsA("Model") and hex.PrimaryPart then
					return hex.PrimaryPart.Position.Y + hex.PrimaryPart.Size.Y / 2
				elseif hex:IsA("Model") then
					local cf, size = hex:GetBoundingBox()
					return cf.Position.Y + size.Y / 2
				elseif hex:IsA("BasePart") then
					return hex.Position.Y + hex.Size.Y / 2
				end
			end
		end
	end

	return HexUtils.Config.SPAWN_Y + 2
end

--------------------------------------------------------------------------------
-- getBuildingTemplate(buildingType) -> Model or nil
--------------------------------------------------------------------------------
function BuildingSystem.getBuildingTemplate(buildingType)
	local config = BuildingConfig.GetBuilding(buildingType)
	if not config then
		warn("[BuildingSystem] Unbekannter Gebäude-Typ: " .. tostring(buildingType))
		return nil
	end

	local folder = ReplicatedStorage:FindFirstChild(BuildingConfig.FOLDER_NAME)
	if not folder then
		warn("[BuildingSystem] ReplicatedStorage > " .. BuildingConfig.FOLDER_NAME .. " nicht gefunden!")
		return nil
	end

	local template = folder:FindFirstChild(config.Model)
	if not template then
		warn("[BuildingSystem] Model '" .. config.Model .. "' nicht gefunden in " .. BuildingConfig.FOLDER_NAME)
		return nil
	end

	return template
end

--------------------------------------------------------------------------------
-- placeBuildingModel(buildingType, q, r) -> Model or nil
--------------------------------------------------------------------------------
function BuildingSystem.placeBuildingModel(buildingType, q, r)
	local template = BuildingSystem.getBuildingTemplate(buildingType)
	if not template then return nil end

	local model = template:Clone()
	model.Name = buildingType .. "_" .. q .. "_" .. r

	local folder = BuildingSystem.getBuildingsFolder()
	model.Parent = folder

	-- Position dynamisch anhand der tatsächlichen Terrain-Höhe (Soil/Gebäude/
	-- Hex-Modell), NICHT anhand einer festen SPAWN_Y.
	local worldPos = HexUtils.axialToWorld(q, r)
	local spawnY = HexHeightUtil.getSpawnHeight(q, r)

	if model:IsA("Model") then
		local bboxCf, bboxSize = model:GetBoundingBox()
		local pivot = model:GetPivot()

		local pivotToBottom = pivot.Position.Y - (bboxCf.Position.Y - bboxSize.Y / 2)
		local targetPivotY = spawnY + pivotToBottom

		local rotation = pivot - pivot.Position
		model:PivotTo(CFrame.new(worldPos.X, targetPivotY, worldPos.Z) * rotation)
	elseif model:IsA("BasePart") then
		local halfY = model.Size.Y / 2
		model.Position = Vector3.new(worldPos.X, spawnY + halfY, worldPos.Z)
	end

	return model
end

--------------------------------------------------------------------------------
-- CanBuild(player, buildingType, q, r) -> boolean, reason
--------------------------------------------------------------------------------
function BuildingSystem.CanBuild(player, buildingType, q, r)
	local config = BuildingConfig.GetBuilding(buildingType)
	if not config then
		return false, "Unbekannter Gebäude-Typ"
	end

	-- Hex prüfen
	local hex = HexData.GetHex(q, r)
	if not hex then
		return false, "Hex existiert nicht"
	end

	-- Bereits Gebäude auf dem Hex?
	if BuildingData.HasBuildingOnHex(q, r) then
		return false, "Hex hat bereits ein Gebäude"
	end

	-- Genug Gold?
	if not PlayerData.CanAfford(player, config.Cost) then
		return false, "Nicht genug Gold (" .. PlayerData.GetGold(player) .. "/" .. config.Cost .. ")"
	end

	return true, nil
end

--------------------------------------------------------------------------------
-- BuildBuilding(player, buildingType, q, r) -> buildingId or nil
--------------------------------------------------------------------------------
function BuildingSystem.BuildBuilding(player, buildingType, q, r)
	local canBuild, reason = BuildingSystem.CanBuild(player, buildingType, q, r)
	if not canBuild then
		warn("[BuildingSystem] Bauen nicht möglich: " .. tostring(reason))
		return nil, reason
	end

	local config = BuildingConfig.GetBuilding(buildingType)
	local hex = HexData.GetHex(q, r)
	local provinceId = hex.province

	-- Gold abziehen
	local paid = PlayerData.SpendGold(player, config.Cost)
	if not paid then
		warn("[BuildingSystem] Gold-Abzug fehlgeschlagen")
		return nil, "Gold-Abzug fehlgeschlagen"
	end

	-- Model platzieren
	local model = BuildingSystem.placeBuildingModel(buildingType, q, r)
	if not model then
		-- Gold zurückgeben
		PlayerData.AddGold(player, config.Cost)
		return nil, "Model konnte nicht platziert werden"
	end

	-- In BuildingData speichern
	local buildingId = BuildingData.CreateBuilding(buildingType, player, q, r, provinceId)

	-- HexData aktualisieren
	HexData.UpdateHex(q, r, { building = buildingType })

	print("[BuildingSystem] " .. buildingType .. " gebaut von " .. player.Name .. " auf (" .. q .. ", " .. r .. ") für " .. config.Cost .. " Gold")

	-- Province automatisch claimen
	if config.ClaimsProvince and provinceId and provinceId > 0 then
		ClaimSystem.ClaimProvince(player, provinceId)
		print("[BuildingSystem] Province " .. provinceId .. " automatisch geclaimed")
	end

	-- Wenn es ein Camp ist: CampData-Eintrag erstellen
	if buildingType == "Camp" then
		CampData.CreateCamp(buildingId, provinceId, player, q, r)
		print("[BuildingSystem] CampData-Eintrag erstellt")
	end

	return buildingId, nil
end

--------------------------------------------------------------------------------
-- DestroyBuilding(buildingId)
--------------------------------------------------------------------------------
function BuildingSystem.DestroyBuilding(buildingId)
	local building = BuildingData.GetBuilding(buildingId)
	if not building then return false end

	-- Model entfernen
	local folder = BuildingSystem.getBuildingsFolder()
	local modelName = building.buildingType .. "_" .. building.q .. "_" .. building.r
	local model = folder:FindFirstChild(modelName)
	if model then
		model:Destroy()
	end

	-- HexData leeren (ClearHexField, da { building = nil } ein No-Op wäre)
	HexData.ClearHexField(building.q, building.r, "building")

	-- Aus Daten entfernen
	BuildingData.RemoveBuilding(buildingId)

	print("[BuildingSystem] Gebäude " .. buildingId .. " zerstört")
	return true
end

return BuildingSystem