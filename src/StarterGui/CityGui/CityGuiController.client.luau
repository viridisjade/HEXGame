--[[
    CityGuiController (LocalScript)
    Ort: StarterGui > CityGui > CityGuiController
    
    Haupt-Controller für die CityGui:
    Zeigt City-Stats, erzeugt Gebäude- und Unit-Listen,
    startet Platzierungen, zeigt die BuildQueue.
--]]

-- HINWEIS: industryCost hier ist nur der BASIS-Fallback-Wert, falls die
-- dynamischen (skalierten) Kosten nicht vom Server geladen werden konnten
-- (siehe getBuildingCostsRemote weiter unten). Der tatsächlich angezeigte
-- Preis kommt aus buildingCosts[type].actualCost (BuildingCostSystem).
local CITY_BUILDINGS = {
	{ type = "Farm",       name = "Farm",       icon = "rbxassetid://FARM_ASSET_ID",    industryCost = 15 },
	{ type = "Factory",    name = "Factory",    icon = "rbxassetid://FACTORY_ASSET_ID", industryCost = 15 },
	{ type = "Market",     name = "Market",     icon = "rbxassetid://MARKET_ASSET_ID",  industryCost = 20 },
	{ type = "Laboratory", name = "Laboratory", icon = "rbxassetid://LAB_ASSET_ID",     industryCost = 20 },
	{ type = "Bastion",    name = "Bastion",    icon = "rbxassetid://BASTION_ASSET_ID", industryCost = 30 },
}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 1. GUI finden und sofort verstecken (Failsafe)
local cityGui = script.Parent:IsA("ScreenGui")
	and script.Parent
	or script.Parent:FindFirstAncestorWhichIsA("ScreenGui")

if not cityGui then
	warn("[CityGuiController] CityGui ScreenGui nicht gefunden")
	return
end

cityGui.Enabled = false

local cityFrame = cityGui:FindFirstChild("CityFrame")
if not cityFrame then
	warn("[CityGuiController] FEHLER: CityFrame fehlt in der GUI!")
	return
end

-- 2. Abhängigkeiten laden (WaitForChild - die Module existieren garantiert)
local State = require(ReplicatedStorage:WaitForChild("ClientState"))
local CityBuildState = require(ReplicatedStorage:WaitForChild("CityBuildState"))
local UnitSpawnState = require(ReplicatedStorage:WaitForChild("UnitSpawnState"))
local UnitConfig = require(ReplicatedStorage:WaitForChild("UnitConfig"))
local CityDataCache = require(ReplicatedStorage:WaitForChild("CityDataCache"))

local DataRemotes = ReplicatedStorage:WaitForChild("DataRemotes")
local getBuildingCostsRemote = DataRemotes:FindFirstChild("GetBuildingCosts")
local getEmpireDataRemote = DataRemotes:FindFirstChild("GetEmpireData")
local requestInstantBuyRemote = DataRemotes:FindFirstChild("RequestInstantBuy")

-- Stadtaufschlag-Hinweis (wird in updateStats befüllt)
local markupLabel = cityFrame:FindFirstChild("MarkupLabel")
if not markupLabel then
	markupLabel = Instance.new("TextLabel")
	markupLabel.Name = "MarkupLabel"
	markupLabel.Size = UDim2.new(1, 0, 0, 16)
	markupLabel.Position = UDim2.new(0, 10, 0, -18)
	markupLabel.BackgroundTransparency = 1
	markupLabel.Font = Enum.Font.SourceSansBold
	markupLabel.TextSize = 13
	markupLabel.TextColor3 = Color3.fromRGB(255, 180, 0)
	markupLabel.TextXAlignment = Enum.TextXAlignment.Left
	markupLabel.Text = ""
	markupLabel.Visible = false
	markupLabel.Parent = cityFrame
end

