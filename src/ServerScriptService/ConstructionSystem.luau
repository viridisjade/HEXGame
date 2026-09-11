
--[[
    ConstructionSystem (ModuleScript)
    Ort: ServerScriptService > ConstructionSystem
    
    Verwaltet die sequenzielle Warteschlange (Gebäude & Units) der Städte.
--]]

local ConstructionSystem = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HexUtils = require(script.Parent:WaitForChild("HexUtils"))
local HexData = require(script.Parent:WaitForChild("HexData"))
local BuildingConfig = require(script.Parent:WaitForChild("BuildingConfig"))
local BuildingData = require(script.Parent:WaitForChild("BuildingData"))
local CityData = require(script.Parent:WaitForChild("CityData"))
local UnitConfig = require(ReplicatedStorage:WaitForChild("UnitConfig"))
local SoilGenerator = require(script.Parent:WaitForChild("SoilGenerator"))
local CityEconomySystem = require(script.Parent:WaitForChild("CityEconomySystem"))
local HexHeightUtil = require(ReplicatedStorage:WaitForChild("HexHeightUtil"))

local UnitSpawner = require(script.Parent:WaitForChild("UnitSpawner"))
local CombatData = require(script.Parent:WaitForChild("CombatData"))
local FogOfWarSystem = require(script.Parent:WaitForChild("FogOfWarSystem"))

-- Lazy tech access (avoids require cycles).
local _techSystem
local function Tech()
	if not _techSystem then
		local ok, mod = pcall(function()
			return require(script.Parent:WaitForChild("TechTreeSystem"))
		end)
		_techSystem = ok and mod or false
	end
	return _techSystem or nil
end

local buildingsFolder = ReplicatedStorage:WaitForChild("Buildings")
local workspaceBuildings = nil

local function getWorkspaceBuildings()
	if workspaceBuildings and workspaceBuildings.Parent then return workspaceBuildings end
	local hexMap = workspace:FindFirstChild("HexMap")
	if not hexMap then
		hexMap = Instance.new("Folder")
		hexMap.Name = "HexMap"
		hexMap.Parent = workspace
	end
	workspaceBuildings = hexMap:FindFirstChild("Buildings")
	if not workspaceBuildings then
		workspaceBuildings = Instance.new("Folder")
		workspaceBuildings.Name = "Buildings"
		workspaceBuildings.Parent = hexMap
	end
	return workspaceBuildings
end

