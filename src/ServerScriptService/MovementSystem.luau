
--[[
    MovementSystem (ModuleScript)
    Ort: ServerScriptService > MovementSystem
    
    Die eigentliche Bewegungslogik.
    Berechnet Routen (A* Pathfinding) und führt Bewegung durch.
--]]

local MovementSystem = {}

local HexUtils = require(script.Parent:WaitForChild("HexUtils"))
local HexData = require(script.Parent:WaitForChild("HexData"))
local ArmyData = require(script.Parent:WaitForChild("ArmyData"))
local UnitData = require(script.Parent:WaitForChild("UnitData"))
local ArmySystem = require(script.Parent:WaitForChild("ArmySystem"))
local ArmyStats = require(script.Parent:WaitForChild("ArmyStats"))
local MovementCostConfig = require(script.Parent:WaitForChild("MovementCostConfig"))
local MovementOrderData = require(script.Parent:WaitForChild("MovementOrderData"))
local ArmyModelMover = require(script.Parent:WaitForChild("ArmyModelMover"))
local CombatSystem = require(script.Parent:WaitForChild("CombatSystem"))
local CombatData = require(script.Parent:WaitForChild("CombatData"))
local DiplomacySystem = require(script.Parent:WaitForChild("DiplomacySystem"))
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

--------------------------------------------------------------------------------
-- GetMovementCost(q, r) -> number or nil
--------------------------------------------------------------------------------
function MovementSystem.GetMovementCost(q, r)
	local hex = HexData.GetHex(q, r)
	if not hex then return nil end

	local soil = hex.soil
	if not soil then return nil end

	return MovementCostConfig.GetCost(soil)
end

--------------------------------------------------------------------------------
-- CanEnterHex(q, r) -> boolean
--------------------------------------------------------------------------------
function MovementSystem.CanEnterHex(q, r)
	local hex = HexData.GetHex(q, r)
	if not hex then return false end

	local cost = MovementSystem.GetMovementCost(q, r)
	if not cost then return false end

	return true
end

--------------------------------------------------------------------------------
-- GetTerrainHeight(terrainType) -> number
--------------------------------------------------------------------------------
-- Mappt den Terrain-String (siehe HexData.terrain, gesetzt aus
-- TerrainGenerator.TerrainNames) auf ein Hoehenlevel:
--   Water           -> 0  (Referenz, unbetretbar)
--   Ebene1          -> 1
--   Ebene2          -> 2
--   Ebene3_Gebirge  -> 3
--   Ebene4_Bergspitze -> 4
--------------------------------------------------------------------------------
local TERRAIN_HEIGHTS = {
	Water = 0,
	Ebene1 = 1,
	Ebene2 = 2,
	Ebene3_Gebirge = 3,
	Ebene4_Bergspitze = 4,
	Ebene0 = 0,
	Unknown = 0,
}

function MovementSystem.GetTerrainHeight(terrainType)
	return TERRAIN_HEIGHTS[terrainType] or 0
end

--------------------------------------------------------------------------------
-- GetHeightMoveCost(baseCost, currentHeight, neighborHeight) -> number
--------------------------------------------------------------------------------
-- Gleiche Ebene: normale Kosten; +1/-1 Ebene: x1.5 (anstrengender).
--------------------------------------------------------------------------------
local HEIGHT_STEP_COST_MULT = 1.5

function MovementSystem.GetHeightMoveCost(baseCost, currentHeight, neighborHeight)
	if not baseCost then return nil end
	if currentHeight == neighborHeight then
		return baseCost
	end
	return baseCost * HEIGHT_STEP_COST_MULT
end

