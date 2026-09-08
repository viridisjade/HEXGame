--[[
    FogOfWarController (LocalScript)
    Ort: StarterPlayer > StarterPlayerScripts > FogOfWarController

    Client-Seite des Fog-of-War-Systems (KOMPLETTER REWRITE).

    Empfaengt FogOfWarInit (voller State beim Join) und FogOfWarUpdate
    (Deltas nach Bewegung/Bau/Kampf) und blendet die Modelle der Welt
    entsprechend dem Sicht-Zustand des Spielers.

    ZUSTAENDE (siehe FogOfWarConfig.STATE):
        unexplored  -> alles Transparency = 1 (unsichtbar)
        explored    -> Terrain/Soil/Gebaeude/Province = 0.5, KEINE Units
        visible     -> Terrain/Soil/Gebaeude = 0, Province = 0.5, Units = 0

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

	local t = 1            -- unexplored: alles unsichtbar
	local provinceT = 1
	if state == FogOfWarConfig.STATE.VISIBLE then
		t = 0              -- sichtbar: voll
		provinceT = 0.5    -- ProvinceHex bleibt halb transparent
	elseif state == FogOfWarConfig.STATE.EXPLORED then
		t = 0.5            -- erkundet: Geister-Look
		provinceT = 0.5
	end

	applyTransparency(findTerrainModel(q, r), t)
	applyTransparency(findSoilModel(q, r), t)
	applyTransparency(findBuilding(q, r), t)
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

local function setupHexMapWatchers()
	refreshFolders()
	if not hexMapFolder then return end

	connectBuildingsWatcher(hexMapFolder:FindFirstChild("Buildings"))
	connectArmyWatcher(hexMapFolder:FindFirstChild("ArmyModels"))

	-- Falls die Folder erst nach dem Map-Spawn (lazy) angelegt werden.
	hexMapFolder.ChildAdded:Connect(function(child)
		if child.Name == "Buildings" and child:IsA("Folder") then
			connectBuildingsWatcher(child)
		elseif child.Name == "ArmyModels" and child:IsA("Folder") then
			connectArmyWatcher(child)
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
	setupHexMapWatchers()
	mapReady = true
	finishInitIfReady()
	print("[Fog] Initialisierung: Alles unsichtbar, HexMap bereit.")
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
		setupHexMapWatchers()
		print("[Fog] HexMap neu erstellt - alles wieder versteckt.")
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
