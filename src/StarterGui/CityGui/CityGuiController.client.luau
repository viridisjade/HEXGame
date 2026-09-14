--[[
    CityGuiController (LocalScript)
    Ort: StarterGui > CityGui > CityGuiController

    KOMPLETT CODE-GENERIERTE CityGui im Fantasy-Stil (wie DiplomacyGui,
    VictoryGui, TechTreeGui): alle Elemente werden per Instance.new()
    erzeugt, nichts wird mehr manuell in Studio gebaut.

    LAYOUT (3 Spalten):
      Spalte 1 (25%)  RESSOURCEN     - Food/Industry/Gold/Research + Bevölkerung/Wachstum
      Spalte 2 (30%)  ARBEITSPLÄTZE  - Farmer/Worker/Trader/Scientist (klickbar, gleiche Logik wie vorher)
      Spalte 3 (45%)  BAU-QUEUE      - Aktives Item + Warteschlange + Gebäude bauen (2 Kategorien) + Units rekrutieren

    SUB-SCRIPTS (CityStatsSync, GrowthBarController, JobAssignmentController,
    ResourceOverviewController): ihre komplette Funktionalität wurde HIER
    integriert (ein einziger Controller, wie bei den anderen *Gui-Controllern
    im Projekt). Die 4 Dateien existieren als Dateien weiterhin (Deprecated-
    Stubs, siehe deren Kommentare), werden aber als GUI-Instanzen beim
    Spielstart mit allen anderen alten CityGui-Children per Destroy()
    entfernt (siehe Cleanup-Block unten) - sie laufen also nie tatsächlich.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

--------------------------------------------------------------------------------
-- GUI-Wurzel finden + sofort verstecken (Failsafe)
--------------------------------------------------------------------------------
local cityGui = script.Parent:IsA("ScreenGui")
	and script.Parent
	or script.Parent:FindFirstAncestorWhichIsA("ScreenGui")

if not cityGui then
	warn("[CityGuiController] CityGui ScreenGui nicht gefunden")
	return
end

cityGui.Enabled = false
cityGui.ResetOnSpawn = false
cityGui.IgnoreGuiInset = true

--------------------------------------------------------------------------------
-- Abhängigkeiten
--------------------------------------------------------------------------------
local State = require(ReplicatedStorage:WaitForChild("ClientState"))
local CityBuildState = require(ReplicatedStorage:WaitForChild("CityBuildState"))
local UnitSpawnState = require(ReplicatedStorage:WaitForChild("UnitSpawnState"))
local UnitConfig = require(ReplicatedStorage:WaitForChild("UnitConfig"))
local CityDataCache = require(ReplicatedStorage:WaitForChild("CityDataCache"))

local DataRemotes = ReplicatedStorage:WaitForChild("DataRemotes")
local getBuildingCostsRemote = DataRemotes:FindFirstChild("GetBuildingCosts")
local getEmpireDataRemote = DataRemotes:FindFirstChild("GetEmpireData")
local requestInstantBuyRemote = DataRemotes:FindFirstChild("RequestInstantBuy")
local requestCancelBuildOrderRemote = DataRemotes:FindFirstChild("RequestCancelBuildOrder")
local requestMoveCitizenRemote = DataRemotes:FindFirstChild("RequestMoveCitizen")

--------------------------------------------------------------------------------
-- FANTASY-FARBSCHEMA
--------------------------------------------------------------------------------
local COLORS = {
	windowBg     = Color3.fromRGB(35, 28, 22),
	panelBg      = Color3.fromRGB(50, 40, 32),
	panelBorder  = Color3.fromRGB(120, 90, 50),

	headerBg     = Color3.fromRGB(80, 60, 40),
	headerText   = Color3.fromRGB(255, 220, 150),

	food         = Color3.fromRGB(150, 200, 100),
	industry     = Color3.fromRGB(220, 140, 60),
	gold         = Color3.fromRGB(255, 200, 80),
	research     = Color3.fromRGB(150, 180, 250),

	dotFilled    = Color3.fromRGB(255, 220, 150),
	dotEmpty     = Color3.fromRGB(80, 65, 50),

	btnNormal    = Color3.fromRGB(70, 55, 40),
	btnHover     = Color3.fromRGB(100, 80, 55),
	btnPressed   = Color3.fromRGB(50, 40, 30),
	btnDisabled  = Color3.fromRGB(45, 40, 35),
	btnText      = Color3.fromRGB(255, 220, 150),

	buyNormal    = Color3.fromRGB(180, 130, 40),
	buyHover     = Color3.fromRGB(220, 160, 60),
	buyBorder    = Color3.fromRGB(255, 220, 100),

	negative     = Color3.fromRGB(255, 110, 100),
	positive     = Color3.fromRGB(150, 220, 120),

	textDim      = Color3.fromRGB(200, 185, 165),
}

local FONT_TITLE = Enum.Font.FredokaOne
local FONT_VALUE = Enum.Font.GothamBold
local FONT_DESC  = Enum.Font.Gotham

--------------------------------------------------------------------------------
-- KONFIGURATION: Gebäude / Units / Jobs / Ressourcen
--------------------------------------------------------------------------------
-- HINWEIS: industryCost hier ist nur der BASIS-Fallback-Wert, falls die
-- dynamischen (skalierten) Kosten nicht vom Server geladen werden konnten.
-- Der tatsächlich angezeigte Preis kommt aus buildingCosts[type].actualCost.
local ECONOMY_BUILDINGS = {
	{ type = "Farm",       name = "Farm",       icon = "🏗️", industryCost = 15 },
	{ type = "Factory",    name = "Factory",    icon = "🏭", industryCost = 15 },
	{ type = "Market",     name = "Market",     icon = "🛒", industryCost = 20 },
	{ type = "Laboratory", name = "Laboratory", icon = "🧪", industryCost = 20 },
}
local DEFENSE_BUILDINGS = {
	{ type = "Bastion", name = "Bastion", icon = "🏰", industryCost = 30 },
}
local ALL_BUILDINGS = {}
for _, b in ipairs(ECONOMY_BUILDINGS) do table.insert(ALL_BUILDINGS, b) end
for _, b in ipairs(DEFENSE_BUILDINGS) do table.insert(ALL_BUILDINGS, b) end

local buildingByType = {}
for _, b in ipairs(ALL_BUILDINGS) do buildingByType[b.type] = b end

local UNIT_ORDER = { "Tribe", "StoneWarrior", "StonespearFighter", "Rider" }
local UNIT_ICONS = {
	Tribe = "🪓",
	StonespearFighter = "🔱",
	StoneWarrior = "⚔️",
	Rider = "🐎",
}

local JOBS = {
	{ key = "farmer",    name = "Farmer",    icon = "👨‍🌾" },
	{ key = "worker",    name = "Worker",    icon = "🔨" },
	{ key = "trader",    name = "Trader",    icon = "🛒" },
	{ key = "scientist", name = "Scientist", icon = "🧪" },
}

local RESOURCES = {
	{ key = "food",     name = "Food",     icon = "🍞", color = COLORS.food },
	{ key = "industry", name = "Industry", icon = "⚙️", color = COLORS.industry },
	{ key = "gold",     name = "Gold",     icon = "💰", color = COLORS.gold },
	{ key = "research", name = "Research", icon = "🔬", color = COLORS.research },
}

--------------------------------------------------------------------------------
-- HILFSFUNKTION: ensure (erzeugt nur, falls noch nicht vorhanden)
--------------------------------------------------------------------------------
local function ensure(parent, class, name, setup)
	local existing = parent:FindFirstChild(name)
	if existing then return existing end
	local obj = Instance.new(class)
	obj.Name = name
	if setup then setup(obj) end
	obj.Parent = parent
	return obj
end

local function makeCorner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = parent
	return c
end

local function makeStroke(parent, thickness, color, transparency)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness or 2
	s.Color = color or COLORS.panelBorder
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

--------------------------------------------------------------------------------
-- ALTE GUI VOLLSTÄNDIG ENTFERNEN (CLEANUP)
--
-- Das komplette alte, manuell gebaute CityFrame (inkl. seiner rbxm-Kinder
-- und der 4 alten Sub-Scripts CityStatsSync/GrowthBarController/
-- JobAssignmentController/ResourceOverviewController) wird beim Start
-- entfernt. Zusätzlich werden defensiv ALLE anderen Children direkt unter
-- CityGui gelöscht (falls z.B. eines der alten Sub-Scripts jemals direkt
-- unter CityGui statt unter CityFrame lag) - nur das Controller-Script
-- selbst (dieses Script) bleibt unangetastet.
--
-- WICHTIG: Ab hier darf NICHTS mehr auf die alten Elemente zugreifen
-- (z.B. cityFrame:FindFirstChild("FarmerLabel")). Alle GUI-Elemente
-- werden im Folgenden komplett neu per Code direkt unter der CityGui
-- (ScreenGui) erzeugt.
--------------------------------------------------------------------------------
for _, child in ipairs(cityGui:GetChildren()) do
	if child ~= script then
		child:Destroy()
	end
end

--------------------------------------------------------------------------------
-- WURZEL-FENSTER
--------------------------------------------------------------------------------
local cityWindow = ensure(cityGui, "Frame", "CityWindow", function(f)
	f.Size = UDim2.new(0.8, 0, 0.85, 0)
	f.Position = UDim2.new(0.5, 0, 0.5, 0)
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.BackgroundColor3 = COLORS.windowBg
	f.BackgroundTransparency = 0.1
	f.BorderSizePixel = 0
end)
makeCorner(cityWindow, 12)
makeStroke(cityWindow, 3, COLORS.panelBorder)

--------------------------------------------------------------------------------
-- HEADER
--------------------------------------------------------------------------------
local header = ensure(cityWindow, "Frame", "Header", function(f)
	f.Size = UDim2.new(1, 0, 0, 52)
	f.Position = UDim2.new(0, 0, 0, 0)
	f.BackgroundColor3 = COLORS.headerBg
	f.BorderSizePixel = 0
end)
makeCorner(header, 12)

-- Fix: die untere Rundung des Headers soll nicht sichtbar sein (Rechteck
-- unten anschließen). Wir legen ein kleines Deckel-Frame drüber.
ensure(header, "Frame", "CornerFix", function(f)
	f.Size = UDim2.new(1, 0, 0, 12)
	f.Position = UDim2.new(0, 0, 1, -12)
	f.BackgroundColor3 = COLORS.headerBg
	f.BorderSizePixel = 0
	f.ZIndex = 0
end)

local nameLabel = ensure(header, "TextLabel", "CityNameLabel", function(l)
	l.Size = UDim2.new(1, -70, 1, 0)
	l.Position = UDim2.new(0, 16, 0, 0)
	l.BackgroundTransparency = 1
	l.Font = FONT_TITLE
	l.TextSize = 24
	l.TextColor3 = COLORS.headerText
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Text = "🏛️ Stadt"
end)

local closeButton = ensure(header, "TextButton", "CloseButton", function(b)
	b.Size = UDim2.fromOffset(36, 36)
	b.Position = UDim2.new(1, -46, 0.5, -18)
	b.BackgroundColor3 = Color3.fromRGB(120, 55, 55)
	b.Font = FONT_VALUE
	b.TextSize = 18
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = "✕"
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
end)
makeCorner(closeButton, 6)

local markupLabel = ensure(header, "TextLabel", "MarkupLabel", function(l)
	l.Size = UDim2.new(1, -70, 0, 16)
	l.Position = UDim2.new(0, 16, 1, -18)
	l.BackgroundTransparency = 1
	l.Font = FONT_DESC
	l.TextSize = 12
	l.TextColor3 = Color3.fromRGB(255, 200, 120)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = ""
	l.Visible = false
end)

closeButton.Activated:Connect(function()
	State.Clear()
end)

--------------------------------------------------------------------------------
-- BODY (3 Spalten)
--------------------------------------------------------------------------------
local body = ensure(cityWindow, "Frame", "Body", function(f)
	f.Size = UDim2.new(1, -20, 1, -64)
	f.Position = UDim2.new(0, 10, 0, 58)
	f.BackgroundTransparency = 1
end)
ensure(body, "UIListLayout", "Layout", function(l)
	l.FillDirection = Enum.FillDirection.Horizontal
	l.Padding = UDim.new(0, 10)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.VerticalAlignment = Enum.VerticalAlignment.Top
end)

--------------------------------------------------------------------------------
-- Panel-Fabrik: erzeugt eine ScrollingFrame-Spalte im Fantasy-Look
--------------------------------------------------------------------------------
local function createColumn(name, widthScale, layoutOrder)
	local col = ensure(body, "ScrollingFrame", name, function(f)
		f.Size = UDim2.new(widthScale, 0, 1, 0)
		f.BackgroundColor3 = COLORS.panelBg
		f.BorderSizePixel = 0
		f.ScrollBarThickness = 6
		f.ScrollBarImageColor3 = COLORS.panelBorder
		f.AutomaticCanvasSize = Enum.AutomaticSize.Y
		f.CanvasSize = UDim2.new()
		f.LayoutOrder = layoutOrder
	end)
	makeCorner(col, 8)
	makeStroke(col, 2, COLORS.panelBorder)
	ensure(col, "UIPadding", "Padding", function(p)
		p.PaddingTop = UDim.new(0, 10)
		p.PaddingBottom = UDim.new(0, 10)
		p.PaddingLeft = UDim.new(0, 10)
		p.PaddingRight = UDim.new(0, 10)
	end)
	ensure(col, "UIListLayout", "Layout", function(l)
		l.Padding = UDim.new(0, 8)
		l.SortOrder = Enum.SortOrder.LayoutOrder
	end)
	return col
end

-- Spalte 1: Ressourcen (25%), Spalte 2: Arbeitsplätze (30%), Spalte 3: Bau (45%)
-- (Summe < 1.0, damit für die 10px-Listenabstände Platz bleibt.)
local resourceColumn = createColumn("ResourceColumn", 0.24, 1)
local jobsColumn = createColumn("JobsColumn", 0.29, 2)
local buildColumn = createColumn("BuildColumn", 0.45, 3)

--------------------------------------------------------------------------------
-- Section-Header-Fabrik (kleine Fantasy-Überschrift innerhalb einer Spalte)
--------------------------------------------------------------------------------
local function sectionHeader(parent, text, layoutOrder)
	local l = Instance.new("TextLabel")
	l.Name = "SectionHeader_" .. tostring(layoutOrder)
	l.LayoutOrder = layoutOrder
	l.Size = UDim2.new(1, 0, 0, 22)
	l.BackgroundTransparency = 1
	l.Font = FONT_VALUE
	l.TextSize = 15
	l.TextColor3 = COLORS.headerText
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.Parent = parent
	return l
end

--------------------------------------------------------------------------------
-- SPALTE 1: RESSOURCEN
--------------------------------------------------------------------------------
sectionHeader(resourceColumn, "📊 RESSOURCEN", 1)

local resourceRows = {}
for i, res in ipairs(RESOURCES) do
	local row = Instance.new("Frame")
	row.Name = "Resource_" .. res.key
	row.LayoutOrder = 10 + i
	row.Size = UDim2.new(1, 0, 0, 40)
	row.BackgroundTransparency = 1
	row.Parent = resourceColumn

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Name = "NameLabel"
	nameLbl.Size = UDim2.new(1, 0, 0, 18)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Font = FONT_VALUE
	nameLbl.TextSize = 14
	nameLbl.TextColor3 = res.color
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.Text = res.icon .. " " .. res.name
	nameLbl.Parent = row

	local valueLbl = Instance.new("TextLabel")
	valueLbl.Name = "ValueLabel"
	valueLbl.Size = UDim2.new(1, 0, 0, 18)
	valueLbl.Position = UDim2.new(0, 0, 0, 18)
	valueLbl.BackgroundTransparency = 1
	valueLbl.Font = FONT_DESC
	valueLbl.TextSize = 13
	valueLbl.TextColor3 = res.color
	valueLbl.TextXAlignment = Enum.TextXAlignment.Left
	valueLbl.Text = "+0/Runde"
	valueLbl.Parent = row

	resourceRows[res.key] = valueLbl
end

-- Bevölkerung + Wachstum
sectionHeader(resourceColumn, "👥 BEVÖLKERUNG", 20)

local populationLabel = Instance.new("TextLabel")
populationLabel.Name = "PopulationLabel"
populationLabel.LayoutOrder = 21
populationLabel.Size = UDim2.new(1, 0, 0, 18)
populationLabel.BackgroundTransparency = 1
populationLabel.Font = FONT_VALUE
populationLabel.TextSize = 14
populationLabel.TextColor3 = COLORS.headerText
populationLabel.TextXAlignment = Enum.TextXAlignment.Left
populationLabel.Text = "Bev: 0"
populationLabel.Parent = resourceColumn

local growthTextLabel = Instance.new("TextLabel")
growthTextLabel.Name = "GrowthTextLabel"
growthTextLabel.LayoutOrder = 22
growthTextLabel.Size = UDim2.new(1, 0, 0, 16)
growthTextLabel.BackgroundTransparency = 1
growthTextLabel.Font = FONT_DESC
growthTextLabel.TextSize = 12
growthTextLabel.TextColor3 = COLORS.textDim
growthTextLabel.TextXAlignment = Enum.TextXAlignment.Left
growthTextLabel.TextWrapped = true
growthTextLabel.Text = "Wächst in ? Runden"
growthTextLabel.Parent = resourceColumn

local growthBarBg = Instance.new("Frame")
growthBarBg.Name = "GrowthBarBg"
growthBarBg.LayoutOrder = 23
growthBarBg.Size = UDim2.new(1, 0, 0, 14)
growthBarBg.BackgroundColor3 = COLORS.dotEmpty
growthBarBg.BorderSizePixel = 0
growthBarBg.Parent = resourceColumn
makeCorner(growthBarBg, 4)

local growthBarFill = Instance.new("Frame")
growthBarFill.Name = "Fill"
growthBarFill.Size = UDim2.new(0, 0, 1, 0)
growthBarFill.BackgroundColor3 = COLORS.positive
growthBarFill.BorderSizePixel = 0
growthBarFill.Parent = growthBarBg
makeCorner(growthBarFill, 4)

--------------------------------------------------------------------------------
-- SPALTE 2: ARBEITSPLÄTZE
--------------------------------------------------------------------------------
sectionHeader(jobsColumn, "⚒️ ARBEITSPLÄTZE", 1)

local CONFIG_JOB = {
	COLOR_SOURCE  = Color3.fromRGB(255, 210, 60),
	COLOR_TARGET  = Color3.fromRGB(120, 220, 130),
	COLOR_BLOCKED = Color3.fromRGB(150, 150, 150),
	COLOR_IDLE    = COLORS.panelBorder,
	TWEEN_TIME    = 0.15,
	MOVE_COOLDOWN = 0.25,
}

local TweenService = game:GetService("TweenService")

local jobSlots = {}       -- jobKey -> { row, button, nameLbl, glow, hintLbl, dotsRow, key, display }
local selectedJobSource = nil
local lastMoveAt = 0

for i, job in ipairs(JOBS) do
	local row = Instance.new("Frame")
	row.Name = "Job_" .. job.key
	row.LayoutOrder = i
	row.Size = UDim2.new(1, 0, 0, 58)
	row.BackgroundColor3 = Color3.fromRGB(42, 34, 27)
	row.BorderSizePixel = 0
	row.Parent = jobsColumn
	makeCorner(row, 6)
	local glow = makeStroke(row, 2, CONFIG_JOB.COLOR_IDLE, 1)

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Name = "NameLabel"
	nameLbl.Size = UDim2.new(1, -12, 0, 20)
	nameLbl.Position = UDim2.new(0, 8, 0, 4)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Font = FONT_VALUE
	nameLbl.TextSize = 14
	nameLbl.TextColor3 = COLORS.headerText
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.Text = job.icon .. " " .. job.name .. "   0/0"
	nameLbl.Parent = row

	local hintLbl = Instance.new("TextLabel")
	hintLbl.Name = "HintLabel"
	hintLbl.Size = UDim2.new(1, -12, 0, 14)
	hintLbl.Position = UDim2.new(0, 8, 0, 22)
	hintLbl.BackgroundTransparency = 1
	hintLbl.Font = FONT_DESC
	hintLbl.TextSize = 11
	hintLbl.TextColor3 = CONFIG_JOB.COLOR_TARGET
	hintLbl.TextXAlignment = Enum.TextXAlignment.Left
	hintLbl.Text = ""
	hintLbl.Visible = false
	hintLbl.Parent = row

	local dotsRow = Instance.new("Frame")
	dotsRow.Name = "DotsRow"
	dotsRow.Size = UDim2.new(1, -12, 0, 14)
	dotsRow.Position = UDim2.new(0, 8, 1, -18)
	dotsRow.BackgroundTransparency = 1
	dotsRow.Parent = row
	ensure(dotsRow, "UIListLayout", "Layout", function(l)
		l.FillDirection = Enum.FillDirection.Horizontal
		l.Padding = UDim.new(0, 3)
		l.SortOrder = Enum.SortOrder.LayoutOrder
	end)

	local clickButton = Instance.new("TextButton")
	clickButton.Name = "ClickArea"
	clickButton.Size = UDim2.fromScale(1, 1)
	clickButton.BackgroundTransparency = 1
	clickButton.Text = ""
	clickButton.AutoButtonColor = false
	clickButton.ZIndex = 3
	clickButton.Parent = row

	jobSlots[job.key] = {
		row = row, button = clickButton, nameLbl = nameLbl,
		glow = glow, hintLbl = hintLbl, dotsRow = dotsRow,
		key = job.key, display = job.name, icon = job.icon,
	}
end

local unemployedLabel = Instance.new("TextLabel")
unemployedLabel.Name = "UnemployedLabel"
unemployedLabel.LayoutOrder = 100
unemployedLabel.Size = UDim2.new(1, 0, 0, 20)
unemployedLabel.BackgroundTransparency = 1
unemployedLabel.Font = FONT_DESC
unemployedLabel.TextSize = 13
unemployedLabel.TextColor3 = COLORS.textDim
unemployedLabel.TextXAlignment = Enum.TextXAlignment.Left
unemployedLabel.Text = "Arbeitslos: 0"
unemployedLabel.Parent = jobsColumn

--------------------------------------------------------------------------------
-- JOB-LOGIK (identisch zum bisherigen JobAssignmentController, nur andere
-- visuelle Elemente)
--------------------------------------------------------------------------------
local lastCity = nil

local function getJobCount(city, jobKey)
	if not city or not city.jobs then return 0 end
	return tonumber(city.jobs[jobKey]) or 0
end

local function getSlotCount(city, jobKey)
	if not city or not city.jobSlots then return 0 end
	return tonumber(city.jobSlots[jobKey]) or 0
end

local function canMoveJob(city, fromJob, toJob)
	if not city then return false end
	if fromJob == toJob then return false end
	if getJobCount(city, fromJob) < 1 then return false end
	if getJobCount(city, toJob) >= getSlotCount(city, toJob) then return false end
	return true
end

local function setJobGlow(slot, color, visible)
	TweenService:Create(
		slot.glow,
		TweenInfo.new(CONFIG_JOB.TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Transparency = visible and 0 or 1 }
	):Play()
	slot.glow.Color = color
end

local function setJobHint(slot, text, color)
	if text == nil or text == "" then
		slot.hintLbl.Visible = false
		slot.hintLbl.Text = ""
		return
	end
	slot.hintLbl.Text = text
	slot.hintLbl.TextColor3 = color or CONFIG_JOB.COLOR_TARGET
	slot.hintLbl.Visible = true
end

local function refreshDots(slot, assigned, available)
	for _, child in ipairs(slot.dotsRow:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
	local maxDots = math.min(available, 20)
	for i = 1, maxDots do
		local dot = Instance.new("Frame")
		dot.Name = "Dot" .. i
		dot.LayoutOrder = i
		dot.Size = UDim2.fromOffset(10, 10)
		dot.BackgroundColor3 = (i <= assigned) and COLORS.dotFilled or COLORS.dotEmpty
		dot.BorderSizePixel = 0
		dot.Parent = slot.dotsRow
		makeCorner(dot, 5)
	end
end

local function refreshJobNumbers(city)
	if not city then return end
	local totalUnemployed = (tonumber(city.population) or 0)
	for jobKey, slot in pairs(jobSlots) do
		local assigned = getJobCount(city, jobKey)
		local available = getSlotCount(city, jobKey)
		totalUnemployed = totalUnemployed - assigned

		slot.nameLbl.Text = slot.icon .. " " .. slot.display .. "   " .. assigned .. "/" .. available
		refreshDots(slot, assigned, available)

		if not selectedJobSource then
			slot.nameLbl.TextTransparency = (available > 0 and assigned >= available) and 0.35 or 0
		end
	end
	unemployedLabel.Text = "Arbeitslos: " .. math.max(0, totalUnemployed)
end

local function clearJobSelection()
	selectedJobSource = nil
	for _, slot in pairs(jobSlots) do
		setJobGlow(slot, CONFIG_JOB.COLOR_IDLE, false)
		setJobHint(slot, nil)
		slot.nameLbl.TextTransparency = 0
	end
	refreshJobNumbers(lastCity)
end

local function selectJobSource(jobKey)
	local city = lastCity
	if not city then return end

	if getJobCount(city, jobKey) < 1 then
		local slot = jobSlots[jobKey]
		if slot then
			setJobGlow(slot, CONFIG_JOB.COLOR_BLOCKED, true)
			setJobHint(slot, "niemand hier", CONFIG_JOB.COLOR_BLOCKED)
			task.delay(0.8, function()
				if selectedJobSource ~= jobKey then
					setJobGlow(slot, CONFIG_JOB.COLOR_IDLE, false)
					setJobHint(slot, nil)
				end
			end)
		end
		return
	end

	selectedJobSource = jobKey

	for key, slot in pairs(jobSlots) do
		if key == jobKey then
			setJobGlow(slot, CONFIG_JOB.COLOR_SOURCE, true)
			setJobHint(slot, "Ziel wählen...", CONFIG_JOB.COLOR_SOURCE)
			slot.nameLbl.TextTransparency = 0
		elseif canMoveJob(city, jobKey, key) then
			setJobGlow(slot, CONFIG_JOB.COLOR_TARGET, true)
			setJobHint(slot, "hierhin", CONFIG_JOB.COLOR_TARGET)
			slot.nameLbl.TextTransparency = 0
		else
			setJobGlow(slot, CONFIG_JOB.COLOR_BLOCKED, true)
			setJobHint(slot, "voll", CONFIG_JOB.COLOR_BLOCKED)
			slot.nameLbl.TextTransparency = 0.4
		end
	end
end

local function moveJobCitizen(fromJob, toJob)
	local city = lastCity
	if not city then return end
	if tick() - lastMoveAt < CONFIG_JOB.MOVE_COOLDOWN then return end
	if not canMoveJob(city, fromJob, toJob) then return end

	lastMoveAt = tick()

	-- Optimistisches lokales Update
	city.jobs[fromJob] = getJobCount(city, fromJob) - 1
	city.jobs[toJob] = getJobCount(city, toJob) + 1

	if requestMoveCitizenRemote then
		requestMoveCitizenRemote:FireServer(city.id, fromJob, toJob)
	end

	clearJobSelection()
	refreshJobNumbers(city)
end

local function onJobClicked(jobKey)
	if not lastCity then return end
	if not selectedJobSource then
		selectJobSource(jobKey)
	elseif selectedJobSource == jobKey then
		clearJobSelection()
	else
		moveJobCitizen(selectedJobSource, jobKey)
	end
end

for jobKey, slot in pairs(jobSlots) do
	slot.button.MouseButton1Click:Connect(function()
		onJobClicked(jobKey)
	end)
end

--------------------------------------------------------------------------------
-- Generischer Button-Stil (Hover/Pressed/Disabled)
--------------------------------------------------------------------------------
local function wireButtonStyle(button, colorSet)
	button.AutoButtonColor = false
	button.BorderSizePixel = 0

	local function currentColors()
		if button:GetAttribute("Disabled") then
			return colorSet.disabled, 0.5
		end
		return colorSet.normal, 0
	end

	local normal = currentColors()
	button.BackgroundColor3 = normal

	button.MouseEnter:Connect(function()
		if button:GetAttribute("Disabled") then return end
		button.BackgroundColor3 = colorSet.hover
	end)
	button.MouseLeave:Connect(function()
		if button:GetAttribute("Disabled") then return end
		button.BackgroundColor3 = colorSet.normal
	end)
	button.MouseButton1Down:Connect(function()
		if button:GetAttribute("Disabled") then return end
		button.BackgroundColor3 = colorSet.pressed
	end)
	button.MouseButton1Up:Connect(function()
		if button:GetAttribute("Disabled") then return end
		button.BackgroundColor3 = colorSet.hover
	end)
end

local function setButtonEnabled(button, colorSet, enabled)
	button:SetAttribute("Disabled", not enabled)
	button.Active = enabled
	if enabled then
		button.BackgroundColor3 = colorSet.normal
		button.TextTransparency = 0
	else
		button.BackgroundColor3 = colorSet.disabled
		button.TextTransparency = 0.5
	end
end

local ACTION_COLORS = {
	normal = COLORS.btnNormal, hover = COLORS.btnHover,
	pressed = COLORS.btnPressed, disabled = COLORS.btnDisabled,
}

--------------------------------------------------------------------------------
-- SPALTE 3: BAU-QUEUE + GEBÄUDE + UNITS
--------------------------------------------------------------------------------

-- 1) AKTIVES ITEM + WARTESCHLANGE ----------------------------------------------
sectionHeader(buildColumn, "⚡ BAU-QUEUE", 1)

local queueEmptyLabel = Instance.new("TextLabel")
queueEmptyLabel.Name = "QueueEmptyLabel"
queueEmptyLabel.LayoutOrder = 2
queueEmptyLabel.Size = UDim2.new(1, 0, 0, 26)
queueEmptyLabel.BackgroundTransparency = 1
queueEmptyLabel.Font = FONT_DESC
queueEmptyLabel.TextSize = 13
queueEmptyLabel.TextColor3 = COLORS.textDim
queueEmptyLabel.TextXAlignment = Enum.TextXAlignment.Left
queueEmptyLabel.Text = "Keine Bau-Queue"
queueEmptyLabel.Visible = false
queueEmptyLabel.Parent = buildColumn

local activeQueueFrame = Instance.new("Frame")
activeQueueFrame.Name = "ActiveQueueFrame"
activeQueueFrame.LayoutOrder = 3
activeQueueFrame.AutomaticSize = Enum.AutomaticSize.Y
activeQueueFrame.Size = UDim2.new(1, 0, 0, 0)
activeQueueFrame.BackgroundColor3 = Color3.fromRGB(60, 48, 34)
activeQueueFrame.BorderSizePixel = 0
activeQueueFrame.Visible = false
activeQueueFrame.Parent = buildColumn
makeCorner(activeQueueFrame, 6)
makeStroke(activeQueueFrame, 2, COLORS.dotFilled, 0.2)
ensure(activeQueueFrame, "UIPadding", "Padding", function(p)
	p.PaddingTop = UDim.new(0, 8)
	p.PaddingBottom = UDim.new(0, 8)
	p.PaddingLeft = UDim.new(0, 8)
	p.PaddingRight = UDim.new(0, 8)
end)
ensure(activeQueueFrame, "UIListLayout", "Layout", function(l)
	l.Padding = UDim.new(0, 6)
	l.SortOrder = Enum.SortOrder.LayoutOrder
end)

local activeHeaderLabel = Instance.new("TextLabel")
activeHeaderLabel.Name = "ActiveHeaderLabel"
activeHeaderLabel.LayoutOrder = 1
activeHeaderLabel.Size = UDim2.new(1, 0, 0, 18)
activeHeaderLabel.BackgroundTransparency = 1
activeHeaderLabel.Font = FONT_VALUE
activeHeaderLabel.TextSize = 13
activeHeaderLabel.TextColor3 = COLORS.dotFilled
activeHeaderLabel.TextXAlignment = Enum.TextXAlignment.Left
activeHeaderLabel.Text = "⚡ Aktiv:"
activeHeaderLabel.Parent = activeQueueFrame

local activeNameLabel = Instance.new("TextLabel")
activeNameLabel.Name = "ActiveNameLabel"
activeNameLabel.LayoutOrder = 2
activeNameLabel.Size = UDim2.new(1, 0, 0, 20)
activeNameLabel.BackgroundTransparency = 1
activeNameLabel.Font = FONT_VALUE
activeNameLabel.TextSize = 15
activeNameLabel.TextColor3 = COLORS.headerText
activeNameLabel.TextXAlignment = Enum.TextXAlignment.Left
activeNameLabel.TextWrapped = true
activeNameLabel.Text = ""
activeNameLabel.Parent = activeQueueFrame

local activeProgressBg = Instance.new("Frame")
activeProgressBg.Name = "ActiveProgressBg"
activeProgressBg.LayoutOrder = 3
activeProgressBg.Size = UDim2.new(1, 0, 0, 14)
activeProgressBg.BackgroundColor3 = COLORS.dotEmpty
activeProgressBg.BorderSizePixel = 0
activeProgressBg.Parent = activeQueueFrame
makeCorner(activeProgressBg, 4)

local activeProgressFill = Instance.new("Frame")
activeProgressFill.Name = "Fill"
activeProgressFill.Size = UDim2.new(0, 0, 1, 0)
activeProgressFill.BackgroundColor3 = COLORS.industry
activeProgressFill.BorderSizePixel = 0
activeProgressFill.Parent = activeProgressBg
makeCorner(activeProgressFill, 4)

local activeProgressText = Instance.new("TextLabel")
activeProgressText.Name = "ActiveProgressText"
activeProgressText.Size = UDim2.fromScale(1, 1)
activeProgressText.BackgroundTransparency = 1
activeProgressText.Font = FONT_DESC
activeProgressText.TextSize = 11
activeProgressText.TextColor3 = Color3.new(1, 1, 1)
activeProgressText.Text = ""
activeProgressText.Parent = activeProgressBg

local buyButton = Instance.new("TextButton")
buyButton.Name = "InstantBuyButton"
buyButton.LayoutOrder = 4
buyButton.Size = UDim2.new(1, 0, 0, 30)
buyButton.Font = FONT_VALUE
buyButton.TextSize = 14
buyButton.TextColor3 = Color3.new(1, 1, 1)
buyButton.Text = "⚡ Sofort kaufen"
buyButton.Visible = false
buyButton.Parent = activeQueueFrame
makeCorner(buyButton, 6)
makeStroke(buyButton, 2, COLORS.buyBorder, 0.3)
wireButtonStyle(buyButton, { normal = COLORS.buyNormal, hover = COLORS.buyHover, pressed = COLORS.buyNormal, disabled = COLORS.btnDisabled })

buyButton.Activated:Connect(function()
	if buyButton:GetAttribute("Disabled") then return end
	local city = CityDataCache.Get()
	if not city or not requestInstantBuyRemote then return end
	requestInstantBuyRemote:FireServer(city.id)
end)

-- Warteschlange
local queueSubHeader = sectionHeader(buildColumn, "📋 Warteschlange:", 4)
queueSubHeader.Visible = false

local queueTotalLabel = Instance.new("TextLabel")
queueTotalLabel.Name = "QueueTotalLabel"
queueTotalLabel.LayoutOrder = 5
queueTotalLabel.Size = UDim2.new(1, 0, 0, 16)
queueTotalLabel.BackgroundTransparency = 1
queueTotalLabel.Font = FONT_DESC
queueTotalLabel.TextSize = 12
queueTotalLabel.TextColor3 = COLORS.textDim
queueTotalLabel.TextXAlignment = Enum.TextXAlignment.Left
queueTotalLabel.Text = ""
queueTotalLabel.Visible = false
queueTotalLabel.Parent = buildColumn

local queueGrid = Instance.new("Frame")
queueGrid.Name = "QueueGrid"
queueGrid.LayoutOrder = 6
queueGrid.AutomaticSize = Enum.AutomaticSize.Y
queueGrid.Size = UDim2.new(1, 0, 0, 0)
queueGrid.BackgroundTransparency = 1
queueGrid.Parent = buildColumn
local queueGridLayout = Instance.new("UIGridLayout")
queueGridLayout.CellSize = UDim2.fromOffset(76, 84)
queueGridLayout.CellPadding = UDim2.fromOffset(6, 6)
queueGridLayout.SortOrder = Enum.SortOrder.LayoutOrder
queueGridLayout.Parent = queueGrid

-- 2) GEBÄUDE BAUEN --------------------------------------------------------------
sectionHeader(buildColumn, "💰 WIRTSCHAFT", 10)

local buildingButtons = {}

local function createBuildingButton(parent, layoutOrder, buildingInfo)
	local btn = Instance.new("TextButton")
	btn.Name = buildingInfo.type .. "Button"
	btn.LayoutOrder = layoutOrder
	btn.Size = UDim2.new(1, 0, 0, 34)
	btn.Font = FONT_DESC
	btn.TextSize = 14
	btn.TextColor3 = COLORS.btnText
	btn.TextXAlignment = Enum.TextXAlignment.Left
	btn.Text = "  " .. buildingInfo.icon .. " " .. buildingInfo.name
	btn.Parent = parent
	makeCorner(btn, 6)
	wireButtonStyle(btn, ACTION_COLORS)

	btn.Activated:Connect(function()
		if btn:GetAttribute("Disabled") then return end
		local cityId = State.GetId(State.Kind.CITY)
		if not cityId then return end
		CityBuildState.Start(cityId, buildingInfo.type)
		cityGui.Enabled = false
	end)

	buildingButtons[buildingInfo.type] = btn
	return btn
end

for i, b in ipairs(ECONOMY_BUILDINGS) do
	createBuildingButton(buildColumn, 10 + i, b)
end

sectionHeader(buildColumn, "🛡️ VERTEIDIGUNG", 20)
for i, b in ipairs(DEFENSE_BUILDINGS) do
	createBuildingButton(buildColumn, 20 + i, b)
end

-- 3) UNITS REKRUTIEREN -----------------------------------------------------------
sectionHeader(buildColumn, "⚔️ UNITS REKRUTIEREN", 30)

