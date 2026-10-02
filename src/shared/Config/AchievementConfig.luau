--!strict
--[[
	AchievementConfig
	Data-driven: each achievement is either a Stat >= Threshold check or a
	WorldId unlocked check. AchievementService (Phase 5) evaluates them
	generically — no per-achievement code.
]]

local Types = require(script.Parent.Parent.Types)

type AchievementData = Types.AchievementData

local function gems(amount: number): { Types.RewardData }
	return { { Type = "Currency", Currency = "Gems", Amount = amount } }
end

local Achievements: { [string]: AchievementData } = {
	FirstClick = { Id = "FirstClick", DisplayName = "First Click", Description = "Click once.", Stat = "TotalClicks", Threshold = 1, Rewards = gems(1) },
	Clicks1K = { Id = "Clicks1K", DisplayName = "1K Clicks", Description = "Click 1,000 times.", Stat = "TotalClicks", Threshold = 1_000, Rewards = gems(5) },
	Clicks10K = { Id = "Clicks10K", DisplayName = "10K Clicks", Description = "Click 10,000 times.", Stat = "TotalClicks", Threshold = 10_000, Rewards = gems(25) },
	Clicks1M = { Id = "Clicks1M", DisplayName = "1M Clicks", Description = "Click 1,000,000 times.", Stat = "TotalClicks", Threshold = 1_000_000, Rewards = gems(500) },
	FirstRebirth = { Id = "FirstRebirth", DisplayName = "Reborn", Description = "Rebirth once.", Stat = "Rebirths", Threshold = 1, Rewards = gems(10) },
	Rebirths10 = { Id = "Rebirths10", DisplayName = "Cycle Breaker", Description = "Rebirth 10 times.", Stat = "Rebirths", Threshold = 10, Rewards = gems(100) },
	FirstLegendary = { Id = "FirstLegendary", DisplayName = "Legend", Description = "Hatch a Legendary pet.", Stat = "LegendaryHatched", Threshold = 1, Rewards = gems(50) },
	FirstMythic = { Id = "FirstMythic", DisplayName = "Myth", Description = "Hatch a Mythic pet.", Stat = "MythicHatched", Threshold = 1, Rewards = gems(250) },
	UnlockCity = { Id = "UnlockCity", DisplayName = "City Lights", Description = "Unlock the City.", WorldId = "City", Rewards = gems(100) },
	UnlockSpace = { Id = "UnlockSpace", DisplayName = "Lift Off", Description = "Unlock Space.", WorldId = "Space", Rewards = gems(1_000) },
}

return {
	Achievements = Achievements,
}
