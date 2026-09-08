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
-- SICHTBEREICH (Radius-Suche ueber das Hex-Grid)
--------------------------------------------------------------------------------
local function collectVisibleHexes(q, r, sight, outSet)
	if not outSet then return end
	if sight < 0 then return end

	local queue = { { q = q, r = r, d = 0 } }
	local visited = { [HexUtils.coordToKey(q, r)] = true }
	local head = 1

	while head <= #queue do
		local cur = queue[head]
		head = head + 1

		local key = HexUtils.coordToKey(cur.q, cur.r)
		-- Nur existierende (gespawnte) Hexes koennen sichtbar werden.
		if HexData.HasHex(cur.q, cur.r) then
			outSet[key] = true
		end

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
local function addArmySight(player, outSet)
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
			collectVisibleHexes(army.q, army.r, maxSight, outSet)
		end
	end
end

local function addCampSight(player, outSet)
	for _, camp in ipairs(CampData.GetCampsByOwner(player)) do
		collectVisibleHexes(camp.q, camp.r, FogOfWarConfig.CAMP_SIGHT, outSet)
	end
end

local function addCitySight(player, outSet)
	for _, city in ipairs(CityData.GetCitiesByOwner(player)) do
		collectVisibleHexes(city.q, city.r, FogOfWarConfig.CITY_SIGHT, outSet)
	end
end

local function addBastionSight(player, outSet)
	for _, building in ipairs(BuildingData.GetBuildingsByType("Bastion")) do
		if building.owner == player then
			collectVisibleHexes(building.q, building.r, FogOfWarConfig.BASTION_SIGHT, outSet)
		end
	end
end

local function computeVisible(player)
	local visible = {}
	addArmySight(player, visible)
	addCampSight(player, visible)
	addCitySight(player, visible)
	addBastionSight(player, visible)
	return visible
end

--------------------------------------------------------------------------------
-- UPDATE VISION (Kern)
-- Berechnet sichtbar, merged explored, sendet Delta.
--------------------------------------------------------------------------------
function FogOfWarSystem.UpdateVision(player)
	if not player then return end
	if not player.Parent then return end  -- Spieler ist weg

	local state = FogOfWarData.GetOrCreate(player)
	if not state then return end

	-- 1) Neue sichtbare Menge berechnen.
	local newVisible = computeVisible(player)

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

	-- 3) Explored = explored UNION visible (permanent, nie entfernen).
	local newlyExplored = FogOfWarData.AddExplored(player, newVisible)

	-- 4) Neuen Zustand speichern.
	state.visible = newVisible

	-- 5) Delta an den Client senden. Neu-erkundete Felder werden dem Client
	--    auch als explored gemeldet (auch wenn sie bereits visible sind:
	--    der Client setzt sie direkt auf visible).
	FogOfWarSystem.SendVisionDelta(player, newlyVisible, newlyHidden, newlyExplored)
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

	fire(player, "FogOfWarUpdate", {
		newlyVisible = FogOfWarData.setToArray(newlyVisible),
		newlyHidden  = FogOfWarData.setToArray(newlyHidden),
		newlyExplored = FogOfWarData.setToArray(newlyExplored),
	})
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

	fire(player, "FogOfWarInit", {
		visible  = FogOfWarData.setToArray(state.visible),
		explored = FogOfWarData.setToArray(state.explored),
	})
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
