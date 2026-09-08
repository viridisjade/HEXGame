--[[
    JobAssignmentController (LocalScript)
    Ort: StarterGui > CityGui > CityFrame > JobAssignmentController
    
    Verschiebt Bürger zwischen den Jobs per Klick auf die Job-Labels.
    
    BEDIENUNG
      1. Klick auf ein Job-Label  -> wird QUELLE (gelber Glow),
                                     alle möglichen ZIELE leuchten grün
      2. Klick auf dieselbe Quelle -> Abbruch, alles zurück
      3. Klick auf ein grünes Ziel -> Bürger wird verschoben (Server-Request)
      4. Klick auf ein graues Ziel -> ignoriert (Ziel ist voll)
    
    ANZEIGE pro Label:  "Farmer: 2/3"   (zugewiesen / verfügbare Slots)
    
    ERWARTETE GUI (wird NICHT verändert, nur ergänzt):
      CityGui > CityFrame
        ├── FarmerLabel     (TextLabel)
        ├── WorkerLabel     (TextLabel)
        ├── TraderLabel     (TextLabel)
        └── ScientistLabel  (TextLabel)
    
    Automatisch ergänzt werden pro Label (falls nicht vorhanden):
      - "JobGlow"  (UIStroke)  -> farbiger Rahmen für Quelle/Ziel
      - "MoveLabel" (TextLabel) -> kleiner Hinweistext unter dem Label
    
    Benötigt:
      ReplicatedStorage > CityDataCache        (ModuleScript)
      ReplicatedStorage > ClientState          (ModuleScript, als "State")
      ReplicatedStorage > DataRemotes > RequestMoveCitizen (RemoteEvent)
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local CityDataCache = require(ReplicatedStorage:WaitForChild("CityDataCache"))
local State = require(ReplicatedStorage:WaitForChild("ClientState"))

local remotes = ReplicatedStorage:WaitForChild("DataRemotes")
local requestMoveCitizen = remotes:WaitForChild("RequestMoveCitizen")

local cityFrame = script.Parent

--------------------------------------------------------------------------------
-- KONFIGURATION
--------------------------------------------------------------------------------
local CONFIG = {
	-- Farben
	COLOR_SOURCE      = Color3.fromRGB(255, 210, 60),   -- Quelle (gelb)
	COLOR_TARGET      = Color3.fromRGB(80, 240, 110),   -- gültiges Ziel (grün)
	COLOR_BLOCKED     = Color3.fromRGB(150, 150, 150),  -- volles Ziel (grau)
	COLOR_IDLE        = Color3.fromRGB(255, 255, 255),

	GLOW_THICKNESS    = 2,
	TWEEN_TIME        = 0.15,

	-- Schutz gegen Klick-Spam (Sekunden)
	MOVE_COOLDOWN     = 0.25,

	-- Anzeigetexte
	TEXT_SOURCE       = "Ziel wählen...",
	TEXT_TARGET       = "hierhin",
	TEXT_BLOCKED      = "voll",
}

-- Reihenfolge + Anzeigenamen der Jobs
local JOBS = {
	{ key = "farmer",    label = "FarmerLabel",    display = "Farmer" },
	{ key = "worker",    label = "WorkerLabel",    display = "Worker" },
	{ key = "trader",    label = "TraderLabel",    display = "Trader" },
	{ key = "scientist", label = "ScientistLabel", display = "Scientist" },
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------
local slots = {}            -- slots[jobKey] = { label, glow, moveLabel, button }
local selectedSource = nil  -- jobKey der Quelle oder nil
local lastCity = nil        -- zuletzt empfangene Stadt-Daten
local lastMoveAt = 0        -- Zeitpunkt der letzten Verschiebung (Cooldown)

--------------------------------------------------------------------------------
-- SETUP: Glow + MoveLabel an jedes Job-Label hängen
-- Verändert die bestehende Struktur NICHT, ergänzt sie nur.
--------------------------------------------------------------------------------
local function setupSlot(job)
	local label = cityFrame:FindFirstChild(job.label)
	if not label then
		warn("[JobAssignment] FEHLT: CityFrame > " .. job.label)
		return nil
	end

	-- Glow (UIStroke) ergänzen
	local glow = label:FindFirstChild("JobGlow")
	if not glow then
		glow = Instance.new("UIStroke")
		glow.Name = "JobGlow"
		glow.Thickness = CONFIG.GLOW_THICKNESS
		glow.Color = CONFIG.COLOR_IDLE
		glow.Transparency = 1          -- unsichtbar bis gebraucht
		glow.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		glow.Parent = label
	end

	-- MoveLabel (Hinweistext) ergänzen
	local moveLabel = label:FindFirstChild("MoveLabel")
	if not moveLabel then
		moveLabel = Instance.new("TextLabel")
		moveLabel.Name = "MoveLabel"
		moveLabel.Size = UDim2.new(1, 0, 0, 14)
		moveLabel.Position = UDim2.new(0, 0, 1, 0)
		moveLabel.BackgroundTransparency = 1
		moveLabel.Font = Enum.Font.SourceSansBold
		moveLabel.TextSize = 12
		moveLabel.TextColor3 = CONFIG.COLOR_TARGET
		moveLabel.TextXAlignment = label.TextXAlignment
		moveLabel.Text = ""
		moveLabel.Visible = false
		moveLabel.ZIndex = label.ZIndex + 1
		moveLabel.Parent = label
	end

	-- Klickfläche: TextButton über dem Label (Label selbst bleibt unangetastet)
	local button = label:FindFirstChild("JobClickArea")
	if not button then
		button = Instance.new("TextButton")
		button.Name = "JobClickArea"
		button.Size = UDim2.fromScale(1, 1)
		button.BackgroundTransparency = 1
		button.Text = ""
		button.AutoButtonColor = false
		button.ZIndex = label.ZIndex + 2
		button.Parent = label
	end

	return {
		key = job.key,
		display = job.display,
		label = label,
		glow = glow,
		moveLabel = moveLabel,
		button = button,
	}
end

for _, job in ipairs(JOBS) do
	local slot = setupSlot(job)
	if slot then
		slots[job.key] = slot
	end
end

--------------------------------------------------------------------------------
-- Hilfsfunktionen
--------------------------------------------------------------------------------
local function getJobCount(city, jobKey)
	if not city or not city.jobs then return 0 end
	return tonumber(city.jobs[jobKey]) or 0
end

local function getSlotCount(city, jobKey)
	if not city or not city.jobSlots then return 0 end
	return tonumber(city.jobSlots[jobKey]) or 0
end

-- Kann von fromJob nach toJob verschoben werden?
-- Gleiche Regeln wie serverseitig in CityPopulationSystem.MoveCitizen,
-- damit gar nicht erst abgelehnte Requests rausgehen.
local function canMove(city, fromJob, toJob)
	if not city then return false end
	if fromJob == toJob then return false end
	if getJobCount(city, fromJob) < 1 then return false end
	if getJobCount(city, toJob) >= getSlotCount(city, toJob) then return false end
	return true
end

local function setGlow(slot, color, visible)
	if not slot or not slot.glow then return end
	slot.glow.Color = color
	TweenService:Create(
		slot.glow,
		TweenInfo.new(CONFIG.TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Transparency = visible and 0 or 1 }
	):Play()
end

local function setHint(slot, text, color)
	if not slot or not slot.moveLabel then return end
	if text == nil or text == "" then
		slot.moveLabel.Visible = false
		slot.moveLabel.Text = ""
		return
	end
	slot.moveLabel.Text = text
	slot.moveLabel.TextColor3 = color or CONFIG.COLOR_TARGET
	slot.moveLabel.Visible = true
end

--------------------------------------------------------------------------------
-- ANZEIGE: Zahlen aktualisieren (zugewiesen / Slots)
--------------------------------------------------------------------------------
local function refreshNumbers(city)
	if not city then return end

	for jobKey, slot in pairs(slots) do
		local assigned = getJobCount(city, jobKey)
		local available = getSlotCount(city, jobKey)

		slot.label.Text = slot.display .. ": " .. assigned .. "/" .. available

		-- Volle Jobs dezent kennzeichnen (nur wenn keine Auswahl läuft)
		if not selectedSource then
			if available > 0 and assigned >= available then
				slot.label.TextTransparency = 0.25
			else
				slot.label.TextTransparency = 0
			end
		end
	end
end

--------------------------------------------------------------------------------
-- AUSWAHL: Quelle setzen / Ziele markieren / zurücksetzen
--------------------------------------------------------------------------------
local function clearSelection()
	selectedSource = nil
	for _, slot in pairs(slots) do
		setGlow(slot, CONFIG.COLOR_IDLE, false)
		setHint(slot, nil)
		slot.label.TextTransparency = 0
	end
	refreshNumbers(lastCity)
end

local function selectSource(jobKey)
	local city = lastCity
	if not city then return end

	-- Ohne Bürger im Quell-Job gibt es nichts zu verschieben
	if getJobCount(city, jobKey) < 1 then
		local slot = slots[jobKey]
		if slot then
			setGlow(slot, CONFIG.COLOR_BLOCKED, true)
			setHint(slot, "niemand hier", CONFIG.COLOR_BLOCKED)
			task.delay(0.8, function()
				if selectedSource ~= jobKey then
					setGlow(slot, CONFIG.COLOR_IDLE, false)
					setHint(slot, nil)
				end
			end)
		end
		return
	end

	selectedSource = jobKey

	for key, slot in pairs(slots) do
		if key == jobKey then
			-- Quelle: gelb
			setGlow(slot, CONFIG.COLOR_SOURCE, true)
			setHint(slot, CONFIG.TEXT_SOURCE, CONFIG.COLOR_SOURCE)
			slot.label.TextTransparency = 0
		elseif canMove(city, jobKey, key) then
			-- Gültiges Ziel: grün
			setGlow(slot, CONFIG.COLOR_TARGET, true)
			setHint(slot, CONFIG.TEXT_TARGET, CONFIG.COLOR_TARGET)
			slot.label.TextTransparency = 0
		else
			-- Volles/ungültiges Ziel: grau + gedimmt
			setGlow(slot, CONFIG.COLOR_BLOCKED, true)
			setHint(slot, CONFIG.TEXT_BLOCKED, CONFIG.COLOR_BLOCKED)
			slot.label.TextTransparency = 0.4
		end
	end
end

--------------------------------------------------------------------------------
-- VERSCHIEBEN
--------------------------------------------------------------------------------
local function moveCitizen(fromJob, toJob)
	local city = lastCity
	if not city then return end

	-- Cooldown gegen Klick-Spam
	if tick() - lastMoveAt < CONFIG.MOVE_COOLDOWN then return end

	if not canMove(city, fromJob, toJob) then
		return
	end

	lastMoveAt = tick()

	-- Optimistisches lokales Update: Zahlen springen sofort,
	-- der Server bestätigt gleich darauf über CityStatsChanged.
	city.jobs[fromJob] = getJobCount(city, fromJob) - 1
	city.jobs[toJob] = getJobCount(city, toJob) + 1

	requestMoveCitizen:FireServer(city.id, fromJob, toJob)

	clearSelection()
	refreshNumbers(city)

	print("[JobAssignment] " .. fromJob .. " -> " .. toJob)
end

--------------------------------------------------------------------------------
-- KLICK-LOGIK
--------------------------------------------------------------------------------
local function onJobClicked(jobKey)
	if not lastCity then return end

	if not selectedSource then
		-- 1. Klick: Quelle wählen
		selectSource(jobKey)
	elseif selectedSource == jobKey then
		-- 2. Klick auf dieselbe: Abbruch
		clearSelection()
	else
		-- Klick auf anderes Label: verschieben (canMove prüft intern)
		moveCitizen(selectedSource, jobKey)
	end
end

for jobKey, slot in pairs(slots) do
	slot.button.MouseButton1Click:Connect(function()
		onJobClicked(jobKey)
	end)
end

--------------------------------------------------------------------------------
-- DATEN: eventbasiert über den CityDataCache (kein Polling!)
--------------------------------------------------------------------------------
CityDataCache.OnUpdated:Connect(function(city)
	lastCity = city

	if not city then
		clearSelection()
		return
	end

	-- Während einer laufenden Auswahl nur die Ziel-Markierung nachziehen,
	-- damit die Auswahl durch ein Server-Update nicht wegspringt.
	if selectedSource then
		if getJobCount(city, selectedSource) < 1 then
			clearSelection()
		else
			selectSource(selectedSource)
		end
	else
		refreshNumbers(city)
	end
end)

-- Auswahl aufheben, sobald die Stadt gewechselt/abgewählt wird
State.OnChanged:Connect(function()
	clearSelection()
end)

-- Initialzustand
lastCity = CityDataCache.Get()
if lastCity then
	refreshNumbers(lastCity)
end

print("[JobAssignmentController] Bereit. Klick auf ein Job-Label startet die Zuweisung.")