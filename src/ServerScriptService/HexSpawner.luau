--[[
    HexSpawner (ModuleScript)
    Ort: ServerScriptService > HexSpawner
    
    Kümmert sich um:
      - Template aus ServerStorage > HexTemplates klonen
      - Position setzen (über HexUtils.axialToWorld)
      - Namen setzen (z.B. "Hex_5_12")
      - Ins richtige Folder in Workspace packen
    
    Erwartete Struktur in ServerStorage:
      ServerStorage
        └── HexTemplates
            ├── Water          (Model oder Part)
            ├── Ebene1         (Model oder Part)
            ├── Ebene2         (Model oder Part)
            ├── Ebene3_Gebirge       (Model oder Part)
            └── Ebene4_Bergspitze    (Model oder Part)
    
    Jedes Hex-Template sollte ein Model sein mit PrimaryPart gesetzt.
    Die Hex-Modelle sollten die Maße 10 (Breite) x 8.66 (Höhe/Tiefe) haben.
    Hexes spawnen an ihrem UNTERSTEN Punkt auf Y = -8 (nicht am Center of Mass).
--]]

local HexSpawner = {}

local ServerStorage = game:GetService("ServerStorage")
local HexUtils = require(script.Parent:WaitForChild("HexUtils"))

-- Referenz auf die Hex-Templates (mit Timeout, damit bei fehlendem Ordner
-- kein "Infinite yield possible" entsteht).
local hexTemplatesFolder = ServerStorage:WaitForChild("HexTemplates", 10)

-- Terrain-Namen mapping (muss mit TerrainGenerator übereinstimmen)
local terrainTemplateNames = {
	[1] = "Water",
	[2] = "Ebene1",
	[3] = "Ebene2",
	[4] = "Ebene3_Gebirge",
	[5] = "Ebene4_Bergspitze",
}

-- Alle Hexes spawnen auf Y = -8 (wird in HexUtils.axialToWorld gesetzt)
-- Kein zusätzlicher Höhen-Offset pro Terrain-Typ

--------------------------------------------------------------------------------
-- Workspace Folder erstellen / abrufen
--------------------------------------------------------------------------------
local mapFolder = nil

function HexSpawner.getMapFolder()
	if mapFolder then return mapFolder end

	mapFolder = workspace:FindFirstChild("HexMap")
	if not mapFolder then
		mapFolder = Instance.new("Folder")
		mapFolder.Name = "HexMap"
		mapFolder.Parent = workspace
	end

	return mapFolder
end

function HexSpawner.getTerrainFolder(terrainType)
	local parent = HexSpawner.getMapFolder()
	local folderName = terrainTemplateNames[terrainType] or "Unknown"

	local folder = parent:FindFirstChild(folderName)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = folderName
		folder.Parent = parent
	end

	return folder
end

--------------------------------------------------------------------------------
-- getTemplate(terrainType) -> Model
-- Holt das passende Template aus ServerStorage > HexTemplates
--------------------------------------------------------------------------------
function HexSpawner.getTemplate(terrainType)
	local templateName = terrainTemplateNames[terrainType]

	if not templateName then
		warn("[HexSpawner] Unbekannter Terrain-Typ: " .. tostring(terrainType))
		return nil
	end

	if not hexTemplatesFolder then
		warn("[HexSpawner] ServerStorage > HexTemplates fehlt - es werden keine Hex-Templates erzeugt")
		return nil
	end

	local template = hexTemplatesFolder:FindFirstChild(templateName)

	if not template then
		warn("[HexSpawner] Template nicht gefunden: " .. templateName)
		warn("[HexSpawner] Stelle sicher, dass ServerStorage > HexTemplates > " .. templateName .. " existiert!")
		return nil
	end

	return template
end

