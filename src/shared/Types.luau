--!strict
--[[
	Types
	Shared Luau type definitions. No runtime logic lives here.

	Rule: PlayerData is the persisted schema. Any change to its shape MUST bump
	ServerScriptService.Server.ServerConfig.DataConfig.DataVersion and add a migration in
	ServerScriptService.Server.Services.DataService.Migrations.
]]

-- ─── Identifiers ────────────────────────────────────────────────────────────

export type CurrencyId = "Power" | "Gems" | "Wins"
export type RarityId = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic"
export type VariantId = "Normal" | "Golden" | "Shiny" | "Rainbow"

-- ─── Persisted player data ──────────────────────────────────────────────────

-- A single owned pet. Only identifiers are stored, never models.
export type PetInstance = {
	PetId: string,
	Variant: VariantId,
	Locked: boolean,
	ObtainedAt: number, -- os.time() on the server
}

export type PetsData = {
	-- Keyed by a server-generated unique id (string). Never trust ids from the client.
	Inventory: { [string]: PetInstance },
	Equipped: { string }, -- list of inventory uids
	NextUid: number,
}

export type CurrenciesData = {
	Power: number,
	Gems: number,
	-- Wins come only from the win pads behind a broken wall. They never reset
	-- (not on rebirth, not on world change) — they are the long-term status.
	Wins: number,
}

export type StatsData = {
	TotalClicks: number,
	TotalPowerEarned: number,
	TotalGemsEarned: number,
	TotalWinsEarned: number,
	Rebirths: number,
	EggsOpened: number,
	PlaytimeSeconds: number,
	OverdrivesActivated: number,
	HighestCombo: number,
	LegendaryHatched: number,
	MythicHatched: number,
	FirstJoinTime: number,
	LastJoinTime: number,
	SessionCount: number,
}

export type WorldsData = {
	Unlocked: { [string]: boolean },
	Current: string,
}

export type BoostsData = {
	-- Remaining seconds per boost id. Boost time is consumed only while online.
	Remaining: { [string]: number },
}

export type OverdriveData = {
	Charge: number,
}

export type DailyRewardsData = {
	Streak: number, -- 0 = never claimed. Day index = ((Streak - 1) % CycleLength) + 1
	LastClaimTime: number, -- server os.time(); 0 = never
	TotalClaims: number,
}

export type QuestProgress = {
	Progress: number,
	Claimed: boolean,
}

export type QuestsData = {
	Progress: { [string]: QuestProgress },
	LastDailyReset: number, -- server os.time()
}

export type AchievementsData = {
	Unlocked: { [string]: number }, -- achievementId -> unlock time
}

export type CodesData = {
	Redeemed: { [string]: number }, -- normalized code -> redeem time
}

export type PurchasesData = {
	-- Idempotency ledger for ProcessReceipt. Server-only; never replicated.
	ProcessedReceipts: { [string]: number }, -- PurchaseId -> processed time
	ReceiptOrder: { string }, -- FIFO used to cap ledger size
	OneTimeOffersClaimed: { [string]: boolean }, -- e.g. StarterPack
	TotalRobuxSpent: number,
}

export type SettingsData = {
	MusicVolume: number,
	SfxVolume: number,
	ShowFloatingNumbers: boolean,
	ReducedEffects: boolean,
}

export type TutorialData = {
	Step: number,
	Completed: boolean,
}

export type SeasonData = {
	SeasonId: string, -- resets when SeasonConfig.Id changes
	Xp: number,
	-- Level numbers as STRING keys ("7"): DataStore tables must not have
	-- numeric keys mixed with an array shape.
	ClaimedFree: { [string]: boolean },
	ClaimedVip: { [string]: boolean },
}

-- Auras (AuraConfig): bought with Gems, one equipped at a time.
export type AurasData = {
	Owned: { [string]: boolean }, -- auraId -> true
	Equipped: string, -- auraId ("None" = no aura)
}

-- Cosmetic auras (AuraSkinConfig): particles around the character, earned by
-- progression. Separate from AurasData, which is the Gem purchase that gives
-- speed and Power — both can be active at once.
export type AuraSkinsData = {
	Owned: { [string]: boolean }, -- skinId -> true
	Equipped: string,
}

-- Swords (SwordConfig): cosmetic skins for the blade. They never touch damage
-- — the Cut does that — so nothing here feeds PowerFormula.
export type SwordsData = {
	Owned: { [string]: boolean }, -- swordId -> true
	Equipped: string,
}

-- The tower (WallConfig): which stages this player has already opened once.
-- Wins come from the pads every time; the gems come only on the first clear.
export type TowerData = {
	Cleared: { [string]: boolean }, -- stageId -> true
	Highest: number, -- highest stage Order ever opened (0 = none)
}

-- Cuts (CutConfig): the damage pads in front of the spawn. Owning is using:
-- the best one bought is the one that swings.
export type CutsData = {
	Owned: { [string]: boolean }, -- cutId -> true
}

