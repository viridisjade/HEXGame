--[[
    CityPlacementController (LocalScript)
    Ort: StarterPlayer > StarterPlayerScripts > CityPlacementController

    Zeigt den lokalen transparenten Vorschau-Klon, snappt ihn auf das
    gemeinsame Hex-Grid und sendet die bestätigte Position zum Server.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local CityBuildState = require(ReplicatedStorage:WaitForChild("CityBuildState"))
local State = require(ReplicatedStorage:WaitForChild("ClientState"))
local HexGridConfig = require(ReplicatedStorage:WaitForChild("HexGridConfig"))
local HexHeightUtil = require(ReplicatedStorage:WaitForChild("HexHeightUtil"))

local buildingsFolder = ReplicatedStorage:WaitForChild("Buildings")
local dataRemotes = ReplicatedStorage:WaitForChild("DataRemotes")
local requestPlace = dataRemotes:WaitForChild("RequestPlaceBuilding")

local currentGhost = nil
local previewQ = nil
local previewR = nil
local originalRotation = CFrame.new()

local function clearGhost()
	if currentGhost then currentGhost:Destroy() end
	currentGhost = nil
	previewQ = nil
	previewR = nil
end

local function getSurfaceY(q, r)
	local hexMap = workspace:FindFirstChild("HexMap")
	if not hexMap then return HexGridConfig.Config.SPAWN_Y + 2 end

	local soils = hexMap:FindFirstChild("Soils")
	if soils then
		local prefix = "Soil_" .. q .. "_" .. r .. "_"
		for _, soilFolder in ipairs(soils:GetChildren()) do
			for _, object in ipairs(soilFolder:GetChildren()) do
				if object.Name:sub(1, #prefix) == prefix then
					if object:IsA("Model") then
						local cf, size = object:GetBoundingBox()
						return cf.Position.Y + size.Y / 2
					elseif object:IsA("BasePart") then
						return object.Position.Y + object.Size.Y / 2
					end
				end
			end
		end
	end

	return HexGridConfig.Config.SPAWN_Y + 2
end

local function moveGhostToHex(q, r)
	if not currentGhost then return end

	local worldPos = HexGridConfig.axialToWorld(q, r)
	local topY = HexHeightUtil.getTopY(q, r)

	if currentGhost:IsA("Model") then
		local bboxCf, bboxSize = currentGhost:GetBoundingBox()
		local pivot = currentGhost:GetPivot()
		local pivotToBottom = pivot.Position.Y - (bboxCf.Position.Y - bboxSize.Y / 2)
		currentGhost:PivotTo(CFrame.new(worldPos.X, topY + 0.2 + pivotToBottom, worldPos.Z) * originalRotation)
	elseif currentGhost:IsA("BasePart") then
		currentGhost.CFrame = CFrame.new(worldPos.X, topY + 0.2 + currentGhost.Size.Y / 2, worldPos.Z) * originalRotation
	end

	previewQ = q
	previewR = r
end

local function createGhost(buildingType)
	clearGhost()

	local template = buildingsFolder:FindFirstChild(buildingType)
	if not template then
		warn("[CityPlacement] Model fehlt: ReplicatedStorage > Buildings > " .. tostring(buildingType))
		CityBuildState.Cancel()
		return
	end

	currentGhost = template:Clone()
	currentGhost.Name = "LocalBuildPreview_" .. buildingType
	currentGhost.Parent = workspace

	if currentGhost:IsA("Model") then
		local pivot = currentGhost:GetPivot()
		originalRotation = pivot - pivot.Position
	elseif currentGhost:IsA("BasePart") then
		originalRotation = currentGhost.CFrame - currentGhost.Position
	end

	local parts = currentGhost:IsA("BasePart") and { currentGhost } or currentGhost:GetDescendants()
	for _, part in ipairs(parts) do
		if part:IsA("BasePart") then
			part.Transparency = 0.55
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.Anchored = true
		end
	end

	print("[CityPlacement] Vorschau gestartet: " .. buildingType)
end

CityBuildState.OnChanged:Connect(function(placement)
	if placement then
		createGhost(placement.buildingType)
	else
		clearGhost()
	end
end)

-- Vorschau folgt der Maus, solange ein Build-State aktiv ist.
game:GetService("RunService").RenderStepped:Connect(function()
	if not currentGhost or not CityBuildState.IsPlacing() then return end

	local q, r = HexGridConfig.worldToAxial(mouse.Hit.Position)
	if q ~= previewQ or r ~= previewR then
		moveGhostToHex(q, r)
	end
end)

mouse.Button1Down:Connect(function()
	local placement = CityBuildState.Get()
	if not placement or not currentGhost or previewQ == nil then return end

	requestPlace:FireServer(
		placement.cityId,
		placement.buildingType,
		previewQ,
		previewR
	)

	print("[CityPlacement] Platzierung gesendet: " .. placement.buildingType .. " @ (" .. previewQ .. ", " .. previewR .. ")")
	CityBuildState.Cancel()
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.Escape or input.UserInputType == Enum.UserInputType.MouseButton2 then
		CityBuildState.Cancel()
	end
end)

State.OnChanged:Connect(function(kind, id)
	if kind ~= State.Kind.CITY and not CityBuildState.IsPlacing() then
		clearGhost()
	end
end)

print("[CityPlacement] Bereit")