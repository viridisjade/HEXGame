--[[
    FogOfWarController (LocalScript)
    Ort: StarterPlayer > StarterPlayerScripts > FogOfWarController

    Client-Seite des Fog-of-War-Systems. Empfängt FogOfWarInit (voller State
    beim Join) und FogOfWarUpdate (Deltas nach Bewegung/Bau/Kampf) und wendet
    die Sicht-Zustände auf die Hex-Modelle im Workspace an.

    ZUSTÄNDE (siehe FogOfWarConfig.STATE):
        unexplored - alles unsichtbar
        explored   - Terrain/Gebäude 50% transparent, KEINE Units
        visible    - alles voll, Units sichtbar

    Modell-Lookup (workspace/HexMap):
        Hex-Modell   : <TerrainFolder>/Hex_q_r
        Soil-Modell  : Soils/<soilFolder>/Soil_q_r_<index>
        Gebäude      : Buildings/<Type>_q_r  (Ghost_ ausgenommen)
        Province     : ProvinceVisuals/Hex_q_r
        Armee-Modell : ArmyModels/Army_<id>
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Net"))
local HexGridConfig = require(ReplicatedStorage:WaitForChild("HexGridConfig"))
local FogOfWarConfig = require(ReplicatedStorage:WaitForChild("FogOfWarConfig"))

--------------------------------------------------------------------------------
-- STATE + CACHES
--------------------------------------------------------------------------------
local hexMapFolder = nil
local soilsFolder = nil
local buildingsFolder = nil
local provinceFolder = nil
local armyModelsFolder = nil

-- Cache des zuletzt angewandten Zustands pro Hex-Key. Wird von setHexState
-- gepflegt und von refreshArmies() benutzt, um Armee-Modelle unabhaengig von
-- einem Hex-Zustandswechsel korrekt zu blenden (z.B. wenn ein gegnerisches
-- Heer sich in das Sichtfeld bewegt oder dieses verlässt).
local stateByKey = {}

local SPECIAL_FOLDERS = {
	Soils = true, Buildings = true, ArmyModels = true, ProvinceVisuals = true,
}

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

--------------------------------------------------------------------------------
-- SET MODEL VISIBILITY
--------------------------------------------------------------------------------
local function setModelVisibility(model, visible, transparency)
	if not model then return end
	local desiredTransparency = transparency or 0

	-- BasePart-Descendants.
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Visible = visible
			part.Transparency = desiredTransparency
		elseif part:IsA("Decal") or part:IsA("Texture") then
			part.Transparency = desiredTransparency
		end
	end

	-- Falls das Modell selbst ein BasePart ist.
	if model:IsA("BasePart") then
		model.Visible = visible
		model.Transparency = desiredTransparency
	end
end

--------------------------------------------------------------------------------
-- MODELL-LOOKUP
--------------------------------------------------------------------------------
local function findHexModel(q, r)
	if not hexMapFolder then return nil end
	local name = "Hex_" .. q .. "_" .. r
	-- Hex-Modelle liegen in Terrain-Ordnern (Nicht-Spezial-Folders).
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
	return provinceFolder:FindFirstChild("Hex_" .. q .. "_" .. r)
end

local function findArmiesOnHex(q, r)
	if not armyModelsFolder then return {} end
	local result = {}
	local targetWorld = HexGridConfig.axialToWorld(q, r)
	for _, model in ipairs(armyModelsFolder:GetChildren()) do
		if model:IsA("Model") or model:IsA("BasePart") then
			local pos = model:IsA("Model") and model.PrimaryPart and model.PrimaryPart.Position
				or (model:IsA("BasePart") and model.Position or nil)
			if pos then
				local aq, ar = HexGridConfig.worldToAxial(pos)
				if aq == q and ar == r then
					table.insert(result, model)
				end
			end
		end
	end
	return result
end

--------------------------------------------------------------------------------
-- SET HEX STATE (Kernanwendung auf ein einzelnes Feld)
--------------------------------------------------------------------------------
-- state: "visible" | "explored" | (optional "unexplored", versteckt alles)
local function setHexState(key, state)
	local q, r = string.match(key, "^(%-?%d+)_(%-?%d+)$")
	if not q or not r then return end
	q = tonumber(q); r = tonumber(r)

	-- Zustand fuer spaetere Armee-Bewertung merken.
	stateByKey[key] = state

	local hexModel = findHexModel(q, r)
	local soilModel = findSoilModel(q, r)
	local building = findBuilding(q, r)
	local provinceModel = findProvinceModel(q, r)
	local armies = findArmiesOnHex(q, r)

	if state == "visible" then
		setModelVisibility(hexModel, true, FogOfWarConfig.VISIBLE_TRANSPARENCY)
		setModelVisibility(soilModel, true, FogOfWarConfig.VISIBLE_TRANSPARENCY)
		setModelVisibility(building, true, FogOfWarConfig.VISIBLE_TRANSPARENCY)
		setModelVisibility(provinceModel, true, FogOfWarConfig.VISIBLE_TRANSPARENCY)
		-- Units sichtbar.
		for _, army in ipairs(armies) do
			setModelVisibility(army, true, FogOfWarConfig.VISIBLE_TRANSPARENCY)
		end

	elseif state == "explored" then
		setModelVisibility(hexModel, true, FogOfWarConfig.EXPLORED_TRANSPARENCY)
		setModelVisibility(soilModel, true, FogOfWarConfig.EXPLORED_TRANSPARENCY)
		setModelVisibility(building, true, FogOfWarConfig.EXPLORED_TRANSPARENCY)
		setModelVisibility(provinceModel, true, FogOfWarConfig.EXPLORED_TRANSPARENCY)
		-- Units UNSICHTBAR.
		for _, army in ipairs(armies) do
			setModelVisibility(army, false, 1)
		end

	elseif state == "unexplored" then
		setModelVisibility(hexModel, false, 1)
		setModelVisibility(soilModel, false, 1)
		setModelVisibility(building, false, 1)
		setModelVisibility(provinceModel, false, 1)
		for _, army in ipairs(armies) do
			setModelVisibility(army, false, 1)
		end
	end
end

--------------------------------------------------------------------------------
-- ARMY-REFRESH (Position gegen Hex-Zustand)
--------------------------------------------------------------------------------
-- Armee-Modelle tragen keinen Hex-Key im Namen und bewegen sich unabhaengig.
-- Deshalb wird hier die aktuelle Position jedes Armee-Modells in Axial-Koordinaten
-- umgerechnet und mit dem gecachten Hex-Zustand abgeglichen. So erscheinen und
-- verschwinden Heere sofort, wenn sie das (eigene) Sichtfeld betreten/verlassen -
-- auch ohne dass sich der Hex-Zustand dabei aendert.
local function applyArmyVisibility(model, state)
	if state == FogOfWarConfig.STATE.VISIBLE then
		setModelVisibility(model, true, FogOfWarConfig.VISIBLE_TRANSPARENCY)
	else
		setModelVisibility(model, false, 1)
	end
end

local function refreshArmies()
	if not armyModelsFolder then
		refreshFolders()
		if not armyModelsFolder then return end
	end
	-- Falls die HexMap noch fehlt, abbrechen.
	if not hexMapFolder then return end

	for _, model in ipairs(armyModelsFolder:GetChildren()) do
		if model:IsA("Model") or model:IsA("BasePart") then
			local pos = model:IsA("Model") and model.PrimaryPart and model.PrimaryPart.Position
				or (model:IsA("BasePart") and model.Position or nil)
			if pos then
				local aq, ar = HexGridConfig.worldToAxial(pos)
				local key = aq .. "_" .. ar
				local state = stateByKey[key] or FogOfWarConfig.STATE.UNEXPLORED
				applyArmyVisibility(model, state)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- PUBLIC NAME / READY (vorab deklariert, damit applyFullVision darauf zugreifen kann)
--------------------------------------------------------------------------------
local FogOfWarController = { Ready = false }
function FogOfWarController.MarkReady()
	FogOfWarController.Ready = true
	print("[FogOfWarController] Bereit.")
end

--------------------------------------------------------------------------------
-- HIDE ALLES (Initialzustand beim Start - "nichts generiert")
--------------------------------------------------------------------------------
local function hideEverything()
	refreshFolders()
	if not hexMapFolder then return end
	-- Jedes direkte Kind (Terrain-Folder, Soils, Buildings, ProvinceVisuals,
	-- ArmyModels) komplett unsichtbar machen.
	for _, child in ipairs(hexMapFolder:GetChildren()) do
		setModelVisibility(child, false, 1)
	end
end

--------------------------------------------------------------------------------
-- DELTA ANWENDEN
--------------------------------------------------------------------------------
local function applyVisionDelta(data)
	if not data then return end
	refreshFolders()

	-- Erst explored (halbtransparent, keine Units), dann visible (voll) -
	-- damit ein Feld, das beides neu ist, korrekt auf "visible" endet.
	for _, key in ipairs(data.newlyExplored or {}) do
		setHexState(key, FogOfWarConfig.STATE.EXPLORED)
	end
	for _, key in ipairs(data.newlyVisible or {}) do
		setHexState(key, FogOfWarConfig.STATE.VISIBLE)
	end
	for _, key in ipairs(data.newlyHidden or {}) do
		setHexState(key, FogOfWarConfig.STATE.EXPLORED)
	end

	-- Armee-Modelle nach dem Delta neu bewerten (nie naeher als noetig).
	refreshArmies()
end

--------------------------------------------------------------------------------
-- VOL LEN STATE ANWENDEN (beim Join)
--------------------------------------------------------------------------------
local function applyFullVision(data)
	if not data then return end
	refreshFolders()

	-- Basis: erstmal alles erkundet (auf 50% transparent), dann sichtbar.
	for _, key in ipairs(data.explored or {}) do
		setHexState(key, FogOfWarConfig.STATE.EXPLORED)
	end
	for _, key in ipairs(data.visible or {}) do
		setHexState(key, FogOfWarConfig.STATE.VISIBLE)
	end

	FogOfWarController.MarkReady()
	refreshArmies()
end

--------------------------------------------------------------------------------
-- INITIALISIERUNG
--------------------------------------------------------------------------------
-- Warten, bis die HexMap existiert (der Server spawnt sie). Dann verstecken.
task.spawn(function()
	-- Kurz warten, damit die Map bzw. das Spiel starten kann.
	while not workspace:FindFirstChild("HexMap") do
		task.wait(0.5)
	end
	hideEverything()
	print("[FogOfWarController] Alle Hexes initial versteckt.")
end)

--------------------------------------------------------------------------------
-- LISTENERS
--------------------------------------------------------------------------------
Net.On("FogOfWarInit", function(data)
	if not data then return end
	task.spawn(function() applyFullVision(data) end)
end)

Net.On("FogOfWarUpdate", function(data)
	if not data then return end
	task.spawn(function() applyVisionDelta(data) end)
end)

-- Wenn ein Spieler neu spawnt (Charakter respawn), sollte die Map nicht wieder
-- auftauchen - das Fog-of-War gilt persistent pro Sitzung. Wir refreshen nur,
-- falls die HexMap neu aufgebaut wurde (z.B. /regen).
workspace.ChildAdded:Connect(function(child)
	if child.Name == "HexMap" then
		task.wait(1)
		hideEverything()
		stateByKey = {}
		print("[FogOfWarController] HexMap neu erstellt - alles wieder versteckt.")
	end
end)

--------------------------------------------------------------------------------
-- PERIODISCHER ARMY-REFRESH
--------------------------------------------------------------------------------
-- Fängt Armee-Bewegungen, die keinen Hex-Zustandswechsel auslösen (z.B. ein
-- gegnerisches Heer, das innerhalb des Sichtfelds zieht oder es verlässt).
task.spawn(function()
	while true do
		task.wait(0.4)
		if armyModelsFolder then
			pcall(refreshArmies)
		end
	end
end)
