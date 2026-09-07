--[[
    HoverPreview (LocalScript)
    Ort: StarterPlayer > StarterPlayerScripts > HoverPreview
    
    Zeigt einen transparenten Klon der ausgewählten Army
    auf dem Hex unter der Maus an.
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local State = require(ReplicatedStorage:WaitForChild("ClientState"))
local HexGridConfig = require(ReplicatedStorage:WaitForChild("HexGridConfig"))

--------------------------------------------------------------------------------
-- KONFIGURATION
--------------------------------------------------------------------------------
local CONFIG = {
	PREVIEW_TRANSPARENCY = 0.5,
	PREVIEW_Y_OFFSET = 0.35,
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------
local previewClone = nil
local currentPreviewArmyId = nil
local lastHoverQ = nil
local lastHoverR = nil
local lockedQ = nil
local lockedR = nil

--------------------------------------------------------------------------------
-- Klon erstellen / zerstören
--------------------------------------------------------------------------------
local function destroyPreviewClone()
	if previewClone then
		previewClone:Destroy()
		previewClone = nil
	end
	currentPreviewArmyId = nil
	lockedQ = nil
	lockedR = nil
end

local function createPreviewClone(armyId)
	destroyPreviewClone()

	local hexMap = workspace:FindFirstChild("HexMap")
	if not hexMap then return end
	local armyModels = hexMap:FindFirstChild("ArmyModels")
	if not armyModels then return end
	local originalModel = armyModels:FindFirstChild("Army_" .. armyId)
	if not originalModel then return end

	previewClone = originalModel:Clone()
	previewClone.Name = "PreviewClone"

	for _, part in ipairs(previewClone:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Transparency = CONFIG.PREVIEW_TRANSPARENCY
			part.CanCollide = false
		end
	end

	previewClone.Parent = workspace
	currentPreviewArmyId = armyId
end

--------------------------------------------------------------------------------
-- Hex aus Mausposition
--------------------------------------------------------------------------------
local function getHexFromMouse()
	local target = mouse.Target
	if not target then return nil, nil end

	-- VORSCHAU-SCHUTZ: Wenn die Maus auf dem Klon selbst hängt, behalte letzte Position bei
	if previewClone then
		local current = target
		while current do
			if current == previewClone then
				return lastHoverQ, lastHoverR
			end
			current = current.Parent
		end
	end

	return HexGridConfig.worldToAxial(mouse.Hit.Position)
end

--------------------------------------------------------------------------------
-- Klon auf Hex positionieren
--------------------------------------------------------------------------------
local function moveCloneToHex(q, r)
	if not previewClone then return end

	local worldPos = HexGridConfig.axialToWorld(q, r)
	local topY = HexGridConfig.Config.SPAWN_Y + 2
	local extraY = CONFIG.PREVIEW_Y_OFFSET

	if previewClone:IsA("Model") then
		local bboxCf, bboxSize = previewClone:GetBoundingBox()
		local pivot = previewClone:GetPivot()

		local pivotToBottom = pivot.Position.Y - (bboxCf.Position.Y - bboxSize.Y / 2)
		local targetPivotY = topY + extraY + pivotToBottom

		local rotation = pivot - pivot.Position
		previewClone:PivotTo(CFrame.new(worldPos.X, targetPivotY, worldPos.Z) * rotation)
	elseif previewClone:IsA("BasePart") then
		local halfY = previewClone.Size.Y / 2
		previewClone.Position = Vector3.new(worldPos.X, topY + extraY + halfY, worldPos.Z)
	end
end

--------------------------------------------------------------------------------
-- LockToHex / Unlock
--------------------------------------------------------------------------------
function SetPreviewLock(q, r)
	lockedQ = q
	lockedR = r
	if previewClone and q and r then
		moveCloneToHex(q, r)
	end
end

function ClearPreviewLock()
	lockedQ = nil
	lockedR = nil
end

_G.SetPreviewLock = SetPreviewLock
_G.ClearPreviewLock = ClearPreviewLock

--------------------------------------------------------------------------------
-- Update Loop
--------------------------------------------------------------------------------
RunService.RenderStepped:Connect(function()
	local armyId = State.GetId(State.Kind.ARMY)

	if not armyId then
		if previewClone then destroyPreviewClone() end
		lastHoverQ = nil
		lastHoverR = nil
		return
	end

	if currentPreviewArmyId ~= armyId then
		createPreviewClone(armyId)
	end

	if not previewClone then return end

	if lockedQ and lockedR then
		moveCloneToHex(lockedQ, lockedR)
		return
	end

	local q, r = getHexFromMouse()
	if q == nil then
		previewClone.Parent = nil
		return
	end

	if q ~= lastHoverQ or r ~= lastHoverR then
		lastHoverQ = q
		lastHoverR = r

		if previewClone.Parent == nil then
			previewClone.Parent = workspace
		end

		moveCloneToHex(q, r)
	end
end)

State.OnChanged:Connect(function(kind, id)
	if kind ~= State.Kind.ARMY then
		destroyPreviewClone()
	end
end)

print("[HoverPreview] Bereit.")