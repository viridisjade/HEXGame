
--[[
    CityEconomySystem (ModuleScript)
    Ort: ServerScriptService > CityEconomySystem
    
    Die komplette Stadt-Wirtschaft an EINEM Ort.
--]]

local CityEconomySystem = {}

local CityData = require(script.Parent:WaitForChild("CityData"))
local HexData = require(script.Parent:WaitForChild("HexData"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local BuildingConfig = require(script.Parent:WaitForChild("BuildingConfig"))
local SoilGenerator = require(script.Parent:WaitForChild("SoilGenerator"))

-- Lazy tech access: TechTreeSystem itself reads CityData, so a direct
-- require at the top would create a cycle.
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

CityEconomySystem.Config = {
	PRODUCTION_PER_FARMER    = 2,
	PRODUCTION_PER_WORKER    = 2,
	PRODUCTION_PER_TRADER    = 2,
	PRODUCTION_PER_SCIENTIST = 2,

	START_POPULATION   = 4,
	FOOD_PER_CITIZEN   = 1,
	BASE_GROWTH        = 10,
	GROWTH_PER_CITIZEN = 5,
	MIN_POPULATION     = 1,
	MAX_CYCLES         = 20,
}

local config = CityEconomySystem.Config

local function num(value)
	return tonumber(value) or 0
end

local function growthThresholdFor(population)
	return config.BASE_GROWTH + (population * config.GROWTH_PER_CITIZEN)
end

function CityEconomySystem.GetWorkerProduction(cityId)
	local city = CityData.GetCity(cityId)
	if not city or not city.jobs then
		return { food = 0, work = 0, gold = 0, research = 0 }
	end

	local jobs = city.jobs
	return {
		food     = num(jobs.farmer)    * config.PRODUCTION_PER_FARMER,
		work     = num(jobs.worker)    * config.PRODUCTION_PER_WORKER,
		gold     = num(jobs.trader)    * config.PRODUCTION_PER_TRADER,
		research = num(jobs.scientist) * config.PRODUCTION_PER_SCIENTIST,
	}
end

function CityEconomySystem.GetHexAndBuildingProduction(cityId)
	local city = CityData.GetCity(cityId)
	if not city then
		return { food = 0, work = 0, gold = 0, research = 0 }
	end

	local result = { food = 0, work = 0, gold = 0, research = 0 }

	for _, building in ipairs(city.buildings or {}) do
		local hex = HexData.GetHex(building.q, building.r)
		if hex and hex.soil then
			local soilStats = SoilGenerator.Stats[hex.soil]
			if soilStats then
				local bConfig = BuildingConfig.GetBuilding(building.buildingType)
				local mult = (bConfig and bConfig.StatMultiplier)
					or { Nutrients = 1, Industry = 1, Gold = 1, Research = 1 }

				-- TECH: yield multipliers (e.g. Advanced Farming +50% on Farms,
				-- Mining Techniques +30% industry, Trade Networks +25% gold).
				local owner = city.owner
				local bType = building.buildingType
				local tFood, tWork, tGold = 1, 1, 1
				local tech = Tech()
				if tech and owner then
					tFood = tech.GetYieldMultiplier(owner, "food", bType)
					tWork = tech.GetYieldMultiplier(owner, "work", bType)
					tGold = tech.GetYieldMultiplier(owner, "gold", bType)
				end

				result.food     = result.food     + num(soilStats.Nutrients) * num(mult.Nutrients) * tFood
				result.work     = result.work     + num(soilStats.Industry)  * num(mult.Industry)  * tWork
				result.gold     = result.gold     + num(soilStats.Gold)      * num(mult.Gold)      * tGold
				result.research = result.research + num(soilStats.Research)  * num(mult.Research)
			end
		end
	end

	return result
end

function CityEconomySystem.CalculateTotalResources(cityId)
	local hex = CityEconomySystem.GetHexAndBuildingProduction(cityId)
	local workers = CityEconomySystem.GetWorkerProduction(cityId)

	return {
		food     = hex.food     + workers.food,
		work     = hex.work     + workers.work,
		gold     = hex.gold     + workers.gold,
		research = hex.research + workers.research,
	}
end

function CityEconomySystem.GetResourceBreakdown(cityId)
	local city = CityData.GetCity(cityId)
	if not city then return nil end

	return {
		hex = CityEconomySystem.GetHexAndBuildingProduction(cityId),
		workers = CityEconomySystem.GetWorkerProduction(cityId),
		total = CityEconomySystem.CalculateTotalResources(cityId),
	}
end

function CityEconomySystem.UpdateStats(cityId)
	local city = CityData.GetCity(cityId)
	if not city then return nil end

	local hexProd = CityEconomySystem.GetHexAndBuildingProduction(cityId)
	local workers = CityEconomySystem.GetWorkerProduction(cityId)
	local totals = {
		food     = hexProd.food     + workers.food,
		work     = hexProd.work     + workers.work,
		gold     = hexProd.gold     + workers.gold,
		research = hexProd.research + workers.research,
	}

	local consumption = num(city.population) * config.FOOD_PER_CITIZEN

	city.currentFoodProduction     = totals.food
	city.currentFoodConsumption    = consumption
	city.currentIndustryProduction = totals.work
	city.currentGoldProduction     = totals.gold
	city.currentResearchProduction = totals.research
	city.foodSurplus               = totals.food - consumption
	city.foodThreshold             = growthThresholdFor(num(city.population))

	city.productionBreakdown = {
		hex = hexProd,
		workers = workers,
		total = totals,
	}

	return totals
end

CityEconomySystem.UpdateWorkerStats = CityEconomySystem.UpdateStats

function CityEconomySystem.GetPopulation(cityId)
	local city = CityData.GetCity(cityId)
	return city and num(city.population) or 0
end

function CityEconomySystem.GetTotalJobSlots(cityId)
	local city = CityData.GetCity(cityId)
	if not city or not city.jobSlots then return 0 end

	local total = 0
	for _, slots in pairs(city.jobSlots) do
		total = total + num(slots)
	end
	return total
end

function CityEconomySystem.GetOverpopulation(cityId)
	local pop = CityEconomySystem.GetPopulation(cityId)
	local slots = CityEconomySystem.GetTotalJobSlots(cityId)
	return math.max(0, pop - slots)
end

function CityEconomySystem.GetFoodConsumption(cityId)
	return CityEconomySystem.GetPopulation(cityId) * config.FOOD_PER_CITIZEN
end

function CityEconomySystem.GetJobCounts(cityId)
	local city = CityData.GetCity(cityId)
	if not city or not city.jobs then
		return { farmer = 0, worker = 0, trader = 0, scientist = 0 }
	end
	return city.jobs
end

function CityEconomySystem.AddPopulation(cityId, amount)
	local city = CityData.GetCity(cityId)
	if not city then return end
	city.population = math.max(0, num(city.population) + num(amount))
end

function CityEconomySystem.RemovePopulation(cityId, amount)
	CityEconomySystem.AddPopulation(cityId, -num(amount))
end

function CityEconomySystem.GetJobWithMostWorkers(cityId)
	local city = CityData.GetCity(cityId)
	if not city or not city.jobs then return nil end

	local priority = { "scientist", "trader", "worker", "farmer" }
	local bestJob, bestCount = nil, -1

	for _, jobType in ipairs(priority) do
		local count = num(city.jobs[jobType])
		if count > bestCount then
			bestCount = count
			bestJob = jobType
		end
	end

	if bestCount <= 0 then return nil end
	return bestJob
end

function CityEconomySystem.AddJobSlot(cityId, jobType, amount)
	local city = CityData.GetCity(cityId)
	if not city or not city.jobSlots then return false end

	city.jobSlots[jobType] = num(city.jobSlots[jobType]) + (num(amount) > 0 and num(amount) or 1)
	return true
end

--------------------------------------------------------------------------------
-- RemoveJobSlot(cityId, jobType, amount)
-- Entfernt Arbeitsplätze (z.B. wenn ein Gebäude zerstört wird). Wenn dadurch
-- mehr Bürger im Job stehen als es Plätze gibt, werden die überzähligen
-- Bürger arbeitslos (city.jobs wird auf city.jobSlots gekappt) - sie
-- können danach von AutoAssignWorkers auf andere freie Plätze verteilt
-- werden.
--------------------------------------------------------------------------------
function CityEconomySystem.RemoveJobSlot(cityId, jobType, amount)
	local city = CityData.GetCity(cityId)
	if not city or not city.jobSlots then return false end

	local removeAmount = num(amount) > 0 and num(amount) or 1
	city.jobSlots[jobType] = math.max(0, num(city.jobSlots[jobType]) - removeAmount)

	-- Bürger, die jetzt über der neuen Kapazität stehen, werden arbeitslos.
	if city.jobs and num(city.jobs[jobType]) > num(city.jobSlots[jobType]) then
		city.jobs[jobType] = num(city.jobSlots[jobType])
	end

	return true
end

function CityEconomySystem.AssignWorker(cityId, jobType)
	local city = CityData.GetCity(cityId)
	if not city or not city.jobs or not city.jobSlots then return false end

	local assigned = 0
	for _, count in pairs(city.jobs) do
		assigned = assigned + num(count)
	end

	if assigned >= num(city.population) then return false end
	if num(city.jobs[jobType]) >= num(city.jobSlots[jobType]) then return false end

	city.jobs[jobType] = num(city.jobs[jobType]) + 1
	return true
end

function CityEconomySystem.UnassignWorker(cityId, jobType)
	local city = CityData.GetCity(cityId)
	if not city or not city.jobs then return false end

	if num(city.jobs[jobType]) > 0 then
		city.jobs[jobType] = city.jobs[jobType] - 1
		return true
	end
	return false
end

function CityEconomySystem.MoveCitizen(cityId, fromJob, toJob)
	local city = CityData.GetCity(cityId)
	if not city or not city.jobs or not city.jobSlots then return false, "CityNotFound" end

	if fromJob == toJob then return false, "SameJob" end
	if num(city.jobs[fromJob]) < 1 then return false, "SourceEmpty" end
	if num(city.jobs[toJob]) >= num(city.jobSlots[toJob]) then return false, "TargetFull" end

	city.jobs[fromJob] = city.jobs[fromJob] - 1
	city.jobs[toJob] = num(city.jobs[toJob]) + 1

	CityEconomySystem.UpdateStats(cityId)

	if _G.NotifyCityStatsChanged then _G.NotifyCityStatsChanged(cityId) end
	return true
end

--------------------------------------------------------------------------------
-- AutoAssignWorkers(cityId) -> number (Anzahl neu zugewiesener Bürger)
--------------------------------------------------------------------------------
-- Verteilt arbeitslose Bürger (Bevölkerung - bereits zugewiesene Jobs) auf
-- freie Arbeitsplätze, nach fester Priorität:
--   1. Farmer (Food)  2. Worker (Industrie)  3. Trader (Gold)  4. Scientist (Forschung)
--
-- Überschreibt NIE eine bestehende (manuelle) Zuweisung - sie füllt nur
-- Lücken: freie Plätze, für die arbeitslose Bürger vorhanden sind.
-- Bleiben nach dem Auffüllen aller Plätze noch Bürger übrig, bleiben sie
-- arbeitslos (kein Fehler).
--
-- Auslöser (siehe Aufrufer): Bevölkerungswachstum/-schrumpfung (ProcessGrowth),
-- neues Gebäude (ConstructionSystem, neue Job-Slots), Gebäude-Zerstörung
-- (BuildingSystem/ConstructionSystem, weniger Job-Slots), manuelle
-- Job-Verschiebung (CityActions.RequestMoveCitizen).
--------------------------------------------------------------------------------
local JOB_PRIORITY = { "farmer", "worker", "trader", "scientist" }

function CityEconomySystem.AutoAssignWorkers(cityId)
	local city = CityData.GetCity(cityId)
	if not city or not city.jobs or not city.jobSlots then return 0 end

	-- 1) Arbeitslose Bürger zählen (Bevölkerung - bereits zugewiesene Jobs).
	local assigned = 0
	for _, count in pairs(city.jobs) do
		assigned = assigned + num(count)
	end

	local unemployed = num(city.population) - assigned
	if unemployed <= 0 then return 0 end

	-- 2) Nach Priorität auffüllen: erst alle freien Farmer-Plätze, dann
	--    Worker, dann Trader, dann Scientist.
	local totalAssignedNow = 0
	for _, jobType in ipairs(JOB_PRIORITY) do
		if unemployed <= 0 then break end

		local slots = num(city.jobSlots[jobType])
		local current = num(city.jobs[jobType])
		local freeSlots = math.max(0, slots - current)

		if freeSlots > 0 then
			local fill = math.min(freeSlots, unemployed)
			city.jobs[jobType] = current + fill
			unemployed = unemployed - fill
			totalAssignedNow = totalAssignedNow + fill
		end
	end

	-- 3) Übrige arbeitslose Bürger bleiben arbeitslos (keine Plätze frei).

	if totalAssignedNow > 0 then
		CityEconomySystem.UpdateStats(cityId)
		if _G.NotifyCityStatsChanged then _G.NotifyCityStatsChanged(cityId) end
		print("[CityEconomy] AutoAssignWorkers City " .. tostring(cityId) .. ": " .. totalAssignedNow .. " Bürger neu zugewiesen")
	end

	return totalAssignedNow
