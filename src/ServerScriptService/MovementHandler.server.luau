
--[[
    MovementHandler (Script)
    Ort: ServerScriptService > MovementHandler
    
    Empfängt alle Bewegungs-Anfragen vom Client.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArmyData = require(script.Parent:WaitForChild("ArmyData"))
local MovementSystem = require(script.Parent:WaitForChild("MovementSystem"))
local MovementOrderData = require(script.Parent:WaitForChild("MovementOrderData"))
local CombatData = require(script.Parent:WaitForChild("CombatData"))

local requestRouteRemote = ReplicatedStorage:WaitForChild("RequestRoute")
local confirmMoveRemote = ReplicatedStorage:WaitForChild("ConfirmMove")
local cancelMoveRemote = ReplicatedStorage:WaitForChild("CancelMove")

local function isArmyOwnedBy(armyId, player)
	local army = ArmyData.GetArmy(armyId)
	if not army then return false end
	return army.owner == player
end

requestRouteRemote.OnServerInvoke = function(player, armyId, targetQ, targetR, isRefresh)
	if not isArmyOwnedBy(armyId, player) then
		warn("[MovementHandler] " .. player.Name .. " besitzt Army " .. tostring(armyId) .. " nicht")
		return nil
	end

	local army = ArmyData.GetArmy(armyId)
	if not army then return nil end

	-- NEW: an army that is locked in a turn based combat cannot be routed.
	if CombatData.IsInCombat(armyId) then
		return { path = nil, reason = "Armee ist im Kampf" }
	end

	if not MovementSystem.CanEnterHex(targetQ, targetR) then
		return { path = nil, reason = "Hex nicht betretbar" }
	end

	local path, totalCost = MovementSystem.CalculatePath(army.q, army.r, targetQ, targetR)

	if not path then
		return { path = nil, reason = "Kein Pfad gefunden" }
	end

	local movementPoints = army.stats and army.stats.Movement or 0
	local reachableSteps = MovementSystem.GetReachableSteps(path, movementPoints)

	if not isRefresh then
		if MovementOrderData.HasActiveOrder(armyId) then
			MovementOrderData.CancelOrder(armyId)
		end
		MovementOrderData.CreateOrder(armyId, targetQ, targetR, path)
	end

	print("[MovementHandler] Route für Army " .. armyId .. ": " .. #path .. " Hexes, " .. totalCost .. " Kosten, " .. reachableSteps .. " erreichbar" .. (isRefresh and " [refresh]" or ""))

	return {
		path = path,
		totalCost = totalCost,
		reachableSteps = reachableSteps,
		movementPoints = movementPoints,
	}
end

confirmMoveRemote.OnServerEvent:Connect(function(player, armyId)
	if not isArmyOwnedBy(armyId, player) then return end

	-- NEW: block confirmations while the army is fighting.
	if CombatData.IsInCombat(armyId) then
		warn("[MovementHandler] Army " .. tostring(armyId) .. " ist im Kampf - keine Bewegung")
		return
	end

	local order = MovementOrderData.GetOrder(armyId)
	if not order then
		warn("[MovementHandler] Keine Route für Army " .. tostring(armyId))
		return
	end

	if order.confirmed then
		warn("[MovementHandler] Route für Army " .. armyId .. " bereits bestätigt")
		return
	end

	MovementOrderData.ConfirmOrder(armyId)

	MovementSystem.MoveArmyAlongPath(armyId, order.fullPath, nil, 1)

	print("[MovementHandler] Army " .. armyId .. " Bewegung bestätigt und ausgeführt")
end)

cancelMoveRemote.OnServerEvent:Connect(function(player, armyId)
	if not isArmyOwnedBy(armyId, player) then return end

	MovementOrderData.CancelOrder(armyId)
	print("[MovementHandler] Route für Army " .. armyId .. " abgebrochen")
end)

local MovementHandler = {}

function MovementHandler.ContinueAllOrders()
	local orders = MovementOrderData.GetConfirmedOrders()
	local moved = 0

	for _, order in ipairs(orders) do
		if not order.completed then
			local startStep = order.currentStep or 1

			if startStep < #order.fullPath then
				local ok, err = pcall(function()
					MovementSystem.MoveArmyAlongPath(
						order.armyId, order.fullPath, nil, startStep)
				end)

				if ok then
					moved = moved + 1
				else
					warn("[MovementHandler] Fehler bei Army " .. tostring(order.armyId)
						.. ": " .. tostring(err))
				end
			else
				MovementOrderData.CompleteOrder(order.armyId)
			end
		end
	end

	if moved > 0 then
		print("[MovementHandler] " .. moved .. " Armeen setzen ihre Bewegung fort")
	end
	return moved
end

_G.ContinueAllMovementOrders = MovementHandler.ContinueAllOrders

print("[MovementHandler] Bereit. Bewegungen laufen automatisch zu Rundenbeginn weiter.")
