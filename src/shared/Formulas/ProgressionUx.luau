--!strict
--[[
	ProgressionUx
	Responde duas perguntas do jogador SEM mudar a economia (só leitura):
	  1. "Já está na hora de eu renascer?"   → ProgressionUx.Rebirth
	  2. "Já estou forte para o Colosso?"     → ProgressionUx.ColossusState

	Tudo vem das fórmulas que o servidor usa:
	  custo do próximo renascimento = EconomyFormulas.RebirthCostFor(Stats)
	    (mesma função do RebirthLogic.GetCost, com a âncora do C2-E);
	  multiplicadores = EconomyFormulas.RebirthMultiplier (1,75^R);
	  golpes = HitDisplay.HitsFor(HP, ⚔ dano do golpe) — o mesmo ⚔ da HUD.

	O estado do Colosso é do JOGADOR (o dano é dele): cada cliente calcula o
	próprio; não existe propriedade global no mapa.
]]

local Shared = script.Parent.Parent
local EconomyFormulas = require(Shared.Formulas.EconomyFormulas)
local HitDisplay = require(Shared.Formulas.HitDisplay)
local RebirthConfig = require(Shared.Config.RebirthConfig)

local ProgressionUx = {}

export type RebirthView = {
	Rebirths: number,
	Next: number,
	Cost: number,
	Power: number,
	Ready: boolean,
	Missing: number,
	Fraction: number,
	MultiplierNow: number,
	MultiplierNext: number,
	Gems: number,
	Maxed: boolean,
}

function ProgressionUx.Rebirth(stats: any, power: number?): RebirthView
	local rebirths = EconomyFormulas.RebirthsOf(stats)
	local cost = EconomyFormulas.RebirthCostFor(stats)
	local balance = if type(power) == "number" and power == power then math.max(power, 0) else 0
	local maxed = rebirths >= RebirthConfig.MaxRebirths or cost == math.huge
	local ready = not maxed and balance >= cost
	return {
		Rebirths = rebirths,
		Next = rebirths + 1,
		Cost = cost,
		Power = balance,
		Ready = ready,
		Missing = if ready or maxed then 0 else cost - balance,
		Fraction = if maxed then 1 else math.clamp(balance / cost, 0, 1),
		MultiplierNow = EconomyFormulas.RebirthMultiplier(rebirths),
		MultiplierNext = EconomyFormulas.RebirthMultiplier(rebirths + 1),
		Gems = EconomyFormulas.RebirthGems(rebirths),
		Maxed = maxed,
	}
end

--[[
	Aviso "RENASCER DISPONÍVEL": avisa quando passa a ficar disponível (e ao
	entrar já disponível), nunca repetido em sequência. Se o Power cair abaixo
	do custo, a oportunidade fecha; quando voltar, avisa de novo, mas só depois
	de `cooldown` segundos desde o último aviso (o selo no botão continua
	mostrando o estado nesse meio tempo).
]]
ProgressionUx.RebirthNoticeCooldown = 120

export type RebirthNotice = { Update: (self: RebirthNotice, ready: boolean, now: number) -> boolean, Ready: boolean, LastAt: number, Cooldown: number }

local RebirthNotice = {}
RebirthNotice.__index = RebirthNotice

function RebirthNotice.Update(self: RebirthNotice, ready: boolean, now: number): boolean
	local opened = ready and not self.Ready
	self.Ready = ready
	if opened and now - self.LastAt >= self.Cooldown then
		self.LastAt = now
		return true
	end
	return false
end

function ProgressionUx.NewRebirthNotice(cooldown: number?): RebirthNotice
	return setmetatable({ Ready = false, LastAt = -math.huge, Cooldown = cooldown or ProgressionUx.RebirthNoticeCooldown }, RebirthNotice) :: any
end

--[[
	Colosso: golpes por fileira = HP da fileira ÷ ⚔ dano atual.
	  > 300 golpes  🔴 DESAFIO EXTREMO
	  101–300       🟠 PREPARANDO
	  ≤ 100         🟢 PRONTO
	Coerente com o baseline C2-E: o simulador chama de "pronto" a luta de
	≤ 3 min e de "preparando" a de ≤ 10 min; no ritmo do perfil Ativo (9 cps ×
	75% segurando × 80% na barreira ≈ 5,4 golpes/s) e 10 fileiras isso dá
	≈ 97 e ≈ 324 golpes por fileira.

	O ESTADO usa o HP CHEIO da fileira (não muda de estado no fim de cada
	fileira); o "≈ N golpes" mostrado usa o HP que resta na fileira da frente.
]]
ProgressionUx.Colossus = {
	StageId = "Colossus",
	ExtremeAbove = 300,
	ReadyAtMost = 100,
}

export type ColossusLevel = "Extreme" | "Preparing" | "Ready"

local RANK: { [string]: number } = { Extreme = 1, Preparing = 2, Ready = 3 }

function ProgressionUx.ColossusState(rowHp: number, damage: number): (ColossusLevel, number)
	local hits = HitDisplay.HitsFor(math.max(rowHp, 0), damage)
	local rule = ProgressionUx.Colossus
	if hits > rule.ExtremeAbove then
		return "Extreme", hits
	elseif hits > rule.ReadyAtMost then
		return "Preparing", hits
	end
	return "Ready", hits
end

function ProgressionUx.Rank(level: ColossusLevel): number
	return RANK[level] or 0
end

-- Chaves de texto: longa (PC) ou curta (celular).
function ProgressionUx.ColossusLabelKey(level: ColossusLevel, compact: boolean?): string
	return "colossus.state." .. level .. (if compact then ".short" else "")
end

--[[
	Aviso de travessia do Colosso: só quando SOBE para um estado melhor que o
	melhor já avisado nesta sessão (o combo sobe e desce; isso não repete o
	aviso). A primeira leitura vira a linha de base, sem aviso. Leitura sem
	dano (math.huge) é ignorada (dados ainda não chegaram).
]]
export type ColossusNotice = { Update: (self: ColossusNotice, level: ColossusLevel, hits: number) -> ColossusLevel?, Best: number }

local ColossusNotice = {}
ColossusNotice.__index = ColossusNotice

function ColossusNotice.Update(self: ColossusNotice, level: ColossusLevel, hits: number): ColossusLevel?
	if hits == math.huge then
		return nil
	end
	local rank = ProgressionUx.Rank(level)
	if self.Best == 0 then
		self.Best = rank
		return nil
	end
	if rank > self.Best then
		self.Best = rank
		return level
	end
	return nil
end

function ProgressionUx.NewColossusNotice(): ColossusNotice
	return setmetatable({ Best = 0 }, ColossusNotice) :: any
end

return ProgressionUx
