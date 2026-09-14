--[[
    DiplomacyHandler (Script)
    Ort: ServerScriptService > DiplomacyHandler

    Bindet alle Diplomatie-Remotes (Client -> Server) an das DiplomacySystem.

    Remotes (in ReplicatedStorage, siehe Net.ROOT):
        DiplomacySendOffer     {toPlayerId, type}
        DiplomacyRespondOffer  {fromPlayerId, offerType, accept}
        DiplomacyDeclareWar    {toPlayerId}
        DiplomacyBreakAlliance {toPlayerId}

    Read-Only RemoteFunction GetDiplomacyState (in DataRemotes):
        liefert die Beziehungen + Angebote eines Spielers.

    Die Server -> Client-Push-Remotes (DiplomacyUpdate, DiplomacyNotification)
    feuert das DiplomacySystem selbst.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local DiplomacySystem = require(script.Parent:WaitForChild("DiplomacySystem"))

local dataRemotes = ReplicatedStorage:WaitForChild("DataRemotes", 30)

--------------------------------------------------------------------------------
-- HELFER
--------------------------------------------------------------------------------
local function playerById(id)
	id = tonumber(id)
	if not id then return nil end
	for _, player in ipairs(Players:GetPlayers()) do
		if player.UserId == id then return player end
	end
	return nil
end

local function onRootEvent(name, handler)
	local remote = ReplicatedStorage:FindFirstChild(name)
		or ReplicatedStorage:WaitForChild(name, 5)
	if not remote then
		warn("[DiplomacyHandler] RemoteEvent fehlt: " .. name)
		return
	end
	remote.OnServerEvent:Connect(handler)
end

--------------------------------------------------------------------------------
-- GetDiplomacyState (read only)
--------------------------------------------------------------------------------
local stateRemote = dataRemotes:FindFirstChild("GetDiplomacyState")
	or dataRemotes:WaitForChild("GetDiplomacyState", 5)
if stateRemote then
	stateRemote.OnServerInvoke = function(player)
		if not player then return nil end
		return {
			relations = DiplomacySystem.GetRelationsByPlayer(player),
			pendingOffers = DiplomacySystem.GetOffersFor(player),
		}
	end
end

--------------------------------------------------------------------------------
-- ACTIONEN
--------------------------------------------------------------------------------
onRootEvent("DiplomacySendOffer", function(player, toPlayerId, offerType)
	local target = playerById(toPlayerId)
	if not target then return end
	if offerType == "Alliance" then
		DiplomacySystem.SendAllianceOffer(player, target)
	elseif offerType == "Peace" then
		DiplomacySystem.SendPeaceOffer(player, target)
	end
end)

onRootEvent("DiplomacyRespondOffer", function(player, fromPlayerId, offerType, accept)
	local from = playerById(fromPlayerId)
	if not from then return end
	DiplomacySystem.RespondOffer(player, from, offerType, accept == true)
end)

onRootEvent("DiplomacyDeclareWar", function(player, toPlayerId)
	local target = playerById(toPlayerId)
	if not target then return end
	DiplomacySystem.DeclareWar(player, target)
end)

onRootEvent("DiplomacyBreakAlliance", function(player, toPlayerId)
	local target = playerById(toPlayerId)
	if not target then return end
	DiplomacySystem.BreakAlliance(player, target)
end)

print("[DiplomacyHandler] Bereit.")
