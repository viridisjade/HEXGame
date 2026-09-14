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

    BANNER-GARANTIEN (Fix "City-Banner nicht sichtbar"):
        1. GENAU EIN Banner pro City-Gebaeude. Vor UND nach dem Erzeugen
           wird aufgeraeumt (destroyStrayBanners/enforceSingleBanner),
           zusaetzlich gibt es einen periodischen Dedupe-Sweep.
        2. Der Banner-Text ist IMMER der Stadtname aus CityData - der
           Platzhalter "..." bleibt niemals dauerhaft stehen (Retries +
           Heal-Loop, siehe refreshBannerData).
        3. Die Banner-Farbe ist IMMER die Spielerfarbe des Besitzers
           (kommt vom Server via GetCityPublicInfo.ownerColor, denn
           PlayerColorConfig liegt in ServerScriptService und ist fuer
           den Client nicht erreichbar). Grau gibt es NUR noch fuer
           besitzlose Staedte (eliminierte Spieler).
        4. Enabled = false ist NUR der Fog-Zustand "unexplored". Eigene
           Staedte sind immer sichtbar (eine eigene Stadt ist selbst eine
           Sichtquelle), und fehlt die Fog-Quelle komplett (FogOfWar-
           Controller laedt noch/fehlt), wird das Banner NICHT dauerhaft
           versteckt (Fail-Open + Heal-Loop).
        5. Besitzerwechsel (Eroberung, Eliminierung) und Hauptstadt-
           Status aendern Farbe/Text/Layout sofort, nicht erst irgendwann.

    HINWEIS ZUR ARCHITEKTUR: Die Banner werden bewusst CLIENTSEITIG per
    Code erzeugt (Projekt-Konvention "komplett code-generierte GUI") und
    NICHT serverseitig ins City-Model gehaengt: Die Sichtbarkeit muss pro
    Spieler dem Fog-of-War folgen, ein serverseitiges BillboardGui wuerde
    aber an ALLE Clients replizieren. Das Template
    ReplicatedStorage > Buildings > City bleibt deshalb banner-frei.

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

print("[CityBannerController v2] geladen (LocalScript laeuft)"
	.. " - Banner werden ausschliesslich von diesem Script erzeugt (Owner-Marker:"
	.. " CityBannerController-v2). Erscheint diese Zeile DOPPELT im Output,"
	.. " laeuft eine zweite Banner-Script-Instanz im Place.")

--------------------------------------------------------------------------------
-- STIL
--------------------------------------------------------------------------------
local BRONZE = Color3.fromRGB(120, 90, 50)
local GOLD = Color3.fromRGB(255, 210, 60)

-- Platzhalter-Farbe, solange die Owner-Daten noch nicht angekommen sind.
local DEFAULT_COLOR = Color3.fromRGB(140, 140, 140)

-- Farbe fuer BESITZLOSE Staedte (z.B. nach der Eliminierung des Besitzers,
-- siehe VictorySystem.EliminatePlayer -> city.owner = nil). Das ist der
-- einzige Fall, in dem ein Banner dauerhaft grau sein darf.
local NEUTRAL_COLOR = Color3.fromRGB(128, 128, 128)

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------
local banners = {}        -- [hexKey] = bannerEntry
local bannerByCityId = {} -- [cityId] = hexKey

-- Wird von currentFogState() gepflegt: steht auf false, solange der
-- FogOfWarController keine Zustandsabfrage anbietet (_G.GetFogHexState).
-- Der Heal-Loop nutzt das, um Banner nachzuladen, die sonst nie ein
-- FogOfWarHexStateChanged-Event bekommen wuerden.
local fogSourceAvailable = false

--------------------------------------------------------------------------------
-- OWNER-MARKER + BANNER-NAMEN
--
-- Jedes von DIESEM Script erzeugte Banner traegt das Attribut "BannerOwner".
-- Damit lassen sich eigene Banner von FREMD-Bannern unterscheiden. Das ist
-- die Diagnose fuer den gemeldeten Befund "oft ZWEI BillboardGuis namens
-- CityBanner unter dem Part": Diese eine Script-Version kann keine zwei
-- Banner offen lassen (destroyStrayBanners VOR + enforceSingleBanner NACH
-- dem Erzeugen + Dedupe-Sweep). Taucht trotzdem regelmaessig ein Banner
-- OHNE Marker auf, laeuft im Place eine ZWEITE (aeltere, z.B. manuell in
-- Studio angelegte und nie von Rojo ersetzte) Banner-Script-Instanz -
-- die dann auch fuer Enabled=false/"..."/grau verantwortlich ist.
--------------------------------------------------------------------------------
local BANNER_OWNER_TAG = "CityBannerController-v2"

