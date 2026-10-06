--[[
	econ_model.luau — modelo CANÔNICO da progressão do Power Clicker (auditoria
	da economia). Ferramenta de análise: não faz parte do jogo, não mexe em
	save, não é carregada pelo Rojo.

	Fonte da verdade = o código do jogo. Tudo o que pode ser reaproveitado vem
	direto dos módulos reais (via env.luau):
		PowerFormula.Compute          (camadas e teto)
		EconomyFormulas               (custos de upgrade/rebirth, multiplicador
		                               do rebirth, combo, gemas do rebirth)
		ComboLogic                    (stacks, timeout, decaimento)
		WinPadRules                   (prêmio dos pads, repetição)
		EggOdds                       (chances com sorte)
		CorridorLayout                (posições reais das barreiras)
		AuraLogic.WalkSpeed           (velocidade de caminhada)
		configs: Economy, Rebirth, Combo, Upgrade, Cut, Pet, Egg, Wall,
		         Training, Overdrive, Event, Session, Boost, Aura, Rune,
		         DailyReward, Quest, Season, Achievement, Product, Lobby.
	O que é comportamento do jogador (quanto clica, quando compra, quando
	renasce) é SUPOSIÇÃO e fica nos perfis (econ_profiles.luau), documentada.

	Uso:
		local Model = require("./econ_model")(E)       -- E = require("./env")(raiz)
		local run = Model.Run(profile, { Days = 30, Seed = 1 })

	Overrides (cenários A/B/C, elasticidade) mudam SÓ a cópia que o modelo usa:
		Model.Run(profile, { Overrides = { StageHp = { [7] = 2 } } })
]]