end

function CityEconomySystem.ProcessGrowth(cityId)
	local city = CityData.GetCity(cityId)
	if not city then return end

	local surplus = num(city.foodSurplus)
	city.growthBar = num(city.growthBar) + surplus

	local cycles = 0
	while cycles < config.MAX_CYCLES do
		local threshold = growthThresholdFor(num(city.population))
		if city.growthBar >= threshold then
			city.growthBar = city.growthBar - threshold
			city.population = num(city.population) + 1
			cycles = cycles + 1
		else
			break
		end
	end

	cycles = 0
	while cycles < config.MAX_CYCLES and city.growthBar < 0 do
		if num(city.population) <= config.MIN_POPULATION then
			city.growthBar = math.max(0, city.growthBar)
			break
		end

		city.population = num(city.population) - 1
		city.growthBar = growthThresholdFor(num(city.population)) + city.growthBar
		cycles = cycles + 1
	end

	city.foodThreshold = growthThresholdFor(num(city.population))
end

function CityEconomySystem.ProcessPopulationEnd(cityId, foodSurplus)
	local city = CityData.GetCity(cityId)
	if not city then return end

	if foodSurplus ~= nil then
		city.foodSurplus = num(foodSurplus)
	end

	CityEconomySystem.ProcessGrowth(cityId)
	city.currentFoodConsumption = num(city.population) * config.FOOD_PER_CITIZEN

	if _G.NotifyCityStatsChanged then _G.NotifyCityStatsChanged(cityId) end
