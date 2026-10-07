--!strict
--[[
	DataTemplate
	Builds the default PlayerData for brand-new players, and is used to
	reconcile (add missing keys to) loaded data after migrations.

	Changing the SHAPE of this template requires bumping DataConfig.DataVersion
	and writing a migration. Adding a new key with a default value does not
	strictly need a migration (Reconcile adds it), but bump anyway if old data
	needs a non-default value for that key.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local WorldConfig = require(Shared.Config.WorldConfig)
local SeasonConfig = require(Shared.Config.SeasonConfig)
local AuraLogic = require(Shared.Formulas.AuraLogic)
local RuneLogic = require(Shared.Formulas.RuneLogic)
local CutLogic = require(Shared.Formulas.CutLogic)
local SwordLogic = require(Shared.Formulas.SwordLogic)
local AuraSkinLogic = require(Shared.Formulas.AuraSkinLogic)
local DataConfig = require(script.Parent.Parent.Parent.ServerConfig.DataConfig)

type PlayerData = Types.PlayerData

local DataTemplate = {}

-- Top-level keys that are never sent to the client.
DataTemplate.ServerOnlyKeys = table.freeze({
	Purchases = true,
})

function DataTemplate.Create(now: number): PlayerData
	return {
		DataVersion = DataConfig.DataVersion,
		Currencies = {
			Power = 0,
			Gems = 0,
			Wins = 0,
		},
		Stats = {
			TotalClicks = 0,
			TotalPowerEarned = 0,
			TotalGemsEarned = 0,
			TotalWinsEarned = 0,
			Rebirths = 0,
			RebirthAnchor = 0, -- save novo: curva de renascimento nova direto
			EggsOpened = 0,
			PlaytimeSeconds = 0,
			OverdrivesActivated = 0,
			HighestCombo = 0,
			LegendaryHatched = 0,
			MythicHatched = 0,
			FirstJoinTime = now,
			LastJoinTime = now,
			SessionCount = 0,
		},
		Upgrades = {},
		PermanentUpgrades = {},
		Pets = {
			Inventory = {},
			Equipped = {},
			NextUid = 1,
		},
		Worlds = {
			Unlocked = { [WorldConfig.DefaultWorld] = true },
			Current = WorldConfig.DefaultWorld,
		},
		Boosts = {
			Remaining = {},
		},
		Overdrive = {
			Charge = 0,
		},
		DailyRewards = {
			Streak = 0,
			LastClaimTime = 0,
			TotalClaims = 0,
		},
		Quests = {
			Progress = {},
			LastDailyReset = 0,
		},
		Achievements = {
			Unlocked = {},
		},
		Codes = {
			Redeemed = {},
		},
		Purchases = {
			ProcessedReceipts = {},
			ReceiptOrder = {},
			OneTimeOffersClaimed = {},
			TotalRobuxSpent = 0,
		},
		Settings = {
			MusicVolume = 0.5,
			SfxVolume = 0.8,
			ShowFloatingNumbers = true,
			ReducedEffects = false,
		},
		Tutorial = {
			Step = 0,
			Completed = false,
		},
		Season = {
			SeasonId = SeasonConfig.Id,
			Xp = 0,
			ClaimedFree = {},
			ClaimedVip = {},
		},
		Auras = AuraLogic.Fresh(),
		Runes = RuneLogic.Fresh(),
		Cuts = CutLogic.Fresh(),
		Tower = { Cleared = {}, Highest = 0 },
		Swords = SwordLogic.Fresh(),
		AuraSkins = AuraSkinLogic.Fresh(),
	}
end

-- Set of valid stat names (used by ConfigValidator for achievements).
function DataTemplate.StatKeys(): { [string]: boolean }
	local keys = {}
	for key in DataTemplate.Create(0).Stats :: any do
		keys[key] = true
	end
	return keys
end

return DataTemplate
