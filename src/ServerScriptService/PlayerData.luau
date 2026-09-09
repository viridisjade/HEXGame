--[[
    PlayerData (ModuleScript)
    Ort: ServerScriptService > PlayerData
    
    Speichert alle Spieler-Daten in einer zentralen Tabelle.
    Die Spielerfarbe kommt standardmäßig aus PlayerColorConfig.
    
    Datenstruktur pro Spieler:
    {
        player = Player,          -- Referenz auf den Player
        gold = number,            -- Aktuelles Gold
        provinces = {},           -- Liste der Provinz-IDs { 1, 4, 7, ... }
        provinceCount = number,   -- Anzahl der besessenen Provinzen
        cities = {},              -- Liste der Stadt-Daten (zukünftig)
        cityCount = number,       -- Anzahl der Städte
        color = Color3,           -- Spielerfarbe
    }
    
    Verwendung:
        local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
        
        PlayerData.InitPlayer(player)
        PlayerData.AddGold(player, 100)
        PlayerData.AddProvince(player, 3)
        
        local data = PlayerData.GetPlayerData(player)
        print(data.gold)
        print(data.provinceCount)
--]]

local PlayerData = {}

local Players = game:GetService("Players")
local PlayerColorConfig = require(script.Parent:WaitForChild("PlayerColorConfig"))

--------------------------------------------------------------------------------
-- Interne Daten
--------------------------------------------------------------------------------
local playerDataStore = {}  -- playerDataStore[player] = data

--------------------------------------------------------------------------------
-- InitPlayer(player, optionalColor)
-- Initialisiert die Daten für einen neuen Spieler.
-- Wird aufgerufen wenn ein Spieler dem Spiel beitritt.
--------------------------------------------------------------------------------
function PlayerData.InitPlayer(player, optionalColor)
	if playerDataStore[player] then return playerDataStore[player] end

	local assignedColor = optionalColor or PlayerColorConfig.AssignColor(player)

	playerDataStore[player] = {
		player = player,
		gold = 220,
		provinces = {},
		provinceCount = 0,
		cities = {},
		cityCount = 0,
		color = assignedColor,
		-- Diplomatie-Zustand (siehe DiplomacyData / DiplomacySystem).
		relations = {},       -- [otherUserId] = "Alliance"|"Neutral"|"War"
		pendingOffers = {},   -- Liste der laufenden Angebote
		-- Victory/Points (siehe PointSystem/VictorySystem).
		points = 0,            -- aktuelle Sieg-Punkte
		capitalCityId = nil,   -- Hauptstadt-City-ID (erste gegruendete City)
		isEliminated = false,  -- Spieler ausgeschieden
		allianceId = nil,      -- Allianz-Gruppen-ID
	}

	print("[PlayerData] Spieler initialisiert: " .. player.Name .. " (Farbe: " .. tostring(playerDataStore[player].color) .. ")")
	return playerDataStore[player]
end

--------------------------------------------------------------------------------
-- RemovePlayer(player)
-- Entfernt die Daten eines Spielers (bei Verlassen).
--------------------------------------------------------------------------------
function PlayerData.RemovePlayer(player)
	PlayerColorConfig.ReleaseColor(player)
	playerDataStore[player] = nil
end

--------------------------------------------------------------------------------
-- GetPlayerData(player) -> table or nil
--------------------------------------------------------------------------------
function PlayerData.GetPlayerData(player)
	return playerDataStore[player]
end

--------------------------------------------------------------------------------
-- GetAllPlayerData() -> table
--------------------------------------------------------------------------------
function PlayerData.GetAllPlayerData()
	return playerDataStore
end

--------------------------------------------------------------------------------
-- GOLD
--------------------------------------------------------------------------------
function PlayerData.GetGold(player)
	local data = playerDataStore[player]
	return data and data.gold or 0
end

function PlayerData.SetGold(player, amount)
	local data = playerDataStore[player]
	if not data then return end
	data.gold = math.max(0, amount)
end

function PlayerData.AddGold(player, amount)
	local data = playerDataStore[player]
	if not data then return end
	data.gold = math.max(0, data.gold + amount)
end

function PlayerData.SpendGold(player, amount)
	local data = playerDataStore[player]
	if not data then return false end
	if data.gold < amount then return false end
	data.gold = data.gold - amount
	return true
end

function PlayerData.CanAfford(player, amount)
	local data = playerDataStore[player]
	if not data then return false end
	return data.gold >= amount
end

--------------------------------------------------------------------------------
-- PROVINZEN
--------------------------------------------------------------------------------
function PlayerData.GetProvinces(player)
	local data = playerDataStore[player]
	return data and data.provinces or {}
end

function PlayerData.GetProvinceCount(player)
	local data = playerDataStore[player]
	return data and data.provinceCount or 0
end