end

function CityEconomySystem.GetGrowthData(cityId)
	local city = CityData.GetCity(cityId)
	if not city then return nil end

	return {
		population = num(city.population),
		growthBar  = num(city.growthBar),
		threshold  = num(city.foodThreshold) > 0
			and num(city.foodThreshold)
			or growthThresholdFor(num(city.population)),
		surplus    = num(city.foodSurplus),
	}
end

local function payIndustry(city, amount)
	local remaining = amount

	while remaining > 0 and city.buildQueue and #city.buildQueue > 0 do
		local activeOrder = nil
		for _, order in ipairs(city.buildQueue) do
			if order.status == "Building" then
				activeOrder = order
				break
			end
		end

		if not activeOrder then break end

		local progress = num(activeOrder.industryProgress)
		local cost = num(activeOrder.industryCost)
		if cost <= 0 then cost = 1 end

		local needed = math.max(0, cost - progress)
		if needed <= 0 then break end

		if remaining >= needed then
			activeOrder.industryProgress = cost
			remaining = remaining - needed
			print("[CityEconomy] " .. tostring(activeOrder.buildingType or activeOrder.unitType)
				.. " fertig (" .. cost .. "/" .. cost .. "), Überschuss: " .. remaining)
		else
			activeOrder.industryProgress = progress + remaining
			print("[CityEconomy] " .. tostring(activeOrder.buildingType or activeOrder.unitType)
				.. ": " .. activeOrder.industryProgress .. "/" .. cost)
			remaining = 0
		end
	end

	return remaining
