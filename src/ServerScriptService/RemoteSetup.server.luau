
--[[
    RemoteSetup (Script)
    Ort: ServerScriptService > RemoteSetup
    
    Erstellt ALLE RemoteFunctions und RemoteEvents des Spiels.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LOG_PREFIX = "[RemoteSetup]"

local created = 0
local existed = 0
local conflicts = 0

local function ensure(parent, className, name)
	local found = parent:FindFirstChild(name)
	if found then
		if found.ClassName ~= className then
			conflicts = conflicts + 1
			warn(LOG_PREFIX .. " KONFLIKT:  .. (parent.Name) .. / .. name ..  ist ein " 
				.. found.ClassName .. ", erwartet wurde " .. className)
		else
			existed = existed + 1
		end
		return found
	end
	local obj = Instance.new(className)
	obj.Name = name
	obj.Parent = parent
	created = created + 1
	return obj
end

local dataRemotes = ReplicatedStorage:FindFirstChild("DataRemotes")
if not dataRemotes then
	dataRemotes = Instance.new("Folder")
	dataRemotes.Name = "DataRemotes"
	dataRemotes.Parent = ReplicatedStorage
	print(LOG_PREFIX .. " Ordner DataRemotes erstellt")
else
	print(LOG_PREFIX .. " Ordner DataRemotes existiert bereits")
end

ensure(dataRemotes, "RemoteFunction", "GetHex")
ensure(dataRemotes, "RemoteFunction", "GetAllHexes")
ensure(dataRemotes, "RemoteFunction", "GetHexCount")
ensure(dataRemotes, "RemoteFunction", "GetHexesByTerrain")

ensure(dataRemotes, "RemoteFunction", "GetProvince")
ensure(dataRemotes, "RemoteFunction", "GetAllProvinces")
ensure(dataRemotes, "RemoteFunction", "GetProvinceCount")
ensure(dataRemotes, "RemoteFunction", "GetProvincesByOwner")

ensure(dataRemotes, "RemoteFunction", "GetUnit")
ensure(dataRemotes, "RemoteFunction", "GetUnitsByOwner")
ensure(dataRemotes, "RemoteFunction", "GetUnitCount")
ensure(dataRemotes, "RemoteFunction", "GetAliveUnitCount")
ensure(dataRemotes, "RemoteFunction", "GetUnitStats")
ensure(dataRemotes, "RemoteFunction", "GetUnitConfig")

ensure(dataRemotes, "RemoteFunction", "GetArmy")
ensure(dataRemotes, "RemoteFunction", "GetArmyDetail")
ensure(dataRemotes, "RemoteFunction", "GetArmiesByOwner")
ensure(dataRemotes, "RemoteFunction", "GetArmyOnHex")
ensure(dataRemotes, "RemoteFunction", "GetArmyCount")
ensure(dataRemotes, "RemoteFunction", "GetArmyOwner")
ensure(dataRemotes, "RemoteEvent", "ArmyStatsChanged")

ensure(dataRemotes, "RemoteFunction", "GetCamp")
ensure(dataRemotes, "RemoteFunction", "GetCampOnHex")

ensure(dataRemotes, "RemoteFunction", "GetCity")
ensure(dataRemotes, "RemoteFunction", "GetCityOnHex")
ensure(dataRemotes, "RemoteFunction", "GetBuildingCosts")
ensure(dataRemotes, "RemoteFunction", "GetCitySpawnHexes")

ensure(dataRemotes, "RemoteFunction", "GetEmpireData")
ensure(dataRemotes, "RemoteFunction", "GetRoundData")

ensure(dataRemotes, "RemoteFunction", "GetHexInfo")

ensure(dataRemotes, "RemoteEvent", "CombatStart")
ensure(dataRemotes, "RemoteEvent", "CombatRoundUpdate")
ensure(dataRemotes, "RemoteEvent", "CombatEnd")
ensure(dataRemotes, "RemoteEvent", "FleeRequest")
ensure(dataRemotes, "RemoteEvent", "FleeResult")

ensure(dataRemotes, "RemoteEvent", "RequestClaimProvince")
ensure(dataRemotes, "RemoteEvent", "RequestSpawnUnit")
ensure(dataRemotes, "RemoteEvent", "RequestFoundCity")
ensure(dataRemotes, "RemoteEvent", "RequestPlaceBuilding")
ensure(dataRemotes, "RemoteEvent", "RequestRecruitUnit")
ensure(dataRemotes, "RemoteEvent", "RequestMoveCitizen")
ensure(dataRemotes, "RemoteEvent", "RequestInstantBuy")
ensure(dataRemotes, "RemoteEvent", "RequestCancelBuildOrder")
ensure(dataRemotes, "RemoteEvent", "RequestBuildCamp")
ensure(dataRemotes, "RemoteEvent", "CityStatsChanged")

-- Turn based combat: server -> client
ensure(dataRemotes, "RemoteEvent", "CombatTurnStart")
ensure(dataRemotes, "RemoteEvent", "CombatUnitSelected")
ensure(dataRemotes, "RemoteEvent", "CombatAttackResult")
ensure(dataRemotes, "RemoteEvent", "CombatAutoResolveStart")
ensure(dataRemotes, "RemoteEvent", "CombatAutoResolveVote")
-- Turn based combat: client queries
ensure(dataRemotes, "RemoteFunction", "GetArmyInCombat")
ensure(dataRemotes, "RemoteFunction", "GetCombatSnapshot")

-- Tech tree: server -> client push + state query
ensure(dataRemotes, "RemoteEvent", "TechTreeUpdate")
ensure(dataRemotes, "RemoteEvent", "TechResearched")
ensure(dataRemotes, "RemoteFunction", "GetTechState")

-- Diplomatie: server -> client push + state query
ensure(dataRemotes, "RemoteEvent", "DiplomacyUpdate")
ensure(dataRemotes, "RemoteEvent", "DiplomacyNotification")
ensure(dataRemotes, "RemoteFunction", "GetDiplomacyState")
ensure(dataRemotes, "RemoteFunction", "GetDiplomacyPlayers")
ensure(dataRemotes, "RemoteFunction", "GetDiplomacyAllianceInfo")

-- Fog of War: server -> client push (Init = voller State beim Join, Update = Delta)
ensure(dataRemotes, "RemoteEvent", "FogOfWarInit")
ensure(dataRemotes, "RemoteEvent", "FogOfWarUpdate")

-- Victory system: server -> client push
ensure(dataRemotes, "RemoteEvent", "PointsUpdate")
ensure(dataRemotes, "RemoteEvent", "VictoryAchieved")
ensure(dataRemotes, "RemoteEvent", "PlayerEliminated")
ensure(dataRemotes, "RemoteEvent", "CapitalCityMarked")

ensure(ReplicatedStorage, "RemoteEvent", "RoundEnd")
ensure(ReplicatedStorage, "RemoteEvent", "SkipRound")
ensure(ReplicatedStorage, "RemoteFunction", "RequestRoute")
ensure(ReplicatedStorage, "RemoteEvent", "ConfirmMove")
ensure(ReplicatedStorage, "RemoteEvent", "CancelMove")

-- Turn based combat input (root level, mirrored in Net.ROOT)
ensure(ReplicatedStorage, "RemoteEvent", "CombatSelectUnit")
ensure(ReplicatedStorage, "RemoteEvent", "CombatSelectTarget")
ensure(ReplicatedStorage, "RemoteEvent", "CombatAutoResolve")

-- Tech tree input (root level, mirrored in Net.ROOT)
ensure(ReplicatedStorage, "RemoteEvent", "TechAddToQueue")
ensure(ReplicatedStorage, "RemoteEvent", "TechRemoveFromQueue")
ensure(ReplicatedStorage, "RemoteEvent", "TechReorderQueue")

-- Diplomatie input (root level, mirrored in Net.ROOT)
ensure(ReplicatedStorage, "RemoteEvent", "DiplomacySendOffer")
ensure(ReplicatedStorage, "RemoteEvent", "DiplomacyRespondOffer")
ensure(ReplicatedStorage, "RemoteEvent", "DiplomacyDeclareWar")
ensure(ReplicatedStorage, "RemoteEvent", "DiplomacyBreakAlliance")

local totalRF = 0
local totalRE = 0
for _, child in ipairs(dataRemotes:GetChildren()) do
	if child:IsA("RemoteFunction") then
		totalRF = totalRF + 1
	elseif child:IsA("RemoteEvent") then
		totalRE = totalRE + 1
	end
end

print(LOG_PREFIX .. " ===== Zusammenfassung =====")
print(LOG_PREFIX .. " Neu erstellt:        " .. created)
print(LOG_PREFIX .. " Bereits vorhanden:   " .. existed)
print(LOG_PREFIX .. " Konflikte:           " .. conflicts)
print(LOG_PREFIX .. " DataRemotes enthält: " .. totalRF .. " RemoteFunctions + " .. totalRE .. " RemoteEvents")
print(LOG_PREFIX .. " OK - alle Remotes bereit. Handler können jetzt verbinden.")
