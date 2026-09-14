
--[[
    MovementHandler (Script)
    Ort: ServerScriptService > MovementHandler

    Empfängt alle Bewegungs-Anfragen vom Client.

    STADT-BESETZUNG MIT BÜRGERWEHR (siehe Aufgabenstellung "Stadt-Besetzung"):
        Zieht eine Armee auf ein Hex mit einem FEINDLICHEN Stadt-Gebäude
        (City oder Camp), wird die normale Bewegung/der normale
        Army-vs-Army-Kampf NICHT ausgeloest. Stattdessen:

          1. RequestRoute liefert weiterhin die Route (unveraendert) - die
             Vorschau zeigt dem Spieler, wie weit er kommt.
          2. ConfirmMove prueft VOR der Bewegung, ob das ERREICHBARE Ziel-Hex
             (also das Hex, das die Armee diese Runde tatsaechlich erreichen
             wuerde) eine feindliche Stadt/ein feindliches Camp traegt:
               - Diplomatie-Check: nur im ECHTEN Krieg (State.WAR) erlaubt,
                 NICHT bei Neutral oder Allianz (strenger als der normale
                 Armee-Kampf, der auch bei Neutral kaempft).
               - Ist das nicht erfuellt: Bewegung wird abgelehnt, Meldung an
                 den Client.
               - Ist das erfuellt: statt die Bewegung sofort auszufuehren,
                 wird dem Client zunaechst ein Bestaetigungs-Popup geschickt
                 (CityAttackPopup) und auf die Antwort (RequestAttackCity)
                 gewartet. Die normale Bewegung wird in diesem Fall NICHT
                 gestartet.
          3. RequestAttackCity (Client -> Server, {armyId, targetQ, targetR,
             confirmed}):
               - confirmed = false -> Abbrechen, Bewegungsbefehl verworfen.
               - confirmed = true  -> Sonderfall 0 Buerger: sofortige
                 Uebernahme (kein Kampf). Sonst: Armee 1 Hex VOR die Stadt
                 bewegen (das ist bereits das erreichbare Hex direkt davor,
                 siehe finalStopHex), Buergerwehr erstellen, CombatSystem.
                 StartCombat() mit siegeInfo aufrufen.

    Die eigentliche Besetzungs-Logik NACH dem Kampf (Besitzerwechsel,
    Buergerverluste, Bau-Queue leeren, Punkte, Hauptstadt-Elimination) laeuft
    komplett in CombatSystem.EndCombat()/ResolveCitySiege() - dieser Handler
    ist nur fuer den Popup-Flow VOR dem Kampf zustaendig.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArmyData = require(script.Parent:WaitForChild("ArmyData"))
local MovementSystem = require(script.Parent:WaitForChild("MovementSystem"))
local MovementOrderData = require(script.Parent:WaitForChild("MovementOrderData"))
local CombatData = require(script.Parent:WaitForChild("CombatData"))
local CombatSystem = require(script.Parent:WaitForChild("CombatSystem"))
local CityData = require(script.Parent:WaitForChild("CityData"))
local CampData = require(script.Parent:WaitForChild("CampData"))
local ArmySystem = require(script.Parent:WaitForChild("ArmySystem"))
local UnitData = require(script.Parent:WaitForChild("UnitData"))
local ArmyStats = require(script.Parent:WaitForChild("ArmyStats"))
local ArmyModelMover = require(script.Parent:WaitForChild("ArmyModelMover"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local DiplomacySystem = require(script.Parent:WaitForChild("DiplomacySystem"))
local DiplomacyConfig = require(ReplicatedStorage:WaitForChild("DiplomacyConfig"))
local FogOfWarSystem = require(script.Parent:WaitForChild("FogOfWarSystem"))

local dataRemotes = ReplicatedStorage:WaitForChild("DataRemotes", 30)

local function dataRemote(name)
	return dataRemotes and dataRemotes:FindFirstChild(name) or nil
end

local requestRouteRemote = ReplicatedStorage:WaitForChild("RequestRoute")
local confirmMoveRemote = ReplicatedStorage:WaitForChild("ConfirmMove")
local cancelMoveRemote = ReplicatedStorage:WaitForChild("CancelMove")
local requestAttackCityRemote = ReplicatedStorage:WaitForChild("RequestAttackCity", 10)

-- Pending-Bestaetigungen: {[armyId] = { q, r, targetType, targetRecord,
--   defenderOwner, stopQ, stopR }}
-- Wird gesetzt, sobald das Popup an den Client geschickt wurde, und beim
-- Abbrechen/Bestaetigen/erneutem RequestRoute wieder geleert. Vorab
-- deklariert, damit requestRouteRemote (unten) sie ebenfalls aufraeumen kann.
local pendingCityAttacks = {}

local function isArmyOwnedBy(armyId, player)
	local army = ArmyData.GetArmy(armyId)
	if not army then return false end
	return army.owner == player
end

requestRouteRemote.OnServerInvoke = function(player, armyId, targetQ, targetR, isRefresh)
	if not isArmyOwnedBy(armyId, player) then
		warn("[MovementHandler] " .. player.Name .. " besitzt Army " .. tostring(armyId) .. " nicht")
		return nil
	end

	local army = ArmyData.GetArmy(armyId)
	if not army then return nil end

	-- NEW: an army that is locked in a turn based combat cannot be routed.
	if CombatData.IsInCombat(armyId) then
		return { path = nil, reason = "Armee ist im Kampf" }
	end

	if not MovementSystem.CanEnterHex(targetQ, targetR) then
		return { path = nil, reason = "Hex nicht betretbar" }
	end

	local path, totalCost = MovementSystem.CalculatePath(army.q, army.r, targetQ, targetR)

	if not path then
		return { path = nil, reason = "Kein Pfad gefunden" }
	end

	local movementPoints = army.stats and army.stats.Movement or 0
	local reachableSteps = MovementSystem.GetReachableSteps(path, movementPoints)

	if not isRefresh then
		if MovementOrderData.HasActiveOrder(armyId) then
			MovementOrderData.CancelOrder(armyId)
		end
		MovementOrderData.CreateOrder(armyId, targetQ, targetR, path)
		-- Neue Route angefordert -> ein evtl. noch offenes Stadt-Angriffs-Popup
		-- fuer diese Armee ist ungueltig geworden.
		pendingCityAttacks[armyId] = nil
	end

	print("[MovementHandler] Route für Army " .. armyId .. ": " .. #path .. " Hexes, " .. totalCost .. " Kosten, " .. reachableSteps .. " erreichbar" .. (isRefresh and " [refresh]" or ""))

	return {
		path = path,
		totalCost = totalCost,
		reachableSteps = reachableSteps,
		movementPoints = movementPoints,
	}
end

--------------------------------------------------------------------------------
-- getEnemyCityOrCamp(q, r, attackerOwner) -> "city"|"camp", cityOrCampRecord, ownerPlayer
-- Nil, wenn kein feindliches Stadt-Gebaeude auf dem Hex steht (eigene/
-- neutrale/allierte Gebaeude zaehlen NICHT als Ziel).
--------------------------------------------------------------------------------
local function getEnemyCityOrCamp(q, r, attackerOwner)
	local city = CityData.GetCityOnHex(q, r)
	if city and city.owner and city.owner ~= attackerOwner then
		return "city", city, city.owner
	end

	local camp = CampData.GetCampOnHex(q, r)
	if camp and camp.owner and camp.owner ~= attackerOwner then
		return "camp", camp, camp.owner
	end

	return nil, nil, nil
end

--------------------------------------------------------------------------------
-- countBastions(cityId) -> number
-- Zaehlt alle Bastion-Gebaeude in einer Stadt (fuer den Verteidigungs-Bonus
-- der Buergerwehr, siehe buildMilitiaDefenseBonus).
--------------------------------------------------------------------------------
local function countBastions(cityId)
	local city = CityData.GetCity(cityId)
	if not city or not city.buildings then return 0 end

	local count = 0
	for _, entry in ipairs(city.buildings) do
		if entry.buildingType == "Bastion" then
			count += 1
		end
	end
	return count
end

--------------------------------------------------------------------------------
-- buildMilitiaDefenseBonus(defenderOwner, cityId, campId, isCapital) -> number
-- Prozentualer Verteidigungs-Bonus (additiv, nicht multiplikativ), der auf
-- die Basis-Defense der Buergerwehr (UnitConfig.CitizenMilitia.Stats.Defense)
-- addiert wird:
--   City:           +15%
--   Hauptstadt:     +30% (15% City + 15% Extra, ersetzt den normalen
--                   City-Bonus statt ihn zu addieren)
--   Bastion:        +10% pro Bastion in der Stadt, gedeckelt bei +40%
--   Fortification:  +5% Bronze / +10% Silber / +15% Gold (Tech)
-- Camps erhalten NUR den Fortification-Tech-Bonus (kein City-/Bastion-Bonus,
-- da Camps keine Bastions bauen koennen).
--------------------------------------------------------------------------------
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

local function buildMilitiaDefenseBonus(defenderOwner, cityId, campId, isCapital)
	local bonus = 0

	if cityId then
		bonus += isCapital and 0.30 or 0.15

		local bastionCount = countBastions(cityId)
		bonus += math.min(bastionCount * 0.10, 0.40)
	end
	-- Camps: kein City-/Bastion-Bonus (nur Fortification-Tech unten).

	local tech = Tech()
	if tech and defenderOwner then
		-- FortificationBonus liefert bereits 0.10/0.20/0.30 fuer
		-- Bronze/Silber/Gold (siehe TechConfig.Fortification) - die
		-- Aufgabenstellung will hier ABWEICHEND davon 5%/10%/15% fuer die
		-- Buergerwehr speziell. Da GetSpecial nur die Summe ueber alle
		-- erreichten Stufen liefert (0.10 bei Bronze, 0.30 bei Bronze+Silber+
		-- Gold gleichzeitig unmoeglich, da nur 1 Stufe je Tech aktiv sein
		-- kann), wird der volle TechConfig-Wert halbiert uebernommen, um die
		-- vorgegebenen 5/10/15% exakt zu treffen.
		local fortBonus = tech.GetSpecial(defenderOwner, "FortificationBonus")
		bonus += fortBonus * 0.5
	end

	return bonus
end

--------------------------------------------------------------------------------
-- createMilitiaArmy(defenderOwner, citizenCount, q, r, defenseBonus) -> armyId?
-- Erstellt eine temporaere, UNSICHTBARE (kein ArmySpawner/kein 3D-Model)
-- Buergerwehr-Armee mit min(citizenCount, 8) CitizenMilitia-Units. Die Armee
-- wird direkt auf dem Stadt-/Camp-Hex "platziert" (rein als Datensatz - das
-- Hex traegt schon die eigentliche Armee des Verteidigers nicht, da Staedte
-- selbst keine Armee-Eintraege im HexData.army-Feld belegen).
--------------------------------------------------------------------------------
local function createMilitiaArmy(defenderOwner, citizenCount, q, r, defenseBonus)
	local militiaCount = math.min(math.max(0, citizenCount), 8)
	if militiaCount <= 0 then return nil end

	-- ArmySystem.SpawnArmy legt nur den Datensatz an (HexData.army = armyId,
	-- KEIN 3D-Model im Workspace - das entsteht ausschliesslich ueber
	-- ArmySpawner.placeArmyModel/RefreshArmyModel, die hier bewusst NIE
	-- aufgerufen werden). Die Militia ist damit fuer den Spieler unsichtbar,
	-- existiert aber als vollwertiger Kampf-Teilnehmer. HexData.army wird
	-- beim Kampfende automatisch wieder geleert (ArmySystem.DeleteArmy in
	-- CombatSystem.ResolveCitySiege).
	local armyId = ArmySystem.SpawnArmy(defenderOwner, q, r)
	if not armyId then
		warn("[MovementHandler] Buergerwehr-Armee konnte nicht erstellt werden (Hex belegt?)")
		return nil
	end

	for _ = 1, militiaCount do
		local unitId = UnitData.CreateUnit("CitizenMilitia", defenderOwner)
		if unitId then
			-- Verteidigungs-Bonus additiv auf die Basis-Defense der Einheit
			-- anwenden (gecappt durch UnitData/CombatSystem bei 70%).
			local unit = UnitData.GetUnit(unitId)
			if unit then
				unit.defense = math.clamp((unit.defense or 0) + math.floor(defenseBonus * 100 + 0.5), 0, 70)
			end
			ArmySystem.AddUnit(armyId, unitId)
		end
	end

	local army = ArmyData.GetArmy(armyId)
	if not army or #army.units == 0 then
		pcall(ArmySystem.DeleteArmy, armyId)
		return nil
	end

	ArmyStats.Recalculate(armyId)

	-- WICHTIG: Buergerwehr ist NICHT sichtbar auf dem Hex - kein
	-- ArmySpawner.SpawnUnit/placeArmyModel, kein 3D-Model im Workspace. Sie
	-- existiert nur als Kampf-Datensatz fuer die Dauer der Belagerung.
	return armyId
end

--------------------------------------------------------------------------------
-- immediateOccupation(attackerArmyId, q, r, targetType, targetRecord, defenderOwner)
-- Sonderfall 0 Buerger: kein Kampf noetig, sofortige Uebernahme. Die Armee
-- rueckt direkt auf das Stadt-Hex vor.
--------------------------------------------------------------------------------
local function immediateOccupation(attackerArmyId, q, r, targetType, targetRecord, defenderOwner)
	local attackerArmy = ArmyData.GetArmy(attackerArmyId)
	if not attackerArmy then return end
	local attackerOwner = attackerArmy.owner

	if targetType == "city" then
		CityData.ClearBuildQueue(targetRecord.id)

		local wasCapital = defenderOwner
			and PlayerData.GetCapitalCityId(defenderOwner) == targetRecord.id

		if wasCapital and defenderOwner then
			local VictorySystem = require(script.Parent:WaitForChild("VictorySystem"))
			-- EliminatePlayer setzt city.owner NUR auf nil (neutral) - die
			-- Stadt (inkl. Province) muss danach explizit an den Eroberer
			-- uebertragen werden, sonst bleibt sie besitzlos/neutral.
			pcall(VictorySystem.EliminatePlayer, defenderOwner, attackerOwner, "Hauptstadt erobert (unbewohnt)")
			if attackerOwner then
				CityData.SetOwner(targetRecord.id, attackerOwner)
				if targetRecord.provinceId then
					local ClaimSystem = require(script.Parent:WaitForChild("ClaimSystem"))
					pcall(ClaimSystem.ClaimProvince, attackerOwner, targetRecord.provinceId)
				end
			end
		else
			CityData.SetOwner(targetRecord.id, attackerOwner)
			if targetRecord.provinceId and defenderOwner and attackerOwner then
				local ClaimSystem = require(script.Parent:WaitForChild("ClaimSystem"))
				pcall(ClaimSystem.TransferProvince, defenderOwner, attackerOwner, targetRecord.provinceId)
			end
		end

		if _G.NotifyCityStatsChanged then
			_G.NotifyCityStatsChanged(targetRecord.id)
		end
	elseif targetType == "camp" then
		CampData.SetOwner(targetRecord.id, attackerOwner)
		if targetRecord.provinceId and defenderOwner and attackerOwner then
			local ClaimSystem = require(script.Parent:WaitForChild("ClaimSystem"))
			pcall(ClaimSystem.TransferProvince, defenderOwner, attackerOwner, targetRecord.provinceId)
		end
	end

	if attackerOwner then
		local PointSystem = require(script.Parent:WaitForChild("PointSystem"))
		local VictoryConfig = require(ReplicatedStorage:WaitForChild("VictoryConfig"))
		pcall(PointSystem.AwardPoints, attackerOwner, "CitySiegeWon", VictoryConfig.ACTIVE_POINTS.CitySiegeWon)
	end

	-- Armee auf das Stadt-Hex vorruecken (freie Bewegung, kein Kampf).
	if ArmySystem.MoveArmy(attackerArmyId, q, r, true) then
		ArmyModelMover.MoveModelToHex(attackerArmyId, q, r)
	end

	if attackerOwner then pcall(FogOfWarSystem.UpdateVision, attackerOwner) end
	if defenderOwner then pcall(FogOfWarSystem.UpdateVision, defenderOwner) end

	local cityAttackResult = dataRemote("CityAttackResult")
	if cityAttackResult and attackerOwner then
		cityAttackResult:FireClient(attackerOwner, {
			cityId = targetRecord.id,
			result = "win",
			casualties = 0,
			newOwner = attackerOwner.UserId,
			unopposed = true,
		})
	end
	if cityAttackResult and defenderOwner then
		cityAttackResult:FireClient(defenderOwner, {
			cityId = targetRecord.id,
			result = "lose",
			casualties = 0,
			newOwner = attackerOwner and attackerOwner.UserId or nil,
			unopposed = true,
		})
	end

	print("[MovementHandler] Unbewohnte(s) " .. targetType .. " " .. tostring(targetRecord.id)
		.. " kampflos von " .. tostring(attackerOwner and attackerOwner.Name) .. " uebernommen")
end

--------------------------------------------------------------------------------
-- tryStartCitySiege(player, armyId, order) -> true (Belagerungs-Popup
-- ausgeloest, normale Bewegung wird NICHT gestartet), false (kein
-- Stadt-Ziel, normale Bewegung soll ganz normal weiterlaufen)
--------------------------------------------------------------------------------
local function tryStartCitySiege(player, armyId, order)
	local army = ArmyData.GetArmy(armyId)
	if not army then return false end

	-- Inkl. TECH-Bonus (Road Building), damit dasselbe Ziel-Hex geprueft wird,
	-- das MovementSystem.MoveArmyAlongPath tatsaechlich anlaufen wuerde.
	local movementPoints = MovementSystem.GetEffectiveMovementPoints(armyId)
	local reachableSteps = MovementSystem.GetReachableSteps(order.fullPath, movementPoints)
	if reachableSteps <= 0 then return false end

	local finalHex = order.fullPath[1 + reachableSteps]
	if not finalHex then return false end

	-- Steht auf dem Ziel-Hex bereits eine (feindliche oder verbuendete) Armee,
	-- hat der normale Armee-vs-Armee-Kampf/die normale Koexistenz-Bewegung
	-- IMMER Vorrang vor der Stadt-Belagerung (siehe MovementSystem.
	-- MoveArmyAlongPath) - die Buergerwehr wird nur erzeugt, wenn das
	-- Stadt-/Camp-Hex unbewacht ist.
	if ArmyData.GetArmyOnHex(finalHex.q, finalHex.r) then return false end

	local targetType, targetRecord, defenderOwner = getEnemyCityOrCamp(finalHex.q, finalHex.r, player)
	if not targetType then return false end

	-- Diplomatie: Stadt-Angriff NUR im echten Krieg. Neutral/Allianz -> Blockade.
	local relation = DiplomacySystem.GetRelation(player, defenderOwner)
	if relation ~= DiplomacyConfig.STATE.WAR then
		MovementOrderData.CompleteOrder(armyId)
		local cityAttackResult = dataRemote("CityAttackResult")
		if cityAttackResult then
			cityAttackResult:FireClient(player, {
				cityId = targetRecord.id,
				result = "blocked",
				reason = "Du kannst diesen Spieler nicht angreifen.",
			})
		end
		print("[MovementHandler] Stadt-Angriff blockiert (" .. tostring(relation)
			.. "): " .. player.Name .. " -> " .. tostring(defenderOwner and defenderOwner.Name))
		return true
	end

	-- Das Hex UNMITTELBAR vor der Stadt (letztes freies Hex des erreichbaren
	-- Pfad-Abschnitts) - dort bleibt die Armee bei Bestaetigung stehen.
	local stopStep = reachableSteps - 1
	local stopHex = order.fullPath[1 + stopStep]

	pendingCityAttacks[armyId] = {
		q = finalHex.q,
		r = finalHex.r,
		targetType = targetType,
		targetRecord = targetRecord,
		defenderOwner = defenderOwner,
		stopQ = stopHex and stopHex.q or army.q,
		stopR = stopHex and stopHex.r or army.r,
	}

	local citizenCount = (targetType == "city")
		and (tonumber(targetRecord.population) or 0)
		or (tonumber(targetRecord.citizenCount) or 0)

	local isCapital = defenderOwner
		and targetType == "city"
		and PlayerData.GetCapitalCityId(defenderOwner) == targetRecord.id

	local popup = dataRemote("CityAttackPopup")
	if popup then
		popup:FireClient(player, {
			armyId = armyId,
			targetQ = finalHex.q,
			targetR = finalHex.r,
			cityName = targetRecord.name,
			isCapital = isCapital == true,
			defenderName = defenderOwner and defenderOwner.Name or "?",
			citizenCount = citizenCount,
			unopposed = citizenCount <= 0,
		})
	end

	print("[MovementHandler] Stadt-Angriffs-Popup gesendet: " .. player.Name .. " -> "
		.. tostring(targetRecord.name) .. " (" .. citizenCount .. " Buerger)")

	return true
end

--------------------------------------------------------------------------------
-- tryStartCitySiegeForOrder(order) -> true (Popup ausgeloest, Bewegung
-- diese Runde NICHT starten), false (kein Stadt-Ziel erreichbar)
-- Duenner Wrapper um tryStartCitySiege, der den Besitzer der Armee aus der
-- Order aufloest - wird sowohl von confirmMoveRemote (1. Runde) als auch von
-- ContinueAllOrders (Folgerunden) genutzt, damit eine mehrrundige Bewegung
-- eine Stadt/ein Camp niemals unbemerkt in einer spaeteren Runde passiert.
--------------------------------------------------------------------------------
local function tryStartCitySiegeForOrder(order)
	local army = ArmyData.GetArmy(order.armyId)
	if not army or not army.owner then return false end

	local ok, siegeTriggered = pcall(tryStartCitySiege, army.owner, order.armyId, order)
	if not ok then
		warn("[MovementHandler] Stadt-Angriff-Check fehlgeschlagen: " .. tostring(siegeTriggered))
		return false
	end
	return siegeTriggered == true
end

confirmMoveRemote.OnServerEvent:Connect(function(player, armyId)
	if not isArmyOwnedBy(armyId, player) then return end

	-- NEW: block confirmations while the army is fighting.
	if CombatData.IsInCombat(armyId) then
		warn("[MovementHandler] Army " .. tostring(armyId) .. " ist im Kampf - keine Bewegung")
		return
	end

	local order = MovementOrderData.GetOrder(armyId)
	if not order then
		warn("[MovementHandler] Keine Route für Army " .. tostring(armyId))
		return
	end

	if order.confirmed then
		warn("[MovementHandler] Route für Army " .. armyId .. " bereits bestätigt")
		return
	end

	MovementOrderData.ConfirmOrder(armyId)

	-- Stadt-/Camp-Angriff abfangen: Popup statt sofortiger Bewegung.
	if tryStartCitySiegeForOrder(order) then
		return
	end

	MovementSystem.MoveArmyAlongPath(armyId, order.fullPath, nil, 1)

	print("[MovementHandler] Army " .. armyId .. " Bewegung bestätigt und ausgeführt")
end)

cancelMoveRemote.OnServerEvent:Connect(function(player, armyId)
	if not isArmyOwnedBy(armyId, player) then return end

	pendingCityAttacks[armyId] = nil
	MovementOrderData.CancelOrder(armyId)
	print("[MovementHandler] Route für Army " .. armyId .. " abgebrochen")
end)

--------------------------------------------------------------------------------
-- RequestAttackCity (Client -> Server): Antwort auf das CityAttackPopup.
--------------------------------------------------------------------------------
if requestAttackCityRemote then
	requestAttackCityRemote.OnServerEvent:Connect(function(player, armyId, targetQ, targetR, confirmed)
		if not isArmyOwnedBy(armyId, player) then return end

		local pending = pendingCityAttacks[armyId]
		pendingCityAttacks[armyId] = nil

		if not pending or pending.q ~= targetQ or pending.r ~= targetR then
			warn("[MovementHandler] RequestAttackCity: keine passende Anfrage fuer Army " .. tostring(armyId))
			MovementOrderData.CompleteOrder(armyId)
			return
		end

		if not confirmed then
			-- Abbrechen -> Bewegungsbefehl wird abgebrochen.
			MovementOrderData.CompleteOrder(armyId)
			print("[MovementHandler] Stadt-Angriff von " .. player.Name .. " abgebrochen")
			return
		end

		local citizenCount = (pending.targetType == "city")
			and (tonumber(pending.targetRecord.population) or 0)
			or (tonumber(pending.targetRecord.citizenCount) or 0)

		-- SONDERFALL 0 BUERGER: kein Kampf, sofortige Uebernahme.
		if citizenCount <= 0 then
			MovementOrderData.CompleteOrder(armyId)
			local okOcc, errOcc = pcall(immediateOccupation, armyId, pending.q, pending.r,
				pending.targetType, pending.targetRecord, pending.defenderOwner)
			if not okOcc then
				warn("[MovementHandler] Sofortige Uebernahme fehlgeschlagen: " .. tostring(errOcc))
			end
			return
		end

		-- 1) Armee einen Schritt VOR die Stadt bewegen (nicht auf das Hex).
		MovementOrderData.CompleteOrder(armyId)
		local army = ArmyData.GetArmy(armyId)
		if army and (army.q ~= pending.stopQ or army.r ~= pending.stopR) then
			if ArmySystem.MoveArmy(armyId, pending.stopQ, pending.stopR) then
				ArmyModelMover.MoveModelToHex(armyId, pending.stopQ, pending.stopR)
				pcall(FogOfWarSystem.UpdateVision, player)
			end
		end

		-- 2) Buergerwehr erstellen (unsichtbar) mit Verteidigungs-Boni.
		local isCapital = pending.defenderOwner
			and pending.targetType == "city"
			and PlayerData.GetCapitalCityId(pending.defenderOwner) == pending.targetRecord.id

		local defenseBonus = buildMilitiaDefenseBonus(pending.defenderOwner,
			pending.targetType == "city" and pending.targetRecord.id or nil,
			pending.targetType == "camp" and pending.targetRecord.id or nil,
			isCapital == true)

		local militiaArmyId = createMilitiaArmy(pending.defenderOwner, citizenCount,
			pending.q, pending.r, defenseBonus)

		if not militiaArmyId then
			warn("[MovementHandler] Buergerwehr konnte nicht erstellt werden - Angriff abgebrochen")
			return
		end

		-- 3) Kampf starten (Angreifer = Spieler-Armee, Verteidiger = Militia).
		local siegeInfo = {
			cityId = pending.targetType == "city" and pending.targetRecord.id or nil,
			campId = pending.targetType == "camp" and pending.targetRecord.id or nil,
			hexQ = pending.q,
			hexR = pending.r,
			initialCitizens = citizenCount,
		}

		local startedOk, combatId, startReason = pcall(CombatSystem.StartCombat,
			armyId, militiaArmyId, pending.q, pending.r, siegeInfo)

		if not startedOk or not combatId then
			warn("[MovementHandler] Belagerungs-Kampf konnte nicht gestartet werden: "
				.. tostring(combatId or startReason))
			pcall(ArmySystem.DeleteArmy, militiaArmyId)
			return
		end

		print("[MovementHandler] Belagerung gestartet: " .. player.Name .. " greift "
			.. tostring(pending.targetRecord.name) .. " an (Combat " .. tostring(combatId) .. ")")
	end)
else
	warn("[MovementHandler] RequestAttackCity Remote fehlt - Stadt-Besetzung deaktiviert")
end

local MovementHandler = {}

function MovementHandler.ContinueAllOrders()
	local orders = MovementOrderData.GetConfirmedOrders()
	local moved = 0

	for _, order in ipairs(orders) do
		-- Ein offenes Stadt-Angriffs-Popup blockiert die automatische
		-- Rundenfortsetzung dieser Armee - sonst wuerde die Bewegung im
		-- Hintergrund weiterlaufen, waehrend der Spieler noch entscheidet.
		if not order.completed and not pendingCityAttacks[order.armyId] then
			local startStep = order.currentStep or 1

			if startStep < #order.fullPath then
				-- Auch in Folgerunden abfangen: eine mehrrundige Bewegung
				-- koennte diese Runde ERSTMALS eine feindliche Stadt/ein
				-- Camp erreichen (Bewegungspunkte wurden zu Rundenbeginn
				-- neu aufgefuellt).
				if tryStartCitySiegeForOrder(order) then
					-- Popup ausgeloest - diese Armee zaehlt bewusst NICHT
					-- als "moved", die Bewegung wartet auf die Antwort.
				else
					local ok, err = pcall(function()
						MovementSystem.MoveArmyAlongPath(
							order.armyId, order.fullPath, nil, startStep)
					end)

					if ok then
						moved = moved + 1
					else
						warn("[MovementHandler] Fehler bei Army " .. tostring(order.armyId)
							.. ": " .. tostring(err))
					end
				end
			else
				MovementOrderData.CompleteOrder(order.armyId)
			end
		end
	end

	if moved > 0 then
		print("[MovementHandler] " .. moved .. " Armeen setzen ihre Bewegung fort")
	end
	return moved
end

_G.ContinueAllMovementOrders = MovementHandler.ContinueAllOrders

print("[MovementHandler] Bereit. Bewegungen laufen automatisch zu Rundenbeginn weiter.")
