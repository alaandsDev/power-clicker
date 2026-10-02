--!strict
--[[
	RebirthConfig
	Cost(r)       = BaseCost * CostGrowth ^ r                (r = rebirths done so far)
	Gems(r)       = floor(BaseGems + GemsPerRebirth * r)      (reward for rebirth r+1)
	Multiplier(R) = (1 + MultiplierPerRebirth) ^ R            (R = total rebirths)

	Phase 8 audit (full simulation incl. pets, gem upgrades, worlds, passes):
	active player (6 CPS) ~8.5 min to 1st rebirth, ~40 min to 5 rebirths/City,
	~7 h to Volcano; casual ~25 min / ~2 h. See ECONOMY.md.
]]

local RebirthConfig = {
	Currency = "Power",
	BaseCost = 200_000,
	--[[
		Fase H (correção de P2): era 2.3, com multiplicador de +0,5 por
		renascimento. A simulação mostrava 6 a 8 renascimentos em 2–4 h, um a
		cada ~15 min: virou rotina, não decisão.
		Agora o custo cresce bem mais rápido E cada renascimento vale mais
		(0,5 → 0,75), então são menos vezes e cada uma pesa. Testado em 2,7,
		3,2 e 3,8: 3,2 é o que dá ~1 renascimento a cada 40 min para o jogador
		ativo sem travar o longo prazo.
	]]
	CostGrowth = 3.2,

	--[[
		Fase H: era 15 + 8r. Com a simulação de 12 h, o jogador terminava com
		~40 gemas no bolso e o multiplicador de pets congelado em +60% — os ovos
		bons (150, 400, 2.500 gemas) ficavam fora de alcance e o sistema de pets
		sumia do meio do jogo. Renascer agora paga o suficiente para os ovos
		fazerem parte do ciclo.
	]]
	BaseGems = 30,
	GemsPerRebirth = 20,

	--[[
		Agora COMPOSTO: cada renascimento multiplica por 1,75 (era soma linear
		de +0,5). Ver EconomyFormulas.RebirthMultiplier.
	]]
	MultiplierPerRebirth = 0.75,

	-- What a rebirth resets (everything else is kept).
	Resets = {
		Power = true,
		TemporaryUpgrades = true,
		OverdriveCharge = false,
	},

	MaxRebirths = 1000,
}

return RebirthConfig