-- Runes (RuneConfig): dropped by world bosses, equipped in a few slots.
export type RunesData = {
	Owned: { [string]: number }, -- runeId -> how many copies
	Equipped: { string }, -- runeIds, up to RuneConfig.Slots (repeats allowed)
}

export type PlayerData = {
	DataVersion: number,
	Currencies: CurrenciesData,
	Stats: StatsData,
	Upgrades: { [string]: number }, -- temporary upgrades (reset on rebirth): id -> level
	PermanentUpgrades: { [string]: number }, -- gem upgrades (kept): id -> level
	Pets: PetsData,
	Worlds: WorldsData,
	Boosts: BoostsData,
	Overdrive: OverdriveData,
	DailyRewards: DailyRewardsData,
	Quests: QuestsData,
	Achievements: AchievementsData,
	Codes: CodesData,
	Purchases: PurchasesData,
	Settings: SettingsData,
	Tutorial: TutorialData,
	Season: SeasonData,
	Auras: AurasData,
	Runes: RunesData,
	Cuts: CutsData,
	Tower: TowerData,
	Swords: SwordsData,
	AuraSkins: AuraSkinsData,
}

-- ─── Config definitions ─────────────────────────────────────────────────────

-- Reward granted by daily rewards, quests, achievements, codes and products.
export type RewardData = {
	Type: "Currency" | "Boost" | "Pet",
	Currency: CurrencyId?, -- Type == "Currency"
	Amount: number?, -- Currency amount / Boost stack count
	BoostId: string?, -- Type == "Boost"
	PetId: string?, -- Type == "Pet"
	Variant: VariantId?, -- Type == "Pet" (defaults to Normal)
}

export type RarityData = {
	Id: RarityId,
	DisplayName: string,
	Order: number, -- 1 = most common
	Color: Color3,
	AffectedByLuck: boolean,
	Announce: boolean, -- server-wide announcement when hatched
}

export type VariantData = {
	Id: VariantId,
	DisplayName: string,
	MultiplierScale: number, -- scales the pet's base bonus
	Enabled: boolean, -- architecture ready; only Normal enabled in MVP
}

export type PetData = {
	Id: string,
	DisplayName: string,
	Rarity: RarityId,
	Bonus: number, -- additive power bonus (0.1 = +10%)
	WorldId: string,
	EggId: string?, -- nil = not hatchable (exclusive / product pet)
	Icon: string, -- "rbxassetid://<id>" or "TODO_ASSET" (UI image: cards, hatch reveal)
	ModelName: string, -- model name inside ReplicatedStorage.Assets.Pets (TODO_ASSET until created)
	Tradeable: boolean,
}

export type EggDrop = {
	PetId: string,
	Weight: number, -- relative weight, not a percentage
}

export type EggData = {
	Id: string,
	DisplayName: string,
	WorldId: string,
	-- Estágio da torre que precisa ter caído uma vez (WallConfig). nil = livre.
	-- É assim que os ovos acompanham a progressão em vez de só o saldo.
	RequiredStage: string?,
	Currency: CurrencyId,
	Price: number,
	Drops: { EggDrop },
	Icon: string, -- "rbxassetid://<id>" or "TODO_ASSET" (UI image)
	ModelName: string,
	Enabled: boolean,
}

export type WorldRequirement = {
	Rebirths: number,
	Cost: number,
	Currency: CurrencyId,
}

export type WorldData = {
	Id: string,
	DisplayName: string,
	Order: number,
	Multiplier: number,
	Requirement: WorldRequirement,
	SpawnName: string, -- Workspace.Map.Spawns.<SpawnName>
	Ambient: string, -- AmbientConfig preset id (client lighting)
	Eggs: { string },
	Enabled: boolean,
}

-- Training zones (ZoneConfig): floating islands with breakable targets.
export type ZoneTarget = {
	Kind: string, -- visual style built by WorldBuilder (Dummy / Rock / Crystal / Orb)
	Count: number,
	Hp: number,
	Reward: number, -- Power granted to whoever lands the finishing hit
	RespawnSeconds: number,
}

export type ZoneRequirement = {
	Power: number, -- Stats.TotalPowerEarned
	Rebirths: number,
}

export type ZoneData = {
	Id: string,
	WorldId: string,
	Order: number,
	DisplayName: string,
	Offset: Vector3, -- from the world origin
	Radius: number,
	Multiplier: number, -- "Zone" layer of PowerFormula
	Requirement: ZoneRequirement,
	Color: Color3,
	Target: ZoneTarget,
}

-- Auras (AuraConfig): a Gem purchase that gives speed and Power.
export type AuraData = {
	Id: string,
	DisplayName: string,
	Order: number,
	Rarity: RarityId,
	Price: number, -- in AuraConfig.Currency; 0 = free (the default aura)
	RequiredWins: number, -- wins needed before it can be bought
	WalkSpeedBonus: number, -- studs/s added to AuraConfig.BaseWalkSpeed
	PowerMultiplier: number, -- "Aura" layer of PowerFormula
	Color: Color3,
	RingSize: number, -- diameter in studs (0 = no ring)
	LightRange: number,
	Outline: boolean,
}

