--[[
	check_c2e.luau — o balanceamento C2-E aprovado está no jogo, exatamente.

		lune run tools/lune/check_c2e.luau [raiz]

	R. Renascimento: 1M × 5,5^R, multiplicador 1,75^R, gemas 30 + 20r.
	A. Âncora convergente (Stats.RebirthAnchor): próximo custo = curva antiga,
	   depois min(curva nova, antiga(R0) × 7,15^(r−R0)); converge e fica na nova.
	M. Migração v8 → v9: âncora = renascimentos; nada mais muda; save novo = 0.
	W. Barreiras: Rows × HPPerRow = TotalHP (7–10), 1–4 inalterados.
	E. Ovos: Místico 300, Caminho 800; o resto (preços, chances, pets) igual.
	B. Power2x do boss: 5 min só para quem causou dano (serviço real).
	S. Saves já conquistados: Cleared/Highest, Ovo do Colosso, 1ª vez sem repetir.
	H. "≈ golpes" usa o HP DA FILEIRA, não o do estágio.
]]
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")
local E = require("./env")(process.args[1])

local problems = {}
local function check(condition: any, message: string)
	if condition then
		print("OK   " .. message)
	else
		table.insert(problems, message)
		print("FALHA " .. message)
	end
end
local function near(a: number, b: number, rel: number?): boolean
	return math.abs(a - b) <= (rel or 1e-9) * math.max(math.abs(a), math.abs(b), 1)
end

local RebirthConfig = E.require(E.Shared.Config.RebirthConfig)
local EconomyFormulas = E.require(E.Shared.Formulas.EconomyFormulas)
local WallConfig = E.require(E.Shared.Config.WallConfig)
local EggConfig = E.require(E.Shared.Config.EggConfig)
local EventConfig = E.require(E.Shared.Config.EventConfig)
local BoostConfig = E.require(E.Shared.Config.BoostConfig)
local WinPadRules = E.require(E.Shared.Formulas.WinPadRules)
local HitDisplay = E.require(E.Shared.Formulas.HitDisplay)

local function old(r)
	return math.ceil(200_000 * 3.2 ^ r)
end
local function new(r)
	return math.ceil(1_000_000 * 5.5 ^ r)
end

-- ── R. Curva nova ───────────────────────────────────────────────────────────
check(RebirthConfig.BaseCost == 1_000_000 and RebirthConfig.CostGrowth == 5.5, "R1. RebirthConfig: BaseCost 1.000.000, CostGrowth 5,5")
do
	local ok = true
	for r = 0, 30 do
		ok = ok and EconomyFormulas.RebirthCost(r) == new(r) and EconomyFormulas.RebirthCost(r, 0) == new(r)
	end
	check(ok, "R2. jogador novo (âncora 0/nil): custo(r) = ceil(1M × 5,5^r) para r = 0…30")
end
check(RebirthConfig.MultiplierPerRebirth == 0.75 and near(EconomyFormulas.RebirthMultiplier(10), 1.75 ^ 10), "R3. multiplicador continua 1,75^R")
check(RebirthConfig.BaseGems == 30 and RebirthConfig.GemsPerRebirth == 20 and EconomyFormulas.RebirthGems(7) == 170, "R4. gemas do renascimento inalteradas (30 + 20r)")
check(RebirthConfig.Resets.Power == true and RebirthConfig.Resets.TemporaryUpgrades == true and RebirthConfig.Resets.OverdriveCharge == false, "R5. o que o renascimento zera não mudou")

-- ── A. Âncora convergente ───────────────────────────────────────────────────
check(RebirthConfig.Anchor.LegacyBaseCost == 200_000 and RebirthConfig.Anchor.LegacyCostGrowth == 3.2 and RebirthConfig.Anchor.GrowthFactor == 1.3,
	"A1. âncora: curva antiga 200K × 3,2^r, fator 1,3 (crescimento temporário 7,15×)")
for _, case in { { 5, "MID R5" }, { 7, "R7" }, { 15, "R15" }, { 20, "R20" }, { 27, "R27" } } do
	local r0 = case[1]
	check(EconomyFormulas.RebirthCost(r0, r0) == old(r0), string.format("A2. %s: 1º renascimento depois da migração = custo antigo (%s)", case[2], tostring(old(r0))))
