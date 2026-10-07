--[[
	check_progression_ux.luau — UX de progressão (só leitura, sem economia nova):
	"Já está na hora de renascer?" e "Já estou forte para o Colosso?".

		lune run tools/lune/check_progression_ux.luau [raiz]

	R. Renascer disponível — fonte única (ProgressionUx ← EconomyFormulas,
	   a MESMA do RebirthLogic do servidor, com a âncora do C2-E): R0, R7 e R15
	   migrados; Power abaixo / exatamente / acima do custo; gastar Power;
	   multiplicador antes/depois; Stats corrompido.
	N. Aviso "RENASCER DISPONÍVEL": uma vez ao abrir, não repete, fecha quando
	   o Power cai, reabre com intervalo mínimo (sem spam).
	P. Painel/selo REAIS (RebirthController): R → R+1, ⚡ custo ancorado,
	   ×A → ×B, "⚡ Faltam X" / "✓ RENASCER DISPONÍVEL", selo "!", aviso, altar.
	S. Altar (StationFxController REAL sobre o lobby gerado): estado
	   disponível por jogador, discreto, Efeitos reduzidos, nada de Part/luz.
	C. Colosso — classificação (300/100) e aviso de travessia.
	W. Placa + faixa REAIS (WallController + CorridorHudController), um
	   ambiente por jogador: ≈10,5K → EXTREMO, ≈271 → PREPARANDO, ≈82 → PRONTO;
	   dano muda; HP da fileira muda; fileira avança; dois jogadores com
	   estados diferentes no MESMO Colosso; respawn; Efeitos reduzidos;
	   celular (textos curtos); estágios 1–9 sem mudança; a placa mais alta
	   continua fora da HUD em 1920x1080, 1366x768, tablet e celular.

	REQUER VALIDAÇÃO NO ROBLOX STUDIO: leitura real da placa/etiqueta, emoji
	nas fontes, tamanho real da placa no celular, toque, ritmo do aviso.
]]
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local V3 = roblox.Vector3
local CF = roblox.CFrame

local problems = {}
local function check(condition: any, message: string)
	if condition then
		print("OK   " .. message)
	else
		table.insert(problems, message)
		print("FALHA " .. message)
	end
end

local Sig = {
	Connect = function()
		return { Disconnect = function() end }
	end,
	Once = function()
		return { Disconnect = function() end }
	end,
	Wait = function() end,
}
for _, pair in {
	{ "Instance", { "Changed", "ChildAdded", "ChildRemoved", "Destroying", "AncestryChanged", "AttributeChanged", "DescendantAdded" } },
	{ "GuiObject", { "InputBegan", "InputEnded", "InputChanged", "MouseEnter", "MouseLeave" } },
	{ "GuiButton", { "Activated", "MouseButton1Click" } },
} do
	for _, name in pair[2] do
		roblox.implementProperty(pair[1], name, function()
			return Sig
		end)
	end
end
roblox.implementMethod("Instance", "GetPropertyChangedSignal", function()
	return Sig
end)
roblox.implementMethod("Instance", "GetAttributeChangedSignal", function()
	return Sig
end)
roblox.implementMethod("ParticleEmitter", "Emit", function() end)

local root = process.args[1]
local E = require("./env")(root)
local F = E.require(E.Shared.Formulas.EconomyFormulas)
local PU = E.require(E.Shared.Formulas.ProgressionUx)
local RebirthLogic = E.require(E.Server.Logic.RebirthLogic)
local DataTemplate = E.require(E.Server.Services.DataService.DataTemplate)
local NumberFormat = E.require(E.Shared.Utils.NumberFormat)
local WallConfigE = E.require(E.Shared.Config.WallConfig)

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for key, item in value do
		out[key] = deepCopy(item)
	end
	return out
end
local function save(rebirths, anchor, power)
	local data = DataTemplate.Create(0)
	data.Stats = data.Stats or {}
	data.Currencies = data.Currencies or {}
	data.Stats.Rebirths = rebirths
	data.Stats.RebirthAnchor = anchor
	data.Currencies.Power = power
	return data
end

-- ── R. Renascer disponível: fonte única ─────────────────────────────────────
local cases = {
	{ "R0 (save novo)", 0, 0 },
	{ "R7 migrado", 7, 7 },
	{ "R15 migrado", 15, 15 },
	{ "R3 novo", 3, 0 },
	{ "R9 migrado em R7", 9, 7 },
}
local sameCost = true
for _, case in cases do
	local data = save(case[2], case[3], 0)
	local view = PU.Rebirth(data.Stats, 0)
	local server = RebirthLogic.GetCost(data)
	local direct = F.RebirthCost(case[2], case[3])
	if view.Cost ~= server or server ~= direct then
		sameCost = false
		print(string.format("      %s: tela %s servidor %s fórmula %s", case[1], tostring(view.Cost), tostring(server), tostring(direct)))
	end
	print(string.format("      %-18s custo do próximo: %s (R%d → R%d)  ×%s → ×%s", case[1], NumberFormat.Short(view.Cost), view.Rebirths, view.Next, NumberFormat.Short(view.MultiplierNow), NumberFormat.Short(view.MultiplierNext)))
end
check(sameCost, "R1. custo real do próximo renascimento: tela = RebirthLogic.GetCost (servidor) = EconomyFormulas.RebirthCost(R, âncora) em R0, R3, R7/R15 migrados e R9 ancorado em R7")
check(PU.Rebirth({ Rebirths = 0, RebirthAnchor = 0 }, 0).Cost == 1_000_000, "R2. R0: custo 1M (C2-E)")
local r7 = PU.Rebirth({ Rebirths = 7, RebirthAnchor = 7 }, 0)
check(r7.Cost == math.ceil(200_000 * 3.2 ^ 7) and r7.Cost < 1_000_000 * 5.5 ^ 7, string.format("R3. R7 migrado: custo ancorado %s (curva antiga no R0), não %s da curva nova", NumberFormat.Short(r7.Cost), NumberFormat.Short(1_000_000 * 5.5 ^ 7)))
local r15 = PU.Rebirth({ Rebirths = 15, RebirthAnchor = 15 }, 0)
check(r15.Cost == math.ceil(200_000 * 3.2 ^ 15), string.format("R4. R15 migrado: custo ancorado %s", NumberFormat.Short(r15.Cost)))

