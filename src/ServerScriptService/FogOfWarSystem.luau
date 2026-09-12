--[[
    FogOfWarSystem (ModuleScript)
    Ort: ServerScriptService > FogOfWarSystem

    Server-seitige Fog-of-War-Logik. Berechnet pro Spieler, welche Hexfelder
    er JETZT sieht (visible) und welche er je erkundet hat (explored), und
    sendet Deltas an den jeweiligen Client.

    SICHTQUELLEN (additiv):
        - Armeen: max(UnitConfig.Sight) aller lebenden Units der Armee
        - Camps:  FogOfWarConfig.CAMP_SIGHT   (2)
        - Cities: FogOfWarConfig.CITY_SIGHT   (3)
        - Bastions: FogOfWarConfig.BASTION_SIGHT (4)

    ÜBERGÄNGE:
        unexplored -> explored : Feld war mal im Sichtbereich (permanent)
        explored   -> visible  : eigene Sichtquelle sieht es JETZT
        visible    -> explored : Sichtquelle weg/zerstört, bleibt erkundet

    REMOTES (Server -> Client, in DataRemotes):
        FogOfWarInit   (einmalig beim Join, voller State)
        FogOfWarUpdate (Delta nach Bewegung/Bau/Kampf)
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local HexUtils = require(script.Parent:WaitForChild("HexUtils"))
local HexData = require(script.Parent:WaitForChild("HexData"))
local ArmyData = require(script.Parent:WaitForChild("ArmyData"))
local UnitData = require(script.Parent:WaitForChild("UnitData"))
local CampData = require(script.Parent:WaitForChild("CampData"))
local CityData = require(script.Parent:WaitForChild("CityData"))
local BuildingData = require(script.Parent:WaitForChild("BuildingData"))
local UnitConfig = require(ReplicatedStorage:WaitForChild("UnitConfig"))
local FogOfWarConfig = require(ReplicatedStorage:WaitForChild("FogOfWarConfig"))
local FogOfWarData = require(script.Parent:WaitForChild("FogOfWarData"))

local FogOfWarSystem = {}

local dataRemotes = ReplicatedStorage:WaitForChild("DataRemotes", 30)

local function remote(name)
	return dataRemotes and dataRemotes:FindFirstChild(name) or nil
end

local function fire(player, remoteName, payload)
	if not player then return end
	local rem = remote(remoteName)
	if not rem then
		warn("[FogOfWar] Remote fehlt: " .. tostring(remoteName))
		return
	end
	pcall(function()
		rem:FireClient(player, payload)
	end)
end

--------------------------------------------------------------------------------
-- TERRAIN-HOEHE EINES HEXES (0 wenn unbekannt/nicht gespawnt)
--------------------------------------------------------------------------------
local function getTerrainHeightAt(q, r)
	local hex = HexData.GetHex(q, r)
	return hex and HexUtils.GetTerrainHeight(hex.terrain) or 0
end

--------------------------------------------------------------------------------
-- SICHTLINIEN-CHECK (Terrain-basiert)
--------------------------------------------------------------------------------
-- Laeuft die Hex-Linie von der Quelle zum Ziel ab. Sobald ein Hex auf dem
-- Weg (ausser der Quelle selbst) 2+ Ebenen hoeher ist als die Quelle,
-- blockiert es die Sicht - das Ziel UND alles dahinter ist unsichtbar.
-- Gibt zusaetzlich die Koordinate des ERSTEN blockierenden Hexes zurueck
-- (falls vorhanden), damit der Aufrufer es als "erkundet" markieren kann.
--------------------------------------------------------------------------------
local function isVisibleAlongLine(sourceQ, sourceR, sourceHeight, targetQ, targetR)
	local line = HexUtils.getLine(sourceQ, sourceR, targetQ, targetR)

	for _, hex in ipairs(line) do
		if not (hex.q == sourceQ and hex.r == sourceR) then
			local hexHeight = getTerrainHeightAt(hex.q, hex.r)
			if hexHeight >= sourceHeight + 2 then
				-- ABBRUCH: dieses Hex blockiert die Sicht. Es selbst wird
				-- vom Aufrufer als "erkundet" markiert (Terrain/Soil
				-- sichtbar, keine Units/Gebaeude); alles dahinter bleibt
				-- im Nebel.
				return false, hex.q, hex.r
			end
		end
	end

	return true, nil, nil
end

--------------------------------------------------------------------------------
-- SICHTBEREICH (Radius-Suche ueber das Hex-Grid + Sichtlinien-Blockade)
--------------------------------------------------------------------------------
local function collectVisibleHexes(q, r, sight, outSet, blockedSet)
	if not outSet then return end
	if sight < 0 then return end

	local sourceHeight = getTerrainHeightAt(q, r)

	local queue = { { q = q, r = r, d = 0 } }
	local visited = { [HexUtils.coordToKey(q, r)] = true }
	local head = 1

	while head <= #queue do
		local cur = queue[head]
		head = head + 1

		local key = HexUtils.coordToKey(cur.q, cur.r)

		-- Nur existierende (gespawnte) Hexes koennen sichtbar werden.
		if HexData.HasHex(cur.q, cur.r) then
			-- Bereits durch eine andere Quelle sichtbare Hexes muessen
			-- nicht erneut geprueft werden (Optimierung).
			if not outSet[key] then
				if cur.q == q and cur.r == r then
					-- Die Quelle selbst sieht immer sich selbst.
					outSet[key] = true
				else
					local visible, blockerQ, blockerR = isVisibleAlongLine(q, r, sourceHeight, cur.q, cur.r)
					if visible then
						outSet[key] = true
					elseif blockedSet and blockerQ and HexData.HasHex(blockerQ, blockerR) then
						-- Nur das ERSTE Hindernis auf der Sichtlinie wird
						-- als erkundet markiert - alles dahinter bleibt
						-- im Nebel (isVisibleAlongLine bricht bereits beim
						-- ersten Hindernis ab, liefert also genau das).
						blockedSet[HexUtils.coordToKey(blockerQ, blockerR)] = true
					end
				end
			end
		end

		-- Der Radius (Reichweite der Sichtquelle) wird weiterhin per
		-- Distanz bestimmt - die Sichtlinien-Blockade filtert danach nur
		-- noch aus, was tatsaechlich sichtbar ist.
		if cur.d < sight then
			for _, n in ipairs(HexUtils.getNeighbors(cur.q, cur.r)) do
				local nk = HexUtils.coordToKey(n.q, n.r)
				if not visited[nk] then
					visited[nk] = true
					table.insert(queue, { q = n.q, r = n.r, d = cur.d + 1 })
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- SICHTQUELLEN EINES SPIELERS
--------------------------------------------------------------------------------
local function addArmySight(player, outSet, blockedSet)
	for _, army in ipairs(ArmyData.GetArmiesByOwner(player)) do
		local maxSight = 0
		for _, unitId in ipairs(army.units or {}) do
			local unit = UnitData.GetUnit(unitId)
			if unit and unit.alive then
				local cfg = UnitConfig.GetUnit(unit.unitType)
				local sight = cfg and cfg.Stats.Sight or 0
				if sight > maxSight then maxSight = sight end
			end
		end
		if maxSight > 0 then
			collectVisibleHexes(army.q, army.r, maxSight, outSet, blockedSet)
		end
	end
end

local function addCampSight(player, outSet, blockedSet)
	for _, camp in ipairs(CampData.GetCampsByOwner(player)) do
		collectVisibleHexes(camp.q, camp.r, FogOfWarConfig.CAMP_SIGHT, outSet, blockedSet)
	end
end

local function addCitySight(player, outSet, blockedSet)
	for _, city in ipairs(CityData.GetCitiesByOwner(player)) do
		collectVisibleHexes(city.q, city.r, FogOfWarConfig.CITY_SIGHT, outSet, blockedSet)
	end
end

local function addBastionSight(player, outSet, blockedSet)
	for _, building in ipairs(BuildingData.GetBuildingsByType("Bastion")) do
		if building.owner == player then
			collectVisibleHexes(building.q, building.r, FogOfWarConfig.BASTION_SIGHT, outSet, blockedSet)
		end
	end
end

-- computeVisible(player) -> visible, blockedExplored
-- blockedExplored: Hexes, die eine Sichtlinie blockiert haben (2+ Ebenen
-- hoeher als die jeweilige Quelle) - werden NIE visible, aber als
-- "erkundet" markiert (Terrain/Soil aufgedeckt, keine Units/Gebaeude).
local function computeVisible(player)
	local visible = {}
	local blockedExplored = {}
	addArmySight(player, visible, blockedExplored)
	addCampSight(player, visible, blockedExplored)
	addCitySight(player, visible, blockedExplored)
	addBastionSight(player, visible, blockedExplored)
	return visible, blockedExplored
end

local function countSet(s)
	local n = 0
	for _ in pairs(s or {}) do n = n + 1 end
	return n
end

--------------------------------------------------------------------------------
-- UPDATE VISION (Kern)
-- Berechnet sichtbar, merged explored, sendet Delta.
--------------------------------------------------------------------------------
function FogOfWarSystem.UpdateVision(player)
	if not player then
		warn("[FogOfWar] UpdateVision OHNE Spieler aufgerufen")
		return
	end
	if not player.Parent then
		return -- Spieler ist weg
	end

	local ok, err = pcall(function()
		local state = FogOfWarData.GetOrCreate(player)
		if not state then return end

		-- 1) Neue sichtbare Menge berechnen. blockedExplored sind Hexes,
		--    die eine Sichtlinie blockiert haben (2+ Ebenen hoeher) - sie
		--    werden NIE visible, aber unten als "erkundet" markiert.
		local newVisible, blockedExplored = computeVisible(player)

		local oldVisible = state.visible or {}

		-- 2) Vergleich: neu sichtbar vs. nicht mehr sichtbar.
		local newlyVisible = {}
		local newlyHidden = {}
		for key in pairs(newVisible) do
			if not oldVisible[key] then newlyVisible[key] = true end
		end
		for key in pairs(oldVisible) do
			if not newVisible[key] then newlyHidden[key] = true end
		end

		-- 3) Explored = explored UNION visible UNION blockedExplored
		--    (permanent, nie entfernen). Blockierende Hexes werden als
		--    erkundet markiert, auch wenn sie NICHT visible werden -
		--    Terrain/Soil aufdecken, aber keine Units/Gebaeude.
		local exploredCandidates = {}
		for key in pairs(newVisible) do exploredCandidates[key] = true end
		for key in pairs(blockedExplored) do exploredCandidates[key] = true end
		local newlyExplored = FogOfWarData.AddExplored(player, exploredCandidates)

		-- 4) Neuen Zustand speichern.
		state.visible = newVisible

		print(("[FogOfWar] UpdateVision %s | sichtbar=%d neu=%d hidden=%d erkundet=%d blockiert=%d")
			:format(player.Name, countSet(newVisible), countSet(newlyVisible),
				countSet(newlyHidden), countSet(newlyExplored), countSet(blockedExplored)))

		-- 5) Delta an den Client senden.
		FogOfWarSystem.SendVisionDelta(player, newlyVisible, newlyHidden, newlyExplored)
	end)

	if not ok then
		warn("[FogOfWar] UpdateVision FEHLER (" .. tostring(player.Name) .. "): " .. tostring(err))
	end
