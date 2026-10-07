--[[
	econ_scenarios.luau — cenários de rebalanceamento da auditoria (PROPOSTAS).

	Nada disto está no jogo. São overrides que o econ_model aplica só na própria
	cópia das configs, para comparar com o ATUAL. Calibrados com o Monte Carlo
	(econ_audit.luau scenarios) contra as metas do perfil Ativo:
		estágio 7 ≈ 3–4 h ativas (D3) · 8 ≈ 6–7 h (D5) · 9 ≈ 10–14 h (D7–D10)
		mata o Colosso ≈ 35–50 h ativas (D25–D35)

	StageHp multiplica o HP POR FILEIRA; StageRows troca o número de fileiras.
]]

local Scenarios = {}

--[[
	Parâmetros do C2 (os mesmos da busca em econ_search.luau) → overrides.
	HpN multiplica o HP TOTAL do estágio N; com mais fileiras cada fileira
	fica mais fina (mesma luta total).
]]
function Scenarios.FromParams(p, wallStages)
	local curve = if p.Knee and p.Knee > 0 then { Base = p.Base, Early = p.Early, Knee = p.Knee, Growth = p.Growth } else nil
	return {
		RebirthCurve = curve,
		RebirthBaseCost = if curve then nil else p.Base,
		RebirthCostGrowth = if curve then nil else p.Growth,
		BossBoostSeconds = p.Boss,
		BossBoostParticipantsOnly = true,
		EggPrice = { MysticEgg = p.Mystic, TowerEgg = p.Tower },
		StageRows = { [7] = p.Rows7, [8] = p.Rows8, [9] = p.Rows9, [10] = p.Rows10 },
		StageHp = {
			[5] = p.Hp5,
			[6] = p.Hp6,
			[7] = p.Hp7 * wallStages[7].Rows / p.Rows7,
			[8] = p.Hp8 * wallStages[8].Rows / p.Rows8,
			[9] = p.Hp9 * wallStages[9].Rows / p.Rows9,
			[10] = p.Hp10 * wallStages[10].Rows / p.Rows10,
		},
	}
end

for key, value in {
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
} do
	Scenarios[key] = value
end

--[[
	Finalistas do C2 (curva longa refinada), saídos da busca automática
	(econ_search.luau, 4 pontos de partida). Todos preservam 1,75^R, pets,
	cortes, melhorias, treino, Auto Click e prêmios. Custo do renascimento:
	Base × Growth^r (Knee = 0: as buscas que partiram de curvas em duas fases
	convergiram para uma fase só).
]]
Scenarios.C2 = {
	["C2-A"] = {
		Summary = "busca a partir do C: base 2M, crescimento 5; HP 5 ×2, 6 ×4, 7 ×10, 8 ×14, 9 ×6, 10 ×120; fileiras 6/7/8/10; Místico 400, Caminho 1.000; boss 3 min só participantes.",
		Params = { Base = 2e6, Early = 3.2, Knee = 0, Growth = 5, Hp5 = 2, Hp6 = 4, Hp7 = 10, Hp8 = 14, Hp9 = 6, Hp10 = 120, Rows7 = 6, Rows8 = 7, Rows9 = 8, Rows10 = 10, Mystic = 400, Tower = 1000, Boss = 180 },
	},
	["C2-B"] = {
		Summary = "busca a partir de curva em 2 fases (convergiu p/ 1 fase): base 1M, crescimento 6; HP 5 ×1,5, 6 ×2,5, 7 ×4, 8 ×10, 9 ×12, 10 ×120; fileiras 5/6/8/10; Místico 300, Caminho 800; boss 5 min só participantes.",
		Params = { Base = 1e6, Early = 4, Knee = 0, Growth = 6, Hp5 = 1.5, Hp6 = 2.5, Hp7 = 4, Hp8 = 10, Hp9 = 12, Hp10 = 120, Rows7 = 5, Rows8 = 6, Rows9 = 8, Rows10 = 10, Mystic = 300, Tower = 800, Boss = 300 },
	},
	["C2-C"] = {
		Summary = "busca a partir de curva antiga no início: base 2M, crescimento 6; HP 5 ×1,5, 6 ×1,5, 7 ×3, 8 ×5, 9 ×6, 10 ×80; fileiras 5/7/6/10; Místico 350, Caminho 800; boss 3 min só participantes.",
		Params = { Base = 2e6, Early = 4, Knee = 0, Growth = 6, Hp5 = 1.5, Hp6 = 1.5, Hp7 = 3, Hp8 = 5, Hp9 = 6, Hp10 = 80, Rows7 = 5, Rows8 = 7, Rows9 = 6, Rows10 = 10, Mystic = 350, Tower = 800, Boss = 180 },
	},
	["C2-D"] = {
		Summary = "C2-B com o Colosso mais baixo (×40): o \"pronto\" (luta ≤ 3 min) vem para ~D30; base 1M, crescimento 6; HP 5 ×1,5, 6 ×2,5, 7 ×4, 8 ×10, 9 ×12, 10 ×40; fileiras 5/6/8/10; Místico 300, Caminho 800; boss 5 min só participantes.",
		Params = { Base = 1e6, Early = 4, Knee = 0, Growth = 6, Hp5 = 1.5, Hp6 = 2.5, Hp7 = 4, Hp8 = 10, Hp9 = 12, Hp10 = 40, Rows7 = 5, Rows8 = 6, Rows9 = 8, Rows10 = 10, Mystic = 300, Tower = 800, Boss = 300 },
	},
	["C2-E"] = {
		Summary = "C2-D com crescimento 5,5 e estágios 8/9 mais baixos (×8): mesma estreia do renascimento, casual sem ficar semanas parado; base 1M, crescimento 5,5; HP 5 ×1,5, 6 ×2,5, 7 ×4, 8 ×8, 9 ×8, 10 ×40; fileiras 5/6/8/10; Místico 300, Caminho 800; boss 5 min só participantes.",
		Params = { Base = 1e6, Early = 4, Knee = 0, Growth = 5.5, Hp5 = 1.5, Hp6 = 2.5, Hp7 = 4, Hp8 = 8, Hp9 = 8, Hp10 = 40, Rows7 = 5, Rows8 = 6, Rows9 = 8, Rows10 = 10, Mystic = 300, Tower = 800, Boss = 300 },
	},
}
Scenarios.C2Order = { "C2-A", "C2-B", "C2-C", "C2-D", "C2-E" }
Scenarios.C2Pick = "C2-E" -- escolhido após o Monte Carlo de 500 (ver relatório C2)

return Scenarios