end
check(near(EconomyFormulas.RebirthCost(7, 7), 687.2e6, 1e-3), "A3. R7: próximo renascimento ≈ 687,2M (igual à economia atual)")
check(near(EconomyFormulas.RebirthCost(15, 15), 7.56e12, 1e-3), "A3. R15: próximo renascimento ≈ 7,56T (igual à economia atual)")
do
	-- Convergência: nunca acima da curva nova, sempre crescente, e a partir de
	-- algum r fica exatamente na curva nova para sempre.
	local okAll = true
	local report = {}
	for _, r0 in { 5, 7, 15, 20, 27 } do
		local joined, previous, never = nil, 0, true
		for r = r0, 120 do -- até ~1e95: acima disso o custo encosta no MaxValue (1e100)
			local cost = EconomyFormulas.RebirthCost(r, r0)
			never = never and cost <= new(r)
			okAll = okAll and cost > previous
			previous = cost
			if r > r0 then
				local expected = math.ceil(math.min(1_000_000 * 5.5 ^ r, 200_000 * 3.2 ^ r0 * (1.3 * 5.5) ^ (r - r0)))
				okAll = okAll and cost == expected
			end
			if not joined and cost == new(r) then
				joined = r
			end
			if joined and cost ~= new(r) then
				okAll = false
			end
		end
		okAll = okAll and never and joined ~= nil
		table.insert(report, string.format("R%d→curva nova no R%s", r0, tostring(joined)))
	end
	check(okAll, "A4. custo = min(nova, antiga(R0) × 7,15^(r−R0)), crescente, nunca acima da nova e converge: " .. table.concat(report, ", "))
end
check(EconomyFormulas.RebirthCost(3, 7) == old(3), "A5. renascimentos de antes da migração (r < R0) seguem a curva antiga (nada é recalculado)")

-- ── M. Migração e saves ─────────────────────────────────────────────────────
local DataConfig = E.require(E.Server.ServerConfig.DataConfig)
local Migrations = E.require(E.Server.Services.DataService.Migrations)
local DataTemplate = E.require(E.Server.Services.DataService.DataTemplate)
check(DataConfig.DataVersion == 9 and Migrations.Steps[8] ~= nil, "M1. DataVersion 9 com o passo de migração 8 → 9")
check(DataTemplate.Create(0).Stats.RebirthAnchor == 0, "M2. save novo: RebirthAnchor = 0 (curva nova direto)")
do
	local okAll = true
	for _, r in { 0, 5, 7, 15, 20, 27 } do
		local data = DataTemplate.Create(0)
		data.DataVersion = 8
		data.Stats.RebirthAnchor = nil
		data.Stats.Rebirths = r
		data.Currencies.Power = 4e9
		data.Currencies.Gems = 1234
		data.Pets.Inventory = { a = { PetId = "Dragon" } }
		local ok = Migrations.Run(data, DataConfig.DataVersion)
		okAll = okAll and ok and data.DataVersion == 9 and data.Stats.RebirthAnchor == r and data.Stats.Rebirths == r
			and data.Currencies.Power == 4e9 and data.Currencies.Gems == 1234 and data.Pets.Inventory.a.PetId == "Dragon"
	end
	check(okAll, "M3. saves v8 com R0/R5/R7/R15/R20/R27: âncora = renascimentos; R, Power, gemas e pets intactos")
	local kept = DataTemplate.Create(0)
	kept.DataVersion = 8
	kept.Stats.Rebirths = 9
	kept.Stats.RebirthAnchor = 4
	Migrations.Run(kept, DataConfig.DataVersion)
	check(kept.Stats.RebirthAnchor == 4, "M4. âncora já existente não é sobrescrita")
end
do
	-- RebirthLogic real: R7 migrado com exatamente o custo antigo consegue renascer.
	local RebirthLogic = E.require(E.Server.Logic.RebirthLogic)
	local data = DataTemplate.Create(0)
	data.Stats.Rebirths = 7
	data.Stats.RebirthAnchor = 7
	data.Currencies.Power = old(7) - 1
	local before = RebirthLogic.CanRebirth(data)
	data.Currencies.Power = old(7)
	local ok, _, result = RebirthLogic.Perform(data)
	check(not before and ok and result.Rebirths == 8 and data.Currencies.Power == 0, "M5. R7 migrado: com 687,2M renasce (com 1 a menos, não); vai para R8")
	check(RebirthLogic.GetCost(data) == math.ceil(math.min(1_000_000 * 5.5 ^ 8, 200_000 * 3.2 ^ 7 * (1.3 * 5.5))), "M6. R8 desse save custa min(nova(8), antiga(7) × 7,15)")
	local fresh = DataTemplate.Create(0)
	check(RebirthLogic.GetCost(fresh) == 1_000_000, "M7. jogador novo: 1º renascimento custa 1M")
end

