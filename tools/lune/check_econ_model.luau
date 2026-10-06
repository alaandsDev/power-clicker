--[[
	check_econ_model.luau — o simulador da auditoria (econ_model) é fiel ao jogo?

		lune run tools/lune/check_econ_model.luau [raiz]

	Só testa a FERRAMENTA: que ela monta as camadas do PowerFormula como o
	PowerService, usa as fórmulas reais (rebirth, combo, pads), é reprodutível
	por seed, não inventa progresso offline e desfaz os overrides de cenário.
	Não testa (nem fixa) números de balanceamento.
]]
local process = require("@lune/process")
local E = require("./env")(process.args[1])
local Model = require("./econ_model")(E)
local Profiles = require("./econ_profiles")
local Cfg, F = Model.Cfg, Model.F

local problems = {}
local function check(condition: any, message: string)
	if condition then
		print("OK   " .. message)
	else
		table.insert(problems, message)
		print("FALHA " .. message)
	end
end
local function near(a: number, b: number, tolerance: number?): boolean
	return math.abs(a - b) <= (tolerance or 1e-9) * math.max(1, math.abs(a), math.abs(b))
end

local function profile(id: string, extra: { [string]: any }?)
	local p = table.clone(Profiles[id])
	for key, value in extra or {} do
		p[key] = value
	end
	p.ComboAvg = p.ComboAvg or Model.ComboAverage(Cfg.Economy.Click.HoldClicksPerSecond, p.Burst, p.Pause)
	return p
end

-- 1. Camadas = PowerService.compute (conta feita à mão com as configs).
do
	local st = Model.NewState(profile("Ativo", { Passes = { DoublePower = true, VIP = true } }), { Seed = 1 })
	st.Rebirths = 5
	st.Temp.ClickStrength = 10
	st.Temp.PowerBoost = 4
	st.Perm.GemPower = 3
	st.Perm.PetSlots = 1
	st.Pets = { 3, 2, 1, 0.5, 0.1 }
	st.AuraIndex = 4 -- Storm
	st.Runes = { [3] = 2 } -- 2 lendárias
	for index, cut in Cfg.Cut.Cuts do
		if cut.Id == "Cut5" then
			for i, ordered in (function()
				local list = {}
				for _, c in Cfg.Cut.Cuts do
					table.insert(list, c)
				end
				table.sort(list, function(a, b)
					return a.Order < b.Order
				end)
				return list
			end)() do
				if ordered.Id == "Cut5" then
					st.CutIndex = i
				end
			end
		end
		local _ = index
	end
	st.Dirty = true
	local perClick = Model.PerClick(st)
	local up = Cfg.Upgrade
	local base = Cfg.Economy.Click.BasePowerPerClick + 10 * up.Temporary.ClickStrength.EffectPerLevel + Cfg.Cut.Cuts.Cut5.Flat
	local slots = Cfg.Pet.BaseEquipSlots + 1
	local pets = 1
	for i = 1, slots do
		pets += st.Pets[i]
	end
	local legendary = Cfg.Rune.Tiers[3].Bonus * (Cfg.Rune.WorldScale.Training or 1)
	local expected = base
		* (1 + 4 * up.Temporary.PowerBoost.EffectPerLevel)
		* (1 + 3 * up.Permanent.GemPower.EffectPerLevel)
		* (1 + Cfg.Rebirth.MultiplierPerRebirth) ^ 5
		* pets
		* Cfg.Aura.Auras.Storm.PowerMultiplier
		* (1 + legendary) ^ 2
		* Cfg.Product.GamePasses.DoublePower.Benefits.PowerMultiplier
		* Cfg.Product.GamePasses.VIP.Benefits.PowerMultiplier
	check(near(perClick, expected, 1e-12), string.format("1. ⚡ por clique = conta do PowerService (%.6g)", perClick))
	check(near(Model.Hit(st), perClick * st.Profile.ComboAvg * Model.OverdriveAverage(Cfg.Economy.Click.HoldClicksPerSecond * st.Profile.HoldShare)), "1. ⚔ golpe médio = ⚡ × combo médio × overdrive médio")
end

-- 2. Passes: escada pega o maior, fora da escada multiplica.
check(Model.PassMultiplier({ DoublePower = true, QuadPower = true, VIP = true }, "PowerMultiplier") == 4 * 1.25, "2. passes: 2x+4x na escada = 4x, × VIP 1,25")

-- 3. Renascimento: custo e multiplicador são os do EconomyFormulas.
check(F.Economy.RebirthCost(3) == math.ceil(Cfg.Rebirth.BaseCost * Cfg.Rebirth.CostGrowth ^ 3), "3. custo do renascimento = BaseCost × CostGrowth^r")
check(near(F.Economy.RebirthMultiplier(10), (1 + Cfg.Rebirth.MultiplierPerRebirth) ^ 10), "3. multiplicador do renascimento composto")

-- 4. Combo médio com o ComboLogic real.
local hold = Model.ComboAverage(Cfg.Economy.Click.HoldClicksPerSecond, 3600, 0)
check(hold > Cfg.Combo.MaxMultiplier - 0.01 and hold <= Cfg.Combo.MaxMultiplier, string.format("4. segurando sem parar o combo médio ≈ máximo (×%.3f)", hold))
local taps = Model.ComboAverage(1, 0.5, 5)
check(taps < 1.05, string.format("4. um toque a cada ~5 s não acumula combo (×%.3f)", taps))
check(Cfg.Economy.AutoClick.BuildsCombo == false, "4. Auto Click não monta combo (EconomyConfig)")

