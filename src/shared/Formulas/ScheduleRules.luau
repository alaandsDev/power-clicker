--!strict
--[[
	ScheduleRules
	Pure clock rules for the Happy Hour windows (SessionConfig.HappyHours).
	Server and client both use these, so the banner and the real multiplier
	can never disagree. Everything is UTC, so all servers agree too.
]]

local Shared = script.Parent.Parent
local SessionConfig = require(Shared.Config.SessionConfig)

type HappyHour = SessionConfig.HappyHour

local HOUR = 3600
local DAY = 24 * HOUR

local ScheduleRules = {}

-- Seconds since midnight UTC and the weekday (1 = Sunday) of `timestamp`.
local function clockOf(timestamp: number): (number, number)
	local parts = os.date("!*t", timestamp)
	return parts.hour * HOUR + parts.min * 60 + parts.sec, parts.wday
end

--[[
	The window running at `timestamp`, plus how many seconds are left in it.
	When several overlap, the strongest multiplier wins.
	Returns nil when no event is running.
]]
function ScheduleRules.Active(timestamp: number): (HappyHour?, number)
	local seconds, weekday = clockOf(timestamp)
	local best: HappyHour? = nil
	local bestLeft = 0
	for _, window in SessionConfig.HappyHours do
		if window.Weekday == nil or window.Weekday == weekday then
			local start = window.StartHourUtc * HOUR
			local finish = start + window.DurationHours * HOUR
			-- A window may wrap past midnight.
			local inside = (seconds >= start and seconds < finish) or (finish > DAY and seconds < finish - DAY)
			if inside then
				local left = if seconds >= start then finish - seconds else finish - DAY - seconds
				if best == nil or window.Multiplier > best.Multiplier then
					best, bestLeft = window, left
				end
			end
		end
	end
	return best, math.max(bestLeft, 0)
end

-- Power multiplier in force at `timestamp` (1 when nothing is running).
function ScheduleRules.Multiplier(timestamp: number): number
	local window = ScheduleRules.Active(timestamp)
	return if window then window.Multiplier else 1
end

return ScheduleRules
