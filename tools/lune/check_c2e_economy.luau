--[[
	check_c2e_economy.luau — a economia do JOGO (configs reais, sem override)
	continua perto do baseline C2-E aprovado (relatório C2, Monte Carlo 500).

		lune run tools/lune/check_c2e_economy.luau [raiz] [runs=120]

	O simulador lê as configs reais (RebirthConfig, WallConfig, EggConfig,
	EventConfig...): se a implementação divergir do aprovado, os marcos se
	afastam do baseline. Não é para "acertar o dia": as faixas são largas
	(variância do Monte Carlo) e só pegam divergência grande.
]]
local process = require("@lune/process")
local runs = 120
for _, arg in process.args do
	if string.sub(arg, 1, 5) == "runs=" then
		runs = tonumber(string.sub(arg, 6)) or runs
	end
end
local root = nil
for _, arg in process.args do
	if string.find(arg, "/") then
		root = arg
	end
end

local E = require("./env")(root)
local Model = require("./econ_model")(E)
local Profiles = require("./econ_profiles")
local Cfg = Model.Cfg
local DAY = 86400

local problems = {}
local function check(condition: any, message: string)
	if condition then
		print("OK   " .. message)
	else
		table.insert(problems, message)
		print("FALHA " .. message)
	end
end

--[[
	Baseline C2-E aprovado (P50, 500 execuções, relatorio_C2.md):
	valor = dias de calendário (D = valor + 1) ou minutos ativos (R*).
	Faixa aceita: [min, max] — largas de propósito.
]]
local BASELINE = {
	Ativo = {
		{ "clear:6", "cal", 0, { 0, 1 } }, -- D1
		{ "clear:7", "cal", 1, { 0, 3 } }, -- D2
		{ "clear:8", "cal", 2, { 1, 5 } }, -- D3
		{ "clear:9", "cal", 5, { 3, 9 } }, -- D6
		{ "clear:10", "cal", 18, { 11, 28 } }, -- D19
		{ "ready180:10", "cal", 28, { 19, 40 } }, -- D29
		{ "rebirth:1", "min", 12, { 8, 18 } },
		{ "rebirth:2", "min", 26, { 18, 38 } },
		{ "rebirth:3", "min", 41, { 28, 60 } },
		{ "rebirth:5", "min", 132, { 90, 190 } },
		{ "rebirth:10", "min", 900, { 600, 1300 } },
	},
	Casual = {
		{ "clear:5", "cal", 1, { 0, 3 } }, -- D2
		{ "clear:6", "cal", 4, { 2, 7 } }, -- D5
		{ "clear:7", "cal", 9, { 6, 14 } }, -- D10
		{ "clear:8", "cal", 33, { 22, 46 } }, -- D34
		{ "clear:9", "cal", 75, { 52, 110 } }, -- D76
	},
}
local HORIZON = { Ativo = 90, Casual = 160 }

for id, list in BASELINE do
	local profile = table.clone(Profiles[id])
	profile.ComboAvg = Model.ComboAverage(Cfg.Economy.Click.HoldClicksPerSecond, profile.Burst, profile.Pause)
	local values = {}
	for _, item in list do
		values[item[1]] = {}
	end
	for seed = 1, runs do
		local st = Model.Run(profile, { Days = HORIZON[id], Seed = seed * 7919, StopWhen = if id == "Ativo" then "Colossus" else nil })
		for _, item in list do
			local m = st.Milestones[item[1]]
			if m then
				table.insert(values[item[1]], if item[2] == "cal" then m.Calendar / DAY else m.Active / 60)
			end
		end
	end
	for _, item in list do
		local list2 = values[item[1]]
		table.sort(list2)
		local median = if #list2 * 2 >= runs then list2[math.ceil(#list2 / 2)] else nil
		local unit = if item[2] == "cal" then "dias" else "min"
		check(median ~= nil and median >= item[4][1] and median <= item[4][2],
			string.format("%s %s: P50 %s %s (baseline %s; faixa %s–%s)", id, item[1], if median then string.format("%.1f", median) else "fora do horizonte", unit, tostring(item[3]), tostring(item[4][1]), tostring(item[4][2])))
	end
end

print("")
if #problems > 0 then
	print(string.format("FALHOU: %d marco(s) longe do baseline C2-E", #problems))
	process.exit(1)
end
print(string.format("OK: economia do jogo (configs reais) dentro das faixas do baseline C2-E (%d execuções por perfil).", runs))
process.exit(0)
