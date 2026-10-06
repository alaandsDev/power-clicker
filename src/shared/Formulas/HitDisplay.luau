--!strict
--[[
	HitDisplay
	A matemática REAL do golpe, só para MOSTRAR (nada aqui muda a economia).

	No servidor (ClickService.processClick) um clique válido faz duas coisas
	com o MESMO número:
	  1. soma Power no saldo:  ganho = PowerPerClick × Combo  (CurrencyService)
	  2. tira esse mesmo ganho da fileira à frente (WallService.OnClick),
	     do alvo do treino e do chefe.
	  PowerPerClick = PowerService (base + planos) × camadas (Melhoria,
	  Renascimento, Mundo, Permanente, Pets, Passes, Boosts, Overdrive...).
	  Combo = EconomyFormulas.ComboMultiplier(stacks): 1x … 2x (só clique
	  manual; o Auto Click não constrói combo).

	Ou seja: ⚔ DANO por golpe = ⚡ Poder ganho por clique. O ⚡ PODER do topo
	é o SALDO acumulado (gasto nas melhorias de Poder) — não é o dano.
]]

local Shared = script.Parent.Parent
local EconomyFormulas = require(Shared.Formulas.EconomyFormulas)
local Types = require(Shared.Types)

export type Info = { PerClick: number, Base: number?, Layers: { [string]: number }? }

local HitDisplay = {}

-- Dano de UM golpe agora (PerClick já tem todas as camadas; falta o combo).
function HitDisplay.Damage(perClick: number, comboStacks: number?): number
	if type(perClick) ~= "number" or perClick ~= perClick or perClick <= 0 then
		return 0
	end
	return perClick * EconomyFormulas.ComboMultiplier(comboStacks or 0)
end

-- Quantos golpes para tirar `hp` com `damage` por golpe (math.huge sem dano).
function HitDisplay.HitsFor(hp: number, damage: number): number
	if damage <= 0 then
		return math.huge
	end
	return math.max(math.ceil(hp / damage), if hp > 0 then 1 else 0)
end

--[[
	Prévia: o Poder por clique (= dano por golpe, sem combo) DEPOIS de comprar
	`levels` níveis desta melhoria, pela mesma fórmula do PowerService. nil
	para melhorias que não mexem no golpe (pets, sorte, depósito).
]]
function HitDisplay.PreviewUpgrade(info: Info, upgrade: Types.UpgradeData, levels: number, permanent: boolean): number?
	local perClick = info.PerClick
	if levels <= 0 or type(perClick) ~= "number" or perClick <= 0 then
		return nil
	end
	local added = upgrade.EffectPerLevel * levels
	if upgrade.EffectType == "ClickPowerFlat" then
		local base = info.Base or 0
		return if base > 0 then perClick * (base + added) / base else nil
	elseif upgrade.EffectType == "PowerMultiplier" then
		local layers = info.Layers or {}
		local layer = (if permanent then layers.Permanent else layers.Upgrade) or 1
		return if layer > 0 then perClick * (layer + added) / layer else nil
	end
	return nil
end

return HitDisplay
