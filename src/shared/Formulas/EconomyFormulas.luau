--!strict
--[[
	EconomyFormulas
	Pure, deterministic formulas shared by server (authoritative) and client
	(display/prediction ONLY — the client never decides outcomes).

	Every formula lives here once. Services must call these instead of
	re-implementing math, so balancing only ever touches config.
]]

local Config = script.Parent.Parent.Config
local GameConfig = require(Config.GameConfig)
local RebirthConfig = require(Config.RebirthConfig)
local ComboConfig = require(Config.ComboConfig)
local Types = require(script.Parent.Parent.Types)

type UpgradeData = Types.UpgradeData

local MAX_VALUE = GameConfig.Numbers.MaxValue

local EconomyFormulas = {}

-- Clamps to [0, MaxValue] and turns NaN into 0. Use on every stored amount.
function EconomyFormulas.Sanitize(value: number): number
	if value ~= value or value < 0 then
		return 0
	end
	return math.min(value, MAX_VALUE)
end

-- Cost to go from `level` to `level + 1`. math.huge when maxed or invalid.
function EconomyFormulas.UpgradeCost(upgrade: UpgradeData, level: number): number
	if level < 0 or level % 1 ~= 0 or level >= upgrade.MaxLevel then
		return math.huge
	end
	return math.ceil(math.min(upgrade.BaseCost * upgrade.CostGrowth ^ level, MAX_VALUE))
end

-- Total effect of an upgrade at `level` (e.g. +N flat power, +X multiplier).
function EconomyFormulas.UpgradeEffect(upgrade: UpgradeData, level: number): number
	local clamped = math.clamp(level, 0, upgrade.MaxLevel)
	return upgrade.EffectPerLevel * clamped
end

--[[
	Power required for the next rebirth, given rebirths already done.
	`anchor` = Stats.RebirthAnchor (renascimentos do save na migração do C2-E;
	0/nil = save novo). Ver RebirthConfig.Anchor.
]]
function EconomyFormulas.RebirthCost(rebirths: number, anchor: number?): number
	if rebirths < 0 or rebirths >= RebirthConfig.MaxRebirths then
		return math.huge
	end
	local cost = RebirthConfig.BaseCost * RebirthConfig.CostGrowth ^ rebirths
	local r0 = if type(anchor) == "number" and anchor == anchor then math.floor(math.max(anchor, 0)) else 0
	if r0 > 0 then
		local rule = RebirthConfig.Anchor
		if rebirths < r0 then
			-- Renascimentos já feitos antes da migração: curva antiga.
			cost = rule.LegacyBaseCost * rule.LegacyCostGrowth ^ rebirths
		else
			local legacy = rule.LegacyBaseCost * rule.LegacyCostGrowth ^ r0
			cost = math.min(cost, legacy * (rule.GrowthFactor * RebirthConfig.CostGrowth) ^ (rebirths - r0))
		end
	end
	return math.ceil(math.min(cost, MAX_VALUE))
end

--[[
	Leitura saneada do Stats (servidor e cliente usam a MESMA): renascimentos
	feitos, âncora do C2-E e o custo real do próximo. O RebirthLogic delega
	para cá, então a tela/selo do cliente nunca diverge do que o servidor cobra.
]]
local function wholeOrZero(value: any): number
	if type(value) ~= "number" or value ~= value or value < 0 then
		return 0
	end
	return math.floor(value)
end

function EconomyFormulas.RebirthsOf(stats: any): number
	return wholeOrZero(if type(stats) == "table" then stats.Rebirths else nil)
end

function EconomyFormulas.RebirthAnchorOf(stats: any): number
	return wholeOrZero(if type(stats) == "table" then stats.RebirthAnchor else nil)
end

function EconomyFormulas.RebirthCostFor(stats: any): number
	return EconomyFormulas.RebirthCost(EconomyFormulas.RebirthsOf(stats), EconomyFormulas.RebirthAnchorOf(stats))
end

-- Gems awarded for performing the next rebirth, given rebirths already done.
function EconomyFormulas.RebirthGems(rebirths: number): number
	if rebirths < 0 then
		return 0
	end
	return math.floor(RebirthConfig.BaseGems + RebirthConfig.GemsPerRebirth * rebirths)
end

-- Permanent power multiplier from total rebirths.
--[[
	Multiplicador do renascimento.

	Fase H: era linear (1 + 0,75 × R). O problema apareceu na simulação de 12 h:
	as barreiras da torre crescem ~8× por estágio, e um multiplicador linear
	fica para trás — todo mundo travava no estágio 6, com dano 10% abaixo do
	necessário para o 7, e nada no jogo o faria subir.

	Agora é composto: cada renascimento multiplica por (1 + MultiplierPerRebirth),
	que é como a progressão de longo prazo acompanha uma torre exponencial.
	O teto é o MaxValue do jogo, para não existir número infinito na economia.
]]
function EconomyFormulas.RebirthMultiplier(rebirths: number): number
	local count = math.max(0, math.floor(rebirths))
	local multiplier = (1 + RebirthConfig.MultiplierPerRebirth) ^ count
	return math.min(multiplier, MAX_VALUE)
end

function EconomyFormulas.ComboMultiplier(stacks: number): number
	local clamped = math.clamp(stacks, 0, ComboConfig.MaxStacks)
	return math.min(1 + clamped * ComboConfig.MultiplierPerStack, ComboConfig.MaxMultiplier)
end

return EconomyFormulas
