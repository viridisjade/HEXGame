--[[
    FogOfWarController (LocalScript)
    Ort: StarterPlayer > StarterPlayerScripts > FogOfWarController

    Client-Seite des Fog-of-War-Systems (KOMPLETTER REWRITE).

    Empfaengt FogOfWarInit (voller State beim Join) und FogOfWarUpdate
    (Deltas nach Bewegung/Bau/Kampf) und blendet die Modelle der Welt
    entsprechend dem Sicht-Zustand des Spielers.

    ZUSTAENDE (siehe FogOfWarConfig.STATE):
        unexplored  -> echtes Hex unsichtbar, stattdessen FOG-Model-Platzhalter
        explored    -> Terrain/Soil/Province = 0.5, Gebaeude/Units = 1 (unsichtbar)
        visible     -> Terrain/Soil/Gebaeude = 0, Province = 0.5, Units = 0

    FOG-MODELS:
        - Rein CLIENTSEITIG (FilteringEnabled -> keine Replikation an andere
          Clients/Server). Der Server spawnt keine FOG-Models.
        - Lokaler Ordner workspace > FogModels. Bei Spielstart werden fuer ALLE
          Hexes FOG-Models gespawnt; erkundete/sichtbare Felder entfernen sie.

    REGELN:
        - BaseParts/MeshParts/Union haben KEIN .Visible - es wird NUR
          Transparency verwendet (0 = sichtbar, 0.5 = erkundet, 1 = unsichtbar).
        - Armee-Modelle liegen in ArmyModels, bewegen sich und sind NICHT
          fest an ein Hex gebunden -> werden separat ueber Position behandelt.
        - Eigene Armeen (OwnerUserId-Attribut == LocalPlayer.UserId) sind
          IMMER sichtbar; feindliche nur, wenn ihr Hex im Sichtfeld liegt.
        - Gebaeude werden ueber den Namen (<Type>_q_r) -> Hex-Key gefunden.
        - Initialisierung versteckt ALLES; das erste FogOfWarInit (voller
          State) ist autoritativ und deckt sichtbare/erkundete Felder auf.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Net = require(ReplicatedStorage:WaitForChild("Net"))
local HexGridConfig = require(ReplicatedStorage:WaitForChild("HexGridConfig"))
local FogOfWarConfig = require(ReplicatedStorage:WaitForChild("FogOfWarConfig"))

-- Lebenszeichen: Wenn dieser Print NICHT erscheint, laedt das LocalScript
-- nicht (dann liegt es an der Rojo-Zuordnung, nicht an der Fog-Logik).
print("[FogOfWarController] geladen (LocalScript laeuft)")

--------------------------------------------------------------------------------
-- STATE + FOLDER-REFERENZEN
--------------------------------------------------------------------------------
local hexMapFolder = nil
local soilsFolder = nil
local buildingsFolder = nil
local provinceFolder = nil
local armyModelsFolder = nil

-- Autoritative Mengen. visible = was der Spieler JETZT sieht (Units sichtbar).
-- explored = was er je erkundet hat (permanent, 50% transparent).
local visibleSet = {}   -- [key] = true
local exploredSet = {}  -- [key] = true

local SPECIAL_FOLDERS = {
	Soils = true, Buildings = true, ArmyModels = true, ProvinceVisuals = true,
}

--------------------------------------------------------------------------------
-- HILFSFUNKTIONEN
--------------------------------------------------------------------------------
local function myUserId()
	local lp = Players.LocalPlayer
	return lp and lp.UserId
end

local function refreshFolders()
	hexMapFolder = workspace:FindFirstChild("HexMap")
	if not hexMapFolder then
		soilsFolder = nil; buildingsFolder = nil; provinceFolder = nil; armyModelsFolder = nil
		return
	end
	soilsFolder = hexMapFolder:FindFirstChild("Soils")
	buildingsFolder = hexMapFolder:FindFirstChild("Buildings")
	provinceFolder = hexMapFolder:FindFirstChild("ProvinceVisuals")
	armyModelsFolder = hexMapFolder:FindFirstChild("ArmyModels")
end

local function keyToCoord(key)
	local q, r = string.match(key, "^(%-?%d+)_(%-?%d+)$")
	if not q or not r then return nil, nil end
	return tonumber(q), tonumber(r)
end

-- Zustand eines Hex-Keys aus den autoritativen Mengen ableiten.
local function getState(key)
	if visibleSet[key] then
		return FogOfWarConfig.STATE.VISIBLE
	elseif exploredSet[key] then
		return FogOfWarConfig.STATE.EXPLORED
	end
	return FogOfWarConfig.STATE.UNEXPLORED
end

--------------------------------------------------------------------------------
-- TRANSPARENZ SETZEN (sicher, KEIN .Visible auf BaseParts!)
--------------------------------------------------------------------------------
local function applyTransparency(model, t)
	if not model then return end
	if model:IsA("BasePart") then
		model.Transparency = t
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") or d:IsA("Decal") or d:IsA("Texture") then
			d.Transparency = t
		end
	end
end

--------------------------------------------------------------------------------
-- FOG-MODELS (Platzhalter fuer unerforschte Hexes)
--
-- Rein CLIENTSEITIG. Der Server spawnt keine FOG-Models und weiss nichts
-- davon. Der FogModels-Ordner liegt unter workspace und ist nur auf diesem
-- Client sichtbar (FilteringEnabled -> keine Replikation an andere Clients).
--------------------------------------------------------------------------------
local fogFolder = nil

local function getFogFolder()
	if fogFolder and fogFolder.Parent then return fogFolder end
	fogFolder = workspace:FindFirstChild("FogModels")
	if not fogFolder then
		fogFolder = Instance.new("Folder")
		fogFolder.Name = "FogModels"
		fogFolder.Parent = workspace
	end
	return fogFolder
end

-- FOG-Template: bevorzugt ReplicatedStorage > HexTemplates > FOG, sonst
-- direkt ReplicatedStorage > FOG.
local function getFogTemplate()
	local hexTemplates = ReplicatedStorage:FindFirstChild("HexTemplates")
	local t = hexTemplates and hexTemplates:FindFirstChild("FOG")
	if not t then
		t = ReplicatedStorage:FindFirstChild("FOG")
	end
	return t
end

-- SpawnFogModel(q, r): klont das FOG-Model, positioniert es auf dem Hex
-- (Boden auf SPAWN_Y, gleiche Hoehe wie echte Hexes) und legt es in den
-- lokalen FogModels-Ordner.
local function SpawnFogModel(q, r)
	local template = getFogTemplate()
	if not template then return end

	local folder = getFogFolder()
	local name = "Fog_" .. q .. "_" .. r
	if folder:FindFirstChild(name) then return end

	local fog = template:Clone()
	fog.Name = name

	local worldPos = HexGridConfig.axialToWorld(q, r)

	if fog:IsA("Model") then
		local bboxCf, bboxSize = fog:GetBoundingBox()
		local pivot = fog:GetPivot()
		local pivotToBottom = pivot.Position.Y - (bboxCf.Position.Y - bboxSize.Y / 2)
		local targetPivotY = worldPos.Y + pivotToBottom
		local rotation = pivot - pivot.Position
		fog:PivotTo(CFrame.new(worldPos.X, targetPivotY, worldPos.Z) * rotation)
	elseif fog:IsA("BasePart") then
		fog.Position = Vector3.new(worldPos.X, worldPos.Y + fog.Size.Y / 2, worldPos.Z)
	end

	fog.Parent = folder
end

-- RemoveFogModel(q, r): loescht das FOG-Model (falls vorhanden).
local function RemoveFogModel(q, r)
	local folder = getFogFolder()
	local fog = folder:FindFirstChild("Fog_" .. q .. "_" .. r)
	if fog then fog:Destroy() end
end

-- forEachHex(callback): ruft callback(q, r) fuer jedes Hex-Model auf der Karte
-- auf (durchsucht die Terrain-/Hex-Folder im HexMap-Ordner).
local function forEachHex(callback)
	if not hexMapFolder then return end
	for _, child in ipairs(hexMapFolder:GetChildren()) do
		if child:IsA("Folder") and not SPECIAL_FOLDERS[child.Name] then
			for _, obj in ipairs(child:GetChildren()) do
				local q, r = string.match(obj.Name, "^Hex_(%-?%d+)_(%-?%d+)$")
				if q and r then callback(tonumber(q), tonumber(r)) end
			end
		end
	end
end

-- spawnAllFog(): klare alte FOG-Models und lege fuer JEDES Hex ein neues an.
local function spawnAllFog()
	refreshFolders()
	local folder = getFogFolder()
	for _, child in ipairs(folder:GetChildren()) do
		child:Destroy()
	end
	forEachHex(function(q, r) SpawnFogModel(q, r) end)
end

--------------------------------------------------------------------------------
-- MODELL-LOOKUP (pro Hex)
--------------------------------------------------------------------------------
local function findTerrainModel(q, r)
	if not hexMapFolder then return nil end
	local name = "Hex_" .. q .. "_" .. r
	for _, child in ipairs(hexMapFolder:GetChildren()) do
		if child:IsA("Folder") and not SPECIAL_FOLDERS[child.Name] then
			local hex = child:FindFirstChild(name)
			if hex then return hex end
		end
	end
	return nil
end

local function findSoilModel(q, r)
	if not soilsFolder then return nil end
	local prefix = "Soil_" .. q .. "_" .. r .. "_"
	for _, subFolder in ipairs(soilsFolder:GetChildren()) do
		for _, child in ipairs(subFolder:GetChildren()) do
			if child.Name:sub(1, #prefix) == prefix then
				return child
			end
		end
	end
	return nil
end

local function findBuilding(q, r)
	if not buildingsFolder then return nil end
	local suffix = "_" .. q .. "_" .. r
	for _, child in ipairs(buildingsFolder:GetChildren()) do
		if child.Name:sub(-#suffix) == suffix and not child.Name:match("^Ghost_") then
			return child
		end
	end
	return nil
end

local function findProvinceModel(q, r)
	if not provinceFolder then return nil end
	local name = "Hex_" .. q .. "_" .. r
	-- Provinz-Hexes liegen gruppiert unter Province_<id> Modellen.
	for _, provinceModel in ipairs(provinceFolder:GetChildren()) do
		if provinceModel:IsA("Model") or provinceModel:IsA("Folder") then
			local hex = provinceModel:FindFirstChild(name)
			if hex then return hex end
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- HEX-STATE ANWENDEN
--------------------------------------------------------------------------------
local function setHexState(key, state)
	local q, r = keyToCoord(key)
	if not q then return end

	-- t = Terrain/Soil-Transparenz. buildingT = Gebaeude-Transparenz
	-- (im erkundeten Zustand IMMER unsichtbar, unabhaengig von t -
	-- Sichtlinien-Blockaden decken nur Terrain/Soil auf, keine Gebaeude).
	local t = 1            -- unexplored: alles unsichtbar
	local buildingT = 1
	local provinceT = 1
	if state == FogOfWarConfig.STATE.VISIBLE then
		t = 0              -- sichtbar: voll
		buildingT = 0
		provinceT = 0.5    -- ProvinceHex bleibt halb transparent
		RemoveFogModel(q, r)   -- FOG-Platzhalter entfernen, echtes Hex sichtbar
	elseif state == FogOfWarConfig.STATE.EXPLORED then
		t = 0.5            -- erkundet: Terrain/Soil im Geister-Look sichtbar
		buildingT = 1      -- Gebaeude bleiben im erkundeten Zustand unsichtbar
		provinceT = 0.5
		RemoveFogModel(q, r)   -- FOG entfernen, echtes Hex 50% sichtbar
	else
		-- unexplored: echtes Hex unsichtbar, stattdessen FOG-Platzhalter.
		-- SpawnFogModel ist idempotent (ueberspringt bereits vorhandene Models).
		SpawnFogModel(q, r)
	end

	applyTransparency(findTerrainModel(q, r), t)
	applyTransparency(findSoilModel(q, r), t)
	applyTransparency(findBuilding(q, r), buildingT)
	applyTransparency(findProvinceModel(q, r), provinceT)
end

--------------------------------------------------------------------------------
-- ARMEEN AKTUALISIEREN (separiert - sie bewegen sich!)
--------------------------------------------------------------------------------
-- Eigene Armeen (OwnerUserId) IMMER sichtbar; feindliche nur wenn ihr Hex im
-- visible-Set liegt. Erkundete/unerforschte Gebiete zeigen KEINE feindlichen Units.
local function updateArmyVisibility()
	refreshFolders()
	if not armyModelsFolder then return end

	local uid = myUserId()
	local visibleCount = 0
	local hiddenCount = 0

	for _, model in ipairs(armyModelsFolder:GetChildren()) do
		if model:IsA("Model") or model:IsA("BasePart") then
			local pos
			if model:IsA("BasePart") then
				pos = model.Position
			elseif model.PrimaryPart then
				pos = model.PrimaryPart.Position
			else
				local ok, cf = pcall(function() return model:GetPivot() end)
				if ok and cf then pos = cf.Position end
			end

			if pos then
				local aq, ar = HexGridConfig.worldToAxial(pos)
				local key = aq .. "_" .. ar
				local ownerId = model:GetAttribute("OwnerUserId")

				local t = 1
				if ownerId and uid and ownerId == uid then
					t = 0          -- eigene Armee: IMMER sichtbar
				elseif visibleSet[key] then
					t = 0          -- feindliche Armee im Sichtfeld
				end

				applyTransparency(model, t)
				if t == 0 then visibleCount = visibleCount + 1 else hiddenCount = hiddenCount + 1 end
			end
		end
	end

	print(("[Fog] Armeen: %d sichtbar, %d unsichtbar"):format(visibleCount, hiddenCount))
end

--------------------------------------------------------------------------------
-- GEBÄUDE NACHBEWERTEN (alle, ueber Hex-Key)
--------------------------------------------------------------------------------
local function buildingKeyFromName(name)
	if not name then return nil end
	if name:match("^Ghost_") then return nil end
	local q, r = string.match(name, "_(%-?%d+)_(%-?%d+)$")
	if q and r then return q .. "_" .. r end
	return nil
end

local function refreshBuildings()
	refreshFolders()
	if not buildingsFolder then return end
	for _, building in ipairs(buildingsFolder:GetChildren()) do
		local key = buildingKeyFromName(building.Name)
		if key then
			setHexState(key, getState(key))
		end
	end
end

--------------------------------------------------------------------------------
-- ALLES UNSICHTBAR (Initialisierung)
--------------------------------------------------------------------------------
local function hideEverything()
	refreshFolders()
	if not hexMapFolder then return end
	for _, child in ipairs(hexMapFolder:GetChildren()) do
		applyTransparency(child, 1)
	end
end

--------------------------------------------------------------------------------
-- VOLLER STATE ANWENDEN (beim Init - autoritativ)
--------------------------------------------------------------------------------
local function applyFullVision(data)
	refreshFolders()

	-- Mengen neu aufbauen.
	visibleSet = {}
	exploredSet = {}
	for _, key in ipairs(data.visible or {}) do visibleSet[key] = true end
	for _, key in ipairs(data.explored or {}) do exploredSet[key] = true end

	-- Erst ALLES verstecken, dann sichtbare/erkundete Felder auflisten.
	hideEverything()
	for _, key in ipairs(data.explored or {}) do setHexState(key, FogOfWarConfig.STATE.EXPLORED) end
	for _, key in ipairs(data.visible or {}) do setHexState(key, FogOfWarConfig.STATE.VISIBLE) end

	updateArmyVisibility()
	refreshBuildings()

	print(("[Fog] Init: %d sichtbar, %d erkundet")
		:format(#(data.visible or {}), #(data.explored or {})))
end

--------------------------------------------------------------------------------
-- DELTA ANWENDEN
--------------------------------------------------------------------------------
local function applyVisionDelta(data)
	refreshFolders()

	-- Erst erkundet, dann sichtbar - damit ein Feld, das beides neu ist,
	-- korrekt auf "visible" endet.
	for _, key in ipairs(data.newlyExplored or {}) do
		exploredSet[key] = true
		setHexState(key, FogOfWarConfig.STATE.EXPLORED)
	end
	for _, key in ipairs(data.newlyVisible or {}) do
		visibleSet[key] = true
		exploredSet[key] = true
		setHexState(key, FogOfWarConfig.STATE.VISIBLE)
	end
	for _, key in ipairs(data.newlyHidden or {}) do
		visibleSet[key] = nil
		setHexState(key, FogOfWarConfig.STATE.EXPLORED)
	end

	updateArmyVisibility()
	refreshBuildings()

	print(("[Fog] Update: %d neu sichtbar, %d versteckt")
		:format(#(data.newlyVisible or {}), #(data.newlyHidden or {})))
end

--------------------------------------------------------------------------------
-- WATCHER (neu auftauchende Modelle sofort behandeln)
--------------------------------------------------------------------------------
local function connectBuildingsWatcher(folder)
	if not folder then return end
	buildingsFolder = folder
	folder.ChildAdded:Connect(function(child)
		if not child then return end
		local key = buildingKeyFromName(child.Name)
		if key then setHexState(key, getState(key)) end
	end)
	pcall(refreshBuildings)
end

local function connectArmyWatcher(folder)
	if not folder then return end
	armyModelsFolder = folder
	folder.ChildAdded:Connect(function(child)
		if child then pcall(updateArmyVisibility) end
	end)
	pcall(updateArmyVisibility)
end

-- Neu eintreffende Hex-Modelle (asynchrone Replikation) abdecken: FOG-Model
-- spawnen bzw. echten Hex sichtbar/erkundet setzen.
local function connectHexWatcher(folder)
	if not folder then return end
	folder.ChildAdded:Connect(function(child)
		if not child then return end
		local q, r = string.match(child.Name, "^Hex_(%-?%d+)_(%-?%d+)$")
		if q and r then
			setHexState(q .. "_" .. r, getState(q .. "_" .. r))
		end
	end)
end

local function setupHexMapWatchers()
	refreshFolders()
	if not hexMapFolder then return end

	connectBuildingsWatcher(hexMapFolder:FindFirstChild("Buildings"))
	connectArmyWatcher(hexMapFolder:FindFirstChild("ArmyModels"))

	-- Terrain-/Hex-Folder: neu eintreffende Hex-Modelle abdecken.
	for _, child in ipairs(hexMapFolder:GetChildren()) do
		if child:IsA("Folder") and not SPECIAL_FOLDERS[child.Name] then
			connectHexWatcher(child)
		end
	end

	-- Falls die Folder erst nach dem Map-Spawn (lazy) angelegt werden.
	hexMapFolder.ChildAdded:Connect(function(child)
		if child.Name == "Buildings" and child:IsA("Folder") then
			connectBuildingsWatcher(child)
		elseif child.Name == "ArmyModels" and child:IsA("Folder") then
			connectArmyWatcher(child)
		elseif child:IsA("Folder") and not SPECIAL_FOLDERS[child.Name] then
			connectHexWatcher(child)
		end
	end)
end

--------------------------------------------------------------------------------
-- INITIALISIERUNG + RACE-HANDLING
--------------------------------------------------------------------------------
-- Rojo/Replikation sind asynchron: Das erste FogOfWarInit kann VOR oder NACH
-- der HexMap-Erstellung eintreffen. Deshalb merken wir das Init, falls die Map
-- noch nicht da ist, und wenden es an, sobald sie bereitsteht. hideEverything()
-- laeuft nur EINMAL bei Map-Bereitschaft - nie nach einem Init (sonst wuerde
-- es die aufgedeckten Felder erneut verstecken).
local mapReady = false
local pendingInit = nil

local function finishInitIfReady()
	if mapReady and pendingInit then
		local data = pendingInit
		pendingInit = nil
		applyFullVision(data)
	end
end

task.spawn(function()
	while not workspace:FindFirstChild("HexMap") do
		task.wait(0.5)
	end
	hideEverything()
	spawnAllFog()
	setupHexMapWatchers()
	mapReady = true
	finishInitIfReady()
	print("[Fog] Initialisierung: Alles unsichtbar, FOG-Models gespawnt, HexMap bereit.")
end)

--------------------------------------------------------------------------------
-- REMOTE-HANDLER
--------------------------------------------------------------------------------
Net.On("FogOfWarInit", function(data)
	if not data then return end
	if not mapReady then
		pendingInit = data
		return
	end
	applyFullVision(data)
end)

Net.On("FogOfWarUpdate", function(data)
	if not data then return end
	if not mapReady then return end
	task.spawn(function() applyVisionDelta(data) end)
end)

-- HexMap neu aufgebaut (z.B. /regen): Zustand zuruecksetzen und neu verstecken.
workspace.ChildAdded:Connect(function(child)
	if child.Name == "HexMap" then
		task.wait(1)
		visibleSet = {}
		exploredSet = {}
		hideEverything()
		spawnAllFog()
		setupHexMapWatchers()
		print("[Fog] HexMap neu erstellt - alles wieder versteckt, FOG-Models neu gespawnt.")
	end
end)

--------------------------------------------------------------------------------
-- PERIODISCHER CHECK (Fallback fuer Bewegung/neue Modelle)
--------------------------------------------------------------------------------
task.spawn(function()
	while true do
		task.wait(0.5)
		if mapReady and (armyModelsFolder or buildingsFolder) then
			pcall(updateArmyVisibility)
			pcall(refreshBuildings)
		end
	end
end)