local powerOk = true
for _, case in cases do
	local data = save(case[2], case[3], 0)
	local cost = RebirthLogic.GetCost(data)
	for _, p in { { cost - 1, false }, { cost, true }, { cost * 3, true }, { 0, false } } do
		data.Currencies.Power = p[1]
		local view = PU.Rebirth(data.Stats, p[1])
		local serverOk = RebirthLogic.CanRebirth(data)
		if view.Ready ~= p[2] or serverOk ~= p[2] then
			powerOk = false
			print(string.format("      %s Power %s: tela %s servidor %s", case[1], tostring(p[1]), tostring(view.Ready), tostring(serverOk)))
		end
		if not view.Ready and view.Missing ~= cost - p[1] then
			powerOk = false
		end
		if view.Ready and view.Missing ~= 0 then
			powerOk = false
		end
	end
end
check(powerOk, "R5. Power abaixo (faltam 1) / exatamente no custo / acima / zerado: tela e servidor (CanRebirth) dizem o mesmo; \"faltam\" = custo − Power")

-- Gastar Power: estava disponível, gasta numa melhoria, deixa de estar.
local spend = PU.Rebirth({ Rebirths = 0 }, 1_000_000)
local spent = PU.Rebirth({ Rebirths = 0 }, 1_000_000 - 250_000)
check(spend.Ready and not spent.Ready and spent.Missing == 250_000, "R6. gastar Power abaixo do custo volta para \"⚡ Faltam 250K\"")
local multOk = true
for r = 0, 20 do
	local view = PU.Rebirth({ Rebirths = r }, 0)
	if math.abs(view.MultiplierNow - 1.75 ^ r) > 1e-9 * 1.75 ^ r or math.abs(view.MultiplierNext - 1.75 ^ (r + 1)) > 1e-9 * 1.75 ^ (r + 1) then
		multOk = false
	end
	if view.MultiplierNow ~= F.RebirthMultiplier(r) or view.Gems ~= F.RebirthGems(r) then
		multOk = false
	end
end
check(multOk, "R7. multiplicador permanente ×1,75^R → ×1,75^(R+1) (EconomyFormulas.RebirthMultiplier) e gemas = RebirthGems")
local corrupt = true
for _, bad in { { Rebirths = 0 / 0, RebirthAnchor = -3 }, { Rebirths = -2 }, { Rebirths = 4.7, RebirthAnchor = 4.2 }, {} } do
	local data = save(0, 0, 0)
	data.Stats = bad
	if PU.Rebirth(bad, 0).Cost ~= RebirthLogic.GetCost(data) or PU.Rebirth(bad, 0).Rebirths ~= RebirthLogic.GetRebirths(data) then
		corrupt = false
	end
end
check(corrupt, "R8. Stats corrompido (NaN, negativo, fracionado, vazio): tela e servidor saneiam igual (EconomyFormulas.RebirthsOf/RebirthAnchorOf)")

-- ── N. Aviso "RENASCER DISPONÍVEL" ──────────────────────────────────────────
local notice = PU.NewRebirthNotice(120)
local seq = {
	{ 0, false, false, "sem Power" },
	{ 10, true, true, "atinge o custo: avisa" },
	{ 11, true, false, "continua disponível: não repete" },
	{ 50, true, false, "continua disponível: não repete" },
	{ 60, false, false, "gastou Power: fecha" },
	{ 70, true, false, "volta em 60 s: dentro do intervalo, só o selo" },
	{ 80, false, false, "gastou de novo" },
	{ 200, true, true, "volta depois de 120 s: avisa de novo" },
}
local seqOk = true
for _, step in seq do
	local fired = notice:Update(step[2], step[1])
	if fired ~= step[3] then
		seqOk = false
		print(string.format("      t=%d %s: avisou=%s", step[1], step[4], tostring(fired)))
	end
end
check(seqOk, "N1. aviso só quando passa a ficar disponível; não repete; Power cai = fecha; reabre só após 120 s")
local join = PU.NewRebirthNotice()
check(join:Update(true, 5) == true and join:Update(true, 6) == false, "N2. entrou já com Power suficiente: avisa uma vez")
local spam = PU.NewRebirthNotice()
local fires = 0
for t = 0, 600, 0.5 do
	if spam:Update(math.floor(t) % 2 == 0, t) then
		fires += 1
	end
end
check(fires <= 6, string.format("N3. Power oscilando no limite por 10 min: %d avisos (máx. 1 a cada 2 min)", fires))

