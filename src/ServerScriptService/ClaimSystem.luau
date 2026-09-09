--[[
    ClaimSystem (ModuleScript)
    Ort: ServerScriptService > ClaimSystem
    
    Ordnet eine Province einem Spieler zu (Claim).
    
    Wenn eine Province geclaimed wird:
      1. Province bekommt den Spieler als Owner (ProvinceData)
      2. Province bekommt die Spielerfarbe in einer helleren Version (ProvinceData)
      3. Alle Hexes der Province bekommen den Spieler als Owner (HexData)
      4. PlayerData wird aktualisiert (Province zur Liste hinzufügen)
      5. Die Provinz-Hexes im Workspace werden visuell umgefärbt
    
    Wenn eine Province unclaimed wird:
      1. Province-Owner wird auf nil gesetzt
      2. Province-Farbe wird auf Grau zurückgesetzt
      3. Alle Hexes der Province verlieren den Owner
      4. PlayerData wird aktualisiert (Province aus Liste entfernen)
      5. Die Provinz-Hexes im Workspace werden visuell zurückgefärbt
    
    Verwendung:
        local ClaimSystem = require(script.Parent:WaitForChild("ClaimSystem"))
        
        ClaimSystem.ClaimProvince(player, provinceId)
        ClaimSystem.UnclaimProvince(provinceId)
--]]