local function isBannerGui(instance)
	return instance:IsA("BillboardGui")
		and (instance.Name == "CityBanner" or instance.Name == "CapitalBanner")
end

local function isOwnBanner(instance)
	return isBannerGui(instance) and instance:GetAttribute("BannerOwner") == BANNER_OWNER_TAG
end

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

-- DEDUPE-FIX: entfernt AGGRESSIV ALLE bereits vorhandenen Banner-
-- BillboardGuis eines City-Gebäudes, egal ob sie (wie frueher, siehe
-- ADORNEE-BUG) direkt am Model haengen oder (aktuell korrekt) am
-- PrimaryPart. Wird IMMER unmittelbar VOR dem Erzeugen eines neuen
-- Banners aufgerufen, damit niemals mehr als 1 Banner pro Gebaeude
-- existiert - unabhaengig davon, ob die Altlast von einer frueheren
-- Skript-Version, einem Reload oder einer Race-Condition stammt.
local function destroyStrayBanners(buildingModel)
	local removed = 0
	local foreign = 0

	for _, child in ipairs(buildingModel:GetDescendants()) do
		if isBannerGui(child) then
			if not isOwnBanner(child) then
				foreign = foreign + 1
			end
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
			if not isOwnBanner(direct) then
				foreign = foreign + 1
			end
			direct:Destroy()
			removed = removed + 1
		end
	end

	if foreign > 0 then
		warn(("[Banner] DIAGNOSE: %d Banner OHNE Owner-Marker (%s) an %s entfernt."
			.. " Laeuft im Place eine zweite/aeltere Banner-Script-Instanz?"
			.. " (Studio -> StarterPlayerScripts auf doppelte LocalScripts pruefen)")
			:format(foreign, BANNER_OWNER_TAG, buildingModel:GetFullName()))
	end
	if removed > 0 then
		print(("[Banner] %d verwaiste Banner-BillboardGui(s) an %s entfernt")
			:format(removed, buildingModel:GetFullName()))
	end
	return removed
end

-- SINGLE-BANNER-GARANTIE (Fix "teilweise 2 Banner im Model"):
-- Laesst an einem City-Gebaeude GENAU EIN Banner stehen. keepBillboard
-- bleibt erhalten, jede andere Banner-BillboardGui wird entfernt -
-- unabhaengig davon, woher sie stammt (Altlast einer frueheren Version,
-- parallel laufender Rebuild, zweite Script-Instanz, Model das aus einem
-- alten Spielstand geladen wurde, ...). Wird nach jedem Erzeugen und
-- periodisch im Heal-Loop aufgerufen.
local function enforceSingleBanner(buildingModel, keepBillboard)
	if not buildingModel or not buildingModel.Parent then return 0 end

	local removed = 0
	local foreign = 0

	for _, child in ipairs(buildingModel:GetDescendants()) do
		if isBannerGui(child) and child ~= keepBillboard then
			if not isOwnBanner(child) then
				foreign = foreign + 1
			end
			child:Destroy()
			removed = removed + 1
		end
	end

	-- Direkt am Model angedockte Banner (Adornee-auf-Model-Altlast).
	for _, name in ipairs({ "CityBanner", "CapitalBanner" }) do
		local direct = buildingModel:FindFirstChild(name)
		if direct and direct:IsA("BillboardGui") and direct ~= keepBillboard then
			if not isOwnBanner(direct) then
				foreign = foreign + 1
			end
			direct:Destroy()
			removed = removed + 1
		end
	end

	if foreign > 0 then
		warn(("[Banner] DIAGNOSE: %d doppelte(s) Banner OHNE Owner-Marker (%s) an %s entfernt."
			.. " Verdacht: eine zweite/aeltere Banner-Script-Instanz im Place erzeugt sie neu.")
			:format(foreign, BANNER_OWNER_TAG, buildingModel:GetFullName()))
	end
	if removed > 0 then
		warn(("[Banner] %d doppelte Banner-BillboardGui(s) an %s entfernt - nur 1 pro City erlaubt")
			:format(removed, buildingModel:GetFullName()))
	end
	return removed
end


