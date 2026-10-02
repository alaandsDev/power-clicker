--!strict
--[[
	SessionConfig
	Two retention systems that need no persisted data (Phase 12):

	Playtime chests — paid automatically at milestones of the CURRENT session
	                  (they reset when the player leaves, so they reward the
	                  session, not the account). Amounts are "clicks worth", so
	                  a veteran gets a veteran-sized chest.

	Happy Hour     — a scheduled server-wide Power multiplier (layer "Event").
	                 Windows are given in UTC hours so every server agrees.
]]

local Types = require(script.Parent.Parent.Types)

type RewardData = Types.RewardData

export type PlaytimeChest = {
	Minutes: number,
	ClicksWorth: number, -- Power = player's per-click × this
	Rewards: { RewardData }, -- extra fixed rewards (gems, boosts)
}

local Chests: { PlaytimeChest } = {
	{ Minutes = 5, ClicksWorth = 60, Rewards = {} },
	{ Minutes = 12, ClicksWorth = 150, Rewards = { { Type = "Currency", Currency = "Gems", Amount = 5 } } },
	{ Minutes = 25, ClicksWorth = 350, Rewards = { { Type = "Boost", BoostId = "Power2x", Amount = 1 } } },
	{ Minutes = 45, ClicksWorth = 750, Rewards = { { Type = "Currency", Currency = "Gems", Amount = 15 } } },
	{ Minutes = 70, ClicksWorth = 1_500, Rewards = { { Type = "Boost", BoostId = "Luck2x", Amount = 1 } } },
}

export type HappyHour = {
	Id: string,
	-- Weekday from os.date("!*t").wday (1 = Sunday ... 7 = Saturday); nil = every day.
	Weekday: number?,
	StartHourUtc: number,
	DurationHours: number,
	Multiplier: number,
}

local HappyHours: { HappyHour } = {
	-- Daily after-school window (18:00–20:00 UTC).
	{ Id = "AfterSchool", Weekday = nil, StartHourUtc = 18, DurationHours = 2, Multiplier = 1.5 },
	-- Weekend: all Saturday and all Sunday.
	{ Id = "Saturday", Weekday = 7, StartHourUtc = 0, DurationHours = 24, Multiplier = 2 },
	{ Id = "Sunday", Weekday = 1, StartHourUtc = 0, DurationHours = 24, Multiplier = 2 },
}

return {
	Chests = Chests,
	HappyHours = HappyHours,

	-- How often the server checks playtime milestones and the clock.
	TickSeconds = 15,
	-- Floor for a chest, so a new player still gets something visible.
	MinChestPower = 250,
}