--------------------------------------------------------------------------------
-- CalculatePath(startQ, startR, targetQ, targetR) -> path, totalCost
--------------------------------------------------------------------------------
function MovementSystem.CalculatePath(startQ, startR, targetQ, targetR)
	if not MovementSystem.CanEnterHex(targetQ, targetR) then
		return nil, 0
	end

	local startKey = HexUtils.coordToKey(startQ, startR)
	local targetKey = HexUtils.coordToKey(targetQ, targetR)

	-- Hoehe des Start-Hexes (fuer den Hoehen-Check der ersten Bewegung).
	local startHex = HexData.GetHex(startQ, startR)
	local startHeight = startHex and MovementSystem.GetTerrainHeight(startHex.terrain) or 0

	local openSet = {}
	local cameFrom = {}
	local gScore = {}
	local fScore = {}
	local inOpenSet = {}

	gScore[startKey] = 0
	fScore[startKey] = HexUtils.getDistance(startQ, startR, targetQ, targetR)
	table.insert(openSet, { key = startKey, q = startQ, r = startR, height = startHeight })
	inOpenSet[startKey] = true

	while #openSet > 0 do
		local bestIdx = 1
		local bestF = fScore[openSet[1].key] or math.huge

		for i = 2, #openSet do
			local f = fScore[openSet[i].key] or math.huge
			if f < bestF then
				bestF = f
				bestIdx = i
			end
		end

		local current = openSet[bestIdx]
		table.remove(openSet, bestIdx)
		inOpenSet[current.key] = nil

		-- Ziel erreicht?
		if current.key == targetKey then
			local path = {}
			local key = targetKey

			while key do
				local q, r = HexUtils.keyToCoord(key)
				table.insert(path, 1, { q = q, r = r })
				key = cameFrom[key]
			end

			return path, gScore[targetKey]
		end

		-- Nachbarn prüfen
		local neighbors = HexUtils.getNeighbors(current.q, current.r)

		for _, n in ipairs(neighbors) do
			local nKey = HexUtils.coordToKey(n.q, n.r)
			local moveCost = MovementSystem.GetMovementCost(n.q, n.r)

			if moveCost then
				-- HOEHEN-CHECK: nur max. 1 Stufe Differenz pro Schritt erlaubt.
				local neighborHex = HexData.GetHex(n.q, n.r)
				local neighborHeight = neighborHex and MovementSystem.GetTerrainHeight(neighborHex.terrain) or 0
				local heightDiff = math.abs(neighborHeight - (current.height or startHeight))

				if heightDiff <= 1 then
					local adjustedCost = MovementSystem.GetHeightMoveCost(moveCost, current.height or startHeight, neighborHeight)
					local tentativeG = (gScore[current.key] or math.huge) + adjustedCost

					if tentativeG < (gScore[nKey] or math.huge) then
						cameFrom[nKey] = current.key
						gScore[nKey] = tentativeG
						fScore[nKey] = tentativeG + HexUtils.getDistance(n.q, n.r, targetQ, targetR)

						if not inOpenSet[nKey] then
							table.insert(openSet, { key = nKey, q = n.q, r = n.r, height = neighborHeight })
							inOpenSet[nKey] = true
						end
					end
				end
			end
		end
	end

	return nil, 0
end

--------------------------------------------------------------------------------
-- GetReachableSteps(path, movementPoints) -> number
--------------------------------------------------------------------------------
function MovementSystem.GetReachableSteps(path, movementPoints)
	if not path or #path <= 1 then return 0 end

	local remaining = movementPoints
	local steps = 0

	for i = 2, #path do
		local cost = MovementSystem.GetMovementCost(path[i].q, path[i].r) or math.huge
		if remaining >= cost then
			remaining = remaining - cost
			steps = steps + 1
		else
			break
		end
	end

	return steps
end

