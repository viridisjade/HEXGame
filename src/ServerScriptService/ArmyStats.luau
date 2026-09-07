
--[[
    ArmyStats (ModuleScript)
    Ort: ServerScriptService > ArmyStats
    
    Berechnet Army-Stats aus den Units.
    
    Regeln:
      LP          = Summe currentLP
      MaxLP       = Summe maxLP
      Attack      = Summe Attack
      Defense     = Summe Defense
      Sight       = höchste Sight
      MaxMovement = niedrigste maxMovement der Units
      Movement    = niedrigste currentMovement der Units
--]]

local ArmyStats = {}

local ArmyData = require(script.Parent:WaitForChild("ArmyData"))
local UnitData = require(script.Parent:WaitForChild("UnitData"))

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UnitConfig = require(ReplicatedStorage:WaitForChild("UnitConfig"))

-- Lazy tech access (avoids a require cycle through ArmyData).
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

--------------------------------------------------------------------------------
-- Recalculate(armyId)
--------------------------------------------------------------------------------
function ArmyStats.Recalculate(armyId)
	local army = ArmyData.GetArmy(armyId)
	if not army then
		warn("[ArmyStats] Recalculate: Army " .. tostring(armyId) .. " nicht gefunden")
		return nil
	end

	local totalLP = 0
	local totalMaxLP = 0
	local totalAttack = 0
	local totalDefense = 0
	local maxSight = 0
	local minCurrentMovement = math.huge
	local minMaxMovement = math.huge
	local aliveUnits = 0

	for _, unitId in ipairs(army.units) do
		local unit = UnitData.GetUnit(unitId)
		if unit and unit.alive then
			aliveUnits = aliveUnits + 1

			totalLP = totalLP + (unit.currentLP or 0)
			totalMaxLP = totalMaxLP + (unit.maxLP or 0)

			local config = UnitConfig.GetUnit(unit.unitType)
			if config then
				----------------------------------------------------------
				-- TECH BONUSES (Bronze Weapons, Iron Armor, Cartography)
				-- Flat bonuses add up, percent bonuses scale the base.
				----------------------------------------------------------
				local unitClass = config.Class
				local owner = army.owner
				local tech = Tech()

				local atk = config.Stats.Attack
				local def = config.Stats.Defense
				local sight = config.Stats.Sight

				if tech and owner then
					local aFlat, aPct = tech.GetStatBonus(owner, "Attack", unitClass)
					atk = (atk + aFlat) * (1 + aPct)

					local dFlat, dPct = tech.GetStatBonus(owner, "Defense", unitClass)
					def = (def + dFlat) * (1 + dPct)

					local sFlat, sPct = tech.GetStatBonus(owner, "Sight", unitClass)
					sight = (sight + sFlat) * (1 + sPct)
				end

				totalAttack = totalAttack + atk
				totalDefense = totalDefense + def

				if sight > maxSight then
					maxSight = sight
				end
			end

			local currentMove = unit.currentMovement or 0
			local maxMove = unit.maxMovement or 0

			if currentMove < minCurrentMovement then
				minCurrentMovement = currentMove
			end
			if maxMove < minMaxMovement then
				minMaxMovement = maxMove
			end
		end
	end

	if aliveUnits == 0 then
		minCurrentMovement = 0
		minMaxMovement = 0
	end

	army.stats = {
		LP = totalLP,
		MaxLP = totalMaxLP,
		Attack = math.floor(totalAttack + 0.5),
		Defense = math.floor(totalDefense + 0.5),
		Sight = math.floor(maxSight + 0.5),
		Movement = minCurrentMovement,
		MaxMovement = minMaxMovement,
	}

	return army.stats
end

--------------------------------------------------------------------------------
-- GetStats(armyId)
--------------------------------------------------------------------------------
function ArmyStats.GetStats(armyId)
	local army = ArmyData.GetArmy(armyId)
	if not army then return nil end
	return army.stats
end

--------------------------------------------------------------------------------
-- SpendMovement(armyId, amount)
--------------------------------------------------------------------------------
function ArmyStats.SpendMovement(armyId, amount)
	local army = ArmyData.GetArmy(armyId)
	if not army then return 0 end

	for _, unitId in ipairs(army.units) do
		UnitData.SpendMovement(unitId, amount)
	end

	local stats = ArmyStats.Recalculate(armyId)
	return stats and stats.Movement or 0
end

--------------------------------------------------------------------------------
-- ResetMovement(armyId)
--------------------------------------------------------------------------------
function ArmyStats.ResetMovement(armyId)
	local army = ArmyData.GetArmy(armyId)
	if not army then return end

	for _, unitId in ipairs(army.units) do
		UnitData.ResetMovement(unitId)
	end

	ArmyStats.Recalculate(armyId)
end

--------------------------------------------------------------------------------
-- ResetAllMovement()
--------------------------------------------------------------------------------
function ArmyStats.ResetAllMovement()
	local armies = ArmyData.GetAllArmies()
	local count = 0

	for id, army in pairs(armies) do
		for _, unitId in ipairs(army.units) do
			UnitData.ResetMovement(unitId)
		end
		ArmyStats.Recalculate(id)
		count = count + 1
	end

	print("[ArmyStats] Movement für " .. count .. " Armeen zurückgesetzt")
end

--------------------------------------------------------------------------------
-- RecalculateAll()
--------------------------------------------------------------------------------
function ArmyStats.RecalculateAll()
	local armies = ArmyData.GetAllArmies()
	local count = 0

	for id, _ in pairs(armies) do
		ArmyStats.Recalculate(id)
		count = count + 1
	end

	print("[ArmyStats] " .. count .. " Armeen neu berechnet")
end

--------------------------------------------------------------------------------
-- PrintStats(armyId)
--------------------------------------------------------------------------------
function ArmyStats.PrintStats(armyId)
	local army = ArmyData.GetArmy(armyId)
	if not army then return end
	local stats = army.stats
	print("[ArmyStats] Army " .. armyId .. ": LP " .. stats.LP .. "/" .. stats.MaxLP .. ", ATK " .. stats.Attack .. ", DEF " .. stats.Defense .. ", Sight " .. stats.Sight .. ", Move " .. stats.Movement .. "/" .. stats.MaxMovement)
end

return ArmyStats
