--[[
    MovementOrderData (ModuleScript)
    Ort: ServerScriptService > MovementOrderData
    
    Speichert alle aktiven Bewegungsbefehle.
    
    Datenstruktur pro Order:
    {
        armyId = number,
        targetQ = number,
        targetR = number,
        fullPath = { {q=0,r=0}, {q=1,r=0}, ... },
        currentStep = number,
        confirmed = boolean,
        completed = boolean,
    }
--]]

local MovementOrderData = {}

local orders = {}

function MovementOrderData.CreateOrder(armyId, targetQ, targetR, path)
	orders[armyId] = {
		armyId = armyId,
		targetQ = targetQ,
		targetR = targetR,
		fullPath = path,
		currentStep = 1,
		confirmed = false,
		completed = false,
	}
	return orders[armyId]
end

function MovementOrderData.GetOrder(armyId)
	return orders[armyId]
end

function MovementOrderData.ConfirmOrder(armyId)
	local order = orders[armyId]
	if not order then return false end
	order.confirmed = true
	return true
end

function MovementOrderData.UpdateStep(armyId, step)
	local order = orders[armyId]
	if not order then return end
	order.currentStep = step
end

function MovementOrderData.CompleteOrder(armyId)
	-- Order endgültig entfernen (statt nur completed zu setzen).
	-- Wichtig: eine completed-Order, die im Speicher bleibt, wird von
	-- ContinueAllOrders sonst immer wieder aufgegriffen.
	orders[armyId] = nil
end

function MovementOrderData.CancelOrder(armyId)
	orders[armyId] = nil
end

function MovementOrderData.HasActiveOrder(armyId)
	return orders[armyId] ~= nil
end

function MovementOrderData.GetAllActiveOrders()
	local active = {}
	for _, order in pairs(orders) do
		table.insert(active, order)
	end
	return active
end

function MovementOrderData.GetConfirmedOrders()
	local confirmed = {}
	for _, order in pairs(orders) do
		if order.confirmed then
			table.insert(confirmed, order)
		end
	end
	return confirmed
end

function MovementOrderData.ClearAll()
	orders = {}
end

return MovementOrderData