--------------------------------------------------------------------------------
-- MoveArmyAlongPath(armyId, path, maxSteps, startStep) -> stepsCompleted
--------------------------------------------------------------------------------
function MovementSystem.MoveArmyAlongPath(armyId, path, maxSteps, startStep)
	local army = ArmyData.GetArmy(armyId)
	if not army then
		warn("[MovementSystem] Army " .. armyId .. " nicht gefunden")
		return 0
	end

	-- Armeen im Kampf sind an ihr Hex gebunden
	if CombatData.IsInCombat(armyId) then
		print("[MovementSystem] Army " .. armyId .. " kämpft - keine Bewegung möglich")
		return 0
	end

	if not path or #path <= 1 then return 0 end

	startStep = startStep or 1
	if startStep >= #path then
		MovementOrderData.CompleteOrder(armyId)
		return 0
	end

	-- Aktuelle Bewegungspunkte dieser Runde
	local stats = army.stats
	local movementPoints = stats and stats.Movement or 0

	----------------------------------------------------------------------
	-- TECH: Road Building grants +1 movement while the army starts on
	-- its own territory (hex.owner == army owner).
	----------------------------------------------------------------------
	local tech = Tech()
	if tech and army.owner and movementPoints > 0 then
		local startHex = HexData.GetHex(army.q, army.r)
		local onOwnLand = (startHex ~= nil and startHex.owner == army.owner)
		movementPoints += tech.GetMovementBonus(army.owner, nil, onOwnLand)
	end

	local remaining = movementPoints
	local stepsToTake = 0
	local spentCost = 0

	for i = startStep + 1, #path do
		local cost = MovementSystem.GetMovementCost(path[i].q, path[i].r) or math.huge
		if remaining >= cost then
			remaining = remaining - cost
			spentCost = spentCost + cost
			stepsToTake = stepsToTake + 1
		else
			break
		end

		if maxSteps and stepsToTake >= maxSteps then
			break
		end
	end

	if stepsToTake <= 0 then
		print("[MovementSystem] Army " .. armyId .. " hat keine Bewegungspunkte mehr diese Runde")
		return 0
	end

	local endStep = startStep + stepsToTake

	local finalHex = path[endStep]

	----------------------------------------------------------------------------
	-- KAMPF-PRÜFUNG vor dem Betreten des Ziel-Hexes
	----------------------------------------------------------------------------
	local blockingArmy = ArmyData.GetArmyOnHex(finalHex.q, finalHex.r)

	-- CLEANUP-FIX: Verwaiste oder leere Armeen auf dem Ziel-Hex ignorieren.
	-- Nach einem bereits beendeten Kampf kann (durch fruehere Race-Bugs)
	-- eine tote Armee als Datensatz stehen geblieben sein. Sie wird als
	-- Ghost behandelt: aus dem Weg raeumen statt einen Phantom-Kampf
	-- auszuloesen (der das Overlay erneut oeffnete und alle
	-- Bewegungspunkte fraes).
	if blockingArmy and blockingArmy.id ~= armyId then
		-- WICHTIG: Im Zweifel gilt die Armee als LEBENDIG.
		-- Nur eine nachweislich leere Armee (0 lebende Units) wird entfernt.
		-- So kann ein Fehler in dieser Pruefung niemals den Kampf-Trigger
		-- unterdruecken (frueherer Bug: fehlendes UnitData liess Angriffe
		-- stillschweigend ins Leere laufen).
		local hasLivingUnit = true

		if UnitData and blockingArmy.units then
			hasLivingUnit = false
			for _, unitId in ipairs(blockingArmy.units) do
				local unit = UnitData.GetUnit(unitId)
				if unit and unit.alive then
					hasLivingUnit = true
					break
				end
			end
		end

		if not hasLivingUnit then
			warn("[MovementSystem] Geister-Armee " .. tostring(blockingArmy.id)
				.. " auf (" .. finalHex.q .. ", " .. finalHex.r
				.. ") entfernt (keine lebenden Units)")
			ArmySystem.DeleteArmy(blockingArmy.id)
			blockingArmy = nil
		end
	end

	-- CLEANUP-FIX: Zusatz-Check - laeuft auf dem Hex noch ein AKTIVER Kampf?
	-- (Kann der Fall sein, wenn die Fehlerkette woanders endete.) In dem
	-- Fall wird die Bewegung hier blockiert statt erneut auszuloesen.
	do
		local activeCombat = CombatData.GetByHex(finalHex.q, finalHex.r)
		-- Phase names are UPPERCASE since the combat rework - always ask
		-- CombatData instead of comparing raw strings.
		if activeCombat and CombatData.IsHexContested(finalHex.q, finalHex.r) then
			print("[MovementSystem] Hex wird noch bekaempft - Bewegung blockiert")
			MovementOrderData.CompleteOrder(armyId)
			return 0
		elseif activeCombat then
			-- Veralteter ended-Kampf selbst aufraeumen
			CombatData.Remove(activeCombat.id)
		end
	end

	if blockingArmy and blockingArmy.id ~= armyId then
		local isWildlife = (blockingArmy.owner == nil)
		local atWar = isWildlife or DiplomacySystem.IsAtWar(army.owner, blockingArmy.owner)

		print("[MovementSystem] Ziel-Hex (" .. finalHex.q .. ", " .. finalHex.r
			.. ") belegt von Army " .. tostring(blockingArmy.id)
			.. " | Besitzer: " .. tostring(blockingArmy.owner and blockingArmy.owner.Name or "Wildtier")
			.. " | Wildtier: " .. tostring(isWildlife)
			.. " | Krieg: " .. tostring(atWar))

		if atWar then
			-- Feindliche Armee oder Wildtier -> Kampf statt Bewegung
			-- NEW (turn based combat): the army does NOT enter the contested
			-- hex. It stops on the last free tile of the path and the fight is
			-- handed over to the asynchronous CombatSystem. The winner advances
			-- onto the hex later (see CombatSystem.EndCombat).
			local stopStep = endStep - 1
			if stopStep > startStep then
				-- FOG OF WAR: Hex für Hex bis zum letzten freien Hex vorrücken und
				-- die Sicht nach JEDEM Schritt aktualisieren (alle Zwischen-Hexes
				-- inkl. Sight-Radius werden aufgedeckt).
				local stepDelay = ArmyModelMover.Config.STEP_DELAY or 0.35
				for i = startStep + 1, stopStep do
					local hex = path[i]
					if hex and ArmySystem.MoveArmy(armyId, hex.q, hex.r) then
						ArmyModelMover.MoveModelToHex(armyId, hex.q, hex.r)
						pcall(FogOfWarSystem.UpdateVision, army.owner)
					end
					if i < stopStep then
						task.wait(stepDelay)
					end
				end
			end

			-- Fog of War: Sicht des Besitzers final aktualisieren (Armee steht neu).
			pcall(FogOfWarSystem.UpdateVision, army.owner)

			ArmyStats.SpendMovement(armyId, spentCost)
			MovementOrderData.CompleteOrder(armyId)

			-- Protected: a failing combat start must not break the movement
			-- pipeline (the army already paid its movement points above).
			local startedOk, combatId, startReason = pcall(CombatSystem.StartCombat,
				armyId, blockingArmy.id, finalHex.q, finalHex.r)
			if not startedOk then
				warn("[MovementSystem] StartCombat Fehler: " .. tostring(combatId))
				combatId = nil
			elseif not combatId then
				print("[MovementSystem] Kampf nicht gestartet: " .. tostring(startReason))
			end

			print("[MovementSystem] Kampf ausgelöst auf ("
				.. finalHex.q .. ", " .. finalHex.r .. ") - Combat " .. tostring(combatId))
			return 0
		else
			-- Allianz (nicht atWar) -> Armee darf das Hex betreten und mit der
			-- Allianz-Armee koexistieren. Kein Kampf, keine Blockade.
			print("[MovementSystem] Ziel besetzt (Allianz) - Bewegung erlaubt")
			-- fällt durch zur MoveArmy-Bewegung unten.
		end
	end

	-- Bewegungspunkte VERBRAUCHEN
	ArmyStats.SpendMovement(armyId, spentCost)

	-- FOG OF WAR: Armee bewegt sich Hex für Hex entlang des Pfades. Die Sicht
	-- wird NACH JEDEM einzelnen Schritt aktualisiert (nicht nur am Ziel), damit
	-- ALLE Zwischen-Hexes inkl. Sight-Radius aufgedeckt werden.
	local stepDelay = ArmyModelMover.Config.STEP_DELAY or 0.35
	for i = startStep + 1, endStep do
		local hex = path[i]
		if not hex or not ArmySystem.MoveArmy(armyId, hex.q, hex.r) then
			warn("[MovementSystem] MoveArmy fehlgeschlagen für Army " .. armyId .. " (Schritt " .. i .. ")")
			return 0
		end
		ArmyModelMover.MoveModelToHex(armyId, hex.q, hex.r)
		pcall(FogOfWarSystem.UpdateVision, army.owner)
		if i < endStep then
			task.wait(stepDelay)
		end
	end

	-- OrderData aktualisieren (ABSOLUTER Fortschritt)
	local order = MovementOrderData.GetOrder(armyId)
	if order then
		MovementOrderData.UpdateStep(armyId, endStep)

		if endStep >= #path then
			MovementOrderData.CompleteOrder(armyId)
			print("[MovementSystem] Army " .. armyId .. " hat Ziel erreicht!")
		end
	end

	print("[MovementSystem] Army " .. armyId .. " bewegt: " .. stepsToTake .. " Schritte (" .. startStep .. " -> " .. endStep .. ")")
	return stepsToTake
end

return MovementSystem