-- Swords (SwordConfig): a cosmetic blade. Unlocked by progression, never sold.
export type SwordUnlock = {
	Kind: string, -- "Default" | "TowerStage" | "Rebirths" | "Wins"
	Stage: string?,
	Value: number?,
}

export type SwordData = {
	Id: string,
	Order: number,
	DisplayName: string,
	Rarity: RarityId,
	Unlock: SwordUnlock,
	BladeSize: Vector3,
	Color: Color3,
	Material: Enum.Material,
	Neon: boolean,
	TrailSeconds: number,
	TrailWidth: number,
	LightRange: number,
	ArcColor: Color3,
	ArcScale: number,
}

-- Cuts (CutConfig): a Power purchase that adds flat damage per click.
export type CutData = {
	Id: string,
	Order: number,
	DisplayName: string,
	Flat: number, -- added to the BASE of PowerFormula
	Price: number, -- in CutConfig.Currency; 0 = the starter cut
	RequiredWins: number,
	-- Look of the blade the player carries while this is their best cut.
	Color: Color3,
	TrailSeconds: number, -- 0 = no trail (the starter blade)
	LightRange: number, -- 0 = no glow
	Neon: boolean, -- the blade itself glows
}

-- Runes (RuneConfig): boss drops, equipped in slots.
export type RuneData = {
	Id: string,
	DisplayName: string,
	WorldId: string,
	Rarity: RarityId,
	Order: number,
	PowerMultiplier: number, -- multiplied into the "Rune" layer
	Weight: number, -- relative drop weight inside its world
}

export type UpgradeEffectType = "ClickPowerFlat" | "PowerMultiplier" | "EquipSlots" | "LuckMultiplier" | "InventorySlots"

export type UpgradeData = {
	Id: string,
	DisplayName: string,
	Description: string,
	Currency: CurrencyId,
	BaseCost: number,
	CostGrowth: number,
	MaxLevel: number,
	EffectType: UpgradeEffectType,
	EffectPerLevel: number,
	Order: number,
}

export type BoostData = {
	Id: string,
	DisplayName: string,
	Category: "Power" | "Luck",
	Multiplier: number,
	DurationSeconds: number, -- duration added per stack
	MaxStoredSeconds: number,
}

export type GamePassBenefits = {
	PowerMultiplier: number?,
	LuckMultiplier: number?,
	ExtraEquipSlots: number?,
	AutoClick: boolean?,
	Vip: boolean?,
}

export type GamePassData = {
	Key: string,
	-- Ladder passes (x2 -> x4 -> x8): same Ladder id, increasing LadderStep.
	-- Only the HIGHEST step a player owns counts, and a step can only be
	-- bought once the one before it is owned.
	Ladder: string?,
	LadderStep: number?,
	GamePassId: number, -- 0 = not created yet (TODO_PRODUCT_ID); never granted
	DisplayName: string,
	SuggestedPriceRobux: number, -- documentation only; the real price lives on Roblox
	Benefits: GamePassBenefits,
}

export type DeveloperProductData = {
	Key: string,
	ProductId: number, -- 0 = not created yet (TODO_PRODUCT_ID); never granted
	DisplayName: string,
	SuggestedPriceRobux: number, -- documentation only; the real price lives on Roblox
	Rewards: { RewardData },
	OneTimeOffer: boolean, -- e.g. Starter Pack
}

export type ProductData = GamePassData | DeveloperProductData

export type QuestType = "Clicks" | "Rebirths" | "EggsOpened" | "Playtime" | "Overdrives" | "WorldsUnlocked" | "PetsHatched"

export type QuestData = {
	Id: string,
	DisplayName: string,
	Type: QuestType,
	Target: number,
	Rewards: { RewardData },
	Repeat: "Once" | "Daily",
}

export type AchievementData = {
	Id: string,
	DisplayName: string,
	Description: string,
	Stat: string?, -- key in StatsData compared against Threshold
	Threshold: number?,
	WorldId: string?, -- alternative condition: world unlocked
	Rewards: { RewardData },
}

-- ─── Networking ─────────────────────────────────────────────────────────────

export type RateLimitSpec = {
	Capacity: number, -- burst size
	RefillPerSecond: number, -- sustained rate
}

export type RemoteSpec = {
	Kind: "Event" | "Function",
	Direction: "ClientToServer" | "ServerToClient",
	RateLimit: RateLimitSpec?, -- required for ClientToServer
	RequiresData: boolean?, -- ClientToServer: drop requests until the player's data is loaded (default true)
}

-- Standard response for RemoteFunctions. Never contains stack traces.
export type RemoteResponse = {
	Ok: boolean,
	Code: string?, -- machine readable error code when Ok == false
	Data: any,
}

return {}
