--[[
    CitySystem (ModuleScript)
    Ort: ServerScriptService > CitySystem
    
    Wandelt ein Camp in eine City um.
--]]

local CitySystem = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HexUtils = require(script.Parent:WaitForChild("HexUtils"))
local HexData = require(script.Parent:WaitForChild("HexData"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local CampData = require(script.Parent:WaitForChild("CampData"))
local CityData = require(script.Parent:WaitForChild("CityData"))
local BuildingData = require(script.Parent:WaitForChild("BuildingData"))
local BuildingConfig = require(script.Parent:WaitForChild("BuildingConfig"))
local ProvinceData = require(script.Parent:WaitForChild("ProvinceData"))
local SoilGenerator = require(script.Parent:WaitForChild("SoilGenerator"))
local HexHeightUtil = require(ReplicatedStorage:WaitForChild("HexHeightUtil"))
local PointSystem = require(script.Parent:WaitForChild("PointSystem"))
local VictoryConfig = require(ReplicatedStorage:WaitForChild("VictoryConfig"))

--------------------------------------------------------------------------------
-- KONFIGURATION
--------------------------------------------------------------------------------
CitySystem.Config = {
	CITY_COST = 200,
	CITY_MODEL_NAME = "City",
	HEIGHT_OFFSET = 0.2,
}

--------------------------------------------------------------------------------
-- Workspace Folder
--------------------------------------------------------------------------------
local function getBuildingsFolder()
	local hexMap = workspace:FindFirstChild("HexMap")
	if not hexMap then return nil end
	return hexMap:FindFirstChild("Buildings")
end

--------------------------------------------------------------------------------
-- findTopY(q, r) -> number
--------------------------------------------------------------------------------
local function findTopY(q, r)
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
-- swapModelToCity(q, r) -> Model or nil
--------------------------------------------------------------------------------
function CitySystem.swapModelToCity(q, r)
	local folder = getBuildingsFolder()
	if not folder then
		warn("[CitySystem] Buildings-Folder nicht gefunden")
		return nil
	end

	-- Altes Camp-Model löschen
	local campModel = folder:FindFirstChild("Camp_" .. q .. "_" .. r)
	if campModel then
		campModel:Destroy()
	end

	-- City-Template holen
	local storageFolder = ReplicatedStorage:FindFirstChild(BuildingConfig.FOLDER_NAME)
	if not storageFolder then
		warn("[CitySystem] ReplicatedStorage > " .. BuildingConfig.FOLDER_NAME .. " nicht gefunden")
		return nil
	end

	local template = storageFolder:FindFirstChild(CitySystem.Config.CITY_MODEL_NAME)
	if not template then
		warn("[CitySystem] Model '" .. CitySystem.Config.CITY_MODEL_NAME .. "' nicht gefunden in " .. BuildingConfig.FOLDER_NAME)
		return nil
	end

	-- City-Model klonen und platzieren
	local model = template:Clone()
	model.Name = "City_" .. q .. "_" .. r
	model.Parent = folder

	local worldPos = HexUtils.axialToWorld(q, r)
	local topY = HexHeightUtil.getTopY(q, r)
	local extraY = CitySystem.Config.HEIGHT_OFFSET

	if model:IsA("Model") then
		local bboxCf, bboxSize = model:GetBoundingBox()
		local pivot = model:GetPivot()

		local pivotToBottom = pivot.Position.Y - (bboxCf.Position.Y - bboxSize.Y / 2)
		local targetPivotY = topY + extraY + pivotToBottom

		local rotation = pivot - pivot.Position
		model:PivotTo(CFrame.new(worldPos.X, targetPivotY, worldPos.Z) * rotation)
	elseif model:IsA("BasePart") then
		local halfY = model.Size.Y / 2
		model.Position = Vector3.new(worldPos.X, topY + extraY + halfY, worldPos.Z)
	end

	return model
end

--------------------------------------------------------------------------------
-- recolorProvinceToCityColor(provinceId, player)
--------------------------------------------------------------------------------
function CitySystem.recolorProvinceToCityColor(provinceId, player)
	if not provinceId or provinceId <= 0 then return end

	local playerColor = PlayerData.GetColor(player)

	ProvinceData.SetProvinceColor(provinceId, playerColor)

	local hexMap = workspace:FindFirstChild("HexMap")
	if not hexMap then return end

	local provinceVisuals = hexMap:FindFirstChild("ProvinceVisuals")
	if not provinceVisuals then return end

	local provinceModel = provinceVisuals:FindFirstChild("Province_" .. provinceId)
	if not provinceModel then return end

	for _, part in ipairs(provinceModel:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Color = playerColor
		end
	end

	print("[CitySystem] Province " .. provinceId .. " auf volle Spielerfarbe gesetzt")
end

--------------------------------------------------------------------------------
-- CanFoundCity(player, campId) -> boolean, reason
--------------------------------------------------------------------------------
function CitySystem.CanFoundCity(player, campId)
	local camp = CampData.GetCamp(campId)
	if not camp then
		return false, "Camp nicht gefunden"
	end

	if camp.owner ~= player then
		return false, "Camp gehört nicht dir"
	end

	if not PlayerData.CanAfford(player, CitySystem.Config.CITY_COST) then
		return false, "Nicht genug Gold (" .. PlayerData.GetGold(player) .. "/" .. CitySystem.Config.CITY_COST .. ")"
	end

	return true, nil
end

--------------------------------------------------------------------------------
-- FoundCity(player, campId) -> cityId or nil, reason
--------------------------------------------------------------------------------
function CitySystem.FoundCity(player, campId)
	local canFound, reason = CitySystem.CanFoundCity(player, campId)
	if not canFound then
		warn("[CitySystem] City-Gründung nicht möglich: " .. tostring(reason))
		return nil, reason
	end

	local camp = CampData.GetCamp(campId)
	local q, r = camp.q, camp.r
	local provinceId = camp.provinceId

	-- Gold abziehen
	local paid = PlayerData.SpendGold(player, CitySystem.Config.CITY_COST)
	if not paid then
		return nil, "Gold-Abzug fehlgeschlagen"
	end

	-- Model tauschen
	local model = CitySystem.swapModelToCity(q, r)
	if not model then
		PlayerData.AddGold(player, CitySystem.Config.CITY_COST)
		return nil, "City-Model konnte nicht platziert werden"
	end

	-- Daten von Camp → City übertragen (nur owner, q, r, provinceId!)
	local cityId = CityData.CreateCityFromCamp(camp)
	if not cityId then
		PlayerData.AddGold(player, CitySystem.Config.CITY_COST)
		return nil, "CityData konnte nicht erstellt werden"
	end

	CampData.RemoveCamp(campId)

	local building = BuildingData.GetBuildingOnHex(q, r)
	if building then
		building.buildingType = "City"
	end

	HexData.UpdateHex(q, r, { building = "City" })

	-- Das City-Gebäude in die city.buildings Liste eintragen
	local city = CityData.GetCity(cityId)
	if city then
		local alreadyAdded = false
		for _, b in ipairs(city.buildings or {}) do
			if b.buildingType == "City" then
				alreadyAdded = true
				break
			end
		end
		if not alreadyAdded then
			CityData.AddBuilding(cityId, camp.buildingId or 0, "City", q, r)
			print("[CitySystem] City-Gebäude in buildings-Liste eingetragen!")
		end
	end

	-- Arbeiter-Stats sofort bei der Gründung berechnen (mit pcall um hängen zu vermeiden!)
	local success, err = pcall(function()
		local CityEconomySystem = require(script.Parent:WaitForChild("CityEconomySystem"))
		CityEconomySystem.UpdateStats(cityId)
	end)
	if not success then
		warn("[CitySystem] Fehler bei ResourceSystem Initialisierung: " .. tostring(err))
	else
		print("[CitySystem] Arbeiter-Stats initialisiert!")
	end

	CitySystem.recolorProvinceToCityColor(provinceId, player)

	-- VICTORY: Erste City eines Spielers wird automatisch zur HAUPTSTADT.
	-- Jede City-Gründung bringt +75 Punkte.
	pcall(PointSystem.AwardPoints, player, "CityFounded", VictoryConfig.ACTIVE_POINTS.CityFounded)
	if not PlayerData.GetCapitalCityId(player) then
		PlayerData.SetCapitalCityId(player, cityId)
		CitySystem.addCapitalMarker(model, q, r, player.Name)
		pcall(CitySystem.broadcastCapitalMarked, player, cityId, q, r)
		print("[CitySystem] Dies ist die HAUPTSTADT von " .. player.Name)
	end

	print("[CitySystem] City gegründet: " .. CityData.GetName(cityId) .. " (ID: " .. cityId .. ") von " .. player.Name)
	return cityId, nil
end

--------------------------------------------------------------------------------
-- addCapitalMarker(model, q, r, playerName) - EHEMALS goldener Stern.
--
-- ERSETZT durch das Hauptstadt-Fantasy-Banner aus CityBannerController
-- (client-seitig, code-generiert, Gold-Rahmen + Krone + Glow - siehe
-- StarterPlayerScripts > CityBannerController.client.luau). Diese Funktion
-- ist bewusst zu einem No-Op geworden (keine BillboardGui mehr), damit der
-- alte Stern nicht mehr entsteht. Sie bleibt als Funktion erhalten, falls
-- andere Server-Scripts sie noch aufrufen (siehe FoundCity oben) - ein
-- Loeschen des Aufrufs war nicht noetig, da der Stern jetzt serverseitig
-- schlicht nicht mehr erzeugt wird.
--------------------------------------------------------------------------------
function CitySystem.addCapitalMarker(model, q, r, playerName)
	if not model then return end

	-- Altes CapitalMarker-BillboardGui entfernen, falls es (z.B. aus einem
	-- alten Spielstand/Studio-Test) noch existiert.
	local oldMarker = model:FindFirstChild("CapitalMarker")
	if oldMarker then
		oldMarker:Destroy()
	end

	return nil
end

--------------------------------------------------------------------------------
-- broadcastCapitalMarked(player, cityId, q, r)
--------------------------------------------------------------------------------
function CitySystem.broadcastCapitalMarked(player, cityId, q, r)
	local dataRemotes = ReplicatedStorage:WaitForChild("DataRemotes", 30)
	local rem = dataRemotes and dataRemotes:FindFirstChild("CapitalCityMarked")
	if not rem then return end
	pcall(function()
		rem:FireAllClients({
			playerId = player.UserId,
			playerName = player.Name,
			cityId = cityId,
			q = q,
			r = r,
		})
	end)
end

--------------------------------------------------------------------------------
-- LADE-CHECK: Bestaetigt beim Laden dass alle oeffentlichen Funktionen
-- definiert sind. Wenn eine Funktion fehlt, erscheint sofort eine klare
-- Warnung im Output (statt eines spaeteren nil-Fehlers beim Aufruf).
--------------------------------------------------------------------------------
local _required = { "FoundCity", "CanFoundCity", "swapModelToCity", "recolorProvinceToCityColor" }
for _, fnName in ipairs(_required) do
	if type(CitySystem[fnName]) ~= "function" then
		warn("[CitySystem] KRITISCH: Funktion '" .. fnName .. "' fehlt!")
	end
end
print("[CitySystem] Geladen. FoundCity verfügbar: "
	.. tostring(type(CitySystem.FoundCity) == "function"))

return CitySystem