return function(E)
	local Cfg = {
		Economy = E.require(E.Shared.Config.EconomyConfig),
		Rebirth = E.require(E.Shared.Config.RebirthConfig),
		Combo = E.require(E.Shared.Config.ComboConfig),
		Upgrade = E.require(E.Shared.Config.UpgradeConfig),
		Cut = E.require(E.Shared.Config.CutConfig),
		Pet = E.require(E.Shared.Config.PetConfig),
		Egg = E.require(E.Shared.Config.EggConfig),
		Wall = E.require(E.Shared.Config.WallConfig),
		Training = E.require(E.Shared.Config.TrainingConfig),
		Overdrive = E.require(E.Shared.Config.OverdriveConfig),
		Event = E.require(E.Shared.Config.EventConfig),
		Session = E.require(E.Shared.Config.SessionConfig),
		Boost = E.require(E.Shared.Config.BoostConfig),
		Aura = E.require(E.Shared.Config.AuraConfig),
		Rune = E.require(E.Shared.Config.RuneConfig),
		Daily = E.require(E.Shared.Config.DailyRewardConfig),
		Quest = E.require(E.Shared.Config.QuestConfig),
		Season = E.require(E.Shared.Config.SeasonConfig),
		Achievement = E.require(E.Shared.Config.AchievementConfig),
		Product = E.require(E.Shared.Config.ProductConfig),
		Lobby = E.require(E.Shared.Config.LobbyConfig),
	}
	local F = {
		Power = E.require(E.Shared.Formulas.PowerFormula),
		Economy = E.require(E.Shared.Formulas.EconomyFormulas),
		Combo = E.require(E.Shared.Formulas.ComboLogic),
		WinPad = E.require(E.Shared.Formulas.WinPadRules),
		EggOdds = E.require(E.Shared.Formulas.EggOdds),
		Corridor = E.require(E.Shared.Formulas.CorridorLayout),
		Aura = E.require(E.Shared.Formulas.AuraLogic),
		Rune = E.require(E.Shared.Formulas.RuneLogic),
	}

	local Model = { Cfg = Cfg, F = F }

	local HOLD_CPS = Cfg.Economy.Click.HoldClicksPerSecond
	local AUTO_CPS = Cfg.Economy.AutoClick.TicksPerSecond
	local AUTO_COMBO = Cfg.Economy.AutoClick.BuildsCombo
	local DAY = 24 * 3600

	-- ── Dados derivados das configs (lidos uma vez) ─────────────────────────
	local STAGES = Cfg.Wall.Stages
	local SEGMENTS = F.Corridor.Segments()
	local SPAWN_X = Cfg.Lobby.SpawnPoint.X

	local CUTS = {}
	for _, cut in Cfg.Cut.Cuts do
		table.insert(CUTS, cut)
	end
	table.sort(CUTS, function(a, b)
		return a.Order < b.Order
	end)

	local AURAS = F.Aura.Ordered()

	local GEM_EGGS = {}
	local POWER_EGGS = {}
	for _, egg in Cfg.Egg.Eggs do
		if egg.Enabled then
			table.insert(if egg.Currency == "Gems" then GEM_EGGS else POWER_EGGS, egg)
		end
	end
	table.sort(GEM_EGGS, function(a, b)
		return a.Price < b.Price
	end)
	table.sort(POWER_EGGS, function(a, b)
		return a.Price < b.Price
	end)

	local STATIONS = table.clone(Cfg.Training.Stations)
	table.sort(STATIONS, function(a, b)
		return a.Order < b.Order
	end)
	local TRAINING_CAP = Cfg.Training.MaxShareOfHoldClick * HOLD_CPS

	local RUNE_TIERS = Cfg.Rune.Tiers
	local RUNE_SCALE = Cfg.Rune.WorldScale.Training or 1

	-- ── RNG reprodutível (xorshift32) ───────────────────────────────────────
	function Model.Rng(seed: number): () -> number
		local s = math.floor(seed) % 4294967296
		if s == 0 then
			s = 2463534242
		end
		return function(): number
			s = bit32.bxor(s, bit32.lshift(s, 13))
			s = bit32.bxor(s, bit32.rshift(s, 17))
			s = bit32.bxor(s, bit32.lshift(s, 5))
			return s / 4294967296
		end
	end

	-- ── Combo: média REAL (ComboLogic) para um padrão de cliques ────────────
	--[[
		Segura `burst` segundos a `cps`, para `pause` segundos, repete. Devolve
		o multiplicador médio POR CLIQUE (é o que entra no Power e no dano).
	]]
	function Model.ComboAverage(cps: number, burst: number, pause: number, seconds: number?): number
		if cps <= 0 then
			return 1
		end
		local horizon = seconds or 3600
		local stacks, last, now = 0, -math.huge, 0
		local sum, clicks = 0, 0
		local interval = 1 / cps
		while now < horizon do
			local burstEnd = now + burst
			while now < burstEnd do
				stacks = F.Combo.Register(stacks, last, now)
				last = now
				sum += F.Economy.ComboMultiplier(stacks)
				clicks += 1
				now += interval
			end
			now += pause
		end
		return sum / math.max(clicks, 1)
	end

	-- ── Overdrive: multiplicador médio do clique manual ─────────────────────
	--[[
		A barra enche 1 por clique manual (ChargePerClick) até ChargeMax; aí
		DurationSeconds a ×Multiplier; depois CooldownSeconds sem carregar.
		Média ponderada pelo tempo (o clique é constante): (encher + cooldown +
		mult × duração) / (encher + cooldown + duração).
	]]
	function Model.OverdriveAverage(cps: number): number
		local od = Cfg.Overdrive
		if cps <= 0 then
			return 1
		end
		local fill = od.ChargeMax / (od.ChargePerClick * cps)
		return (fill + od.CooldownSeconds + od.Multiplier * od.DurationSeconds) / (fill + od.CooldownSeconds + od.DurationSeconds)
	end

	-- ── Passes ─────────────────────────────────────────────────────────────
	-- Mesma regra do MonetizationService.passMultiplier (escada = o maior).
	function Model.PassMultiplier(passes: { [string]: boolean }?, benefit: string): number
		local total = 1
		local ladders = {}
		for key, owned in passes or {} do
			local pass = Cfg.Product.GamePasses[key]
			local value = owned and pass and (pass.Benefits :: any)[benefit]
			if type(value) == "number" and value >= 1 then
				if pass.Ladder then
					ladders[pass.Ladder] = math.max(ladders[pass.Ladder] or 1, value)
				else
					total *= value
				end
			end
		end
		for _, value in ladders do
			total *= value
		end
		return total
	end

	local function passExtraSlots(passes): number
		local extra = 0
		for key, owned in passes or {} do
			local pass = Cfg.Product.GamePasses[key]
			if owned and pass and type((pass.Benefits :: any).ExtraEquipSlots) == "number" then
				extra += (pass.Benefits :: any).ExtraEquipSlots
			end
		end
		return extra
	end

	-- ── Overrides (só a cópia do modelo) ────────────────────────────────────
	local function stageOf(st, order: number)
		return st.Stages[order]
	end

	local function makeStages(overrides)
		local list = {}
		for index, stage in STAGES do
			local copy = table.clone(stage)
			copy.Pads = table.clone(stage.Pads)
			local hpScale = overrides and overrides.StageHp and overrides.StageHp[index] or 1
			copy.Hp = stage.Hp * hpScale
			local rows = overrides and overrides.StageRows and overrides.StageRows[index]
			if rows then
				copy.Rows = rows
			end
			list[index] = copy
		end
		return list
	end

	-- ── Estado ──────────────────────────────────────────────────────────────
	local function newState(profile, opts)
		local overrides = opts.Overrides or {}
		local st = {
			Profile = profile,
			Overrides = overrides,
			Stages = makeStages(overrides),
			Rng = Model.Rng(opts.Seed or 1),

			Power = 0,
			TotalPower = 0,
			Gems = 0,
			TotalGems = 0,
			Wins = 0,
			Rebirths = 0,
			Temp = { ClickStrength = 0, PowerBoost = 0 },
			Perm = { GemPower = 0, PetSlots = 0, Luck = 0, Storage = 0 },
			CutIndex = 1,
			Pets = {}, -- bônus, ordem decrescente
			BasicHatched = 0,
			AuraIndex = 1,
			Runes = {}, -- [tier] = quantidade
			Cleared = {}, -- [order] = true
			Highest = 0,

			Boost2x = 0, -- segundos restantes de Power2x (só gasta online)
			Luck2x = 0,

			Active = 0, -- segundos de jogo ATIVO acumulados
			Online = 0, -- ativo + AFK
			Calendar = 0, -- segundos de calendário
			Day = 0,
			DailyStreak = 0,

			Clicks = 0,
			BossKills = 0,
			Hatched = 0,
			Legendary = 0,
			Mythic = 0,
			Achieved = {},
			QuestsOnce = {},
			SeasonXp = 0,
			SeasonLevel = 0,

			Income = { Click = 0, Auto = 0, Training = 0, Boss = 0, Orbs = 0, Chests = 0 },
			Milestones = {}, -- [key] = { Active = s, Calendar = s }
			Snapshots = {},
			Dirty = true,
			Cache = nil,
			Activity = nil,
			Spent = { Upgrades = 0, Cuts = 0, Eggs = 0 },
			GemSpent = { GemPower = 0, PetSlots = 0, Luck = 0, Aura = 0, Eggs = 0 },
		}
		st.Passes = profile.Passes or {}
		st.PassPower = Model.PassMultiplier(st.Passes, "PowerMultiplier")
		st.PassLuck = Model.PassMultiplier(st.Passes, "LuckMultiplier")
		st.ExtraSlots = passExtraSlots(st.Passes)
		-- Run sorteia a variação do jogador; aqui fica o valor nominal do perfil.
		st.HoldShare = profile.HoldShare or 0
		st.OdAvg = profile.OdAvg or Model.OverdriveAverage(HOLD_CPS * st.HoldShare)
		return st
	end
	Model.NewState = newState

	-- ── Camadas do PowerFormula (iguais ao PowerService.compute) ────────────
	local function upgradeLevelEffect(kind: string, id: string, level: number): number
		return F.Economy.UpgradeEffect(Cfg.Upgrade[kind][id], level)
	end

	function Model.EquipSlots(st): number
		local slots = Cfg.Pet.BaseEquipSlots + upgradeLevelEffect("Permanent", "PetSlots", st.Perm.PetSlots) + st.ExtraSlots
		return math.clamp(math.floor(slots), 1, Cfg.Pet.MaxEquipSlots)
	end

	function Model.InventorySlots(st): number
		local slots = Cfg.Pet.BaseInventorySlots + upgradeLevelEffect("Permanent", "Storage", st.Perm.Storage)
		return math.clamp(math.floor(slots), 1, Cfg.Pet.MaxInventorySlots)
	end

	-- PetLogic.GetMultiplier: 1 + Σ bônus dos equipados (o jogador equipa os melhores).
	function Model.PetMultiplier(st): number
		local total = 1
		for index = 1, math.min(#st.Pets, Model.EquipSlots(st)) do
			total += st.Pets[index]
		end
		return total
	end

	function Model.RuneMultiplier(st): number
		-- 3 encaixes, a mesma runa pode ocupar mais de um (RuneLogic.Equip).
		local total, used = 1, 0
		for tier = #RUNE_TIERS, 1, -1 do
			local count = st.Runes[tier] or 0
			while count > 0 and used < Cfg.Rune.Slots do
				total *= 1 + RUNE_TIERS[tier].Bonus * RUNE_SCALE
				used += 1
				count -= 1
			end
		end
		return total
	end

	function Model.EventMultiplier(st): number
		-- Happy Hours (SessionConfig): sábado e domingo UTC o dia inteiro.
		-- Os da semana (18–20 UTC) ficam de fora por suposição de horário.
		local weekday = ((st.Day + (st.Profile.StartWeekday or 2) - 1) % 7) + 1 -- 1 = domingo
		local best = 1
		for _, hh in Cfg.Session.HappyHours do
			if hh.Weekday ~= nil and hh.Weekday == weekday and hh.DurationHours >= 24 then
				best = math.max(best, hh.Multiplier)
			end
		end
		return if st.Profile.HappyHours == false then 1 else best
	end

	--[[
		As camadas que NÃO mudam a cada passo (cache). Boost e Event entram por
		fora (mesmo produto: PowerFormula multiplica todas as camadas).
	]]
	function Model.Layers(st)
		local cut = CUTS[st.CutIndex]
		local base = Cfg.Economy.Click.BasePowerPerClick + upgradeLevelEffect("Temporary", "ClickStrength", st.Temp.ClickStrength) + cut.Flat
		local layers = {
			Upgrade = 1 + upgradeLevelEffect("Temporary", "PowerBoost", st.Temp.PowerBoost),
			Permanent = 1 + upgradeLevelEffect("Permanent", "GemPower", st.Perm.GemPower),
			Rebirth = F.Economy.RebirthMultiplier(st.Rebirths),
			World = 1,
			Pet = Model.PetMultiplier(st),
			Aura = AURAS[st.AuraIndex].PowerMultiplier,
			Rune = Model.RuneMultiplier(st),
			GamePass = st.PassPower,
			Social = 1 + math.min(st.Profile.Friends or 0, 6) * 0.05,
		}
		return base, layers
	end

	function Model.PerClick(st): number
		if st.Dirty or not st.Cache then
			local base, layers = Model.Layers(st)
			local perClick = F.Power.Compute(base, layers)
			st.Cache = { PerClick = perClick, Base = base, Layers = layers }
			st.Dirty = false
		end
		local boost = if st.Boost2x > 0 then Cfg.Boost.Boosts.Power2x.Multiplier else 1
		return st.Cache.PerClick * boost * Model.EventMultiplier(st)
	end

	-- ── Marcos e helpers ────────────────────────────────────────────────────
	local function mark(st, key: string)
		if not st.Milestones[key] then
			st.Milestones[key] = { Active = st.Active, Calendar = st.Calendar, Rebirths = st.Rebirths, Power = st.Power, Hit = if st.Cache then Model.Hit(st) else nil }
		end
	end

	local function addPower(st, source: string, amount: number)
		st.Power += amount
		st.TotalPower += amount
		st.Income[source] += amount
	end

	local function addGems(st, amount: number)
		st.Gems += amount
		st.TotalGems += amount
	end

	local function addBoost(st, boostId: string, stacks: number)
		local boost = Cfg.Boost.Boosts[boostId]
		local key = if boostId == "Luck2x" then "Luck2x" else "Boost2x"
		if boostId == "Power5x" then
			return -- só vem de compra; nenhum perfil compra
		end
		st[key] = math.min(st[key] + boost.DurationSeconds * stacks, boost.MaxStoredSeconds)
	end

	-- Power2x de quem está no mundo quando o boss morre (BossService.payout).
	local function bossBoost(st)
		local boss = Cfg.Event.Boss
		local seconds = st.Overrides.BossBoostSeconds
		if seconds == nil then
			addBoost(st, boss.VictoryBoostId, boss.VictoryBoostStacks)
		elseif seconds > 0 then
			local boost = Cfg.Boost.Boosts[boss.VictoryBoostId]
			st.Boost2x = math.min(st.Boost2x + seconds, boost.MaxStoredSeconds)
		end
	end

	local function grant(st, rewards)
		for _, reward in rewards do
			if reward.Type == "Currency" and reward.Currency == "Gems" then
				addGems(st, reward.Amount)
			elseif reward.Type == "Boost" then
				addBoost(st, reward.BoostId, reward.Amount)
			elseif reward.Type == "Pet" then
				local pet = Cfg.Pet.Pets[reward.PetId]
				if pet then
					table.insert(st.Pets, pet.Bonus)
					table.sort(st.Pets, function(a, b)
						return a > b
					end)
					st.Dirty = true
				end
			end
		end
	end

	local function seasonXp(st, amount: number)
		st.SeasonXp += amount
		while st.SeasonLevel < Cfg.Season.LevelCount and st.SeasonXp >= (st.SeasonLevel + 1) * Cfg.Season.XpPerLevel do
			st.SeasonLevel += 1
			grant(st, Cfg.Season.Levels[st.SeasonLevel].Free)
		end
	end

	local function checkAchievements(st)
		for id, achievement in Cfg.Achievement.Achievements do
			if not st.Achieved[id] and achievement.Stat then
				local value = if achievement.Stat == "TotalClicks"
					then st.Clicks
					elseif achievement.Stat == "Rebirths" then st.Rebirths
					elseif achievement.Stat == "LegendaryHatched" then st.Legendary
					elseif achievement.Stat == "MythicHatched" then st.Mythic
					else 0
				if value >= achievement.Threshold then
					st.Achieved[id] = true
					grant(st, achievement.Rewards)
				end
			end
		end
	end

	local function questOnce(st, id: string)
		if not st.QuestsOnce[id] then
			st.QuestsOnce[id] = true
			grant(st, Cfg.Quest.Quests[id].Rewards)
			seasonXp(st, Cfg.Season.XpSources.QuestClaimed)
		end
	end

	-- ── Ovos ────────────────────────────────────────────────────────────────
	function Model.Luck(st): number
		local luck = 1 + upgradeLevelEffect("Permanent", "Luck", st.Perm.Luck)
		luck *= st.PassLuck
		if st.Luck2x > 0 then
			luck *= Cfg.Boost.Boosts.Luck2x.Multiplier
		end
		return F.EggOdds.ClampLuck(luck)
	end

	-- Preço do ovo (override de cenário: EggPrice = { [EggId] = preço }).
	local function eggPrice(st, egg): number
		local prices = st.Overrides.EggPrice
		return if prices and prices[egg.Id] then prices[egg.Id] else egg.Price
	end
	Model.EggPrice = eggPrice

	local function eggUnlocked(st, egg): boolean
		if not egg.RequiredStage then
			return true
		end
		for _, stage in STAGES do
			if stage.Id == egg.RequiredStage then
				return st.Cleared[stage.Order] == true
			end
		end
		return false
	end

	local function insertPet(st, bonus: number)
		table.insert(st.Pets, bonus)
		table.sort(st.Pets, function(a, b)
			return a > b
		end)
		local cap = Model.InventorySlots(st)
		while #st.Pets > cap do
			table.remove(st.Pets) -- o jogador apaga o pior
		end
		st.Dirty = true
	end

	local function hatch(st, egg)
		local weights = F.EggOdds.Weights(egg, Model.Luck(st))
		local petId = F.EggOdds.Pick(weights, st.Rng())
		local pet = Cfg.Pet.Pets[petId]
		st.Hatched += 1
		if pet.Rarity == "Legendary" then
			st.Legendary += 1
		elseif pet.Rarity == "Mythic" then
			st.Mythic += 1
		end
		insertPet(st, pet.Bonus)
		if st.Hatched >= 3 then
			questOnce(st, "HatchThree")
		end
		mark(st, "egg:" .. egg.Id)
		return pet
	end

	-- Ganho esperado de UM ovo no multiplicador de pets (com a sorte atual).
	function Model.EggExpectedGain(st, egg): number
		local chances = F.EggOdds.Chances(egg, Model.Luck(st))
		local slots = Model.EquipSlots(st)
		local worst = if #st.Pets >= slots then st.Pets[slots] else 0
		local expected = 0
		for petId, chance in chances do
			local bonus = Cfg.Pet.Pets[petId].Bonus
			expected += chance * math.max(bonus - worst, 0)
		end
		return expected
	end

	-- ── Compras ─────────────────────────────────────────────────────────────
	local function rebirthCost(st): number
		return F.Economy.RebirthCost(st.Rebirths)
	end

	local function buyCuts(st)
		for index = #CUTS, st.CutIndex + 1, -1 do
			local cut = CUTS[index]
			if st.Wins >= cut.RequiredWins and st.Power >= cut.Price then
				st.Power -= cut.Price
				st.Spent.Cuts += cut.Price
				st.CutIndex = index
				st.Dirty = true
				mark(st, "cut:" .. cut.Id)
				return
			end
		end
	end

	local function buyPowerEggs(st)
		local profile = st.Profile
		local limit = profile.BasicEggs or 25
		for _, egg in POWER_EGGS do
			local price = eggPrice(st, egg)
			while st.BasicHatched < limit and st.Power >= price * (profile.EggReserve or 10) do
				st.Power -= price
				st.Spent.Eggs += price
				st.BasicHatched += 1
				hatch(st, egg)
			end
		end
	end

	local function buyTempUpgrades(st)
		local profile = st.Profile
		local saveLine = rebirthCost(st) * (profile.RebirthAt or 1) * (profile.SaveAt or 0.5)
		if st.Power >= saveLine then
			return -- guardando para o renascimento: upgrade temporário seria perdido
		end
		local guard = 0
		while guard < 400 do
			guard += 1
			local bestId, bestCost = nil, math.huge
			for id, upgrade in Cfg.Upgrade.Temporary do
				local cost = F.Economy.UpgradeCost(upgrade, st.Temp[id])
				if cost < bestCost then
					bestId, bestCost = id, cost
				end
			end
			if not bestId or bestCost > st.Power then
				return
			end
			st.Power -= bestCost
			st.Spent.Upgrades += bestCost
			st.Temp[bestId] += 1
			st.Dirty = true
			if st.Power >= saveLine then
				return
			end
		end
	end

	--[[
		Gemas: o jogador escolhe a compra com o maior ganho de multiplicador
		por gema (ln(ganho)/custo) entre: Eternal Power, espaço de pet, aura,
		ovo (ganho ESPERADO) e sorte. Se a melhor não cabe, guarda.
	]]
	local function gemOptions(st)
		local options = {}
		local petMult = Model.PetMultiplier(st)
		-- Eternal Power
		local gp = Cfg.Upgrade.Permanent.GemPower
		local gpCost = F.Economy.UpgradeCost(gp, st.Perm.GemPower)
		if gpCost < math.huge then
			local now = 1 + gp.EffectPerLevel * st.Perm.GemPower
			table.insert(options, { Kind = "GemPower", Cost = gpCost, Gain = (now + gp.EffectPerLevel) / now })
		end
		-- Espaço de pet: só vale se houver pet esperando fora.
		local slotsUp = Cfg.Upgrade.Permanent.PetSlots
		local slotCost = F.Economy.UpgradeCost(slotsUp, st.Perm.PetSlots)
		local slots = Model.EquipSlots(st)
		if slotCost < math.huge and #st.Pets > slots and slots < Cfg.Pet.MaxEquipSlots then
			table.insert(options, { Kind = "PetSlots", Cost = slotCost, Gain = (petMult + st.Pets[slots + 1]) / petMult })
		end
		-- Aura: a próxima que os Wins já liberam.
		local nextAura = AURAS[st.AuraIndex + 1]
		if nextAura and st.Wins >= nextAura.RequiredWins then
			table.insert(options, { Kind = "Aura", Cost = nextAura.Price, Gain = nextAura.PowerMultiplier / AURAS[st.AuraIndex].PowerMultiplier })
		end
		-- Ovos de gema liberados.
		for _, egg in GEM_EGGS do
			if eggUnlocked(st, egg) and #st.Pets < Model.InventorySlots(st) + 50 then
				local gain = Model.EggExpectedGain(st, egg)
				if gain > 0 then
					table.insert(options, { Kind = "Egg", Egg = egg, Cost = eggPrice(st, egg), Gain = (petMult + gain) / petMult })
				end
			end
		end
		-- Sorte: o perfil Otimizador considera (o ganho é indireto).
		if st.Profile.BuysLuck then
			local luck = Cfg.Upgrade.Permanent.Luck
			local cost = F.Economy.UpgradeCost(luck, st.Perm.Luck)
			if cost < math.huge then
				table.insert(options, { Kind = "Luck", Cost = cost, Gain = 1 + 0.25 * luck.EffectPerLevel })
			end
		end
		return options
	end

	local function buyWithGems(st)
		local guard = 0
		while guard < 200 do
			guard += 1
			local options = gemOptions(st)
			local best, bestScore = nil, 0
			for _, option in options do
				local score = math.log(option.Gain) / option.Cost
				if score > bestScore then
					best, bestScore = option, score
				end
			end
			if not best then
				return
			end
			if best.Cost > st.Gems then
				-- Perfil impaciente compra a melhor que CABE; o resto guarda.
				if st.Profile.GemPatience == false then
					local alt, altScore = nil, 0
					for _, option in options do
						local score = math.log(option.Gain) / option.Cost
						if option.Cost <= st.Gems and score > altScore then
							alt, altScore = option, score
						end
					end
					if not alt then
						return
					end
					best = alt
				else
					return
				end
			end
			st.Gems -= best.Cost
			if best.Kind == "Egg" then
				st.GemSpent.Eggs += best.Cost
				hatch(st, best.Egg)
			elseif best.Kind == "Aura" then
				st.GemSpent.Aura += best.Cost
				st.AuraIndex += 1
				mark(st, "aura:" .. AURAS[st.AuraIndex].Id)
			else
				st.GemSpent[best.Kind] += best.Cost
				st.Perm[best.Kind] += 1
			end
			st.Dirty = true
		end
	end

	local function tryRebirth(st)
		-- RebirthAt: o jogador renasce quando o saldo passa de RebirthAt × custo
		-- (1 = assim que pode; quem não sabe que vale a pena espera mais).
		while st.Power >= rebirthCost(st) * (st.Profile.RebirthAt or 1) do
			local gems = F.Economy.RebirthGems(st.Rebirths)
			st.Power = 0
			st.Temp.ClickStrength = 0
			st.Temp.PowerBoost = 0
			st.Rebirths += 1
			addGems(st, gems)
			st.Dirty = true
			mark(st, "rebirth:" .. st.Rebirths)
			questOnce(st, "FirstRebirth")
			checkAchievements(st)
			-- Ir ao altar (na praça) fecha as barreiras atrás: a corrida recomeça.
			if st.Activity and st.Activity.Stage > 0 then
				st.Activity.Overhead = Model.Overhead(st, st.Activity.Stage)
			end
		end
	end

	local function spend(st)
		buyCuts(st)
		buyPowerEggs(st)
		buyTempUpgrades(st)
		buyWithGems(st)
		tryRebirth(st)
	end
	Model.Spend = spend

	-- ── Corredor ────────────────────────────────────────────────────────────
	function Model.ManualCps(st): number
		return HOLD_CPS * st.HoldShare
	end

	-- Dano de um golpe manual médio (combo e overdrive médios do perfil).
	function Model.Hit(st): number
		return Model.PerClick(st) * st.Profile.ComboAvg * st.OdAvg
	end

	-- Golpes para derrubar o estágio (cada golpe só tira uma fileira: o
	-- excedente se perde — WallService.OnClick faz max(hp - dano, 0)).
	function Model.HitsFor(st, order: number, hit: number): number
		local stage = stageOf(st, order)
		return stage.Rows * math.ceil(stage.Hp / math.max(hit, 1e-9))
	end

	-- Golpes por segundo na barreira: os manuais + o auto click (sem combo).
	local function wallHitsPerSecond(st, hit: number): number
		local manual = Model.ManualCps(st) * (st.Profile.WallShare or 0.85)
		local auto = 0
		if st.Profile.AutoClick then
			-- tick do auto vale perClick (sem combo/overdrive): em "golpes médios"
			auto = AUTO_CPS * Model.PerClick(st) / math.max(hit, 1e-9)
			if AUTO_COMBO then
				auto *= st.Profile.ComboAvg
			end
		end
		return manual + auto
	end

	Model.WallHitsPerSecond = wallHitsPerSecond
	Model.StageOf = stageOf

	-- Ida da praça até a barreira N + quebrar de novo as N-1 anteriores.
	function Model.Overhead(st, order: number): number
		local segment = SEGMENTS[order]
		local speed = F.Aura.WalkSpeed({ Owned = {}, Equipped = AURAS[st.AuraIndex].Id })
		local walk = (segment.Barrier - SPAWN_X) / speed
		local hit = Model.Hit(st)
		local hits = 0
		for lower = 1, order - 1 do
			hits += Model.HitsFor(st, lower, hit)
		end
		return walk + hits / math.max(wallHitsPerSecond(st, hit), 1e-9)
	end

	function Model.ClearSeconds(st, order: number): number
		local hit = Model.Hit(st)
		return Model.Overhead(st, order) + Model.HitsFor(st, order, hit) / math.max(wallHitsPerSecond(st, hit), 1e-9)
	end

	local function tower(st)
		local cleared = {}
		for order in st.Cleared do
			cleared[STAGES[order].Id] = true
		end
		return { Cleared = cleared, Highest = st.Highest }
	end

	function Model.RepeatWins(st, order: number): number
		local stage = stageOf(st, order)
		local share = F.WinPad.Share(stage, tower(st), false)
		return F.WinPad.Payout(stage, #stage.Pads, share)
	end

	local function needsWins(st): boolean
		local nextCut = CUTS[st.CutIndex + 1]
		if nextCut and st.Wins < nextCut.RequiredWins then
			return true
		end
		local nextAura = AURAS[st.AuraIndex + 1]
		return nextAura ~= nil and st.Wins < nextAura.RequiredWins and st.Gems >= nextAura.Price * 0.5
	end

	local function chooseActivity(st, sessionLeft: number)
		local frontier = st.Highest + 1
		local profile = st.Profile
		--[[
			Paciência: o jogador só encara a barreira nova se a luta inteira
			(ida + barreiras anteriores + esta) cabe em `Patience` segundos —
			com "≈ 50.000 golpes" na placa, ninguém fica raspando. Fora disso
			ele farma vitórias (se precisa delas) ou só clica (Power igual, sem
			progresso na barreira) e reavalia a cada minuto. ChipsBeyondPatience
			= true é o jogador que raspa a sessão inteira (a fileira não
			regenera dentro da sessão — WallService só refaz depois de abrir).
		]]
		if frontier <= #STAGES then
			local seconds = Model.ClearSeconds(st, frontier)
			if seconds <= (profile.Patience or 600) or st.Highest == 0 then
				st.Activity = { Kind = "Frontier", Stage = frontier, Overhead = Model.Overhead(st, frontier), Progress = 0 }
				return
			end
		end
		-- Farmar vitórias: o estágio com mais vitórias por segundo.
		local best, bestRate = nil, 0
		for order = 1, st.Highest do
			local seconds = Model.ClearSeconds(st, order)
			local rate = Model.RepeatWins(st, order) / math.max(seconds, 1)
			if rate > bestRate then
				best, bestRate = order, rate
			end
		end
		if best and needsWins(st) then
			st.Activity = { Kind = "Farm", Stage = best, Overhead = Model.Overhead(st, best), Progress = 0 }
		elseif frontier <= #STAGES and profile.ChipsBeyondPatience then
			st.Activity = { Kind = "Frontier", Stage = frontier, Overhead = Model.Overhead(st, frontier), Progress = 0 }
		else
			st.Activity = { Kind = "Idle", Stage = 0, Overhead = 0, Progress = 0, Wait = 60 }
		end
	end

	local function clearStage(st, order: number, kind: string)
		local stage = stageOf(st, order)
		if not st.Cleared[order] then
			st.Cleared[order] = true
			st.Highest = math.max(st.Highest, order)
			addGems(st, stage.FirstClearGems)
			-- 1ª conquista: pega o pad x2 (valor cheio) — a corrida termina.
			st.Wins += F.WinPad.Payout(stage, #stage.Pads, 1)
			mark(st, "clear:" .. order)
			st.Dirty = true
		else
			st.Wins += Model.RepeatWins(st, order)
		end
	end

	-- Avança o corredor `dt` segundos de clique (só durante jogo ativo).
	local function advanceWall(st, dt: number, sessionLeft: number)
		if not st.Activity then
			chooseActivity(st, sessionLeft)
		end
		local activity = st.Activity
		if activity.Kind == "Idle" then
			activity.Wait = (activity.Wait or 60) - dt
			if activity.Wait <= 0 then
				st.Activity = nil
				chooseActivity(st, sessionLeft)
			end
			return
		end
		local remaining = dt
		if activity.Overhead > 0 then
			local used = math.min(activity.Overhead, remaining)
			activity.Overhead -= used
			remaining -= used
		end
		if remaining <= 0 then
			return
		end
		local hit = Model.Hit(st)
		local need = Model.HitsFor(st, activity.Stage, hit)
		activity.Progress += wallHitsPerSecond(st, hit) * remaining / need
		if activity.Progress >= 1 then
			clearStage(st, activity.Stage, activity.Kind)
			st.Activity = nil
			chooseActivity(st, sessionLeft)
		end
	end

	-- ── Um passo de jogo ATIVO ──────────────────────────────────────────────
	local function stepActive(st, dt: number, session)
		local profile = st.Profile
		local perClick = Model.PerClick(st)
		local cps = Model.ManualCps(st)
		local manualPower = perClick * profile.ComboAvg * st.OdAvg * cps * dt
		addPower(st, "Click", manualPower)
		st.Clicks += cps * dt
		if profile.AutoClick then
			addPower(st, "Auto", perClick * AUTO_CPS * dt)
		end
		-- Treino: quando não está segurando o clique e está no pedestal.
		local idleShare = 1 - st.HoldShare
		local rate = Model.TrainingRate(st)
		if rate > 0 and idleShare > 0 then
			addPower(st, "Training", perClick * rate * idleShare * (profile.TrainShare or 0) * dt)
		end

		session.Elapsed += dt
		-- Orbes (EventConfig.Pickup).
		session.OrbClock += dt
		local pickup = Cfg.Event.Pickup
		while session.OrbClock >= pickup.IntervalSeconds do
			session.OrbClock -= pickup.IntervalSeconds
			if st.Rng() < (profile.OrbCatch or 0) then
				addPower(st, "Orbs", math.max(perClick * pickup.ClicksWorth, pickup.MinValue))
			end
		end
		-- Boss (EventConfig.Boss): a cada IntervalSeconds no mundo.
		session.BossClock += dt
		local boss = Cfg.Event.Boss
		while session.BossClock >= boss.IntervalSeconds do
			session.BossClock -= boss.IntervalSeconds
			local joined = st.Rng() < (profile.BossJoin or 0)
			local share = profile.BossShare or 1
			if joined then
				-- pool = 0,75 × HP; HP = Σ perClick × 220. Com jogadores do mesmo
				-- porte, share × pool ≈ 165 cliques do próprio jogador.
				addPower(st, "Boss", perClick * boss.ClicksToKill * boss.RewardRatio)
				st.BossKills += 1
				seasonXp(st, Cfg.Season.XpSources.BossDefeated)
				local runeId = F.Rune.Roll("Training", share, st.Rng)
				if runeId then
					for tier, data in RUNE_TIERS do
						if runeId == "Training" .. data.Rarity then
							st.Runes[tier] = (st.Runes[tier] or 0) + 1
							st.Dirty = true
						end
					end
				end
			end
			local othersCount = not st.Overrides.BossBoostParticipantsOnly
			if joined or (othersCount and st.Rng() < (profile.OthersKillBoss or 0)) then
				bossBoost(st)
			end
		end
		-- Baús da sessão (SessionConfig.Chests).
		local chests = Cfg.Session.Chests
		while session.Chest < #chests and session.Elapsed >= chests[session.Chest + 1].Minutes * 60 do
			session.Chest += 1
			local chest = chests[session.Chest]
			addPower(st, "Chests", math.max(perClick * chest.ClicksWorth, Cfg.Session.MinChestPower))
			grant(st, chest.Rewards)
			seasonXp(st, Cfg.Season.XpSources.PlaytimeChest)
		end

		advanceWall(st, dt, session.Length - session.Elapsed)
	end

	function Model.TrainingRate(st): number
		local rate = 0
		for _, station in STATIONS do
			if st.Rebirths >= station.RequiredRebirths then
				rate = math.max(rate, math.min(station.Rate, TRAINING_CAP))
			end
		end
		return rate
	end

	-- AFK: auto click (se tiver o passe) no pedestal de treino.
	local function stepAfk(st, dt: number)
		local profile = st.Profile
		local perClick = Model.PerClick(st)
		if profile.AutoClick then
			addPower(st, "Auto", perClick * AUTO_CPS * dt)
		end
		addPower(st, "Training", perClick * Model.TrainingRate(st) * dt)
		-- Boss morto por outros no servidor ainda dá Power2x a quem está no mundo.
		st.AfkBossClock = (st.AfkBossClock or 0) + dt
		local boss = Cfg.Event.Boss
		while st.AfkBossClock >= boss.IntervalSeconds do
			st.AfkBossClock -= boss.IntervalSeconds
			if not st.Overrides.BossBoostParticipantsOnly and st.Rng() < (profile.OthersKillBoss or 0) then
				bossBoost(st)
			end
		end
	end

	local function tickBoosts(st, dt: number)
		if st.Boost2x > 0 then
			st.Boost2x = math.max(st.Boost2x - dt, 0)
		end
		if st.Luck2x > 0 then
			st.Luck2x = math.max(st.Luck2x - dt, 0)
		end
	end

	-- ── Diário (recompensa, missões, temporada) ─────────────────────────────
	local function newDay(st, activeSeconds: number)
		st.DailyStreak += 1
		local days = Cfg.Daily.Days
		grant(st, days[((st.DailyStreak - 1) % #days) + 1])
		seasonXp(st, Cfg.Season.XpSources.DailyReward)
		local profile = st.Profile
		local manualClicks = HOLD_CPS * st.HoldShare * activeSeconds
		for id, quest in Cfg.Quest.Quests do
			if quest.Repeat == "Daily" then
				local done = (quest.Type == "Clicks" and manualClicks >= quest.Target)
					or (quest.Type == "Playtime" and activeSeconds + (profile.AfkHoursPerDay or 0) * 3600 >= quest.Target)
					or (quest.Type == "Overdrives" and manualClicks >= quest.Target * Cfg.Overdrive.ChargeMax)
				if done then
					grant(st, quest.Rewards)
					seasonXp(st, Cfg.Season.XpSources.QuestClaimed)
				end
			end
		end
		if st.Clicks >= Cfg.Quest.Quests.Click100.Target then
			questOnce(st, "Click100")
		end
	end

	-- ── Snapshot ────────────────────────────────────────────────────────────
	function Model.Snapshot(st)
		local perClick = Model.PerClick(st)
		local hit = Model.Hit(st)
		local frontier = math.min(st.Highest + 1, #STAGES)
		local stage = stageOf(st, frontier)
		local layers = st.Cache.Layers
		return {
			Active = st.Active,
			Calendar = st.Calendar,
			Power = st.Power,
			TotalPower = st.TotalPower,
			PerClick = perClick,
			Hit = hit,
			Rebirths = st.Rebirths,
			Highest = st.Highest,
			Wins = st.Wins,
			Gems = st.Gems,
			TotalGems = st.TotalGems,
			Cut = CUTS[st.CutIndex].Id,
			Aura = AURAS[st.AuraIndex].Id,
			PetMult = layers.Pet,
			RebirthMult = layers.Rebirth,
			UpgradeMult = layers.Upgrade,
			PermMult = layers.Permanent,
			AuraMult = layers.Aura,
			RuneMult = layers.Rune,
			Base = st.Cache.Base,
			Boosted = st.Boost2x > 0,
			Event = Model.EventMultiplier(st),
			FrontierHitsPerRow = math.ceil(stage.Hp / math.max(hit, 1e-9)),
			FrontierSeconds = Model.ClearSeconds(st, frontier),
			TrainingShare = st.Income.Training / math.max(st.TotalPower, 1),
			Income = table.clone(st.Income),
		}
	end

	--[[
		Roda um jogador por `Days` dias de calendário. A cada dia: o tempo ativo
		do perfil (com variação diária de ±Jitter) em `Sessions` sessões, depois
		o AFK (se houver). O resto do dia é offline: o jogo NÃO tem progresso
		offline (nada acumula sem o jogador no servidor).

		opts: Days, Seed, Dt, Overrides, ActiveMarks {s}, CalendarMarks {s},
		      StopWhen = "Colossus" (para o Monte Carlo)
	]]
	--[[
		Overrides de config (cenários): aplicados SÓ durante o Run e desfeitos no
		fim, para os módulos reais (EconomyFormulas lê RebirthConfig na hora)
		verem o valor do cenário.
			RebirthCostGrowth, RebirthMultiplierPerRebirth, RebirthBaseCost
			BossBoostSeconds   duração do Power2x do boss (0 = sem boost)
			BossBoostParticipantsOnly  só quem bateu no boss ganha o Power2x
			EggPrice {[EggId]=preço}
			StageHp {[n]=×}, StageRows {[n]=rows}
	]]
	local function applyOverrides(overrides)
		local saved = {
			CostGrowth = Cfg.Rebirth.CostGrowth,
			MultiplierPerRebirth = Cfg.Rebirth.MultiplierPerRebirth,
			BaseCost = Cfg.Rebirth.BaseCost,
		}
		if overrides.RebirthCostGrowth then
			Cfg.Rebirth.CostGrowth = overrides.RebirthCostGrowth
		end
		if overrides.RebirthMultiplierPerRebirth then
			Cfg.Rebirth.MultiplierPerRebirth = overrides.RebirthMultiplierPerRebirth
		end
		if overrides.RebirthBaseCost then
			Cfg.Rebirth.BaseCost = overrides.RebirthBaseCost
		end
		return function()
			Cfg.Rebirth.CostGrowth = saved.CostGrowth
			Cfg.Rebirth.MultiplierPerRebirth = saved.MultiplierPerRebirth
			Cfg.Rebirth.BaseCost = saved.BaseCost
		end
	end

	function Model.Run(profile, opts)
		local restore = applyOverrides(opts.Overrides or {})
		local ok, result = pcall(Model.RunInner, profile, opts)
		restore()
		if not ok then
			error(result, 0)
		end
		return result
	end

	function Model.RunInner(profile, opts)
		local st = newState(profile, opts)
		local rng = st.Rng
		local dt = opts.Dt or 10
		local jitter = profile.Jitter or 0
		st.HoldShare = math.clamp(profile.HoldShare * (1 + (rng() * 2 - 1) * (profile.HoldJitter or 0)), 0, 1)
		st.OdAvg = profile.OdAvg or Model.OverdriveAverage(HOLD_CPS * st.HoldShare)
		local activeMarks = opts.ActiveMarks or {}
		local calendarMarks = opts.CalendarMarks or {}
		local nextActive, nextCalendar = 1, 1
		st.Dirty = true
		Model.PerClick(st)

		local function snapshots()
			while activeMarks[nextActive] and st.Active >= activeMarks[nextActive] do
				st.Snapshots["A" .. activeMarks[nextActive]] = Model.Snapshot(st)
				nextActive += 1
			end
			while calendarMarks[nextCalendar] and st.Calendar >= calendarMarks[nextCalendar] do
				st.Snapshots["C" .. calendarMarks[nextCalendar]] = Model.Snapshot(st)
				nextCalendar += 1
			end
		end

		for day = 0, opts.Days - 1 do
			st.Day = day
			local dayStart = day * DAY
			local factor = 1 + (rng() * 2 - 1) * jitter
			local activeToday = math.max(profile.HoursPerDay * 3600 * factor, 0)
			local sessions = math.max(profile.Sessions or 1, 1)
			local perSession = activeToday / sessions
			st.Calendar = dayStart
			for _ = 1, sessions do
				local session = { Elapsed = 0, Length = perSession, OrbClock = 0, BossClock = 0, Chest = 0 }
				st.Activity = nil -- barreiras são por servidor: sessão nova, corrida nova
				local t = 0
				while t < perSession do
					local step = math.min(dt, perSession - t)
					stepActive(st, step, session)
					tickBoosts(st, step)
					st.Active += step
					st.Online += step
					st.Calendar += step
					t += step
					spend(st)
					snapshots()
				end
				checkAchievements(st)
				if opts.StopWhen == "Colossus" and st.Cleared[#STAGES] then
					return st
				end
			end
			newDay(st, activeToday)
			local afk = (profile.AfkHoursPerDay or 0) * 3600
			local t = 0
			local afkDt = math.max(dt, 120) -- AFK não tem decisão: passo largo (boss é contado pelo relógio)
			while t < afk do
				local step = math.min(afkDt, afk - t)
				stepAfk(st, step)
				tickBoosts(st, step)
				st.Online += step
				st.Calendar += step
				t += step
				spend(st)
				snapshots()
			end
			-- Offline até o próximo dia (sem progresso offline).
			st.Calendar = (day + 1) * DAY
			snapshots()
		end
		return st
	end

	return Model
end
