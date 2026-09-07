--[[
    ResourceOverviewController (LocalScript)
    Ort: StarterGui > CityGui > CityFrame > ResourceOverviewController
    
    Zeigt für jede Ressource die Aufschlüsselung an.
    
    Vereinfacht: Die Stadt-Daten kommen zentral aus dem CityDataCache.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CityDataCache = require(ReplicatedStorage:WaitForChild("CityDataCache"))

local cityFrame = script.Parent

local overviewFrame = cityFrame:FindFirstChild("ResourceOverviewFrame")
if not overviewFrame then
	overviewFrame = Instance.new("Frame")
	overviewFrame.Name = "ResourceOverviewFrame"
	overviewFrame.Size = UDim2.new(1, 0, 0, 150)
	overviewFrame.Position = UDim2.new(0, 0, 0, -155)
	overviewFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
	overviewFrame.BorderSizePixel = 0
	overviewFrame.Parent = cityFrame
end

local labels = {}

local function createResourceBlock(name, yPos, headerColor)
	local header = overviewFrame:FindFirstChild(name .. "HeaderLabel")
	if not header then
		header = Instance.new("TextLabel")
		header.Name = name .. "HeaderLabel"
		header.Size = UDim2.new(0.5, -10, 0, 18)
		header.Position = UDim2.new(0, 10, 0, yPos)
		header.BackgroundTransparency = 1
		header.Font = Enum.Font.SourceSansBold
		header.TextSize = 16
		header.TextColor3 = headerColor
		header.TextXAlignment = Enum.TextXAlignment.Left
		header.Text = name
		header.Parent = overviewFrame
	end

	local detail = overviewFrame:FindFirstChild(name .. "DetailLabel")
	if not detail then
		detail = Instance.new("TextLabel")
		detail.Name = name .. "DetailLabel"
		detail.Size = UDim2.new(0.5, -10, 0, 60)
		detail.Position = UDim2.new(0, 20, 0, yPos + 18)
		detail.BackgroundTransparency = 1
		detail.Font = Enum.Font.SourceSans
		detail.TextSize = 11
		detail.TextColor3 = Color3.fromRGB(200, 200, 200)
		detail.TextXAlignment = Enum.TextXAlignment.Left
		detail.TextWrapped = true
		detail.Text = "..."
		detail.Parent = overviewFrame
	end

	labels[name] = { header = header, detail = detail }
end

createResourceBlock("Food", 5, Color3.fromRGB(100, 255, 100))
createResourceBlock("Work", 49, Color3.fromRGB(100, 180, 255))
createResourceBlock("Gold", 93, Color3.fromRGB(255, 220, 80))
createResourceBlock("Research", 5, Color3.fromRGB(200, 150, 255))

if labels.Work then
	labels.Work.header.Position = UDim2.new(0.5, 5, 0, 49)
	labels.Work.detail.Position = UDim2.new(0.5, 15, 0, 67)
end
if labels.Research then
	labels.Research.header.Position = UDim2.new(0.5, 5, 0, 5)
	labels.Research.detail.Position = UDim2.new(0.5, 15, 0, 23)
end

local COLORS = {
	positive = Color3.fromRGB(100, 255, 100),
	negative = Color3.fromRGB(255, 100, 100),
	neutral = Color3.fromRGB(200, 200, 200),
	project = Color3.fromRGB(100, 180, 255),
	wasted = Color3.fromRGB(150, 150, 150),
	gold = Color3.fromRGB(255, 220, 80),
	research = Color3.fromRGB(200, 150, 255),
}

local function updateOverview(city)
	if not city then return end

	-- NAHRUNG
	if labels.Food then
		local foodProd = city.currentFoodProduction or 0
		local foodCons = city.currentFoodConsumption or 0
		local surplus = foodProd - foodCons
		local growthBar = city.growthBar or 0
		local threshold = city.foodThreshold or 30

		labels.Food.header.Text = "Nahrung: " .. (surplus >= 0 and "+" or "") .. surplus
		labels.Food.detail.Text = "+ " .. foodProd .. " Produktion\n- " .. foodCons .. " Verbrauch (" .. (city.population or 0) .. " Einwohner)\n" .. (surplus >= 0 and "+" or "") .. surplus .. " Wachstums-Bar (" .. growthBar .. "/" .. threshold .. ")"

		if surplus > 0 then
			labels.Food.detail.TextColor3 = COLORS.positive
		elseif surplus < 0 then
			labels.Food.detail.TextColor3 = COLORS.negative
		else
			labels.Food.detail.TextColor3 = COLORS.neutral
		end
	end

	-- ARBEIT
	if labels.Work then
		local workProd = city.currentIndustryProduction or 0

		local activeProject = nil
		for _, order in ipairs(city.buildQueue or {}) do
			if order.status == "Building" then
				activeProject = order
				break
			end
		end

		labels.Work.header.Text = "Arbeit: +" .. workProd

		if activeProject then
			local name = activeProject.buildingType or activeProject.unitType or "?"
			labels.Work.detail.Text = "→ " .. workProd .. " " .. name .. " (" .. (activeProject.industryProgress or 0) .. "/" .. (activeProject.industryCost or 0) .. ")"
			labels.Work.detail.TextColor3 = COLORS.project
		else
			labels.Work.detail.Text = "→ 0 Kein aktives Projekt (verfällt)"
			labels.Work.detail.TextColor3 = COLORS.wasted
		end
	end

	-- GOLD
	if labels.Gold then
		local goldProd = city.currentGoldProduction or 0
		labels.Gold.header.Text = "Gold: +" .. goldProd
		labels.Gold.detail.Text = "→ " .. goldProd .. " Spieler-Guthaben"
		labels.Gold.detail.TextColor3 = COLORS.gold
	end

	-- FORSCHUNG
	if labels.Research then
		local resProd = city.currentResearchProduction or 0
		labels.Research.header.Text = "Forschung: +" .. resProd
		labels.Research.detail.Text = "→ 0 Kein Projekt (verfällt)"
		labels.Research.detail.TextColor3 = COLORS.wasted
	end
end

CityDataCache.OnUpdated:Connect(function(city)
	if city then updateOverview(city) end
end)

print("[ResourceOverviewController] Bereit")