end


--------------------------------------------------------------------------------
-- DELTA SENDEN
--------------------------------------------------------------------------------
function FogOfWarSystem.SendVisionDelta(player, newlyVisible, newlyHidden, newlyExplored)
	if not player then return end
	-- Nur senden, wenn es etwas zu berichten gibt, sonst sparen wir Traffic.
	local hasChange = next(newlyVisible) ~= nil
		or next(newlyHidden) ~= nil
		or next(newlyExplored) ~= nil
	if not hasChange then return end

	local payload = {
		newlyVisible = FogOfWarData.setToArray(newlyVisible),
		newlyHidden  = FogOfWarData.setToArray(newlyHidden),
		newlyExplored = FogOfWarData.setToArray(newlyExplored),
	}
	print(("[FogOfWar] Sende Delta an %s | neu=%d hidden=%d erkundet=%d")
		:format(player.Name, #payload.newlyVisible, #payload.newlyHidden, #payload.newlyExplored))

	fire(player, "FogOfWarUpdate", payload)
end

--------------------------------------------------------------------------------
-- VOLLER STATE (beim Join)
--------------------------------------------------------------------------------
function FogOfWarSystem.SendFullVision(player)
	if not player then return end
	local state = FogOfWarData.GetOrCreate(player)
	if not state then return end

	-- Beim Join sofort die aktuelle Sicht berechnen (falls noch nie passiert).
	if next(state.visible) == nil and next(state.explored) == nil then
		FogOfWarSystem.UpdateVision(player)
		state = FogOfWarData.GetOrCreate(player)
	end

	local payload = {
		visible  = FogOfWarData.setToArray(state.visible),
		explored = FogOfWarData.setToArray(state.explored),
	}
	print(("[FogOfWar] Sende FULL-State an %s | visible=%d explored=%d")
		:format(player.Name, #payload.visible, #payload.explored))

	fire(player, "FogOfWarInit", payload)
end

--------------------------------------------------------------------------------
-- QUERIES
--------------------------------------------------------------------------------
function FogOfWarSystem.GetVisibleHexes(player)
	local state = FogOfWarData.Get(player)
	return state and state.visible or {}
end

function FogOfWarSystem.GetExploredHexes(player)
	local state = FogOfWarData.Get(player)
	return state and state.explored or {}
end

-- IsHexVisible(player, q, r) -> boolean
function FogOfWarSystem.IsHexVisible(player, q, r)
	local state = FogOfWarData.Get(player)
	if not state then return false end
	return state.visible[HexUtils.coordToKey(q, r)] == true
end

-- IsHexExplored(player, q, r) -> boolean
function FogOfWarSystem.IsHexExplored(player, q, r)
	local state = FogOfWarData.Get(player)
	if not state then return false end
	return state.explored[HexUtils.coordToKey(q, r)] == true
end

--------------------------------------------------------------------------------
-- BASEPLATE (neutrale Farbe fuer die unerforschte Map)
--------------------------------------------------------------------------------
function FogOfWarSystem.SetBaseplateColor()
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		baseplate.Color = FogOfWarConfig.BASEPLATE_COLOR
	else
		-- Fallback: das groesste Basis-Part (nicht Teil von HexMap) einfärben.
		-- Ist nur eine Defensiv-Massnahme; das eigentliche Baseplate wird
		-- normalerweise ueber den Namen gefunden.
		local hexMap = workspace:FindFirstChild("HexMap")
		if not hexMap then return end
		for _, obj in ipairs(workspace:GetChildren()) do
			if obj:IsA("BasePart") and obj.Name ~= "Baseplate" and obj.Size.X > 100 then
				obj.Color = FogOfWarConfig.BASEPLATE_COLOR
				break
			end
		end
	end
end

--------------------------------------------------------------------------------
-- PLAYER LIFECYCLE (einmalig abonniert beim Laden des Moduls)
--------------------------------------------------------------------------------
local baseplateSet = false

Players.PlayerAdded:Connect(function(player)
	-- Baseplate einmalig neutral einfärben (grau/beige, nicht weiss).
	if not baseplateSet then
		pcall(FogOfWarSystem.SetBaseplateColor)
		baseplateSet = true
	end

	-- Dem Client einen Moment geben, Scripts zu laden, bevor der volle
	-- State gepusht wird.
	task.delay(2, function()
		if player.Parent then
			pcall(FogOfWarSystem.SendFullVision, player)
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	FogOfWarData.Remove(player)
end)

-- Bereits anwesende Spieler (z.B. lokale Tests) ebenfalls initialisieren.
for _, player in ipairs(Players:GetPlayers()) do
	FogOfWarData.Create(player)
	task.delay(1, function()
		if player.Parent then
			pcall(FogOfWarSystem.SendFullVision, player)
		end
	end)
end

return FogOfWarSystem
