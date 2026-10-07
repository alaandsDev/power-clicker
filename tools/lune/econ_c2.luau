--[[
	econ_c2.luau — rodada C2 (curva longa refinada) da auditoria de economia.

	Duas etapas, para dividir o trabalho entre processos:

		lune run tools/lune/econ_c2.luau [raiz] compute <config> runs=500 out=<arquivo.json>
		lune run tools/lune/econ_c2.luau [raiz] extras runs=100 out=<arquivo.json>   (regen, sensibilidade, saves)
		lune run tools/lune/econ_c2.luau [raiz] report dir=<pasta dos json>

	<config> = ATUAL, C (original), ou um id de Scenarios.C2 (econ_scenarios).
	Só análise: o modelo aplica overrides na própria cópia das configs.
]]
local process = require("@lune/process")
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local root, mode, config, runs, out, dir = nil, nil, nil, 500, nil, nil
for _, arg in process.args do
	if string.sub(arg, 1, 5) == "runs=" then
		runs = tonumber(string.sub(arg, 6)) or runs
	elseif string.sub(arg, 1, 4) == "out=" then
		out = string.sub(arg, 5)
	elseif string.sub(arg, 1, 4) == "dir=" then
		dir = string.sub(arg, 5)
	elseif string.find(arg, "/") then
		root = arg
	elseif mode == nil then
		mode = arg
	else
		config = arg
	end
end

local E = require("./env")(root)
local Model = require("./econ_model")(E)
local Profiles = require("./econ_profiles")
local Scenarios = require("./econ_scenarios")
local Cfg, F = Model.Cfg, Model.F
local DAY = 86400
local ORDER = { "Casual", "Ativo", "MuitoAtivo", "Afk", "Otimizador" }
local HORIZON = { Casual = 180, Ativo = 90, MuitoAtivo = 60, Afk = 90, Otimizador = 60 }
local REBIRTHS = { 1, 2, 3, 5, 7, 10, 15, 20 }

local function overridesFor(id: string)
	if id == "ATUAL" then
		return {}
	elseif id == "C" then
		return Scenarios.C.Overrides
	end
	local c2 = Scenarios.C2[id]
	assert(c2, "config desconhecida: " .. tostring(id))
	return Scenarios.FromParams(c2.Params, Cfg.Wall.Stages)
end

local function profileFor(id: string, extra)
	local p = table.clone(Profiles[id])
	for k, v in extra or {} do
		p[k] = v
	end
	p.ComboAvg = p.ComboAvg or Model.ComboAverage(Cfg.Economy.Click.HoldClicksPerSecond, p.Burst, p.Pause)
	return p
end

local function keysWanted()
	local keys = {}
	for order = 1, #Cfg.Wall.Stages do
		table.insert(keys, "clear:" .. order)
	end
	for _, r in REBIRTHS do
		table.insert(keys, "rebirth:" .. r)
	end
	for _, k in { "ready1800:10", "ready600:10", "ready180:10" } do
		table.insert(keys, k)
	end
	return keys
end

-- Monte Carlo de um perfil: listas por marco (ativo s, calendário s) + extras.
local function mc(profileId: string, overrides, n: number, extra)
	local profile = profileFor(profileId, extra)
	local result = { N = n, Active = {}, Calendar = {}, Missing = {}, Arrive = {}, Ready600 = {}, Ready180 = {}, Fight180 = {}, KillRow = {}, KillFight = {} }
	for _, key in keysWanted() do
		result.Active[key], result.Calendar[key], result.Missing[key] = {}, {}, 0
	end
	for seed = 1, n do
		local st = Model.Run(profile, { Days = HORIZON[profileId], Seed = seed * 7919, StopWhen = "Colossus", Overrides = overrides })
		for _, key in keysWanted() do
			local m = st.Milestones[key]
			if m then
				table.insert(result.Active[key], m.Active)
				table.insert(result.Calendar[key], m.Calendar)
			else
				result.Missing[key] += 1
			end
		end
		local m9, r6, r18, k10 = st.Milestones["clear:9"], st.Milestones["ready600:10"], st.Milestones["ready180:10"], st.Milestones["clear:10"]
		if m9 and m9.NextPerRow then
			table.insert(result.Arrive, m9.NextPerRow)
		end
		if r6 then
			table.insert(result.Ready600, r6.PerRow)
		end
		if r18 then
			table.insert(result.Ready180, r18.PerRow)
			table.insert(result.Fight180, r18.Fight)
		end
		if k10 and k10.PerRow then
			table.insert(result.KillRow, k10.PerRow)
			table.insert(result.KillFight, k10.Fight)
		end
	end
	return result
