--!strict
--[[
	EggOdds
	Pure drop-chance math. Shared so the client can DISPLAY exact chances;
	the actual roll happens only on the server (EggLogic + server Random).

	Luck multiplies the weight of drops whose rarity has AffectedByLuck, so
	rarer pets become more likely while the total stays normalized.
]]

local Shared = script.Parent.Parent
local Types = require(Shared.Types)
local PetConfig = require(Shared.Config.PetConfig)
local EggConfig = require(Shared.Config.EggConfig)

type EggData = Types.EggData

export type Drop = { PetId: string, Weight: number }

local EggOdds = {}

function EggOdds.ClampLuck(luck: number): number
	if luck ~= luck or luck < 1 then
		return 1
	end
	return math.min(luck, EggConfig.MaxLuckMultiplier)
end

-- Effective weights after luck (same order as egg.Drops). Unknown pets get weight 0.
function EggOdds.Weights(egg: EggData, luck: number): { Drop }
	local effectiveLuck = EggOdds.ClampLuck(luck)
	local result: { Drop } = {}
	for _, drop in egg.Drops do
		local pet = PetConfig.Pets[drop.PetId]
		local weight = 0
		if pet then
			local rarity = PetConfig.Rarities[pet.Rarity]
			weight = drop.Weight * (if rarity and rarity.AffectedByLuck then effectiveLuck else 1)
		end
		table.insert(result, { PetId = drop.PetId, Weight = weight })
	end
	return result
end

-- Probability (0..1) per pet id.
function EggOdds.Chances(egg: EggData, luck: number): { [string]: number }
	local weights = EggOdds.Weights(egg, luck)
	local total = 0
	for _, drop in weights do
		total += drop.Weight
	end
	local chances: { [string]: number } = {}
	for _, drop in weights do
		chances[drop.PetId] = if total > 0 then drop.Weight / total else 0
	end
	return chances
end

-- Picks a pet id from weights given a uniform roll in [0, 1). nil if no valid drops.
function EggOdds.Pick(weights: { Drop }, roll: number): string?
	local total = 0
	for _, drop in weights do
		total += drop.Weight
	end
	if total <= 0 then
		return nil
	end
	local target = math.clamp(roll, 0, 0.999999999) * total
	local cumulative = 0
	local last: string? = nil
	for _, drop in weights do
		if drop.Weight > 0 then
			cumulative += drop.Weight
			last = drop.PetId
			if target < cumulative then
				return drop.PetId
			end
		end
	end
	return last -- floating point safety
end

return EggOdds
