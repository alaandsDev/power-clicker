--!strict
--[[
	LeaderboardConfig
	Global leaderboards use OrderedDataStores (Phase 5). Writes are batched per
	player at UpdateIntervalSeconds; board reads are cached for RefreshIntervalSeconds.
	OrderedDataStore only stores integers, so large values are stored as
	floor(log10(value) * LogScale) when UseLogScale = true.
]]

export type BoardConfig = {
	Stat: string, -- key in PlayerData.Stats
	StoreName: string, -- OrderedDataStore name
	UseLogScale: boolean,
	LogScale: number?, -- required when UseLogScale
}

local Boards: { [string]: BoardConfig } = {
	Clicks = { Stat = "TotalClicks", StoreName = "LB_Clicks_v1", UseLogScale = false },
	Rebirths = { Stat = "Rebirths", StoreName = "LB_Rebirths_v1", UseLogScale = false },
	Power = { Stat = "TotalPowerEarned", StoreName = "LB_Power_v1", UseLogScale = true, LogScale = 1000 },
	Wins = { Stat = "TotalWinsEarned", StoreName = "LB_Wins_v1", UseLogScale = false },
}

return {
	UpdateIntervalSeconds = 120,
	RefreshIntervalSeconds = 90,
	TopCount = 50,

	Boards = Boards,
}