function PlayerData.AddProvince(player, provinceId)
	local data = playerDataStore[player]
	if not data then return false end

	-- Prüfe ob schon vorhanden
	for _, id in ipairs(data.provinces) do
		if id == provinceId then return false end
	end

	table.insert(data.provinces, provinceId)
	data.provinceCount = #data.provinces
	return true
end

function PlayerData.RemoveProvince(player, provinceId)
	local data = playerDataStore[player]
	if not data then return false end

	for i, id in ipairs(data.provinces) do
		if id == provinceId then
			table.remove(data.provinces, i)
			data.provinceCount = #data.provinces
			return true
		end
	end
	return false
end

function PlayerData.HasProvince(player, provinceId)
	local data = playerDataStore[player]
	if not data then return false end

	for _, id in ipairs(data.provinces) do
		if id == provinceId then return true end
	end
	return false
end

--------------------------------------------------------------------------------
-- STÄDTE
--------------------------------------------------------------------------------
function PlayerData.GetCities(player)
	local data = playerDataStore[player]
	return data and data.cities or {}
end

function PlayerData.GetCityCount(player)
	local data = playerDataStore[player]
	return data and data.cityCount or 0
end

function PlayerData.AddCity(player, cityData)
	local data = playerDataStore[player]
	if not data then return false end

	table.insert(data.cities, cityData)
	data.cityCount = #data.cities
	return true
end

function PlayerData.RemoveCity(player, cityIndex)
	local data = playerDataStore[player]
	if not data then return false end

	if cityIndex < 1 or cityIndex > #data.cities then return false end
	table.remove(data.cities, cityIndex)
	data.cityCount = #data.cities
	return true
end

--------------------------------------------------------------------------------
-- FARBE
--------------------------------------------------------------------------------
function PlayerData.GetColor(player)
	local data = playerDataStore[player]
	return data and data.color or Color3.fromRGB(128, 128, 128)
end

function PlayerData.SetColor(player, color)
	local data = playerDataStore[player]
	if not data then return end
	data.color = color
end

--------------------------------------------------------------------------------
-- PrintStats(player)
--------------------------------------------------------------------------------
function PlayerData.PrintStats(player)
	local data = playerDataStore[player]
	if not data then
		warn("[PlayerData] Keine Daten für " .. tostring(player))
		return
	end

	print("[PlayerData] === " .. player.Name .. " ===")
	print("  Gold: " .. data.gold)
	print("  Provinzen: " .. data.provinceCount .. " (" .. table.concat(data.provinces, ", ") .. ")")
	print("  Städte: " .. data.cityCount)
	print("  Farbe: " .. tostring(data.color))
end

--------------------------------------------------------------------------------
-- DIPLOMATIE
--------------------------------------------------------------------------------
function PlayerData.GetRelations(player)
	local data = playerDataStore[player]
	return data and data.relations or {}
end

function PlayerData.SetRelation(player, otherUserId, state)
	local data = playerDataStore[player]
	if not data then return end
	data.relations[otherUserId] = state
end

function PlayerData.GetRelation(player, otherUserId)
	local data = playerDataStore[player]
	if not data then return nil end
	return data.relations[otherUserId]
end

function PlayerData.GetPendingOffers(player)
	local data = playerDataStore[player]
	return data and data.pendingOffers or {}
end

function PlayerData.SetPendingOffers(player, offers)
	local data = playerDataStore[player]
	if not data then return end
	data.pendingOffers = offers or {}
end

--------------------------------------------------------------------------------
-- VICTORY / POINTS
--------------------------------------------------------------------------------
function PlayerData.GetPoints(player)
	local data = playerDataStore[player]
	return data and data.points or 0
end

function PlayerData.SetPoints(player, amount)
	local data = playerDataStore[player]
	if not data then return end
	data.points = math.max(0, amount or 0)
end

function PlayerData.AddPoints(player, amount)
	local data = playerDataStore[player]
	if not data then return end
	data.points = math.max(0, (data.points or 0) + (amount or 0))
end

function PlayerData.GetCapitalCityId(player)
	local data = playerDataStore[player]
	return data and data.capitalCityId or nil
end

function PlayerData.SetCapitalCityId(player, cityId)
	local data = playerDataStore[player]
	if not data then return end
	data.capitalCityId = cityId
end

function PlayerData.IsEliminated(player)
	local data = playerDataStore[player]
	return data and data.isEliminated or false
end

function PlayerData.SetEliminated(player, value)
	local data = playerDataStore[player]
	if not data then return end
	data.isEliminated = value == true
end

function PlayerData.GetAllianceId(player)
	local data = playerDataStore[player]
	return data and data.allianceId or nil
end

function PlayerData.SetAllianceId(player, allianceId)
	local data = playerDataStore[player]
	if not data then return end
	data.allianceId = allianceId
end

--------------------------------------------------------------------------------
-- PrintAll()
--------------------------------------------------------------------------------
function PlayerData.PrintAll()
	print("[PlayerData] === Alle Spieler ===")
	for player, data in pairs(playerDataStore) do
		PlayerData.PrintStats(player)
	end
end

return PlayerData
