--[[
	econ_search.luau — busca automática de parâmetros para o cenário C2.

		lune run tools/lune/econ_search.luau [raiz] [start=C|TwoA|TwoB|TwoC] [seeds=8] [evals=120]

	Descida por coordenadas numa grade discreta: a cada passo tenta o vizinho
	de cada parâmetro (índice ±1) e fica com o que baixa a pontuação. A
	pontuação é a distância (em log) às JANELAS-alvo de design — fora da
	janela custa, dentro não — somada às penalidades (1º renascimento lento,
	luta "pronta" do Colosso fora de 25–100 golpes/fileira, Otimizador
	zerando cedo demais). Nada disto muda o jogo: é o econ_model com
	overrides.

	Reprodutível: seeds fixas por perfil; avaliações em cache.
]]
local process = require("@lune/process")

local root, start, seeds, maxEvals = nil, "C", 8, 120
for _, arg in process.args do
	if string.sub(arg, 1, 6) == "start=" then
		start = string.sub(arg, 7)
	elseif string.sub(arg, 1, 6) == "seeds=" then
		seeds = tonumber(string.sub(arg, 7)) or seeds
	elseif string.sub(arg, 1, 6) == "evals=" then
		maxEvals = tonumber(string.sub(arg, 7)) or maxEvals
	elseif string.find(arg, "/") then
		root = arg
	end
end

local E = require("./env")(root)
local Model = require("./econ_model")(E)
local Profiles = require("./econ_profiles")
local Cfg = Model.Cfg

-- ── Grade ───────────────────────────────────────────────────────────────────
local GRID = {
	{ Key = "Base", Values = { 2e5, 5e5, 1e6, 2e6, 5e6, 1e7, 2e7 } },
	{ Key = "Early", Values = { 2.5, 3.2, 4 } },
	{ Key = "Knee", Values = { 0, 3, 4, 5, 6 } }, -- 0 = curva de uma fase (Base × Growth^r)
	{ Key = "Growth", Values = { 4.0, 4.25, 4.5, 4.75, 5.0, 5.5, 6.0 } },
	{ Key = "Hp5", Values = { 1, 1.25, 1.5, 2 } },
	{ Key = "Hp6", Values = { 1.5, 2, 2.5, 3, 4 } },
	{ Key = "Hp7", Values = { 3, 4, 5, 6, 8, 10 } },
	{ Key = "Hp8", Values = { 5, 7, 10, 14, 20 } },
	{ Key = "Hp9", Values = { 6, 9, 12, 16, 24, 32 } },
	{ Key = "Hp10", Values = { 10, 15, 20, 30, 40, 60, 80, 120 } },
	{ Key = "Rows7", Values = { 5, 6 } },
	{ Key = "Rows8", Values = { 6, 7 } },
	{ Key = "Rows9", Values = { 6, 8 } },
	{ Key = "Rows10", Values = { 8, 10, 12 } },
	{ Key = "Mystic", Values = { 150, 250, 300, 350, 400 } },
	{ Key = "Tower", Values = { 400, 800, 1000, 1200 } },
	{ Key = "Boss", Values = { 180, 300, 420 } },
}

local STARTS = {
	C = { Base = 2e7, Early = 3.2, Knee = 0, Growth = 4.5, Hp5 = 2, Hp6 = 4, Hp7 = 6, Hp8 = 10, Hp9 = 12, Hp10 = 40, Rows7 = 6, Rows8 = 7, Rows9 = 8, Rows10 = 10, Mystic = 400, Tower = 1200, Boss = 300 },
	TwoA = { Base = 5e5, Early = 3.2, Knee = 3, Growth = 4.75, Hp5 = 1.5, Hp6 = 2.5, Hp7 = 5, Hp8 = 10, Hp9 = 16, Hp10 = 80, Rows7 = 5, Rows8 = 6, Rows9 = 6, Rows10 = 10, Mystic = 300, Tower = 800, Boss = 300 },
	TwoB = { Base = 1e6, Early = 2.5, Knee = 4, Growth = 5.0, Hp5 = 1, Hp6 = 2, Hp7 = 5, Hp8 = 10, Hp9 = 16, Hp10 = 80, Rows7 = 5, Rows8 = 6, Rows9 = 6, Rows10 = 10, Mystic = 300, Tower = 1000, Boss = 300 },
	TwoC = { Base = 2e5, Early = 3.2, Knee = 5, Growth = 5.5, Hp5 = 1, Hp6 = 2, Hp7 = 4, Hp8 = 7, Hp9 = 12, Hp10 = 60, Rows7 = 5, Rows8 = 6, Rows9 = 6, Rows10 = 10, Mystic = 300, Tower = 800, Boss = 300 },
}

