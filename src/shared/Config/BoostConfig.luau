--!strict
--[[
	BoostConfig
	Temporary boosts. Stacking rule (economy safety):
	- Buying the same boost again ADDS duration (capped at MaxStoredSeconds).
	- Within a Category only the HIGHEST active multiplier applies; boosts of the
	  same category never multiply each other.
	- Boost time is consumed only while the player is online.
]]

local Types = require(script.Parent.Parent.Types)

type BoostData = Types.BoostData

local Boosts: { [string]: BoostData } = {
	Power2x = {
		Id = "Power2x",
		DisplayName = "2x Power",
		Category = "Power",
		Multiplier = 2,
		DurationSeconds = 15 * 60,
		MaxStoredSeconds = 6 * 60 * 60,
	},
	Power5x = {
		Id = "Power5x",
		DisplayName = "5x Power",
		Category = "Power",
		Multiplier = 5,
		DurationSeconds = 10 * 60,
		MaxStoredSeconds = 3 * 60 * 60,
	},
	Luck2x = {
		Id = "Luck2x",
		DisplayName = "2x Luck",
		Category = "Luck",
		Multiplier = 2,
		DurationSeconds = 15 * 60,
		MaxStoredSeconds = 6 * 60 * 60,
	},
}

return {
	Boosts = Boosts,
}
