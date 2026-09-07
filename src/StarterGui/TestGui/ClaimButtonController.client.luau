--[[
    ClaimButtonController (LocalScript)
    Ort: StarterGui > TestGui > ClaimButtonController
    
    Test-Controller für den ClaimButton.
    
    Ablauf:
      1. Spieler klickt auf ClaimButton
      2. Claim-Modus wird aktiviert
      3. Nächster Klick auf ein Hex sendet RequestClaimProvince an den Server
      4. Server claimt die zugehörige Province
    
    Benötigt:
      StarterGui > TestGui > ClaimButton (TextButton)
      ReplicatedStorage > DataRemotes > RequestClaimProvince (RemoteEvent)
      ReplicatedStorage > HexGridConfig (ModuleScript)
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local HexGridConfig = require(ReplicatedStorage:WaitForChild("HexGridConfig"))

local gui = script.Parent
local claimButton = gui:WaitForChild("ClaimButton")

local dataRemotes = ReplicatedStorage:WaitForChild("DataRemotes")
local requestClaimProvince = dataRemotes:WaitForChild("RequestClaimProvince")

local waitingForProvinceClick = false

--------------------------------------------------------------------------------
-- Button klicken → Claim-Modus aktivieren
--------------------------------------------------------------------------------
claimButton.MouseButton1Click:Connect(function()
	waitingForProvinceClick = true
	claimButton.Text = "Klicke auf ein Hex..."
	print("[ClaimButtonController] Claim-Modus aktiv. Klicke auf ein Hex.")
end)

--------------------------------------------------------------------------------
-- Nächster Klick auf Hex → Province claimen
--------------------------------------------------------------------------------
mouse.Button1Down:Connect(function()
	if not waitingForProvinceClick then return end

	local target = mouse.Target
	if not target then return end

	local q, r = HexGridConfig.worldToAxial(mouse.Hit.Position)

	waitingForProvinceClick = false
	claimButton.Text = "Claim Province"

	print("[ClaimButtonController] Claim-Request für Hex (" .. q .. ", " .. r .. ") gesendet")
	requestClaimProvince:FireServer(q, r)
end)

claimButton.Text = "Claim Province"
print("[ClaimButtonController] Bereit.")
