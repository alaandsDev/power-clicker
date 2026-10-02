--!strict
--[[
	ComboConfig
	Combo = consecutive valid clicks. Multiplier = 1 + Stacks * MultiplierPerStack,
	capped at MaxMultiplier. With the values below the cap (2x) is reached at 50 stacks
	(~8s of active clicking at 6 CPS).
]]

local ComboConfig = {
	MaxStacks = 50,
	MultiplierPerStack = 0.02,
	MaxMultiplier = 2,

	-- Seconds without a valid click before stacks start decaying.
	TimeoutSeconds = 1.25,
	-- Stacks lost per second after the timeout (0 = drop to zero instantly).
	DecayStacksPerSecond = 15,

	-- Visual tiers (client feedback only; no gameplay effect).
	VisualTiers = { 10, 25, 50 },
}

return ComboConfig
