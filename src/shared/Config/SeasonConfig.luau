--!strict
--[[
	SeasonConfig
	Season pass: 20 levels, two tracks (free for everyone, VIP for the pass
	holders). XP comes from playing — quests, daily rewards, playtime chests,
	bosses and broken targets — never from spending Robux.

	Changing Id starts a NEW season: SeasonService sees the mismatch and resets
	that player's progress (levels and claims) the next time they play.
	Rewards are built from the constants below, so the curve stays readable
	instead of twenty hand-written rows.
]]

local Types = require(script.Parent.Parent.Types)

type RewardData = Types.RewardData

export type SeasonLevel = {
	Level: number,
	Free: { RewardData },
	Vip: { RewardData },
}

local LEVEL_COUNT = 20
local XP_PER_LEVEL = 120

-- Free track: gems that grow with the level.
local FREE_GEMS_BASE = 8
local FREE_GEMS_STEP = 4
-- Every Nth level pays a boost instead of gems.
local BOOST_EVERY = 5
-- VIP track: the same gems doubled, plus a boost on every boost level.
local VIP_GEMS_FACTOR = 2

local function gems(amount: number): RewardData
	return { Type = "Currency", Currency = "Gems", Amount = amount }
end

local function boost(boostId: string, stacks: number): RewardData
	return { Type = "Boost", BoostId = boostId, Amount = stacks }
end

local Levels: { SeasonLevel } = {}
for level = 1, LEVEL_COUNT do
	local amount = FREE_GEMS_BASE + FREE_GEMS_STEP * (level - 1)
	local isBoostLevel = level % BOOST_EVERY == 0
	local free: { RewardData } = if isBoostLevel then { boost("Power2x", 1) } else { gems(amount) }
	local vip: { RewardData } = { gems(amount * VIP_GEMS_FACTOR) }
	if isBoostLevel then
		table.insert(vip, boost("Luck2x", 1))
	end
	-- The last level of the VIP track pays the exclusive pet.
	if level == LEVEL_COUNT then
		table.insert(vip, { Type = "Pet", PetId = "StarterDragonling", Variant = "Normal" })
	end
	Levels[level] = { Level = level, Free = free, Vip = vip }
end

-- XP granted by each activity (SeasonService.AddXp callers).
local XpSources = {
	QuestClaimed = 20,
	DailyReward = 30,
	PlaytimeChest = 25,
	BossDefeated = 40,
	TargetBroken = 1,
}

return {
	Id = "S1", -- change to start a new season (progress resets)
	DisplayName = "Temporada 1",
	LevelCount = LEVEL_COUNT,
	XpPerLevel = XP_PER_LEVEL,
	Levels = Levels,
	XpSources = XpSources,
}