-- 3. GUI Referenzen finden
local nameLabel = cityFrame:FindFirstChild("CityNameLable")
local citizenLabel = cityFrame:FindFirstChild("CityCitizenLable")
local farmerLabel = cityFrame:FindFirstChild("FarmerLabel")
local workerLabel = cityFrame:FindFirstChild("WorkerLabel")
local traderLabel = cityFrame:FindFirstChild("TraderLabel")
local scientistLabel = cityFrame:FindFirstChild("ScientistLabel")
local nutritionLabel = cityFrame:FindFirstChild("CityNutritionPerRoundLable")
local industryLabel = cityFrame:FindFirstChild("CityIndustryPerRoundLable")
local goldLabel = cityFrame:FindFirstChild("CityGoldPerRoundLable")
local researchLabel = cityFrame:FindFirstChild("CityResearchPerRoundLable")

local buildScrollingFrame = cityFrame:FindFirstChild("CityBuildScrollingFrame")
local unitScrollingFrame = cityFrame:FindFirstChild("CityUnitScrollingFrame")
local buildQueueFrame = cityFrame:FindFirstChild("BuildQueueFame")

if not buildScrollingFrame then warn("[CityGuiController] FEHLT: CityFrame > CityBuildScrollingFrame") end
if not unitScrollingFrame then warn("[CityGuiController] FEHLT: CityFrame > CityUnitScrollingFrame") end
if not buildQueueFrame then warn("[CityGuiController] FEHLT: CityFrame > BuildQueueFame") end

local buildingByType = {}
for _, building in ipairs(CITY_BUILDINGS) do
	buildingByType[building.type] = building
end

local buildingStatLabels = {}
local unitStatLabels = {}
local lastQueueSignature = nil

