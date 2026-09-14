--[[
    TechData (ModuleScript)
    Location: ServerScriptService > TechData

    In-memory research state per player. Holds NO game logic - the rules live
    in TechTreeSystem.

    Record layout:
    {
        player          : Player,
        techLevels      : { [techId] = level },  -- 0 = none, 1 = Bronze, 2 = Silver, 3 = Gold
        researchQueue   : { techId, ... },       -- ORDER MATTERS (index 1 first)
        currentProgress : { [techId] = number }, -- accumulated RP for the NEXT tier
        totalRPPerRound : number,                -- cached for the GUI
    }

    A tech's target tier is derived from its current level at research time:
        level 0 -> tier 1 (Bronze), level 1 -> tier 2 (Silver), level 2 -> tier 3 (Gold).
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TechConfig = require(ReplicatedStorage:WaitForChild("TechConfig"))

local TechData = {}

local records: { [any]: any } = {}

local MAX_QUEUE = 16   -- there are only 16 techs in total

--------------------------------------------------------------------------------
-- Create(player) -> record
--------------------------------------------------------------------------------
function TechData.Create(player)
	if records[player] then return records[player] end

	records[player] = {
		player = player,
		techLevels = {},
		researchQueue = {},
		currentProgress = {},
		totalRPPerRound = 0,
	}
	return records[player]
end

function TechData.Get(player)
	if not player then return nil end
	return records[player] or TechData.Create(player)
end

function TechData.GetAll()
	return records
end

function TechData.Remove(player)
	records[player] = nil
end

function TechData.ClearAll()
	records = {}
	print("[TechData] Alle Forschungsdaten geloescht.")
end

--------------------------------------------------------------------------------
-- LEVELS
--------------------------------------------------------------------------------
-- GetLevel(player, techId) -> number (0-3)
function TechData.GetLevel(player, techId)
	local rec = TechData.Get(player)
	if not rec then return 0 end
	return rec.techLevels[techId] or 0
end

function TechData.SetLevel(player, techId, level)
	local rec = TechData.Get(player)
	if not rec then return end
	rec.techLevels[techId] = math.clamp(tonumber(level) or 0, 0, TechConfig.MAX_LEVEL)
end

-- IsResearched: a tech counts as researched as soon as it reached tier 1+.
function TechData.IsResearched(player, techId)
	return TechData.GetLevel(player, techId) >= 1
end

--------------------------------------------------------------------------------
-- QUEUE
--------------------------------------------------------------------------------
function TechData.IsQueued(player, techId)
	local rec = TechData.Get(player)
	if not rec then return false end
	for _, id in ipairs(rec.researchQueue) do
		if id == techId then return true end
	end
	return false
end

function TechData.QueuePosition(player, techId)
	local rec = TechData.Get(player)
	if not rec then return nil end
	for i, id in ipairs(rec.researchQueue) do
		if id == techId then return i end
	end
	return nil
end

-- AddToQueue(player, techId) -> boolean, reason
-- Queues the NEXT tier of a tech (the tier is derived later in ProcessResearch).
function TechData.AddToQueue(player, techId)
	local rec = TechData.Get(player)
	if not rec then return false, "Keine Spielerdaten" end
	if not TechConfig.IsValidTech(techId) then return false, "Unbekannte Technologie" end
	if rec.techLevels[techId] and rec.techLevels[techId] >= TechConfig.MAX_LEVEL then
		return false, "Bereits auf Gold (max)"
	end
	if TechData.IsQueued(player, techId) then return false, "Bereits in der Queue" end
	if #rec.researchQueue >= MAX_QUEUE then return false, "Queue ist voll" end

	table.insert(rec.researchQueue, techId)
	-- Progress starts at 0 (or keeps a partial value from an earlier attempt).
	rec.currentProgress[techId] = rec.currentProgress[techId] or 0
	return true, nil
end

-- RemoveFromQueue(player, techId) -> boolean, reason
-- The accumulated RP are KEPT, so re-queuing later continues where it stopped.
function TechData.RemoveFromQueue(player, techId)
	local rec = TechData.Get(player)
	if not rec then return false, "Keine Spielerdaten" end

	for i, id in ipairs(rec.researchQueue) do
		if id == techId then
			table.remove(rec.researchQueue, i)
			return true, nil
		end
	end
	return false, "Nicht in der Queue"
end

-- ReorderQueue(player, newOrder) -> boolean, reason
-- Only accepts a permutation of the CURRENT queue (no smuggling in new techs).
function TechData.ReorderQueue(player, newOrder)
	local rec = TechData.Get(player)
	if not rec then return false, "Keine Spielerdaten" end
	if type(newOrder) ~= "table" then return false, "Ungueltige Reihenfolge" end

	local current = {}
	for _, id in ipairs(rec.researchQueue) do current[id] = true end

	local seen, result = {}, {}
	for _, id in ipairs(newOrder) do
		if type(id) == "string" and current[id] and not seen[id] then
			seen[id] = true
			table.insert(result, id)
		end
	end

	-- Anything the client forgot keeps its relative order at the end.
	for _, id in ipairs(rec.researchQueue) do
		if not seen[id] then table.insert(result, id) end
	end

	rec.researchQueue = result
	return true, nil
end

--------------------------------------------------------------------------------
-- PROGRESS
--------------------------------------------------------------------------------
function TechData.GetProgress(player, techId)
	local rec = TechData.Get(player)
	if not rec then return 0 end
	return rec.currentProgress[techId] or 0
end

function TechData.SetProgress(player, techId, value)
	local rec = TechData.Get(player)
	if not rec then return end
	rec.currentProgress[techId] = math.max(0, value or 0)
end

-- MarkResearched: advance the tech one tier, drop it from the queue and
-- reset the progress so the NEXT tier starts from 0.
function TechData.MarkResearched(player, techId)
	local rec = TechData.Get(player)
	if not rec then return false end

	local tech = TechConfig.GetTech(techId)
	if not tech then return false end

	local nextLevel = (rec.techLevels[techId] or 0) + 1
	rec.techLevels[techId] = math.clamp(nextLevel, 0, TechConfig.MAX_LEVEL)
	rec.currentProgress[techId] = 0
	TechData.RemoveFromQueue(player, techId)
	return true
end

function TechData.SetTotalRP(player, value)
	local rec = TechData.Get(player)
	if not rec then return end
	rec.totalRPPerRound = math.max(0, value or 0)
end

function TechData.GetTotalRP(player)
	local rec = TechData.Get(player)
	return rec and rec.totalRPPerRound or 0
end

--------------------------------------------------------------------------------
-- BuildClientPayload(player) -> table  (sent through TechTreeUpdate)
--------------------------------------------------------------------------------
function TechData.BuildClientPayload(player)
	local rec = TechData.Get(player)
	if not rec then return nil end

	local rp = rec.totalRPPerRound or 0
	local progress = {}
	local spent = 0

	-- Rounds left is cumulative: a tech at queue position 3 has to wait for
	-- everything in front of it. Costs are based on the tech's TARGET tier.
	for _, techId in ipairs(rec.researchQueue) do
		local tech = TechConfig.GetTech(techId)
		if tech then
			local level = rec.techLevels[techId] or 0
			local targetLevel = level + 1
			local cost = TechConfig.GetLevelCost(techId, targetLevel)
			local current = rec.currentProgress[techId] or 0
			local remaining = math.max(0, cost - current)
			spent += remaining

			progress[techId] = {
				current = current,
				max = cost,
				level = level,
				targetLevel = targetLevel,
				roundsLeft = (rp > 0) and math.ceil(spent / rp) or -1, -- -1 = never
			}
		end
	end

	-- Partial progress of techs that are NOT queued right now (a tier was
	-- started but the tech was removed from the queue before it finished).
	for techId, value in pairs(rec.currentProgress) do
		if not progress[techId] then
			local level = rec.techLevels[techId] or 0
			-- Ignore already-finished (value reset to 0) or maxed techs.
			if level < TechConfig.MAX_LEVEL and value > 0 then
				local tech = TechConfig.GetTech(techId)
				if tech then
					local targetLevel = level + 1
					local cost = TechConfig.GetLevelCost(techId, targetLevel)
					progress[techId] = {
						current = value,
						max = cost,
						level = level,
						targetLevel = targetLevel,
						roundsLeft = -1,
					}
				end
			end
		end
	end

	local techLevels = {}
	for techId, level in pairs(rec.techLevels) do
		if level > 0 then techLevels[techId] = level end
	end

	local queue = {}
	for i, techId in ipairs(rec.researchQueue) do queue[i] = techId end

	return {
		techLevels = techLevels,
		researchQueue = queue,
		currentProgress = progress,
		totalRPPerRound = rp,
	}
end

return TechData
