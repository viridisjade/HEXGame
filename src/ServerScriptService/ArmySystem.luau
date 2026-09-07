
--[[
    ArmySystem (ModuleScript)
    Ort: ServerScriptService > ArmySystem
    
    Verwaltet Armeen: Erstellen, Löschen, Kombinieren, Splitten,
    Units hinzufügen/entfernen, Bewegen.
--]]

local ArmySystem = {}

local ArmyData = require(script.Parent:WaitForChild("ArmyData"))
local UnitData = require(script.Parent:WaitForChild("UnitData"))
local HexData = require(script.Parent:WaitForChild("HexData"))
local ArmyStats = require(script.Parent:WaitForChild("ArmyStats"))
local CombatData = require(script.Parent:WaitForChild("CombatData"))

--------------------------------------------------------------------------------
-- KOMPATIBILITÄTS-FIX (nil-crash bei aelteren HexData-Versionen):
--
-- ArmySystem wurde zuletzt mit HexData.ClearHexField() geschrieben.
-- Existiert diese Funktion in der eingebundenen HexData-Version nicht
-- (z. B. weil in Studio noch eine aeltere HexData laeuft), crashte jeder
-- Aufruf mit "attempt to call a nil value" - Worst Case: mitten in
-- ArmySystem.MoveArmy(), Zeile ~107 beim Bewegen.
--
-- Diese Helper-Funktion waehlt zur Laufzeit den sicheren Weg:
-- bevorzugt HexData.ClearHexField, sonst direkte Feld-Leerung.
--------------------------------------------------------------------------------
local function clearHexFieldSafe(q, r, field)
	if HexData and HexData.ClearHexField then
		HexData.ClearHexField(q, r, field)
		return
	end
	-- Fallback fuer alte HexData ohne ClearHexField: Feld manuell leeren.
	local hex = HexData and HexData.GetHex(q, r) or nil
	if hex then
		hex[field] = nil
	end
end

--------------------------------------------------------------------------------
-- KONFIGURATION
--------------------------------------------------------------------------------
ArmySystem.Config = {
	MAX_UNITS_PER_ARMY = 8,
}

-- Lazy tech access (avoids require cycles).
local _techSystem
local function Tech()
	if not _techSystem then
		local ok, mod = pcall(function()
			return require(script.Parent:WaitForChild("TechTreeSystem"))
		end)
		_techSystem = ok and mod or false
	end
	return _techSystem or nil
end

--------------------------------------------------------------------------------
-- GetMaxUnits(armyId) -> number
-- Base cap plus the Logistics tech bonus of the army owner (8 -> 10).
--------------------------------------------------------------------------------
function ArmySystem.GetMaxUnits(armyId)
	local base = ArmySystem.Config.MAX_UNITS_PER_ARMY
	local army = ArmyData.GetArmy(armyId)
	if not army or not army.owner then return base end

	local tech = Tech()
	if not tech then return base end
	return tech.GetMaxUnitsPerArmy(army.owner, base)
end

--------------------------------------------------------------------------------
-- SpawnArmy(owner, q, r) -> armyId or nil
--------------------------------------------------------------------------------
function ArmySystem.SpawnArmy(owner, q, r)
	local hex = HexData.GetHex(q, r)
	if not hex then
		warn("[ArmySystem] SpawnArmy: Hex (" .. q .. ", " .. r .. ") existiert nicht")
		return nil
	end

	-- WICHTIG: Nicht blind hex.army vertrauen!
	local actualArmyOnHex = ArmyData.GetArmyOnHex(q, r)

	if hex.army and (not actualArmyOnHex or actualArmyOnHex.id ~= hex.army) then
		HexData.UpdateHex(q, r, { army = actualArmyOnHex and actualArmyOnHex.id or nil })
	end

	if actualArmyOnHex then
		warn("[ArmySystem] SpawnArmy: Hex (" .. q .. ", " .. r .. ") hat WIRKLICH bereits Army " .. actualArmyOnHex.id)
		return nil
	end

	local armyId = ArmyData.CreateArmy(owner, q, r)

	HexData.UpdateHex(q, r, { army = armyId })

	print("[ArmySystem] Army " .. armyId .. " erstellt auf (" .. q .. ", " .. r .. ")")
	return armyId
