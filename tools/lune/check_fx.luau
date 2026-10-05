--[[
	check_fx.luau — os efeitos de combate nas barreiras, com os controllers
	REAIS do cliente (WallController, SwordSwingController, SlashController,
	CombatFxController) sobre o mapa gerado, um personagem R15 e um "servidor"
	mínimo que manda o WallState deste jogador a cada hit (a regra de verdade do
	servidor é testada no check_corridor). Relógio simulado.

		lune run tools/lune/check_fx.luau [raiz]

	Verifica:
	  1. 4 camadas no mesmo instante: golpe, corte (CutFx), impacto
	     (BarrierFx.Impact) e reação da barreira;
	  2. impacto no ponto de contato da face, com a intensidade do Corte;
	  3. identidade por barreira (todos os estágios com tema; temas distintos);
	  4. evolução dos Cortes (1, 2, 4, 8): intensidade, espessura, onda;
	  5. rachaduras progressivas pelo HP (0–4) e limpas quando a fileira volta;
	  6. hit forte (só visual) e câmera por nível; quebra com hit stop visual;
	     a última fileira e o Colosso com a quebra maior;
	  7. números de dano reais, agrupados (no máximo 4 na tela) e a soma certa;
	  8. "Efeitos reduzidos": golpe + flash ficam; partículas, onda, câmera saem;
	  9. spam 9 hits/s por 30 s em Madeira, Gelo, Cristal, Vulcânica, Magma e
	     Colosso com os Cortes 1/2/4/8, efeitos ligados e reduzidos: nenhuma
	     instância acumulando;
	 10. golpe de OUTRO jogador não gera impacto nem dano na minha barreira;
	 11. respawn e troca de espada no meio do spam.

	REQUER VALIDAÇÃO NO ROBLOX STUDIO: beleza, partículas, cores por tema,
	tremor de câmera (enjoo), números na tela, FPS real com 2+ jogadores.
]]
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local luneTask = require("@lune/task")
local E = require("./env")(process.args[1])
local V3 = roblox.Vector3
local CF = roblox.CFrame
local Instance = roblox.Instance

local problems = {}
local function check(condition: any, message: string)
	if condition then
		print("OK   " .. message)
	else
		table.insert(problems, message)
		print("FALHA " .. message)
	end
end

-- ── Eventos e métodos que o Lune não tem ────────────────────────────────────
local Sig = { Connect = function()
	return { Disconnect = function() end }
end, Once = function()
	return { Disconnect = function() end }
end, Wait = function() end }
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
local emitted = 0
roblox.implementMethod("ParticleEmitter", "Emit", function(_, count)
	emitted += count
end)

-- ── Relógio, tweens e task.delay simulados ──────────────────────────────────
local now = 1000
E.extraGlobals.os = setmetatable({ clock = function()
	return now
end }, { __index = os })
E.extraGlobals.TweenInfo = { new = function(...)
	return { ... }
end }
E.stubs.TweenService = { Create = function(_, instance, _, goal)
	return { Play = function()
		for key, value in goal do
			instance[key] = value
		end
	end, Cancel = function() end, Completed = Sig }
end }
local delayed = {}
E.extraGlobals.task = setmetatable({ delay = function(seconds, fn, ...)
	table.insert(delayed, { At = now + seconds, Fn = fn, Args = { ... } })
end }, { __index = luneTask })
local function runDelayed()
	local pending = delayed
	delayed = {}
	for _, item in pending do
		if item.At <= now + 1e-9 then
			item.Fn(table.unpack(item.Args))
		else
			table.insert(delayed, item)
		end
	end
end