--------------------------------------------------------------------------------
-- BAULISTE ERZEUGEN
--------------------------------------------------------------------------------
local function createBuildingList()
	if not buildScrollingFrame then return end

	for _, child in ipairs(buildScrollingFrame:GetChildren()) do
		if child:GetAttribute("GeneratedBuildingEntry") then child:Destroy() end
	end

	local layout = buildScrollingFrame:FindFirstChildWhichIsA("UIGridLayout")
	if not layout then
		layout = Instance.new("UIGridLayout")
		layout.Parent = buildScrollingFrame
	end
	layout.CellSize = UDim2.new(0.5, -6, 0, 140)
	layout.CellPadding = UDim2.new(0, 8, 0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.FillDirectionMaxCells = 2

	for index, building in ipairs(CITY_BUILDINGS) do
		local container = Instance.new("Frame")
		container.Name = building.type .. "_Container"
		container:SetAttribute("GeneratedBuildingEntry", true)
		container.LayoutOrder = index
		container.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
		container.BorderSizePixel = 0
		container.Parent = buildScrollingFrame

		local iconButton = Instance.new("ImageButton")
		iconButton.Name = building.type .. "Button"
		iconButton.Size = UDim2.fromOffset(62, 62)
		iconButton.Position = UDim2.new(0.5, -31, 0, 8)
		iconButton.Image = building.icon
		iconButton.BackgroundTransparency = 1
		iconButton.Parent = container

		local buildingName = Instance.new("TextLabel")
		buildingName.Size = UDim2.new(1, -8, 0, 24)
		buildingName.Position = UDim2.new(0, 4, 0, 76)
		buildingName.BackgroundTransparency = 1
		buildingName.Font = Enum.Font.SourceSansBold
		buildingName.TextSize = 18
		buildingName.TextColor3 = Color3.new(1, 1, 1)
		buildingName.Text = building.name
		buildingName.Parent = container

		local buildTime = Instance.new("TextLabel")
		buildTime.Size = UDim2.new(1, -8, 0, 32)
		buildTime.Position = UDim2.new(0, 4, 0, 102)
		buildTime.BackgroundTransparency = 1
		buildTime.Font = Enum.Font.SourceSans
		buildTime.TextSize = 14
		buildTime.TextWrapped = true
		buildTime.TextColor3 = Color3.fromRGB(190, 190, 190)
		buildTime.Text = "Berechnung..."
		buildTime.Parent = container

		buildingStatLabels[building.type] = buildTime

		iconButton.MouseButton1Click:Connect(function()
			local cityId = State.GetId(State.Kind.CITY)
			if not cityId then return end

			CityBuildState.Start(cityId, building.type)
			cityGui.Enabled = false
		end)
	end

	buildScrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	buildScrollingFrame.CanvasSize = UDim2.new()
end

--------------------------------------------------------------------------------
-- UNITLISTE ERZEUGEN
--------------------------------------------------------------------------------
local function createUnitList()
	if not unitScrollingFrame then return end

	for _, child in ipairs(unitScrollingFrame:GetChildren()) do
		if child:GetAttribute("GeneratedUnitEntry") then child:Destroy() end
	end

	local layout = unitScrollingFrame:FindFirstChildWhichIsA("UIGridLayout")
	if not layout then
		layout = Instance.new("UIGridLayout")
		layout.Parent = unitScrollingFrame
	end
	layout.CellSize = UDim2.new(0.5, -6, 0, 140)
	layout.CellPadding = UDim2.new(0, 8, 0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.FillDirectionMaxCells = 2

	local index = 1
	for unitType, unitData in pairs(UnitConfig.Units) do
		local container = Instance.new("Frame")
		container.Name = unitType .. "_Container"
		container:SetAttribute("GeneratedUnitEntry", true)
		container.LayoutOrder = index
		container.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
		container.BorderSizePixel = 0
		container.Parent = unitScrollingFrame

		local iconButton = Instance.new("ImageButton")
		iconButton.Name = unitType .. "Button"
		iconButton.Size = UDim2.fromOffset(62, 62)
		iconButton.Position = UDim2.new(0.5, -31, 0, 8)
		iconButton.Image = unitData.Icon
		iconButton.BackgroundTransparency = 1
		iconButton.Parent = container

		local unitName = Instance.new("TextLabel")
		unitName.Size = UDim2.new(1, -8, 0, 24)
		unitName.Position = UDim2.new(0, 4, 0, 76)
		unitName.BackgroundTransparency = 1
		unitName.Font = Enum.Font.SourceSansBold
		unitName.TextSize = 18
		unitName.TextColor3 = Color3.new(1, 1, 1)
		unitName.Text = unitData.Name
		unitName.Parent = container

		local statLb = Instance.new("TextLabel")
		statLb.Size = UDim2.new(1, -8, 0, 32)
		statLb.Position = UDim2.new(0, 4, 0, 102)
		statLb.BackgroundTransparency = 1
		statLb.Font = Enum.Font.SourceSans
		statLb.TextSize = 14
		statLb.TextWrapped = true
		statLb.TextColor3 = Color3.fromRGB(190, 190, 190)
		statLb.Text = "Berechnung..."
		statLb.Parent = container

		unitStatLabels[unitType] = {
			label = statLb,
			industryCost = unitData.IndustryCost or 0,
			citizenCost = unitData.CitizenCost or 0
		}

		iconButton.MouseButton1Click:Connect(function()
			local cityId = State.GetId(State.Kind.CITY)
			if not cityId then return end
			UnitSpawnState.Start(cityId, unitType)
			cityGui.Enabled = false
		end)

		index = index + 1
	end

	unitScrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	unitScrollingFrame.CanvasSize = UDim2.new()
end

--------------------------------------------------------------------------------
-- BuildQueueFame
--------------------------------------------------------------------------------
local function clearGeneratedQueue()
	if not buildQueueFrame then return end
	for _, child in ipairs(buildQueueFrame:GetChildren()) do
		if child:GetAttribute("GeneratedQueueEntry") then child:Destroy() end
	end
end

local function buildQueueSignature(city, currentGold)
	local queue = city.buildQueue or {}
	local parts = { "ind:" .. tostring(city.industryPerRound or 0), "gold:" .. tostring(currentGold or 0) }
	for _, order in ipairs(queue) do
		table.insert(parts, table.concat({
			tostring(order.id),
			tostring(order.orderType),
			tostring(order.buildingType),
			tostring(order.unitType),
			tostring(order.spawnQ or order.q),
			tostring(order.spawnR or order.r),
			tostring(order.industryProgress),
			tostring(order.industryCost),
			tostring(order.status),
		}, ":"))
	end
	return table.concat(parts, "|")
end

--------------------------------------------------------------------------------
-- Sofortkauf: Preis-Formel (Feature "Bauzeit aufkaufen mit Gold")
--   basisPreis = industrieKosten * 1.5
--   fortschritt = industryProgress / industryCost (0..1)
--   preis = math.ceil(basisPreis * (1 - fortschritt))
-- Muss exakt mit ConstructionSystem.GetInstantBuyPrice (Server) übereinstimmen.
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

-- UIStroke-Rahmen für wartende Items (Position 2+ in der Queue), damit sie
-- optisch als eigene Einträge erkennbar sind. Das erste Item (aktiver Bau)
-- bekommt KEINEN Rahmen, sondern den Sofortkauf-Button.
local function addWaitingStroke(guiObject)
	local stroke = Instance.new("UIStroke")
	stroke.Name = "WaitingStroke"
	stroke.Color = Color3.fromRGB(230, 230, 230)
	stroke.Transparency = 0.5
	stroke.Thickness = 1.5
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = guiObject
end

local function renderBuildQueue(city, currentGold)
	if not buildQueueFrame then return end

	local queue = city.buildQueue or {}
	local signature = buildQueueSignature(city, currentGold)
	if signature == lastQueueSignature then return end
	lastQueueSignature = signature

	clearGeneratedQueue()

	if #queue == 0 then
		local emptyLabel = Instance.new("TextLabel")
		emptyLabel.Name = "EmptyQueueLabel"
		emptyLabel:SetAttribute("GeneratedQueueEntry", true)
		emptyLabel.Size = UDim2.new(1, 0, 0, 34)
		emptyLabel.Position = UDim2.new(0, 0, 0.5, -17)
		emptyLabel.BackgroundTransparency = 1
		emptyLabel.Text = "Warteschlange leer"
		emptyLabel.TextColor3 = Color3.fromRGB(160, 160, 160)
		emptyLabel.TextSize = 15
		emptyLabel.Parent = buildQueueFrame
		return
	end

	-- WICHTIG: industryPerRound ist IMMER 0! Korrekter Wert: currentIndustryProduction
	local industry = tonumber(city.currentIndustryProduction) or 0
	local cumulativeRemaining = 0
	local remainingRoundsList = {}

	for _, order in ipairs(queue) do
		local remaining = math.max(0, (order.industryCost or 0) - (order.industryProgress or 0))
		cumulativeRemaining = cumulativeRemaining + remaining
		remainingRoundsList[order.id] = (industry > 0)
			and math.ceil(cumulativeRemaining / industry)
			or 0
	end

	local activeOrder = queue[1]

	local activeInfo = nil
	if activeOrder.orderType == "Unit" then
		local uCfg = UnitConfig.GetUnit(activeOrder.unitType)
		activeInfo = uCfg and {name = uCfg.Name, icon = uCfg.Icon} or {name = "Unit", icon = ""}
	else
		activeInfo = buildingByType[activeOrder.buildingType] or {name = "Building", icon = ""}
	end

	-- Sofortkauf-Preis fuer das aktive Item (nil wenn nicht kaufbar, z.B.
	-- WaitingSpawn-Status oder bereits fertig).
	local instantBuyPrice, instantBuyProgress = getInstantBuyPrice(activeOrder)
	local activeFrameHeight = instantBuyPrice and 104 or 70

	local activeFrame = Instance.new("Frame")
	activeFrame.Name = "ActiveEntry"
	activeFrame:SetAttribute("GeneratedQueueEntry", true)
	activeFrame.Size = UDim2.new(1, 0, 0, activeFrameHeight)
	activeFrame.Position = UDim2.new(0, 0, 0, 0)
	activeFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
	activeFrame.BorderSizePixel = 0
	activeFrame.Parent = buildQueueFrame

	local activeIcon = Instance.new("ImageLabel")
	activeIcon.Size = UDim2.fromOffset(50, 50)
	activeIcon.Position = UDim2.new(0, 10, 0.5, -25)
	activeIcon.BackgroundTransparency = 1
	activeIcon.Image = activeInfo.icon
	activeIcon.Parent = activeFrame

	local activeText = Instance.new("TextLabel")
	activeText.Size = UDim2.new(1, -70, 0, 70)
	activeText.Position = UDim2.new(0, 70, 0, 0)
	activeText.BackgroundTransparency = 1
	activeText.Font = Enum.Font.SourceSansBold
	activeText.TextSize = 18
	activeText.TextWrapped = true
	activeText.TextXAlignment = Enum.TextXAlignment.Left
	activeText.TextColor3 = Color3.new(1, 1, 1)

	local statusText
	if activeOrder.status == "WaitingSpawn" then
		statusText = "Wartet auf freies Spawn-Feld..."
	else
		local progress = activeOrder.industryProgress or 0
		local cost = activeOrder.industryCost or 0

		if industry > 0 then
			local remaining = math.max(0, cost - progress)
			local roundsLeft = math.ceil(remaining / industry)

			if roundsLeft <= 1 then
				statusText = "Noch 1 Runde (" .. progress .. "/" .. cost .. " Arbeit)"
			else
				statusText = "Noch " .. roundsLeft .. " Runden (" .. progress .. "/" .. cost .. " Arbeit)"
			end
		else
			statusText = "Unendlich Runden (" .. progress .. "/" .. cost .. " Arbeit)"
		end
	end
	activeText.Text = activeInfo.name .. " – " .. statusText
	activeText.Parent = activeFrame

	-- Feature "Bauzeit aufkaufen mit Gold": Button unter dem aktiven Item.
	-- Nur sichtbar, wenn das Item ueberhaupt aufkaufbar ist (Building-Status,
	-- gueltige Industriekosten).
	if instantBuyPrice then
		local buyButton = Instance.new("TextButton")
		buyButton.Name = "InstantBuyButton"
		buyButton:SetAttribute("GeneratedQueueEntry", true)
		buyButton.Size = UDim2.new(1, -20, 0, 28)
		buyButton.Position = UDim2.new(0, 10, 0, 72)
		buyButton.Font = Enum.Font.SourceSansBold
		buyButton.TextSize = 15
		buyButton.AutoButtonColor = true

		local affordable = (currentGold or 0) >= instantBuyPrice
		local nearlyDone = (instantBuyProgress or 0) >= 0.95

		local labelPrefix = nearlyDone and "⚡ Fertigstellen (" or "⚡ Sofort kaufen ("
		buyButton.Text = labelPrefix .. instantBuyPrice .. " Gold)"

		if affordable then
			buyButton.BackgroundColor3 = Color3.fromRGB(70, 150, 70)
			buyButton.TextColor3 = Color3.new(1, 1, 1)
			buyButton.Active = true
		else
			buyButton.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
			buyButton.TextColor3 = Color3.fromRGB(180, 180, 180)
			buyButton.Active = false
		end
		buyButton.BorderSizePixel = 0
		buyButton.Parent = activeFrame

		if affordable then
			buyButton.MouseButton1Click:Connect(function()
				if requestInstantBuyRemote then
					requestInstantBuyRemote:FireServer(city.id)
				end
			end)
		end
	end

	if #queue > 1 then
		local waitingArea = Instance.new("Frame")
		waitingArea.Name = "WaitingArea"
		waitingArea:SetAttribute("GeneratedQueueEntry", true)
		waitingArea.Size = UDim2.new(1, 0, 0, 60)
		-- 5px Abstand unter dem aktiven Item (dessen Hoehe variiert, je
		-- nachdem ob der Sofortkauf-Button angezeigt wird).
		waitingArea.Position = UDim2.new(0, 0, 0, activeFrameHeight + 5)
		waitingArea.BackgroundTransparency = 1
		waitingArea.Parent = buildQueueFrame

		local frameWidth = waitingArea.AbsoluteSize.X
		if frameWidth <= 0 then frameWidth = 250 end

		local itemWidth = 48
		local padding = 6
		local maxItems = math.floor((frameWidth + padding) / (itemWidth + padding))

		local count = 0
		for i = 2, #queue do
			if count >= maxItems then break end

			local order = queue[i]

			local info
			if order.orderType == "Unit" then
				local uCfg = UnitConfig.GetUnit(order.unitType)
				info = uCfg and {name = uCfg.Name, icon = uCfg.Icon} or {name = "Unit", icon = ""}
			else
				info = buildingByType[order.buildingType] or {name = "Building", icon = ""}
			end

			local item = Instance.new("Frame")
			item.Name = "Waiting_" .. tostring(order.id)
			item.Size = UDim2.fromOffset(itemWidth, 60)
			item.Position = UDim2.new(0, (count * (itemWidth + padding)), 0, 0)
			item.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
			item.BackgroundTransparency = 0.5
			item.Parent = waitingArea

			-- Änderung B: wartende Items (Position 2+) bekommen einen
			-- duennen hellen Rahmen, damit sie als eigene Eintraege
			-- erkennbar sind. Das aktive Item (oben) hat KEINEN Rahmen.
			addWaitingStroke(item)

			local icon = Instance.new("ImageLabel")
			icon.Size = UDim2.fromOffset(40, 40)
			icon.Position = UDim2.new(0.5, -20, 0, 0)
			icon.BackgroundTransparency = 1
			icon.Image = info and info.icon or ""
			icon.Parent = item

			local timeText = Instance.new("TextLabel")
			timeText.Size = UDim2.new(1, 0, 0, 15)
			timeText.Position = UDim2.new(0, 0, 0, 40)
			timeText.BackgroundTransparency = 1
			timeText.Font = Enum.Font.SourceSans
			timeText.TextSize = 13
			timeText.TextColor3 = Color3.fromRGB(200, 200, 200)
			timeText.Text = tostring(remainingRoundsList[order.id]) .. " R"
			timeText.Parent = item

			count = count + 1
		end
	end
end

--------------------------------------------------------------------------------
-- City-Daten
--------------------------------------------------------------------------------
local function clearStats()
	if nameLabel then nameLabel.Text = "" end
	if citizenLabel then citizenLabel.Text = "0" end
	if nutritionLabel then nutritionLabel.Text = "0" end
	if industryLabel then industryLabel.Text = "0" end
	if goldLabel then goldLabel.Text = "0" end
	if researchLabel then researchLabel.Text = "0" end
	lastQueueSignature = nil
	clearGeneratedQueue()
end

local function updateStats(city)
	if not city then return end

	if nameLabel then nameLabel.Text = city.name or ("City " .. city.id) end

	-- Bevölkerung und Slots
	local pop = city.population or 0
	local totalSlots = 0
	for _, slots in pairs(city.jobSlots or {}) do totalSlots = totalSlots + slots end

	if citizenLabel then
		citizenLabel.Text = pop .. "/" .. totalSlots .. " Bevölkerung"
		if pop > totalSlots then
			citizenLabel.TextColor3 = Color3.fromRGB(255, 50, 50) -- Rot bei Überbevölkerung
		else
			citizenLabel.TextColor3 = Color3.fromRGB(0, 0, 0) -- Schwarz
		end
	end

	-- HINWEIS: Die Job-Labels (Farmer/Worker/Trader/Scientist) werden
	-- ausschließlich vom JobAssignmentController aktualisiert!

	-- Erträge anzeigen
	if nutritionLabel then
		local production = city.currentFoodProduction or 0
		local consumption = city.currentFoodConsumption or 0
		local netFood = production - consumption
		local sign = netFood >= 0 and "+" or ""

		if netFood >= 0 then
			nutritionLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
		else
			nutritionLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
		end
		nutritionLabel.Text = sign .. netFood .. " Food/R"
	end
	if industryLabel then
		local work = city.currentIndustryProduction or 0
		industryLabel.Text = work .. " Work/R"
	end
	if goldLabel then
		local gold = city.currentGoldProduction or 0
		goldLabel.Text = gold .. " Gold/R"
	end
	if researchLabel then
		local research = city.currentResearchProduction or 0
		researchLabel.Text = research .. " Research/R"
	end

	local industry = tonumber(city.currentIndustryProduction) or 0

	-- Aktuelles Spieler-Gold laden (für den Sofortkauf-Button in der Queue:
	-- Preis-Anzeige + Ausgrauen wenn nicht genug Gold vorhanden ist).
	local currentGold = 0
	if getEmpireDataRemote then
		local goldSuccess, empireData = pcall(function()
			return getEmpireDataRemote:InvokeServer()
		end)
		if goldSuccess and empireData then
			currentGold = tonumber(empireData.gold) or 0
		end
	end

	-- Dynamische Baukosten vom Server abfragen
	local buildingCosts = nil
	if getBuildingCostsRemote then
		local costSuccess, costs = pcall(function()
			return getBuildingCostsRemote:InvokeServer(city.id)
		end)
		if costSuccess then buildingCosts = costs end
	end

	-- Stadtaufschlag-Hinweis aktualisieren (Stufen-System)
	if markupLabel then
		if buildingCosts and buildingCosts._info and buildingCosts._info.stage and buildingCosts._info.stage > 1 then
			local multiplierText = string.format("%.1f", buildingCosts._info.multiplier or 1.0)
			markupLabel.Text = "Stadtaufschlag: Stufe " .. buildingCosts._info.stage .. " (x" .. multiplierText .. ", " .. buildingCosts._info.buildingCount .. " Gebäude)"
			markupLabel.Visible = true
		else
			markupLabel.Visible = false
		end
	end

	-- Gebäude-Texte updaten: "Fertig in X Runden (Y Industrie)"
	for _, building in ipairs(CITY_BUILDINGS) do
		local label = buildingStatLabels[building.type]
		if label then
			-- Prüfen ob dieses Gebäude bereits im Bau ist
			local activeOrder = nil
			for _, order in ipairs(city.buildQueue or {}) do
				if order.status == "Building" and order.buildingType == building.type then
					activeOrder = order
					break
				end
			end

			if activeOrder then
				-- Projekt ist im Bau: Fortschritt anzeigen!
				local remaining = math.max(0, (activeOrder.industryCost or 0) - (activeOrder.industryProgress or 0))
				if industry > 0 then
					local rounds = math.ceil(remaining / industry)
					label.Text = "Fertig in " .. rounds .. " Runden (" .. (activeOrder.industryProgress or 0) .. "/" .. (activeOrder.industryCost or 0) .. " Arbeit)"
				else
					label.Text = "Unendlich Runden (" .. (activeOrder.industryProgress or 0) .. "/" .. (activeOrder.industryCost or 0) .. " Arbeit)"
				end
			else
				-- Noch nicht im Bau: Rundenanzahl + tatsächliche Kosten!
				local actualCost = building.industryCost
				if buildingCosts and buildingCosts[building.type] then
					actualCost = buildingCosts[building.type].actualCost
				end

				if industry > 0 then
					local rounds = math.ceil(actualCost / industry)
					label.Text = "Fertig in " .. rounds .. " Runden (" .. actualCost .. " Industrie)"
				else
					label.Text = "Unendlich Runden (" .. actualCost .. " Industrie)"
				end
			end
		end
	end

	-- Unit-Texte updaten
	for unitType, data in pairs(unitStatLabels) do
		if data.label then
			local activeUnitOrder = nil
			for _, order in ipairs(city.buildQueue or {}) do
				if order.status == "Building" and order.unitType == unitType then
					activeUnitOrder = order
					break
				end
			end

			local citizenText = ""
			if (data.citizenCost or 0) > 0 then
				citizenText = " (-" .. data.citizenCost .. " Einwohner)"
			end

			if activeUnitOrder then
				local remaining = math.max(0, (activeUnitOrder.industryCost or 0) - (activeUnitOrder.industryProgress or 0))
				if industry > 0 then
					local rounds = math.ceil(remaining / industry)
					data.label.Text = "Fertig in " .. rounds .. " Runden" .. citizenText .. " (" .. (activeUnitOrder.industryProgress or 0) .. "/" .. (activeUnitOrder.industryCost or 0) .. " Arbeit)"
				else
					data.label.Text = "Unendlich Runden" .. citizenText .. " (" .. (activeUnitOrder.industryProgress or 0) .. "/" .. (activeUnitOrder.industryCost or 0) .. " Arbeit)"
				end
			else
				if industry > 0 then
					local rounds = math.ceil(data.industryCost / industry)
					data.label.Text = "Fertig in " .. rounds .. " Runden" .. citizenText
				else
					data.label.Text = "Unendlich Runden (keine Produktion)" .. citizenText
				end
			end
		end
	end

	renderBuildQueue(city, currentGold)
end

--------------------------------------------------------------------------------
-- Sichtbarkeit: rein Event-basiert (kein Polling!)
--------------------------------------------------------------------------------
local function showGui()
	if CityBuildState.IsPlacing() or UnitSpawnState.IsPlacing() then return end
	if not cityGui.Enabled then
		cityGui.Enabled = true
	end
	-- Daten frisch holen -> feuert CityDataCache.OnUpdated
	task.spawn(CityDataCache.Refresh)
end

local function hideGui()
	if cityGui.Enabled then
		cityGui.Enabled = false
		clearStats()
	end
end

-- Auswahl geändert -> sofort anzeigen/verstecken
State.OnChanged:Connect(function(kind, id)
	if kind == State.Kind.CITY and id then
		showGui()
	else
		hideGui()
	end
end)

-- Während der Gebäude-Platzierung verstecken, danach wieder zeigen
CityBuildState.OnChanged:Connect(function(placement)
	if placement then
		cityGui.Enabled = false
	elseif State.Has(State.Kind.CITY) then
		showGui()
	end
end)

-- Während der Unit-Spawn-Auswahl verstecken, danach wieder zeigen
UnitSpawnState.OnChanged:Connect(function(placement)
	if placement then
		cityGui.Enabled = false
	elseif State.Has(State.Kind.CITY) then
		showGui()
	end
end)

-- Stadt-Daten kommen zentral aus dem CityDataCache
CityDataCache.OnUpdated:Connect(function(city)
	if not city or not cityGui.Enabled then return end
	local success, err = pcall(updateStats, city)
	if not success then
		warn("[CityGuiController] Update Fehler: " .. tostring(err))
	end
end)

createBuildingList()
createUnitList()
clearStats()
cityGui.Enabled = false

-- Falls beim Start schon eine Stadt ausgewählt ist: sofort anzeigen
if State.Has(State.Kind.CITY) then
	showGui()
end

print("[CityGuiController] Bereit")