end

--------------------------------------------------------------------------------
-- DeleteArmy(armyId)
--------------------------------------------------------------------------------
function ArmySystem.DeleteArmy(armyId)
	local army = ArmyData.GetArmy(armyId)
	if not army then
		warn("[ArmySystem] DeleteArmy: Army " .. armyId .. " nicht gefunden")
		return
	end

	for _, unitId in ipairs(army.units) do
		UnitData.SetArmyId(unitId, nil)
	end

	-- HexData leeren (ClearHexField, da { army = nil } ein Lua-No-Op wäre)
	clearHexFieldSafe(army.q, army.r, "army")

	-- Sicherheitsnetz: 3D-Modell mitentfernen.
	-- Sonst bleibt eine "Geister-Armee" im Workspace stehen, die Raycasts
	-- abfängt und das Hex besetzt aussehen lässt.
	local hexMap = workspace:FindFirstChild("HexMap")
	local armyModels = hexMap and hexMap:FindFirstChild("ArmyModels")
	local model = armyModels and armyModels:FindFirstChild("Army_" .. armyId)
	if model then
		model:Destroy()
	end

	ArmyData.RemoveArmy(armyId)

	print("[ArmySystem] Army " .. armyId .. " gelöscht")
end

--------------------------------------------------------------------------------
-- MoveArmy(armyId, newQ, newR) -> boolean
--------------------------------------------------------------------------------
-- MoveArmy(armyId, newQ, newR, force)
--   force = true bypasses the combat lock. ONLY CombatSystem may use it
--   (winner advancing onto the contested hex, routing armies retreating).
function ArmySystem.MoveArmy(armyId, newQ, newR, force)
	-- NEW: armies bound to a running combat are frozen in place.
	if not force and CombatData.IsInCombat(armyId) then
		warn("[ArmySystem] MoveArmy: Army " .. tostring(armyId) .. " ist im Kampf gebunden")
		return false
	end

	local army = ArmyData.GetArmy(armyId)
	if not army then
		warn("[ArmySystem] MoveArmy: Army " .. armyId .. " nicht gefunden")
		return false
	end

	local targetHex = HexData.GetHex(newQ, newR)
	if not targetHex then
		warn("[ArmySystem] MoveArmy: Ziel-Hex (" .. newQ .. ", " .. newR .. ") existiert nicht")
		return false
	end

	if targetHex.army and targetHex.army ~= armyId then
		warn("[ArmySystem] MoveArmy: Ziel-Hex (" .. newQ .. ", " .. newR .. ") hat bereits Army " .. targetHex.army)
		return false
	end

	-- Alte Position wirklich freigeben (ClearHexField, da { army = nil } ein No-Op wäre)
	clearHexFieldSafe(army.q, army.r, "army")

	ArmyData.UpdateArmy(armyId, { q = newQ, r = newR })

	HexData.UpdateHex(newQ, newR, { army = armyId })

	return true
end