-- ── Stubs do cliente ────────────────────────────────────────────────────────
local Signal = E.require(E.Shared.Utils.Signal)
local settings = { ReducedEffects = false, ShowFloatingNumbers = true }
local perClick = 7
local client = "StarterPlayer.Client."
local handlers = {}
E.stubModules[client .. "Net.ClientNet"] = { On = function(name, fn)
	handlers[name] = fn
	return { Disconnect = function() end }
end, Fire = function() end, Invoke = function()
	return { Ok = false }
end }
E.stubModules[client .. "Controllers.SoundController"] = { Play = function() end }
E.stubModules[client .. "Controllers.NotificationController"] = { Show = function() end }
E.stubModules[client .. "Controllers.HudController"] = { GetTopStack = function()
	return Instance.new("Frame")
end }
E.stubModules[client .. "Controllers.DataController"] = { Get = function(key)
	return if key == "Settings" then settings else nil
end, IsLoaded = function()
	return true
end }
E.stubModules[client .. "Controllers.GameStateController"] = { GetPowerInfo = function()
	return { PerClick = perClick }
end }
-- O Lune não expõe BasePart.Position (só CFrame): troca só nestes módulos.
for _, name in { "WallController", "CombatFxController" } do
	E.patches[client .. "Controllers." .. name] = {
		{ "row.Position", "row.CFrame.Position", "all" },
		{ "root.Position", "root.CFrame.Position", "all" },
	}
end
E.patches[client .. "Controllers.SwordSwingController"] = { { ".Position", ".CFrame.Position", "all" } }
local renderStep, heartbeat, preSim, postSim
E.stubs.RunService.RenderStepped = { Connect = function(_, fn)
	renderStep = fn
	return { Disconnect = function() end }
end }
-- O corpo com espada roda depois do Animator (PreSimulation) e verifica depois
-- da física (PostSimulation).
E.stubs.RunService.PreSimulation = { Connect = function(_, fn)
	preSim = fn
	return { Disconnect = function() end }
end }
E.stubs.RunService.PostSimulation = { Connect = function(_, fn)
	postSim = fn
	return { Disconnect = function() end }
end }
E.stubs.RunService.Heartbeat = { Connect = function(_, fn)
	heartbeat = fn
	return { Disconnect = function() end }
end }
local cameraStep
E.stubs.RunService.BindToRenderStep = function(_, _, _, fn)
	cameraStep = fn
end

-- Personagem R15 com a espada (Tool + Blade + RightGrip).
local function part(parent, name, size)
	local p = Instance.new("Part")
	p.Name = name
	if size then
		p.Size = size
	end
	p.Parent = parent
	return p
end
local function motor(parent, name, part0, part1, c0)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = c0
	m.Transform = CF.identity
	m.Parent = parent
end
local function giveSword(model)
	local tool = Instance.new("Tool")
	tool.Name = "CutBlade"
	part(tool, "Handle")
	local blade = part(tool, "Blade", V3.new(0.2, 4.2, 0.8))
	-- Como o SwordService monta: luz contida parada, fio de energia apagado.
	local glow = Instance.new("PointLight")
	glow.Brightness = 0.35
	glow:SetAttribute("IdleBrightness", 0.35)
	glow:SetAttribute("SwingBrightness", 1.6)
	glow.Parent = blade
	local edge = part(tool, "BladeEdge", V3.new(0.2, 4, 0.14))
	edge.Transparency = 0.4
	edge:SetAttribute("IdleTransparency", 0.4)
	tool.Parent = model
	return tool
end
local function newCharacter(position)
	local model = Instance.new("Model")
	model.Name = "Local"
	local root = part(model, "HumanoidRootPart")
	root.CFrame = CF.new(position)
	local lower, upper = part(model, "LowerTorso"), part(model, "UpperTorso")
	local upperArm, lowerArm, hand = part(model, "RightUpperArm"), part(model, "RightLowerArm"), part(model, "RightHand")
	motor(upper, "Waist", lower, upper, CF.new(0, 0.2, 0))
	motor(upperArm, "RightShoulder", upper, upperArm, CF.new(1, 0.56, 0))
	motor(lowerArm, "RightElbow", upperArm, lowerArm, CF.new(0, -0.33, 0))
	motor(hand, "RightWrist", lowerArm, hand, CF.new(0, -0.5, 0))
	giveSword(model)
	model.Parent = E.Workspace
	return model
