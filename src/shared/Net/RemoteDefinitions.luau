--!strict
--[[
	RemoteDefinitions
	Single source of truth for every RemoteEvent / RemoteFunction.

	The server creates the instances from this table at boot (NetService);
	nothing else may create remotes. Every ClientToServer remote MUST declare a
	RateLimit, and the server MUST register a validated handler for it
	(NetService warns at Start for any ClientToServer remote without one).

	Remotes are added phase by phase together with the system that owns them.
]]

local Types = require(script.Parent.Parent.Types)
local EconomyConfig = require(script.Parent.Parent.Config.EconomyConfig)

type RemoteSpec = Types.RemoteSpec

local Remotes: { [string]: RemoteSpec } = {
	-- ── Client → Server ──────────────────────────────────────────────────
	-- Client says its listeners are connected and it wants the initial snapshot.
	ClientReady = {
		Kind = "Event",
		Direction = "ClientToServer",
		RateLimit = { Capacity = 2, RefillPerSecond = 0.1 },
		RequiresData = false,
	},
	-- "I clicked." No arguments: the server computes everything.
	Click = {
		Kind = "Event",
		Direction = "ClientToServer",
		RateLimit = {
			Capacity = EconomyConfig.Click.ClickBurst,
			RefillPerSecond = EconomyConfig.Click.MaxClicksPerSecond,
		},
	},
	-- (upgradeId: string, amount: number) → RemoteResponse { Data = { Level, Cost, Bought } }
	-- amount: how many levels (0 = as many as the player can afford).
	BuyUpgrade = {
		Kind = "Function",
		Direction = "ClientToServer",
		RateLimit = { Capacity = 8, RefillPerSecond = 4 },
	},
	-- () → RemoteResponse { Data = { Rebirths, Gems } }
	Rebirth = {
		Kind = "Function",
		Direction = "ClientToServer",
		RateLimit = { Capacity = 2, RefillPerSecond = 0.5 },
	},
	-- (eggId: string) → RemoteResponse { Data = HatchResult }. RNG is server-side.
	HatchEgg = {
		Kind = "Function",
		Direction = "ClientToServer",
		RateLimit = { Capacity = 3, RefillPerSecond = 2 },
	},
	-- (action: "Equip"|"Unequip"|"EquipBest"|"Delete"|"Lock"|"Unlock", uid: string?)
	-- → RemoteResponse. uids are server-generated; only owned uids are accepted.
	PetAction = {
		Kind = "Function",
		Direction = "ClientToServer",
		RateLimit = { Capacity = 10, RefillPerSecond = 5 },
	},
	-- (worldId: string) → RemoteResponse. Requirements and cost are server-side.
	UnlockWorld = {
		Kind = "Function",
		Direction = "ClientToServer",
		RateLimit = { Capacity = 3, RefillPerSecond = 1 },
	},
	-- (worldId: string) → RemoteResponse. The SERVER teleports the character.
	TravelWorld = {
		Kind = "Function",
		Direction = "ClientToServer",
		RateLimit = { Capacity = 3, RefillPerSecond = 0.5 },
	},
	-- () → RemoteResponse { Data = { Day, Streak, Summary } }. Server clock only.
	ClaimDaily = {
		Kind = "Function",
		Direction = "ClientToServer",
		RateLimit = { Capacity = 3, RefillPerSecond = 0.5 },
	},
	-- (questId: string) → RemoteResponse
	ClaimQuest = {
		Kind = "Function",
		Direction = "ClientToServer",
		RateLimit = { Capacity = 6, RefillPerSecond = 2 },
	},
	-- (code: string) → RemoteResponse. Tight limit: brute-force protection.
	RedeemCode = {
		Kind = "Function",
		Direction = "ClientToServer",
		RateLimit = { Capacity = 3, RefillPerSecond = 0.2 },
	},
	-- (productOrPassKey: string) → RemoteResponse. The SERVER validates and
	-- opens the Roblox purchase prompt; grants happen only via ProcessReceipt.
	PromptPurchase = {
		Kind = "Function",
		Direction = "ClientToServer",
		RateLimit = { Capacity = 4, RefillPerSecond = 1 },
	},
	-- (enabled: boolean) → RemoteResponse. Requires the Auto Click pass.
	SetAutoClick = {
		Kind = "Function",
		Direction = "ClientToServer",
		RateLimit = { Capacity = 4, RefillPerSecond = 1 },
	},
	-- (key: string, value: boolean | number) → RemoteResponse. Validated per key.
	UpdateSettings = {
		Kind = "Function",
		Direction = "ClientToServer",
		RateLimit = { Capacity = 6, RefillPerSecond = 2 },
	},
	-- (skinId: string) → RemoteResponse. Equips a cosmetic aura already
	-- unlocked; the unlocks themselves are granted by the server.
	AuraSkinAction = {
		Kind = "Function",
		Direction = "ClientToServer",
		RateLimit = { Capacity = 6, RefillPerSecond = 2 },
	},
	-- (swordId: string) → RemoteResponse. Equips a cosmetic blade the player
	-- already unlocked; unlocks themselves are granted by the server.
	SwordAction = {
		Kind = "Function",
		Direction = "ClientToServer",
		RateLimit = { Capacity = 6, RefillPerSecond = 2 },
	},
	-- (action: "Buy"|"Equip", auraId: string) → RemoteResponse. The server
	-- checks the price, the rebirth requirement and the ownership.
	AuraAction = {
		Kind = "Function",
		Direction = "ClientToServer",
		RateLimit = { Capacity = 6, RefillPerSecond = 2 },
	},
	-- (action: "Equip"|"Unequip"|"UnequipAll", runeId: string | slot: number)
	-- → RemoteResponse { Data = { Equipped } }. Runes only come from bosses.
	RuneAction = {
		Kind = "Function",
		Direction = "ClientToServer",
		RateLimit = { Capacity = 10, RefillPerSecond = 4 },
	},
	-- (command: string, amount: number?) → RemoteResponse. Server rejects
	-- unless AdminConfig allows the caller (see DebugService).
	DebugCommand = {
		Kind = "Function",
		Direction = "ClientToServer",
		RateLimit = { Capacity = 10, RefillPerSecond = 3 },
	},

	-- ── Server → Client ──────────────────────────────────────────────────
	-- Full client-safe view of the player's data.
	DataSnapshot = { Kind = "Event", Direction = "ServerToClient" },
	-- (topLevelKey, value) for batched changes.
	DataChanged = { Kind = "Event", Direction = "ServerToClient" },
	-- (kind: string, payload: table) generic notifications / toasts.
	Notify = { Kind = "Event", Direction = "ServerToClient" },
	-- ({ [stageId]: { Hp = { number }, Open = boolean } }) the barriers of the
	-- Power Path AS THEY ARE FOR THIS PLAYER (each player has their own; the
	-- shared parts in the Workspace never change on the server).
	WallState = { Kind = "Event", Direction = "ServerToClient" },
	-- (manualGain, manualClicks, comboStacks, autoGain) batched per flush.
	ClickFeedback = { Kind = "Event", Direction = "ServerToClient" },
	-- ({ PerClick, Base, Total, Layers }) when the player's multipliers change.
	PowerInfo = { Kind = "Event", Direction = "ServerToClient" },
	-- (active: boolean, remainingSeconds: number, cooldownSeconds: number)
	OverdriveState = { Kind = "Event", Direction = "ServerToClient" },
	-- ({ [boardId]: { Entries = {Rank, UserId, Name, Value}, Local } })
	Leaderboards = { Kind = "Event", Direction = "ServerToClient" },
	-- (level, track) claim a season pass level. Rate limited like any action.
	SeasonAction = { Kind = "Function", Direction = "ClientToServer", RateLimit = { Capacity = 6, RefillPerSecond = 3 } },
	-- ({ ZoneId: string?, Multiplier: number }) when the player enters/leaves a zone.
	ZoneChanged = { Kind = "Event", Direction = "ServerToClient" },
	-- ({ Active, Hp, MaxHp, WorldId, SecondsLeft }) world boss state.
	BossState = { Kind = "Event", Direction = "ServerToClient" },
	-- ({ EventId: string?, Multiplier: number, SecondsLeft: number }) happy hour.
	EventState = { Kind = "Event", Direction = "ServerToClient" },
	-- (debugAllowed: boolean) sent once when the client is ready.
	DebugAccess = { Kind = "Event", Direction = "ServerToClient" },
}

return {
	FolderName = "Remotes",
	Remotes = Remotes,
}
