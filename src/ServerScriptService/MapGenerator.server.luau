--[[
    MapGenerator (Script)
    Ort: ServerScriptService > MapGenerator
    
    Hauptscript das die Map-Generierung startet.
    
    Ablauf:
      1. Module laden
      2. Alte Map löschen
      3. Terrain-Map generieren
      4. Post-Processing (Bergspitzen validieren)
      5. Soil-Map generieren
      6. Provinzen generieren (Flood Fill)
      7. Hex-Daten + Soil + Provinz in HexData speichern
      8. Hex-Modelle spawnen
      9. Soil-Modelle spawnen
    
    Benötigte Struktur:
    
    ServerScriptService
      ├── MapGenerator          (dieses Script)
      ├── MapConfig             (ModuleScript)
      ├── HexUtils              (ModuleScript)
      ├── TerrainGenerator      (ModuleScript)
      ├── HexSpawner            (ModuleScript)
      ├── SoilGenerator         (ModuleScript)
      ├── SoilSpawner           (ModuleScript)
      ├── ProvinceGenerator     (ModuleScript)
      ├── ProvinceVisualizer    (ModuleScript)
      ├── ArmySystem            (ModuleScript)
      ├── HexData               (ModuleScript)
      ├── ProvinceData          (ModuleScript)
      ├── UnitData              (ModuleScript)
      ├── ArmyData              (ModuleScript)
      └── DataRemoteHandler     (ModuleScript)
    
    ReplicatedStorage
      ├── UnitConfig            (ModuleScript – bleibt hier für Client-UI)
      └── DataAccess            (ModuleScript – Client liest Daten über Remotes)
    
    ServerStorage
      ├── HexTemplates
      └── SoilTemplates
--]]

print("========================================")
print("   HEX MAP GENERATOR")
print("   Starte Welt-Generierung...")
print("========================================")

-- Module laden (alle im ServerScriptService)
local HexUtils = require(script.Parent:WaitForChild("HexUtils"))
local MapConfig = require(script.Parent:WaitForChild("MapConfig"))
local TerrainGenerator = require(script.Parent:WaitForChild("TerrainGenerator"))
local HexSpawner = require(script.Parent:WaitForChild("HexSpawner"))
local SoilGenerator = require(script.Parent:WaitForChild("SoilGenerator"))
local SoilSpawner = require(script.Parent:WaitForChild("SoilSpawner"))
local ProvinceGenerator = require(script.Parent:WaitForChild("ProvinceGenerator"))
local ProvinceVisualizer = require(script.Parent:WaitForChild("ProvinceVisualizer"))
local HexData = require(script.Parent:WaitForChild("HexData"))
local ProvinceData = require(script.Parent:WaitForChild("ProvinceData"))
local UnitData = require(script.Parent:WaitForChild("UnitData"))
local ArmyData = require(script.Parent:WaitForChild("ArmyData"))

-- Warte kurz bis alles geladen ist
task.wait(1)

-- Hinweis: Die Lese-Remotes werden vom DataQueryBinder verbunden.
-- (früher DataRemoteHandler.Init() - entfällt seit v89)

--------------------------------------------------------------------------------
-- KONFIGURATION (Optional: Überschreibe Defaults)
--------------------------------------------------------------------------------
-- MapConfig.MapSize.WIDTH = 80
-- MapConfig.MapSize.HEIGHT = 60
-- MapConfig.LandWater.WATER_AMOUNT = 0.40

-- Provinzen konfigurieren
-- MapConfig.Provinces.LAND_PROVINCE_COUNT = 16
-- MapConfig.Provinces.MAX_WATER_RATIO = 0.22
-- MapConfig.Provinces.LAND_WATER_RINGS = 2

--------------------------------------------------------------------------------
-- SCHRITT 1: Alte Map und Daten löschen
--------------------------------------------------------------------------------
print("")
print("[MapGenerator] Schritt 1: Alte Map wird gelöscht...")
HexSpawner.clearMap()
SoilSpawner.clearSoils()
ProvinceVisualizer.clearVisualization()
HexData.ClearAll()
ProvinceData.ClearAll()

--------------------------------------------------------------------------------
-- SCHRITT 2: Terrain-Map generieren
--------------------------------------------------------------------------------
print("")
print("[MapGenerator] Schritt 2: Terrain wird generiert...")
local startTime = tick()

local map = TerrainGenerator.generateMap()

local genTime = math.floor((tick() - startTime) * 1000)
print("[MapGenerator] Terrain-Generierung abgeschlossen in " .. genTime .. "ms")

--------------------------------------------------------------------------------
-- SCHRITT 3: Post-Processing (Terrain)
--------------------------------------------------------------------------------
print("")
print("[MapGenerator] Schritt 3: Post-Processing...")
map = TerrainGenerator.postProcessMap(map)

--------------------------------------------------------------------------------
-- SCHRITT 4: Soil-Map generieren
--------------------------------------------------------------------------------
print("")
print("[MapGenerator] Schritt 4: Soil wird generiert...")
local soilStartTime = tick()

local soilMap = SoilGenerator.generateSoilMap(map)

local soilGenTime = math.floor((tick() - soilStartTime) * 1000)
print("[MapGenerator] Soil-Generierung abgeschlossen in " .. soilGenTime .. "ms")

--------------------------------------------------------------------------------
-- SCHRITT 5: Provinzen generieren (Flood Fill)
--------------------------------------------------------------------------------
print("")
print("[MapGenerator] Schritt 5: Provinzen werden generiert...")
local provinceStartTime = tick()

local provinceMap = ProvinceGenerator.generateProvinces(map)

