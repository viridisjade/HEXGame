--[[
    ProvinceData (ModuleScript)
    Ort: ServerScriptService > ProvinceData
    
    Speichert alle Provinz-Daten in einer zentralen Tabelle.
    Die Standard-Provinzfarben werden direkt in ProvinceData.ColorConfig festgelegt.
    
    Datenstruktur pro Provinz:
    {
        id = number,              -- Provinz-Nummer (1, 2, 3, ...)
        name = string,            -- Name der Provinz (z.B. "Nord-Mark")
        owner = nil,              -- Besitzer (Player oder nil)
        color = Color3,           -- Farbe der Provinz
        hexes = {},               -- Liste aller {q, r} Koordinaten
        capital = nil,            -- Hauptstadt {q, r} oder nil
    }
    
    Verwendung:
        local ProvinceData = require(game.ServerScriptService:WaitForChild("ProvinceData"))
        
        -- Provinz erstellen
        ProvinceData.CreateProvince(1, {
            name = "Nord-Mark",
            owner = nil,
            color = Color3.fromRGB(255, 100, 100),
        })
        
        -- Hex zu Provinz hinzufügen
        ProvinceData.AddHexToProvince(1, 5, 10)
        
        -- Provinz abrufen
        local province = ProvinceData.GetProvince(1)
        print(province.name)  -- "Nord-Mark"
--]]

local ProvinceData = {}

--------------------------------------------------------------------------------
-- FARB-KONFIGURATION
-- Ändere HIER die Standardfarben der Provinzen.
-- Aktuell: verschiedene Grautöne damit Nachbar-Provinzen unterscheidbar bleiben.
--------------------------------------------------------------------------------
ProvinceData.ColorConfig = {
	-- Alle Provinzen standardmäßig MONOTON grau
	BASE_PROVINCE_COLOR = Color3.fromRGB(110, 110, 110),
	FALLBACK_COLOR = Color3.fromRGB(110, 110, 110),
}

--------------------------------------------------------------------------------
-- Interne Daten-Tabelle
-- Struktur: provinces[id] = { id, name, owner, color, hexes, capital }
--------------------------------------------------------------------------------
local provinces = {}

--------------------------------------------------------------------------------
-- Standard-Namen für Provinzen (werden zufällig ausgewählt)
--------------------------------------------------------------------------------
local defaultNames = {
	"Nordmark", "Südland", "Ostreich", "Westfalen",
	"Bergheim", "Thalgrund", "Seenland", "Waldreich",
	"Hochfeld", "Grüntal", "Steinburg", "Flussmark",
	"Eichenwald", "Nebelheim", "Sonnenfeld", "Mondtal",
	"Sturmküste", "Frostgipfel", "Glutstein", "Windbruch",
	"Silbersee", "Goldgrund", "Kupferberg", "Eisenwald",
	"Himmelshöh", "Schattenwald", "Lichtaue", "Dunkeltal",
	"Königsmark", "Fürstenland", "Grafenhain", "Ritterfeld",
}

local usedNames = {}

--------------------------------------------------------------------------------
-- generateProvinceColor(provinceId) -> Color3
-- Alle Provinzen bekommen dieselbe monotone Grundfarbe.
-- Hover-/Auswahl-Effekte passieren CLIENT-seitig in StrategyCam.
--------------------------------------------------------------------------------
function ProvinceData.generateProvinceColor(provinceId)
	return ProvinceData.ColorConfig.BASE_PROVINCE_COLOR or ProvinceData.ColorConfig.FALLBACK_COLOR
end