--------------------------------------------------------------------------------
-- BANNER-GUI ERZEUGEN (Fahnenform: Rechteck + 2 gedrehte Quadrate als
-- Spitzen an den Enden). isCapital=true -> groesseres Gold-Design mit
-- Krone und Glow, isCapital=false -> normales Bronze-Design.
--------------------------------------------------------------------------------
local function buildBannerGui(adorneePart, isCapital, initialText, initialColor)
	-- Bekanntes Aussehen direkt mitnehmen (Rebuild nach Besitzerwechsel /
	-- Hauptstadt-Wechsel), damit nie kurz der Platzhalter aufblitzt.
	local fillColor = initialColor or DEFAULT_COLOR

	local billboard = Instance.new("BillboardGui")
	billboard.Name = isCapital and "CapitalBanner" or "CityBanner"
	-- Owner-Marker: kennzeichnet dieses Banner als von DIESEM Script erzeugt
	-- (Basis fuer die Fremd-Banner-Diagnose in destroyStrayBanners /
	-- enforceSingleBanner).
	billboard:SetAttribute("BannerOwner", BANNER_OWNER_TAG)
	billboard.Size = isCapital and UDim2.new(0, 250, 0, 70) or UDim2.new(0, 200, 0, 50)
	billboard.StudsOffset = isCapital and Vector3.new(0, 10, 0) or Vector3.new(0, 8, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 500
	billboard.ResetOnSpawn = false
	-- Enabled startet auf false und wird UNMITTELBAR danach von
	-- applyFogState() gesetzt (siehe tryAttachCityBanner/rebuildBanner):
	--   unexplored           -> false
	--   explored / visible   -> true
	--   eigene Stadt         -> true (immer, auch ohne Fog-Information)
	-- Kein anderer Code-Pfad darf dieses Banner dauerhaft auf false
	-- stehen lassen - der Heal-Loop am Dateiende prueft das nach.
	billboard.Enabled = false
	billboard.Adornee = adorneePart
	billboard.Parent = adorneePart
	print(("[Banner] %s erstellt an %s | Adornee: %s | Size: %s | StudsOffset: %s | MaxDistance: %d | AlwaysOnTop: %s")
		:format(
			billboard.Name,
			adorneePart:GetFullName(),
			billboard.Adornee and billboard.Adornee:GetFullName() or "nil",
			tostring(billboard.Size),
			tostring(billboard.StudsOffset),
			billboard.MaxDistance,
			tostring(billboard.AlwaysOnTop)
		))
	-- Hinweis: Enabled wird direkt danach von applyFogState() gesetzt.

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
	flag.BackgroundColor3 = fillColor
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
		tip.BackgroundColor3 = fillColor
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
	-- Platzhalter, bis applyBannerInfo() den echten Stadtnamen setzt.
	-- Darf nicht dauerhaft stehen bleiben (siehe refreshBannerData).
	nameLabel.Text = initialText or "..."
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

-- Setzt die Banner-Sichtbarkeit aus dem Fog-Zustand.
-- REGEL: Enabled = false darf NUR bei "unexplored" vorkommen (und auch da
-- nicht bei der eigenen Stadt). Das ist die einzige Stelle im Projekt, die
-- ein City-Banner auf Enabled = false setzt - der FogOfWarController selbst
-- fasst BillboardGuis bewusst NICHT an (er arbeitet nur mit Transparency
-- auf BaseParts/Decals/Textures).
local function applyFogState(entry, state)
	if not entry or not entry.billboard or not entry.billboard.Parent then return end

	-- EIGENE Stadt -> immer sichtbar. Eine eigene Stadt ist selbst eine
	-- Sichtquelle (FogOfWarConfig.CITY_SIGHT = 3), ihr Hex kann also
	-- regelmaessig gar nicht "unexplored" sein. Falls doch (Fog-State
	-- gerade nicht verfuegbar), soll das eigene Banner trotzdem sichtbar
	-- sein, statt unsichtbar haengen zu bleiben.
	local forceVisible = entry.isMine == true

	if state == FogOfWarConfig.STATE.UNEXPLORED and not forceVisible then
		entry.billboard.Enabled = false
		entry.fogState = state
		return
	end

	entry.billboard.Enabled = true
	if state == FogOfWarConfig.STATE.EXPLORED and not forceVisible then
		-- erkundet, aber gerade nicht im Sichtfeld -> Geister-Look
		setElementsTransparency(entry, 0.5, 0.5, 0.5)
	else
		-- sichtbar (oder eigene Stadt)
		setElementsTransparency(entry, 0.2, 0, 0)
	end
	entry.fogState = state
end

-- Aktuellen Fog-Zustand eines Hex ermitteln. Bevorzugt die synchrone
-- _G.GetFogHexState-Abfrage aus FogOfWarController (deckt den Fall ab,
-- dass ein Gebäude/Banner ERST NACH dem letzten Zustandswechsel des Hex
-- entsteht - z.B. beim Nachladen oder bei einer neu gegründeten Stadt in
-- bereits erkundetem Gebiet).
--
-- FAIL-OPEN-STATT-FAIL-BLIND: Ist die Fog-Quelle (noch) nicht verfuegbar,
-- wurde VISIBLE zurueckgegeben statt UNEXPLORED. Grund: UNEXPLORED haette
-- das Banner auf Enabled = false gesetzt, und ohne FogOfWarController
-- feuert auch niemals ein FogOfWarHexStateChanged-Event -> das Banner
-- bliebe FUER IMMER unsichtbar (genau das gemeldete Bug-Bild). Der
-- Heal-Loop korrigiert den Zustand spaeter auf den echten Wert, sobald
-- _G.GetFogHexState existiert.
local function currentFogState(key)
	if type(_G.GetFogHexState) == "function" then
		local ok, state = pcall(_G.GetFogHexState, key)
		if ok and state then
			fogSourceAvailable = true
			return state
		end
	end

	fogSourceAvailable = false
	return FogOfWarConfig.STATE.VISIBLE
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

-- MAX_FAST_RETRIES schnelle Versuche, danach unbegrenzt viele langsame
-- Versuche (SLOW_RETRY_DELAY) bzw. der Heal-Loop am Dateiende.
local MAX_FAST_RETRIES = 8
local FAST_RETRY_DELAY = 0.5
local SLOW_RETRY_DELAY = 5

-- Wendet die Owner-Daten (Name, Farbe, isMine) auf ein bestehendes Banner
-- an. Das ist die EINZIGE Stelle, die Text und Farbe setzt:
--   Text  = Stadtname aus CityData (via GetCityPublicInfo.name)
--   Farbe = Spielerfarbe des Besitzers (via GetCityPublicInfo.ownerColor)
-- Der Platzhalter "..." und die graue Default-Farbe aus buildBannerGui
-- werden hier ersetzt - und bleiben nie dauerhaft stehen, weil
-- refreshBannerData() bei fehlgeschlagenen Abfragen immer wieder neu
-- ansetzt (Retries + Heal-Loop).
local function applyBannerInfo(entry, info)
	-- Besitzlos (city.owner == nil, z.B. nach Eliminierung) -> neutral grau.
	-- Besitzer vorhanden aber Farbe fehlt -> ebenfalls Fallback, damit das
	-- Banner nie farblos/unlesbar wird.
	local color = info.ownerColor
	if not color then
		color = info.ownerUserId and DEFAULT_COLOR or NEUTRAL_COLOR
	end

	entry.flag.BackgroundColor3 = color
	entry.tipLeft.BackgroundColor3 = color
	entry.tipRight.BackgroundColor3 = color
	entry.nameLabel.Text = tostring(info.name or "?")
	entry.info = info
	entry.dataResolved = true
	entry.isMine = info.isMine and true or false

	-- isMine kann die Sichtbarkeitsregel aendern (eigene Stadt = immer
	-- sichtbar), deshalb den Fog-Zustand direkt neu lesen und anwenden
	-- (billige lokale Abfrage, kein RPC).
	applyFogState(entry, currentFogState(entry.key))
end

-- RETRY-/HEAL-FIX: GetCityOnHex/GetCityPublicInfo koennen kurz nach dem
-- Erstellen eines Banners fehlschlagen (Remote noch nicht repliziert,
-- CityData auf dem Server noch nicht committed, Netzwerk-Hickup, ...).
-- Der urspruengliche Code hat nach einem einzigen Fehlschlag aufgegeben -
-- das Banner blieb dann FUER IMMER beim Platzhaltertext "..." und der
-- grauen Default-Farbe, weil nichts sonst einen erneuten Versuch ausgeloest
-- hat. Ausserdem war bannerByCityId[cityId] nie gefuellt, wodurch auch das
-- CityStatsChanged-Event (Eroberung!) dieses Banner nicht mehr erreichen
-- konnte - doppelt tot.
--
-- JETZT:
--   * bis zu MAX_FAST_RETRIES schnelle Versuche (0.5s)
--   * danach unbegrenzt langsame Versuche (5s)
--   * zusaetzlich prueft der Heal-Loop am Dateiende unaufgeloeste Banner
--   * entry.refreshing/refreshQueued verhindert parallele Doppel-Refreshes
--     (die frueher zu doppelt gebauten Bannern fuehren konnten), ohne dass
--     ein Event verloren geht.
local function refreshBannerData(entry, attempt)
	attempt = attempt or 1
	if not entry or not entry.billboard or not entry.billboard.Parent then return end

	if entry.refreshing then
		entry.refreshQueued = true -- nicht vergessen, nach dem laufenden Durchlauf nachholen
		return
	end
	entry.refreshing = true

	task.spawn(function()
		local info = nil

		local ok1, cityOnHex = Net.Invoke("GetCityOnHex", entry.q, entry.r)
		if ok1 and cityOnHex and cityOnHex.id then
			entry.cityId = cityOnHex.id
			bannerByCityId[entry.cityId] = entry.key

			local ok2, result = Net.Invoke("GetCityPublicInfo", entry.cityId)
			if ok2 and result and result.exists then
				info = result
			elseif attempt <= MAX_FAST_RETRIES then
				warn(("[Banner] GetCityPublicInfo fehlgeschlagen fuer City %s (Versuch %d/%d)")
					:format(tostring(entry.cityId), attempt, MAX_FAST_RETRIES))
			end
		elseif attempt <= MAX_FAST_RETRIES then
			warn(("[Banner] GetCityOnHex fehlgeschlagen fuer %s (Versuch %d/%d)")
				:format(entry.key, attempt, MAX_FAST_RETRIES))
		end

		entry.refreshing = false

		-- Nach dem laufenden Durchlauf noch ein offenes Event? -> sofort erneut.
		local function runQueued()
			if entry.refreshQueued then
				entry.refreshQueued = false
				refreshBannerData(entry, attempt)
			end
		end

		if not info then
			-- Noch keine Daten: spaeter erneut versuchen (schnell, dann langsam).
			entry.pendingRetry = true
			local delay = (attempt <= MAX_FAST_RETRIES) and FAST_RETRY_DELAY or SLOW_RETRY_DELAY
			task.delay(delay, function()
				entry.pendingRetry = nil
				refreshBannerData(entry, attempt + 1)
			end)
			runQueued()
			return
		end

		local wantsCapital = info.isCapital and true or false
		if wantsCapital ~= entry.isCapital then
			-- Hauptstadt-Status hat sich geaendert -> Banner-Layout muss
			-- gewechselt werden (Normal <-> Hauptstadtbanner).
			-- WICHTIG: entry.info VOR dem Rebuild setzen, damit das neue
			-- Banner sofort Name/Farbe kennt (kein "..."-Blitz) und ein
			-- fehlgeschlagener Rebuild nicht in einer Endlosschleife landet.
			entry.info = info
			entry.dataResolved = true
			print(("[Banner] Hauptstadt-Status von %s geaendert -> Banner wird neu gebaut")
				:format(tostring(info.name)))
			rebuildBanner(entry, wantsCapital)
			runQueued()
			return
		end

		applyBannerInfo(entry, info)
		runQueued()
	end)
end

--------------------------------------------------------------------------------
-- BANNER AN EIN CITY-GEBÄUDE ANHÄNGEN
--------------------------------------------------------------------------------
local function attachBannerUi(buildingModel, isCapital, initialText, initialColor)
	local adorneePart = findAdorneePart(buildingModel)
	if not adorneePart then
		warn("[Banner] Kein BasePart in " .. buildingModel:GetFullName()
			.. " gefunden - Banner kann nicht angedockt werden!")
		return nil
	end

	-- VOR dem Neubau: sicherstellen, dass kein Alt-Banner mehr an diesem
	-- Gebaeude haengt (Reste frueherer Versionen / eines alten Spielstands).
	destroyStrayBanners(buildingModel)

	local ui = buildBannerGui(adorneePart, isCapital, initialText, initialColor)

	-- NACH dem Neubau: harte Garantie "genau 1 Banner pro City".
	enforceSingleBanner(buildingModel, ui.billboard)

	return ui
end

local function tryAttachCityBanner(buildingModel, attempt)
	attempt = attempt or 1

	local key, q, r = hexKeyFromBuildingName(buildingModel.Name)
	if not key then return end

	-- Fuer dieses Hex gibt es schon einen Banner-Eintrag: kein zweites
	-- Banner bauen (Dedupe), aber das Entry auf das aktuelle Model
	-- nachziehen (das Gebaeude-Model kann ersetzt worden sein, z.B.
	-- Camp -> City oder nach einer Eroberung).
	local existing = banners[key]
	if existing then
		if existing.buildingModel ~= buildingModel then
			existing.buildingModel = buildingModel
			existing.dataResolved = false -- Daten neu ziehen (Owner kann anders sein)
		end
		enforceSingleBanner(buildingModel, existing.billboard)
		return
	end

	local ui = attachBannerUi(buildingModel, false)
	if not ui then
		-- REPLIKATIONS-RACE: Beim ChildAdded-Event kann das City-Model noch
		-- ohne BasePart/PrimaryPart beim Client ankommen (die Descendants
		-- folgen einen Tick spaeter). attachBannerUi findet dann kein
		-- Adornee-Part -> es entstuende UEBERHAUPT KEIN Banner fuer diese
		-- Stadt, und nichts wuerde es je nachtraeglich anlegen.
		-- Deshalb: kurz warten und erneut versuchen (begrenzt, 20x0.5s).
		if attempt < 20 and buildingModel.Parent then
			task.delay(0.5, function()
				if not banners[key] and buildingModel.Parent then
					tryAttachCityBanner(buildingModel, attempt + 1)
				end
			end)
		end
		return
	end

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
		-- Daten-Status fuer Retries/Heal-Loop (siehe refreshBannerData).
		dataResolved = false,
		refreshing = false,
		refreshQueued = false,
		pendingRetry = false,
		rebuilding = false,
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
-- Name/Farbe werden aus entry.info uebernommen, damit beim Umbau kein
-- Platzhalter ("...", grau) aufblitzt.
rebuildBanner = function(entry, isCapital)
	if not entry or not entry.buildingModel or not entry.buildingModel.Parent then return end
	if entry.rebuilding then return end
	entry.rebuilding = true

	-- isCapital VOR dem Neubau setzen: schlaegt der Neubau fehl, wuerde
	-- sonst jeder weitere Refresh erneut einen Rebuild anstossen
	-- (Endlosschleife + Banner-Chaos).
	entry.isCapital = isCapital and true or false

	if entry.billboard and entry.billboard.Parent then
		entry.billboard:Destroy()
	end
	entry.billboard = nil

	local info = entry.info
	local ui = attachBannerUi(
		entry.buildingModel,
		entry.isCapital,
		info and info.name,
		info and info.ownerColor
	)

	entry.rebuilding = false

	if not ui then
		-- Gebaeude hat gerade keine BasePart -> Daten als unaufgeloest
		-- markieren, der Heal-Loop versucht den Neubau spaeter erneut.
		entry.dataResolved = false
		warn("[Banner] Rebuild fuer " .. entry.key
			.. " nicht moeglich - Heal-Loop versucht es erneut")
		return
	end

	entry.billboard = ui.billboard
	entry.flag = ui.flag
	entry.tipLeft = ui.tipLeft
	entry.tipRight = ui.tipRight
	entry.nameLabel = ui.nameLabel
	entry.nameStroke = ui.nameStroke
	entry.flagStroke = ui.flagStroke
	entry.glow = ui.glow
	entry.crownLabel = ui.crownLabel

	ui.clickButton.Activated:Connect(function()
		onBannerClicked(entry)
	end)

	applyFogState(entry, currentFogState(entry.key))

	if info then
		applyBannerInfo(entry, info)
	else
		refreshBannerData(entry)
	end
end

-- Banner ueber den Hex-Key entfernen (Gebaeude zerstoert/ersetzt oder
-- Eintrag im Heal-Loop als verwaist erkannt).
local function removeBannerByKey(key)
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

local function removeBanner(name)
	local key = hexKeyFromBuildingName(name)
	if not key then return end
	removeBannerByKey(key)
end

--------------------------------------------------------------------------------
-- BUILDINGS-FOLDER BEOBACHTEN
--------------------------------------------------------------------------------
local watchedBuildingsFolder = nil

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

	-- Doppelte Verbindungen vermeiden (diese Funktion wird auch nach einem
	-- HexMap-Neubau erneut aufgerufen).
	if watchedBuildingsFolder == buildingsFolder then
		return
	end
	watchedBuildingsFolder = buildingsFolder

	for _, child in ipairs(buildingsFolder:GetChildren()) do
		if child.Name:match("^City_") then
			tryAttachCityBanner(child)
		end
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
		for key in pairs(banners) do
			removeBannerByKey(key)
		end
		bannerByCityId = {}
		watchedBuildingsFolder = nil
		connectBuildingsWatcher()
	end
end)