-- 5. Overdrive médio.
do
	local od = Cfg.Overdrive
	local cps = 9
	local fill = od.ChargeMax / cps
	local expected = (fill + od.CooldownSeconds + od.Multiplier * od.DurationSeconds) / (fill + od.CooldownSeconds + od.DurationSeconds)
	check(near(Model.OverdriveAverage(cps), expected) and Model.OverdriveAverage(0) == 1, "5. overdrive médio = (encher + cooldown + mult×duração)/(ciclo); sem clique = ×1")
end

-- 6. Corredor: excedente do golpe se perde por fileira; pads = WinPadRules.
do
	local st = Model.NewState(profile("Ativo"), { Seed = 1 })
	local stage = Cfg.Wall.Stages[3]
	check(Model.HitsFor(st, 3, stage.Hp * 0.6) == stage.Rows * 2, "6. golpe de 60% da fileira: 2 golpes por fileira (o excedente não passa)")
	check(Model.HitsFor(st, 3, stage.Hp * 1000) == stage.Rows, "6. golpe gigante: 1 golpe por fileira")
	st.Cleared = { [1] = true, [2] = true, [3] = true }
	st.Highest = 3
	local tower = { Cleared = { [Cfg.Wall.Stages[1].Id] = true, [Cfg.Wall.Stages[2].Id] = true, [stage.Id] = true }, Highest = 3 }
	check(Model.RepeatWins(st, 3) == F.WinPad.Payout(stage, #stage.Pads, F.WinPad.Share(stage, tower, false)), "6. repetir = WinPadRules (fração de repetição)")
end

-- 7. Treino nunca passa do teto do TrainingConfig.
do
	local st = Model.NewState(profile("Ativo"), { Seed = 1 })
	st.Rebirths = 99
	check(Model.TrainingRate(st) <= Cfg.Training.MaxShareOfHoldClick * Cfg.Economy.Click.HoldClicksPerSecond, "7. treino ≤ teto (MaxShareOfHoldClick × clique segurado)")
end

-- 8. Sem progresso offline: dia sem jogar não rende nada.
do
	local st = Model.Run(profile("Ativo", { HoursPerDay = 0, AfkHoursPerDay = 0, Jitter = 0 }), { Days = 3, Seed = 1 })
	check(st.TotalPower == 0 and st.Active == 0, "8. sem jogar, 3 dias de calendário = 0 Power (o jogo não tem progresso offline)")
end

-- 9. Reprodutível por seed; seeds diferentes mudam o RNG.
do
	local p = profile("Ativo")
	local a = Model.Run(p, { Days = 2, Seed = 11 })
	local b = Model.Run(p, { Days = 2, Seed = 11 })
	check(a.TotalPower == b.TotalPower and a.Rebirths == b.Rebirths and a.Hatched == b.Hatched, "9. mesma seed → mesmo resultado")
	local differ = false
	for seed = 12, 16 do
		local c = Model.Run(p, { Days = 2, Seed = seed })
		if c.TotalPower ~= a.TotalPower then
			differ = true
		end
	end
	check(differ, "9. seeds diferentes → resultados diferentes (ovos, boss, jornada)")
end

-- 10. Overrides de cenário são desfeitos depois do Run.
do
	local growth, mult = Cfg.Rebirth.CostGrowth, Cfg.Rebirth.MultiplierPerRebirth
	local hp = Cfg.Wall.Stages[7].Hp
	Model.Run(profile("Ativo"), { Days = 1, Seed = 1, Overrides = { RebirthCostGrowth = 9, RebirthMultiplierPerRebirth = 0.1, StageHp = { [7] = 50 } } })
	check(Cfg.Rebirth.CostGrowth == growth and Cfg.Rebirth.MultiplierPerRebirth == mult and Cfg.Wall.Stages[7].Hp == hp, "10. overrides não vazam para as configs reais")
end

-- 11. Override de HP muda só o estágio pedido.
do
	local st = Model.NewState(profile("Ativo"), { Seed = 1, Overrides = { StageHp = { [7] = 10 } } })
	check(Model.StageOf(st, 7).Hp == Cfg.Wall.Stages[7].Hp * 10 and Model.StageOf(st, 6).Hp == Cfg.Wall.Stages[6].Hp, "11. StageHp multiplica só o estágio indicado")
end

-- 12. Monte Carlo: percentis em ordem e marcos em ordem de estágio.
do
	local p = profile("Ativo")
	local times = {}
	local ordered = true
	for seed = 1, 20 do
		local st = Model.Run(p, { Days = 30, Seed = seed, StopWhen = "Colossus" })
		local last = -1
		for order = 1, #Cfg.Wall.Stages do
			local m = st.Milestones["clear:" .. order]
			if m then
				if m.Active < last then
					ordered = false
				end
				last = m.Active
			end
		end
		local m7 = st.Milestones["clear:7"]
		if m7 then
			table.insert(times, m7.Active)
		end
	end
	table.sort(times)
	local function pct(q)
		return times[math.clamp(math.ceil(q * #times), 1, #times)]
	end
	check(#times > 0 and pct(0.25) <= pct(0.5) and pct(0.5) <= pct(0.75) and pct(0.75) <= pct(0.9), "12. P25 ≤ P50 ≤ P75 ≤ P90")
	check(ordered, "12. cada estágio é conquistado depois do anterior")
end

print("")
if #problems > 0 then
	print(string.format("FALHOU: %d verificação(ões) do simulador", #problems))
	process.exit(1)
end
print("OK: simulador da auditoria fiel às fórmulas do jogo, reprodutível e sem progresso offline.")