-- ── W. Barreiras ────────────────────────────────────────────────────────────
do
	local expected = {
		[1] = { 3, 60, 180 },
		[2] = { 4, 450, 1_800 },
		[3] = { 4, 3_500, 14_000 },
		[4] = { 4, 28_000, 112_000 },
		[5] = { 5, 330_000, 1_650_000 },
		[6] = { 5, 4_500_000, 22_500_000 },
		[7] = { 5, 60_000_000, 300_000_000 },
		[8] = { 6, 960_000_000, 5_760_000_000 },
		[9] = { 8, 6_000_000_000, 48_000_000_000 },
		[10] = { 10, 288_000_000_000, 2_880_000_000_000 },
	}
	local before = { [7] = 75e6, [8] = 720e6, [9] = 6e9, [10] = 72e9 }
	local mult = { [7] = 4, [8] = 8, [9] = 8, [10] = 40 }
	for order, e in expected do
		local stage = WallConfig.Stages[order]
		local total = stage.Rows * stage.Hp
		local label = string.format("W%d. %s: %d fileiras × %s HP/fileira = %s total", order, stage.Id, stage.Rows, tostring(stage.Hp), tostring(total))
		local ok = stage.Rows == e[1] and stage.Hp == e[2] and total == e[3]
		if mult[order] then
			ok = ok and near(total / before[order], mult[order])
			label ..= string.format(" (×%s do HP total antigo)", tostring(mult[order]))
		end
		check(ok, label)
	end
	check(WallConfig.Stages[10].Hp == 288e9 and WallConfig.Stages[10].Hp ~= 28.8e9, "W11. Colosso: 288B POR FILEIRA (não 28,8B): ×40 é do HP total, não por fileira")
end

-- ── E. Ovos ─────────────────────────────────────────────────────────────────
do
	local eggs = EggConfig.Eggs
	check(eggs.MysticEgg.Price == 300 and eggs.MysticEgg.Currency == "Gems" and eggs.TowerEgg.Price == 800 and eggs.TowerEgg.Currency == "Gems",
		"E1. Ovo Místico 300 💎 e Ovo do Caminho 800 💎")
	check(eggs.BasicEgg.Price == 2_000 and eggs.BasicEgg.Currency == "Power" and eggs.ForestEgg.Price == 25 and eggs.ColossusEgg.Price == 2_500,
		"E2. Básico ⚡2.000, Floresta 💎25 e Colosso 💎2.500 inalterados")
	local weights = {
		BasicEgg = { Dog = 50, Cat = 30, Bunny = 14, Fox = 5, Wolf = 1 },
		ForestEgg = { Deer = 45, Owl = 30, Bear = 18, Panther = 6.5, Unicorn = 0.5 },
		MysticEgg = { SpiritFox = 50, Golem = 35, Phoenix = 12, Dragon = 2.9, CelestialDragon = 0.1 },
		TowerEgg = { Gargoyle = 46, Knight = 30, Griffin = 17, Titan = 6.5, Eclipse = 0.5 },
		ColossusEgg = { Guardian = 55, Seraph = 29, Nova = 15, Colossus = 1 },
	}
	local same = eggs.TowerEgg.RequiredStage == "Gold" and eggs.ColossusEgg.RequiredStage == "Colossus"
	for id, map in weights do
		local count = 0
		for _, drop in eggs[id].Drops do
			same = same and map[drop.PetId] == drop.Weight
			count += 1
		end
		local expectedCount = 0
		for _ in map do
			expectedCount += 1
		end
		same = same and count == expectedCount
	end
	check(same, "E3. chances, pets e liberação (estágio 5 / Colosso) dos 5 ovos inalteradas")
end

-- ── H. "≈ golpes" pela fileira ──────────────────────────────────────────────
do
	local colossus = WallConfig.Stages[10]
	local damage = 3.6e9
	check(HitDisplay.HitsFor(colossus.Hp, damage) == 80 and HitDisplay.HitsFor(colossus.Hp * colossus.Rows, damage) == 800,
		"H1. ≈ golpes = HP DA FILEIRA ÷ golpe: Colosso com golpe 3,6B → 80 por fileira (800 seria o estágio inteiro)")
end

-- ── S. Saves já conquistados ────────────────────────────────────────────────
do
	local EggLogic = E.require(E.Server.Logic.EggLogic)
	local data = DataTemplate.Create(0)
	for _, stage in WallConfig.Stages do
		data.Tower.Cleared[stage.Id] = true
	end
	data.Tower.Highest = 10
	data.Currencies.Gems = 10_000
	data.Worlds.Current = "Training"
	check(data.Tower.Cleared.Colossus == true and data.Tower.Highest == 10, "S1. quem já venceu o Colosso mantém Tower.Cleared/Highest (o HP novo não mexe no save)")
	local ok, code, result = EggLogic.Hatch(data, "ColossusEgg", 1, function()
		return 0.5
	end, 0)
	check(ok and result ~= nil and data.Currencies.Gems == 10_000 - EggConfig.Eggs.ColossusEgg.Price, "S2. e continua abrindo o Ovo do Colosso (2.500 💎) — " .. tostring(code))
	local share = WinPadRules.Share(WallConfig.Stages[10], data.Tower, false)
	check(share < 1, "S3. repetir o Colosso já vencido paga só a fração de repetição (1ª vez não se repete)")
