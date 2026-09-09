--[[
    NotificationGuiController (LocalScript)
    Ort: StarterGui > NotificationGui > NotificationGuiController

    Zentrales Benachrichtigungs-System fuer diplomatische Ereignisse.
    Erscheint als Popup-Banner oben rechts, auch wenn das Diplomatie-Fenster
    geschlossen ist.

    TYPEN (siehe DiplomacyConfig.NOTIFY):
        Offer    (interaktiv, bleibt bis Reaktion/Ablauf)
        War      (10s, rot)
        Accepted (5s, gruen)
        Declined (5s, orange)
        Expired  (5s, grau)
        Broken   (8s, dunkelrot)

    STAPELUNG: max MAX_BANNERS gleichzeitig, neue oben, aeltere rutschen runter.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Net = require(ReplicatedStorage:WaitForChild("Net"))
local DiplomacyConfig = require(ReplicatedStorage:WaitForChild("DiplomacyConfig"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = script.Parent:IsA("ScreenGui")
	and script.Parent
	or script.Parent:FindFirstAncestorWhichIsA("ScreenGui")
if not gui then return end

gui.IgnoreGuiInset = true  -- Banner oben rechts, ohne Topbar-Versatz

local container = gui:FindFirstChild("NotificationContainer")
if not container then
	container = Instance.new("Frame")
	container.Name = "NotificationContainer"
	container.AnchorPoint = Vector2.new(1, 0)
	container.Position = UDim2.new(1, -12, 0, 12)
	container.Size = UDim2.fromOffset(340, 0)
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.Parent = gui
end

local MAX_BANNERS = DiplomacyConfig.MAX_BANNERS or 4

--------------------------------------------------------------------------------
-- BANNER BUILDER
--------------------------------------------------------------------------------
local function attachOfferButtons(banner, payload, offerId)
	local acceptBtn = banner:FindFirstChild("AcceptButton")
	local declineBtn = banner:FindFirstChild("DeclineButton")
	if not acceptBtn or not declineBtn then return end

	acceptBtn.Visible = true
	declineBtn.Visible = true

	local function onAccept()
		Net.Fire("DiplomacyRespondOffer", payload.otherUserId, payload.offerType, true)
		banner:Destroy()
	end
	local function onDecline()
		Net.Fire("DiplomacyRespondOffer", payload.otherUserId, payload.offerType, false)
		banner:Destroy()
	end

	acceptBtn.Activated:Connect(onAccept)
	declineBtn.Activated:Connect(onDecline)
end

-- Erlaubt es, den Timer fuer ein Angebot zu aktualisieren (Runden): vorhandener
-- Banner mit derselben offerId bekommt eine neue Timer-Text.
local function pushBanner(payload)
	local offerId = payload.offerId or payload.id
	if offerId and offerId > 0 then
		-- Vorhandenes interaktives Banner (Angebot) mit gleicher Id aktualisieren.
		for _, existing in ipairs(container:GetChildren()) do
			if existing:IsA("Frame") and existing:GetAttribute("OfferId") == offerId then
				local timer = existing:FindFirstChild("TimerLabel")
				if timer and payload.roundsLeft then
					timer.Text = "⏳ Läuft ab in " .. payload.roundsLeft .. " Runden"
				end
				return
			end
		end
	end

	-- Max-Banner-Cap: aeltestes entfernen, sonst stapeln sich zu viele.
	local banners = {}
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Frame") then table.insert(banners, child) end
	end
	while #banners >= MAX_BANNERS do
		local oldest = banners[1]
		oldest:Destroy()
		table.remove(banners, 1)
	end

	local notifType = payload.type
	local duration = DiplomacyConfig.DISMISS[notifType]
	local color = DiplomacyConfig.COLOR[notifType]

	local banner = Instance.new("Frame")
	banner.Name = "Banner_" .. tostring(offerId or os.clock())
	banner.Size = UDim2.new(1, 0, 0, 0)  -- AutomaticSize füllt per Child
	banner.AnchorPoint = Vector2.new(1, 0)
	banner.Position = UDim2.new(1, -4, 0, 0)
	banner.BackgroundColor3 = color or Color3.fromRGB(80, 80, 90)
	banner.BackgroundTransparency = 0.08
	banner.BorderSizePixel = 0
	banner.AutomaticSize = Enum.AutomaticSize.Y
	banner.LayoutOrder = -os.clock()
	banner.Parent = container
	banner:SetAttribute("OfferId", offerId)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = banner

	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Color3.fromRGB(200, 200, 200)
	stroke.Thickness = 1
	stroke.Transparency = 0.2
	stroke.Parent = banner

	-- Überschrift
	local title = Instance.new("TextLabel")
	title.Name = "TitleText"
	title.Size = UDim2.new(1, -20, 0, 22)
	title.Position = UDim2.new(0, 10, 0, 8)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 14
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextWrapped = true
	title.Parent = banner

	-- Körper
	local body = Instance.new("TextLabel")
	body.Name = "BodyText"
	body.Size = UDim2.new(1, -20, 0, 32)
	body.Position = UDim2.new(0, 10, 0, 30)
	body.BackgroundTransparency = 1
	body.Font = Enum.Font.Gotham
	body.TextSize = 13
	body.TextColor3 = Color3.fromRGB(235, 235, 235)
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.TextWrapped = true
	body.Parent = banner

	-- Timer (nur bei Angeboten)
	local timer = Instance.new("TextLabel")
	timer.Name = "TimerLabel"
	timer.Size = UDim2.new(1, -20, 0, 18)
	timer.Position = UDim2.new(0, 10, 0, 62)
	timer.BackgroundTransparency = 1
	timer.Font = Enum.Font.Gotham
	timer.TextSize = 12
	timer.TextColor3 = Color3.fromRGB(210, 210, 210)
	timer.TextXAlignment = Enum.TextXAlignment.Left
	timer.Visible = false
	timer.Parent = banner

	-- Buttons (nur bei interaktiven Angeboten)
	local acceptBtn = Instance.new("TextButton")
	acceptBtn.Name = "AcceptButton"
	acceptBtn.Size = UDim2.new(0.5, -4, 0, 26)
	acceptBtn.Position = UDim2.new(0, 8, 0, 84)
	acceptBtn.BackgroundColor3 = Color3.fromRGB(40, 130, 60)
	acceptBtn.Font = Enum.Font.GothamBold
	acceptBtn.TextSize = 13
	acceptBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	acceptBtn.Text = "✅ Annehmen"
	acceptBtn.BorderSizePixel = 0
	acceptBtn.Visible = false
	acceptBtn.Parent = banner

	local declineBtn = Instance.new("TextButton")
	declineBtn.Name = "DeclineButton"
	declineBtn.Size = UDim2.new(0.5, -4, 0, 26)
	declineBtn.Position = UDim2.new(0.5, 4, 0, 84)
	declineBtn.BackgroundColor3 = Color3.fromRGB(150, 60, 60)
	declineBtn.Font = Enum.Font.GothamBold
	declineBtn.TextSize = 13
	declineBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	declineBtn.Text = "❌ Ablehnen"
	declineBtn.BorderSizePixel = 0
	declineBtn.Visible = false
	declineBtn.Parent = banner

	-- Inhalt je Typ
	local fromName = payload.fromPlayerName or "Ein Spieler"
	if notifType == DiplomacyConfig.NOTIFY.OFFER then
		local offerLabel = payload.offerType == DiplomacyConfig.OFFER.ALLIANCE and "ALLIANZ" or "FRIEDEN"
		title.Text = "📜 " .. fromName .. " bietet dir ein " .. offerLabel .. " an!"
		body.Text = ""
		timer.Visible = true
		if payload.roundsLeft then
			timer.Text = "⏳ Läuft ab in " .. payload.roundsLeft .. " Runden"
		end
		timer.Position = UDim2.new(0, 10, 0, 30)
		attachOfferButtons(banner, payload, offerId)
		banner.Size = UDim2.new(1, 0, 0, 118)
	elseif notifType == DiplomacyConfig.NOTIFY.WAR then
		title.Text = "⚔️ KRIEGSERKLÄRUNG!"
		body.Text = "Spieler '" .. fromName .. "' hat dir den Krieg erklärt!"
		timer.Visible = false
	elseif notifType == DiplomacyConfig.NOTIFY.BROKEN then
		title.Text = "💔 Allianz gebrochen!"
		body.Text = "Spieler '" .. fromName .. "' hat die Allianz gebrochen!"
	elseif notifType == DiplomacyConfig.NOTIFY.ACCEPTED then
		title.Text = "✅ Angebot angenommen!"
		body.Text = "Spieler '" .. fromName .. "' hat dein Angebot angenommen."
		timer.Visible = false
	elseif notifType == DiplomacyConfig.NOTIFY.DECLINED then
		title.Text = "❌ Angebot abgelehnt."
		if payload.declineReason then
			body.Text = payload.declineReason
		else
			body.Text = "Spieler '" .. fromName .. "' hat dein Angebot abgelehnt."
		end
		timer.Visible = false
	elseif notifType == DiplomacyConfig.NOTIFY.EXPIRED then
		title.Text = "⏳ Angebot abgelaufen."
		body.Text = "Dein Angebot an '" .. fromName .. "' ist abgelaufen."
		timer.Visible = false
	else
		title.Text = "🔔 " .. fromName
		body.Text = ""
		timer.Visible = false
	end

	if notifType == DiplomacyConfig.NOTIFY.OFFER then
		-- Bleibt bis Reaktion oder Ablauf auf dem Server.
		return banner
	end

	-- Auto-Dismiss für alle anderen Typen.
	local dismiss = duration or 5
	task.delay(dismiss, function()
		if banner.Parent then banner:Destroy() end
	end)

	return banner
end

--------------------------------------------------------------------------------
-- SIMPLE BANNER (für Victory/Elimination, ohne Diplo-Typen)
--------------------------------------------------------------------------------
local function pushSimpleBanner(titleText, bodyText, color, duration)
	local banner = Instance.new("Frame")
	banner.Name = "Banner_" .. tostring(os.clock())
	banner.Size = UDim2.new(1, 0, 0, 0)
	banner.AnchorPoint = Vector2.new(1, 0)
	banner.Position = UDim2.new(1, -4, 0, 0)
	banner.BackgroundColor3 = color or Color3.fromRGB(80, 80, 90)
	banner.BackgroundTransparency = 0.08
	banner.BorderSizePixel = 0
	banner.AutomaticSize = Enum.AutomaticSize.Y
	banner.LayoutOrder = -os.clock()
	banner.Parent = container

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = banner

	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Color3.fromRGB(200, 200, 200)
	stroke.Thickness = 1
	stroke.Transparency = 0.2
	stroke.Parent = banner

	local title = Instance.new("TextLabel")
	title.Name = "TitleText"
	title.Size = UDim2.new(1, -20, 0, 24)
	title.Position = UDim2.new(0, 10, 0, 8)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 15
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = titleText
	title.TextWrapped = true
	title.Parent = banner

	local body = Instance.new("TextLabel")
	body.Name = "BodyText"
	body.Size = UDim2.new(1, -20, 0, 34)
	body.Position = UDim2.new(0, 10, 0, 32)
	body.BackgroundTransparency = 1
	body.Font = Enum.Font.Gotham
	body.TextSize = 13
	body.TextColor3 = Color3.fromRGB(235, 235, 235)
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.TextWrapped = true
	body.Text = bodyText
	body.Parent = banner

	task.delay(duration or 6, function()
		if banner.Parent then banner:Destroy() end
	end)
	return banner
end

--------------------------------------------------------------------------------
-- LISTENERS
--------------------------------------------------------------------------------
Net.On("DiplomacyNotification", function(payload)
	if not payload then return end
	-- Nur anzeigen, wenn der Server das an UNS geschickt hat (oder an alle).
	if payload.targetPlayerId and payload.targetPlayerId ~= player.UserId then
		return
	end
	pcall(pushBanner, payload)
end)

-- Statuswechsel des Diplomatie-Systems: vorhandene Offer-Banner-Timer auffrischen.
-- Der Server pusht GetDiplomacyState/DiplomacyUpdate mit pendingOffers, die die
-- aktuelle Anzahl verbleibender Runden tragen. Wir matchen per offerId.
Net.On("DiplomacyUpdate", function(data)
	if not data then return end
	local offers = data.pendingOffers or {}
	local seen = {}
	for _, offer in pairs(offers) do
		if offer.offerId then seen[offer.offerId] = offer end
	end
	-- Timer auf den Banner aktualisieren; nicht mehr existente OFFER-Banner
	-- entfernen. Nicht-Angebots-Banner (War/Accepted/...) haben kein offerId-
	-- Attribut und werden IGNORIERT (ihr Auto-Dismiss laeuft separat).
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Frame") then
			local offerId = child:GetAttribute("OfferId")
			local offer = offerId and seen[offerId]
			if offer then
				local timer = child:FindFirstChild("TimerLabel")
				if timer and offer.roundsLeft then
					timer.Text = "⏳ Läuft ab in " .. offer.roundsLeft .. " Runden"
				end
			elseif offerId and child.Name:match("^Banner_") then
				-- Angebot weg (angenommen/abgelehnt/abgelaufen) -> Banner zu.
				child:Destroy()
			end
		end
	end
end)

-- VICTORY: Spieler eliminiert.
Net.On("PlayerEliminated", function(payload)
	if not payload then return end
	local name = payload.playerName or "Ein Spieler"
	local reason = payload.reason or "Hauptstadt verloren"
	pushSimpleBanner("💀 " .. name .. " wurde eliminiert!", reason, Color3.fromRGB(160, 50, 50), 7)
end)

-- VICTORY: Sieg verkündet.
Net.On("VictoryAchieved", function(payload)
	if not payload then return end
	local winnerType = payload.winnerType == "alliance" and "ALLIANZ" or "SOLO"
	local title = "🏆 SIEG (" .. winnerType .. ")!"
	local body = payload.winnerName .. " hat mit " .. tostring(payload.finalPoints or 0) .. " Punkten gewonnen!"
	pushSimpleBanner(title, body, Color3.fromRGB(200, 160, 30), 12)
	-- Tutorial/Victory-GUI oeffnen.
	local playerGui = player:FindFirstChild("PlayerGui")
	local victoryGui = playerGui and playerGui:FindFirstChild("VictoryGui")
	if victoryGui then victoryGui.Enabled = true end
end)

print("[NotificationGuiController] Bereit.")