end

-- D1…D90: saldo, golpe, R, pets, corte, melhorias, estágio, próximo objetivo (seed 1).
local SNAP_DAYS = { 1, 3, 7, 14, 30, 60, 90 }
local function snapshots(profileId: string, overrides)
	local marks = {}
	for _, d in SNAP_DAYS do
		table.insert(marks, d * DAY)
	end
	local st = Model.Run(profileFor(profileId), { Days = 90, Seed = 1, Overrides = overrides, CalendarMarks = marks })
	local list = {}
	for _, d in SNAP_DAYS do
		local s = st.Snapshots["C" .. d * DAY]
		if s then
			table.insert(list, {
				Day = d, Power = s.Power, Hit = s.Hit, Rebirths = s.Rebirths, Pet = s.PetMult, Cut = s.Cut, ClickStrength = s.ClickStrength,
				PowerBoost = s.PowerBoost, GemPower = s.GemPower, Highest = s.Highest, Frontier = s.Frontier, PerRow = s.FrontierHitsPerRow,
				Fight = s.FrontierSeconds, NextRebirth = s.NextRebirthCost,
			})
		end
	end
	return list
end

-- D7 do Ativo (sem parar no Colosso).
local function day7(overrides, n: number)
	local profile = profileFor("Ativo")
	local out = { Power = {}, Hit = {}, Rebirths = {} }
	for seed = 1, n do
		local st = Model.Run(profile, { Days = 7, Seed = seed * 7919, Overrides = overrides, CalendarMarks = { 7 * DAY } })
		local s = st.Snapshots["C" .. 7 * DAY]
		table.insert(out.Power, s.Power)
		table.insert(out.Hit, s.Hit)
		table.insert(out.Rebirths, s.Rebirths)
	end
	return out
end