--------------------------------------------------------------------------------
-- MergeArmies(armyIdA, armyIdB) -> boolean
--------------------------------------------------------------------------------
function ArmySystem.MergeArmies(armyIdA, armyIdB)
	local armyA = ArmyData.GetArmy(armyIdA)
	local armyB = ArmyData.GetArmy(armyIdB)

	if not armyA then
		warn("[ArmySystem] MergeArmies: Army A (" .. armyIdA .. ") nicht gefunden")
		return false
	end
	if not armyB then
		warn("[ArmySystem] MergeArmies: Army B (" .. armyIdB .. ") nicht gefunden")
		return false
	end

	local totalUnits = #armyA.units + #armyB.units
	local mergeMax = ArmySystem.GetMaxUnits(armyIdA)
	if totalUnits > mergeMax then
		warn("[ArmySystem] MergeArmies: Zusammen " .. totalUnits .. " Units, Maximum ist " .. mergeMax)
		return false
	end

	for _, unitId in ipairs(armyB.units) do
		table.insert(armyA.units, unitId)
		UnitData.SetArmyId(unitId, armyIdA)
	end

	armyB.units = {}
	ArmySystem.DeleteArmy(armyIdB)

	ArmyStats.Recalculate(armyIdA)

	print("[ArmySystem] Army " .. armyIdB .. " in Army " .. armyIdA .. " zusammengeführt (" .. #armyA.units .. " Units)")
	return true
end

--------------------------------------------------------------------------------
-- SplitArmy(armyId, unitId, targetQ, targetR) -> newArmyId or nil
--------------------------------------------------------------------------------
function ArmySystem.SplitArmy(armyId, unitId, targetQ, targetR)
	local army = ArmyData.GetArmy(armyId)
	if not army then
		warn("[ArmySystem] SplitArmy: Army " .. armyId .. " nicht gefunden")
		return nil
	end

	local unitIndex = nil
	for i, uid in ipairs(army.units) do
		if uid == unitId then
			unitIndex = i
			break
		end
	end

	if not unitIndex then
		warn("[ArmySystem] SplitArmy: Unit " .. unitId .. " ist nicht in Army " .. armyId)
		return nil
	end

	if #army.units <= 1 then
		warn("[ArmySystem] SplitArmy: Army " .. armyId .. " hat nur 1 Unit, kann nicht splitten")
		return nil
	end

	local targetHex = HexData.GetHex(targetQ, targetR)
	if not targetHex then
		warn("[ArmySystem] SplitArmy: Ziel-Hex (" .. targetQ .. ", " .. targetR .. ") existiert nicht")
		return nil
	end
	if targetHex.army then
		warn("[ArmySystem] SplitArmy: Ziel-Hex (" .. targetQ .. ", " .. targetR .. ") ist besetzt")
		return nil
	end

	local newArmyId = ArmySystem.SpawnArmy(army.owner, targetQ, targetR)
	if not newArmyId then return nil end

	table.remove(army.units, unitIndex)

	local newArmy = ArmyData.GetArmy(newArmyId)
	table.insert(newArmy.units, unitId)
	UnitData.SetArmyId(unitId, newArmyId)

	ArmyStats.Recalculate(armyId)
	ArmyStats.Recalculate(newArmyId)

	print("[ArmySystem] Unit " .. unitId .. " von Army " .. armyId .. " abgespalten in neue Army " .. newArmyId)
	return newArmyId
end

--------------------------------------------------------------------------------
-- AddUnit(armyId, unitId) -> boolean
--------------------------------------------------------------------------------
function ArmySystem.AddUnit(armyId, unitId)
	local army = ArmyData.GetArmy(armyId)
	if not army then
		warn("[ArmySystem] AddUnit: Army " .. armyId .. " nicht gefunden")
		return false
	end

	local maxUnits = ArmySystem.GetMaxUnits(armyId)
	if #army.units >= maxUnits then
		warn("[ArmySystem] AddUnit: Army " .. armyId .. " ist voll (" .. #army.units .. "/" .. maxUnits .. ")")
		return false
	end

	local unit = UnitData.GetUnit(unitId)
	if not unit then
		warn("[ArmySystem] AddUnit: Unit " .. unitId .. " nicht gefunden")
		return false
	end
	if not unit.alive then
		warn("[ArmySystem] AddUnit: Unit " .. unitId .. " ist tot")
		return false
	end

	if unit.armyId and unit.armyId ~= armyId then
		warn("[ArmySystem] AddUnit: Unit " .. unitId .. " ist bereits in Army " .. unit.armyId)
		return false
	end

	table.insert(army.units, unitId)
	UnitData.SetArmyId(unitId, armyId)

	ArmyStats.Recalculate(armyId)

	return true
end

--------------------------------------------------------------------------------
-- RemoveUnit(armyId, unitId) -> boolean
--------------------------------------------------------------------------------
function ArmySystem.RemoveUnit(armyId, unitId)
	local army = ArmyData.GetArmy(armyId)
	if not army then
		warn("[ArmySystem] RemoveUnit: Army " .. armyId .. " nicht gefunden")
		return false
	end

	local found = false
	for i, uid in ipairs(army.units) do
		if uid == unitId then
			table.remove(army.units, i)
			found = true
			break
		end
	end

	if not found then
		warn("[ArmySystem] RemoveUnit: Unit " .. unitId .. " nicht in Army " .. armyId)
		return false
	end

	UnitData.SetArmyId(unitId, nil)

	if #army.units == 0 then
		print("[ArmySystem] Army " .. armyId .. " ist leer, wird gelöscht")
		ArmySystem.DeleteArmy(armyId)
	else
		ArmyStats.Recalculate(armyId)
	end

	return true
end

--------------------------------------------------------------------------------
-- GetArmyUnits(armyId) -> table
--------------------------------------------------------------------------------
function ArmySystem.GetArmyUnits(armyId)
	local army = ArmyData.GetArmy(armyId)
	if not army then return {} end

	local result = {}
	for _, unitId in ipairs(army.units) do
		local unit = UnitData.GetUnit(unitId)
		if unit then
			table.insert(result, unit)
		end
	end
	return result
end

--------------------------------------------------------------------------------
-- GetArmyStrength(armyId) -> { totalLP, totalAttack, totalDefense }
--------------------------------------------------------------------------------
function ArmySystem.GetArmyStrength(armyId)
	local army = ArmyData.GetArmy(armyId)
	if not army then return { totalLP = 0, totalAttack = 0, totalDefense = 0 } end

	local totalLP = 0
	local totalAttack = 0
	local totalDefense = 0

	for _, unitId in ipairs(army.units) do
		local unit = UnitData.GetUnit(unitId)
		if unit and unit.alive then
			totalLP = totalLP + unit.currentLP

			local stats = UnitData.GetUnitStats(unitId)
			if stats then
				totalAttack = totalAttack + stats.Attack
				totalDefense = totalDefense + stats.Defense
			end
		end
	end

	return {
		totalLP = totalLP,
		totalAttack = totalAttack,
		totalDefense = totalDefense,
	}
end

--------------------------------------------------------------------------------
-- IsArmyFull(armyId) -> boolean
--------------------------------------------------------------------------------
function ArmySystem.IsArmyFull(armyId)
	local army = ArmyData.GetArmy(armyId)
	if not army then return true end
	return #army.units >= ArmySystem.GetMaxUnits(armyId)
end

--------------------------------------------------------------------------------
-- SpawnArmyWithUnit(owner, q, r, unitType) -> armyId, unitId
--------------------------------------------------------------------------------
function ArmySystem.SpawnArmyWithUnit(owner, q, r, unitType)
	local armyId = ArmySystem.SpawnArmy(owner, q, r)
	if not armyId then return nil, nil end

	local unitId = UnitData.CreateUnit(unitType, owner)
	if not unitId then
		ArmySystem.DeleteArmy(armyId)
		return nil, nil
	end

	ArmySystem.AddUnit(armyId, unitId)

	return armyId, unitId
end

--------------------------------------------------------------------------------
-- REENTRANCY-PROTECTION (Stack-Overflow-Schutz)
--
-- Verhindert verschachtelte/versehentliche Wiederaufrufe derselben
-- Army-Lifecycle-Funktionen (z. B. MoveArmy -> Event-Kette -> MoveArmy
-- derselben Armee, oder DeleteArmy waehrend DeleteArmy).
-- Prinzip aus dem Bug-Report: Flag-Loesung. Kein Verhaltens-Unterschied
-- im Normalbetrieb; schuetzt zusätzlich mit pcall vor kaskadierenden
-- Fehlern.
--------------------------------------------------------------------------------
local reentrancyLocks = {}

local function makeReentrant(name, fn)
	return function(...)
		if reentrancyLocks[name] then
			warn("[ArmySystem] Verschachtelter Aufruf blockiert: "
				.. name .. " (Rekursion-Schutz)")
			return nil
		end
		reentrancyLocks[name] = true
		local results = table.pack(pcall(fn, ...))
		reentrancyLocks[name] = nil
		if not results[1] then
			warn("[ArmySystem] Fehler in " .. name .. ": " .. tostring(results[2]))
			return nil
		end
		return table.unpack(results, 2, results.n)
	end
end

ArmySystem.MoveArmy   = makeReentrant("MoveArmy",   ArmySystem.MoveArmy)
ArmySystem.DeleteArmy = makeReentrant("DeleteArmy", ArmySystem.DeleteArmy)

return ArmySystem
