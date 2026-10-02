--!strict
--[[
	TimeRules (shared)
	Daily period boundaries for daily quests, on the SERVER clock (UTC). The
	client passes workspace:GetServerTimeNow() only to display countdowns.
]]

local QuestConfig = require(script.Parent.Parent.Config.QuestConfig)

local DAY = 24 * 60 * 60

local TimeRules = {}

-- Start (unix time) of the daily period containing `now`.
function TimeRules.PeriodStart(now: number): number
	local offset = QuestConfig.DailyResetUtcHour * 3600
	return math.floor((now - offset) / DAY) * DAY + offset
end

function TimeRules.SecondsUntilReset(now: number): number
	return TimeRules.PeriodStart(now) + DAY - now
end

return TimeRules
