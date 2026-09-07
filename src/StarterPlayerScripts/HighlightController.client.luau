--[[
    HighlightController (LocalScript)
    Ort: StarterPlayer > StarterPlayerScripts > HighlightController
    
    Lässt das ausgewählte Objekt leuchten (Army, Camp oder City).
    Ersetzt: SelectionHighlighter, CampHighlighter, CityHighlighter,
             UnifiedHighlighter
--]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local State = require(ReplicatedStorage:WaitForChild("ClientState"))
local Net = require(ReplicatedStorage:WaitForChild("Net"))

--------------------------------------------------------------------------------
-- Wie finde ich das Modell? Und in welcher Farbe leuchtet es?
--------------------------------------------------------------------------------
local function hexMapFolder(name)
	local map = workspace:FindFirstChild("HexMap")
	if not map then return nil end
	return map:FindFirstChild(name)
end

local STYLES = {
	army = {
		fill = Color3.fromRGB(255, 215, 80),
		line = Color3.fromRGB(255, 255, 180),
		find = function(id)
			local folder = hexMapFolder("ArmyModels")
			return folder and folder:FindFirstChild("Army_" .. id) or nil
		end,
	},
	camp = {
		fill = Color3.fromRGB(255, 215, 80),
		line = Color3.fromRGB(255, 255, 180),
		find = function(id)
			local ok, camp = Net.Invoke("GetCamp", id)
			if not ok or not camp then return nil end
			local folder = hexMapFolder("Buildings")
			return folder and folder:FindFirstChild("Camp_" .. camp.q .. "_" .. camp.r) or nil
		end,
	},
	city = {
		fill = Color3.fromRGB(100, 255, 100),
		line = Color3.fromRGB(200, 255, 200),
		find = function(id)
			local ok, city = Net.Invoke("GetCity", id)
			if not ok or not city then return nil end
			local folder = hexMapFolder("Buildings")
			return folder and folder:FindFirstChild("City_" .. city.q .. "_" .. city.r) or nil
		end,
	},
}

local BASE_FILL, BASE_LINE = 0.7, 0.05
local PULSE_STRENGTH, PULSE_SPEED = 0.15, 2.5

--------------------------------------------------------------------------------
local highlight = Instance.new("Highlight")
highlight.Name = "SelectionHighlight"
highlight.Enabled = false
highlight.FillTransparency = BASE_FILL
highlight.OutlineTransparency = BASE_LINE
highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
highlight.Parent = workspace

local pulse = nil
local token = 0

local function stopPulse()
	if pulse then pulse:Disconnect() pulse = nil end
end

local function clear()
	stopPulse()
	highlight.Adornee = nil
	highlight.Enabled = false
end

local function apply(kind, id)
	local style = STYLES[kind]
	if not style then clear() return end

	token = token + 1
	local myToken = token

	task.spawn(function()
		-- bis zu 8 Versuche, falls das Modell gerade erst gespawnt wird
		for _ = 1, 8 do
			if myToken ~= token then return end

			local model = style.find(id)
			if model then
				if myToken ~= token then return end

				highlight.Adornee = model
				highlight.FillColor = style.fill
				highlight.OutlineColor = style.line
				highlight.Enabled = true

				stopPulse()
				local start = tick()
				pulse = RunService.RenderStepped:Connect(function()
					if not highlight.Enabled then return end

					-- Army-Modelle können neu gespawnt werden
					if kind == "army" then
						local current = style.find(id)
						if current and highlight.Adornee ~= current then
							highlight.Adornee = current
						end
					end

					local wave = (math.sin((tick() - start) * PULSE_SPEED * math.pi * 2) + 1) * 0.5
					local p = wave * PULSE_STRENGTH
					highlight.FillTransparency = math.clamp(BASE_FILL - p, 0, 1)
					highlight.OutlineTransparency = math.clamp(BASE_LINE + p * 0.3, 0, 1)
				end)
				return
			end

			task.wait(0.25)
		end

		if myToken == token then clear() end
	end)
end

--------------------------------------------------------------------------------
State.OnChanged:Connect(function(kind, id)
	if kind and id then apply(kind, id) else token = token + 1 clear() end
end)

local kind, id = State.Get()
if kind and id then apply(kind, id) else clear() end

print("[HighlightController] Bereit.")