--------------------------------------------------------------------------------
-- FOG-OF-WAR-EVENT ABONNIEREN (siehe FogOfWarController.setHexState)
--
-- NICHT-BLOCKIEREND: hier stand frueher WaitForChild("FogOfWarHexStateChanged", 30).
-- Solange der FogOfWarController das BindableEvent nicht angelegt hatte,
-- blockierte das den REST dieses LocalScripts um bis zu 30 Sekunden - die
-- Listener fuer CityStatsChanged/CapitalCityMarked wurden also genau in der
-- Phase verbunden, in der Staedte gegruendet/erobert werden. Folge: Banner
-- blieben grau, mit "..." oder im falschen (Nicht-Hauptstadt-)Layout.
-- Jetzt wird das Event bei Bedarf selbst angelegt (identisches Pattern wie
-- im FogOfWarController: erst FindFirstChild, dann Create) und die Listener
-- darunter sind SOFORT scharf.
--------------------------------------------------------------------------------
local hexStateEvent = ReplicatedStorage:FindFirstChild("FogOfWarHexStateChanged")
if not hexStateEvent or not hexStateEvent:IsA("BindableEvent") then
	if hexStateEvent then
		hexStateEvent:Destroy()
	end
	hexStateEvent = Instance.new("BindableEvent")
	hexStateEvent.Name = "FogOfWarHexStateChanged"
	hexStateEvent.Parent = ReplicatedStorage
	warn("[Banner] FogOfWarHexStateChanged fehlte - BindableEvent selbst angelegt")
