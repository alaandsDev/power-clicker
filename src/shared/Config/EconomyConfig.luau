--!strict
--[[
	EconomyConfig
	Core click economy. See ECONOMY.md for the reasoning behind each value.
	All values are provisional until the Phase 8 economy audit.
]]

local EconomyConfig = {
	Click = {
		BasePowerPerClick = 1,

		-- Human hard limit is ~15 CPS; anything above this is dropped server-side.
		MaxClicksPerSecond = 20,
		-- Burst allowance for the click token bucket (absorbs network jitter).
		ClickBurst = 10,

		--[[
			Holding the button (or the screen) keeps clicking. Well under
			MaxClicksPerSecond so a held finger never eats the whole rate
			budget, and jittered on purpose: the pattern detector flags
			machine-regular timing, and an auto-fire we ship ourselves should
			not look like a macro.
		]]
		HoldClicksPerSecond = 9,
		HoldJitterSeconds = 0.02,
	},

	AutoClick = {
		-- Server-generated ticks per second for Auto Click owners.
		-- The client never reports click counts.
		TicksPerSecond = 4,
		-- Auto clicks do not build combo or overdrive (keeps active play valuable).
		BuildsCombo = false,
		BuildsOverdrive = false,
	},

	Currencies = {
		Power = { DisplayName = "Power", ResetsOnRebirth = true },
		Gems = { DisplayName = "Gems", ResetsOnRebirth = false },
		Wins = { DisplayName = "Wins", ResetsOnRebirth = false },
	},

	-- Multiplier layers, applied multiplicatively in this order by the
	-- server PowerCalculator (Phase 2). Listed here for documentation only.
	MultiplierLayers = {
		"Upgrade",
		"Rebirth",
		"Pet",
		"Aura",
		"Rune",
		"World",
		"Zone",
		"Event",
		"Social",
		"Permanent",
		"GamePass",
		"TemporaryBoost",
		"Combo",
		"Overdrive",
	},
}

return EconomyConfig