local Scenarios = require("./econ_scenarios")
local function overridesOf(p)
	return Scenarios.FromParams(p, Cfg.Wall.Stages)
end
Model.SearchOverridesOf = overridesOf

-- ── Avaliação ───────────────────────────────────────────────────────────────
local DAY = 86400
local function profile(id)
	local p = table.clone(Profiles[id])
	p.ComboAvg = Model.ComboAverage(Cfg.Economy.Click.HoldClicksPerSecond, p.Burst, p.Pause)
	return p
end
local PROFILES = { Casual = profile("Casual"), Ativo = profile("Ativo"), MuitoAtivo = profile("MuitoAtivo"), Otimizador = profile("Otimizador") }
local HORIZON = { Casual = 150, Ativo = 70, MuitoAtivo = 30, Otimizador = 30 }
local SEEDS = { Casual = seeds, Ativo = seeds, MuitoAtivo = math.max(seeds // 2, 3), Otimizador = math.max(seeds // 2, 3) }

local function median(list)
	table.sort(list)
	return list[math.max(1, math.ceil(#list / 2))]
end

local function metrics(overrides)
	local out = {}
	for id, p in PROFILES do
		local cal, act = {}, {}
		for seed = 1, SEEDS[id] do
			local st = Model.Run(p, { Days = HORIZON[id], Seed = seed * 7919, StopWhen = "Colossus", Overrides = overrides })
			for key, m in st.Milestones do
				cal[key] = cal[key] or {}
				act[key] = act[key] or {}
				table.insert(cal[key], m.Calendar / DAY)
				table.insert(act[key], m.Active / 60)
				if key == "ready180:10" then
					cal["perRow10"] = cal["perRow10"] or {}
					table.insert(cal["perRow10"], m.PerRow)
				end
			end
		end
		local m = { Cal = {}, Act = {} }
		for key, list in cal do
			-- marco que nem metade alcançou = fora do horizonte
			if #list * 2 >= SEEDS[id] then
				m.Cal[key] = median(list)
				m.Act[key] = act[key] and median(act[key])
			end
		end
		out[id] = m
	end
	return out
end

local function outside(x: number?, lo: number, hi: number, horizon: number): number
	local value = x or horizon * 1.3
	if value < lo then
		return math.log(lo / math.max(value, 0.01))
	elseif value > hi then
		return math.log(value / hi)
	end
	return 0
end

local TARGETS = {
	Casual = { { "clear:4", 0, 1 }, { "clear:5", 2, 4 }, { "clear:6", 5, 9 }, { "clear:7", 10, 16 }, { "clear:8", 25, 35 }, { "clear:9", 45, 75 }, { "clear:10", 60, 130, 0.5 } },
	Ativo = { { "clear:6", 0, 1.5 }, { "clear:7", 2, 4 }, { "clear:8", 4.5, 7.5 }, { "clear:9", 7.5, 12.5 }, { "ready180:10", 24, 35 }, { "clear:10", 22, 35 } },
	MuitoAtivo = { { "clear:10", 4.5, 8.5 } },
	Otimizador = { { "clear:10", 2.5, 5.5 } },
}

local function score(m)
	local total, parts = 0, {}
	for id, list in TARGETS do
		for _, t in list do
			local d = outside(m[id].Cal[t[1]], t[2], t[3], HORIZON[id]) * (t[4] or 1)
			total += d
			if d > 0 then
				table.insert(parts, string.format("%s.%s=%.2f", id, t[1], d))
			end
		end
	end
	--[[
		Renascimentos iniciais = apresentação do sistema (penalidade FORTE):
		Ativo R1 10–20 min, R2 25–45 min, R3 45–90 min de jogo ativo;
		Casual R1 ainda no D1 / começo do D2.
	]]
	local pen = 3 * outside(m.Ativo.Act["rebirth:1"], 10, 20, 999)
		+ 2 * outside(m.Ativo.Act["rebirth:2"], 25, 45, 999)
		+ 2 * outside(m.Ativo.Act["rebirth:3"], 45, 90, 999)
		+ 3 * outside(m.Casual.Cal["rebirth:1"], 0, 1.3, 30)
	-- Colosso pronto: 25–100 golpes por fileira.
	local perRow = m.Ativo.Cal["perRow10"]
	pen += outside(perRow, 25, 100, 1000) * 0.5
	if pen > 0 then
		table.insert(parts, string.format("pen=%.2f", pen))
	end
	return total + pen, table.concat(parts, " ")
end

local cache, evals = {}, 0
local function keyOf(p)
	local parts = {}
	for _, g in GRID do
		table.insert(parts, tostring(p[g.Key]))
	end
	return table.concat(parts, ",")
end
local function evaluate(p)
	local key = keyOf(p)
	if not cache[key] then
		evals += 1
		local m = metrics(overridesOf(p))
		local s, why = score(m)
		cache[key] = { Score = s, Why = why, M = m }
	end
	return cache[key]
end

local function describe(p, r)
	local m = r.M
	local function d(id, key)
		local v = m[id].Cal[key]
		return if v then string.format("D%.0f", v + 1) else "—"
	end
	return string.format("score=%.3f | Casual 5:%s 6:%s 7:%s 8:%s 9:%s 10:%s | Ativo 6:%s 7:%s 8:%s 9:%s pronto:%s mata:%s | MA %s | Otim %s | R1 ativo %.0fm casual %.0fm | ready/fileira %s",
		r.Score, d("Casual", "clear:5"), d("Casual", "clear:6"), d("Casual", "clear:7"), d("Casual", "clear:8"), d("Casual", "clear:9"), d("Casual", "clear:10"),
		d("Ativo", "clear:6"), d("Ativo", "clear:7"), d("Ativo", "clear:8"), d("Ativo", "clear:9"), d("Ativo", "ready180:10"), d("Ativo", "clear:10"),
		d("MuitoAtivo", "clear:10"), d("Otimizador", "clear:10"), m.Ativo.Act["rebirth:1"] or -1, m.Casual.Act["rebirth:1"] or -1, tostring(m.Ativo.Cal["perRow10"])) .. string.format(" | R2 %.0fm R3 %.0fm | casual R1 %s", m.Ativo.Act["rebirth:2"] or -1, m.Ativo.Act["rebirth:3"] or -1, d("Casual", "rebirth:1"))
end

local function literal(p)
	local parts = {}
	for _, g in GRID do
		table.insert(parts, string.format("%s = %s", g.Key, tostring(p[g.Key])))
	end
	return "{ " .. table.concat(parts, ", ") .. " }"
end

-- ── Descida por coordenadas ─────────────────────────────────────────────────
local current = table.clone(STARTS[start] or STARTS.C)
local best = evaluate(current)
print(string.format("[start %s] %s", start, describe(current, best)))
print("  " .. best.Why)
local improved = true
while improved and evals < maxEvals do
	improved = false
	for _, g in GRID do
		local index = table.find(g.Values, current[g.Key]) or 1
		for _, step in { -1, 1 } do
			local nextIndex = index + step
			if g.Values[nextIndex] and evals < maxEvals then
				local candidate = table.clone(current)
				candidate[g.Key] = g.Values[nextIndex]
				local r = evaluate(candidate)
				if r.Score < best.Score - 1e-6 then
					current, best, improved = candidate, r, true
					index = nextIndex
					print(string.format("[%3d] %s=%s %s", evals, g.Key, tostring(g.Values[nextIndex]), describe(current, best)))
				end
			end
		end
	end
end
print("")
print("MELHOR (" .. start .. "): " .. literal(current))
print(describe(current, best))
print("  " .. best.Why)