local provinceGenTime = math.floor((tick() - provinceStartTime) * 1000)
print("[MapGenerator] Provinz-Generierung abgeschlossen in " .. provinceGenTime .. "ms")

--------------------------------------------------------------------------------
-- SCHRITT 5b: ProvinceData initialisieren
--------------------------------------------------------------------------------
print("")
print("[MapGenerator] Schritt 5b: ProvinceData wird initialisiert...")
ProvinceData.InitializeProvinces(ProvinceGenerator.getProvinceCount(), provinceMap, map)

--------------------------------------------------------------------------------
-- SCHRITT 6: Hex-Daten + Soil + Provinz in HexData speichern
--------------------------------------------------------------------------------
print("")
print("[MapGenerator] Schritt 6: Hex-Daten werden gespeichert...")

for key, hexInfo in pairs(map) do
	local soilType = soilMap[key] or "Unknown"
	local province = provinceMap[key] or 0

	HexData.SetHex(hexInfo.q, hexInfo.r, {
		q = hexInfo.q,
		r = hexInfo.r,
		terrain = hexInfo.terrainName,
		soil = soilType,
		province = province,
		owner = nil,
		army = nil,
		building = nil,
	})
end

print("[MapGenerator] " .. HexData.GetHexCount() .. " Hexes in HexData gespeichert")
HexData.PrintStats()

--------------------------------------------------------------------------------
-- SCHRITT 7: Hex-Modelle spawnen
--------------------------------------------------------------------------------
print("")
print("[MapGenerator] Schritt 7: Hexes werden gespawnt...")
local totalHexes = HexSpawner.spawnMap(map)

--------------------------------------------------------------------------------
-- SCHRITT 8: Soil-Modelle spawnen
--------------------------------------------------------------------------------
print("")
print("[MapGenerator] Schritt 8: Soils werden gespawnt...")
local totalSoils = SoilSpawner.spawnAllSoils(map, soilMap)

--------------------------------------------------------------------------------
-- SCHRITT 9: Provinz-Visualisierung spawnen
--------------------------------------------------------------------------------
print("")
print("[MapGenerator] Schritt 9: Provinz-Visualisierung wird gespawnt...")
local totalProvinceHexes = ProvinceVisualizer.visualizeProvinces(map, provinceMap, ProvinceGenerator.getProvinceCount())

--------------------------------------------------------------------------------
-- SCHRITT 10: Fog of War - ALLE Modelle verstecken (auch Soils/Provinzen)
--------------------------------------------------------------------------------
-- HexSpawner.spawnMap() versteckt nur die TERRAIN-Hexes (Schritt 7). Soils
-- (Schritt 8) und Provinzen (Schritt 9) werden erst NACH diesem Aufruf erzeugt
-- und wären sonst standardmaessig sichtbar. Deshalb hier alles nochmal unsichtbar
-- schalten - der Client blendet erkundete/sichtbare Felder pro Spieler wieder ein.
print("")
print("[MapGenerator] Schritt 10: Fog of War - alle Modelle unsichtbar schalten...")
HexSpawner.hideAllHexes()

--------------------------------------------------------------------------------
-- FERTIG
--------------------------------------------------------------------------------
local totalTime = math.floor((tick() - startTime) * 100) / 100
print("")
print("========================================")
print("   MAP GENERIERUNG ABGESCHLOSSEN!")
print("   " .. totalHexes .. " Hexes gespawnt")
print("   " .. totalSoils .. " Soils gespawnt")
print("   " .. totalProvinceHexes .. " Provinz-Hexes gespawnt")
print("   " .. ProvinceGenerator.getProvinceCount() .. " Provinzen erstellt")
print("   " .. HexData.GetHexCount() .. " Hexes in Daten")
print("   Gesamtdauer: " .. totalTime .. " Sekunden")
print("========================================")

--------------------------------------------------------------------------------
-- OPTIONAL: Regeneration per Chat-Command (für Tests)
--------------------------------------------------------------------------------
--[[
game.Players.PlayerAdded:Connect(function(player)
    player.Chatted:Connect(function(message)
        if message:lower() == "/regen" then
            print("[MapGenerator] Regeneration angefordert von " .. player.Name)
            
            HexSpawner.clearMap()
            SoilSpawner.clearSoils()
            ProvinceVisualizer.clearVisualization()
            HexData.ClearAll()
            ProvinceData.ClearAll()
            
            local newMap = TerrainGenerator.generateMap()
            newMap = TerrainGenerator.postProcessMap(newMap)
            local newSoilMap = SoilGenerator.generateSoilMap(newMap)
            local newProvinceMap = ProvinceGenerator.generateProvinces(newMap)
            
            ProvinceData.InitializeProvinces(ProvinceGenerator.getProvinceCount(), newProvinceMap, newMap)
            
            for key, hexInfo in pairs(newMap) do
                HexData.SetHex(hexInfo.q, hexInfo.r, {
                    q = hexInfo.q,
                    r = hexInfo.r,
                    terrain = hexInfo.terrainName,
                    soil = newSoilMap[key] or "Unknown",
                    province = newProvinceMap[key] or 0,
                    owner = nil,
                    army = nil,
                    building = nil,
                })
            end
            
            HexSpawner.spawnMap(newMap)
            SoilSpawner.spawnAllSoils(newMap, newSoilMap)
            ProvinceVisualizer.visualizeProvinces(newMap, newProvinceMap, ProvinceGenerator.getProvinceCount())
            
            print("[MapGenerator] Regeneration abgeschlossen!")
        end
    end)
end)
--]]