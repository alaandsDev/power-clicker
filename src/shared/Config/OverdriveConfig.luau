--!strict
--[[
	OverdriveConfig
	The bar fills from valid manual clicks. When full, Overdrive activates for
	DurationSeconds with a power multiplier. ~67s of clicking at 6 CPS fills it.
]]

local OverdriveConfig = {
	ChargeMax = 400,
	ChargePerClick = 1,

	DurationSeconds = 20,
	Multiplier = 3,

	-- Charge cannot build while active; cooldown after it ends.
	CooldownSeconds = 10,

	-- Charge is persisted so leaving does not wipe progress.
	PersistCharge = true,
}

return OverdriveConfig
