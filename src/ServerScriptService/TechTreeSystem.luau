--[[
    TechTreeSystem (ModuleScript)
    Location: ServerScriptService > TechTreeSystem

    Research core + the single read API every other system uses to ask
    "does this player have tech X / what is my bonus?".

    TIER SYSTEM (Bronze -> Silver -> Gold)
        Every tech has 3 tiers. A tech's level (0-3) determines which tier
        is active. Effects are NOT cumulative: reading a tech's effect always
        returns the value of its CURRENT tier (Silver = +20%, never +10%+10%).
        Upgrading replaces the previous tier's effect automatically, because
        everything is derived on demand from the level.

    RESEARCH FLOW (once per round, driven by CityEconomySystem)
        ProcessResearch(player)
          1. GetTotalRP(player)  - research yield of all cities (+ tech bonus)
          2. pour the RP into the FIRST queue entry
          3. finished tier -> MarkResearched (level+1) + ApplyEffect + broadcast
          4. leftover RP flow into the next entry (nothing is wasted)
        The cost of a tier is BaseCost x tier:
            level 0 -> tier 1 (Bronze) = BaseCost x 1
            level 1 -> tier 2 (Silver) = BaseCost x 2
            level 2 -> tier 3 (Gold)   = BaseCost x 3
        When a tech reaches Gold it is dropped from the queue automatically.

    BONUS API (read by ArmyStats / CombatSystem / MovementSystem / ...)
        HasTech(player, techId)              -> boolean
        GetStatBonus(player, stat, class)    -> flat, percent
        GetYieldMultiplier(player, yield, bt)-> number  (1.0 = no bonus)
        GetCostMultiplier(player, target)    -> number  (1.0 = full price)
        GetSpecial(player, key)              -> number  (0 = tech missing)
        GetMovementBonus(player, class, ownTerritory) -> number
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local TechConfig = require(ReplicatedStorage:WaitForChild("TechConfig"))
local TechData = require(script.Parent:WaitForChild("TechData"))
local PointSystem = require(script.Parent:WaitForChild("PointSystem"))
local VictoryConfig = require(ReplicatedStorage:WaitForChild("VictoryConfig"))

local TechTreeSystem = {}

local dataRemotes = ReplicatedStorage:WaitForChild("DataRemotes", 30)

local function remote(name)
	return dataRemotes and dataRemotes:FindFirstChild(name) or nil
end

--------------------------------------------------------------------------------
-- HasTech(player, techId) -> boolean (true when at least tier 1)
--------------------------------------------------------------------------------
function TechTreeSystem.HasTech(player, techId)
	if not player then return false end
	return TechData.IsResearched(player, techId)
end

--------------------------------------------------------------------------------
-- GetStatBonus(player, stat, unitClass) -> flatBonus, percentBonus
-- stat: "Attack" | "Defense" | "Sight"
--------------------------------------------------------------------------------
function TechTreeSystem.GetStatBonus(player, stat, unitClass)
	local flat, percent = 0, 0
	if not player then return flat, percent end

	local rec = TechData.Get(player)
	if not rec then return flat, percent end

	for techId, level in pairs(rec.techLevels) do
		if level >= 1 then
			local eff = TechConfig.GetTechEffect(techId, level)
			if eff and eff.Type == TechConfig.EffectType.STAT_MOD and eff.Stat == stat then
				-- A class restricted tech only counts for that unit class.
				if (not eff.UnitClass) or eff.UnitClass == unitClass then
					if eff.Mode == "Percent" then
						percent += eff.Value
					else
						flat += eff.Value
					end
				end
			end
		end
	end
	return flat, percent
end

--------------------------------------------------------------------------------
-- GetYieldMultiplier(player, yieldKey, buildingType) -> number
-- yieldKey: "food" | "work" | "gold" | "research"
--------------------------------------------------------------------------------
function TechTreeSystem.GetYieldMultiplier(player, yieldKey, buildingType)
	local multiplier = 1
	if not player then return multiplier end

	local rec = TechData.Get(player)
	if not rec then return multiplier end

	for techId, level in pairs(rec.techLevels) do
		if level >= 1 then
			local eff = TechConfig.GetTechEffect(techId, level)
			if eff and eff.Type == TechConfig.EffectType.YIELD_MOD and eff.Yield == yieldKey then
				-- Building bound techs only apply to that building type.
				if (not eff.BuildingType) or eff.BuildingType == buildingType then
					multiplier += eff.Value
				end
			end
		end
	end
	return multiplier
end

--------------------------------------------------------------------------------
-- GetCostMultiplier(player, target) -> number (1.0 = full price)
--------------------------------------------------------------------------------
function TechTreeSystem.GetCostMultiplier(player, target)
	local multiplier = 1
	if not player then return multiplier end

	local rec = TechData.Get(player)
	if not rec then return multiplier end

	for techId, level in pairs(rec.techLevels) do
		if level >= 1 then
			local eff = TechConfig.GetTechEffect(techId, level)
			if eff and eff.Type == TechConfig.EffectType.COST_MOD and eff.Target == target then
				multiplier -= eff.Value
			end
		end
	end
	return math.max(0.1, multiplier)  -- never free
end

--------------------------------------------------------------------------------
-- GetSpecial(player, key) -> number (0 when the tech is missing)
-- Keys: SiegeBonus | FortificationBonus | MaxUnitsBonus | SupplyHeal
--       BuildSpeedRounds | PostCombatHealBonus
--------------------------------------------------------------------------------
function TechTreeSystem.GetSpecial(player, key)
	if not player then return 0 end

	local rec = TechData.Get(player)
	if not rec then return 0 end

	local total = 0
	for techId, level in pairs(rec.techLevels) do
		if level >= 1 then
			local eff = TechConfig.GetTechEffect(techId, level)
			if eff and eff.Type == TechConfig.EffectType.SPECIAL and eff.Key == key then
				total += eff.Value
			end
		end
	end
	return total
end

--------------------------------------------------------------------------------
-- GetMovementBonus(player, unitClass, ownTerritory) -> number
--------------------------------------------------------------------------------
function TechTreeSystem.GetMovementBonus(player, unitClass, ownTerritory)
	local bonus = 0
	if not player then return bonus end

	local rec = TechData.Get(player)
	if not rec then return bonus end

	for techId, level in pairs(rec.techLevels) do
		if level >= 1 then
			local eff = TechConfig.GetTechEffect(techId, level)
			if eff and eff.Type == TechConfig.EffectType.MOVEMENT_MOD then
				local classOk = (not eff.UnitClass) or eff.UnitClass == unitClass
				local terrainOk = (not eff.OwnTerritoryOnly) or ownTerritory == true
				if classOk and terrainOk then
					bonus += eff.Value
				end
			end
		end
	end
	return bonus
end

--------------------------------------------------------------------------------
-- GetMaxUnitsPerArmy(player) -> number
--------------------------------------------------------------------------------
function TechTreeSystem.GetMaxUnitsPerArmy(player, baseValue)
	local base = baseValue or 8
	return base + TechTreeSystem.GetSpecial(player, "MaxUnitsBonus")
end

--------------------------------------------------------------------------------
-- GetTotalRP(player) -> number
-- Research yield of every city, already including the AdvancedResearch bonus.
--------------------------------------------------------------------------------
function TechTreeSystem.GetTotalRP(player)
	if not player then return 0 end

	-- Lazy require: CityData <-> TechTreeSystem must not form a require cycle.
	local ok, CityData = pcall(function()
		return require(script.Parent:WaitForChild("CityData"))
	end)
	if not ok or not CityData then return 0 end

	local total = 0
	for _, city in pairs(CityData.GetAllCities()) do
		if city.owner == player then
			total += tonumber(city.currentResearchProduction) or 0
		end
	end

	-- AdvancedResearch: up to +75% on the whole research output.
	total = total * TechTreeSystem.GetYieldMultiplier(player, "research", nil)
	return math.floor(total)
end

--------------------------------------------------------------------------------
-- ApplyEffect / RemoveEffect
--
-- All effects are read on demand through the bonus API above, so "applying"
-- an effect only means: remember the new tier and refresh the caches that
-- hold derived values (army stats). The previous tier's effect is replaced
-- automatically because GetTechEffect(techId, level) now returns the value
-- of the CURRENT tier.
--------------------------------------------------------------------------------
function TechTreeSystem.ApplyEffect(player, techId)
	local tech = TechConfig.GetTech(techId)
	if not tech then return false end

	-- Army stats cache flat/percent bonuses -> force a recalculation.
	local ok, ArmyData = pcall(function()
		return require(script.Parent:WaitForChild("ArmyData"))
	end)
	local ok2, ArmyStats = pcall(function()
		return require(script.Parent:WaitForChild("ArmyStats"))
	end)

	if ok and ok2 and ArmyData and ArmyStats then
		for _, army in ipairs(ArmyData.GetArmiesByOwner(player)) do
			pcall(ArmyStats.Recalculate, army.id)
		end
	end

	local level = TechData.GetLevel(player, techId)
	print(("[TechTree] %s hat '%s' (Stufe %d / %s) erforscht"):format(
		player and player.Name or "?", tech.Name, level,
		TechConfig.GetLevelName(level) or "Gold"))

	return true
end

-- Effects only become permanent on completion, so removing a QUEUED tech is
-- a no-op. Kept for API symmetry / future "forget tech" features.
function TechTreeSystem.RemoveEffect(player, techId)
	return true
end

--------------------------------------------------------------------------------
-- Broadcast(player) - pushes the full research state to one client
--------------------------------------------------------------------------------
function TechTreeSystem.Broadcast(player)
	if not player then return end

	local rem = remote("TechTreeUpdate")
	if not rem then return end

	local payload = TechData.BuildClientPayload(player)
	if not payload then return end

	local ok, err = pcall(function()
		rem:FireClient(player, payload)
	end)
	if not ok then
		warn("[TechTree] TechTreeUpdate an " .. player.Name .. " fehlgeschlagen: " .. tostring(err))
	end
end

--------------------------------------------------------------------------------
-- QUEUE API (called by the remote handler)
--------------------------------------------------------------------------------
function TechTreeSystem.AddToQueue(player, techId)
	local ok, reason = TechData.AddToQueue(player, techId)
	if ok then
		TechData.SetTotalRP(player, TechTreeSystem.GetTotalRP(player))
		TechTreeSystem.Broadcast(player)
	end
	return ok, reason
end

function TechTreeSystem.RemoveFromQueue(player, techId)
	local ok, reason = TechData.RemoveFromQueue(player, techId)
	if ok then
		TechTreeSystem.Broadcast(player)
	end
	return ok, reason
end

function TechTreeSystem.ReorderQueue(player, newOrder)
	local ok, reason = TechData.ReorderQueue(player, newOrder)
	if ok then
		TechTreeSystem.Broadcast(player)
	end
	return ok, reason
end

--------------------------------------------------------------------------------
-- ProcessResearch(player) -> finishedTechIds
-- One round of research. Costs depend on the TARGET tier of each tech.
-- Overflow RP roll into the next queue entry.
--------------------------------------------------------------------------------
function TechTreeSystem.ProcessResearch(player)
	if not player then return {} end

	local rec = TechData.Get(player)
	if not rec then return {} end

	local rp = TechTreeSystem.GetTotalRP(player)
	TechData.SetTotalRP(player, rp)

	local finished = {}

	if rp > 0 and #rec.researchQueue > 0 then
		local remaining = rp
		local guard = 0

		-- Pour the points into the queue, front to back.
		while remaining > 0 and #rec.researchQueue > 0 and guard < 32 do
			guard += 1

			local techId = rec.researchQueue[1]
			local tech = TechConfig.GetTech(techId)
			if not tech then
				table.remove(rec.researchQueue, 1)
			else
				local level = rec.techLevels[techId] or 0
				local targetLevel = level + 1
				-- Gold techs cannot be queued (AddToQueue blocks it), but guard
				-- against leftover maxed entries anyway.
				if targetLevel > TechConfig.MAX_LEVEL then
					table.remove(rec.researchQueue, 1)
				else
					local current = rec.currentProgress[techId] or 0
					local cost = TechConfig.GetLevelCost(techId, targetLevel)
					local needed = math.max(0, cost - current)

					if remaining >= needed then
						-- Tier finished, the rest flows into the next entry.
						remaining -= needed
						TechData.MarkResearched(player, techId)
						TechTreeSystem.ApplyEffect(player, techId)
						table.insert(finished, techId)
						-- VICTORY: GoldTech +40 Punkte, wenn ein Tech die Gold-Stufe (max) erreicht.
						if targetLevel == TechConfig.MAX_LEVEL then
							pcall(PointSystem.AwardPoints, player, "GoldTech",
								VictoryConfig.ACTIVE_POINTS.GoldTech)
						end
					else
						rec.currentProgress[techId] = current + remaining
						remaining = 0
					end
				end
			end
		end
	end

	-- The GUI always gets a fresh state, even without progress.
	TechTreeSystem.Broadcast(player)

	if #finished > 0 then
		local rem = remote("TechResearched")
		if rem then
			pcall(function()
				rem:FireClient(player, { techIds = finished })
			end)
		end
	end

	return finished
end

--------------------------------------------------------------------------------
-- ProcessAllPlayers() - convenience entry point for the round loop
--------------------------------------------------------------------------------
function TechTreeSystem.ProcessAllPlayers()
	local count = 0
	for _, player in ipairs(Players:GetPlayers()) do
		local ok, err = pcall(TechTreeSystem.ProcessResearch, player)
		if not ok then
			warn("[TechTree] ProcessResearch fehlgeschlagen fuer "
				.. player.Name .. ": " .. tostring(err))
		end
		count += 1
	end
	return count
end

--------------------------------------------------------------------------------
-- SupplyLines: heal armies standing on own territory (called per round)
--------------------------------------------------------------------------------
function TechTreeSystem.ApplySupplyHealing(player)
	local healPercent = TechTreeSystem.GetSpecial(player, "SupplyHeal")
	if healPercent <= 0 then return 0 end

	local okA, ArmyData = pcall(function()
		return require(script.Parent:WaitForChild("ArmyData"))
	end)
	local okU, UnitData = pcall(function()
		return require(script.Parent:WaitForChild("UnitData"))
	end)
	local okH, HexData = pcall(function()
		return require(script.Parent:WaitForChild("HexData"))
	end)
	local okS, ArmyStats = pcall(function()
		return require(script.Parent:WaitForChild("ArmyStats"))
	end)
	if not (okA and okU and okH and okS) then return 0 end

	local healed = 0
	for _, army in ipairs(ArmyData.GetArmiesByOwner(player)) do
		local hex = HexData.GetHex(army.q, army.r)
		-- Own territory = the hex belongs to this player.
		if hex and hex.owner == player then
			for _, unitId in ipairs(army.units or {}) do
				local unit = UnitData.GetUnit(unitId)
				if unit and unit.alive and unit.currentLP < unit.maxLP then
					UnitData.HealUnit(unitId, math.max(1, math.floor(unit.maxLP * healPercent)))
					healed += 1
				end
			end
			pcall(ArmyStats.Recalculate, army.id)
		end
	end
	return healed
end

return TechTreeSystem