end

function CityEconomySystem.ProcessRound(cityId)
	local city = CityData.GetCity(cityId)
	if not city then return nil end

	local hexProd = CityEconomySystem.GetHexAndBuildingProduction(cityId)
	local workers = CityEconomySystem.GetWorkerProduction(cityId)
	local totals = {
		food     = hexProd.food     + workers.food,
		work     = hexProd.work     + workers.work,
		gold     = hexProd.gold     + workers.gold,
		research = hexProd.research + workers.research,
	}

	if city.owner then
		PlayerData.AddGold(city.owner, totals.gold)
	end

	payIndustry(city, totals.work)

	local consumptionBefore = num(city.population) * config.FOOD_PER_CITIZEN
	city.foodSurplus = totals.food - consumptionBefore

	CityEconomySystem.ProcessGrowth(cityId)

	local consumptionAfter = num(city.population) * config.FOOD_PER_CITIZEN

	city.currentFoodProduction     = totals.food
	city.currentFoodConsumption    = consumptionAfter
	city.currentIndustryProduction = totals.work
	city.currentGoldProduction     = totals.gold
	city.currentResearchProduction = totals.research
	city.foodSurplus               = totals.food - consumptionAfter

	city.productionBreakdown = {
		hex = hexProd,
		workers = workers,
		total = totals,
	}

	return totals