end

hexStateEvent.Event:Connect(function(key, state)
	local entry = banners[key]
	if entry then
		applyFogState(entry, state)
	end
end)

--------------------------------------------------------------------------------
-- CityStatsChanged (Server -> Client): Eroberung/Umbenennung/Bevoelkerung ->
-- Banner neu einfärben (Test-Szenario: Banner-Farbe wechselt nach Eroberung).
--------------------------------------------------------------------------------
Net.On("CityStatsChanged", function(cityId)
	local key = bannerByCityId[cityId]
	local entry = key and banners[key]
	if entry then
		task.delay(0.1, function()
			refreshBannerData(entry)
		end)
		return
	end

	-- FALLBACK: die cityId ist (noch) keinem Banner zugeordnet - z.B. weil
	-- der erste GetCityOnHex-Call dieses Banners fehlgeschlagen ist. Ohne
	-- diesen Fallback bliebe ausgerechnet dieses Banner nach einer
	-- Eroberung dauerhaft in der alten Farbe/beim alten Text haengen.
	-- Deshalb werden alle noch unaufgeloesten Banner nachgezogen.
	for _, other in pairs(banners) do
		if not other.dataResolved or other.cityId == cityId then
			task.delay(0.1, function()
				refreshBannerData(other)
			end)
		end
	end
end)

