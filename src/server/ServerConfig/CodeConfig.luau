--!strict
--[[
	CodeConfig (server-only — never place codes in ReplicatedStorage, clients
	could read them).

	Keys are normalized codes (UPPERCASE, trimmed). CodeService (Phase 5):
	- ExpiresAt: optional unix time (UTC); nil = never expires.
	- MaxRedemptions: optional global cap; requires a DataStore counter
	  (TODO Phase 5). nil = unlimited.
	- Each player may redeem a code once (tracked in PlayerData.Codes).
]]

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

export type CodeData = {
	Rewards: { Types.RewardData },
	ExpiresAt: number?,
	MaxRedemptions: number?,
	Enabled: boolean,
}

local Codes: { [string]: CodeData } = {
	RELEASE = {
		Rewards = { { Type = "Currency", Currency = "Gems", Amount = 25 } },
		ExpiresAt = nil,
		MaxRedemptions = nil,
		Enabled = true,
	},
	POWERUP = {
		Rewards = { { Type = "Boost", BoostId = "Power2x", Amount = 1 } },
		ExpiresAt = nil,
		MaxRedemptions = nil,
		Enabled = true,
	},
}

return {
	Codes = Codes,
	MaxCodeLength = 32,
}
