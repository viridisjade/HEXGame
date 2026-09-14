--[[
    CityBannerController (LocalScript)
    Ort: StarterPlayer > StarterPlayerScripts > CityBannerController

    Erzeugt über jeder Stadt ein komplett per Code generiertes Fantasy-
    Banner (BillboardGui) in der Farbe des Besitzers.

    SICHTBARKEIT (folgt dem Fog-of-War, siehe FogOfWarController):
        unexplored -> Banner unsichtbar (BillboardGui.Enabled = false)
        explored   -> alle Elemente Transparency 0.5 (Geister-Look)
        visible    -> Rahmen/Text voll sichtbar (0), Innenfläche bleibt bei 0.2

    KLICK:
        eigenes Banner  -> ClientState.Toggle(CITY, cityId) (öffnet CityGui)
        fremdes Banner  -> Info-Popup (Name, Besitzer, Gebäude, Bevölkerung)

    Datenquelle: DataRemotes > GetCityOnHex (liefert die cityId für ein
    Hex) + DataRemotes > GetCityPublicInfo (liefert Name/Besitzer/Farbe/
    Gebäude/Bevölkerung OHNE Besitz-Prüfung - für fremde Städte gedacht).
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Net = require(ReplicatedStorage:WaitForChild("Net"))
local State = require(ReplicatedStorage:WaitForChild("ClientState"))
local FogOfWarConfig = require(ReplicatedStorage:WaitForChild("FogOfWarConfig"))

Net.Warmup({ "GetCityOnHex", "GetCityPublicInfo" })

print("[CityBannerController] geladen (LocalScript laeuft)")

--------------------------------------------------------------------------------
-- STIL (Fantasy, bronze Rahmen - wie alle anderen Fantasy-Fenster im Spiel)
--------------------------------------------------------------------------------
local BRONZE = Color3.fromRGB(120, 90, 50)
local DEFAULT_COLOR = Color3.fromRGB(140, 140, 140)

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------
local banners = {}        -- [hexKey] = bannerEntry
local bannerByCityId = {} -- [cityId] = hexKey

--------------------------------------------------------------------------------
-- HILFSFUNKTIONEN
--------------------------------------------------------------------------------
local function hexKeyFromBuildingName(name)
	-- Städte heißen "City_q_r" (siehe CitySystem.swapModelToCity).
	local q, r = string.match(name, "^City_(%-?%d+)_(%-?%d+)$")
	if not q then return nil, nil, nil end
	return q .. "_" .. r, tonumber(q), tonumber(r)
end

--------------------------------------------------------------------------------
-- BANNER-GUI ERZEUGEN (Fahnenform: Rechteck + 2 gedrehte Quadrate als
-- Spitzen an den Enden, bronzefarbener Rahmen, Innenfläche = Besitzerfarbe)
--------------------------------------------------------------------------------
local function buildBannerGui(buildingModel)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "CityBanner"
	billboard.Size = UDim2.new(0, 200, 0, 50)
	billboard.StudsOffset = Vector3.new(0, 8, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 500
	billboard.ResetOnSpawn = false
	billboard.Enabled = false -- Fog-of-War entscheidet, wann es erscheint
	billboard.Adornee = buildingModel
	billboard.Parent = buildingModel

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.ClipsDescendants = false
	root.Parent = billboard

	-- Hauptfläche der Fahne
	local flag = Instance.new("Frame")
	flag.Name = "Flag"
	flag.AnchorPoint = Vector2.new(0.5, 0.5)
	flag.Position = UDim2.new(0.5, 0, 0.5, 0)
	flag.Size = UDim2.new(1, -28, 1, 0)
	flag.BackgroundColor3 = DEFAULT_COLOR
	flag.BackgroundTransparency = 0.2
	flag.BorderSizePixel = 0
	flag.ZIndex = 2
	flag.Parent = root

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = flag

	local flagStroke = Instance.new("UIStroke")
	flagStroke.Name = "FlagStroke"
	flagStroke.Thickness = 2
	flagStroke.Color = BRONZE
	flagStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	flagStroke.Parent = flag

	-- Fahnen-Spitzen: kleine, um 45° gedrehte Quadrate links/rechts, damit
	-- die Fahne spitz zulaufend statt rein rechteckig wirkt.
	local function makeTip(anchorX, name)
		local tip = Instance.new("Frame")
		tip.Name = name
		tip.AnchorPoint = Vector2.new(0.5, 0.5)
		tip.Position = UDim2.new(anchorX, 0, 0.5, 0)
		tip.Size = UDim2.fromOffset(14, 14)
		tip.Rotation = 45
		tip.BackgroundColor3 = DEFAULT_COLOR
		tip.BackgroundTransparency = 0.2
		tip.BorderSizePixel = 0
		tip.ZIndex = 1
		tip.Parent = root

		local tipStroke = Instance.new("UIStroke")
		tipStroke.Thickness = 2
		tipStroke.Color = BRONZE
		tipStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		tipStroke.Parent = tip

		return tip
	end

	local tipLeft = makeTip(0.015, "TipLeft")
	local tipRight = makeTip(0.985, "TipRight")

	-- Stadtname: weiß mit schwarzer Kontur
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "CityName"
	nameLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	nameLabel.Position = UDim2.fromScale(0.5, 0.5)
	nameLabel.Size = UDim2.new(1, -12, 1, -4)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.FredokaOne
	nameLabel.TextSize = 14
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextWrapped = true
	nameLabel.TextScaled = false
	nameLabel.Text = "..."
	nameLabel.ZIndex = 3
	nameLabel.Parent = flag

	local nameStroke = Instance.new("UIStroke")
	nameStroke.Name = "NameStroke"
	nameStroke.Thickness = 2
	nameStroke.Color = Color3.fromRGB(0, 0, 0)
	nameStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Outline
	nameStroke.Parent = nameLabel

	-- Klick-Erkennung: unsichtbarer Button über der gesamten Fahne.
	local clickButton = Instance.new("TextButton")
	clickButton.Name = "ClickCatcher"
	clickButton.Size = UDim2.fromScale(1, 1)
	clickButton.BackgroundTransparency = 1
	clickButton.Text = ""
	clickButton.AutoButtonColor = false
	clickButton.ZIndex = 4
	clickButton.Parent = flag

	return {
		billboard = billboard,
		flag = flag,
		tipLeft = tipLeft,
		tipRight = tipRight,
		nameLabel = nameLabel,
		nameStroke = nameStroke,
		flagStroke = flagStroke,
		clickButton = clickButton,
	}
end

--------------------------------------------------------------------------------
-- FOG-OF-WAR-INTEGRATION
-- Sichtbarkeit/Transparenz folgt den Zuständen aus FogOfWarConfig.STATE.
-- "visible": Rahmen/Text voll sichtbar (0), Innenfläche bleibt bei 0.2
--            (Fantasy-Design - siehe buildBannerGui).
-- "explored": ALLE Elemente auf 0.5 (Geister-Look).
--------------------------------------------------------------------------------
local function setElementsTransparency(entry, fillT, strokeT, textT)
	entry.flag.BackgroundTransparency = fillT
	entry.tipLeft.BackgroundTransparency = fillT
	entry.tipRight.BackgroundTransparency = fillT
	entry.flagStroke.Transparency = strokeT
	entry.nameLabel.TextTransparency = textT
	entry.nameStroke.Transparency = strokeT
end

local function applyFogState(entry, state)
	if state == FogOfWarConfig.STATE.UNEXPLORED then
		entry.billboard.Enabled = false
		return
	end

	entry.billboard.Enabled = true
	if state == FogOfWarConfig.STATE.VISIBLE then
		setElementsTransparency(entry, 0.2, 0, 0)
	else -- EXPLORED
		setElementsTransparency(entry, 0.5, 0.5, 0.5)
	end
	entry.fogState = state
end

--------------------------------------------------------------------------------
-- INFO-POPUP (fremde Stadt): ScreenGui, einmalig erzeugt, wiederverwendet.
--------------------------------------------------------------------------------
local popupGui = Instance.new("ScreenGui")
popupGui.Name = "CityInfoPopupGui"
popupGui.ResetOnSpawn = false
popupGui.IgnoreGuiInset = true
popupGui.DisplayOrder = 60
popupGui.Enabled = false
popupGui.Parent = playerGui

local popupWindow = Instance.new("Frame")
popupWindow.Name = "PopupWindow"
popupWindow.AnchorPoint = Vector2.new(0.5, 0.5)
popupWindow.Position = UDim2.new(0.5, 0, 0.5, 0)
popupWindow.Size = UDim2.new(0, 220, 0, 130)
popupWindow.BackgroundColor3 = Color3.fromRGB(35, 28, 22)
popupWindow.BorderSizePixel = 0
popupWindow.Parent = popupGui

local popupCorner = Instance.new("UICorner")
popupCorner.CornerRadius = UDim.new(0, 8)
popupCorner.Parent = popupWindow

local popupStroke = Instance.new("UIStroke")
popupStroke.Thickness = 2
popupStroke.Color = BRONZE
popupStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
popupStroke.Parent = popupWindow

local popupHeader = Instance.new("Frame")
popupHeader.Name = "Header"
popupHeader.Size = UDim2.new(1, 0, 0, 30)
popupHeader.BackgroundColor3 = Color3.fromRGB(80, 60, 40)
popupHeader.BorderSizePixel = 0
popupHeader.Parent = popupWindow

local popupHeaderCorner = Instance.new("UICorner")
popupHeaderCorner.CornerRadius = UDim.new(0, 8)
popupHeaderCorner.Parent = popupHeader

local popupHeaderFix = Instance.new("Frame")
popupHeaderFix.Size = UDim2.new(1, 0, 0, 8)
popupHeaderFix.Position = UDim2.new(0, 0, 1, -8)
popupHeaderFix.BackgroundColor3 = popupHeader.BackgroundColor3
popupHeaderFix.BorderSizePixel = 0
popupHeaderFix.ZIndex = 0
popupHeaderFix.Parent = popupHeader

local popupTitle = Instance.new("TextLabel")
popupTitle.Name = "Title"
popupTitle.Size = UDim2.new(1, -34, 1, 0)
popupTitle.Position = UDim2.new(0, 8, 0, 0)
popupTitle.BackgroundTransparency = 1
popupTitle.Font = Enum.Font.FredokaOne
popupTitle.TextSize = 14
popupTitle.TextColor3 = Color3.fromRGB(255, 220, 150)
popupTitle.TextXAlignment = Enum.TextXAlignment.Left
popupTitle.TextTruncate = Enum.TextTruncate.AtEnd
popupTitle.Text = "🏰 ..."
popupTitle.Parent = popupHeader

local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.Size = UDim2.fromOffset(22, 22)
closeButton.Position = UDim2.new(1, -26, 0, 4)
closeButton.BackgroundColor3 = Color3.fromRGB(120, 40, 40)
closeButton.AutoButtonColor = true
closeButton.Font = Enum.Font.GothamBold
closeButton.TextSize = 13
closeButton.TextColor3 = Color3.fromRGB(255, 220, 150)
closeButton.Text = "X"
closeButton.Parent = popupHeader

local closeButtonCorner = Instance.new("UICorner")
closeButtonCorner.CornerRadius = UDim.new(0, 5)
closeButtonCorner.Parent = closeButton

local popupBody = Instance.new("TextLabel")
popupBody.Name = "Body"
popupBody.Position = UDim2.new(0, 8, 0, 36)
popupBody.Size = UDim2.new(1, -16, 1, -44)
popupBody.BackgroundTransparency = 1
popupBody.Font = Enum.Font.Gotham
popupBody.TextSize = 13
popupBody.TextColor3 = Color3.fromRGB(220, 200, 170)
popupBody.TextWrapped = true
popupBody.TextXAlignment = Enum.TextXAlignment.Left
popupBody.TextYAlignment = Enum.TextYAlignment.Top
popupBody.Text = ""
popupBody.Parent = popupWindow

local popupGeneration = 0

local function closePopup()
	popupGui.Enabled = false
end

closeButton.Activated:Connect(closePopup)

local function showInfoPopup(entry)
	if not entry.cityId then return end

	task.spawn(function()
		local ok, info = Net.Invoke("GetCityPublicInfo", entry.cityId)
		if not ok or not info or not info.exists then return end

		popupGeneration = popupGeneration + 1
		local myGeneration = popupGeneration

		popupTitle.Text = "🏰 " .. tostring(info.name or "?")
		popupBody.Text = ("Besitzer: %s\nGebäude: %d\nBevölkerung: %d")
			:format(
				tostring(info.ownerName or "Niemand"),
				math.floor(tonumber(info.buildingCount) or 0),
				math.floor(tonumber(info.population) or 0)
			)

		popupGui.Enabled = true

		-- Auto-Close nach 5 Sekunden (nur wenn zwischenzeitlich kein
		-- neueres Popup geöffnet wurde).
		task.delay(5, function()
			if myGeneration == popupGeneration then
				closePopup()
			end
		end)
	end)
end

--------------------------------------------------------------------------------
-- KLICK-VERHALTEN
--------------------------------------------------------------------------------
local function onBannerClicked(entry)
	if not entry.cityId then return end

	if entry.isMine then
		State.Toggle(State.Kind.CITY, entry.cityId)
	else
		showInfoPopup(entry)
	end
end

--------------------------------------------------------------------------------
-- DATEN LADEN (Owner-Farbe, Name, isMine) - über GetCityOnHex + GetCityPublicInfo
--------------------------------------------------------------------------------
local function applyBannerInfo(entry, info)
	local color = info.ownerColor or DEFAULT_COLOR
	entry.flag.BackgroundColor3 = color
	entry.tipLeft.BackgroundColor3 = color
	entry.tipRight.BackgroundColor3 = color
	entry.nameLabel.Text = tostring(info.name or "?")
	entry.isMine = info.isMine and true or false
end

local function refreshBannerData(entry)
	task.spawn(function()
		local ok1, cityOnHex = Net.Invoke("GetCityOnHex", entry.q, entry.r)
		if not ok1 or not cityOnHex or not cityOnHex.id then return end

		entry.cityId = cityOnHex.id
		bannerByCityId[entry.cityId] = entry.key

		local ok2, info = Net.Invoke("GetCityPublicInfo", entry.cityId)
		if not ok2 or not info or not info.exists then return end

		entry.info = info
		applyBannerInfo(entry, info)
	end)
end

--------------------------------------------------------------------------------
-- BANNER AN EIN CITY-GEBÄUDE ANHÄNGEN
--------------------------------------------------------------------------------
local function tryAttachCityBanner(buildingModel)
	local key, q, r = hexKeyFromBuildingName(buildingModel.Name)
	if not key then return end
	if banners[key] then return end -- schon vorhanden

	local ui = buildBannerGui(buildingModel)
	local entry = {
		key = key, q = q, r = r,
		billboard = ui.billboard,
		flag = ui.flag,
		tipLeft = ui.tipLeft,
		tipRight = ui.tipRight,
		nameLabel = ui.nameLabel,
		nameStroke = ui.nameStroke,
		flagStroke = ui.flagStroke,
		cityId = nil,
		info = nil,
		isMine = false,
		fogState = FogOfWarConfig.STATE.UNEXPLORED,
	}
	banners[key] = entry

	ui.clickButton.Activated:Connect(function()
		onBannerClicked(entry)
	end)

	refreshBannerData(entry)
end

local function removeBanner(name)
	local key = hexKeyFromBuildingName(name)
	if not key then return end
	local entry = banners[key]
	if not entry then return end

	if entry.billboard and entry.billboard.Parent then
		entry.billboard:Destroy()
	end
	if entry.cityId then
		bannerByCityId[entry.cityId] = nil
	end
	banners[key] = nil
end

--------------------------------------------------------------------------------
-- BUILDINGS-FOLDER BEOBACHTEN
--------------------------------------------------------------------------------
local function connectBuildingsWatcher()
	local hexMap = workspace:WaitForChild("HexMap", 30)
	if not hexMap then return end
	local buildingsFolder = hexMap:WaitForChild("Buildings", 30)
	if not buildingsFolder then return end

	for _, child in ipairs(buildingsFolder:GetChildren()) do
		tryAttachCityBanner(child)
	end

	buildingsFolder.ChildAdded:Connect(function(child)
		tryAttachCityBanner(child)
	end)

	buildingsFolder.ChildRemoved:Connect(function(child)
		removeBanner(child.Name)
	end)
end

task.spawn(connectBuildingsWatcher)

-- HexMap kann komplett neu gebaut werden (z.B. /regen) - dann alle Banner
-- verwerfen und neu aufbauen (analog zu FogOfWarController).
workspace.ChildAdded:Connect(function(child)
	if child.Name == "HexMap" then
		task.wait(1)
		for key, entry in pairs(banners) do
			if entry.billboard and entry.billboard.Parent then
				entry.billboard:Destroy()
			end
			banners[key] = nil
		end
		bannerByCityId = {}
		connectBuildingsWatcher()
	end
end)

--------------------------------------------------------------------------------
-- FOG-OF-WAR-EVENT ABONNIEREN (siehe FogOfWarController.setHexState)
--------------------------------------------------------------------------------
local hexStateEvent = ReplicatedStorage:WaitForChild("FogOfWarHexStateChanged", 30)
if hexStateEvent then
	hexStateEvent.Event:Connect(function(key, state)
		local entry = banners[key]
		if entry then
			applyFogState(entry, state)
		end
	end)
end

--------------------------------------------------------------------------------
-- CityStatsChanged (Server -> Client): Eroberung/Umbenennung -> Banner
-- neu einfärben (Test-Szenario l: Banner-Farbe wechselt nach Eroberung).
--------------------------------------------------------------------------------
Net.On("CityStatsChanged", function(cityId)
	local key = bannerByCityId[cityId]
	local entry = key and banners[key]
	if entry then
		task.delay(0.1, function()
			refreshBannerData(entry)
		end)
	end
end)

print("[CityBannerController] Bereit.")
