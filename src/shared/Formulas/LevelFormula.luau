--!strict
--[[
	LevelFormula
	Level from the Power a player is holding, for the bar under the click
	button. Pure and derived — nothing is stored.

	Each level asks `Growth` times what the last one did:
		custo(n)     = BaseStep × Growth^n
		acumulado(n) = BaseStep × (Growth^n − 1) / (Growth − 1)

	The level is the largest n whose accumulated cost fits in the player's
	Power, which inverts to a logarithm — O(1), and the number stays readable
	at any Power (a loop would also spin forever once Power is in the
	trillions).
]]

local Shared = script.Parent.Parent
local LevelConfig = require(Shared.Config.LevelConfig)

local LevelFormula = {}

-- Power needed to go from `level` to the next one.
function LevelFormula.StepCost(level: number): number
	return LevelConfig.BaseStep * LevelConfig.Growth ^ math.max(level, 0)
end

-- Power needed to have reached `level` at all.
function LevelFormula.TotalFor(level: number): number
	local n = math.max(math.floor(level), 0)
	return LevelConfig.BaseStep * (LevelConfig.Growth ^ n - 1) / (LevelConfig.Growth - 1)
end

--[[
	Returns (level, intoLevel, stepCost) for a Power balance:
		level     — the level reached
		intoLevel — Power already inside the current level
		stepCost  — Power the current level asks for
	Junk input (NaN, negative) reads as level 0.
]]
function LevelFormula.LevelOf(power: number): (number, number, number)
	if type(power) ~= "number" or power ~= power or power <= 0 then
		return 0, 0, LevelFormula.StepCost(0)
	end
	-- acumulado(n) <= power  ⇒  n <= log(1 + power × (G−1) / BaseStep) / log(G)
	local growth = LevelConfig.Growth
	local level: number
	if growth <= 1 then
		level = math.floor(power / math.max(LevelConfig.BaseStep, 1))
	else
		level = math.floor(math.log(1 + power * (growth - 1) / LevelConfig.BaseStep) / math.log(growth))
	end
	--[[
		A logarithm of floats can land a hair either side of a level boundary
		(log(1.35)/log(1.35) is not always exactly 1). Nudge by one in each
		direction against the exact cost, so the bar flips over at the price the
		player was shown and never one Power early or late.
	]]
	if LevelFormula.TotalFor(level + 1) <= power then
		level += 1
	elseif level > 0 and LevelFormula.TotalFor(level) > power then
		level -= 1
	end
	level = math.clamp(level, 0, LevelConfig.MaxLevel)
	local into = power - LevelFormula.TotalFor(level)
	local cost = LevelFormula.StepCost(level)
	-- Floating point can leave `into` a hair outside its level; clamp so the
	-- bar never shows 1.0000001 or a negative sliver.
	return level, math.clamp(into, 0, cost), cost
end

return LevelFormula