end

CityEconomySystem.ProcessRoundResources = CityEconomySystem.ProcessRound

function CityEconomySystem.ProcessAllCities()
	local count = 0
	for cityId, _ in pairs(CityData.GetAllCities()) do
		CityEconomySystem.ProcessRound(cityId)
		count = count + 1
	end

	-- Nach der Runde (Wachstum/Schrumpfung ist bereits in ProcessRound
	-- passiert): arbeitslose Bürger auf freie Plätze verteilen, für JEDE
	-- Stadt. Muss NACH der Wachstumsberechnung laufen, damit neue Bürger
	-- sofort einen Job bekommen können.
	for cityId, _ in pairs(CityData.GetAllCities()) do
		CityEconomySystem.AutoAssignWorkers(cityId)
	end

	----------------------------------------------------------------------
	-- TECH: research runs AFTER the cities produced their yields, so the
	-- research points of this very round are already available.
	----------------------------------------------------------------------
	local tech = Tech()
	if tech then
		local Players = game:GetService("Players")
		for _, player in ipairs(Players:GetPlayers()) do
			local ok, err = pcall(tech.ProcessResearch, player)
			if not ok then
				warn("[CityEconomy] ProcessResearch fehlgeschlagen: " .. tostring(err))
			end

			-- Supply Lines: heal armies standing on own territory.
			local okHeal, errHeal = pcall(tech.ApplySupplyHealing, player)
			if not okHeal then
				warn("[CityEconomy] SupplyHealing fehlgeschlagen: " .. tostring(errHeal))
			end
		end
	end

	return count
end

return CityEconomySystem