--------------------------------------------------------------------------------
-- CapitalCityMarked (Server -> Client): eine neue Hauptstadt wurde
-- gegründet -> das betroffene Banner SOFORT auf Hauptstadt-Layout umstellen,
-- ohne auf das naechste CityStatsChanged warten zu muessen.
--
-- Das Event kommt direkt nach CitySystem.FoundCity, also moeglicherweise
-- BEVOR das neue City-Model beim Client repliziert ist. Deshalb wird das
-- Banner ueber die mitgelieferten Koordinaten (q/r) gesucht und bei Bedarf
-- kurz gewartet und erneut versucht.
--------------------------------------------------------------------------------
local function refreshCapitalBanner(payload, attempt)
	attempt = attempt or 1
	if not payload then return end

	local key = (payload.q ~= nil and payload.r ~= nil)
		and (tostring(payload.q) .. "_" .. tostring(payload.r))
		or nil
	local byCoords = key and banners[key] or nil
	local byCityId = payload.cityId and banners[bannerByCityId[payload.cityId] or ""] or nil
	local entry = byCoords or byCityId

	if entry then
		if payload.cityId then
			bannerByCityId[payload.cityId] = entry.key
		end
		task.delay(0.1, function()
			refreshBannerData(entry)
		end)
		return
	end

	-- City-Model noch nicht da -> kurz warten und erneut versuchen.
	if attempt < 10 then
		task.delay(0.5, function()
			refreshCapitalBanner(payload, attempt + 1)
		end)
	end