--------------------------------------------------------------------------------
-- getRandomName() -> string
-- Gibt einen zufälligen, noch nicht verwendeten Namen zurück
--------------------------------------------------------------------------------
function ProvinceData.getRandomName()
	local availableNames = {}

	for _, name in ipairs(defaultNames) do
		if not usedNames[name] then
			table.insert(availableNames, name)
		end
	end

	if #availableNames > 0 then
		local name = availableNames[math.random(1, #availableNames)]
		usedNames[name] = true
		return name
	end

	-- Fallback wenn alle Namen vergeben sind
	return "Provinz " .. tostring(#provinces + 1)
end

--------------------------------------------------------------------------------
-- CreateProvince(id, data)
-- Erstellt eine neue Provinz mit der angegebenen ID
--------------------------------------------------------------------------------
function ProvinceData.CreateProvince(id, data)
	data = data or {}

	provinces[id] = {
		id = id,
		name = data.name or ProvinceData.getRandomName(),
		owner = data.owner or nil,
		color = data.color or ProvinceData.generateProvinceColor(id),
		hexes = data.hexes or {},
		capital = data.capital or nil,
	}

	return provinces[id]
end

--------------------------------------------------------------------------------
-- GetProvince(id) -> table or nil
--------------------------------------------------------------------------------
function ProvinceData.GetProvince(id)
	return provinces[id]
end

--------------------------------------------------------------------------------
-- GetAllProvinces() -> table
--------------------------------------------------------------------------------
function ProvinceData.GetAllProvinces()
	return provinces
end

--------------------------------------------------------------------------------
-- GetProvinceCount() -> number
--------------------------------------------------------------------------------
function ProvinceData.GetProvinceCount()
	local count = 0
	for _ in pairs(provinces) do
		count = count + 1
	end
	return count
end

--------------------------------------------------------------------------------
-- UpdateProvince(id, updates)
-- Aktualisiert einzelne Felder einer Provinz
--
-- Beispiel:
--   ProvinceData.UpdateProvince(1, { owner = player, name = "Mein Reich" })
--------------------------------------------------------------------------------
function ProvinceData.UpdateProvince(id, updates)
	local province = provinces[id]

	if not province then
		warn("[ProvinceData] UpdateProvince: Provinz " .. id .. " nicht gefunden")
		return false
	end

	for field, value in pairs(updates) do
		province[field] = value
	end

	return true
end

--------------------------------------------------------------------------------
-- AddHexToProvince(provinceId, q, r)
-- Fügt ein Hex zur Provinz hinzu
--------------------------------------------------------------------------------
function ProvinceData.AddHexToProvince(provinceId, q, r)
	local province = provinces[provinceId]

	if not province then
		warn("[ProvinceData] AddHexToProvince: Provinz " .. provinceId .. " nicht gefunden")
		return false
	end

	table.insert(province.hexes, {q = q, r = r})
	return true
end

--------------------------------------------------------------------------------
-- GetProvinceHexCount(id) -> number
--------------------------------------------------------------------------------
function ProvinceData.GetProvinceHexCount(id)
	local province = provinces[id]
	if province then
		return #province.hexes
	end
	return 0
end

--------------------------------------------------------------------------------
-- SetProvinceOwner(id, owner)
--------------------------------------------------------------------------------
function ProvinceData.SetProvinceOwner(id, owner)
	local ok = ProvinceData.UpdateProvince(id, { owner = owner })
	if ok then
		print("[ProvinceData] Owner von Province", id, "geändert zu",
			owner and (owner.Name or tostring(owner)) or "niemand")
	end
	return ok
end

--------------------------------------------------------------------------------
-- SetProvinceName(id, name)
--------------------------------------------------------------------------------
function ProvinceData.SetProvinceName(id, name)
	return ProvinceData.UpdateProvince(id, { name = name })
end

--------------------------------------------------------------------------------
-- SetProvinceColor(id, color)
--------------------------------------------------------------------------------
function ProvinceData.SetProvinceColor(id, color)
	return ProvinceData.UpdateProvince(id, { color = color })
end

--------------------------------------------------------------------------------
-- SetProvinceCapital(id, q, r)
--------------------------------------------------------------------------------
function ProvinceData.SetProvinceCapital(id, q, r)
	return ProvinceData.UpdateProvince(id, { capital = {q = q, r = r} })
end

--------------------------------------------------------------------------------
-- GetProvincesByOwner(owner) -> table
--------------------------------------------------------------------------------
function ProvinceData.GetProvincesByOwner(owner)
	local result = {}
	for id, province in pairs(provinces) do
		if province.owner == owner then
			table.insert(result, province)
		end
	end
	return result
end

--------------------------------------------------------------------------------
-- GetUnownedProvinces() -> table
--------------------------------------------------------------------------------
function ProvinceData.GetUnownedProvinces()
	return ProvinceData.GetProvincesByOwner(nil)
end

--------------------------------------------------------------------------------
-- ClearAll()
--------------------------------------------------------------------------------
function ProvinceData.ClearAll()
	provinces = {}
	usedNames = {}
	print("[ProvinceData] Alle Provinz-Daten gelöscht.")
end

--------------------------------------------------------------------------------
-- InitializeProvinces(provinceCount, provinceMap, hexMap)
-- Initialisiert alle Provinzen basierend auf der generierten Province-Map
-- Wird vom MapGenerator aufgerufen
--------------------------------------------------------------------------------
function ProvinceData.InitializeProvinces(provinceCount, provinceMap, hexMap)
	ProvinceData.ClearAll()

	print("[ProvinceData] Initialisiere " .. provinceCount .. " Provinzen...")

	-- Provinzen erstellen
	for i = 1, provinceCount do
		ProvinceData.CreateProvince(i)
	end

	-- Hexes zu Provinzen hinzufügen
	for key, provinceId in pairs(provinceMap) do
		if provinceId and provinceId > 0 then
			local hex = hexMap[key]
			if hex then
				ProvinceData.AddHexToProvince(provinceId, hex.q, hex.r)
			end
		end
	end

	-- Statistik ausgeben
	print("[ProvinceData] === Provinz Übersicht ===")
	for i = 1, provinceCount do
		local province = provinces[i]
		if province then
			print("  " .. i .. ". " .. province.name .. ": " .. #province.hexes .. " Hexes")
		end
	end

	return provinces
end

--------------------------------------------------------------------------------
-- PrintStats()
--------------------------------------------------------------------------------
function ProvinceData.PrintStats()
	print("[ProvinceData] === Provinz Statistik ===")

	local total = 0
	for id, province in pairs(provinces) do
		local hexCount = #province.hexes
		local ownerStr = province.owner and tostring(province.owner) or "niemand"
		print("  " .. province.name .. " (ID: " .. id .. "): " .. hexCount .. " Hexes, Besitzer: " .. ownerStr)
		total = total + hexCount
	end

	print("[ProvinceData] Total: " .. ProvinceData.GetProvinceCount() .. " Provinzen, " .. total .. " Hexes")
end

return ProvinceData
