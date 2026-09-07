--[[
    GrowthBarController (LocalScript)
    Ort: StarterGui > CityGui > CityFrame > GrowthBarController
    
    Zeigt die Wachstum-Bar einer Stadt an.
    Erzeugt die UI automatisch, wenn sie fehlt.
    
    Vereinfacht: Die Stadt-Daten kommen zentral aus dem CityDataCache.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CityDataCache = require(ReplicatedStorage:WaitForChild("CityDataCache"))

local cityFrame = script.Parent

--------------------------------------------------------------------------------
-- UI ERSTELLEN (Automatisch, falls sie nicht existiert)
--------------------------------------------------------------------------------
local growthFrame = cityFrame:FindFirstChild("GrowthBarFrame")
if not growthFrame then
	growthFrame = Instance.new("Frame")
	growthFrame.Name = "GrowthBarFrame"
	growthFrame.Size = UDim2.new(1, 0, 0, 55)
	growthFrame.Position = UDim2.new(0, 0, 1, -60)
	growthFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
	growthFrame.BorderSizePixel = 0
	growthFrame.Parent = cityFrame
end

local growthLabel = growthFrame:FindFirstChild("GrowthLabel")
if not growthLabel then
	growthLabel = Instance.new("TextLabel")
	growthLabel.Name = "GrowthLabel"
	growthLabel.Size = UDim2.new(1, 0, 0, 20)
	growthLabel.Position = UDim2.new(0, 10, 0, 5)
	growthLabel.BackgroundTransparency = 1
	growthLabel.Font = Enum.Font.SourceSansBold
	growthLabel.TextSize = 16
	growthLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	growthLabel.TextXAlignment = Enum.TextXAlignment.Left
	growthLabel.Text = "Wachstum: 0/10"
	growthLabel.Parent = growthFrame
end

local barBg = growthFrame:FindFirstChild("GrowthBarBg")
if not barBg then
	barBg = Instance.new("Frame")
	barBg.Name = "GrowthBarBg"
	barBg.Size = UDim2.new(1, -20, 0, 16)
	barBg.Position = UDim2.new(0, 10, 0, 30)
	barBg.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
	barBg.Parent = growthFrame
end

local barFill = barBg:FindFirstChild("GrowthFill")
if not barFill then
	barFill = Instance.new("Frame")
	barFill.Name = "GrowthFill"
	barFill.Size = UDim2.new(0, 0, 1, 0)
	barFill.Position = UDim2.new(0, 0, 0, 0)
	barFill.BackgroundColor3 = Color3.fromRGB(100, 255, 100)
	barFill.Parent = barBg
end

--------------------------------------------------------------------------------
-- DATEN AKTUALISIEREN
--------------------------------------------------------------------------------
local function updateDisplay(city)
	if not city then return end

	local bar = city.growthBar or 0
	local threshold = city.foodThreshold or 10
	local surplus = city.foodSurplus or 0

	-- Threshold neu berechnen, um sicherzustellen das es niemals 0 ist
	if threshold <= 0 then threshold = 10 end

	-- Label Text und Farbe
	local isPositive = surplus >= 0
	growthLabel.Text = "Wachstum: " .. bar .. "/" .. threshold
	growthLabel.TextColor3 = isPositive and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 100, 100)

	-- Bar Fortschritt aktualisieren
	local pct = math.clamp(bar / threshold, 0, 1)
	barFill.Size = UDim2.new(pct, 0, 1, 0)
	barFill.BackgroundColor3 = isPositive and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 100, 100)
end

--------------------------------------------------------------------------------
-- LIVE-REFRESH (eventbasiert über den CityDataCache)
--------------------------------------------------------------------------------
CityDataCache.OnUpdated:Connect(function(city)
	if city then updateDisplay(city) end
end)

print("[GrowthBarController] Bereit")