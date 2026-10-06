--[[
	check_power_ux.luau — ⚡ PODER x ⚔ DANO: o que a UI mostra é a conta REAL.

		lune run tools/lune/check_power_ux.luau [raiz]

	  1. a regra do servidor: o golpe na barreira é o MESMO ganho de Power do
	     clique (PowerPerClick × combo), não o saldo de Power;
	  2. HitDisplay.Damage / HitsFor batem com essa regra (1B ÷ 318M ≈ 4);
	  3. a prévia ⚔ das melhorias bate com PowerFormula.Compute depois da compra;
	  4. melhorias de Power GASTAM Power (linguagem de custo correta);
	  5. UI: ⚔ no pill do Poder, ⚔ na faixa do corredor (golpes da fileira),
	     "⚡ +X" no ganho do clique, ❤ no HP do painel; economia intocada.
]]
local process = require("@lune/process")
local fs = require("@lune/fs")
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
local function read(path: string): string
	return fs.readFile(E.Root .. "/" .. path)
end

-- 1. Regra do servidor.
local click = read("src/server/Services/ClickService.luau")
local body = string.match(click, "local function processClick.-\nend\n") or ""
check(string.find(body, 'local gain = CurrencyService.Add(player, "Power", PowerService.ComputeClick(player, comboMultiplier)', 1, true)
	and string.find(body, "WallService.OnClick(player, gain)", 1, true), "1. servidor: o golpe na barreira = o Power ganho no clique (PowerPerClick × combo), não o saldo")
local power = read("src/server/Services/PowerService.luau")
check(string.find(power, "return math.min(info.PerClick * combo, GameConfig.Numbers.MaxValue)", 1, true) ~= nil, "1. PowerService.ComputeClick = PerClick × combo")

-- 2. HitDisplay.
local HitDisplay = E.require(E.Shared.Formulas.HitDisplay)
local EconomyFormulas = E.require(E.Shared.Formulas.EconomyFormulas)
local ComboConfig = E.require(E.Shared.Config.ComboConfig)
check(HitDisplay.Damage(318e6, 0) == 318e6 and math.abs(HitDisplay.Damage(318e6, ComboConfig.MaxStacks) - 318e6 * EconomyFormulas.ComboMultiplier(ComboConfig.MaxStacks)) < 1, string.format("2. ⚔ golpe = Poder por clique × combo (sem combo 318M; combo cheio %.0fx)", EconomyFormulas.ComboMultiplier(ComboConfig.MaxStacks)))
check(HitDisplay.HitsFor(1e9, 318e6) == 4 and HitDisplay.HitsFor(0, 5) == 0 and HitDisplay.HitsFor(10, 0) == math.huge, "2. ❤ 1B ÷ ⚔ 318M ≈ 4 golpes")

-- 3. Prévia das melhorias = PowerFormula depois da compra.
local PowerFormula = E.require(E.Shared.Formulas.PowerFormula)
local UpgradeConfig = E.require(E.Shared.Config.UpgradeConfig)
local base, layers = 37, { Upgrade = 1.5, Permanent = 1.2, Rebirth = 4, Pet = 2.5 }
local perClick = PowerFormula.Compute(base, layers)
local info = { PerClick = perClick, Base = base, Layers = layers }
local okPreview = true
for _, case in {
	{ UpgradeConfig.Temporary.ClickStrength, 3, false, function() return PowerFormula.Compute(base + 3 * UpgradeConfig.Temporary.ClickStrength.EffectPerLevel, layers) end },
	{ UpgradeConfig.Temporary.PowerBoost, 2, false, function()
		local l = table.clone(layers)
		l.Upgrade += 2 * UpgradeConfig.Temporary.PowerBoost.EffectPerLevel
		return PowerFormula.Compute(base, l)
	end },
	{ UpgradeConfig.Permanent.GemPower, 1, true, function()
		local l = table.clone(layers)
		l.Permanent += UpgradeConfig.Permanent.GemPower.EffectPerLevel
		return PowerFormula.Compute(base, l)
	end },
} do
	local preview = HitDisplay.PreviewUpgrade(info, case[1], case[2], case[3])
	local real = case[4]()
	if not preview or math.abs(preview - real) > real * 1e-9 then
		okPreview = false
		print(string.format("      %s: prévia %s, real %s", case[1].Id, tostring(preview), tostring(real)))
	end