end

local playerGui = Instance.new("Folder")
playerGui.Name = "PlayerGui"
local attributes = { BestCut = "Cut1", EquippedSword = nil }
local characterAdded, characterRemoving = Signal.new(), Signal.new()
local localPlayer = {
	Name = "Local",
	UserId = 1,
	LocaleId = "pt-br",
	Character = nil,
	CharacterAdded = characterAdded,
	CharacterRemoving = characterRemoving,
	WaitForChild = function(_, n)
		return if n == "PlayerGui" then playerGui else nil
	end,
	FindFirstChild = function(_, n)
		return if n == "PlayerGui" then playerGui else nil
	end,
	GetAttribute = function(_, key)
		return attributes[key]
	end,
	GetAttributeChangedSignal = function()
		return Sig
	end,
}
local otherSwing = Signal.new()
local other = { Name = "Other", UserId = 2, Character = nil, CharacterRemoving = Signal.new(), GetAttribute = function()
	return nil
end, GetAttributeChangedSignal = function(_, name)
	return if name == "SwingSeq" then otherSwing else Sig
end }
E.stubs.Players = { LocalPlayer = localPlayer, GetPlayers = function()
	return { localPlayer, other }
end, PlayerAdded = Signal.new(), PlayerRemoving = Signal.new() }

-- ── Mapa ────────────────────────────────────────────────────────────────────
local WallConfig = E.require(E.Shared.Config.WallConfig)
local CutVisuals = E.require(E.Shared.Formulas.CutVisuals)
do
	local map = Instance.new("Folder")
	map.Name = "Map"
	local worlds = Instance.new("Folder")
	worlds.Name = "Worlds"
	worlds.Parent = map
	local spawns = Instance.new("Folder")
	spawns.Name = "Spawns"
	spawns.Parent = map
	map.Parent = E.Workspace
	local WorldBuilder = E.require(E.Server.World.WorldBuilder)
	local WorldConfig = E.require(E.Shared.Config.WorldConfig)
	WorldBuilder.Build(WorldConfig.Worlds[WallConfig.WorldId], V3.new(0, 0, 0), worlds, spawns, true)
end
local rows = {}
for _, d in E.Workspace:GetDescendants() do
	if d:IsA("BasePart") and d:GetAttribute("Wall") == true then
		local id = d:GetAttribute("StageId")
		rows[id] = rows[id] or {}
		rows[id][d:GetAttribute("Row")] = d
	end
end
local stageById = {}
for _, stage in WallConfig.Stages do
	stageById[stage.Id] = stage
end

-- ── Controllers reais ───────────────────────────────────────────────────────
local BarrierFx = E.require(E.Client.Effects.BarrierFx)
local BarrierThemes = E.require(E.Client.Effects.BarrierThemes)
local CameraFx = E.require(E.Client.Effects.CameraFx)
local CutFx = E.require(E.Client.Effects.CutFx)
local DamageNumbers = E.require(E.Client.Effects.DamageNumbers)

local impacts, cutPlays = {}, {}
local originalImpact = BarrierFx.Impact
BarrierFx.Impact = function(fx, theme, point, options)
	table.insert(impacts, { At = now, Theme = theme, Point = point, Options = options })
	return originalImpact(fx, theme, point, options)
end
local breaks = {}
local originalBreak = BarrierFx.Break
BarrierFx.Break = function(fx, theme, row, options)
	table.insert(breaks, { At = now, Theme = theme, Row = row, Options = options })
	return originalBreak(fx, theme, row, options)
end
local originalCut = CutFx.Play
CutFx.Play = function(rig, recipe, origin, scale, roll)
	table.insert(cutPlays, { At = now, Recipe = recipe, Scale = scale })
	return originalCut(rig, recipe, origin, scale, roll)
