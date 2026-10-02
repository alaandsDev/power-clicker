--!strict
--[[
	DailyRewardLogic (shared)
	7-day cycle using ONLY the server clock: the server passes os.time(); the
	client passes workspace:GetServerTimeNow() just to DISPLAY the countdown.
	Claims are validated on the server only, so the device clock is irrelevant.

	- First claim ever, or a gap > StreakResetSeconds → streak restarts at 1.
	- A claim needs ClaimIntervalSeconds since the last one (20h: forgiving).
	- Server clocks going backwards (different servers) just mean "not yet".
	- Day index = ((streak - 1) % CycleLength) + 1  → the cycle loops.
]]

local Shared = script.Parent.Parent
local Types = require(Shared.Types)
local DailyRewardConfig = require(Shared.Config.DailyRewardConfig)

type PlayerData = Types.PlayerData
type RewardData = Types.RewardData

export type Preview = {
	CanClaim: boolean,
	Day: number, -- day that will be (or would be) claimed next
	NewStreak: number,
	SecondsUntilClaim: number,
	StreakBroken: boolean,
}

local DailyRewardLogic = {}

function DailyRewardLogic.DayForStreak(streak: number): number
	return ((math.max(1, streak) - 1) % DailyRewardConfig.CycleLength) + 1
end

function DailyRewardLogic.Preview(data: PlayerData, now: number): Preview
	local daily = data.DailyRewards
	local last = tonumber(daily.LastClaimTime) or 0
	local streak = math.max(0, math.floor(tonumber(daily.Streak) or 0))

	if last <= 0 then
		return { CanClaim = true, Day = 1, NewStreak = 1, SecondsUntilClaim = 0, StreakBroken = false }
	end
	local elapsed = now - last
	if elapsed < DailyRewardConfig.ClaimIntervalSeconds then
		local wait = DailyRewardConfig.ClaimIntervalSeconds - math.max(elapsed, 0)
		return { CanClaim = false, Day = DailyRewardLogic.DayForStreak(streak + 1), NewStreak = streak, SecondsUntilClaim = wait, StreakBroken = false }
	end
	local broken = elapsed > DailyRewardConfig.StreakResetSeconds
	local newStreak = if broken then 1 else streak + 1
	return { CanClaim = true, Day = DailyRewardLogic.DayForStreak(newStreak), NewStreak = newStreak, SecondsUntilClaim = 0, StreakBroken = broken }
end

function DailyRewardLogic.RewardsFor(day: number): { RewardData }
	return DailyRewardConfig.Days[day] or {}
end

-- Records a claim previously validated with Preview (same `now`).
function DailyRewardLogic.Commit(data: PlayerData, now: number, newStreak: number)
	local daily = data.DailyRewards
	daily.Streak = newStreak
	daily.LastClaimTime = now
	daily.TotalClaims = (tonumber(daily.TotalClaims) or 0) + 1
end

return DailyRewardLogic
