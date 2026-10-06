--[[
	econ_scenarios.luau — cenários de rebalanceamento da auditoria (PROPOSTAS).

	Nada disto está no jogo. São overrides que o econ_model aplica só na própria
	cópia das configs, para comparar com o ATUAL. Calibrados com o Monte Carlo
	(econ_audit.luau scenarios) contra as metas do perfil Ativo:
		estágio 7 ≈ 3–4 h ativas (D3) · 8 ≈ 6–7 h (D5) · 9 ≈ 10–14 h (D7–D10)
		mata o Colosso ≈ 35–50 h ativas (D25–D35)

	StageHp multiplica o HP POR FILEIRA; StageRows troca o número de fileiras.
]]

return {
	A = {
		Summary = "só HP: HP por fileira ×4 (4) … ×5.000.000 (10); rebirth, pets, boss e prêmios intactos.",
		Overrides = {
			StageHp = { [4] = 4, [5] = 40, [6] = 1e3, [7] = 1e5, [8] = 6e5, [9] = 1.5e6, [10] = 5e6 },
		},
	},
	B = {
		Summary = "HP + 2 alavancas: custo do renascimento ×100 (base 20M) e crescimento 3,2 → 5; Power2x do boss desligado; HP por fileira ×2 (5) … ×150 (10).",
		Overrides = {
			RebirthBaseCost = 2e7,
			RebirthCostGrowth = 5,
			BossBoostSeconds = 0,
			StageHp = { [5] = 2, [6] = 5, [7] = 10, [8] = 12, [9] = 25, [10] = 150 },
		},
	},
	C = {
		Summary = "curva longa: custo do renascimento ×100 e crescimento 4,5; Power2x do boss 5 min só para quem bateu; Ovo Místico 400 e Ovo do Caminho 1.200 gemas; fileiras 6/7/8/10 nos estágios 7–10; HP por fileira ×2 (5) … ×40 (10).",
		Overrides = {
			RebirthBaseCost = 2e7,
			RebirthCostGrowth = 4.5,
			BossBoostSeconds = 300,
			BossBoostParticipantsOnly = true,
			EggPrice = { MysticEgg = 400, TowerEgg = 1200 },
			StageRows = { [7] = 6, [8] = 7, [9] = 8, [10] = 10 },
			StageHp = { [5] = 2, [6] = 4, [7] = 6, [8] = 10, [9] = 12, [10] = 40 },
		},
	},
}