end
local shakes = {}
local originalShake = CameraFx.Shake
CameraFx.Shake = function(level)
	table.insert(shakes, level)
	return originalShake(level)
end

local Wall = E.require(E.Client.Controllers.WallController)
local Swing = E.require(E.Client.Controllers.SwordSwingController)
local Slash = E.require(E.Client.Controllers.SlashController)
local Combat = E.require(E.Client.Controllers.CombatFxController)

local function frontOf(row, back)
	return V3.new(row.CFrame.Position.X - row.Size.X / 2 - (back or 4), 3, 0)
end
localPlayer.Character = newCharacter(frontOf(rows.Wood[1]))
Wall.Init()
Swing.Init()
Slash.Init()
Combat.Init()
Wall.Start()
Swing.Start()
Combat.Start()
check(heartbeat and preSim and postSim and cameraStep, "laços por quadro registrados uma vez (paredes, golpe, câmera)")

-- Um quadro do corpo: "Animator" reescreve o Transform, a pose entra depois.
local function bodyStep()
	for _, d in E.Workspace:GetDescendants() do
		if d:IsA("Motor6D") then
			d.Transform = CF.identity
		end
	end
	preSim()
	postSim()
end

-- ── "Servidor" mínimo deste jogador ─────────────────────────────────────────
local hp = {}
local function stateOf(stageId)
	if not hp[stageId] then
		hp[stageId] = table.create(stageById[stageId].Rows, stageById[stageId].Hp)
	end
	return hp[stageId]
end
local function send(stageId)
	handlers.WallState({ [stageId] = { Hp = table.clone(stateOf(stageId)), Open = false } })
end
local function serverHit(damage)
	local root = localPlayer.Character.HumanoidRootPart.CFrame.Position
	local best, bestStage, bestIndex, bestDistance = nil, nil, nil, WallConfig.HitRange
	for stageId, list in rows do
		local state = stateOf(stageId)
		for index, row in list do
			local x = row.CFrame.Position.X
			local distance = (row.CFrame.Position - root).Magnitude
			if state[index] > 0 and root.X < x and distance <= bestDistance then
				best, bestStage, bestIndex, bestDistance = row, stageId, index, distance
			end
		end
	end
	if best then
		local state = stateOf(bestStage)
		state[bestIndex] = math.max(state[bestIndex] - damage, 0)
		send(bestStage)
	end
	return best
end
local function restoreStage(stageId)
	hp[stageId] = nil
	send(stageId)
end
local function frames(seconds)
	local steps = math.max(math.floor(seconds * 60 + 0.5), 1)
	for _ = 1, steps do
		now += 1 / 60
		bodyStep()
		cameraStep()
		heartbeat()
		runDelayed()
	end
end
-- Um hit: clique (golpe) + o servidor aplica o dano + quadros até depois do impacto.
local function hit(damage)
	Slash.Play()
	serverHit(damage)
	frames(0.12)
end
local function goTo(stageId)
	local list = rows[stageId]
	local front = list[1]
	for index = 1, #list do
		if stateOf(stageId)[index] > 0 then
			front = list[index]
			break
		end
	end
	localPlayer.Character.HumanoidRootPart.CFrame = CF.new(frontOf(front, 2))
end

