--!strict
--[[
	QuestLogic
	Generic quests (QuestConfig): progress is added per Type; a quest is
	complete at Target and must be CLAIMED to get rewards.
	- "Once" quests are claimed a single time forever.
	- "Daily" quests reset at QuestConfig.DailyResetUtcHour (server UTC clock).
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local QuestConfig = require(Shared.Config.QuestConfig)
local TimeRules = require(Shared.Formulas.TimeRules)

type PlayerData = Types.PlayerData
type QuestData = Types.QuestData
type QuestProgress = Types.QuestProgress

local QuestLogic = {}

QuestLogic.PeriodStart = TimeRules.PeriodStart
QuestLogic.SecondsUntilReset = TimeRules.SecondsUntilReset

local function entry(data: PlayerData, questId: string): QuestProgress
	local progress = data.Quests.Progress[questId]
	if type(progress) ~= "table" then
		progress = { Progress = 0, Claimed = false }
		data.Quests.Progress[questId] = progress
	end
	return progress
end

-- Resets daily quests when a new period started. Returns true if it reset.
function QuestLogic.ApplyDailyReset(data: PlayerData, now: number): boolean
	local periodStart = QuestLogic.PeriodStart(now)
	if (tonumber(data.Quests.LastDailyReset) or 0) >= periodStart then
		return false
	end
	for id, quest in QuestConfig.Quests do
		if quest.Repeat == "Daily" then
			data.Quests.Progress[id] = { Progress = 0, Claimed = false }
		end
	end
	data.Quests.LastDailyReset = periodStart
	return true
end

-- Adds progress to every unclaimed quest of `questType`. Returns ids that
-- just became complete.
function QuestLogic.AddProgress(data: PlayerData, questType: string, amount: number): { string }
	local completed: { string } = {}
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return completed
	end
	for id, quest in QuestConfig.Quests do
		if quest.Type == questType then
			local progress = entry(data, id)
			if not progress.Claimed and progress.Progress < quest.Target then
				progress.Progress = math.min(progress.Progress + amount, quest.Target)
				if progress.Progress >= quest.Target then
					table.insert(completed, id)
				end
			end
		end
	end
	return completed
end

-- Sets progress to an absolute value when larger (e.g. worlds unlocked count).
function QuestLogic.SetProgressAtLeast(data: PlayerData, questType: string, value: number): { string }
	local completed: { string } = {}
	for id, quest in QuestConfig.Quests do
		if quest.Type == questType then
			local progress = entry(data, id)
			if not progress.Claimed and value > progress.Progress then
				local wasComplete = progress.Progress >= quest.Target
				progress.Progress = math.min(value, quest.Target)
				if not wasComplete and progress.Progress >= quest.Target then
					table.insert(completed, id)
				end
			end
		end
	end
	return completed
end

-- Codes: "UnknownQuest" | "NotComplete" | "AlreadyClaimed"
function QuestLogic.CanClaim(data: PlayerData, questId: string): (boolean, string?, QuestData?)
	local quest = QuestConfig.Quests[questId]
	if not quest then
		return false, "UnknownQuest"
	end
	local progress = data.Quests.Progress[questId]
	if not progress or progress.Progress < quest.Target then
		return false, "NotComplete"
	end
	if progress.Claimed then
		return false, "AlreadyClaimed"
	end
	return true, nil, quest
end

function QuestLogic.MarkClaimed(data: PlayerData, questId: string)
	entry(data, questId).Claimed = true
end

return QuestLogic