local unitButtons = {}

for i, unitType in ipairs(UNIT_ORDER) do
	local unitData = UnitConfig.GetUnit(unitType)
	if unitData then
		local btn = Instance.new("TextButton")
		btn.Name = unitType .. "Button"
		btn.LayoutOrder = 30 + i
		btn.Size = UDim2.new(1, 0, 0, 34)
		btn.Font = FONT_DESC
		btn.TextSize = 14
		btn.TextColor3 = COLORS.btnText
		btn.TextXAlignment = Enum.TextXAlignment.Left
		btn.Text = "  " .. (UNIT_ICONS[unitType] or "⚔️") .. " " .. unitData.Name
		btn.Parent = buildColumn
		makeCorner(btn, 6)
		wireButtonStyle(btn, ACTION_COLORS)

		btn.Activated:Connect(function()
			if btn:GetAttribute("Disabled") then return end
			local cityId = State.GetId(State.Kind.CITY)
			if not cityId then return end
			UnitSpawnState.Start(cityId, unitType)
			cityGui.Enabled = false
		end)

		unitButtons[unitType] = { button = btn, industryCost = unitData.IndustryCost or 0, citizenCost = unitData.CitizenCost or 0, name = unitData.Name }
	end
end

--------------------------------------------------------------------------------
-- Sofortkauf: Preis-Formel (muss exakt mit ConstructionSystem.GetInstantBuyPrice
-- (Server) übereinstimmen)
--   basisPreis = industrieKosten * 1.5
--   fortschritt = industryProgress / industryCost (0..1)
--   preis = math.ceil(basisPreis * (1 - fortschritt))
--------------------------------------------------------------------------------
local function getInstantBuyPrice(order)
	if not order or order.status ~= "Building" then return nil end
	local industryCost = tonumber(order.industryCost) or 0
	if industryCost <= 0 then return nil end
	local progressAmount = tonumber(order.industryProgress) or 0
	local progress = math.clamp(progressAmount / industryCost, 0, 1)
	local baseCost = industryCost * 1.5
	return math.ceil(baseCost * (1 - progress)), progress