end
check(okPreview and HitDisplay.PreviewUpgrade(info, UpgradeConfig.Permanent.PetSlots, 1, true) == nil, "3. prévia ⚔ antes → depois das melhorias bate com PowerFormula.Compute (e não aparece em pets/sorte/depósito)")

-- 4. Melhorias de Power gastam Power.
local logic = read("src/server/Logic/UpgradeLogic.luau")
check(UpgradeConfig.Temporary.ClickStrength.Currency == "Power" and UpgradeConfig.Temporary.PowerBoost.Currency == "Power" and string.find(logic, "CurrencyLogic.Remove(data, upgrade.Currency, total)", 1, true) ~= nil, "4. melhorias de ⚡ Poder CONSOMEM Poder: o botão mostra preço (⚡ X), não \"requer\"")

-- 5. UI.
local hud = read("src/client/Controllers/HudController.luau")
local corridor = read("src/client/Controllers/CorridorHudController.luau")
local clickController = read("src/client/Controllers/ClickController.luau")
local upgrades = read("src/client/Controllers/UpgradeController.luau")
local tower = read("src/client/Controllers/TowerController.luau")
local pt = read("src/shared/Localization/Strings/ptBR.luau")
check(string.find(hud, 'Name = "HitDamage"', 1, true) and string.find(hud, "GameStateController.GetHitDamage()", 1, true) and string.find(hud, "Theme.Icons.Damage", 1, true), "5. HUD: ⚔ golpe dentro do pill do Poder (secundário, cor de combate); ⚡ continua o saldo")
check(string.find(corridor, "icon = Theme.Icons.Damage", 1, true) and string.find(corridor, "GameStateController.GetHitDamage()", 1, true) and string.find(corridor, "rowHits", 1, true), "5. faixa do corredor: ⚔ Seu golpe (dano real) e ≈ golpes da FILEIRA da placa de HP")
check(string.find(clickController, 'Theme.Icons.Power .. " +"', 1, true) and string.find(pt, '["click.auto"] = "⚡ +{amount} (auto)"', 1, true), "5. ganho do clique explícito: \"⚡ +X\" (Poder), nunca confundido com dano")
check(string.find(upgrades, "HitDisplay.PreviewUpgrade", 1, true) and string.find(pt, '⚔ dano', 1, true), "5. melhorias: prévia ⚔ antes → depois e descrições dizendo Poder E dano")
check(string.find(tower, '"tower.attack"', 1, true) and string.find(pt, '["tower.detail"] = "{rows} fileiras de ❤ {hp}', 1, true), "5. painel Progresso: ⚡ Poder · ⚔ golpe + decomposição (base × camadas × combo); ❤ no HP")
-- Nada de nova moeda / economia.
local EconomyConfig = E.require(E.Shared.Config.EconomyConfig)
local currencyIds = {}
for id in EconomyConfig.Currencies do
	table.insert(currencyIds, id)
end
table.sort(currencyIds)
local hitSource = read("src/shared/Formulas/HitDisplay.luau")
check(table.concat(currencyIds, ",") == "Gems,Power,Wins" and not string.find(hitSource, "Services", 1, true) and not string.find(hitSource, "FireServer", 1, true), "5. ⚔ Dano não é moeda: as moedas continuam Power/Gems/Wins e HitDisplay só calcula (nada de serviço ou remote)")

if #problems > 0 then
	print(#problems .. " problema(s).")
	process.exit(1)
end
print("OK: ⚡ Poder (saldo) e ⚔ Dano (golpe real) separados e explicados pela fórmula real.")
print("REQUER VALIDAÇÃO NO ROBLOX STUDIO: leitura do HUD no celular, ⚔ no pill, faixa do corredor e prévias das melhorias.")
process.exit(0)
