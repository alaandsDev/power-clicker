--[[
	econ_audit.luau — auditoria da progressão 1 → 10 (só análise).

		lune run tools/lune/econ_audit.luau [raiz] [seção ...] [runs=N] [scenario=A|B|C]

	Seções (sem nenhuma = todas):
		formula     camadas e fórmula do golpe, caso a caso
		combo       combo médio real (ComboLogic) por padrão de clique
		stages      barreiras 1–10 (HP, fileiras, prêmios, gemas)
		rebirth     multiplicador/custo/gemas por renascimento
		upgrades    melhorias (custo, efeito, níveis alcançáveis)
		pets        ovos: chance, EV, P25/P50/P75/P90 do bônus e do time
		base        perfis determinísticos: snapshots, jornada, origem do Power
		snowball    linha do tempo dos renascimentos (onde acelera)
		mc          Monte Carlo (N por perfil): estágio 7, 9, chega 10, mata 10
		elastic     elasticidade: HP 7–10 × 2 / × 5 / × 10
		scenarios   cenários A, B, C (econ_scenarios.luau) vs atual
		repro       hipóteses do caso real (≈4B em ≈2 dias)

	Nada aqui altera o jogo: o modelo lê as configs e as fórmulas reais e
	aplica overrides só na própria cópia. Saída em Markdown.
]]
local process = require("@lune/process")

local root = nil
local wanted = {}
local runs = 500
local scenarioFilter = nil
do
	local index = 1
	while process.args[index] do
		local arg = process.args[index]
		if string.sub(arg, 1, 5) == "runs=" then
			runs = tonumber(string.sub(arg, 6)) or runs
		elseif string.sub(arg, 1, 9) == "scenario=" then
			scenarioFilter = string.sub(arg, 10)
		elseif string.find(arg, "/") then
			root = arg
		else
			wanted[arg] = true
		end
		index += 1
	end
end
local all = next(wanted) == nil

local E = require("./env")(root)
local Model = require("./econ_model")(E)
local Profiles = require("./econ_profiles")
local Scenarios = require("./econ_scenarios")
local Cfg, F = Model.Cfg, Model.F