local function findTopY(q, r)
	local hexMap = workspace:FindFirstChild("HexMap")
	if not hexMap then return HexUtils.Config.SPAWN_Y + 2 end
	local soils = hexMap:FindFirstChild("Soils")
	if soils then
		local prefix = "Soil_" .. q .. "_" .. r .. "_"
		for _, soilFolder in ipairs(soils:GetChildren()) do
			for _, object in ipairs(soilFolder:GetChildren()) do
				if object.Name:sub(1, #prefix) == prefix then
					if object:IsA("Model") then
						local cf, size = object:GetBoundingBox()
						return cf.Position.Y + size.Y / 2
					elseif object:IsA("BasePart") then
						return object.Position.Y + object.Size.Y / 2
					end
				end
			end
		end
	end
	return HexUtils.Config.SPAWN_Y + 2
end

local function placeModel(buildingType, q, r, isGhost)
	local config = BuildingConfig.GetBuilding(buildingType)
	if not config then return nil end
	local template = buildingsFolder:FindFirstChild(config.Model)
	if not template then return nil end

	local object = template:Clone()
	object.Name = (isGhost and "Ghost_" or "") .. buildingType .. "_" .. q .. "_" .. r
	object.Parent = getWorkspaceBuildings()

	-- Position dynamisch anhand der tatsächlichen Terrain-Höhe (Soil/Gebäude/
	-- Hex-Modell), NICHT anhand einer festen SPAWN_Y.
	local worldPos = HexUtils.axialToWorld(q, r)
	local spawnY = HexHeightUtil.getSpawnHeight(q, r)

	if object:IsA("Model") then
		local bboxCf, bboxSize = object:GetBoundingBox()
		local pivot = object:GetPivot()
		local pivotToBottom = pivot.Position.Y - (bboxCf.Position.Y - bboxSize.Y / 2)
		local rotation = pivot - pivot.Position
		object:PivotTo(CFrame.new(worldPos.X, spawnY + pivotToBottom, worldPos.Z) * rotation)
	elseif object:IsA("BasePart") then
		object.Position = Vector3.new(worldPos.X, spawnY + object.Size.Y / 2, worldPos.Z)
	end

	if isGhost then
		local parts = object:IsA("BasePart") and { object } or object:GetDescendants()
		for _, part in ipairs(parts) do
			if part:IsA("BasePart") then
				part.Transparency = 0.6
				part.CanCollide = false
				part.CanQuery = false
				part.Anchored = true
			end
		end
	end
	return object
end

function ConstructionSystem.GetValidSpawnHexes(cityId)
	local city = CityData.GetCity(cityId)
	if not city then return {} end

	local hexes = {}

	for _, b in ipairs(city.buildings or {}) do
		if b.buildingType == "City" or b.buildingType == "Bastion" then
			table.insert(hexes, {q = b.q, r = b.r})
		end
	end

	return hexes
end

function ConstructionSystem.TrySpawnUnit(cityId, order)
	local city = CityData.GetCity(cityId)
	if not city then return false, "CityMissing" end

	local spawnQ = order.spawnQ or order.q
	local spawnR = order.spawnR or order.r

	-- NEW: no reinforcements onto a hex that is currently contested.
	if CombatData.IsHexContested(spawnQ, spawnR) then
		print("[ConstructionSystem] Spawn blockiert: Auf dem Hex laeuft ein Kampf")
		return false, "HexInCombat"
	end

	local hex = HexData.GetHex(spawnQ, spawnR)
	if not hex then 
		print("[ConstructionSystem] Spawn blockiert: Hex existiert nicht")
		return false, "InvalidHex" 
	end

	local success, result = UnitSpawner.Spawn(city.owner, order.unitType, spawnQ, spawnR)

	if not success then
		print("[ConstructionSystem] Spawn fehlgeschlagen wegen: " .. tostring(result))
	end

	return success, result
end

function ConstructionSystem.CanPlaceBuilding(player, cityId, buildingType, q, r)
	local city = CityData.GetCity(cityId)
	if not city then return false, "Stadt nicht gefunden" end
	if city.owner ~= player then return false, "Stadt gehört nicht dir" end

	local config = BuildingConfig.GetBuilding(buildingType)
	if not config or not config.IndustryCost then return false, "Ungültiger Gebäude-Typ" end

	local hex = HexData.GetHex(q, r)
	if not hex then return false, "Hex existiert nicht" end
	if hex.province ~= city.provinceId then return false, "Nicht im Stadtgebiet" end
	if hex.building then return false, "Hex hat bereits ein Gebäude/Bauprojekt" end

	return true
end

function ConstructionSystem.StartConstruction(player, cityId, buildingType, q, r)
	local canBuild, reason = ConstructionSystem.CanPlaceBuilding(player, cityId, buildingType, q, r)
	if not canBuild then return false, reason end

	local config = BuildingConfig.GetBuilding(buildingType)

	local BuildingCostSystem = require(script.Parent:WaitForChild("BuildingCostSystem"))
	local actualCost = BuildingCostSystem.GetBuildingCost(cityId, buildingType)

	----------------------------------------------------------------------
	-- TECH Engineering: buildings finish 1 round earlier. We express that
	-- as a discount worth one round of industry output.
	----------------------------------------------------------------------
	local tech = Tech()
	if tech and player then
		local roundsSaved = tech.GetSpecial(player, "BuildSpeedRounds")
		if roundsSaved > 0 then
			local perRound = tonumber(city.currentIndustryProduction) or 0
			if perRound > 0 then
				actualCost = math.max(1, math.floor(actualCost - perRound * roundsSaved))
			end
		end
	end

	print("[ConstructionSystem] " .. buildingType .. " kostet " .. actualCost .. " (Base: " .. config.IndustryCost .. ", Stufe " .. BuildingCostSystem.GetStage(cityId) .. ", x" .. string.format("%.1f", BuildingCostSystem.GetMultiplier(cityId)) .. ")")

	local order = CityData.AddBuildOrder(cityId, {
		orderType = "Building",
		buildingType = buildingType,
		q = q,
		r = r,
		industryCost = actualCost,
	})
	if not order then return false, "Hex blockiert" end

	placeModel(buildingType, q, r, true)
	HexData.UpdateHex(q, r, { building = "Construction:" .. buildingType })
	return true, order
end

function ConstructionSystem.StartUnitRecruitment(player, cityId, unitType, spawnQ, spawnR)
	local city = CityData.GetCity(cityId)
	if not city or city.owner ~= player then return false, "Not your city" end

	local config = UnitConfig.GetUnit(unitType)
	if not config then return false, "Invalid unit" end

	local popCost = tonumber(config.CitizenCost) or 0

	print("[UnitProd] StartUnitRecruitment für " .. tostring(unitType) .. " (CitizenCost: " .. popCost .. ")")
	print("[UnitProd] Bevölkerung VOR: " .. tostring(city.population))

	if popCost > 0 then
		if (city.population or 0) - popCost < 1 then
			print("[UnitProd] ABGELEHNT - Nicht genug Bevölkerung! (" .. city.population .. " verfügbar, " .. popCost .. " nötig)")
			return false, "Nicht genug Bevölkerung!"
		end
	end

	----------------------------------------------------------------------
	-- TECH Mass Production: -20% industry cost on unit recruitment.
	----------------------------------------------------------------------
	local unitCost = tonumber(config.IndustryCost) or 0
	local techMod = Tech()
	if techMod and player then
		local mult = techMod.GetCostMultiplier(player, "UnitRecruitment")
		unitCost = math.max(1, math.floor(unitCost * mult))
	end

	local validHexes = ConstructionSystem.GetValidSpawnHexes(cityId)
	local isValid = false
	for _, h in ipairs(validHexes) do
		if h.q == spawnQ and h.r == spawnR then isValid = true break end
	end
	if not isValid then return false, "Invalid spawn hex" end

	if popCost > 0 then
		local totalSlots = 0
		for _, slots in pairs(city.jobSlots or {}) do
			totalSlots = totalSlots + (tonumber(slots) or 0)
		end

		local overpopAfter = math.max(0, city.population - totalSlots)

		city.population = city.population - popCost

		if overpopAfter > 0 then
			print("[UnitProd] Überzähliger Einwohner wird zur Unit")
		else
			local priority = { "scientist", "trader", "worker", "farmer" }
			local remaining = popCost

			while remaining > 0 do
				local jobToLose = nil
				local bestCount = -1

				for _, jobType in ipairs(priority) do
					local count = tonumber(city.jobs[jobType]) or 0
					if count > bestCount then
						bestCount = count
						jobToLose = jobType
					end
				end

				if jobToLose and bestCount > 0 then
					city.jobs[jobToLose] = math.max(0, city.jobs[jobToLose] - 1)
					print("[UnitProd] 1 " .. jobToLose .. " wird zur Unit (Platz frei)")
				else
					break
				end

				remaining = remaining - 1
			end
		end

		local BASE_GROWTH = 10
		local GROWTH_PER_CITIZEN = 5
		city.foodThreshold = BASE_GROWTH + (city.population * GROWTH_PER_CITIZEN)
	end

	local order = CityData.AddBuildOrder(cityId, {
		orderType = "Unit",
		unitType = unitType,
		q = spawnQ,
		r = spawnR,
		spawnQ = spawnQ,
		spawnR = spawnR,
		industryCost = unitCost,
		citizenCost = popCost
	})

	if not order then
		if popCost > 0 then
			city.population = city.population + popCost
		end
		return false, "Konnte nicht in Queue gelegt werden"
	end

	if _G.NotifyCityStatsChanged then
		_G.NotifyCityStatsChanged(cityId)
	end

	print("[UnitProd] Bevölkerung NACH: " .. tostring(city.population))
	print("[UnitProd] Jobs: F=" .. tostring(city.jobs.farmer) .. " W=" .. tostring(city.jobs.worker) .. " T=" .. tostring(city.jobs.trader) .. " S=" .. tostring(city.jobs.scientist))
	return true, order
end

function ConstructionSystem.ProcessAllConstruction()
	for cityId, city in pairs(CityData.GetAllCities()) do
		local order = CityData.GetActiveBuildOrder(cityId)
		if order then
			local industry = tonumber(city.currentIndustryProduction) or 0
			local isFinished = false

			if order.status == "Building" then
				local progress = tonumber(order.industryProgress) or 0
				local cost = tonumber(order.industryCost) or 1

				if progress >= cost then
					isFinished = true
					order.industryProgress = cost
					print("[ConstructionSystem] " .. (order.buildingType or order.unitType) .. " FERTIG: " .. progress .. "/" .. cost .. " → wird jetzt abgeschlossen!")
				end
			elseif order.status == "WaitingSpawn" then
				local spawned, spawnState = ConstructionSystem.TrySpawnUnit(cityId, order)
				if spawned then
					print("[ConstructionSystem] Wartende Unit konnte gespawnt werden: " .. order.unitType)
					CityData.CompleteActiveBuildOrder(cityId)
					-- Fog of War: neue Unit erweitert die Sicht des Besitzers.
					pcall(FogOfWarSystem.UpdateVision, city.owner)
				end
			end

			if isFinished then
				if order.orderType == "Unit" then
					local spawned, spawnState = ConstructionSystem.TrySpawnUnit(cityId, order)
					if spawned then
						print("[ConstructionSystem] Unit erfolgreich gespawnt: " .. order.unitType)
						CityData.CompleteActiveBuildOrder(cityId)
						-- Fog of War: neue Unit erweitert die Sicht des Besitzers.
						pcall(FogOfWarSystem.UpdateVision, city.owner)
					else
						print("[ConstructionSystem] Unit " .. order.unitType .. " wartet auf Spawn: " .. tostring(spawnState))
						order.status = "WaitingSpawn"
						order.spawnWaitReason = spawnState
					end
				else
					local folder = getWorkspaceBuildings()
					local ghost = folder:FindFirstChild("Ghost_" .. order.buildingType .. "_" .. order.q .. "_" .. order.r)
					if ghost then ghost:Destroy() end

					local realModel = placeModel(order.buildingType, order.q, order.r, false)
					if realModel then
						local buildingId = BuildingData.CreateBuilding(order.buildingType, city.owner, order.q, order.r, city.provinceId)
						CityData.AddBuilding(cityId, buildingId, order.buildingType, order.q, order.r)
						HexData.UpdateHex(order.q, order.r, { building = order.buildingType })

						local jobTypeMap = {
							Farm = "farmer",
							Factory = "worker",
							Market = "trader",
							Laboratory = "scientist",
						}
						local newJob = jobTypeMap[order.buildingType]
						if newJob then
							CityEconomySystem.AddJobSlot(cityId, newJob, 1)
							-- Neuer Arbeitsplatz entstanden: arbeitslose Bürger sofort
							-- zuweisen (Priorität Farmer > Worker > Trader > Scientist).
							CityEconomySystem.AutoAssignWorkers(cityId)
						end

						local hex = HexData.GetHex(order.q, order.r)
						if hex and hex.soil then
							local soilStats = SoilGenerator.Stats[hex.soil]
							if soilStats then
								local buildingConfig = BuildingConfig.GetBuilding(order.buildingType)
								local mult = (buildingConfig and buildingConfig.StatMultiplier) or { Nutrients=1, Industry=1, Gold=1, Research=1 }

								local finalStats = {
									Nutrients = (soilStats.Nutrients or 0) * (mult.Nutrients or 1),
									Industry = (soilStats.Industry or 0) * (mult.Industry or 1),
									Gold = (soilStats.Gold or 0) * (mult.Gold or 1),
									Research = (soilStats.Research or 0) * (mult.Research or 1),
								}

								CityData.AddStats(cityId, finalStats)
							end
						end

						CityData.CompleteActiveBuildOrder(cityId)
						print("[ConstructionSystem] Gebäude fertiggestellt: " .. order.buildingType)

						-- Fog of War: neues Gebäude (Camp/City/Bastion) ist Sichtquelle.
						pcall(FogOfWarSystem.UpdateVision, city.owner)

						if _G.NotifyCityStatsChanged then
							_G.NotifyCityStatsChanged(cityId)
						end
					end
				end
			end
		end
	end
end

return ConstructionSystem