local ClaimSystem = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProvinceData = require(script.Parent:WaitForChild("ProvinceData"))
local HexData = require(script.Parent:WaitForChild("HexData"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local PointSystem = require(script.Parent:WaitForChild("PointSystem"))
local VictoryConfig = require(ReplicatedStorage:WaitForChild("VictoryConfig"))

--------------------------------------------------------------------------------
-- KONFIGURATION
--------------------------------------------------------------------------------
ClaimSystem.Config = {
	-- Wie viel heller die Spielerfarbe auf der Province wird (0-1)
	-- 0.3 = 30% heller
	LIGHTEN_AMOUNT = 0.3,

	-- Grau-Farbe für unkontrollierte Provinzen
	NEUTRAL_COLOR = Color3.fromRGB(110, 110, 110),
}

--------------------------------------------------------------------------------
-- lightenColor(color, amount) -> Color3
-- Macht eine Farbe um den angegebenen Betrag heller
--------------------------------------------------------------------------------
function ClaimSystem.lightenColor(color, amount)
	local r = color.R + (1 - color.R) * amount
	local g = color.G + (1 - color.G) * amount
	local b = color.B + (1 - color.B) * amount

	return Color3.new(
		math.clamp(r, 0, 1),
		math.clamp(g, 0, 1),
		math.clamp(b, 0, 1)
	)
end

--------------------------------------------------------------------------------
-- recolorProvinceVisuals(provinceId, color)
-- Färbt die Province-Hexes im Workspace um
--------------------------------------------------------------------------------
function ClaimSystem.recolorProvinceVisuals(provinceId, color)
	local hexMap = workspace:FindFirstChild("HexMap")
	if not hexMap then return end

	local provinceVisuals = hexMap:FindFirstChild("ProvinceVisuals")
	if not provinceVisuals then return end

	local provinceModel = provinceVisuals:FindFirstChild("Province_" .. provinceId)
	if not provinceModel then return end

	for _, part in ipairs(provinceModel:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Color = color
		end
	end
end

--------------------------------------------------------------------------------
-- setHexOwners(provinceId, owner)
-- Setzt den Owner aller Hexes einer Province in HexData
--------------------------------------------------------------------------------
function ClaimSystem.setHexOwners(provinceId, owner)
	local province = ProvinceData.GetProvince(provinceId)
	if not province or not province.hexes then return end

	for _, hex in ipairs(province.hexes) do
		HexData.UpdateHex(hex.q, hex.r, { owner = owner })
	end
end

--------------------------------------------------------------------------------
-- ClaimProvince(player, provinceId) -> boolean
-- Ordnet eine Province einem Spieler zu.
--------------------------------------------------------------------------------
function ClaimSystem.ClaimProvince(player, provinceId)
	local province = ProvinceData.GetProvince(provinceId)
	if not province then
		warn("[ClaimSystem] Province " .. tostring(provinceId) .. " nicht gefunden")
		return false
	end

	-- Falls Province bereits einem anderen Spieler gehört: alten Owner entfernen
	-- + Verlust-Punkte (ProvinceLost) fuer den vorherigen Besitzer.
	if province.owner and province.owner ~= player then
		local prevOwner = province.owner
		ClaimSystem.UnclaimProvince(provinceId)
		pcall(PointSystem.DeductPoints, prevOwner, "ProvinceLost",
			VictoryConfig.LOSS_POINTS.ProvinceLost)
	end

	-- Spielerfarbe holen und aufhellen
	local playerColor = PlayerData.GetColor(player)
	local provinceColor = ClaimSystem.lightenColor(playerColor, ClaimSystem.Config.LIGHTEN_AMOUNT)

	-- 1. ProvinceData aktualisieren
	ProvinceData.SetProvinceOwner(provinceId, player)
	ProvinceData.SetProvinceColor(provinceId, provinceColor)

	-- 2. Alle Hexes der Province → Owner setzen
	ClaimSystem.setHexOwners(provinceId, player)

	-- 3. PlayerData aktualisieren
	PlayerData.AddProvince(player, provinceId)

	-- 4. Visuell umfärben
	ClaimSystem.recolorProvinceVisuals(provinceId, provinceColor)

	print("[ClaimSystem] Province " .. provinceId .. " (" .. (province.name or "") .. ") geclaimed von " .. player.Name)
	return true
end

--------------------------------------------------------------------------------
-- UnclaimProvince(provinceId) -> boolean
-- Entfernt den Owner einer Province.
--------------------------------------------------------------------------------
function ClaimSystem.UnclaimProvince(provinceId)
	local province = ProvinceData.GetProvince(provinceId)
	if not province then
		warn("[ClaimSystem] Province " .. tostring(provinceId) .. " nicht gefunden")
		return false
	end

	local previousOwner = province.owner

	-- 1. ProvinceData zurücksetzen
	ProvinceData.SetProvinceOwner(provinceId, nil)
	ProvinceData.SetProvinceColor(provinceId, ClaimSystem.Config.NEUTRAL_COLOR)

	-- 2. Alle Hexes → Owner nil
	ClaimSystem.setHexOwners(provinceId, nil)

	-- 3. PlayerData aktualisieren (wenn vorheriger Besitzer existierte)
	if previousOwner then
		PlayerData.RemoveProvince(previousOwner, provinceId)
	end

	-- 4. Visuell zurückfärben
	ClaimSystem.recolorProvinceVisuals(provinceId, ClaimSystem.Config.NEUTRAL_COLOR)

	print("[ClaimSystem] Province " .. provinceId .. " (" .. (province.name or "") .. ") unclaimed")
	return true
end

--------------------------------------------------------------------------------
-- TransferProvince(fromPlayer, toPlayer, provinceId) -> boolean
-- Überträgt eine Province von einem Spieler an einen anderen.
--------------------------------------------------------------------------------
function ClaimSystem.TransferProvince(fromPlayer, toPlayer, provinceId)
	local province = ProvinceData.GetProvince(provinceId)
	if not province then return false end

	if province.owner ~= fromPlayer then
		warn("[ClaimSystem] Province " .. provinceId .. " gehört nicht " .. fromPlayer.Name)
		return false
	end

	-- Erst unclaimen, dann für neuen Spieler claimen
	ClaimSystem.UnclaimProvince(provinceId)
	ClaimSystem.ClaimProvince(toPlayer, provinceId)

	print("[ClaimSystem] Province " .. provinceId .. " transferiert: " .. fromPlayer.Name .. " → " .. toPlayer.Name)
	return true
end

--------------------------------------------------------------------------------
-- GetProvinceOwner(provinceId) -> Player or nil
--------------------------------------------------------------------------------
function ClaimSystem.GetProvinceOwner(provinceId)
	local province = ProvinceData.GetProvince(provinceId)
	if not province then return nil end
	return province.owner
end

--------------------------------------------------------------------------------
-- IsClaimedBy(player, provinceId) -> boolean
--------------------------------------------------------------------------------
function ClaimSystem.IsClaimedBy(player, provinceId)
	local province = ProvinceData.GetProvince(provinceId)
	if not province then return false end
	return province.owner == player
end

--------------------------------------------------------------------------------
-- IsClaimed(provinceId) -> boolean
--------------------------------------------------------------------------------
function ClaimSystem.IsClaimed(provinceId)
	local province = ProvinceData.GetProvince(provinceId)
	if not province then return false end
	return province.owner ~= nil
end

return ClaimSystem