--------------------------------------------------------------------------------
-- spawnHex(q, r, terrainType) -> Model/Part or nil
-- Klont ein Hex-Template, positioniert es und packt es in den richtigen Folder.
--------------------------------------------------------------------------------
function HexSpawner.spawnHex(q, r, terrainType)
	-- Template holen
	local template = HexSpawner.getTemplate(terrainType)
	if not template then return nil end

	-- Template klonen
	local hex = template:Clone()

	-- Namen setzen
	hex.Name = "Hex_" .. q .. "_" .. r

	-- Welt-Position berechnen (Basis-Y = -8, gesetzt in HexUtils)
	local worldPos = HexUtils.axialToWorld(q, r)

	-- Y-Offset berechnen: Hexes sollen an ihrem UNTERSTEN Punkt
	-- auf Y = -8 stehen, nicht an ihrem Center of Mass.
	-- Dafür verschieben wir das Zentrum um die halbe Y-Größe nach oben.
	local finalPos = worldPos

	-- Position setzen
	if hex:IsA("Model") then
		-- Für Models: PrimaryPart muss gesetzt sein!
		if hex.PrimaryPart then
			-- Halbe Höhe des PrimaryParts nach oben, damit der Boden auf Y = -8 liegt
			local halfY = hex.PrimaryPart.Size.Y / 2
			finalPos = Vector3.new(worldPos.X, worldPos.Y + halfY, worldPos.Z)
			hex:SetPrimaryPartCFrame(CFrame.new(finalPos))
		else
			warn("[HexSpawner] Model '" .. hex.Name .. "' hat kein PrimaryPart! Setze PrimaryPart im Template.")
			-- Fallback: Versuche über GetExtentsSize die Höhe zu ermitteln
			local extents = hex:GetExtentsSize()
			local halfY = extents.Y / 2
			finalPos = Vector3.new(worldPos.X, worldPos.Y + halfY, worldPos.Z)

			local firstPart = hex:FindFirstChildWhichIsA("BasePart")
			if firstPart then
				local offset = firstPart.Position
				for _, part in ipairs(hex:GetDescendants()) do
					if part:IsA("BasePart") then
						part.Position = part.Position - offset + finalPos
					end
				end
			end
		end
	elseif hex:IsA("BasePart") then
		-- Für einzelne Parts: halbe Y-Größe nach oben
		local halfY = hex.Size.Y / 2
		finalPos = Vector3.new(worldPos.X, worldPos.Y + halfY, worldPos.Z)
		hex.Position = finalPos
	end

	-- In den richtigen Folder packen
	local folder = HexSpawner.getTerrainFolder(terrainType)
	hex.Parent = folder

	return hex
end

--------------------------------------------------------------------------------
-- spawnMap(map) -> number
-- Spawnt die komplette Map aus der generierten Terrain-Tabelle.
-- Gibt die Anzahl der gespawnten Hexes zurück.
--------------------------------------------------------------------------------
function HexSpawner.spawnMap(map)
	print("[HexSpawner] Starte Map-Spawning...")

	local count = 0
	local errors = 0
	local startTime = tick()

	for key, hexData in pairs(map) do
		local success = HexSpawner.spawnHex(hexData.q, hexData.r, hexData.terrainType)

		if success then
			count = count + 1
		else
			errors = errors + 1
		end

		-- Alle 100 Hexes kurz warten um Lag zu vermeiden
		if count % 100 == 0 then
			task.wait()
		end
	end

	local elapsed = math.floor((tick() - startTime) * 100) / 100
	print("[HexSpawner] === Spawning abgeschlossen ===")
	print("[HexSpawner] Gespawnt: " .. count .. " Hexes")
	if errors > 0 then
		warn("[HexSpawner] Fehler: " .. errors .. " Hexes konnten nicht gespawnt werden")
	end
	print("[HexSpawner] Dauer: " .. elapsed .. " Sekunden")

	return count
end

--------------------------------------------------------------------------------
-- clearMap()
-- Löscht alle gespawnten Hexes aus dem Workspace.
--------------------------------------------------------------------------------
function HexSpawner.clearMap()
	local folder = workspace:FindFirstChild("HexMap")
	if folder then
		folder:Destroy()
		mapFolder = nil
		print("[HexSpawner] Map gelöscht.")
	end
end

return HexSpawner
