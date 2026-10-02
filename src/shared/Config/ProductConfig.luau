--!strict
--[[
	ProductConfig
	Game Passes and Developer Products.

	All live ids come from the Creator Dashboard. MonetizationService refuses to
	prompt or grant anything whose id is 0, so a new entry stays inert until it
	is created there.

	Prices: the real price is whatever is set on Roblox. SuggestedPriceRobux is
	documentation only and is never used to grant or charge anything. The UI
	must read the live price via MarketplaceService:GetProductInfo.
]]

local Types = require(script.Parent.Parent.Types)

type GamePassData = Types.GamePassData
type DeveloperProductData = Types.DeveloperProductData

local GamePasses: { [string]: GamePassData } = {
	--[[
		Power ladder. The first step is priced to be an impulse buy, and owning
		it unlocks the next one — the pattern every big clicker uses. Only the
		highest step owned counts (they do not multiply with each other).
		The real price lives on Roblox; SuggestedPriceRobux is documentation.
	]]
	DoublePower = {
		Key = "DoublePower",
		GamePassId = 1992002263,
		DisplayName = "2x Power",
		SuggestedPriceRobux = 5,
		Benefits = { PowerMultiplier = 2 },
		Ladder = "Power",
		LadderStep = 1,
	},
	QuadPower = {
		Key = "QuadPower",
		GamePassId = 0, -- TODO_PRODUCT_ID: create on the site, paste the id here
		DisplayName = "4x Power",
		SuggestedPriceRobux = 19,
		Benefits = { PowerMultiplier = 4 },
		Ladder = "Power",
		LadderStep = 2,
	},
	OctaPower = {
		Key = "OctaPower",
		GamePassId = 0, -- TODO_PRODUCT_ID
		DisplayName = "8x Power",
		SuggestedPriceRobux = 49,
		Benefits = { PowerMultiplier = 8 },
		Ladder = "Power",
		LadderStep = 3,
	},
	AutoClick = {
		Key = "AutoClick",
		GamePassId = 1989476485,
		DisplayName = "Auto Click",
		SuggestedPriceRobux = 149,
		Benefits = { AutoClick = true },
	},
	ExtraPets = {
		Key = "ExtraPets",
		GamePassId = 1990298464,
		DisplayName = "+3 Pets Equipped",
		SuggestedPriceRobux = 249,
		Benefits = { ExtraEquipSlots = 3 },
	},
	DoubleLuck = {
		Key = "DoubleLuck",
		GamePassId = 1990250471,
		DisplayName = "2x Luck",
		SuggestedPriceRobux = 299,
		Benefits = { LuckMultiplier = 2 },
	},
	VIP = {
		Key = "VIP",
		GamePassId = 1989098468,
		DisplayName = "VIP",
		SuggestedPriceRobux = 399,
		Benefits = { Vip = true, PowerMultiplier = 1.25 },
	},
}

local DeveloperProducts: { [string]: DeveloperProductData } = {
	PowerBoost2x = {
		Key = "PowerBoost2x",
		ProductId = 3714205163,
		DisplayName = "2x Power Boost (15 min)",
		SuggestedPriceRobux = 29,
		Rewards = { { Type = "Boost", BoostId = "Power2x", Amount = 1 } },
		OneTimeOffer = false,
	},
	PowerBoost5x = {
		Key = "PowerBoost5x",
		ProductId = 3714205211,
		DisplayName = "5x Power Boost (10 min)",
		SuggestedPriceRobux = 79,
		Rewards = { { Type = "Boost", BoostId = "Power5x", Amount = 1 } },
		OneTimeOffer = false,
	},
	LuckBoost = {
		Key = "LuckBoost",
		ProductId = 3714205255,
		DisplayName = "2x Luck Boost (15 min)",
		SuggestedPriceRobux = 39,
		Rewards = { { Type = "Boost", BoostId = "Luck2x", Amount = 1 } },
		OneTimeOffer = false,
	},
	GemsSmall = {
		Key = "GemsSmall",
		ProductId = 3714205326,
		DisplayName = "100 Gems",
		SuggestedPriceRobux = 49,
		Rewards = { { Type = "Currency", Currency = "Gems", Amount = 100 } },
		OneTimeOffer = false,
	},
	GemsMedium = {
		Key = "GemsMedium",
		ProductId = 3714205373,
		DisplayName = "550 Gems",
		SuggestedPriceRobux = 199,
		Rewards = { { Type = "Currency", Currency = "Gems", Amount = 550 } },
		OneTimeOffer = false,
	},
	GemsLarge = {
		Key = "GemsLarge",
		ProductId = 3714205416,
		DisplayName = "1,200 Gems",
		SuggestedPriceRobux = 399,
		Rewards = { { Type = "Currency", Currency = "Gems", Amount = 1200 } },
		OneTimeOffer = false,
	},
	InstantOverdrive = {
		Key = "InstantOverdrive",
		ProductId = 3714205289,
		DisplayName = "Instant Overdrive",
		SuggestedPriceRobux = 25,
		Rewards = {}, -- handled specially by MonetizationService -> OverdriveService (Phase 6)
		OneTimeOffer = false,
	},
	StarterPack = {
		Key = "StarterPack",
		ProductId = 3714205453,
		DisplayName = "Starter Pack",
		SuggestedPriceRobux = 99,
		Rewards = {
			{ Type = "Pet", PetId = "StarterDragonling", Variant = "Normal" },
			{ Type = "Currency", Currency = "Gems", Amount = 250 },
			{ Type = "Boost", BoostId = "Power2x", Amount = 2 },
			{ Type = "Boost", BoostId = "Luck2x", Amount = 1 },
		},
		OneTimeOffer = true,
	},
}

return {
	GamePasses = GamePasses,
	DeveloperProducts = DeveloperProducts,
	-- Max processed receipts remembered per player (FIFO). Roblox retries a
	-- receipt until granted, so the ledger only needs recent history.
	ReceiptLedgerSize = 200,
}
