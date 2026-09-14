--[[
    CityBannerController (LocalScript)
    Ort: StarterPlayer > StarterPlayerScripts > CityBannerController

    Erzeugt über jeder Stadt ein komplett per Code generiertes Fantasy-
    Banner (BillboardGui) in der Farbe des Besitzers. Die Hauptstadt
    bekommt statt des normalen Banners ein groesseres, goldenes
    Hauptstadt-Banner mit Krone und Glow-Effekt (ersetzt den alten
    goldenen Stern aus CitySystem.addCapitalMarker).

    WICHTIGER BUGFIX (siehe unten "ADORNEE-BUG"):
        BillboardGui.Adornee akzeptiert laut Roblox-API NUR ein BasePart
        oder Attachment - NIEMALS ein Model. Die City-Gebaeude im
        Workspace ("City_q_r", siehe CitySystem.swapModelToCity) sind
        aber Models mit einem PrimaryPart. Der vorherige Code hat
        billboard.Adornee direkt auf das Model gesetzt -> das Banner
        wurde nirgendwo angedockt und war deshalb NIE sichtbar.
        FIX: Adornee wird jetzt auf model.PrimaryPart gesetzt (mit
        Fallback auf den ersten gefundenen BasePart, falls PrimaryPart
        fehlt).

    SICHTBARKEIT (folgt dem Fog-of-War, siehe FogOfWarController):
        unexplored -> Banner unsichtbar (BillboardGui.Enabled = false)
        explored   -> alle Elemente Transparency 0.5 (Geister-Look)
        visible    -> Rahmen/Text voll sichtbar (0), Innenfläche bleibt bei 0.2

    KLICK:
        eigenes Banner  -> ClientState.Toggle(CITY, cityId) (öffnet CityGui)
        fremdes Banner  -> Info-Popup (Name, Besitzer, Gebäude, Bevölkerung)

    Datenquelle: DataRemotes > GetCityOnHex (liefert die cityId für ein
    Hex) + DataRemotes > GetCityPublicInfo (liefert Name/Besitzer/Farbe/
    Gebäude/Bevölkerung/isCapital OHNE Besitz-Prüfung - für fremde
    Städte gedacht).
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
-- STIL
--------------------------------------------------------------------------------
local BRONZE = Color3.fromRGB(120, 90, 50)
local GOLD = Color3.fromRGB(255, 210, 60)
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

-- ADORNEE-BUG-FIX: BillboardGui.Adornee darf NUR ein BasePart oder
-- Attachment sein, niemals ein Model. City-Gebäude sind Models
-- (siehe CitySystem.swapModelToCity) - wir müssen also den PrimaryPart
-- (oder ersatzweise den ersten BasePart-Nachfahren) herausfinden.
local function findAdorneePart(buildingModel)
	if buildingModel:IsA("BasePart") then
		return buildingModel
	end
	if buildingModel:IsA("Model") then
		if buildingModel.PrimaryPart then
			return buildingModel.PrimaryPart
		end
		for _, child in ipairs(buildingModel:GetDescendants()) do
			if child:IsA("BasePart") then
				return child
			end
		end
	end
	return nil
end

-- DEDUPE-FIX (Schritt 5): entfernt ALLE bereits vorhandenen Banner-
-- BillboardGuis eines City-Gebäudes, egal ob sie (wie frueher, siehe
-- ADORNEE-BUG) direkt am Model haengen oder (aktuell korrekt) am
-- PrimaryPart. Wird IMMER unmittelbar VOR dem Erzeugen eines neuen
-- Banners aufgerufen, damit niemals mehr als 1 Banner pro Gebaeude
-- existiert - unabhaengig davon, ob die Altlast von einer frueheren
-- Skript-Version, einem Reload oder einer Race-Condition stammt.
local function destroyStrayBanners(buildingModel)
	local removed = 0
	for _, child in ipairs(buildingModel:GetDescendants()) do
		if child:IsA("BillboardGui") and (child.Name == "CityBanner" or child.Name == "CapitalBanner") then
			child:Destroy()
			removed = removed + 1
		end
	end
	-- Auch direkt am Model selbst pruefen (GetDescendants deckt das zwar
	-- schon ab, aber FindFirstChild ist ein billiger zusaetzlicher Check
	-- fuer den Fall, dass buildingModel selbst kein Model, sondern schon
	-- der Part ist).
	for _, name in ipairs({ "CityBanner", "CapitalBanner" }) do
		local direct = buildingModel:FindFirstChild(name)
		if direct and direct:IsA("BillboardGui") then
			direct:Destroy()
			removed = removed + 1
		end
	end
	if removed > 0 then
		print(("[Banner] %d verwaiste Banner-BillboardGui(s) an %s entfernt")
			:format(removed, buildingModel:GetFullName()))
	end
end


--------------------------------------------------------------------------------
-- BANNER-GUI ERZEUGEN (Fahnenform: Rechteck + 2 gedrehte Quadrate als
-- Spitzen an den Enden). isCapital=true -> groesseres Gold-Design mit
-- Krone und Glow, isCapital=false -> normales Bronze-Design.
--------------------------------------------------------------------------------
local function buildBannerGui(adorneePart, isCapital)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = isCapital and "CapitalBanner" or "CityBanner"
	billboard.Size = isCapital and UDim2.new(0, 250, 0, 70) or UDim2.new(0, 200, 0, 50)
	billboard.StudsOffset = isCapital and Vector3.new(0, 10, 0) or Vector3.new(0, 8, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 500
	billboard.ResetOnSpawn = false
	billboard.Enabled = false -- Fog-of-War entscheidet, wann es erscheint
	billboard.Adornee = adorneePart
	billboard.Parent = adorneePart
	print("[Banner] BillboardGui erstellt fuer " .. adorneePart:GetFullName()
		.. (isCapital and " (HAUPTSTADT)" or ""))
	print("[Banner] Enabled:", billboard.Enabled,
		"| Adornee:", billboard.Adornee and billboard.Adornee:GetFullName() or "nil",
		"| StudsOffset:", billboard.StudsOffset,
		"| Size:", billboard.Size,
		"| MaxDistance:", billboard.MaxDistance)

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.ClipsDescendants = false
	root.Parent = billboard

	-- Gold-Glow (nur Hauptstadt): leicht groesserer Frame HINTER der
	-- Fahne mit hoher Transparenz, erzeugt einen sanften Leucht-Effekt.
	local glow = nil
	if isCapital then
		glow = Instance.new("Frame")
		glow.Name = "Glow"
		glow.AnchorPoint = Vector2.new(0.5, 0.5)
		glow.Position = UDim2.new(0.5, 0, 0.5, 0)
		glow.Size = UDim2.new(1, -12, 1, 10)
		glow.BackgroundColor3 = GOLD
		glow.BackgroundTransparency = 0.7
		glow.BorderSizePixel = 0
		glow.ZIndex = 1
		glow.Parent = root

		local glowCorner = Instance.new("UICorner")
		glowCorner.CornerRadius = UDim.new(0, 8)
		glowCorner.Parent = glow
	end

	-- Hauptfläche der Fahne
	local flag = Instance.new("Frame")
	flag.Name = "Flag"
	flag.AnchorPoint = Vector2.new(0.5, 0.5)
	flag.Position = UDim2.new(0.5, 0, 0.5, 0)
	flag.Size = isCapital and UDim2.new(1, -34, 1, 0) or UDim2.new(1, -28, 1, 0)
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
	flagStroke.Thickness = isCapital and 3 or 2
	flagStroke.Color = isCapital and GOLD or BRONZE
	flagStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	flagStroke.Parent = flag

	-- Fahnen-Spitzen: kleine, um 45° gedrehte Quadrate links/rechts, damit
	-- die Fahne spitz zulaufend statt rein rechteckig wirkt.
	local function makeTip(anchorX, name)
		local size = isCapital and 18 or 14
		local tip = Instance.new("Frame")
		tip.Name = name
		tip.AnchorPoint = Vector2.new(0.5, 0.5)
		tip.Position = UDim2.new(anchorX, 0, 0.5, 0)
		tip.Size = UDim2.fromOffset(size, size)
		tip.Rotation = 45
		tip.BackgroundColor3 = DEFAULT_COLOR
		tip.BackgroundTransparency = 0.2
		tip.BorderSizePixel = 0
		tip.ZIndex = 1
		tip.Parent = root

		local tipStroke = Instance.new("UIStroke")
		tipStroke.Thickness = isCapital and 3 or 2
		tipStroke.Color = isCapital and GOLD or BRONZE
		tipStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		tipStroke.Parent = tip

		return tip
	end

	local tipLeft = makeTip(0.015, "TipLeft")
	local tipRight = makeTip(0.985, "TipRight")

	-- Hauptstadt: zweizeilig - "👑 HAUPTSTADT 👑" oben, Stadtname unten.
	local crownLabel = nil
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "CityName"
	nameLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.FredokaOne
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextWrapped = true
	nameLabel.TextScaled = false
	nameLabel.Text = "..."
	nameLabel.ZIndex = 3
	nameLabel.Parent = flag

	if isCapital then
		crownLabel = Instance.new("TextLabel")
		crownLabel.Name = "CrownLabel"
		crownLabel.AnchorPoint = Vector2.new(0.5, 0)
		crownLabel.Position = UDim2.new(0.5, 0, 0, 2)
		crownLabel.Size = UDim2.new(1, -12, 0, 22)
		crownLabel.BackgroundTransparency = 1
		crownLabel.Font = Enum.Font.FredokaOne
		crownLabel.TextSize = 15
		crownLabel.TextColor3 = GOLD
		crownLabel.Text = "👑 HAUPTSTADT 👑"
		crownLabel.ZIndex = 3
		crownLabel.Parent = flag

		local crownStroke = Instance.new("UIStroke")
		crownStroke.Thickness = 2
		crownStroke.Color = Color3.fromRGB(0, 0, 0)
		crownStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Outline
		crownStroke.Parent = crownLabel

		nameLabel.Position = UDim2.new(0.5, 0, 1, -4)
		nameLabel.AnchorPoint = Vector2.new(0.5, 1)
		nameLabel.Size = UDim2.new(1, -12, 0, 24)
		nameLabel.TextSize = 15
	else
		nameLabel.Position = UDim2.fromScale(0.5, 0.5)
		nameLabel.Size = UDim2.new(1, -12, 1, -4)
		nameLabel.TextSize = 14
	end

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
		glow = glow,
		crownLabel = crownLabel,
		isCapital = isCapital,
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
	if entry.crownLabel then
		entry.crownLabel.TextTransparency = textT
	end
	if entry.glow then
		-- Glow bleibt immer dezenter als die Fahne selbst.
		entry.glow.BackgroundTransparency = math.clamp(fillT + 0.5, 0, 1)
	end
end

local function applyFogState(entry, state)
	if state == FogOfWarConfig.STATE.UNEXPLORED then
		entry.billboard.Enabled = false
		entry.fogState = state
		return
	end

	entry.billboard.Enabled = true
	if state == FogOfWarConfig.STATE.VISIBLE then
		setElementsTransparency(entry, 0.2, 0, 0)
	else -- EXPLORED
		setElementsTransparency(entry, 0.5, 0.5, 0.5)
	end
	entry.fogState = state

	print(("[Banner] Fog-Status fuer %s: %s -> Enabled: %s")
		:format(entry.key, tostring(state), tostring(entry.billboard.Enabled)))
end

-- Aktuellen Fog-Zustand eines Hex ermitteln. Bevorzugt die synchrone
-- _G.GetFogHexState-Abfrage aus FogOfWarController (deckt den Fall ab,
-- dass ein Gebäude/Banner ERST NACH dem letzten Zustandswechsel des Hex
-- entsteht - z.B. beim Nachladen oder bei einer neu gegründeten Stadt in
-- bereits erkundetem Gebiet). Fällt sonst auf UNEXPLORED zurück, bis das
-- naechste FogOfWarHexStateChanged-Event eintrifft.
local function currentFogState(key)
	if type(_G.GetFogHexState) == "function" then
		local ok, state = pcall(_G.GetFogHexState, key)
		if ok and state then return state end
	end
	return FogOfWarConfig.STATE.UNEXPLORED
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

		popupTitle.Text = (info.isCapital and "👑 " or "🏰 ") .. tostring(info.name or "?")
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
-- DATEN LADEN (Owner-Farbe, Name, isMine, isCapital) - über GetCityOnHex +
-- GetCityPublicInfo. Wenn sich isCapital seit dem letzten Refresh geändert
-- hat (z.B. weil die Stadt gerade zur Hauptstadt wurde, oder umgekehrt
-- nach einer Eroberung nicht mehr), wird das Banner komplett neu gebaut
-- (Normal- <-> Hauptstadtbanner haben unterschiedliches Layout).
--------------------------------------------------------------------------------
local rebuildBanner -- forward-declaration (siehe unten)

local function applyBannerInfo(entry, info)
	local color = info.ownerColor or DEFAULT_COLOR
	entry.flag.BackgroundColor3 = color
	entry.tipLeft.BackgroundColor3 = color
	entry.tipRight.BackgroundColor3 = color
	entry.nameLabel.Text = tostring(info.name or "?")
	entry.isMine = info.isMine and true or false

	print(("[Banner] Owner: %s, Farbe: %s, Text: %s")
		:format(tostring(info.ownerName), tostring(color), tostring(info.name)))
end

-- RETRY-FIX (Schritt 2/3): GetCityOnHex/GetCityPublicInfo koennen kurz
-- nach dem Erstellen eines Banners fehlschlagen (Remote noch nicht
-- repliziert, CityData auf dem Server noch nicht committed, Netzwerk-
-- Hickup, ...). Der alte Code hat bei einem einzigen fehlgeschlagenen
-- Invoke einfach aufgegeben - das Banner blieb dann fuer immer beim
-- Platzhaltertext "..." und der grauen Default-Farbe haengen, weil
-- NICHTS sonst automatisch einen erneuten Versuch ausgeloest hat.
-- Jetzt wird bei einem Fehlschlag bis zu MAX_RETRIES mal erneut
-- versucht (mit kurzer Wartezeit dazwischen).
local MAX_RETRIES = 8
local RETRY_DELAY = 0.5

local function refreshBannerData(entry, attempt)
	attempt = attempt or 1

	task.spawn(function()
		local ok1, cityOnHex = Net.Invoke("GetCityOnHex", entry.q, entry.r)
		if not ok1 or not cityOnHex or not cityOnHex.id then
			warn(("[Banner] GetCityOnHex fehlgeschlagen fuer %s (Versuch %d/%d)")
				:format(entry.key, attempt, MAX_RETRIES))
			if attempt < MAX_RETRIES then
				task.delay(RETRY_DELAY, function() refreshBannerData(entry, attempt + 1) end)
			end
			return
		end

		entry.cityId = cityOnHex.id
		bannerByCityId[entry.cityId] = entry.key

		local ok2, info = Net.Invoke("GetCityPublicInfo", entry.cityId)
		if not ok2 or not info or not info.exists then
			warn(("[Banner] GetCityPublicInfo fehlgeschlagen fuer City %s (Versuch %d/%d)")
				:format(tostring(entry.cityId), attempt, MAX_RETRIES))
			if attempt < MAX_RETRIES then
				task.delay(RETRY_DELAY, function() refreshBannerData(entry, attempt + 1) end)
			end
			return
		end

		local wantsCapital = info.isCapital and true or false
		if wantsCapital ~= entry.isCapital then
			-- Hauptstadt-Status hat sich geändert -> Banner-Layout muss
			-- gewechselt werden (Normal <-> Hauptstadtbanner).
			print(("[Banner] Hauptstadt-Status von %s geaendert -> Banner wird neu gebaut")
				:format(tostring(info.name)))
			rebuildBanner(entry, wantsCapital)
			return
		end

		entry.info = info
		applyBannerInfo(entry, info)
	end)
end

--------------------------------------------------------------------------------
-- BANNER AN EIN CITY-GEBÄUDE ANHÄNGEN
--------------------------------------------------------------------------------
local function attachBannerUi(buildingModel, isCapital)
	local adorneePart = findAdorneePart(buildingModel)
	if not adorneePart then
		warn("[Banner] Kein BasePart in " .. buildingModel:GetFullName()
			.. " gefunden - Banner kann nicht angedockt werden!")
		return nil
	end
	-- Schritt 5: sicherstellen, dass vor dem Neubau KEIN Alt-Banner mehr
	-- an diesem Gebäude haengt (verhindert Duplikate).
	destroyStrayBanners(buildingModel)
	return buildBannerGui(adorneePart, isCapital)
end

local function tryAttachCityBanner(buildingModel)
	local key, q, r = hexKeyFromBuildingName(buildingModel.Name)
	if not key then return end
	if banners[key] then return end -- schon vorhanden

	print("[Banner] Gefunden: " .. buildingModel.Name)

	local ui = attachBannerUi(buildingModel, false)
	if not ui then return end

	local entry = {
		key = key, q = q, r = r,
		buildingModel = buildingModel,
		billboard = ui.billboard,
		flag = ui.flag,
		tipLeft = ui.tipLeft,
		tipRight = ui.tipRight,
		nameLabel = ui.nameLabel,
		nameStroke = ui.nameStroke,
		flagStroke = ui.flagStroke,
		glow = ui.glow,
		crownLabel = ui.crownLabel,
		cityId = nil,
		info = nil,
		isMine = false,
		isCapital = false,
		fogState = FogOfWarConfig.STATE.UNEXPLORED,
	}
	banners[key] = entry

	ui.clickButton.Activated:Connect(function()
		onBannerClicked(entry)
	end)

	-- Sofort den AKTUELLEN Fog-Zustand anwenden (nicht erst auf das
	-- naechste Event warten - siehe currentFogState()).
	applyFogState(entry, currentFogState(key))

	refreshBannerData(entry)
end

-- rebuildBanner(entry, isCapital): zerstört das bestehende Banner-GUI
-- eines Eintrags und baut es mit dem jeweils passenden Layout
-- (Normal-/Hauptstadtbanner) neu auf. Wird gebraucht, wenn sich der
-- Hauptstadt-Status einer bereits bekannten Stadt ändert.
rebuildBanner = function(entry, isCapital)
	if entry.billboard and entry.billboard.Parent then
		entry.billboard:Destroy()
	end

	local ui = attachBannerUi(entry.buildingModel, isCapital)
	if not ui then return end

	entry.billboard = ui.billboard
	entry.flag = ui.flag
	entry.tipLeft = ui.tipLeft
	entry.tipRight = ui.tipRight
	entry.nameLabel = ui.nameLabel
	entry.nameStroke = ui.nameStroke
	entry.flagStroke = ui.flagStroke
	entry.glow = ui.glow
	entry.crownLabel = ui.crownLabel
	entry.isCapital = isCapital

	ui.clickButton.Activated:Connect(function()
		onBannerClicked(entry)
	end)

	applyFogState(entry, currentFogState(entry.key))
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
	print("[Banner] Suche Cities in Buildings...")

	local hexMap = workspace:WaitForChild("HexMap", 30)
	if not hexMap then
		warn("[Banner] workspace.HexMap nicht gefunden (Timeout)")
		return
	end
	local buildingsFolder = hexMap:WaitForChild("Buildings", 30)
	if not buildingsFolder then
		warn("[Banner] HexMap.Buildings nicht gefunden (Timeout)")
		return
	end

	for _, child in ipairs(buildingsFolder:GetChildren()) do
		tryAttachCityBanner(child)
	end

	-- Neu gebaute/replizierte Cities bekommen SOFORT ein Banner.
	buildingsFolder.ChildAdded:Connect(function(child)
		if child.Name:match("^City_") then
			tryAttachCityBanner(child)
		end
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
else
	warn("[Banner] FogOfWarHexStateChanged-Event nicht gefunden - Banner-Sichtbarkeit bleibt ggf. unsynchron!")
end

--------------------------------------------------------------------------------
-- CityStatsChanged (Server -> Client): Eroberung/Umbenennung -> Banner
-- neu einfärben (Test-Szenario: Banner-Farbe wechselt nach Eroberung).
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

--------------------------------------------------------------------------------
-- CapitalCityMarked (Server -> Client): eine neue Hauptstadt wurde
-- gegründet -> das betroffene Banner (falls schon geladen) sofort auf
-- Hauptstadt-Layout umstellen, ohne auf das naechste CityStatsChanged
-- warten zu muessen.
--------------------------------------------------------------------------------
Net.On("CapitalCityMarked", function(payload)
	if not payload or not payload.cityId then return end
	local key = bannerByCityId[payload.cityId]
	local entry = key and banners[key]
	if entry then
		task.delay(0.1, function()
			refreshBannerData(entry)
		end)
	end
end)

print("[CityBannerController] Bereit.")
