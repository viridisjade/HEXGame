--[[
    DataQueryBinder (Script)
    Ort: ServerScriptService > DataQueryBinder
    
    Verbindet ALLE reinen Lese-Remotes (RemoteFunctions) an EINEM Ort.
    
    ERSETZT diese Handler (in Studio LÖSCHEN!):
      DataRemoteHandler, CityDataRemoteHandler, CampDataRemoteHandler,
      EmpireDataHandler, OwnerCheckHandler, HexInfoHandler
      + den Lese-Anteil von UnitBuildHandler (GetCitySpawnHexes)
    
    REGEL: Hier wird nur GELESEN. Kein Handler ändert Spielzustand.
    Aktionen liegen in WorldActions und CityActions.
    
    BLEIBEN unverändert (brauchen eigenen internen Zustand):
      RoundSystem       (GetRoundData + SkipRound)
      MovementHandler   (RequestRoute, ConfirmMove, CancelMove, ContinueMove)
      CityStatsNotifier (Server -> Client Push)
    
    Vorteil: Die Antwort auf "Welcher Remote liefert was?" steht
    jetzt in EINER Tabelle - unten bei QUERIES.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Daten-Module
local HexData = require(script.Parent:WaitForChild("HexData"))
local ProvinceData = require(script.Parent:WaitForChild("ProvinceData"))
local UnitData = require(script.Parent:WaitForChild("UnitData"))
local ArmyData = require(script.Parent:WaitForChild("ArmyData"))
local CampData = require(script.Parent:WaitForChild("CampData"))
local CityData = require(script.Parent:WaitForChild("CityData"))
local BuildingCostSystem = require(script.Parent:WaitForChild("BuildingCostSystem"))
local ConstructionSystem = require(script.Parent:WaitForChild("ConstructionSystem"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local UnitConfig = require(ReplicatedStorage:WaitForChild("UnitConfig"))
local ArmySystem = require(script.Parent:WaitForChild("ArmySystem"))
local DiplomacySystem = require(script.Parent:WaitForChild("DiplomacySystem"))

local dataRemotes = ReplicatedStorage:WaitForChild("DataRemotes", 30)

--------------------------------------------------------------------------------
-- drop(func)
-- Roblox übergibt OnServerInvoke immer (player, ...) - die Modul-Funktionen
-- wollen aber nur (...). drop() wirft den player-Parameter weg, damit wir
-- die Funktionen direkt in die Tabelle schreiben können.
--------------------------------------------------------------------------------
local function drop(func)
	return function(_, ...)
		return func(...)
	end
end

--------------------------------------------------------------------------------
-- Handler mit etwas mehr Logik
--------------------------------------------------------------------------------

-- Gehört diese Army dem anfragenden Spieler?
local function getArmyOwner(player, armyId)
	if not armyId then return false end
	local army = ArmyData.GetArmy(armyId)
	if not army then return false end
	return army.owner == player
end

-- Diplomatie-Playerliste: alle anderen Spieler + Farbe + Beziehung.
local function getDiplomacyPlayers(player)
	if not player then return {} end
	local Players = game:GetService("Players")
	local result = {}
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			result[#result + 1] = {
				userId = other.UserId,
				name = other.Name,
				color = PlayerData.GetColor(other),
				relation = DiplomacySystem.GetRelation(player, other),
			}
		end
	end
	table.sort(result, function(a, b) return a.name < b.name end)
	return result
end

-- Kompletter Army-Snapshot in EINEM Call fuer die ArmyGui.
-- Ersetzt das alte Muster "1x GetArmy + Nx GetUnit" (N+1 RPC-Problem).
-- Liefert die Army inkl. aufgeloester Units (Stat-Config + aktuelle Werte).
local function getArmyDetail(player, armyId)
	local army = ArmyData.GetArmy(armyId)
	if not army then return nil end

	local units = {}
	for _, unitId in ipairs(army.units or {}) do
		local unit = UnitData.GetUnit(unitId)
		if unit then
			local cfg = UnitConfig.GetUnit(unit.unitType)
			table.insert(units, {
				id = unit.id,
				unitType = unit.unitType,
				name = cfg and cfg.Name or unit.unitType,
				icon = cfg and cfg.Icon or "",
				currentLP = unit.currentLP or 0,
				maxLP = unit.maxLP or (cfg and cfg.Stats and cfg.Stats.LP) or 0,
				attack = unit.attack or (cfg and cfg.Stats and cfg.Stats.Attack) or 0,
				defense = unit.defense or (cfg and cfg.Stats and cfg.Stats.Defense) or 0,
				sight = (cfg and cfg.Stats and cfg.Stats.Sight) or 0,
				currentMovement = unit.currentMovement or 0,
				maxMovement = unit.maxMovement or (cfg and cfg.Stats and cfg.Stats.Movement) or 0,
				alive = unit.alive == true,
			})
		end
	end

	return {
		id = army.id,
		name = army.name,
		q = army.q,
		r = army.r,
		ownerName = army.owner and army.owner.Name or nil,
		-- Maximale Armee-Groesse (Basis 8 + Logistics-Tech-Bonus).
		-- Der Client nutzt das fuer die dynamischen Unit-Slots.
		maxUnits = ArmySystem.GetMaxUnits(armyId),
		stats = army.stats,
		units = units,
	}
end

-- Statistiken fürs Empire-Overlay
local function getEmpireData(player)
	-- Spielerdaten sicherstellen (Lazy-Init wie bisher)
	if not PlayerData.GetPlayerData(player) then
		PlayerData.InitPlayer(player)
	end

	return {
		playerName = player.Name,
		gold = PlayerData.GetGold(player),
		armyCount = #ArmyData.GetArmiesByOwner(player),
		campCount = #CampData.GetCampsByOwner(player),
		cityCount = #CityData.GetCitiesByOwner(player),
		points = PlayerData.GetPoints(player) or 0,
		capitalCityId = PlayerData.GetCapitalCityId(player),
		isEliminated = PlayerData.IsEliminated(player),
	}
end

-- Gültige Spawn-Felder einer Stadt (nur eigene Städte)
local function getCitySpawnHexes(player, cityId)
	local city = CityData.GetCity(cityId)
	if not city or city.owner ~= player then
		return {}
	end
	return ConstructionSystem.GetValidSpawnHexes(cityId)
end

-- Alles was auf einem Hex steht (für den WorldClickRouter)
local function getHexInfo(player, q, r)
	q = tonumber(q)
	r = tonumber(r)
	if not q or not r then
		return { exists = false }
	end

	local hex = HexData.GetHex(q, r)
	if not hex then
		return { exists = false, q = q, r = r }
	end

	local info = {
		exists = true,
		q = q,
		r = r,
		terrain = hex.terrain,
		soil = hex.soil,
		province = hex.province,
	}

	local army = ArmyData.GetArmyOnHex(q, r)
	if army then
		info.army = {
			id = army.id,
			name = army.name,
			isMine = (army.owner == player),
			unitCount = #(army.units or {}),
		}
	end

	local camp = CampData.GetCampOnHex(q, r)
	if camp then
		info.camp = {
			id = camp.id,
			name = camp.name,
			isMine = (camp.owner == player),
		}
	end

	local city = CityData.GetCityOnHex(q, r)
	if city then
		info.city = {
			id = city.id,
			name = city.name,
			isMine = (city.owner == player),
		}
	end

	return info
end

--------------------------------------------------------------------------------
-- DIE BINDING-TABELLE
-- Eine Zeile pro Lese-Remote. Neue Abfrage? Hier eine Zeile ergänzen.
--------------------------------------------------------------------------------
local QUERIES = {
	-- HEX
	GetHex              = drop(HexData.GetHex),
	GetAllHexes         = drop(HexData.GetAllHexes),
	GetHexCount         = drop(HexData.GetHexCount),
	GetHexesByTerrain   = drop(HexData.GetHexesByTerrain),

	-- PROVINZEN
	GetProvince         = drop(ProvinceData.GetProvince),
	GetAllProvinces     = drop(ProvinceData.GetAllProvinces),
	GetProvinceCount    = drop(ProvinceData.GetProvinceCount),
	GetProvincesByOwner = drop(ProvinceData.GetProvincesByOwner),

	-- UNITS
	GetUnit             = drop(UnitData.GetUnit),
	GetUnitsByOwner     = drop(UnitData.GetUnitsByOwner),
	GetUnitCount        = drop(UnitData.GetUnitCount),
	GetAliveUnitCount   = drop(UnitData.GetAliveUnitCount),
	GetUnitStats        = drop(UnitData.GetUnitStats),
	GetUnitConfig       = drop(UnitData.GetUnitConfig),

	-- ARMEEN
	GetArmy             = drop(ArmyData.GetArmy),
	GetArmyDetail       = getArmyDetail,         -- Batch-Snapshot fuer die ArmyGui
	GetArmiesByOwner    = drop(ArmyData.GetArmiesByOwner),
	GetArmyOnHex        = drop(ArmyData.GetArmyOnHex),
	GetArmyCount        = drop(ArmyData.GetArmyCount),
	GetArmyOwner        = getArmyOwner,          -- mit Besitz-Prüfung

	-- CAMPS
	GetCamp             = drop(CampData.GetCamp),
	GetCampOnHex        = drop(CampData.GetCampOnHex),

	-- STÄDTE
	GetCity             = drop(CityData.GetCity),
	GetCityOnHex        = drop(CityData.GetCityOnHex),
	GetBuildingCosts    = drop(BuildingCostSystem.GetAllBuildingCosts),
	GetCitySpawnHexes   = getCitySpawnHexes,     -- nur eigene Städte

	-- SPIELER & KLICK
	GetEmpireData       = getEmpireData,         -- mit Lazy-Init
	GetDiplomacyPlayers = getDiplomacyPlayers,   -- fuer das Diplomatie-Fenster
	GetHexInfo          = getHexInfo,            -- für den WorldClickRouter
}

--------------------------------------------------------------------------------
-- Binden
--------------------------------------------------------------------------------
local bound, missing = 0, 0

for name, handler in pairs(QUERIES) do
	local remote = dataRemotes:WaitForChild(name, 5)
	if remote then
		remote.OnServerInvoke = handler
		bound = bound + 1
	else
		missing = missing + 1
		warn("[DataQueryBinder] Remote fehlt: " .. name)
	end
end

print("[DataQueryBinder] " .. bound .. " Lese-Remotes verbunden"
	.. (missing > 0 and (" - " .. missing .. " FEHLEN!") or ""))