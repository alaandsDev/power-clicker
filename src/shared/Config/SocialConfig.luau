--!strict
--[[
	SocialConfig
	Playing with other people pays (Phase 13):

	Friend bonus — every friend of yours in the same server adds a slice of
	                Power (layer "Social"), capped so a full friend list does
	                not break the economy.
	Group reward — one-time gift for members of the game's Roblox group.
	                GroupId = 0 disables it (no group created yet).
]]

local Types = require(script.Parent.Parent.Types)

type RewardData = Types.RewardData

local GroupRewards: { RewardData } = {
	{ Type = "Currency", Currency = "Gems", Amount = 50 },
	{ Type = "Boost", BoostId = "Power2x", Amount = 1 },
}

return {
	Friends = {
		BonusPerFriend = 0.05, -- +5% Power each
		MaxFriends = 6, -- cap: +30%
	},

	Group = {
		GroupId = 0, -- TODO_GROUP_ID: paste the group id to switch this on
		Rewards = GroupRewards,
		-- Key in Purchases.OneTimeOffersClaimed, so it is paid once per account.
		ClaimKey = "GroupJoin",
	},

	-- Friendship is a web call; re-checked at most this often per player.
	RefreshSeconds = 20,
}