-- 1/2. As 4 camadas juntas, no ponto de contato.
goTo("Wood")
local clickAt = now
Slash.Play()
local rig = Swing.LocalRig()
check(rig and rig.Active, "1. ESPADA: o hit dispara o golpe do personagem")
serverHit(perClick)
frames(0.12)
check(#cutPlays >= 1 and #impacts == 1, "1. CORTE e IMPACTO aparecem para o hit")
check(math.abs(cutPlays[#cutPlays].At - impacts[1].At) < 1e-9, "1. corte e impacto no MESMO instante")
local impactDelay = rig.Duration * 0.4
check(math.abs((impacts[1].At - clickAt) - impactDelay) <= 1 / 60 + 1e-6, string.format("1. no impacto do golpe (%.3f s depois do clique)", impacts[1].At - clickAt))
local woodRow = rows.Wood[1]
local face = woodRow.CFrame.Position.X - woodRow.Size.X / 2
check(math.abs(impacts[1].Point.X - (face - 0.3)) < 0.01, "2. o impacto nasce na face da fileira (ponto de contato), não espalhado")
check(impacts[1].Options.Intensity == CutVisuals.For("Cut1").Impact and impacts[1].Theme.StageId == "Wood", "2. intensidade do Corte atual e tema da barreira atingida")
check(woodRow.Color ~= nil, "1. BARREIRA: a superfície reage (flash) — e o dano real chegou pelo WallState")

-- Combo visual (A→B→C): o efeito nasce um pouco para o lado do fim da lâmina
-- (A esquerda, B direita, C centro), o C é o fecho marcado; a intensidade do
-- Corte (e o dano) não mudam.
do
	local hrp = localPlayer.Character.HumanoidRootPart
	local at = hrp.CFrame.Position
	hrp.CFrame = CF.lookAt(at, at + V3.new(1, 0, 0)) -- de frente para a barreira (+X)
	frames(1.5)
	local first = #impacts + 1
	for _ = 1, 3 do
		Slash.Play()
		frames(0.3)
	end
	local ia, ib, ic = impacts[first], impacts[first + 1], impacts[first + 2]
	check(ia and ib and ic and ia.Point.Z < ic.Point.Z and ib.Point.Z > ic.Point.Z and math.abs(ia.Point.X - ic.Point.X) < 1e-6 and math.abs(ib.Point.X - ic.Point.X) < 1e-6, "COMBO. impacto A à esquerda, B à direita, C no centro — sempre na face da mesma fileira")
	check(ia and ib and ic and not ia.Options.Finisher and not ib.Options.Finisher and ic.Options.Finisher == true, "COMBO. só o 3º golpe (C) é o fecho marcado")
	check(ia and ic and ia.Options.Intensity == ic.Options.Intensity and ia.Options.Strong == ic.Options.Strong, "COMBO. o C não é crítico: mesma intensidade do Corte e mesmo \"hit forte\" (dano igual)")
	hrp.CFrame = CF.new(at)
end

-- 3. Temas.
check(#BarrierThemes.Missing() == 0, "3. todos os estágios do WallConfig têm tema de efeito")
local signature = {}
local distinct = true
for _, stage in WallConfig.Stages do
	local theme = BarrierThemes.For(stage.Id)
	local key = string.format("%s|%s|%s|%s", tostring(theme.Chip), tostring(theme.ChipMaterial), theme.Particle, tostring(theme.Energy))
	if signature[key] then
		distinct = false
	end
	signature[key] = true
end
check(distinct, "3. cada barreira tem identidade própria (fragmento, material, partícula, energia)")
check(BarrierThemes.For("Colossus").Epic > BarrierThemes.For("Tech").Epic and BarrierThemes.For("Wood").Epic == 1, "3. o Colosso tem a quebra mais grandiosa")

-- 4. Evolução dos Cortes.
local r1, r2, r4, r7, r8 = CutVisuals.For("Cut1"), CutVisuals.For("Cut2"), CutVisuals.For("Cut4"), CutVisuals.For("Cut7"), CutVisuals.For("Cut8")
check(r1.Impact < r2.Impact and r2.Impact < r4.Impact and r4.Impact < r8.Impact, "4. impacto cresce com o Corte (1 < 2 < 4 < 8)")
check(r1.Shock == 0 and r4.Shock == 1 and r7.Shock == 2 and r8.Shock == 3, "4. onda: nenhuma no 1, anel no 4 (X), onda no 7, SUPREMA no 8")
check(r8.Thickness > r4.Thickness and r8.SparkSize > r2.SparkSize and r8.Slashes == 3, "4. Corte 8: riscos mais grossos, faíscas maiores, 3 cortes")

-- 5. Rachaduras.
local tiers = { BarrierFx.CrackTier(1), BarrierFx.CrackTier(0.8), BarrierFx.CrackTier(0.6), BarrierFx.CrackTier(0.4), BarrierFx.CrackTier(0.2), BarrierFx.CrackTier(0.05), BarrierFx.CrackTier(0) }
check(table.concat(tiers, ",") == "0,0,1,2,3,4,0", "5. tiers de rachadura pelo HP: 100–75 intacta, 75–50, 50–25, 25–10, <10 (" .. table.concat(tiers, ",") .. ")")
local fx = Combat.State()
restoreStage("Wood")
frames(0.05)
goTo("Wood")
local woodHp = stageById.Wood.Hp
-- No Lune cada leitura de peça é um objeto Lua novo: procura pelo nome.
local function cracksOf(row)
	for key, set in fx.Cracks do
		if key.Name == row.Name then
			return #set.Parts, set
		end
	end
	return 0, nil
end
hit(math.ceil(woodHp * 0.3)) -- 70%
check(cracksOf(woodRow) == 2, "5. abaixo de 75%: primeiras rachaduras (" .. cracksOf(woodRow) .. ")")
hit(math.ceil(woodHp * 0.25)) -- 45%
check(cracksOf(woodRow) == 4, "5. abaixo de 50%: rachaduras maiores")
hit(math.ceil(woodHp * 0.25)) -- 20%
check(cracksOf(woodRow) == 6, "5. abaixo de 25%: rachaduras fortes (com energia)")
hit(math.ceil(woodHp * 0.12)) -- ~8%
local count, set = cracksOf(woodRow)
check(count == 7 and set.Light ~= nil and set.Falling ~= nil, "5. abaixo de 10%: instável — brilho pulsando e fragmentos caindo")
restoreStage("Wood")
frames(0.05)
check(cracksOf(woodRow) == 0, "5. a fileira volta inteira: rachaduras somem")

-- 6. Hit forte, câmera, quebra, hit stop.
table.clear(shakes)
goTo("Wood")
perClick = math.ceil(woodHp * 0.3)
hit(perClick)
check(impacts[#impacts].Options.Strong == true and shakes[#shakes] == "Strong", "6. hit que tira >=25% da fileira: impacto e câmera de hit FORTE (só visual)")
perClick = 1
hit(1)
check(impacts[#impacts].Options.Strong == false and shakes[#shakes] == "Hit", "6. hit comum: tremor quase imperceptível")
local levels = CameraFx.Levels()
check(levels.Hit[1] <= 0.15 and levels.Epic[1] <= 2.5 and levels.Epic[2] <= 0.4, "6. câmera controlada (hit ≤ 0,15°, maior tremor ≤ 2,5° por ≤ 0,4 s)")
restoreStage("Wood")
frames(0.05)
table.clear(breaks)
table.clear(shakes)
local function has(list, from, value)
	for index = from, #list do
		if list[index] == value then
			return true
		end
	end
	return false
end
local bigCut = false
for index = 1, stageById.Wood.Rows do
	goTo("Wood")
	Slash.Play()
	local before = Swing.LocalRig().Started
	local shakeMark, cutMark = #shakes + 1, #cutPlays + 1
	serverHit(woodHp)
	check(Swing.LocalRig().Started > before or not Swing.LocalRig().Active, "6. quebra: hit stop VISUAL (o golpe segura a pose ~0,05 s)")
	for c = cutMark, #cutPlays do
		bigCut = bigCut or cutPlays[c].Scale > 1
	end
	frames(0.15)
	if index < stageById.Wood.Rows then
		check(breaks[#breaks] and breaks[#breaks].Options.Final == false and has(shakes, shakeMark, "Break"), "6. fileira " .. index .. " cai: quebra com tremor curto")
	else
		check(breaks[#breaks].Options.Final == true and has(shakes, shakeMark, "Final"), "6. a última fileira abre a barreira: quebra FINAL")
	end
end
check(#breaks == stageById.Wood.Rows, "6. uma quebra por fileira")
check(bigCut, "5. o Corte atravessa a parede na quebra (corte grande no centro)")
hp.Colossus = table.create(stageById.Colossus.Rows, 1)
send("Colossus")
table.clear(shakes)
for index = 1, stageById.Colossus.Rows do
	goTo("Colossus")
	Slash.Play()
	serverHit(1)
	frames(0.15)
end
check(breaks[#breaks].Theme.StageId == "Colossus" and breaks[#breaks].Options.Final and has(shakes, 1, "Epic"), "6. Colosso: a quebra mais épica (câmera especial)")

-- 7. Números de dano.
local _, numbers = Combat.State()
restoreStage("Ice")
goTo("Ice")
perClick = 3
local shownTotal = 0
for _ = 1, 9 do
	Slash.Play()
	serverHit(3)
	frames(1 / 9)
	shownTotal = math.max(shownTotal, DamageNumbers.Visible(numbers))
end
check(shownTotal <= 4, "7. spam de 9 hits/s: no máximo 4 números na tela (" .. shownTotal .. ")")
local sum = 0
for _, slot in numbers.Slots do
	if slot.Gui.Enabled then
		sum += slot.Total
	end
end
check(sum > 0 and sum % 3 == 0, "7. os números somam o dano real (hits próximos se juntam no mesmo número)")
settings.ShowFloatingNumbers = false
frames(1)
Slash.Play()
serverHit(3)
frames(0.1)
check(DamageNumbers.Visible(numbers) == 0, "7. com \"Mostrar números\" desligado, nenhum número")
settings.ShowFloatingNumbers = true

-- 8. Efeitos reduzidos.
settings.ReducedEffects = true
table.clear(shakes)
local emittedBefore = emitted
local impactsBefore = #impacts
goTo("Ice")
Slash.Play()
local swung = Swing.LocalRig().Active
serverHit(3)
frames(0.15)
check(swung and #impacts == impactsBefore + 1 and impacts[#impacts].Options.Reduced == true, "8. reduzidos: golpe + indicação básica do impacto continuam")
check(emitted == emittedBefore and #shakes == 0, "8. reduzidos: sem partículas e sem tremor de câmera")
settings.ReducedEffects = false

-- 10. Golpe de OUTRO jogador.
other.Character = newCharacter(frontOf(rows.Ice[1]))
other.Character.Name = "Other"
local impactsBefore2, numbersBefore = #impacts, DamageNumbers.Visible(numbers)
otherSwing:Fire()
frames(0.5)
check(#impacts == impactsBefore2 and DamageNumbers.Visible(numbers) <= numbersBefore, "10. o golpe de outro jogador anima o personagem dele, mas não gera impacto nem dano na MINHA barreira")

-- 12. Espada parada = contida; atacando = forte (luz, fio e rastro).
local function near(a, b)
	return math.abs(a - b) < 1e-4 -- propriedades float32
end
do
	frames(0.5)
	local tool = localPlayer.Character.CutBlade
	local glow = tool.Blade:FindFirstChildOfClass("PointLight")
	check(near(glow.Brightness, 0.35) and near(tool.BladeEdge.Transparency, 0.4), "12. espada parada: luz contida e fio de energia apagado")
	goTo("Wood")
	Slash.Play()
	frames(0.03)
	local trail = tool.Blade:FindFirstChildOfClass("Trail")
	check(near(glow.Brightness, 1.6) and near(tool.BladeEdge.Transparency, 0) and trail and trail.Enabled, "12. no golpe: luz forte, fio aceso e rastro ligado")
	frames(0.5)
	check(near(glow.Brightness, 0.35) and near(tool.BladeEdge.Transparency, 0.4) and not trail.Enabled, "12. depois do golpe: volta ao repouso contido")
	restoreStage("Wood")
end

-- 9/11. Spam de 30 s por barreira e Corte, efeitos ligados e reduzidos.
local function count(className)
	local n = 0
	for _, d in E.Workspace:GetDescendants() do
		if className == nil or d:IsA(className) then
			n += 1
		end
	end
	for _, d in playerGui:GetDescendants() do
		if className == nil or d:IsA(className) then
			n += 1
		end
	end
	return n
end
local stagesToTest = { "Wood", "Ice", "Crystal", "Volcanic", "Magma", "Colossus" }
local cutsToTest = { "Cut1", "Cut2", "Cut4", "Cut8" }
local function spam(stageId, cutId, seconds)
	attributes.BestCut = cutId
	local stage = stageById[stageId]
	local nextHit = now
	local t0 = now
	while now - t0 < seconds do
		if now >= nextHit then
			goTo(stageId)
			Slash.Play()
			-- Dano pequeno: a fileira apanha muito antes de cair, e cai às vezes.
			if not serverHit(math.max(math.floor(stage.Hp / 40), 1)) then
				restoreStage(stageId)
			end
			nextHit += 1 / 9
		end
		now += 1 / 60
		bodyStep()
		cameraStep()
		heartbeat()
		runDelayed()
	end
end
for _, reducedMode in { false, true } do
	settings.ReducedEffects = reducedMode
	for _, stageId in stagesToTest do
		restoreStage(stageId)
		spam(stageId, "Cut8", 2) -- aquece pools e emissores do tema
	end
	local baseline = count()
	local emitters = count("ParticleEmitter")
	local lights = count("PointLight")
	for _, stageId in stagesToTest do
		for _, cutId in cutsToTest do
			restoreStage(stageId)
			spam(stageId, cutId, if stageId == "Wood" and cutId == "Cut8" then 30 else 5)
		end
	end
	for _, stageId in stagesToTest do
		restoreStage(stageId)
	end
	frames(1)
	Combat.Prune(now + 2)
	local after = count()
	local label = if reducedMode then "reduzidos" else "ligados"
	check(after <= baseline, string.format("9. spam 9 hits/s (30 s na Madeira com Corte 8, e 6 barreiras x Cortes 1/2/4/8), efeitos %s: nenhuma instância acumulando (%d -> %d)", label, baseline, after))
	check(count("ParticleEmitter") <= emitters and count("PointLight") <= lights, string.format("9. efeitos %s: emissores e luzes não crescem (%d/%d emissores, %d/%d luzes)", label, count("ParticleEmitter"), emitters, count("PointLight"), lights))
end
settings.ReducedEffects = false

-- 11. Respawn e troca de espada no meio do spam.
spam("Wood", "Cut2", 1)
localPlayer.Character.CutBlade:Destroy()
giveSword(localPlayer.Character)
spam("Wood", "Cut2", 1)
local blade = localPlayer.Character.CutBlade.Blade
local trails = 0
for _, child in blade:GetChildren() do
	if child:IsA("Trail") then
		trails += 1
	end
end
check(trails == 1, "11. troca de espada: a lâmina nova ganha UM rastro do golpe (" .. trails .. ")")
characterRemoving:Fire(localPlayer.Character)
localPlayer.Character:Destroy()
localPlayer.Character = newCharacter(frontOf(rows.Wood[1]))
characterAdded:Fire(localPlayer.Character)
local impactsBefore3 = #impacts
spam("Wood", "Cut2", 1)
check(#impacts > impactsBefore3 and Swing.LocalRig() and Swing.LocalRig().Character == localPlayer.Character, "11. respawn: golpe e impactos continuam no personagem novo")

if #problems > 0 then
	print(#problems .. " problema(s).")
	process.exit(1)
end
print("OK: combate com 4 camadas sincronizadas, temas, rachaduras, quebra, câmera e números, sem acumular nada.")
print("REQUER VALIDAÇÃO NO ROBLOX STUDIO: beleza, partículas, cores por tema, tremor de câmera, números e FPS real.")
process.exit(0)