end

local function getOrderInfo(order)
	if order.orderType == "Unit" then
		local uCfg = UnitConfig.GetUnit(order.unitType)
		local icon = UNIT_ICONS[order.unitType] or "⚔️"
		return { name = uCfg and uCfg.Name or "Unit", icon = icon }
	else
		local info = buildingByType[order.buildingType]
		return { name = info and info.name or "Gebäude", icon = info and info.icon or "🏗️" }
	end
end

--------------------------------------------------------------------------------
-- Bau-Queue rendern
--------------------------------------------------------------------------------
local lastQueueSignature = nil

local function buildQueueSignature(city, currentGold)
	local queue = city.buildQueue or {}
	local parts = { "ind:" .. tostring(city.currentIndustryProduction or 0), "gold:" .. tostring(currentGold or 0) }
	for _, order in ipairs(queue) do
		table.insert(parts, table.concat({
			tostring(order.id), tostring(order.orderType), tostring(order.buildingType),
			tostring(order.unitType), tostring(order.industryProgress), tostring(order.industryCost),
			tostring(order.status),
		}, ":"))
	end
	return table.concat(parts, "|")
end

local function clearQueueGrid()
	for _, child in ipairs(queueGrid:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
end

local function renderBuildQueue(city, currentGold)
	local queue = city.buildQueue or {}
	local signature = buildQueueSignature(city, currentGold)
	if signature == lastQueueSignature then return end
	lastQueueSignature = signature

	clearQueueGrid()

	if #queue == 0 then
		queueEmptyLabel.Visible = true
		activeQueueFrame.Visible = false
		queueSubHeader.Visible = false
		queueTotalLabel.Visible = false
		return
	end

	queueEmptyLabel.Visible = false
	activeQueueFrame.Visible = true

	local industry = tonumber(city.currentIndustryProduction) or 0
	local activeOrder = queue[1]
	local activeInfo = getOrderInfo(activeOrder)

	-- Summe der einzeln (unabhängig voneinander) verbleibenden Runden ALLER
	-- Items - so wie im Task-Beispiel ("Gesamt: 8 Runden" = 3+3+2).
	local totalRounds = 0
	local totalIsInfinite = false
	for _, order in ipairs(queue) do
		local remaining = math.max(0, (order.industryCost or 0) - (order.industryProgress or 0))
		if industry > 0 then
			totalRounds = totalRounds + math.ceil(remaining / industry)
		else
			totalIsInfinite = true
		end
	end

	if activeOrder.status == "WaitingSpawn" then
		activeHeaderLabel.Text = "⚡ Aktiv:"
		activeNameLabel.Text = activeInfo.icon .. " " .. activeInfo.name .. " – wartet auf freies Spawn-Feld..."
		activeProgressFill.Size = UDim2.new(0, 0, 1, 0)
		activeProgressText.Text = ""
	else
		local progress = activeOrder.industryProgress or 0
		local cost = activeOrder.industryCost or 0
		local ratio = (cost > 0) and math.clamp(progress / cost, 0, 1) or 0
		local roundsLeft = (industry > 0) and math.max(1, math.ceil(math.max(0, cost - progress) / industry)) or nil

		activeHeaderLabel.Text = roundsLeft and ("⚡ Aktiv (" .. roundsLeft .. " Runden):") or "⚡ Aktiv (∞ Runden):"
		activeNameLabel.Text = activeInfo.icon .. " " .. activeInfo.name
		activeProgressFill.Size = UDim2.new(ratio, 0, 1, 0)
		activeProgressText.Text = progress .. " / " .. cost .. " Arbeit (" .. math.floor(ratio * 100) .. "%)"
	end

	-- Sofortkauf-Button
	local instantBuyPrice, instantBuyProgress = getInstantBuyPrice(activeOrder)
	if instantBuyPrice then
		local affordable = (currentGold or 0) >= instantBuyPrice
		local nearlyDone = (instantBuyProgress or 0) >= 0.95
		buyButton.Text = (nearlyDone and "⚡ Fertigstellen (" or "⚡ Kauf: ") .. instantBuyPrice .. "g)"
		buyButton.Visible = true
		setButtonEnabled(buyButton, { normal = COLORS.buyNormal, hover = COLORS.buyHover, pressed = COLORS.buyNormal, disabled = COLORS.btnDisabled }, affordable)
	else
		buyButton.Visible = false
	end

	-- Warteschlange (Position 2+)
	if #queue > 1 then
		queueSubHeader.Visible = true
		queueTotalLabel.Visible = true
		if totalIsInfinite then
			queueTotalLabel.Text = "Gesamt: ∞ Runden (keine Industrie)"
		else
			queueTotalLabel.Text = "Gesamt: " .. totalRounds .. " Runden"
		end

		for i = 2, #queue do
			local order = queue[i]
			local info = getOrderInfo(order)
			local remaining = math.max(0, (order.industryCost or 0) - (order.industryProgress or 0))
			local roundsForItem = (industry > 0) and math.ceil(remaining / industry) or nil

			local tile = Instance.new("Frame")
			tile.Name = "Tile_" .. tostring(order.id)
			tile.LayoutOrder = i
			tile.BackgroundColor3 = Color3.fromRGB(45, 36, 28)
			tile.BorderSizePixel = 0
			tile.Parent = queueGrid
			makeCorner(tile, 6)
			makeStroke(tile, 1, COLORS.panelBorder, 0.2)

			local iconLbl = Instance.new("TextLabel")
			iconLbl.Size = UDim2.new(1, 0, 0, 30)
			iconLbl.Position = UDim2.new(0, 0, 0, 4)
			iconLbl.BackgroundTransparency = 1
			iconLbl.Font = FONT_TITLE
			iconLbl.TextSize = 22
			iconLbl.Text = info.icon
			iconLbl.Parent = tile

			local nameLbl2 = Instance.new("TextLabel")
			nameLbl2.Size = UDim2.new(1, -6, 0, 16)
			nameLbl2.Position = UDim2.new(0, 3, 0, 34)
			nameLbl2.BackgroundTransparency = 1
			nameLbl2.Font = FONT_DESC
			nameLbl2.TextSize = 11
			nameLbl2.TextColor3 = COLORS.headerText
			nameLbl2.TextXAlignment = Enum.TextXAlignment.Center
			nameLbl2.TextTruncate = Enum.TextTruncate.AtEnd
			nameLbl2.Text = info.name
			nameLbl2.Parent = tile

			local roundsLbl = Instance.new("TextLabel")
			roundsLbl.Size = UDim2.new(1, -6, 0, 14)
			roundsLbl.Position = UDim2.new(0, 3, 0, 50)
			roundsLbl.BackgroundTransparency = 1
			roundsLbl.Font = FONT_DESC
			roundsLbl.TextSize = 11
			roundsLbl.TextColor3 = COLORS.textDim
			roundsLbl.TextXAlignment = Enum.TextXAlignment.Center
			roundsLbl.Text = roundsForItem and (roundsForItem .. " Runden") or "∞"
			roundsLbl.Parent = tile

			local removeBtn = Instance.new("TextButton")
			removeBtn.Name = "RemoveButton"
			removeBtn.Size = UDim2.fromOffset(18, 18)
			removeBtn.Position = UDim2.new(1, -20, 0, 2)
			removeBtn.BackgroundColor3 = Color3.fromRGB(120, 55, 55)
			removeBtn.Font = FONT_VALUE
			removeBtn.TextSize = 11
			removeBtn.TextColor3 = Color3.new(1, 1, 1)
			removeBtn.Text = "✕"
			removeBtn.BorderSizePixel = 0
			removeBtn.ZIndex = 5
			removeBtn.Parent = tile
			makeCorner(removeBtn, 4)

			removeBtn.Activated:Connect(function()
				if requestCancelBuildOrderRemote then
					requestCancelBuildOrderRemote:FireServer(city.id, order.id)
				end
			end)
		end
	else
		queueSubHeader.Visible = false
		queueTotalLabel.Visible = false
	end
end

--------------------------------------------------------------------------------
-- Gebäude-/Unit-Buttons aktualisieren (Preis + Ausgrauen)
--------------------------------------------------------------------------------
local function updateBuildingButtons(city, buildingCosts, currentGold, industry)
	for _, building in ipairs(ALL_BUILDINGS) do
		local btn = buildingButtons[building.type]
		if btn then
			local activeOrder = nil
			for _, order in ipairs(city.buildQueue or {}) do
				if order.status == "Building" and order.buildingType == building.type then
					activeOrder = order
					break
				end
			end

			local actualCost = building.industryCost
			if buildingCosts and buildingCosts[building.type] then
				actualCost = buildingCosts[building.type].actualCost
			end

			if activeOrder then
				btn.Text = "  " .. building.icon .. " " .. building.name .. "  (im Bau)"
				setButtonEnabled(btn, ACTION_COLORS, false)
			else
				btn.Text = "  " .. building.icon .. " " .. building.name .. "   " .. actualCost .. "🔨  [Bau]"
				-- Baukosten sind Industrie, nicht Gold: ein Gebäude kann immer
				-- angestoßen werden (es wird über Runden mit Industrie bezahlt).
				-- Ausgegraut wird nur, wenn schon ein Gebäude dieses Typs im
				-- Bau ist (oben behandelt).
				setButtonEnabled(btn, ACTION_COLORS, true)
			end
		end
	end
end

local function updateUnitButtons(city)
	for unitType, data in pairs(unitButtons) do
		local activeOrder = nil
		for _, order in ipairs(city.buildQueue or {}) do
			if order.status == "Building" and order.unitType == unitType then
				activeOrder = order
				break
			end
		end

		local citizenText = (data.citizenCost > 0) and (" (-" .. data.citizenCost .. " Einw.)") or ""

		if activeOrder then
			data.button.Text = "  " .. (UNIT_ICONS[unitType] or "⚔️") .. " " .. data.name .. "  (im Bau)"
			setButtonEnabled(data.button, ACTION_COLORS, false)
		else
			data.button.Text = "  " .. (UNIT_ICONS[unitType] or "⚔️") .. " " .. data.name .. "   " .. data.industryCost .. "🔨" .. citizenText .. "  [Rek]"
			-- Population-Check: genug Bürger übrig (mind. 1 muss bleiben)?
			local canAfford = (data.citizenCost <= 0) or ((tonumber(city.population) or 0) - data.citizenCost >= 1)
			setButtonEnabled(data.button, ACTION_COLORS, canAfford)
		end
	end
end

--------------------------------------------------------------------------------
-- RESSOURCEN + WACHSTUM AKTUALISIEREN
--------------------------------------------------------------------------------
local function computeGrowthInfo(city)
	local growthBar = tonumber(city.growthBar) or 0
	local threshold = tonumber(city.foodThreshold) or 30
	if threshold <= 0 then threshold = 30 end
	local surplus = tonumber(city.foodSurplus)
	if surplus == nil then
		surplus = (tonumber(city.currentFoodProduction) or 0) - (tonumber(city.currentFoodConsumption) or 0)
	end

	if surplus > 0 then
		local remaining = math.max(0, threshold - growthBar)
		local rounds = math.max(1, math.ceil(remaining / surplus))
		return { state = "growing", rounds = rounds, growthBar = growthBar, threshold = threshold }
	elseif surplus < 0 then
		local remaining = math.max(0, growthBar)
		local rounds = math.max(1, math.ceil(remaining / -surplus))
		return { state = "shrinking", rounds = rounds, growthBar = growthBar, threshold = threshold }
	else
		return { state = "stagnant", rounds = nil, growthBar = growthBar, threshold = threshold }
	end
end

local function updateResourcesColumn(city)
	local netFood = (tonumber(city.currentFoodProduction) or 0) - (tonumber(city.currentFoodConsumption) or 0)
	local sign = netFood >= 0 and "+" or ""
	resourceRows.food.Text = sign .. netFood .. "/Runde"
	resourceRows.food.TextColor3 = netFood >= 0 and COLORS.food or COLORS.negative

	local industry = tonumber(city.currentIndustryProduction) or 0
	resourceRows.industry.Text = "+" .. industry .. "/Runde"

	local gold = tonumber(city.currentGoldProduction) or 0
	resourceRows.gold.Text = "+" .. gold .. "/Runde"

	local research = tonumber(city.currentResearchProduction) or 0
	resourceRows.research.Text = "+" .. research .. "/Runde"

	local pop = tonumber(city.population) or 0
	local totalSlots = 0
	for _, slots in pairs(city.jobSlots or {}) do totalSlots = totalSlots + (tonumber(slots) or 0) end
	populationLabel.Text = "👥 Bev: " .. pop .. "/" .. totalSlots
	populationLabel.TextColor3 = (pop > totalSlots) and COLORS.negative or COLORS.headerText

	local growth = computeGrowthInfo(city)
	if growth.state == "growing" then
		growthTextLabel.Text = "Wächst in " .. growth.rounds .. " Runde" .. (growth.rounds == 1 and "" or "n")
		growthTextLabel.TextColor3 = COLORS.positive
		growthBarFill.BackgroundColor3 = COLORS.positive
	elseif growth.state == "shrinking" then
		growthTextLabel.Text = "Bevölkerung sinkt in " .. growth.rounds .. " Runde" .. (growth.rounds == 1 and "" or "n")
		growthTextLabel.TextColor3 = COLORS.negative
		growthBarFill.BackgroundColor3 = COLORS.negative
	else
		growthTextLabel.Text = "Kein Wachstum (Nahrung ausgeglichen)"
		growthTextLabel.TextColor3 = COLORS.textDim
		growthBarFill.BackgroundColor3 = COLORS.textDim
	end

	local pct = math.clamp(growth.growthBar / growth.threshold, 0, 1)
	growthBarFill.Size = UDim2.new(pct, 0, 1, 0)
end

--------------------------------------------------------------------------------
-- HAUPT-UPDATE
--------------------------------------------------------------------------------
local function updateStats(city)
	if not city then return end

	nameLabel.Text = "🏛️ " .. (city.name or ("City " .. city.id))
	lastCity = city

	updateResourcesColumn(city)

	if selectedJobSource then
		if getJobCount(city, selectedJobSource) < 1 then
			clearJobSelection()
		else
			selectJobSource(selectedJobSource)
		end
	else
		refreshJobNumbers(city)
	end

	-- Aktuelles Spieler-Gold laden (Sofortkauf-Button)
	local currentGold = 0
	if getEmpireDataRemote then
		local ok, empireData = pcall(function() return getEmpireDataRemote:InvokeServer() end)
		if ok and empireData then
			currentGold = tonumber(empireData.gold) or 0
		end
	end

	-- Dynamische (skalierte) Baukosten
	local buildingCosts = nil
	if getBuildingCostsRemote then
		local ok, costs = pcall(function() return getBuildingCostsRemote:InvokeServer(city.id) end)
		if ok then buildingCosts = costs end
	end

	if buildingCosts and buildingCosts._info and buildingCosts._info.stage and buildingCosts._info.stage > 1 then
		local multiplierText = string.format("%.1f", buildingCosts._info.multiplier or 1.0)
		markupLabel.Text = "Stadtaufschlag: Stufe " .. buildingCosts._info.stage .. " (x" .. multiplierText .. ", " .. buildingCosts._info.buildingCount .. " Gebäude)"
		markupLabel.Visible = true
	else
		markupLabel.Visible = false
	end

	local industry = tonumber(city.currentIndustryProduction) or 0
	updateBuildingButtons(city, buildingCosts, currentGold, industry)
	updateUnitButtons(city)
	renderBuildQueue(city, currentGold)
end

--------------------------------------------------------------------------------
-- Sichtbarkeit: rein Event-basiert (kein Polling!)
--------------------------------------------------------------------------------
local function clearStats()
	nameLabel.Text = "🏛️ Stadt"
	lastQueueSignature = nil
	clearJobSelection()
	lastCity = nil
end

local function showGui()
	if CityBuildState.IsPlacing() or UnitSpawnState.IsPlacing() then return end
	if not cityGui.Enabled then
		cityGui.Enabled = true
	end
	task.spawn(CityDataCache.Refresh)
end

local function hideGui()
	if cityGui.Enabled then
		cityGui.Enabled = false
		clearStats()
	end
end

State.OnChanged:Connect(function(kind, id)
	if kind == State.Kind.CITY and id then
		showGui()
	else
		hideGui()
	end
end)

CityBuildState.OnChanged:Connect(function(placement)
	if placement then
		cityGui.Enabled = false
	elseif State.Has(State.Kind.CITY) then
		showGui()
	end
end)

UnitSpawnState.OnChanged:Connect(function(placement)
	if placement then
		cityGui.Enabled = false
	elseif State.Has(State.Kind.CITY) then
		showGui()
	end
end)

CityDataCache.OnUpdated:Connect(function(city)
	if not city or not cityGui.Enabled then return end
	local success, err = pcall(updateStats, city)
	if not success then
		warn("[CityGuiController] Update Fehler: " .. tostring(err))
	end
end)

clearStats()
cityGui.Enabled = false

if State.Has(State.Kind.CITY) then
	showGui()
end

print("[CityGuiController] Bereit (code-generiert, Fantasy-Stil)")
