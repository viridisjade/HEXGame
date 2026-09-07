
--[[
    DiplomacySystem (ModuleScript)
    Ort: ServerScriptService > DiplomacySystem
    
    Verwaltet Kriegs- und Friedenszustände.
--]]

local DiplomacySystem = {}

local relations = {}

local DEFAULT_STATE = "war"

local function keyFor(a, b)
	if not a or not b then return nil end
	local idA, idB = a.UserId, b.UserId
	if idA > idB then idA, idB = idB, idA end
	return idA .. "_" .. idB
end

function DiplomacySystem.GetRelation(playerA, playerB)
	if playerA == playerB then return "self" end
	local key = keyFor(playerA, playerB)
	if not key then return DEFAULT_STATE end
	return relations[key] or DEFAULT_STATE
end

function DiplomacySystem.IsAtWar(playerA, playerB)
	if playerA == nil or playerB == nil then return true end
	if playerA == playerB then return false end
	return DiplomacySystem.GetRelation(playerA, playerB) == "war"
end

function DiplomacySystem.IsAtPeace(playerA, playerB)
	if playerA == playerB then return true end
	return DiplomacySystem.GetRelation(playerA, playerB) == "peace"
end

function DiplomacySystem.DeclareWar(playerA, playerB)
	local key = keyFor(playerA, playerB)
	if not key then return false end
	relations[key] = "war"
	print("[Diplomacy] Krieg: " .. playerA.Name .. " vs " .. playerB.Name)
	return true
end

function DiplomacySystem.MakePeace(playerA, playerB)
	local key = keyFor(playerA, playerB)
	if not key then return false end
	relations[key] = "peace"
	print("[Diplomacy] Frieden: " .. playerA.Name .. " und " .. playerB.Name)
	return true
end

function DiplomacySystem.ClearPlayer(player)
	if not player then return end
	local id = player.UserId
	for key in pairs(relations) do
		local a, b = key:match("^(%d+)_(%d+)$")
		if a and (tonumber(a) == id or tonumber(b) == id) then
			relations[key] = nil
		end
	end
end

--------------------------------------------------------------------------------
-- AreAllied(playerA, playerB) -> boolean
-- CombatSystem.StartCombat uses this: allies never fight each other.
-- Wildlife (nil owner) is never an ally.
--------------------------------------------------------------------------------
function DiplomacySystem.AreAllied(playerA, playerB)
	if playerA == nil or playerB == nil then return false end
	if playerA == playerB then return true end
	return DiplomacySystem.GetRelation(playerA, playerB) == "peace"
end

return DiplomacySystem
