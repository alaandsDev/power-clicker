--!strict
--[[
	DailyRewardConfig
	All timing uses the SERVER clock (os.time(), UTC). The client clock is never
	consulted, so changing the device time does nothing.

	- A claim is available when now - LastClaimTime >= ClaimIntervalSeconds.
	- If now - LastClaimTime > StreakResetSeconds, the streak restarts at day 1.
	- After day CycleLength the cycle loops back to day 1 (streak keeps counting).
]]

local Types = require(script.Parent.Parent.Types)

type RewardData = Types.RewardData

local Days: { { RewardData } } = {
	{ { Type = "Currency", Currency = "Gems", Amount = 10 } },
	{ { Type = "Boost", BoostId = "Power2x", Amount = 1 } },
	{ { Type = "Currency", Currency = "Gems", Amount = 25 } },
	{ { Type = "Boost", BoostId = "Luck2x", Amount = 1 } },
	{ { Type = "Currency", Currency = "Gems", Amount = 50 } },
	{ { Type = "Boost", BoostId = "Power2x", Amount = 2 } },
	{ { Type = "Pet", PetId = "Panther", Variant = "Normal" }, { Type = "Currency", Currency = "Gems", Amount = 100 } },
}

return {
	Days = Days,
	CycleLength = #Days,
	ClaimIntervalSeconds = 20 * 60 * 60, -- 20h: forgiving for players who log in a bit earlier each day
	StreakResetSeconds = 48 * 60 * 60,
}
