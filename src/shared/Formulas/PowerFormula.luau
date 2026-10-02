--!strict
--[[
	PowerFormula
	THE formula for power per click. Nothing else multiplies power.

		PowerPerClick = Base × Π(layer multipliers)

	Layers are listed in EconomyConfig.MultiplierLayers. Unknown layer names
	and invalid values (NaN, inf, <= 0) are ignored (treated as 1) and
	reported, so a bad provider can never zero out or explode the economy.

	Server: PowerService builds the inputs from player data (authoritative).
	Client: may call it with replicated inputs for display only.
]]

local Shared = script.Parent.Parent
local EconomyConfig = require(Shared.Config.EconomyConfig)
local GameConfig = require(Shared.Config.GameConfig)

local MAX_VALUE = GameConfig.Numbers.MaxValue

local KNOWN_LAYERS: { [string]: boolean } = {}
for _, layer in EconomyConfig.MultiplierLayers do
	KNOWN_LAYERS[layer] = true
end

local PowerFormula = {}

function PowerFormula.IsKnownLayer(layer: string): boolean
	return KNOWN_LAYERS[layer] == true
end

local function isValidMultiplier(value: any): boolean
	return type(value) == "number" and value == value and value > 0 and value < math.huge
end

--[[
	Returns (powerPerClick, totalMultiplier, problems).
	`problems` lists ignored layers (empty when everything is valid).
]]
function PowerFormula.Compute(base: number, layers: { [string]: number }): (number, number, { string })
	local problems: { string } = {}
	local total = 1
	for layer, value in layers do
		if not KNOWN_LAYERS[layer] then
			table.insert(problems, "unknown layer " .. tostring(layer))
		elseif not isValidMultiplier(value) then
			table.insert(problems, "invalid " .. layer .. "=" .. tostring(value))
		else
			total *= value
		end
	end

	local safeBase = if isValidMultiplier(base) then base else 0
	if safeBase ~= base then
		table.insert(problems, "invalid base " .. tostring(base))
	end

	total = math.min(total, MAX_VALUE)
	local power = math.min(safeBase * total, MAX_VALUE)
	return power, total, problems
end

return PowerFormula
