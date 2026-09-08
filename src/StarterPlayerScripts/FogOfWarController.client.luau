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

-- Lebenszeichen: Wenn dieser Print NICHT erscheint, lädt das LocalScript nicht
-- (dann liegt es an der Rojo-Zuordnung, nicht an der Fog-Logik).
print("[FogOfWarController] geladen (LocalScript läuft)")

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
-- SET MODEL VISIBILITY (nur Transferenz - BaseParts haben KEIN Visible!)
--------------------------------------------------------------------------------
-- Roblox-BaseParts (Part, MeshPart, Union, WedgePen) besitzen KEIN Visible-
-- Property. Sichtbarkeit wird ausschliesslich über Transparency gesteuert:
--   0 = sichtbar / normal, 0.5 = erkundet, 1 = komplett unsichtbar.
-- Auch Models haben KEIN Visible - die Sichtbarkeit ergibt sich aus der
-- Transparenz ihrer BasePart-Descendants.
local function setModelVisibility(model, visible, transparency)
	if not model then return end
	-- visible=true -> gewuenschte Transparenz (Default 0 = sichtbar);
	-- visible=false -> 1 (komplett unsichtbar).
	local target = visible and (transparency or 0) or 1

	-- Falls das Objekt selbst ein BasePart ist (z.B. einzelnes Hex).
	if model:IsA("BasePart") then
		model.Transparency = target
		-- Decals/Texturen am Part ebenfalls mitziehen.
		for _, child in ipairs(model:GetDescendants()) do
			if child:IsA("Decal") or child:IsA("Texture") then
				child.Transparency = target
			end
		end
		return
	end

	-- Für Models: alle BaseParts + Decals/Texturen.
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Transparency = target
		elseif part:IsA("Decal") or part:IsA("Texture") then
			part.Transparency = target
		end
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
	local name = "Hex_" .. q .. "_" .. r
	-- Provinz-Hexes liegen gruppiert unter Province_<id> Modellen, NICHT direkt
	-- im ProvinceVisuals-Ordner. Suche deshalb in jedem Province_-Modell.
	for _, provinceModel in ipairs(provinceFolder:GetChildren()) do
		if provinceModel:IsA("Model") or provinceModel:IsA("Folder") then
			local hex = provinceModel:FindFirstChild(name)
			if hex then return hex end
		end
	end
	return nil
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

	-- Diagnose beim EINBLENDEN (visible): zeigt ob die Modelle gefunden werden.
	if state == FogOfWarConfig.STATE.VISIBLE then
		print(("[FogOfWar] setHex %s -> visible | hex=%s soil=%s bld=%s prov=%s armies=%d")
			:format(key, tostring(hexModel ~= nil), tostring(soilModel ~= nil),
				tostring(building ~= nil), tostring(provinceModel ~= nil), #armies))
	end

	if state == "visible" then
		setModelVisibility(hexModel, true, FogOfWarConfig.VISIBLE_TRANSPARENCY)
		setModelVisibility(soilModel, true, FogOfWarConfig.VISIBLE_TRANSPARENCY)
		setModelVisibility(building, true, FogOfWarConfig.VISIBLE_TRANSPARENCY)
		-- ProvinceHexes sind Farb-Overlays ueber dem Terrain: IMMER 50% transparent,
		-- damit die Provinzfarbe UND das Terrain darunter sichtbar bleiben.
		setModelVisibility(provinceModel, true, FogOfWarConfig.EXPLORED_TRANSPARENCY)
		-- Units sichtbar.
		for _, army in ipairs(armies) do
			setModelVisibility(army, true, FogOfWarConfig.VISIBLE_TRANSPARENCY)
		end

	elseif state == "explored" then
		setModelVisibility(hexModel, true, FogOfWarConfig.EXPLORED_TRANSPARENCY)
		setModelVisibility(soilModel, true, FogOfWarConfig.EXPLORED_TRANSPARENCY)
		setModelVisibility(building, true, FogOfWarConfig.EXPLORED_TRANSPARENCY)
		-- ProvinceHexes: auch erkundet 50% transparent.
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
-- NEU AUFTAUCHENDE MODELLE (Gebäude, Armeen) NACHBEWERTEN
--------------------------------------------------------------------------------
-- Neue Modelle (z.B. von Gegnern gebaute Gebäude) werden vom Server auf allen
-- Clients sichtbar erzeugt. Wenn ihr Hex keinen Zustandswechsel auslöst (weil es
-- schon erkundet/sichtbar war), bleibt das neue Modell sonst fälschlich sichtbar.
-- Hiermit wenden wir den Hex-Zustand sofort an.
local function buildingKeyFromName(name)
	if not name then return nil end
	local q, r = string.match(name, "_(%-?%d+)_(%-?%d+)$")
	if q and r then return q .. "_" .. r end
	return nil
end

local function applyHexByKey(key)
	if not key then return end
	local state = stateByKey[key] or FogOfWarConfig.STATE.UNEXPLORED
	setHexState(key, state)
end

local function connectBuildingsWatcher(buildingFolder)
	if not buildingFolder then return end
	buildingFolder.ChildAdded:Connect(function(child)
		if not child then return end
		-- Baustellen (Ghost_) sollen mit dem Fog behandelt werden; aber wir
		-- ignorieren sie hier, weil sie beim Fertigstellen ersetzt werden.
		if child.Name:match("^Ghost_") then return end
		local key = buildingKeyFromName(child.Name)
		if key then
			applyHexByKey(key)
		end
	end)
end

local function connectArmyWatcher(armyFolder)
	if not armyFolder then return end
	armyFolder.ChildAdded:Connect(function(child)
		if child then pcall(refreshArmies) end
	end)
end

local function setupHexMapWatchers()
	refreshFolders()
	if not hexMapFolder then return end

	-- Bestehende Folder (falls schon vorhanden) direkt verbinden.
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
-- PUBLIC NAME / READY (vorab deklariert, damit applyFullVision darauf zugreifen kann)
--------------------------------------------------------------------------------
local FogOfWarController = { Ready = false }
function FogOfWarController.MarkReady()
	FogOfWarController.Ready = true
	print("[FogOfWarController] Bereit.")
end

--------------------------------------------------------------------------------
-- DIAGNOSE HILFE (per Hand aufrufen, NICHT im Normalbetrieb)
--------------------------------------------------------------------------------
-- Wenn die Pipeline NICHT das Problem ist, kann man mit diesem Aufruf ALLE
-- Hex-Modelle sichtbar machen, um die Workspace-Struktur zu pruefen.
-- Aufruf im Command-Bar beim Testen:  FogOfWarDebugReveal()
_G.FogOfWarDebugReveal = function()
	local hexMap = workspace:FindFirstChild("HexMap")
	if not hexMap then
		warn("[FogOfWar TEST] HexMap nicht gefunden")
		return
	end
	for _, folder in ipairs(hexMap:GetDescendants()) do
		if folder:IsA("BasePart") then
			folder.Transparency = 0
		end
	end
	print("[FogOfWar TEST] Alle Hexes sichtbar gemacht!")
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

	-- Expliziter Soil-Pass: schaltet auch alle Soil-Modelle auf Transparency = 1.
	-- (Robust - falls der generische Kinder-Loop das Soils-Folder nicht erfasst
	-- hat oder Soils spaeter/spawnweise hinzukommen.)
	local soilCount = 0
	if soilsFolder then
		for _, soilTypeFolder in ipairs(soilsFolder:GetChildren()) do
			for _, soil in ipairs(soilTypeFolder:GetChildren()) do
				setModelVisibility(soil, false, 1)
				soilCount = soilCount + 1
			end
		end
	end
	print("[FogOfWar] hideEverything | Soils versteckt: " .. soilCount)
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
	setupHexMapWatchers()
	print("[FogOfWarController] Alle Hexes initial versteckt, Watcher verbunden.")
end)

--------------------------------------------------------------------------------
-- LISTENERS
--------------------------------------------------------------------------------
Net.On("FogOfWarInit", function(data)
	if not data then return end
	print(("[FogOfWar Client] INIT empfangen | visible=%d explored=%d")
		:format(#(data.visible or {}), #(data.explored or {})))
	task.spawn(function() applyFullVision(data) end)
end)

Net.On("FogOfWarUpdate", function(data)
	if not data then return end
	print(("[FogOfWar Client] UPDATE empfangen | neu=%d hidden=%d erkundet=%d")
		:format(#(data.newlyVisible or {}), #(data.newlyHidden or {}), #(data.newlyExplored or {})))
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
		setupHexMapWatchers()
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
