--[[
    PlayerColorConfig (ModuleScript)
    Ort: ServerScriptService > PlayerColorConfig
    
    Verwaltet die festen Spielerfarben für maximal 10 Spieler.
    Jeder Spieler bekommt pro Spiel eine eindeutige Farbe aus der Liste.
    
    Farben:
      1. Rot
      2. Dunkelblau
      3. Neongrün
      4. Gelb
      5. Lila
      6. Orange
      7. Cyan
      8. Magenta
      9. Dunkelgrün
      10. Weiß
    
    Verwendung:
        local PlayerColorConfig = require(script.Parent:WaitForChild("PlayerColorConfig"))
        
        local color = PlayerColorConfig.AssignColor(player)
        print(color)
        
        local sameColor = PlayerColorConfig.GetColor(player)
        PlayerColorConfig.ReleaseColor(player)
--]]

local PlayerColorConfig = {}

--------------------------------------------------------------------------------
-- FARB-LISTE
--------------------------------------------------------------------------------
PlayerColorConfig.AvailableColors = {
	Color3.fromRGB(220, 50, 50),    -- Rot
	Color3.fromRGB(30, 60, 140),    -- Dunkelblau
	Color3.fromRGB(57, 255, 20),    -- Neongrün
	Color3.fromRGB(255, 220, 40),   -- Gelb
	Color3.fromRGB(170, 60, 220),   -- Lila
	Color3.fromRGB(255, 140, 40),   -- Orange
	Color3.fromRGB(40, 220, 220),   -- Cyan
	Color3.fromRGB(255, 60, 180),   -- Magenta
	Color3.fromRGB(20, 110, 40),    -- Dunkelgrün
	Color3.fromRGB(255, 255, 255),  -- Weiß
}

--------------------------------------------------------------------------------
-- Interner State
--------------------------------------------------------------------------------
local assignedColors = {}   -- assignedColors[player] = Color3
local usedIndices = {}      -- usedIndices[index] = player

--------------------------------------------------------------------------------
-- AssignColor(player) -> Color3
-- Weist einem Spieler die nächste freie Farbe zu.
-- Gibt vorhandene Farbe zurück wenn bereits vergeben.
--------------------------------------------------------------------------------
function PlayerColorConfig.AssignColor(player)
	if assignedColors[player] then
		return assignedColors[player]
	end

	-- Erste freie Farbe finden
	for index, color in ipairs(PlayerColorConfig.AvailableColors) do
		if not usedIndices[index] then
			assignedColors[player] = color
			usedIndices[index] = player
			print("[PlayerColorConfig] " .. player.Name .. " bekommt Farbe #" .. index)
			return color
		end
	end

	warn("[PlayerColorConfig] Keine freie Spielerfarbe mehr verfügbar!")
	return Color3.fromRGB(128, 128, 128)
end

--------------------------------------------------------------------------------
-- GetColor(player) -> Color3 or nil
--------------------------------------------------------------------------------
function PlayerColorConfig.GetColor(player)
	return assignedColors[player]
end

--------------------------------------------------------------------------------
-- GetColorIndex(player) -> number or nil
--------------------------------------------------------------------------------
function PlayerColorConfig.GetColorIndex(player)
	local color = assignedColors[player]
	if not color then return nil end

	for index, c in ipairs(PlayerColorConfig.AvailableColors) do
		if c == color then
			return index
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- ReleaseColor(player)
-- Gibt die Farbe eines Spielers wieder frei.
--------------------------------------------------------------------------------
function PlayerColorConfig.ReleaseColor(player)
	local color = assignedColors[player]
	if not color then return end

	for index, c in ipairs(PlayerColorConfig.AvailableColors) do
		if c == color then
			usedIndices[index] = nil
			break
		end
	end

	assignedColors[player] = nil
	print("[PlayerColorConfig] Farbe von " .. player.Name .. " freigegeben")
end

--------------------------------------------------------------------------------
-- ResetAll()
--------------------------------------------------------------------------------
function PlayerColorConfig.ResetAll()
	assignedColors = {}
	usedIndices = {}
	print("[PlayerColorConfig] Alle Farben zurückgesetzt")
end

--------------------------------------------------------------------------------
-- PrintAssignments()
--------------------------------------------------------------------------------
function PlayerColorConfig.PrintAssignments()
	print("[PlayerColorConfig] === Farbzuweisungen ===")
	for player, color in pairs(assignedColors) do
		local index = PlayerColorConfig.GetColorIndex(player)
		print("  " .. player.Name .. " → Farbe #" .. tostring(index))
	end
end

return PlayerColorConfig