-- ── Formatação ──────────────────────────────────────────────────────────────
local function short(x: number?): string
	if x == nil or x == math.huge then
		return "—"
	end
	local units = { { 1e18, "Qi" }, { 1e15, "Qa" }, { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }
	for _, unit in units do
		if math.abs(x) >= unit[1] then
			return string.format("%.2f%s", x / unit[1], unit[2])
		end
	end
	if x == math.floor(x) then
		return tostring(x)
	end
	return string.format("%.2f", x)
end

local function hours(seconds: number?): string
	if seconds == nil then
		return "—"
	end
	if seconds < 3600 then
		return string.format("%.0f min", seconds / 60)
	end
	return string.format("%.1f h", seconds / 3600)
end

local function days(seconds: number?): string
	if seconds == nil then
		return "—"
	end
	local d = seconds / 86400
	if d < 1 then
		return string.format("D1 (%s)", hours(seconds))
	end
	return string.format("D%d", math.floor(d) + 1)
end

local function both(m): string
	if not m then
		return "não chega"
	end
	return string.format("%s ativo · %s", hours(m.Active), days(m.Calendar))
end

local function row(cells: { string }): string
	return "| " .. table.concat(cells, " | ") .. " |"
end

local function header(cells: { string })
	print(row(cells))
	local dashes = {}
	for _ in cells do
		table.insert(dashes, "---")
	end
	print(row(dashes))
end

local function section(title: string)
	print("")
	print("## " .. title)
	print("")
end

local function percentile(list: { number }, p: number): number?
	if #list == 0 then
		return nil
	end
	local sorted = table.clone(list)
	table.sort(sorted)
	local index = math.clamp(math.ceil(p * #sorted), 1, #sorted)
	return sorted[index]
end

local function profileFor(id: string, extra: { [string]: any }?)
	local profile = table.clone(Profiles[id])
	for key, value in extra or {} do
		profile[key] = value
	end
	profile.ComboAvg = profile.ComboAvg or Model.ComboAverage(Cfg.Economy.Click.HoldClicksPerSecond, profile.Burst, profile.Pause)
	return profile
end

local CAL_MARKS = { 15 * 60, 30 * 60, 3600, 2 * 3600, 4 * 3600, 6 * 3600, 12 * 3600, 86400, 2 * 86400, 3 * 86400, 7 * 86400, 14 * 86400, 30 * 86400 }
local CAL_NAMES = { "15m", "30m", "1h", "2h", "4h", "6h", "12h", "24h", "2d", "3d", "7d", "14d", "30d" }
local ACTIVE_MARKS = { 15 * 60, 30 * 60, 3600, 2 * 3600, 4 * 3600, 6 * 3600, 12 * 3600, 24 * 3600, 48 * 3600 }
local ACTIVE_NAMES = { "15m", "30m", "1h", "2h", "4h", "6h", "12h", "24h", "48h" }

-- ── formula ─────────────────────────────────────────────────────────────────
if all or wanted.formula then
	section("Fórmula do golpe (PowerFormula real)")
	print("golpe = (1 + ClickStrength + Corte) × Upgrade × Permanent × Rebirth × World × Pet × Aura × Rune × GamePass × TemporaryBoost × Event × Social × Zone × Overdrive × combo")
	print("")
	header({ "Exemplo", "Base", "Camadas", "⚡ por clique (PowerFormula)", "⚔ golpe (combo máx)" })
	local examples = {
		{ "Início", 2, { Upgrade = 1, Rebirth = 1 } },
		{ "R5, PB10, pets 3, Corte5", 1 + 60 + 25, { Upgrade = 3.5, Rebirth = F.Economy.RebirthMultiplier(5), Pet = 3 } },
		{ "R15, PB20, pets 15, Corte8, boost, fds", 1 + 100 + 400, { Upgrade = 6, Rebirth = F.Economy.RebirthMultiplier(15), Pet = 15, Aura = 1.4, TemporaryBoost = 2, Event = 2 } },
	}
	for _, example in examples do
		local perClick = F.Power.Compute(example[2], example[3])
		local parts = {}
		for layer, value in example[3] do
			table.insert(parts, string.format("%s ×%s", layer, short(value)))
		end
		table.sort(parts)
		print(row({ example[1], tostring(example[2]), table.concat(parts, ", "), short(perClick), short(perClick * F.Economy.ComboMultiplier(Cfg.Combo.MaxStacks)) }))
	end
end

-- ── combo ───────────────────────────────────────────────────────────────────
if all or wanted.combo then
	section("Combo médio real (ComboLogic + EconomyFormulas.ComboMultiplier)")
	local combo = Cfg.Combo
	print(string.format("Stacks: +1 por clique manual, máx %d (×%.2f), timeout %.2f s, depois cai %d stacks/s. Auto Click: BuildsCombo = %s.",
		combo.MaxStacks, F.Economy.ComboMultiplier(combo.MaxStacks), combo.TimeoutSeconds, combo.DecayStacksPerSecond, tostring(Cfg.Economy.AutoClick.BuildsCombo)))
	print(string.format("Segurando a %d/s o combo chega ao máximo em %.1f s.", Cfg.Economy.Click.HoldClicksPerSecond, combo.MaxStacks / Cfg.Economy.Click.HoldClicksPerSecond))
	print("")
	header({ "Padrão", "cps", "segura / para (s)", "combo médio por clique", "Overdrive médio" })
	local patterns = {
		{ "toques soltos", 3, 2, 3 },
		{ "Casual", 9, Profiles.Casual.Burst, Profiles.Casual.Pause },
		{ "Ativo", 9, Profiles.Ativo.Burst, Profiles.Ativo.Pause },
		{ "Muito ativo", 9, Profiles.MuitoAtivo.Burst, Profiles.MuitoAtivo.Pause },
		{ "Otimizador", 9, Profiles.Otimizador.Burst, Profiles.Otimizador.Pause },
		{ "segurando sem parar", 9, 3600, 0 },
		{ "clique rápido (teto 20/s)", 20, 3600, 0 },
	}
	for _, pattern in patterns do
		local avg = Model.ComboAverage(pattern[2], pattern[3], pattern[4])
		local duty = pattern[3] / (pattern[3] + pattern[4])
		print(row({ pattern[1], tostring(pattern[2]), string.format("%s / %s", pattern[3], pattern[4]), string.format("×%.3f", avg), string.format("×%.2f", Model.OverdriveAverage(pattern[2] * duty)) }))
	end
	print(row({ "Auto Click", tostring(Cfg.Economy.AutoClick.TicksPerSecond), "—", "×1.000 (sem combo)", "×1.00 (não carrega)" }))
end

-- ── stages ──────────────────────────────────────────────────────────────────
if all or wanted.stages then
	section("Barreiras 1–10 (WallConfig)")
	header({ "#", "Estágio", "HP/fileira", "Fileiras", "HP total", "× anterior", "Pads (normal / x2)", "Gemas 1ª vez", "Repetir no melhor (x2)", "Ovo liberado" })
	local previous = nil
	for _, stage in Cfg.Wall.Stages do
		local total = stage.Hp * stage.Rows
		local share = F.WinPad.Share(stage, { Cleared = { [stage.Id] = true }, Highest = stage.Order }, false)
		local eggs = {}
		for _, egg in Cfg.Egg.Eggs do
			if egg.RequiredStage == stage.Id then
				table.insert(eggs, egg.DisplayName)
			end
		end
		print(row({ tostring(stage.Order), stage.Id, short(stage.Hp), tostring(stage.Rows), short(total), if previous then string.format("×%.1f", total / previous) else "—",
			string.format("%s / %s", short(stage.Pads[1]), short(stage.Pads[2])), tostring(stage.FirstClearGems), short(F.WinPad.Payout(stage, 2, share)), table.concat(eggs, ", ") }))
		previous = total
	end
end

-- ── rebirth ─────────────────────────────────────────────────────────────────
if all or wanted.rebirth then
	section("Renascimento (RebirthConfig + EconomyFormulas)")
	print(string.format("custo(r) = %s × %.2f^r · multiplicador(R) = (1 + %.2f)^R · gemas(r) = %d + %d·r · reseta: Power e melhorias temporárias · mantém: cortes, pets, gemas, wins, auras, runas, barreiras conquistadas",
		short(Cfg.Rebirth.BaseCost), Cfg.Rebirth.CostGrowth, Cfg.Rebirth.MultiplierPerRebirth, Cfg.Rebirth.BaseGems, Cfg.Rebirth.GemsPerRebirth))
	print("")
	header({ "R", "Multiplicador", "Custo do próximo", "Custo ÷ multiplicador", "Gemas do próximo", "Gemas acumuladas" })
	local cumulative = 0
	local marks = { [0] = true, [1] = true, [2] = true, [3] = true, [5] = true, [10] = true, [15] = true, [20] = true, [25] = true, [30] = true, [40] = true, [50] = true }
	for r = 0, 50 do
		if marks[r] then
			local mult = F.Economy.RebirthMultiplier(r)
			local cost = F.Economy.RebirthCost(r)
			print(row({ tostring(r), "×" .. short(mult), short(cost), short(cost / mult), tostring(F.Economy.RebirthGems(r)), tostring(cumulative) }))
		end
		cumulative += F.Economy.RebirthGems(r)
	end
end

-- ── upgrades ────────────────────────────────────────────────────────────────
if all or wanted.upgrades then
	section("Melhorias (UpgradeConfig)")
	header({ "Melhoria", "Moeda", "Custo base", "Crescimento", "Máx", "Efeito/nível", "Custo nv 10", "Custo nv 25", "Custo do máx", "Nível com 1B / 1T de saldo" })
	for _, kind in { "Temporary", "Permanent" } do
		for id, upgrade in Cfg.Upgrade[kind] do
			local function levelWith(balance: number): number
				local level, spent = 0, 0
				while level < upgrade.MaxLevel do
					local cost = F.Economy.UpgradeCost(upgrade, level)
					if spent + cost > balance then
						break
					end
					spent += cost
					level += 1
				end
				return level
			end
			print(row({ id, upgrade.Currency, short(upgrade.BaseCost), tostring(upgrade.CostGrowth), tostring(upgrade.MaxLevel), string.format("%s %s", tostring(upgrade.EffectPerLevel), upgrade.EffectType),
				short(F.Economy.UpgradeCost(upgrade, 10)), short(F.Economy.UpgradeCost(upgrade, math.min(25, upgrade.MaxLevel - 1))), short(F.Economy.UpgradeCost(upgrade, upgrade.MaxLevel - 1)),
				string.format("%d / %d", levelWith(1e9), levelWith(1e12)) }))
		end
	end
	print("")
	print("Cortes (base, comprados com Power, gate por Wins, o melhor conta):")
	print("")
	header({ "Corte", "+ base", "Preço", "Wins" })
	local cuts = {}
	for _, cut in Cfg.Cut.Cuts do
		table.insert(cuts, cut)
	end
	table.sort(cuts, function(a, b)
		return a.Order < b.Order
	end)
	for _, cut in cuts do
		print(row({ cut.Id, "+" .. cut.Flat, short(cut.Price), short(cut.RequiredWins) }))
	end
	print("")
	print("Auras (gemas, gate por Wins, uma equipada):")
	print("")
	header({ "Aura", "× Power", "Gemas", "Wins", "Velocidade" })
	for _, aura in F.Aura.Ordered() do
		print(row({ aura.Id, "×" .. aura.PowerMultiplier, short(aura.Price), short(aura.RequiredWins), "+" .. aura.WalkSpeedBonus }))
	end
end

-- ── pets ────────────────────────────────────────────────────────────────────
if all or wanted.pets then
	section("Ovos e pets (EggOdds real, sorte 1)")
	print(string.format("Pet = 1 + Σ bônus dos equipados (aditivo). Equipados: %d base + até 3 (Pet Slots) + 3 (passe) → teto %d.",
		Cfg.Pet.BaseEquipSlots, Cfg.Pet.MaxEquipSlots))
	print("")
	header({ "Ovo", "Moeda", "Preço", "Requisito", "Chances", "EV bônus/ovo", "EV por 1K de preço" })
	local order = {}
	for _, egg in Cfg.Egg.Eggs do
		table.insert(order, egg)
	end
	table.sort(order, function(a, b)
		return (if a.Currency == "Power" then 0 else 1) * 1e9 + a.Price < (if b.Currency == "Power" then 0 else 1) * 1e9 + b.Price
	end)
	for _, egg in order do
		local chances = F.EggOdds.Chances(egg, 1)
		local parts, ev = {}, 0
		for _, drop in egg.Drops do
			local pet = Cfg.Pet.Pets[drop.PetId]
			ev += chances[drop.PetId] * pet.Bonus
			table.insert(parts, string.format("%s %.1f%% (+%s)", pet.DisplayName, chances[drop.PetId] * 100, tostring(pet.Bonus)))
		end
		print(row({ egg.DisplayName, egg.Currency, short(egg.Price), egg.RequiredStage or "—", table.concat(parts, "; "), string.format("+%.2f", ev), string.format("%.3f", ev / egg.Price * 1000) }))
	end
	print("")
	print("Multiplicador de pets com N ovos do MESMO tipo, 6 equipados (3 base + 3 Pet Slots), 4000 amostras:")
	print("")
	header({ "Ovo", "N ovos", "Gemas", "P25", "P50", "P75", "P90" })
	local rng = Model.Rng(42)
	for _, egg in order do
		if egg.Currency == "Gems" then
			for _, n in { 5, 20, 50 } do
				local samples = {}
				for _ = 1, 4000 do
					local bonuses = {}
					local weights = F.EggOdds.Weights(egg, 1)
					for _ = 1, n do
						table.insert(bonuses, Cfg.Pet.Pets[F.EggOdds.Pick(weights, rng())].Bonus)
					end
					table.sort(bonuses, function(a, b)
						return a > b
					end)
					local mult = 1
					for index = 1, math.min(6, #bonuses) do
						mult += bonuses[index]
					end
					table.insert(samples, mult)
				end
				print(row({ egg.DisplayName, tostring(n), short(n * egg.Price), string.format("×%.1f", percentile(samples, 0.25)), string.format("×%.1f", percentile(samples, 0.5)), string.format("×%.1f", percentile(samples, 0.75)), string.format("×%.1f", percentile(samples, 0.9)) }))
			end
		end
	end
end

-- ── base ────────────────────────────────────────────────────────────────────
local function deterministic(id: string, overrides, extra)
	local profile = profileFor(id, extra)
	return Model.Run(profile, { Days = 30, Seed = 1, CalendarMarks = CAL_MARKS, ActiveMarks = ACTIVE_MARKS, Overrides = overrides })
end

if all or wanted.base then
	section("Perfis (suposições) — econ_profiles.luau")
	header({ "Perfil", "h ativas/dia", "sessões", "AFK h/dia", "segura clique", "combo médio", "Overdrive médio", "boss", "renasce em", "passes" })
	for _, id in Profiles.Order do
		local p = profileFor(id)
		local passes = {}
		for key in p.Passes or {} do
			table.insert(passes, key)
		end
		print(row({ p.Name, tostring(p.HoursPerDay), tostring(p.Sessions), tostring(p.AfkHoursPerDay or 0), string.format("%.0f%%", p.HoldShare * 100), string.format("×%.2f", p.ComboAvg),
			string.format("×%.2f", Model.OverdriveAverage(9 * p.HoldShare)), string.format("entra %.0f%%, outros %.0f%%", p.BossJoin * 100, p.OthersKillBoss * 100), string.format("%s× custo", tostring(p.RebirthAt or 1)), if #passes > 0 then table.concat(passes, ", ") else "nenhum" }))
	end

	local results = {}
	for _, id in Profiles.Order do
		results[id] = deterministic(id)
	end

	section("Snapshots por CALENDÁRIO (seed 1) — ⚡ saldo · ⚔ golpe · R · estágio conquistado")
	header({ "Perfil", table.unpack(CAL_NAMES) })
	for _, id in Profiles.Order do
		local st = results[id]
		local cells = { Profiles[id].Name }
		for _, mark in CAL_MARKS do
			local s = st.Snapshots["C" .. mark]
			table.insert(cells, if s then string.format("⚡%s ⚔%s R%d E%d", short(s.Power), short(s.Hit), s.Rebirths, s.Highest) else "—")
		end
		print(row(cells))
	end

	section("Snapshots por tempo ATIVO (seed 1)")
	header({ "Perfil", table.unpack(ACTIVE_NAMES) })
	for _, id in Profiles.Order do
		local st = results[id]
		local cells = { Profiles[id].Name }
		for _, mark in ACTIVE_MARKS do
			local s = st.Snapshots["A" .. mark]
			table.insert(cells, if s then string.format("⚡%s ⚔%s R%d E%d", short(s.Power), short(s.Hit), s.Rebirths, s.Highest) else "—")
		end
		print(row(cells))
	end

	section("Jornada por estágio (1ª conquista; 'chega ao 10' = conquista o 9) — seed 1")
	header({ "Estágio", table.unpack((function()
		local names = {}
		for _, id in Profiles.Order do
			table.insert(names, Profiles[id].Name)
		end
		return names
	end)()) })
	for order = 1, #Cfg.Wall.Stages do
		local cells = { tostring(order) .. " " .. Cfg.Wall.Stages[order].Id }
		for _, id in Profiles.Order do
			local m = results[id].Milestones["clear:" .. order]
			table.insert(cells, if m then string.format("%s · %s · R%d", hours(m.Active), days(m.Calendar), m.Rebirths) else "não chega em 30d")
		end
		print(row(cells))
	end

	section("De onde vem o Power (30 dias, seed 1)")
	header({ "Perfil", "Clique", "Auto", "Treino", "Boss", "Orbes", "Baús", "Power total", "R", "Pets ×", "Aura", "Runa ×" })
	for _, id in Profiles.Order do
		local st = results[id]
		local total = 0
		for _, v in st.Income do
			total += v
		end
		local s = Model.Snapshot(st)
		local function pct(key)
			return string.format("%.1f%%", st.Income[key] / math.max(total, 1) * 100)
		end
		print(row({ Profiles[id].Name, pct("Click"), pct("Auto"), pct("Training"), pct("Boss"), pct("Orbs"), pct("Chests"), short(st.TotalPower), tostring(st.Rebirths), string.format("×%.1f", s.PetMult), s.Aura, string.format("×%.2f", s.RuneMult) }))
	end
end

-- ── snowball ────────────────────────────────────────────────────────────────
if all or wanted.snowball then
	section("Onde acelera — renascimentos do perfil Ativo (seed 1)")
	local st = deterministic("Ativo")
	header({ "R", "quando (ativo)", "intervalo", "estágio na hora", "custo pago" })
	local previous = 0
	for r = 1, st.Rebirths do
		local m = st.Milestones["rebirth:" .. r]
		local stage = 0
		for order = 1, #Cfg.Wall.Stages do
			local c = st.Milestones["clear:" .. order]
			if c and c.Active <= m.Active then
				stage = order
			end
		end
		print(row({ tostring(r), hours(m.Active), hours(m.Active - previous), tostring(stage), short(F.Economy.RebirthCost(r - 1)) }))
		previous = m.Active
	end
end

-- ── Monte Carlo ─────────────────────────────────────────────────────────────
local MC_DAYS = 180
local function monteCarlo(id: string, n: number, overrides, extra)
	local profile = profileFor(id, extra)
	local out = { Missing = {}, Hit9 = {}, Hit10 = {} }
	for order = 1, #Cfg.Wall.Stages do
		out["S" .. order] = {}
		out["S" .. order .. "c"] = {}
		out.Missing["S" .. order] = 0
	end
	for seed = 1, n do
		local st = Model.Run(profile, { Days = MC_DAYS, Seed = seed * 7919, StopWhen = "Colossus", Overrides = overrides })
		for order = 1, #Cfg.Wall.Stages do
			local key = "S" .. order
			local m = st.Milestones["clear:" .. order]
			if m then
				table.insert(out[key], m.Active)
				table.insert(out[key .. "c"], m.Calendar)
			else
				out.Missing[key] += 1
			end
		end
	end
	return out
end
Model.MonteCarlo = monteCarlo

local function pctCell(list, missing, p, calendar)
	local value = percentile(list, p)
	if value == nil or (missing > 0 and #list < math.ceil(p * (#list + missing))) then
		return string.format(">%dd", MC_DAYS)
	end
	return if calendar then days(value) else hours(value)
end

if all or wanted.mc then
	section(string.format("Monte Carlo — %d execuções por perfil (até %d dias)", runs, MC_DAYS))
	header({ "Perfil", "Marco", "P25", "P50", "P75", "P90", "P50 calendário", "P90 calendário" })
	for _, id in Profiles.Order do
		local out = monteCarlo(id, runs)
		for _, item in { { "S7", "Estágio 7" }, { "S9", "Estágio 9 (chega ao 10)" }, { "S10", "Mata o Colosso" } } do
			local list, miss = out[item[1]], out.Missing[item[1]]
			print(row({ Profiles[id].Name, item[2], pctCell(list, miss, 0.25), pctCell(list, miss, 0.5), pctCell(list, miss, 0.75), pctCell(list, miss, 0.9),
				pctCell(out[item[1] .. "c"], miss, 0.5, true), pctCell(out[item[1] .. "c"], miss, 0.9, true) }))
		end
	end
end

-- ── elasticidade ────────────────────────────────────────────────────────────
if all or wanted.elastic then
	local n = math.max(math.floor(runs / 2.5), 50)
	section(string.format("Elasticidade — HP dos estágios 7–10 multiplicado (Ativo e Muito ativo, %d execuções)", n))
	header({ "Perfil", "HP 7–10", "Estágio 7 P50", "Estágio 9 P50", "Mata Colosso P50", "Mata Colosso P90" })
	for _, id in { "Ativo", "MuitoAtivo" } do
		for _, k in { 1, 2, 5, 10 } do
			local out = monteCarlo(id, n, { StageHp = { [7] = k, [8] = k, [9] = k, [10] = k } })
			print(row({ Profiles[id].Name, "×" .. k, pctCell(out.S7, out.Missing.S7, 0.5), pctCell(out.S9, out.Missing.S9, 0.5), pctCell(out.S10, out.Missing.S10, 0.5), pctCell(out.S10, out.Missing.S10, 0.9) }))
		end
	end
end

-- Saldo/total/renascimentos do perfil no D2 e D7 (sem parar no Colosso).
local function earlyDays(id: string, n: number, overrides)
	local profile = profileFor(id)
	local out = { PowerD2 = {}, PowerD7 = {}, TotalD7 = {}, RebirthD7 = {}, StageD7 = {} }
	for seed = 1, n do
		local st = Model.Run(profile, { Days = 7, Seed = seed * 7919, Overrides = overrides, CalendarMarks = { 2 * 86400, 7 * 86400 } })
		local d2, d7 = st.Snapshots["C" .. 2 * 86400], st.Snapshots["C" .. 7 * 86400]
		table.insert(out.PowerD2, d2.Power)
		table.insert(out.PowerD7, d7.Power)
		table.insert(out.TotalD7, d7.TotalPower)
		table.insert(out.RebirthD7, d7.Rebirths)
		table.insert(out.StageD7, d7.Highest)
	end
	return out
end

-- Os 3 estados do Colosso (Ativo, seed 1): ao chegar, no meio, pronto.
local function colossusStates(overrides)
	local profile = profileFor("Ativo")
	local first = Model.Run(profile, { Days = MC_DAYS, Seed = 1, StopWhen = "Colossus", Overrides = overrides })
	local arrive = first.Milestones["clear:9"]
	local kill = first.Milestones["clear:10"]
	if not arrive or not kill then
		return nil
	end
	local mid = (arrive.Active + kill.Active) / 2
	local again = Model.Run(profile, { Days = MC_DAYS, Seed = 1, StopWhen = "Colossus", Overrides = overrides, ActiveMarks = { arrive.Active + 1, mid } })
	local states = {}
	for _, item in { { "acabou de chegar", "A" .. (arrive.Active + 1) }, { "se preparando", "A" .. mid } } do
		local snap = again.Snapshots[item[2]]
		if snap then
			table.insert(states, { item[1], snap.Hit, snap.Active, snap.Rebirths })
		end
	end
	table.insert(states, { "pronto (quando mata)", kill.Hit, kill.Active, kill.Rebirths })
	local stage = Model.StageOf({ Stages = (function()
		local list = {}
		for index, st in Cfg.Wall.Stages do
			local copy = table.clone(st)
			copy.Hp = st.Hp * (overrides.StageHp and overrides.StageHp[index] or 1)
			copy.Rows = overrides.StageRows and overrides.StageRows[index] or st.Rows
			list[index] = copy
		end
		return list
	end)() }, #Cfg.Wall.Stages)
	local wallRate = Cfg.Economy.Click.HoldClicksPerSecond * profile.HoldShare * profile.WallShare
	local rows = {}
	for _, state in states do
		local perRow = math.ceil(stage.Hp / math.max(state[2] or 1, 1e-9))
		table.insert(rows, { Name = state[1], Hit = state[2], Active = state[3], Rebirths = state[4], PerRow = perRow, Total = perRow * stage.Rows, Seconds = perRow * stage.Rows / wallRate })
	end
	return rows, stage
end

-- ── cenários ────────────────────────────────────────────────────────────────
if all or wanted.scenarios then
	section(string.format("Cenários — Monte Carlo %d execuções", runs))
	local list = { { Id = "ATUAL", Overrides = {} } }
	for _, id in { "A", "B", "C" } do
		if not scenarioFilter or scenarioFilter == id then
			table.insert(list, { Id = id, Overrides = Scenarios[id].Overrides })
		end
	end
	local results = {}
	for _, scenario in list do
		results[scenario.Id] = {}
		for _, id in Profiles.Order do
			results[scenario.Id][id] = monteCarlo(id, runs, scenario.Overrides)
		end
	end
	local cols = { "Linha" }
	for _, scenario in list do
		table.insert(cols, scenario.Id)
	end
	header(cols)
	local function line(label, fn)
		local cells = { label }
		for _, scenario in list do
			table.insert(cells, fn(results[scenario.Id]))
		end
		print(row(cells))
	end
	for _, id in { "Casual", "Ativo", "MuitoAtivo" } do
		for _, item in { { "S7", "Stage 7" }, { "S9", "Stage 9" }, { "S9", "chega 10" }, { "S10", "mata Colosso" } } do
			line(string.format("%s: %s (P50 ativo · calendário)", Profiles[id].Name, item[2]), function(r)
				local out = r[id]
				return pctCell(out[item[1]], out.Missing[item[1]], 0.5) .. " · " .. pctCell(out[item[1] .. "c"], out.Missing[item[1]], 0.5, true)
			end)
		end
	end
	line("Otimizador mata Colosso (P50)", function(r)
		local out = r.Otimizador
		return pctCell(out.S10, out.Missing.S10, 0.5) .. " · " .. pctCell(out.S10c, out.Missing.S10, 0.5, true)
	end)
	local early = {}
	for _, scenario in list do
		early[scenario.Id] = earlyDays("Ativo", math.max(math.floor(runs / 2.5), 50), scenario.Overrides)
	end
	local function earlyLine(label, fn)
		local cells = { label }
		for _, scenario in list do
			table.insert(cells, fn(early[scenario.Id]))
		end
		print(row(cells))
	end
	earlyLine("Power ativo D2 (⚡ saldo P50)", function(r)
		return short(percentile(r.PowerD2, 0.5))
	end)
	earlyLine("Power ativo D7 (⚡ saldo P50)", function(r)
		return short(percentile(r.PowerD7, 0.5))
	end)
	earlyLine("Power ativo D7 (total ganho P50)", function(r)
		return short(percentile(r.TotalD7, 0.5))
	end)
	earlyLine("Rebirth ativo D7 (P50)", function(r)
		return tostring(percentile(r.RebirthD7, 0.5) or "—")
	end)
	earlyLine("Estágio ativo D7 (P50)", function(r)
		return tostring(percentile(r.StageD7, 0.5) or "—")
	end)
	for _, scenario in list do
		if scenario.Id ~= "ATUAL" then
			print("")
			print(string.format("**%s** — %s", scenario.Id, Scenarios[scenario.Id].Summary))
		end
	end

	-- Detalhe por estágio (Ativo): HP atual/novo, multiplicador, tempo P50.
	for _, scenario in list do
		if scenario.Id ~= "ATUAL" then
			section("Cenário " .. scenario.Id .. " — estágio a estágio (perfil Ativo, P50)")
			header({ "Estágio", "HP atual (fileira × fileiras)", "HP novo", "× HP total", "Tempo atual", "Tempo novo" })
			local o = scenario.Overrides
			for order, stage in Cfg.Wall.Stages do
				local rows = o.StageRows and o.StageRows[order] or stage.Rows
				local hp = stage.Hp * (o.StageHp and o.StageHp[order] or 1)
				local now, new = results.ATUAL.Ativo, results[scenario.Id].Ativo
				local key = "S" .. order
				print(row({ string.format("%d %s", order, stage.Id), string.format("%s × %d = %s", short(stage.Hp), stage.Rows, short(stage.Hp * stage.Rows)),
					string.format("%s × %d = %s", short(hp), rows, short(hp * rows)), string.format("×%s", short(hp * rows / (stage.Hp * stage.Rows))),
					pctCell(now[key], now.Missing[key], 0.5) .. " · " .. pctCell(now[key .. "c"], now.Missing[key], 0.5, true),
					pctCell(new[key], new.Missing[key], 0.5) .. " · " .. pctCell(new[key .. "c"], new.Missing[key], 0.5, true) }))
			end
		end
	end

	section("Colosso em 3 estados (Ativo, seed 1): golpes por fileira e tempo de luta")
	header({ "Cenário", "Estado", "⚔ golpe", "R", "tempo ativo", "golpes/fileira", "golpes no total", "luta (s)" })
	for _, scenario in list do
		local rowsOut, stage = colossusStates(scenario.Overrides)
		if rowsOut then
			for _, r in rowsOut do
				print(row({ scenario.Id, r.Name, short(r.Hit), tostring(r.Rebirths), hours(r.Active), short(r.PerRow), short(r.Total), short(math.floor(r.Seconds)) }))
			end
		end
	end
end

-- ── caso real ───────────────────────────────────────────────────────────────
if all or wanted.repro then
	section("Caso real (≈4B de Power em ≈2 dias) — o que reproduz")
	header({ "Hipótese", "⚡ saldo D2", "⚡ total D2", "R", "estágio", "⚔ golpe" })
	local cases = {
		{ "Casual 30 min/dia (perfil)", "Casual", {} },
		{ "Ativo 1,5 h/dia (perfil)", "Ativo", {} },
		{ "Ativo sem boss/boost", "Ativo", { BossJoin = 0, OthersKillBoss = 0 } },
		{ "30 min/dia, segura 30%, renasce ao poder", "Ativo", { HoursPerDay = 0.5, HoldShare = 0.3, RebirthAt = 1, Jitter = 0 } },
		{ "1 h/dia, segura 60%, renasce em 5×, sem boss", "Ativo", { HoursPerDay = 1, HoldShare = 0.6, RebirthAt = 5, BossJoin = 0, OthersKillBoss = 0, Jitter = 0 } },
		{ "4 h/dia sem nunca renascer, com passes", "Ativo", { HoursPerDay = 4, HoldShare = 0.9, RebirthAt = 1e12, Passes = { DoublePower = true, VIP = true, ExtraPets = true, AutoClick = true }, AutoClick = true, Jitter = 0 } },
		{ "Dono com passes, servidor sozinho", "DonoComPasses", {} },
	}
	for _, case in cases do
		local profile = profileFor(case[2], case[3])
		local st = Model.Run(profile, { Days = 2, Seed = 1 })
		local s = Model.Snapshot(st)
		print(row({ case[1], short(s.Power), short(s.TotalPower), tostring(s.Rebirths), tostring(s.Highest), short(s.Hit) }))
	end
end