-- ── P. Painel e selo reais (RebirthController) ──────────────────────────────
do
	local P = require("./env")(root)
	local client = "StarterPlayer.Client."
	P.stubs.TweenService = { Create = function()
		return { Play = function() end, Cancel = function() end, Completed = Sig }
	end }
	P.extraGlobals.TweenInfo = { new = function(...)
		return { ... }
	end }
	local store = { Currencies = { Power = 0 }, Stats = { Rebirths = 7, RebirthAnchor = 7 }, Settings = { ReducedEffects = false } }
	local changed = {}
	P.stubModules[client .. "Controllers.DataController"] = {
		Get = function(key)
			return store[key]
		end,
		Changed = { Connect = function(_, fn)
			table.insert(changed, fn)
			return { Disconnect = function() end }
		end },
	}
	local canvas = roblox.Instance.new("Frame")
	local content = roblox.Instance.new("Frame")
	P.stubModules[client .. "Controllers.UIController"] = {
		CreatePanel = function()
			return roblox.Instance.new("Frame"), content
		end,
		GetCanvas = function()
			return canvas
		end,
		TogglePanel = function() end,
		ClosePanel = function() end,
		IsTouch = function()
			return false
		end,
	}
	local badge = { Visible = false }
	local button = roblox.Instance.new("TextButton")
	P.stubModules[client .. "Controllers.MenuController"] = {
		AddButton = function()
			return button
		end,
		SetBadge = function(_, visible)
			badge.Visible = visible
		end,
	}
	local toasts = {}
	P.stubModules[client .. "Controllers.NotificationController"] = { Show = function(text, style)
		table.insert(toasts, { text, style })
	end }
	local altar = { Ready = nil, Calls = 0 }
	P.stubModules[client .. "Controllers.StationFxController"] = { SetRebirthReady = function(ready)
		altar.Ready = ready
		altar.Calls += 1
	end }
	P.stubModules[client .. "Controllers.SoundController"] = { Play = function() end }
	P.stubModules[client .. "Net.ClientNet"] = { Invoke = function()
		return { Ok = true }
	end, On = function() end, Fire = function() end }
	local Rebirth = P.require(P.Client.Controllers.RebirthController)
	Rebirth.Init()
	local function set(key, value)
		store[key] = value
		for _, fn in changed do
			fn(key, value)
		end
	end
	local function labels()
		local list = {}
		for _, d in content:GetDescendants() do
			if d:IsA("TextLabel") or d:IsA("TextButton") then
				table.insert(list, d.Text)
			end
		end
		return table.concat(list, " | ")
	end
	local cost = F.RebirthCost(7, 7)
	set("Currencies", { Power = cost - 1000 })
	local text = labels()
	print("      painel (abaixo do custo): " .. string.gsub(text, "\n", " / "))
	check(string.find(text, "R7 → R8", 1, true) and string.find(text, NumberFormat.Short(cost), 1, true) ~= nil, "P1. painel: \"Renascimento: R7 → R8\" e \"Custo: ⚡ " .. NumberFormat.Short(cost) .. "\" (ancorado do save migrado)")
	check(string.find(text, "×" .. NumberFormat.Short(1.75 ^ 7) .. " → ×" .. NumberFormat.Short(1.75 ^ 8), 1, true) ~= nil, "P2. painel: \"Poder permanente: ×" .. NumberFormat.Short(1.75 ^ 7) .. " → ×" .. NumberFormat.Short(1.75 ^ 8) .. "\"")
	check(string.find(text, "Faltam " .. NumberFormat.Short(1000), 1, true) ~= nil and not badge.Visible and #toasts == 0 and altar.Ready == false, "P3. abaixo do custo: \"⚡ Faltam 1K\", sem selo, sem aviso, altar normal")
	set("Currencies", { Power = cost })
	text = labels()
	print("      painel (no custo):        " .. string.gsub(text, "\n", " / "))
	check(string.find(text, "RENASCER DISPONÍVEL", 1, true) ~= nil and badge.Visible and altar.Ready == true, "P4. exatamente no custo: \"✓ RENASCER DISPONÍVEL\", selo \"!\" no botão, altar disponível")
	check(#toasts == 1 and toasts[1][1] == "♻ RENASCER DISPONÍVEL! Fique mais forte permanentemente.", "P5. aviso \"♻ RENASCER DISPONÍVEL! Fique mais forte permanentemente.\" uma vez")
	set("Currencies", { Power = cost * 2 })
	set("Stats", { Rebirths = 7, RebirthAnchor = 7 })
	check(#toasts == 1 and badge.Visible, "P6. Power subindo / Stats de novo: sem repetir o aviso")
	-- Renasceu: o servidor zera o Power e soma 1.
	set("Stats", { Rebirths = 8, RebirthAnchor = 7 })
	set("Currencies", { Power = 0 })
	text = labels()
	check(not badge.Visible and altar.Ready == false and string.find(text, "R8 → R9", 1, true) ~= nil and string.find(text, NumberFormat.Short(F.RebirthCost(8, 7)), 1, true) ~= nil, "P7. depois do Rebirth: selo some, altar volta ao normal, painel R8 → R9 com o custo seguinte")
	check(altar.Calls >= 4, "P8. tudo por evento (DataController.Changed): nenhum loop no painel")
end

-- ── B. Selo "!" do botão lateral (MenuController REAL + RebirthController) ──
do
	local M = require("./env")(root)
	local client = "StarterPlayer.Client."
	M.stubs.TweenService = { Create = function()
		return { Play = function() end, Cancel = function() end, Completed = Sig }
	end }
	M.extraGlobals.TweenInfo = { new = function(...)
		return { ... }
	end }
	local store = { Currencies = { Power = 0 }, Stats = { Rebirths = 0, RebirthAnchor = 0 }, Settings = { ReducedEffects = false } }
	local changed = {}
	M.stubModules[client .. "Controllers.DataController"] = {
		Get = function(key)
			return store[key]
		end,
		Changed = { Connect = function(_, fn)
			table.insert(changed, fn)
			return { Disconnect = function() end }
		end },
	}
	local canvas = roblox.Instance.new("Frame")
	M.stubModules[client .. "Controllers.UIController"] = {
		CreatePanel = function()
			return roblox.Instance.new("Frame"), roblox.Instance.new("Frame")
		end,
		GetCanvas = function()
			return canvas
		end,
		CenterOf = function()
			return roblox.Vector2.new(0, 0)
		end,
		PanelChanged = Sig,
		TogglePanel = function() end,
		ClosePanel = function() end,
		IsTouch = function()
			return false
		end,
	}
	M.stubModules[client .. "Controllers.NotificationController"] = { Show = function() end }
	M.stubModules[client .. "Controllers.StationFxController"] = { SetRebirthReady = function() end }
	M.stubModules[client .. "Controllers.SoundController"] = { Play = function() end }
	M.stubModules[client .. "Net.ClientNet"] = { Invoke = function()
		return { Ok = true }
	end, On = function() end, Fire = function() end }
	local Menu = M.require(M.Client.Controllers.MenuController)
	local Rebirth = M.require(M.Client.Controllers.RebirthController)
	Rebirth.Init()
	local button = Menu.GetButton("Rebirth")
	local badge = button and button:FindFirstChild("Badge")
	local function set(stats, power)
		store.Stats = stats
		store.Currencies = { Power = power }
		for _, fn in changed do
			fn("Stats", stats)
			fn("Currencies", store.Currencies)
		end
		return badge.Visible
	end
	local strokes = 0
	for _, child in badge:GetChildren() do
		if child:IsA("UIStroke") then
			strokes += 1
		end
	end
	check(badge ~= nil and badge.Text == "!" and strokes == 0 and badge.TextScaled, "B0. selo do botão Renascer: \"!\" (componente comum), sem contorno de texto que vire \"0\" com a escala da HUD")
	local cost0 = F.RebirthCostFor({ Rebirths = 0, RebirthAnchor = 0 })
	check(set({ Rebirths = 0, RebirthAnchor = 0 }, cost0 - 1) == false, "B1. abaixo do custo: sem \"!\"")
	check(set({ Rebirths = 0, RebirthAnchor = 0 }, cost0) == true and badge.Text == "!", "B2. exatamente no custo: \"!\"")
	check(set({ Rebirths = 0, RebirthAnchor = 0 }, cost0 * 10) == true, "B3. acima do custo: \"!\"")
	-- Renasceu: o servidor zera o Power; o selo recalcula pelo custo seguinte.
	check(set({ Rebirths = 1, RebirthAnchor = 0 }, 0) == false, "B4. depois do Rebirth sem Power suficiente: \"!\" some (custo seguinte " .. NumberFormat.Short(F.RebirthCostFor({ Rebirths = 1 })) .. ")")
	local cost1 = F.RebirthCostFor({ Rebirths = 1, RebirthAnchor = 0 })
	check(set({ Rebirths = 1, RebirthAnchor = 0 }, cost1 + 5) == true, "B5. depois do Rebirth ainda com Power para outro: \"!\" permanece")
	local cost7 = F.RebirthCostFor({ Rebirths = 7, RebirthAnchor = 7 })
	check(cost7 == RebirthLogic.GetCost(save(7, 7, 0)) and set({ Rebirths = 7, RebirthAnchor = 7 }, cost7) == true and set({ Rebirths = 7, RebirthAnchor = 7 }, cost7 - 1) == false and set({ Rebirths = 7, RebirthAnchor = 0 }, cost7) == false, "B6. save R7 migrado: \"!\" no custo ancorado " .. NumberFormat.Short(cost7) .. " (sem âncora o mesmo Power não bastaria)")
	local cost15 = F.RebirthCostFor({ Rebirths = 15, RebirthAnchor = 15 })
	check(cost15 == RebirthLogic.GetCost(save(15, 15, 0)) and set({ Rebirths = 15, RebirthAnchor = 15 }, cost15) == true and set({ Rebirths = 15, RebirthAnchor = 15 }, cost15 - 1) == false, "B7. save R15 migrado: \"!\" no custo ancorado " .. NumberFormat.Short(cost15))
	-- O caso do Studio: Power ~6,45B com o próximo custando ~20,97M.
	local studioCost = F.RebirthCostFor({ Rebirths = 4, RebirthAnchor = 4 })
	check(math.abs(studioCost - 20.97e6) < 0.01e6 and set({ Rebirths = 4, RebirthAnchor = 4 }, 6.45e9) == true and badge.Text == "!", "B8. caso do Studio (save migrado R4: custo " .. NumberFormat.Short(studioCost) .. ", Power 6,45B): \"!\", nunca \"0\"")
end

-- ── S. Altar: estado disponível (StationFxController real) ──────────────────
do
	local S = require("./env")(root)
	local WorldBuilder = S.require(S.Server.World.WorldBuilder)
	local WorldConfig = S.require(S.Shared.Config.WorldConfig)
	local world = WorldBuilder.Build(WorldConfig.Worlds[WorldConfig.DefaultWorld], V3.new(0, 0, 0), S.Instance.new("Folder"), S.Instance.new("Folder"), true)
	local machine = world:FindFirstChild("Station_Rebirth_Machine", true)
	local core = machine and machine:FindFirstChild("RebirthCore", true)
	local rise = nil
	for _, d in (if machine then machine:GetDescendants() else {}) do
		if d.Name == "RebirthRise" and d:IsA("ParticleEmitter") then
			rise = d
		end
	end
	check(machine ~= nil and core ~= nil and rise ~= nil, "S0. altar do lobby gerado (Station_Rebirth_Machine, RebirthCore, RebirthRise)")
	local tagged = {}
	for _, d in world:GetDescendants() do
		for _, tag in d:GetTags() do
			tagged[tag] = tagged[tag] or {}
			table.insert(tagged[tag], d)
		end
	end
	S.stubs.CollectionService = {
		GetTagged = function(_, tag)
			return tagged[tag] or {}
		end,
		GetInstanceAddedSignal = function()
			return Sig
		end,
		GetInstanceRemovedSignal = function()
			return Sig
		end,
	}
	local camera = { CFrame = CF.new(core.CFrame.Position + V3.new(0, 4, -20)) }
	S.stubs.Workspace = setmetatable({ CurrentCamera = camera }, { __index = S.Workspace })
	local playerGui = S.Instance.new("Folder")
	playerGui.Name = "PlayerGui"
	local character = S.Instance.new("Model")
	local playerRoot = S.Instance.new("Part")
	playerRoot.Name = "HumanoidRootPart"
	playerRoot.Parent = character
	playerRoot.CFrame = CF.new(core.CFrame.Position + V3.new(0, 0, -40))
	local localPlayer = {
		Character = character,
		GetAttribute = function()
			return nil
		end,
		GetAttributeChangedSignal = function()
			return Sig
		end,
		FindFirstChildOfClass = function(_, class)
			return if class == "PlayerGui" then playerGui else nil
		end,
	}
	S.stubs.Players = { GetPlayers = function()
		return { { Character = character } }
	end, LocalPlayer = localPlayer }
	local settings = { ReducedEffects = false }
	S.stubModules["StarterPlayer.Client.Controllers.DataController"] = {
		Get = function(key)
			return if key == "Settings" then settings else nil
		end,
		Changed = Sig,
	}
	S.patches["StarterPlayer.Client.Controllers.StationFxController"] = {
		{ "root.Position", "root.CFrame.Position", "all" },
		{ "core.Part.Position", "core.Part.CFrame.Position", "all" },
		{ "pulse.Part.Position", "pulse.Part.CFrame.Position", "all" },
		{ "localRoot.Position", "localRoot.CFrame.Position", "all" },
		{ "screen.Part.Position", "screen.Part.CFrame.Position", "all" },
		{ "flash.Part.Position", "flash.Part.CFrame.Position", "all" },
		{ "holo.Part.Position", "holo.Part.CFrame.Position", "all" },
		{ "(mine - part.Position)", "(mine - part.CFrame.Position)", "all" },
	}
	local Fx = S.require(S.Client.Controllers.StationFxController)
	Fx.Init()
	local before = #machine:GetDescendants()
	local t = 1000
	local function run(seconds)
		for _ = 1, math.floor(seconds * 60) do
			t += 1 / 60
			Fx.Step(t)
		end
	end
	-- Mesmo instante de fase do pulso, pronto x normal.
	local function sample()
		local peak, rate = 1, 0
		for _ = 1, 120 do
			t += 1 / 60
			Fx.Step(t)
			peak = math.min(peak, core.Transparency)
			rate = math.max(rate, rise.Rate)
		end
		return peak, rate
	end
	run(2)
	local idlePeak, idleRate = sample()
	local _, _, noTag = Fx.RebirthReady()
	check(noTag == nil and #playerGui:GetChildren() == 0, "S1. sem renascer disponível: nada criado, altar como antes")
	Fx.SetRebirthReady(true)
	run(3)
	local readyPeak, readyRate = sample()
	local ready, weight, tag = Fx.RebirthReady()
	print(string.format("      núcleo (menor transparência) %.3f → %.3f · partículas subindo %.1f → %.1f/s · peso %.2f", idlePeak, readyPeak, idleRate, readyRate, weight))
	check(ready and weight > 0.95 and readyPeak < idlePeak and readyPeak >= idlePeak - 0.1, "S2. disponível: núcleo um pouco mais intenso (≤ 0,1 de transparência a menos)")
	check(readyRate > idleRate and readyRate <= (rise:GetAttribute("EngagedRate") or 7), "S3. disponível: um pouco mais de partículas subindo, abaixo do \"jogador no altar\"")
	local label = tag and tag:FindFirstChild("Text")
	check(tag ~= nil and tag.Enabled and tag.Adornee == core and label and label.Text == "♻ RENASCER DISPONÍVEL" and tag.Parent == playerGui, "S4. etiqueta local \"♻ RENASCER DISPONÍVEL\" no núcleo (BillboardGui no PlayerGui deste jogador)")
	local lights, parts = 0, 0
	for _, d in playerGui:GetDescendants() do
		if d:IsA("Light") then
			lights += 1
		elseif d:IsA("BasePart") then
			parts += 1
		end
	end
	check(#machine:GetDescendants() == before and lights == 0 and parts == 0 and #playerGui:GetDescendants() == 2, string.format("S5. custo: 2 instâncias (BillboardGui + TextLabel), 0 Part, 0 PointLight, 0 ParticleEmitter novo; altar com %d peças/instâncias como antes", before))
	settings.ReducedEffects = true
	run(2)
	local _, reducedRate = sample()
	local stillText = label.TextTransparency
	run(0.3)
	check(not rise.Enabled and reducedRate <= idleRate + 1e-6 and label.TextTransparency == stillText and tag.Enabled, "S6. Efeitos reduzidos: partículas do altar desligadas, sem reforço e etiqueta parada (o aviso fica)")
	settings.ReducedEffects = false
	run(1.2)
	for _ = 1, 5 do
		Fx.SetRebirthReady(false)
		Fx.SetRebirthReady(true)
	end
	check(#playerGui:GetDescendants() == 2, "S7. liga/desliga várias vezes: a etiqueta é criada uma vez só")
	Fx.SetRebirthReady(false)
	run(3)
	local backPeak = sample()
	local _, offWeight = Fx.RebirthReady()
	check(not tag.Enabled and offWeight < 0.05 and math.abs(backPeak - idlePeak) < 0.02, "S8. Power caiu / renasceu: etiqueta some e o altar volta ao normal")
end

-- ── C. Colosso: classificação ───────────────────────────────────────────────
local colossus = WallConfigE.Stages[10]
check(colossus.Id == "Colossus" and colossus.Hp == 288_000_000_000 and colossus.Rows == 10, "C0. Colosso intocado: 288B × 10 fileiras (C2-E)")
local rowHp = colossus.Hp
local samples = {
	{ 10_500, "Extreme" },
	{ 271, "Preparing" },
	{ 82, "Ready" },
	{ 301, "Extreme" },
	{ 300, "Preparing" },
	{ 101, "Preparing" },
	{ 100, "Ready" },
	{ 1, "Ready" },
}
local classOk = true
for _, sample in samples do
	local damage = rowHp / sample[1]
	local level, hits = PU.ColossusState(rowHp, damage)
	if level ~= sample[2] or hits ~= sample[1] then
		classOk = false
		print(string.format("      %d golpes: %s (%d)", sample[1], level, hits))
	end
end
check(classOk, "C1. ≈10.500 golpes/fileira → EXTREMO; ≈271 → PREPARANDO; ≈82 → PRONTO; limites 301/300 e 101/100")
local zeroLevel, zeroHits = PU.ColossusState(rowHp, 0)
check(zeroLevel == "Extreme" and zeroHits == math.huge, "C2. sem dano: EXTREMO (∞), nunca PRONTO")
local cn = PU.NewColossusNotice()
local seqC = {
	{ "Extreme", 10_500, nil },
	{ "Extreme", 9_000, nil },
	{ "Preparing", 271, "Preparing" },
	{ "Extreme", 320, nil },
	{ "Preparing", 290, nil },
	{ "Ready", 82, "Ready" },
	{ "Preparing", 110, nil },
	{ "Ready", 90, nil },
}
local cnOk = true
for _, step in seqC do
	local got = cn:Update(step[1], step[2])
	if got ~= step[3] then
		cnOk = false
		print(string.format("      %s: aviso %s", step[1], tostring(got)))
	end
end
check(cnOk, "C3. aviso só ao SUBIR de estado (1x PREPARAÇÃO, 1x PRONTO); combo oscilando não repete")
local base = PU.NewColossusNotice()
check(base:Update("Ready", math.huge) == nil and base:Update("Ready", 80) == nil and base.Best == 3, "C4. primeira leitura vira base (sem aviso ao entrar); leitura sem dano ignorada")

-- ── W. Placa e faixa reais, um ambiente por jogador ─────────────────────────
local function makeClient(name: string)
	local C = require("./env")(root)
	local playerGui = roblox.Instance.new("Folder")
	playerGui.Name = "PlayerGui"
	local hrp = roblox.Instance.new("Part")
	hrp.Name = "HumanoidRootPart"
	local character = roblox.Instance.new("Model")
	hrp.Parent = character
	local localPlayer = {
		Name = name,
		UserId = #name,
		LocaleId = "pt-br",
		Character = character,
		WaitForChild = function(_, n)
			return if n == "PlayerGui" then playerGui else nil
		end,
		FindFirstChild = function(_, n)
			return if n == "PlayerGui" then playerGui else nil
		end,
		GetAttribute = function()
			return nil
		end,
		GetAttributeChangedSignal = function()
			return Sig
		end,
	}
	C.stubs.Players = { LocalPlayer = localPlayer, GetPlayers = function()
		return { localPlayer }
	end, PlayerAdded = Sig, PlayerRemoving = Sig }
	C.stubs.TweenService = { Create = function()
		return { Play = function() end, Cancel = function() end, Completed = Sig }
	end }
	local beats = {}
	C.stubs.RunService.Heartbeat = { Connect = function(_, fn)
		table.insert(beats, fn)
		return { Disconnect = function() end }
	end }
	C.extraGlobals.TweenInfo = { new = function(...)
		return { ... }
	end }
	local camera = { ViewportSize = roblox.Vector2.new(1920, 1080) }
	C.stubs.Workspace = setmetatable({ CurrentCamera = camera }, { __index = function(_, key)
		local value = C.Workspace[key]
		if type(value) == "function" then
			return function(_, ...)
				return value(C.Workspace, ...)
			end
		end
		return value
	end })
	local handlers = {}
	local client = "StarterPlayer.Client."
	local topStack = roblox.Instance.new("Frame")
	local settings = { ReducedEffects = false }
	local state = { Damage = 0, Touch = false }
	local toasts = {}
	C.stubModules[client .. "Net.ClientNet"] = { On = function(n, fn)
		handlers[n] = fn
		return { Disconnect = function() end }
	end, Fire = function() end, Invoke = function()
		return { Ok = false }
	end }
	C.stubModules[client .. "Controllers.SoundController"] = { Play = function() end }
	C.stubModules[client .. "Controllers.NotificationController"] = { Show = function(text)
		table.insert(toasts, text)
	end }
	C.stubModules[client .. "Controllers.HudController"] = { GetTopStack = function()
		return topStack
	end }
	C.stubModules[client .. "Controllers.UIController"] = { TogglePanel = function() end, IsTouch = function()
		return state.Touch
	end }
	C.stubModules[client .. "Controllers.GameStateController"] = { GetPowerInfo = function()
		return { PerClick = state.Damage }
	end, GetHitDamage = function()
		return state.Damage
	end }
	C.stubModules[client .. "Controllers.DataController"] = { Get = function(k)
		return if k == "Settings" then settings else nil
	end, IsLoaded = function()
		return false
	end }
	for _, n in { "WallController", "CorridorHudController" } do
		C.patches[client .. "Controllers." .. n] = {
			{ "row.Position", "row.CFrame.Position", "all" },
			{ "root.Position", "root.CFrame.Position", "all" },
		}
	end
	local map = roblox.Instance.new("Folder")
	map.Name = "Map"
	local worlds = roblox.Instance.new("Folder")
	worlds.Name = "Worlds"
	worlds.Parent = map
	local spawns = roblox.Instance.new("Folder")
	spawns.Name = "Spawns"
	spawns.Parent = map
	map.Parent = C.Workspace
	local WallConfig = C.require(C.Shared.Config.WallConfig)
	local worldModel = C.require(C.Server.World.WorldBuilder).Build(C.require(C.Shared.Config.WorldConfig).Worlds[WallConfig.WorldId], V3.new(0, 0, 0), worlds, spawns, true)
	local Wall = C.require(C.Client.Controllers.WallController)
	local Hud = C.require(C.Client.Controllers.CorridorHudController)
	Wall.Init()
	Wall.Start()
	Hud.Init()
	Hud.Start()
	local rows = {}
	for _, d in worldModel:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("Wall") == true then
			rows[d:GetAttribute("StageId")] = rows[d:GetAttribute("StageId")] or {}
			rows[d:GetAttribute("StageId")][d:GetAttribute("Row")] = d
		end
	end
	local self = {
		Wall = Wall,
		Rows = rows,
		State = state,
		Settings = settings,
		Toasts = toasts,
		Camera = camera,
		Player = localPlayer,
		Character = character,
		Handlers = handlers,
		TopStack = topStack,
		PlayerGui = playerGui,
	}
	function self.Tick(n)
		for _ = 1, n or 1 do
			for _, fn in beats do
				fn(1 / 60)
			end
		end
	end
	-- Na frente da fileira de pé do estágio (lado do jogador, dentro do alcance).
	function self.Face(stageId, index)
		local row = rows[stageId][index or 1]
		local face = row.CFrame.Position.X - row.Size.X / 2
		hrp.CFrame = CF.new(face - 6, row.CFrame.Position.Y - row.Size.Y / 2 + 3, 0)
	end
	function self.SetHp(stageId, list)
		handlers.WallState({ [stageId] = { Hp = list, Open = false } })
	end
	function self.Line()
		local sign = Wall.Signs().Colossus
		return if sign and sign.Readiness then sign.Readiness.Text else ""
	end
	function self.Corridor()
		local panel = topStack:FindFirstChild("CorridorHud")
		local reward = panel and panel:FindFirstChild("Reward")
		local status = panel and panel:FindFirstChild("Status")
		return (if status then status.Text else "") .. " · " .. (if reward then reward.Text else ""), panel and panel.Visible
	end
	return self
end

local A = makeClient("JogadorA")
local B = makeClient("JogadorB")
local full = table.create(colossus.Rows, rowHp)
A.SetHp("Colossus", table.clone(full))
B.SetHp("Colossus", table.clone(full))
A.Face("Colossus")
B.Face("Colossus")

-- Entra muito fraco: ≈10,5K golpes por fileira.
A.State.Damage = rowHp / 10_500
A.Tick(2)
local signA = A.Wall.Signs().Colossus
print("      A placa:  " .. A.Line())
print("      A faixa:  " .. (A.Corridor()))
check(signA and signA.Gui.Enabled and signA.Readiness and signA.Readiness.Visible, "W1. placa do Colosso ligada com a linha do estado")
check(signA.Name.Text == "10 · Colosso" and string.find(signA.BarText.Text, NumberFormat.Short(rowHp), 1, true) ~= nil and #signA.Pips == 10, "W2. placa mantém \"10 · Colosso\", ❤ HP atual/total e as 10 fileiras")
check(A.Line() == "🔴 DESAFIO EXTREMO ≈" .. NumberFormat.Short(10_500) .. " golpes/fileira", "W3. muito fraco: \"🔴 DESAFIO EXTREMO ≈" .. NumberFormat.Short(10_500) .. " golpes/fileira\" (o número nunca some)")
local corridorText, corridorVisible = A.Corridor()
check(corridorVisible and string.find(corridorText, "≈" .. NumberFormat.Short(10_500) .. " golpes · 🔴 DESAFIO EXTREMO", 1, true) ~= nil and not string.find(corridorText, "Forte demais", 1, true), "W4. faixa no Colosso: \"⚔ X · ≈N golpes · 🔴 DESAFIO EXTREMO\" (o mesmo N da placa), sem o aviso \"forte demais\"")
check(#A.Toasts == 0, "W5. entrar no Colosso não gera aviso (estado inicial é a base)")

-- Sobe o dano até PREPARANDO e PRONTO.
A.State.Damage = rowHp / 271
A.Tick(2)
check(string.find(A.Line(), "🟠 PREPARANDO ≈271 golpes/fileira", 1, true) ~= nil and A.Toasts[1] == "⚔ COLOSSO  Sua força agora está em PREPARAÇÃO." and #A.Toasts == 1, "W6. ≈271: \"🟠 PREPARANDO\" + aviso \"⚔ COLOSSO Sua força agora está em PREPARAÇÃO.\" uma vez")
A.State.Damage = rowHp / 82
A.Tick(2)
corridorText = A.Corridor()
print("      A placa:  " .. A.Line())
print("      A faixa:  " .. corridorText)
check(string.find(A.Line(), "🟢 PRONTO ≈82 golpes/fileira", 1, true) ~= nil and #A.Toasts == 2 and string.find(A.Toasts[2], "VOCÊ ESTÁ PRONTO", 1, true) ~= nil and string.find(A.Toasts[2], "luta viável", 1, true) ~= nil, "W7. ≈82: \"🟢 PRONTO\" + aviso \"VOCÊ ESTÁ PRONTO! … uma luta viável\" (nunca \"vai vencer\")")
check(string.find(corridorText, "≈82 golpes · 🟢 PRONTO", 1, true) ~= nil, "W8. faixa: \"≈82 golpes · 🟢 PRONTO\"")
local noWin = true
for _, text in A.Toasts do
	if string.find(text, "vencer", 1, true) then
		noWin = false
	end
end
check(noWin, "W9. nenhum texto promete vitória")
for _ = 1, 30 do
	A.Tick(1)
end
check(#A.Toasts == 2, "W10. golpe a golpe (30 quadros): nenhum aviso novo")

-- Combo/dano oscilando no limite não repete.
for i = 1, 10 do
	A.State.Damage = rowHp / (if i % 2 == 0 then 82 else 120)
	A.Tick(1)
end
check(#A.Toasts == 2, "W11. dano oscilando entre PRONTO e PREPARANDO (combo): sem repetir aviso")

-- HP da fileira muda: o ≈N mostrado cai, o estado não muda.
A.State.Damage = rowHp / 271
local half = table.clone(full)
half[1] = rowHp / 2
A.SetHp("Colossus", half)
A.Tick(1)
local readout = A.Wall.ColossusReadout()
check(readout and readout.Level == "Preparing" and readout.Hits == 136 and readout.StateHits == 271 and string.find(A.Line(), "≈136", 1, true) ~= nil, "W12. fileira pela metade: ≈136 golpes nela; estado continua PREPARANDO (classifica pela fileira cheia)")
check(string.find(signA.BarText.Text, NumberFormat.Short(rowHp / 2), 1, true) ~= nil, "W13. ❤ HP atual da fileira continua na placa")
-- Fileira avança.
local broken = table.clone(full)
broken[1] = 0
A.SetHp("Colossus", broken)
A.Face("Colossus", 2)
A.Tick(2)
readout = A.Wall.ColossusReadout()
check(readout and readout.Row == 2 and readout.Hits == 271 and readout.Level == "Preparing", "W14. quebrou a fileira 1: a leitura passa para a fileira 2 (≈271, PREPARANDO)")

-- Dois jogadores, mesmo Colosso, estados diferentes.
B.State.Damage = rowHp / 10_500
A.State.Damage = rowHp / 82
A.Tick(2)
B.Tick(2)
print("      B placa:  " .. B.Line())
check(string.find(A.Line(), "PRONTO", 1, true) ~= nil and string.find(B.Line(), "DESAFIO EXTREMO", 1, true) ~= nil, "W15. jogador A PRONTO e jogador B EXTREMO no MESMO Colosso (estado por jogador)")
local attrs = false
for _, row in A.Rows.Colossus do
	for key in row:GetAttributes() do
		if string.find(string.lower(key), "ready") or string.find(string.lower(key), "state") then
			attrs = true
		end
	end
end
check(not attrs and #B.Toasts == 0, "W16. nenhum estado no mapa (atributos das fileiras intactos); B não recebeu o aviso de A")

-- Respawn: sem personagem, depois volta.
local character = A.Player.Character
A.Player.Character = nil
local ok = pcall(A.Tick, 3)
A.Player.Character = character
A.Tick(2)
check(ok and string.find(A.Line(), "PRONTO", 1, true) ~= nil and #A.Toasts == 2, "W17. respawn: sem erro, o estado volta igual e não repete aviso")

-- Efeitos reduzidos: a linha não depende de efeito.
A.Settings.ReducedEffects = true
A.Tick(2)
check(signA.Readiness.Visible and string.find(A.Line(), "PRONTO", 1, true) ~= nil, "W18. Efeitos reduzidos: estado e número continuam na placa")
A.Settings.ReducedEffects = false

-- Celular: textos curtos (toque ou tela estreita).
B.State.Touch = true
B.Tick(2)
local shortB = B.Line()
B.State.Touch = false
B.Camera.ViewportSize = roblox.Vector2.new(844, 390)
B.Tick(2)
local narrowB = B.Line()
local corridorB = B.Corridor()
print("      B celular placa: " .. shortB .. "   faixa: " .. corridorB)
check(shortB == "🔴 EXTREMO ≈" .. NumberFormat.Short(10_500) .. "/fileira" and narrowB == shortB and string.find(corridorB, "🔴 EXTREMO", 1, true) ~= nil, "W19. celular/tablet: \"🔴 EXTREMO ≈10,5K/fileira\" (forma curta) na placa e na faixa")
B.Camera.ViewportSize = roblox.Vector2.new(1920, 1080)

-- Estágios 1–9 sem mudança: aviso "forte demais" e sem linha de estado.
A.State.Damage = 1
A.SetHp("Tech", table.create(WallConfigE.Stages[9].Rows, WallConfigE.Stages[9].Hp))
A.Face("Tech")
A.Tick(2)
local techText = A.Corridor()
local otherLines = 0
for id, sign in A.Wall.Signs() do
	if id ~= "Colossus" and sign.Readiness then
		otherLines += 1
	end
end
check(string.find(techText, "Forte demais", 1, true) ~= nil and otherLines == 0, "W20. estágios 1–9 iguais: faixa com o aviso de sempre, placas sem linha nova")

-- A placa do Colosso (mais alta) continua fora da HUD, como as outras.
local sign = A.Wall.Signs().Colossus
local size = sign.Gui.Size
local sizeOffset = sign.Gui.SizeOffset
local rowC = A.Rows.Colossus[1]
local faceC = rowC.CFrame.Position.X - rowC.Size.X / 2
local playerAt = V3.new(faceC - 8, 0, 6)
local anchor = A.Wall.PlateAnchor(rowC, playerAt + V3.new(0, 3, 0))
local SCREENS = { { "1920x1080", 1920, 1080 }, { "1366x768", 1366, 768 }, { "tablet 1024x768", 1024, 768 }, { "celular 844x390", 844, 390 } }
local CAMERAS = { { "próxima", 8, 10 }, { "padrão", 12.5, 14 }, { "distante", 28, 24 } }
local camOk = true
local tallest = 0
for _, cam in CAMERAS do
	local focus = playerAt + V3.new(0, 4.5, 0)
	local pitch = math.rad(cam[3])
	local back = V3.new(-math.cos(pitch), math.sin(pitch), 0.12).Unit
	local eye = focus + back * cam[2]
	local target = focus + V3.new(20, -20 * math.tan(pitch), 0)
	local look = (target - eye).Unit
	local right = look:Cross(V3.new(0, 1, 0)).Unit
	local up = right:Cross(look)
	for _, screen in SCREENS do
		local w, h = screen[2], screen[3]
		local k = (h / 2) / math.tan(math.rad(35))
		local d = anchor - eye
		local z = d:Dot(look)
		local px, py = w / 2 + k * d:Dot(right) / z, h / 2 - k * d:Dot(up) / z
		local bw = k * size.X.Scale / z + size.X.Offset
		local bh = k * size.Y.Scale / z + size.Y.Offset
		-- SizeOffset Y negativo desce a placa (fração da altura).
		py -= sizeOffset.Y * bh
		local hd = (playerAt + V3.new(0, 5.6, 0)) - eye
		local headY = h / 2 - k * hd:Dot(up) / hd:Dot(look)
		local scale = math.clamp(math.min(w / 1280, h / 720), 0.5, 1.6)
		local hudBottom = (124 + 6) * scale
		local box = { px - bw / 2, py - bh / 2, px + bw / 2, py + bh / 2 }
		local inside = box[1] >= 0 and box[3] <= w and box[2] >= 0 and box[4] <= h
		local aboveHead = box[4] <= headY + 2
		local clickZone = { w - math.min(260, w * 0.32), h - math.min(260, h * 0.45) }
		local hitsClick = box[3] > clickZone[1] and box[4] > clickZone[2]
		local hitsTop = box[2] < hudBottom
		tallest = math.max(tallest, bh / h)
		if not (inside and aboveHead and not hitsClick and not hitsTop) then
			camOk = false
			print(string.format("      %s %s: caixa (%.0f,%.0f)-(%.0f,%.0f) cabeça %.0f topo HUD %.0f", cam[1], screen[1], box[1], box[2], box[3], box[4], headY, hudBottom))
		end
	end
end
check(camOk, string.format("W21. placa do Colosso (%.2f studs + %d px, só +0,2 stud para a linha) inteira na tela, abaixo da HUD e acima da cabeça: 3 câmeras × 1920x1080, 1366x768, tablet, celular", size.Y.Scale, size.Y.Offset))
local normal = A.Wall.Signs().Wood.Gui.Size
check(size.X == normal.X and size.Y.Scale <= normal.Y.Scale * 1.1 and size.Y.Offset - normal.Y.Offset <= 2, string.format("W22. placa do Colosso no máximo ~7%% mais alta que as outras (%.2f vs %.2f studs; mesma largura); maior altura na tela: %.0f%%", size.Y.Scale, normal.Y.Scale, tallest * 100))

print("")
if #problems > 0 then
	print(string.format("FALHOU: %d problema(s) na UX de progressão", #problems))
	process.exit(1)
end
print("OK: UX de progressão — renascer disponível (custo do servidor, selo, aviso sem spam, altar discreto) e estado do Colosso por jogador (placa + faixa, sem mudar economia).")
print("REQUER VALIDAÇÃO NO ROBLOX STUDIO: leitura da placa/etiqueta, emoji 🔴🟠🟢 na fonte, placa no celular real, ritmo dos avisos.")
process.exit(0)
