--[[
    CampGuiController (LocalScript)
    Ort: StarterGui > CampGui > CampGuiController

    Zeigt/Versteckt die CampGui basierend auf CampSelectionState.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local State = require(ReplicatedStorage:WaitForChild("ClientState"))
local Net = require(ReplicatedStorage:WaitForChild("Net"))

local campGui = script.Parent
local campFrame = campGui:FindFirstChild("CampFrame")

if not campFrame then
	warn("[CampGuiController] CampFrame fehlt in CampGui")
	return
end

local campNameLabel = campFrame:FindFirstChild("CampName")
local campCitizenLabel = campFrame:FindFirstChild("CampCitizenLable")
local foundCityButton = campFrame:FindFirstChild("FoundCityButton")

if not campNameLabel then warn("[CampGuiController] CampName fehlt") end
if not campCitizenLabel then warn("[CampGuiController] CampCitizenLable fehlt") end
if not foundCityButton then warn("[CampGuiController] FoundCityButton fehlt") end

local selectedCampId = nil
local missingCampResponses = 0

local function clearStats()
	if campNameLabel then campNameLabel.Text = "" end
	if campCitizenLabel then campCitizenLabel.Text = "0" end
end

local function updateStats(campId)
	local success, camp = Net.Invoke("GetCamp", campId)

	if not success then
		warn("[CampGuiController] GetCamp Remote-Fehler")
		return
	end

	if not camp then
		missingCampResponses = missingCampResponses + 1

		-- Nach mehreren fehlenden Antworten wurde das Camp wahrscheinlich
		-- in eine City umgewandelt.
		if missingCampResponses >= 3 and State.Is(State.Kind.CAMP, campId) then
			State.Clear()
		end
		return
	end

	missingCampResponses = 0

	if campNameLabel then
		campNameLabel.Text = camp.name or ("Camp " .. tostring(camp.id))
	end
	if campCitizenLabel then
		campCitizenLabel.Text = tostring(camp.citizenCount or 0)
	end
end

-- Auswahl zuerst verbinden
State.OnChanged:Connect(function(kind, newCampId)
	if kind ~= State.Kind.CAMP then
		campGui.Enabled = false
		clearStats()
		return
	end

	selectedCampId = newCampId
	missingCampResponses = 0

	campGui.Enabled = true
	print("[CampGuiController] GUI sichtbar für Camp " .. tostring(newCampId))
	task.spawn(updateStats, newCampId)
end)

if foundCityButton then
	foundCityButton.MouseButton1Click:Connect(function()
		local campId = State.GetId(State.Kind.CAMP)
		if not campId then return end

		Net.Fire("RequestFoundCity", campId)
		print("[CampGuiController] City-Gründung angefordert für Camp " .. tostring(campId))
	end)
end

task.spawn(function()
	while true do
		task.wait(0.5)

		if campGui.Enabled and selectedCampId then
			updateStats(selectedCampId)
		end
	end
end)

local initKind, initId = State.Get()
if initKind == State.Kind.CAMP and initId then
	selectedCampId = initId
	campGui.Enabled = true
	task.spawn(updateStats, initId)
else
	campGui.Enabled = false
	clearStats()
end

print("[CampGuiController] Bereit")