end

Net.On("CapitalCityMarked", refreshCapitalBanner)

--------------------------------------------------------------------------------
-- PlayerEliminated (Server -> Client): VictorySystem.EliminatePlayer setzt
-- alle Staedte des eliminierten Spielers auf owner = nil. Die Banner muessen
-- danach neutral grau werden (und den Hauptstadt-Look verlieren).
--------------------------------------------------------------------------------
Net.On("PlayerEliminated", function()
	for _, entry in pairs(banners) do
		task.delay(0.1, function()
			refreshBannerData(entry)
		end)
	end
end)

--------------------------------------------------------------------------------
-- HEAL-LOOP (Selbstheilung, 1x pro Sekunde)
--
-- Faengt alles ab, was ueber Events allein nicht sicher abgedeckt ist:
--   1. Fog-Zustand: wird JEDE Sekunde fuer JEDES Banner erzwungen
--      (Polling-Fallback). Deckt verpasste Events, einen fehlenden/zu
--      spaet ladenden FogOfWarController und fremde Eingriffe ab.
--   2. Daten: Banner ohne aufgeloeste Info (Text "...", graue Farbe) ->
--      langsamer Retry, bis Name/Farbe vom Server da sind.
--   3. Duplikate: es haengt mehr als ein Banner am Gebaeude -> ueberzaehlige
--      entfernen (nur alle paar Sekunden, das ist billig aber nicht gratis).
--   4. Verwaiste Eintraege: Gebaeude-Model ist weg -> Eintrag loeschen.
--   5. Cities ohne Banner-Eintrag -> Banner nachtraeglich anhaengen.
--------------------------------------------------------------------------------
local DEDUPE_SWEEP_INTERVAL = 5
local lastDedupeSweep = 0
local fogWarningShown = false

