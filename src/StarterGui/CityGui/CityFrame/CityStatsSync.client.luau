--[[
    CityStatsSync (LocalScript)
    Ort: StarterGui > CityGui > CityFrame > CityStatsSync
    
    Aktualisiert die Stat-Labels sobald sich etwas ändert.
    
    Vereinfacht: Die Stadt-Daten kommen zentral aus dem CityDataCache
    (kein eigenes GetCity, kein Polling, kein eigener RemoteListener).
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local CityDataCache = require(ReplicatedStorage:WaitForChild("CityDataCache"))

local cityFrame = script.Parent

-- Labels finden
local nameLabel = cityFrame:FindFirstChild("CityNameLable")
local citizenLabel = cityFrame:FindFirstChild("CityCitizenLable")
local nutritionLabel = cityFrame:FindFirstChild("CityNutritionPerRoundLable")
local industryLabel = cityFrame:FindFirstChild("CityIndustryPerRoundLable")
local goldLabel = cityFrame:FindFirstChild("CityGoldPerRoundLable")
local researchLabel = cityFrame:FindFirstChild("CityResearchPerRoundLable")

-- Alte Werte speichern um Änderungen zu erkennen
local lastValues = {
	population = nil,
	growthBar = nil,
	food = nil,
	work = nil,
	gold = nil,
	research = nil,
}

--------------------------------------------------------------------------------
-- Hilfsfunktion: Flash-Effekt bei Änderung
--------------------------------------------------------------------------------
local function flashLabel(label, color)
	if not label then return end

	local originalColor = label.TextColor3
	label.TextColor3 = color

	local tween = TweenService:Create(
		label,
		TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ TextColor3 = originalColor }
	)
	tween:Play()
end

--------------------------------------------------------------------------------
-- Stats aktualisieren
--------------------------------------------------------------------------------
local function updateStats(city)
	if not city then return end

	-- Bevölkerung
	local pop = city.population or 0
	local totalSlots = 0
	for _, slots in pairs(city.jobSlots or {}) do
		totalSlots = totalSlots + (tonumber(slots) or 0)
	end

	if citizenLabel then
		citizenLabel.Text = pop .. "/" .. totalSlots .. " Bevölkerung"
		if pop > totalSlots then
			citizenLabel.TextColor3 = Color3.fromRGB(255, 50, 50)
		else
			citizenLabel.TextColor3 = Color3.fromRGB(0, 0, 0)
		end
	end

	-- Nahrung (Netto)
	if nutritionLabel then
		local production = city.currentFoodProduction or 0
		local consumption = city.currentFoodConsumption or 0
		local netFood = production - consumption
		local sign = netFood >= 0 and "+" or ""
		nutritionLabel.Text = sign .. netFood .. " Food/R"
	end

	-- Industrie
	if industryLabel then
		industryLabel.Text = (city.currentIndustryProduction or 0) .. " Work/R"
	end

	-- Gold
	if goldLabel then
		goldLabel.Text = (city.currentGoldProduction or 0) .. " Gold/R"
	end

	-- Forschung
	if researchLabel then
		researchLabel.Text = (city.currentResearchProduction or 0) .. " Research/R"
	end

	-- Name
	if nameLabel then
		nameLabel.Text = city.name or ("City " .. city.id)
	end

	-- Änderungen erkennen und Flash auslösen
	if lastValues.population ~= nil and lastValues.population ~= pop then
		if pop > lastValues.population then
			flashLabel(citizenLabel, Color3.fromRGB(0, 255, 0)) -- Grün bei Wachstum
		else
			flashLabel(citizenLabel, Color3.fromRGB(255, 0, 0)) -- Rot bei Verlust
		end
	end

	local currentFood = (city.currentFoodProduction or 0) - (city.currentFoodConsumption or 0)
	if lastValues.food ~= nil and lastValues.food ~= currentFood then
		if currentFood > (lastValues.food or 0) then
			flashLabel(nutritionLabel, Color3.fromRGB(0, 255, 0))
		else
			flashLabel(nutritionLabel, Color3.fromRGB(255, 100, 100))
		end
	end

	-- Neue Werte speichern
	lastValues.population = pop
	lastValues.food = currentFood
	lastValues.work = city.currentIndustryProduction
	lastValues.gold = city.currentGoldProduction
	lastValues.research = city.currentResearchProduction
end

--------------------------------------------------------------------------------
-- Live-Updates aus dem CityDataCache
--------------------------------------------------------------------------------
CityDataCache.OnUpdated:Connect(function(city)
	if not city then return end
	updateStats(city)
end)

print("[CityStatsSync] Bereit")