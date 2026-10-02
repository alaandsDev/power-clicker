--!strict
--[[
	QuestConfig
	Generic quests: QuestService (Phase 5) listens to gameplay events of the
	matching Type and increments Progress up to Target. Adding a quest = adding
	an entry here; no code changes needed for existing Types.
]]

local Types = require(script.Parent.Parent.Types)

type QuestData = Types.QuestData

local Quests: { [string]: QuestData } = {
	Click100 = {
		Id = "Click100",
		DisplayName = "Warm Up: click 100 times",
		Type = "Clicks",
		Target = 100,
		Rewards = { { Type = "Currency", Currency = "Gems", Amount = 5 } },
		Repeat = "Once",
	},
	FirstRebirth = {
		Id = "FirstRebirth",
		DisplayName = "Rebirth once",
		Type = "Rebirths",
		Target = 1,
		Rewards = { { Type = "Currency", Currency = "Gems", Amount = 15 } },
		Repeat = "Once",
	},
	HatchThree = {
		Id = "HatchThree",
		DisplayName = "Hatch 3 eggs",
		Type = "EggsOpened",
		Target = 3,
		Rewards = { { Type = "Currency", Currency = "Gems", Amount = 10 } },
		Repeat = "Once",
	},
	DailyClicks = {
		Id = "DailyClicks",
		DisplayName = "Daily: click 2,000 times",
		Type = "Clicks",
		Target = 2_000,
		Rewards = { { Type = "Currency", Currency = "Gems", Amount = 10 } },
		Repeat = "Daily",
	},
	DailyPlaytime = {
		Id = "DailyPlaytime",
		DisplayName = "Daily: play for 15 minutes",
		Type = "Playtime",
		Target = 15 * 60,
		Rewards = { { Type = "Boost", BoostId = "Power2x", Amount = 1 } },
		Repeat = "Daily",
	},
	DailyOverdrive = {
		Id = "DailyOverdrive",
		DisplayName = "Daily: trigger Overdrive 3 times",
		Type = "Overdrives",
		Target = 3,
		Rewards = { { Type = "Currency", Currency = "Gems", Amount = 10 } },
		Repeat = "Daily",
	},
}

return {
	Quests = Quests,
	-- Daily quests reset at 00:00 UTC (server clock).
	DailyResetUtcHour = 0,
}