task.spawn(function()
	while true do
		task.wait(1)

		local now = tick()
		local doDedupeSweep = (now - lastDedupeSweep) >= DEDUPE_SWEEP_INTERVAL
		if doDedupeSweep then
			lastDedupeSweep = now
		end

		-- Einmalige Diagnose, falls die Fog-Quelle fehlt (dann greift das
		-- Fail-Open und Banner koennen in unerforschtem Gebiet sichtbar sein,
		-- bis der FogOfWarController laeuft).
		if not fogSourceAvailable and not fogWarningShown then
			fogWarningShown = true
			warn("[Banner] _G.GetFogHexState nicht verfuegbar (FogOfWarController"
				.. " laeuft nicht / noch nicht geladen?) -> Fail-Open aktiv:"
				.. " Banner werden als 'visible' behandelt, bis die Quelle da ist.")
		end

		-- 5) Cities OHNE Banner-Eintrag nachtraeglich anhaengen (Replikations-
		--    Race beim ChildAdded, neu gegruendete Stadt, nach einem Heal
		--    verworfener Eintrag, ...). tryAttachCityBanner ist idempotent:
		--    fuer bestehende Eintraege wird nur die Dedupe-Garantie geprueft.
		if doDedupeSweep and watchedBuildingsFolder and watchedBuildingsFolder.Parent then
			for _, child in ipairs(watchedBuildingsFolder:GetChildren()) do
				if child.Name:match("^City_") then
					tryAttachCityBanner(child)
				end
			end
		end

		for key, entry in pairs(banners) do
			local model = entry.buildingModel
			if not model or not model.Parent then
				-- 4) Gebaeude existiert nicht mehr.
				removeBannerByKey(key)
			else
				-- 1) Fog-Zustand ERZWINGEN (Polling-Fallback, 1x/s).
				--    Bewusst UNBEDINGT (nicht nur bei erkannder Aenderung):
				--    damit ein Banner niemals in einem Enabled=false-Zustand
				--    haengen bleibt, den irgend etwas anderes gesetzt hat
				--    (verpasstes Event, zweite Script-Instanz, Studio-Reload).
				--    currentFogState() ist fail-open: ohne _G.GetFogHexState
				--    liefert es VISIBLE statt UNEXPLORED.
				if entry.billboard and entry.billboard.Parent then
					applyFogState(entry, currentFogState(key))

					-- 3) Duplikate entfernen.
					if doDedupeSweep then
						enforceSingleBanner(model, entry.billboard)
					end
				else
					-- Banner-GUI fehlt (z.B. weil ein Rebuild ohne BasePart
					-- fehlgeschlagen ist) -> Eintrag verwerfen und neu anhaengen.
					removeBannerByKey(key)
					tryAttachCityBanner(model)
				end

				-- 2) Daten heilen (nur wenn gerade kein Retry laeuft).
				local refreshed = banners[key]
				if refreshed and not refreshed.dataResolved
					and not refreshed.refreshing and not refreshed.pendingRetry then
					refreshBannerData(refreshed, MAX_FAST_RETRIES + 1)
				end
			end
		end
	end
end)

print("[CityBannerController v2] Bereit. Heal-Loop aktiv (1s: Fog-State erzwingen,"
	.. " Daten-Retry, Dedupe-Sweep alle " .. tostring(DEDUPE_SWEEP_INTERVAL) .. "s).")