-- ── compute ─────────────────────────────────────────────────────────────────
if mode == "compute" then
	local overrides = overridesFor(config)
	local data = { Config = config, Profiles = {}, Snapshots = {} }
	for _, id in ORDER do
		data.Profiles[id] = mc(id, overrides, runs)
		data.Snapshots[id] = snapshots(id, overrides)
	end
	data.Day7 = day7(overrides, math.max(runs // 5, 40))
	fs.writeFile(out, serde.encode("json", data))
	print("ok " .. config)
	process.exit(0)
end

-- ── extras: regeneração, sensibilidade, saves ───────────────────────────────
local function median(list)
	if not list or #list == 0 then
		return nil
	end
	local sorted = table.clone(list)
	table.sort(sorted)
	return sorted[math.max(1, math.ceil(#sorted / 2))]
end

local OLD = { Base = 200000, Growth = 3.2 }
local function oldCost(r)
	return OLD.Base * OLD.Growth ^ r
end

if mode == "extras" then
	local pick = Scenarios.C2[Scenarios.C2Pick]
	local p = pick.Params
	local base = Scenarios.FromParams(p, Cfg.Wall.Stages)
	local data = { Regen = {}, Sensitivity = {}, Saves = {} }

	-- Regeneração: jogador que RASPA a sessão inteira (pior caso) e o Ativo normal.
	local regens = {
		{ "sem regeneração", { Mode = "none" } },
		{ "reset após 60 s sem golpe", { Mode = "reset", After = 60 } },
		{ "lenta após 30 s (1%/s)", { Mode = "slow", After = 30, Rate = 0.01 } },
	}
	for _, regen in regens do
		local o = table.clone(base)
		o.Regen = regen[2]
		for _, who in { { "Ativo", {} }, { "Ativo que raspa", { ChipsBeyondPatience = true } } } do
			local r = mc("Ativo", o, runs, who[2])
			table.insert(data.Regen, { Regen = regen[1], Who = who[1], Kill = median(r.Calendar["clear:10"]), KillActive = median(r.Active["clear:10"]),
				S9 = median(r.Calendar["clear:9"]), KillRow = median(r.KillRow), KillFight = median(r.KillFight) })
		end
	end

	-- Sensibilidade: um parâmetro por vez.
	local variants = {
		{ "base", {} },
		{ "Rebirth BaseCost −20%", { Base = p.Base * 0.8 } },
		{ "Rebirth BaseCost +20%", { Base = p.Base * 1.2 } },
		{ "Rebirth Growth −10%", { Growth = p.Growth * 0.9 } },
		{ "Rebirth Growth +10%", { Growth = p.Growth * 1.1 } },
		{ "Ovo Místico −20%", { Mystic = p.Mystic * 0.8 } },
		{ "Ovo Místico +20%", { Mystic = p.Mystic * 1.2 } },
		{ "Ovo do Caminho −20%", { Tower = p.Tower * 0.8 } },
		{ "Ovo do Caminho +20%", { Tower = p.Tower * 1.2 } },
		{ "HP 7–10 −20%", { Hp7 = p.Hp7 * 0.8, Hp8 = p.Hp8 * 0.8, Hp9 = p.Hp9 * 0.8, Hp10 = p.Hp10 * 0.8 } },
		{ "HP 7–10 +20%", { Hp7 = p.Hp7 * 1.2, Hp8 = p.Hp8 * 1.2, Hp9 = p.Hp9 * 1.2, Hp10 = p.Hp10 * 1.2 } },
		{ "estágios 5/6 = ×2 / ×4 (C original)", { Hp5 = 2, Hp6 = 4 } },
		{ "estágios 5/6 = ×1 / ×2", { Hp5 = 1, Hp6 = 2 } },
		{ "estágios 5/6 = ×1,5 / ×2,5", { Hp5 = 1.5, Hp6 = 2.5 } },
		{ "Boss 3 min", { Boss = 180 } },
		{ "Boss 5 min", { Boss = 300 } },
		{ "Boss 7 min", { Boss = 420 } },
		{ "Místico 300", { Mystic = 300 } },
		{ "Místico 350", { Mystic = 350 } },
		{ "Místico 400", { Mystic = 400 } },
		{ "Místico 150 (sem mudança)", { Mystic = 150 } },
		{ "Caminho 800", { Tower = 800 } },
		{ "Caminho 1.000", { Tower = 1000 } },
		{ "Caminho 1.200", { Tower = 1200 } },
		{ "Caminho 400 (sem mudança)", { Tower = 400 } },
		{ "Colosso 8 fileiras (mesmo HP total)", { Rows10 = 8 } },
		{ "Colosso 10 fileiras", { Rows10 = 10 } },
		{ "Colosso 12 fileiras (mesmo HP total)", { Rows10 = 12 } },
	}
	for _, v in variants do
		local params = table.clone(p)
		for k, value in v[2] do
			params[k] = value
		end
		local o = Scenarios.FromParams(params, Cfg.Wall.Stages)
		local row = { Name = v[1] }
		for _, id in { "Ativo", "Casual" } do
			local r = mc(id, o, runs)
			row[id] = { S7 = median(r.Calendar["clear:7"]), S9 = median(r.Calendar["clear:9"]), Kill = median(r.Calendar["clear:10"]), Ready = median(r.Calendar["ready180:10"]),
				R1 = median(r.Active["rebirth:1"]), ReadyRow = median(r.Ready180), KillRow = median(r.KillRow) }
		end
		table.insert(data.Sensitivity, row)
	end

	-- Saves sintéticos no primeiro login após o C2, com cada regra de custo.
	local newCost = function(r)
		return p.Base * p.Growth ^ r
	end
	local rules = {
		{ "jogo de hoje (curva antiga)", function(_anchor)
			return oldCost
		end },
		{ "sem regra (curva nova direto)", function(_anchor)
			return newCost
		end },
		{ "A) âncora fixa", function(anchor)
			if anchor <= 0 then
				return newCost
			end
			return function(r)
				return if r < anchor then oldCost(r) else oldCost(anchor) * p.Growth ^ (r - anchor)
			end
		end },
		{ "B) custo híbrido global (nova até R12, ×3,2 depois)", function(_anchor)
			return function(r)
				return if r <= 12 then newCost(r) else newCost(12) * 3.2 ^ (r - 12)
			end
		end },
		{ "C) curva antiga para saves existentes", function(anchor)
			return if anchor > 0 then oldCost else newCost
		end },
		{ "D) âncora convergente (×1,3 do crescimento)", function(anchor)
			if anchor <= 0 then
				return newCost
			end
			return function(r)
				return if r < anchor then oldCost(r) else math.min(newCost(r), oldCost(anchor) * (p.Growth * 1.3) ^ (r - anchor))
			end
		end },
	}
	local function cutIndex(id)
		local list = {}
		for _, c in Cfg.Cut.Cuts do
			table.insert(list, c)
		end
		table.sort(list, function(a, b)
			return a.Order < b.Order
		end)
		for i, c in list do
			if c.Id == id then
				return i
			end
		end
		return 1
	end
	local saves = {
		{ Name = "NEW (R0, sem pets)", R = 0, Pets = {}, Cut = "Cut1", Wins = 0, Cleared = 0, Power = 0 },
		{ Name = "MID (R5)", R = 5, Pets = { 2, 2, 1, 1, 0.6, 0.5 }, Cut = "Cut5", Wins = 400, Cleared = 6, Power = 3e7 },
		{ Name = "NOSSO CASO (R7, ~4B, estágio 8)", R = 7, Pets = { 5, 2, 2, 2, 1, 1 }, Cut = "Cut6", Wins = 1300, Cleared = 8, Power = 4e9 },
		{ Name = "VETERANO (R15)", R = 15, Pets = { 12, 6, 6, 4, 4, 4 }, Cut = "Cut8", Wins = 18603, Cleared = 10, Power = 2e12 },
		{ Name = "VETERANO FORTE (R20)", R = 20, Pets = { 35, 12, 12, 6, 6, 6 }, Cut = "Cut8", Wins = 18603, Cleared = 10, Power = 5e14 },
		{ Name = "ENDGAME (R27, pets do Colosso)", R = 27, Pets = { 90, 45, 30, 30, 15, 15 }, Cut = "Cut8", Wins = 18603, Cleared = 10, Power = 1e18, Aura = 4, Runes = { [4] = 3 } },
	}
	for _, save in saves do
		local entry = { Name = save.Name, Rules = {} }
		local function init(st)
			st.Rebirths = save.R
			st.Pets = table.clone(save.Pets)
			st.CutIndex = cutIndex(save.Cut)
			st.Wins = save.Wins
			st.Power = save.Power
			st.AuraIndex = save.Aura or 1
			st.Runes = save.Runes or {}
			for order = 1, save.Cleared do
				st.Cleared[order] = true
			end
			st.Highest = save.Cleared
			st.Perm.PetSlots = if save.R >= 5 then 3 else 0
			st.Dirty = true
		end
		for _, rule in rules do
			local costFn = rule[2](save.R)
			local o = if rule[1] == "jogo de hoje (curva antiga)" then {} else base
			local st = Model.Run(profileFor("Ativo", { Jitter = 0, HoldJitter = 0 }), { Days = 7, Seed = 1, Overrides = o, Init = function(s)
				init(s)
				s.CostFn = costFn
			end, CalendarMarks = { DAY } })
			local first = st.Milestones["rebirth:" .. (save.R + 1)]
			local d1 = st.Snapshots["C" .. DAY]
			table.insert(entry.Rules, {
				Rule = rule[1], NextCost = costFn(save.R), NextActive = first and first.Active, RebirthsD1 = d1 and d1.Rebirths, RebirthsD7 = st.Rebirths,
				Highest = st.Highest, Hit = d1 and d1.Hit,
			})
		end
		-- barreira seguinte / Colosso no 1º login com o HP do C2
		local st0 = Model.NewState(profileFor("Ativo"), { Seed = 1, Overrides = base })
		init(st0)
		st0.Dirty = true
		local hit = Model.Hit(st0)
		local order = math.min(save.Cleared + 1, #Cfg.Wall.Stages)
		entry.NextStage = order
		entry.NextPerRow = math.ceil(Model.StageOf(st0, order).Hp / math.max(hit, 1e-9))
		entry.ColossusPerRow = math.ceil(Model.StageOf(st0, #Cfg.Wall.Stages).Hp / math.max(hit, 1e-9))
		entry.Hit = hit
		table.insert(data.Saves, entry)
	end
	fs.writeFile(out, serde.encode("json", data))
	print("ok extras")
	process.exit(0)
end

-- ── report ──────────────────────────────────────────────────────────────────
if mode ~= "report" then
	print("uso: compute <config> | extras | report")
	process.exit(1)
end

local function load(name)
	local path = dir .. "/" .. name .. ".json"
	if not fs.isFile(path) then
		return nil
	end
	return serde.decode("json", fs.readFile(path))
end

local function short(x)
	if x == nil then
		return "—"
	end
	for _, u in { { 1e18, "Qi" }, { 1e15, "Qa" }, { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } } do
		if math.abs(x) >= u[1] then
			return string.format("%.1f%s", x / u[1], u[2])
		end
	end
	return string.format("%.0f", x)
end
local function hrs(s)
	if s == nil then
		return "—"
	end
	if s < 3600 then
		return string.format("%.0f min", s / 60)
	end
	return string.format("%.1f h", s / 3600)
end
local function dayOf(s)
	if s == nil then
		return "—"
	end
	return "D" .. (math.floor(s / DAY) + 1)
end
local function pct(list, missing, n, q)
	if not list then
		return nil
	end
	local needed = math.ceil(q * n)
	if #list < needed then
		return nil -- fora do horizonte
	end
	local sorted = table.clone(list)
	table.sort(sorted)
	return sorted[needed]
end
local function row(cells)
	print("| " .. table.concat(cells, " | ") .. " |")
end
local function header(cells)
	row(cells)
	local dashes = {}
	for _ in cells do
		table.insert(dashes, "---")
	end
	row(dashes)
end
local function section(t)
	print("")
	print("## " .. t)
	print("")
end
local NAMES = { Casual = "Casual", Ativo = "Ativo", MuitoAtivo = "Muito ativo", Afk = "AFK", Otimizador = "Otimizador" }

local function cell(data, profile, key, q, horizon)
	local p = data.Profiles[profile]
	local a = pct(p.Active[key], p.Missing[key], p.N, q)
	local c = pct(p.Calendar[key], p.Missing[key], p.N, q)
	if not a then
		return string.format(">%dd", horizon or HORIZON[profile])
	end
	return hrs(a) .. " · " .. dayOf(c)
end

local configs = { "ATUAL", "C" }
for _, id in Scenarios.C2Order do
	table.insert(configs, id)
end
local loaded = {}
for _, id in configs do
	loaded[id] = load(id)
end
local pickId = Scenarios.C2Pick
local pick = loaded[pickId]

-- Finalistas lado a lado (P50)
section("Finalistas — P50 (tempo ativo · calendário), " .. tostring(pick and pick.Profiles.Ativo.N or "?") .. " execuções")
local cols = { "Marco" }
for _, id in configs do
	if loaded[id] then
		table.insert(cols, id)
	end
end
header(cols)
local lines = {
	{ "Casual", "clear:5" }, { "Casual", "clear:6" }, { "Casual", "clear:7" }, { "Casual", "clear:8" }, { "Casual", "clear:9" }, { "Casual", "clear:10" },
	{ "Ativo", "clear:6" }, { "Ativo", "clear:7" }, { "Ativo", "clear:8" }, { "Ativo", "clear:9" }, { "Ativo", "ready180:10" }, { "Ativo", "clear:10" },
	{ "MuitoAtivo", "clear:10" }, { "Afk", "clear:10" }, { "Otimizador", "clear:10" },
	{ "Ativo", "rebirth:1" }, { "Casual", "rebirth:1" },
}
for _, l in lines do
	local label = string.format("%s %s", NAMES[l[1]], (string.gsub(string.gsub(l[2], "clear:10", "mata Colosso"), "ready180:10", "Colosso pronto (≤3 min)")))
	local cells = { label }
	for _, id in configs do
		if loaded[id] then
			table.insert(cells, cell(loaded[id], l[1], l[2], 0.5))
		end
	end
	row(cells)
end

if not pick then
	process.exit(0)
end

-- Progressão por perfil (C2 escolhido)
for _, profile in ORDER do
	section(string.format("Curva %s — %s (P25 / P50 / P75 / P90; tempo ativo · calendário)", NAMES[profile], pickId))
	header({ "Marco", "P25", "P50", "P75", "P90", "ATUAL P50" })
	for order = 1, #Cfg.Wall.Stages do
		local key = "clear:" .. order
		local label = if order == 10 then "mata o Colosso" elseif order == 9 then "Stage 9 = chega ao 10" else "Stage " .. order
		row({ label, cell(pick, profile, key, 0.25), cell(pick, profile, key, 0.5), cell(pick, profile, key, 0.75), cell(pick, profile, key, 0.9), loaded.ATUAL and cell(loaded.ATUAL, profile, key, 0.5) or "—" })
	end
	row({ "Colosso pronto (luta ≤ 3 min)", cell(pick, profile, "ready180:10", 0.25), cell(pick, profile, "ready180:10", 0.5), cell(pick, profile, "ready180:10", 0.75), cell(pick, profile, "ready180:10", 0.9), "—" })
end

-- Renascimentos
section("Renascimentos — P50 (tempo ativo · calendário)")
local rcols = { "Perfil", "Config" }
for _, r in REBIRTHS do
	table.insert(rcols, "R" .. r)
end
header(rcols)
for _, profile in ORDER do
	for _, id in { "ATUAL", "C", pickId } do
		local d = loaded[id]
		if d then
			local cells = { NAMES[profile], id }
			for _, r in REBIRTHS do
				table.insert(cells, cell(d, profile, "rebirth:" .. r, 0.5))
			end
			row(cells)
		end
	end
end

-- Colosso nos 3 estados (Ativo)
section("Colosso nos três estados — Ativo (medianas)")
header({ "Config", "ao chegar (golpes/fileira)", "preparando: luta ≤ 10 min (golpes/fileira)", "pronto: luta ≤ 3 min (golpes/fileira)", "luta pronta", "quando mata: golpes/fileira", "luta ao matar", "dia pronto", "dia que mata" })
for _, id in configs do
	local d = loaded[id]
	if d then
		local a = d.Profiles.Ativo
		row({ id, short(median(a.Arrive)), short(median(a.Ready600)), short(median(a.Ready180)), hrs(median(a.Fight180)), short(median(a.KillRow)), hrs(median(a.KillFight)),
			dayOf(median(a.Calendar["ready180:10"])), dayOf(median(a.Calendar["clear:10"])) })
	end
end

-- Snapshots
section("Snapshots — " .. pickId .. " (seed 1)")
header({ "Perfil", "Dia", "⚡ saldo", "⚔ golpe", "R", "Pets ×", "Corte", "Click Str / Power Boost / Eternal", "Estágio", "Próximo objetivo" })
for _, profile in ORDER do
	for _, s in pick.Snapshots[profile] do
		local goal = if s.Frontier
			then string.format("barreira %d: ≈%s golpes/fileira (luta %s)", s.Frontier, short(s.PerRow), hrs(s.Fight))
			else "Colosso vencido; renascer: " .. short(s.NextRebirth)
		row({ NAMES[profile], "D" .. s.Day, short(s.Power), short(s.Hit), tostring(s.Rebirths), string.format("×%.1f", s.Pet), s.Cut,
			string.format("%d / %d / %d", s.ClickStrength, s.PowerBoost, s.GemPower), tostring(s.Highest), goal })
	end
end

-- Extras
local extras = load("extras")
if extras then
	section("Regeneração (" .. pickId .. ", Ativo)")
	header({ "Regra", "Jogador", "Stage 9", "mata Colosso", "golpes/fileira ao matar", "luta ao matar" })
	for _, r in extras.Regen do
		row({ r.Regen, r.Who, dayOf(r.S9), dayOf(r.Kill) .. " (" .. hrs(r.KillActive) .. ")", short(r.KillRow), hrs(r.KillFight) })
	end

	section("Sensibilidade (" .. pickId .. ", P50 calendário)")
	header({ "Variação", "Ativo R1", "Ativo 7", "Ativo 9", "Ativo pronto", "Ativo mata", "golpes/fileira pronto", "golpes/fileira ao matar", "Casual R1", "Casual 7", "Casual 9", "Casual mata" })
	for _, s in extras.Sensitivity do
		row({ s.Name, hrs(s.Ativo.R1), dayOf(s.Ativo.S7), dayOf(s.Ativo.S9), dayOf(s.Ativo.Ready), dayOf(s.Ativo.Kill), short(s.Ativo.ReadyRow), short(s.Ativo.KillRow),
			hrs(s.Casual.R1), dayOf(s.Casual.S7), dayOf(s.Casual.S9), dayOf(s.Casual.Kill) })
	end

	section("Saves existentes no 1º login após o " .. pickId)
	header({ "Save", "⚔ golpe", "próxima barreira (golpes/fileira)", "Colosso (golpes/fileira)", "Regra de custo", "próximo renascimento custa", "chega nele em", "R no D1", "R no D7" })
	for _, s in extras.Saves do
		for i, r in s.Rules do
			row({ if i == 1 then s.Name else "", if i == 1 then short(s.Hit) else "", if i == 1 then string.format("%d: %s", s.NextStage, short(s.NextPerRow)) else "",
				if i == 1 then short(s.ColossusPerRow) else "", r.Rule, short(r.NextCost), r.NextActive and hrs(r.NextActive) or ">7 dias", tostring(r.RebirthsD1), tostring(r.RebirthsD7) })
		end
	end
end

-- Tabela final
section("TABELA FINAL — ATUAL | C original | " .. pickId)
local final = { "ATUAL", "C", pickId }
header({ "Linha", "ATUAL", "C ORIGINAL", pickId })
local function frow(label, fn)
	local cells = { label }
	for _, id in final do
		table.insert(cells, if loaded[id] then fn(loaded[id]) else "—")
	end
	row(cells)
end
for _, l in {
	{ "Casual Stage 5", "Casual", "clear:5" }, { "Casual Stage 6", "Casual", "clear:6" }, { "Casual Stage 7", "Casual", "clear:7" }, { "Casual Stage 8", "Casual", "clear:8" },
	{ "Casual Stage 9", "Casual", "clear:9" }, { "Casual Colosso", "Casual", "clear:10" },
	{ "Ativo Stage 6", "Ativo", "clear:6" }, { "Ativo Stage 7", "Ativo", "clear:7" }, { "Ativo Stage 8", "Ativo", "clear:8" }, { "Ativo Stage 9", "Ativo", "clear:9" },
	{ "Ativo chega 10", "Ativo", "clear:9" }, { "Ativo mata Colosso", "Ativo", "clear:10" }, { "Ativo Colosso pronto (≤3 min)", "Ativo", "ready180:10" },
	{ "Muito ativo mata Colosso", "MuitoAtivo", "clear:10" }, { "AFK mata Colosso", "Afk", "clear:10" }, { "Otimizador mata Colosso", "Otimizador", "clear:10" },
	{ "R1 Ativo", "Ativo", "rebirth:1" }, { "R3 Ativo", "Ativo", "rebirth:3" }, { "R5 Ativo", "Ativo", "rebirth:5" }, { "R10 Ativo", "Ativo", "rebirth:10" },
} do
	frow(l[1], function(d)
		return cell(d, l[2], l[3], 0.5)
	end)
end
frow("Dano Ativo D7 (⚔ golpe P50)", function(d)
	return short(median(d.Day7.Hit))
end)
frow("Power Ativo D7 (⚡ saldo P50)", function(d)
	return short(median(d.Day7.Power))
end)
frow("Rebirth Ativo D7 (P50)", function(d)
	return tostring(median(d.Day7.Rebirths))
end)
frow("Colosso: golpes/fileira ao chegar", function(d)
	return short(median(d.Profiles.Ativo.Arrive))
end)
frow("Colosso: golpes/fileira preparando (luta ≤10 min)", function(d)
	return short(median(d.Profiles.Ativo.Ready600))
end)
frow("Colosso: golpes/fileira pronto (luta ≤3 min)", function(d)
	return short(median(d.Profiles.Ativo.Ready180))
end)
frow("Colosso: tempo de luta pronto", function(d)
	return hrs(median(d.Profiles.Ativo.Fight180))
end)
frow("Colosso: golpes/fileira quando o Ativo mata", function(d)
	return short(median(d.Profiles.Ativo.KillRow))
end)