end

-- ── B. Power2x do boss (serviço real) ───────────────────────────────────────
check(EventConfig.Boss.VictoryBoostSeconds == 300 and EventConfig.Boss.VictoryBoostId == "Power2x" and BoostConfig.Boosts.Power2x.DurationSeconds == 15 * 60,
	"B1. boss: Power2x de 5 min (o Power2x de outras fontes continua 15 min por stack)")
do
	local Signal = E.require(E.Shared.Utils.Signal)
	local players = {}
	local datas = {}
	local removing = Signal.new()
	E.stubs.Players = { GetPlayers = function()
		return players
	end, PlayerRemoving = removing, PlayerAdded = Signal.new() }
	E.stubModules["ServerScriptService.Server.Services.DataService"] = {
		GetData = function(player)
			return datas[player]
		end,
		MarkChanged = function() end,
	}
	E.stubModules["ServerScriptService.Server.Services.NetService"] = { FireClient = function() end, FireAllClients = function() end }
	E.stubModules["ServerScriptService.Server.Services.CurrencyService"] = { Add = function(_, _, amount)
		return amount
	end }
	E.stubModules["ServerScriptService.Server.Services.PowerService"] = {
		GetInfo = function()
			return { PerClick = 100 }
		end,
		Invalidate = function() end,
		RegisterProvider = function() end,
	}
	E.stubModules["ServerScriptService.Server.Services.EggService"] = { RegisterLuckProvider = function() end }
	E.stubModules["ServerScriptService.Server.Services.WorldService"] = { OriginOf = function()
		return roblox.Vector3.new(0, 0, 0)
	end }
	E.patches["ServerScriptService.Server.Services.BossService"] = {
		{ "part.Position = origin + Vector3.new(0, EventConfig.Boss.Height, 0)", "part.CFrame = CFrame.new(origin + Vector3.new(0, EventConfig.Boss.Height, 0))" },
		{ "(root.Position - part.Position)", "(root.CFrame.Position - part.CFrame.Position)" },
	}
	local BossService = E.require(E.Server.Services.BossService)
	BossService.Init()

	local function newPlayer(id, near)
		local character = roblox.Instance.new("Model")
		local root = roblox.Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.CFrame = roblox.CFrame.new(if near then roblox.Vector3.new(4, EventConfig.Boss.Height, 0) else roblox.Vector3.new(500, 3, 0))
		root.Parent = character
		character.Parent = E.Workspace
		local player = { UserId = id, Name = "P" .. id, Character = character, Parent = E.Workspace }
		local data = DataTemplate.Create(0)
		data.Worlds.Current = "Training"
		datas[player] = data
		table.insert(players, player)
		return player
	end
	local A = newPlayer(1, true) -- bate no boss
	local B = newPlayer(2, true) -- está perto, no mundo, mas não bate
	check(BossService.SpawnNow(), "B2. boss nasce (serviço real)")
	BossService.OnClick(A, 100) -- dano parcial
	local C = newPlayer(3, true) -- entra depois e não bate
	BossService.OnClick(A, 1e12) -- A derruba
	local function boost(p)
		return datas[p].Boosts.Remaining.Power2x
	end
	check(boost(A) == 300, string.format("B3. A participou (dano real): recebe Power2x por exatamente 5 min (%s s)", tostring(boost(A))))
	check(boost(B) == nil, "B4. B estava perto e no servidor, sem dano: não recebe")
	check(boost(C) == nil, "B5. C entrou depois e não bateu: não recebe")
	-- Segunda vitória soma 5 min (respeitando o teto do Power2x).
	BossService.SpawnNow()
	BossService.OnClick(A, 1e12)
	check(boost(A) == 600, "B6. outra vitória soma mais 5 min (600 s)")
	local _ = task
end

print("")
if #problems > 0 then
	print(string.format("FALHOU: %d verificação(ões)", #problems))
	process.exit(1)
end
print("OK: C2-E no jogo — renascimento + âncora, migração v9, barreiras 5–10, ovos, Power2x do boss só para quem bateu.")
process.exit(0)
