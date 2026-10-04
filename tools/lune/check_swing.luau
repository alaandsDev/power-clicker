--[[
	check_swing.luau — o golpe da espada (SwordSwing + SwordSwingController) e
	a sincronia com o arco/corte (SlashController + CutFx), de verdade, sobre
	um personagem R15 montado aqui (ombro, cotovelo, punho, cintura, Tool com
	RightGrip), com relógio simulado.

		lune run tools/lune/check_swing.luau [raiz]

	Verifica:
	  1. um hit dispara o golpe (o braço sai da pose de segurar);
	  2. spam a 9 hits/s por 30 s: nenhuma instância nova acumulando, nenhuma
	     Animation/AnimationTrack, um golpe por vez;
	  3. variações A/B alternadas (e um C ocasional);
	  4. a espada volta: C0 de cada articulação EXATAMENTE o original;
	  5. trocar a skin (a Tool inteira) no meio do golpe não quebra nada e o
	     RightGrip não é tocado;
	  6. o golpe não lê nada de dano/economia;
	  7. arco e corte (CutFx) desenhados no IMPACTO do golpe, na diagonal dele;
	  8. "Efeitos reduzidos" tira arco/corte mas mantém o golpe;
	  9. morrer/respawnar no meio do golpe: nada quebrado, golpe no corpo novo;
	 10. outros jogadores: o sinal do servidor (SwingSeq) faz golpes curtos no
	     personagem deles por perto, e nada longe.

	Adaptação SÓ AQUI: `.Position` -> `.CFrame.Position` no controller.

	REQUER VALIDAÇÃO NO ROBLOX STUDIO: a pose real por cima do "toolnone" do
	Animator, se o golpe lê bem em terceira pessoa, braço x espada na tela e
	o rastro da lâmina.
]]
local process = require("@lune/process")
local fs = require("@lune/fs")
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

-- ── Ambiente ────────────────────────────────────────────────────────────────
local Signal = E.require(E.Shared.Utils.Signal)
local now = 1000
E.extraGlobals.os = setmetatable({ clock = function()
	return now
end }, { __index = os })
E.extraGlobals.TweenInfo = { new = function(...)
	return { ... }
end }
E.stubs.TweenService = { Create = function()
	return { Play = function() end, Cancel = function() end }
end }
-- task.delay registrado (o desenho no impacto é chamado à mão, no tempo certo).
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

-- O Lune não expõe BasePart.Position (só CFrame).
E.patches["StarterPlayer.Client.Controllers.SwordSwingController"] = { { ".Position", ".CFrame.Position", "all" } }

local settings = { ReducedEffects = false }
local client = "StarterPlayer.Client."
E.stubModules[client .. "Controllers.DataController"] = { Get = function(key)
	return if key == "Settings" then settings else nil
end, IsLoaded = function()
	return true
end }

-- Personagem R15 mínimo: as articulações que o golpe usa, com C0 de verdade.
local function motor(parent, name, part0, part1, c0)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = c0
	m.Parent = parent
	return m
end
local function part(model, name)
	local p = Instance.new("Part")
	p.Name = name
	p.Parent = model
	return p
end
local function newCharacter(name)
	local model = Instance.new("Model")
	model.Name = name
	local root = part(model, "HumanoidRootPart")
	local lower = part(model, "LowerTorso")
	local upper = part(model, "UpperTorso")
	local upperArm = part(model, "RightUpperArm")
	local lowerArm = part(model, "RightLowerArm")
	local hand = part(model, "RightHand")
	motor(lower, "Root", root, lower, CF.new(0, -1, 0))
	motor(upper, "Waist", lower, upper, CF.new(0, 0.2, 0))
	motor(upperArm, "RightShoulder", upper, upperArm, CF.new(1, 0.56, 0))
	motor(lowerArm, "RightElbow", upperArm, lowerArm, CF.new(0, -0.33, 0))
	motor(hand, "RightWrist", lowerArm, hand, CF.new(0, -0.5, 0))
	local tool = Instance.new("Tool")
	tool.Name = "CutBlade"
	local handle = part(tool, "Handle")
	tool.Parent = model
	local grip = Instance.new("Weld")
	grip.Name = "RightGrip"
	grip.Part0 = hand
	grip.Part1 = handle
	grip.C0 = CF.new(0, -1, 0) * CF.Angles(math.rad(-90), 0, 0)
	grip.C1 = CF.new(0, 0.2, 0)
	grip.Parent = hand
	model.Parent = E.Workspace
	return model
end

local Sig = { Connect = function()
	return { Disconnect = function() end }
end }
local characterAdded, characterRemoving = Signal.new(), Signal.new()
local localPlayer = {
	Name = "Local",
	UserId = 1,
	Character = nil,
	CharacterAdded = characterAdded,
	CharacterRemoving = characterRemoving,
	GetAttribute = function(_, key)
		return if key == "BestCut" then "Cut4" else nil
	end,
	GetAttributeChangedSignal = function()
		return Sig
	end,
}
local otherSwing = Signal.new()
local other = {
	Name = "Other",
	UserId = 2,
	Character = nil,
	CharacterRemoving = Signal.new(),
	GetAttributeChangedSignal = function(_, name)
		return if name == "SwingSeq" then otherSwing else Sig
	end,
}
E.stubs.Players = {
	LocalPlayer = localPlayer,
	GetPlayers = function()
		return { localPlayer, other }
	end,
	PlayerAdded = Signal.new(),
	PlayerRemoving = Signal.new(),
}
local renderStep
E.stubs.RunService.RenderStepped = { Connect = function(_, fn)
	renderStep = fn
	return { Disconnect = function() end }
end }

local CutFx = E.require(E.Client.Effects.CutFx)
local cutPlays = {}
local originalPlay = CutFx.Play
CutFx.Play = function(rig, recipe, origin, scale, roll)
	table.insert(cutPlays, { At = now, Roll = roll, CutId = recipe.CutId })
	return originalPlay(rig, recipe, origin, scale, roll)
end
roblox.implementMethod("ParticleEmitter", "Emit", function() end)

local SwordSwing = E.require(E.Client.Effects.SwordSwing)
local Swing = E.require(E.Client.Controllers.SwordSwingController)
local Slash = E.require(E.Client.Controllers.SlashController)

localPlayer.Character = newCharacter("Local")
Swing.Init()
Slash.Init()
Swing.Start()
check(renderStep ~= nil, "uma conexão por quadro para todos os golpes (RenderStepped)")

local function joints(character)
	return {
		Shoulder = character.RightUpperArm.RightShoulder,
		Elbow = character.RightLowerArm.RightElbow,
		Wrist = character.RightHand.RightWrist,
		Waist = character.UpperTorso.Waist,
	}
end
local function same(a, b): boolean
	return (a.Position - b.Position).Magnitude < 1e-6 and (a.LookVector - b.LookVector).Magnitude < 1e-6 and (a.UpVector - b.UpVector).Magnitude < 1e-6
end
local function baseOf(character)
	local list = {}
	for key, m in joints(character) do
		list[key] = m.C0
	end
	return list
end
local function atBase(character, base): boolean
	for key, m in joints(character) do
		if not same(m.C0, base[key]) then
			return false
		end
	end
	return true
end
local function frames(seconds: number)
	local steps = math.max(math.floor(seconds * 60 + 0.5), 1)
	for _ = 1, steps do
		now += 1 / 60
		renderStep()
		runDelayed()
	end
end
local function countInstances(): number
	return #E.Workspace:GetDescendants()
end
local function countKind(className: string): number
	local n = 0
	for _, d in E.Workspace:GetDescendants() do
		if d:IsA(className) then
			n += 1
		end
	end
	return n
end

local character = localPlayer.Character
local base = baseOf(character)
local gripBefore = character.RightHand.RightGrip.C0
check(Swing.LocalRig() ~= nil, "rig do personagem R15 montado (ombro, cotovelo, punho, cintura)")

-- 1. Um hit dispara o golpe.
Slash.Play()
check(Swing.LocalRig().Active, "1. um hit dispara o golpe")
frames(0.03)
check(not same(joints(character).Shoulder.C0, base.Shoulder) and not same(joints(character).Elbow.C0, base.Elbow), "1. braço e espada saem da pose de segurar (ombro e cotovelo se movem)")

-- 7. Corte no impacto, na diagonal do golpe.
frames(0.2)
local rig = Swing.LocalRig()
local impact = rig.Duration * SwordSwing.IMPACT
check(#cutPlays == 1, "7. o corte (CutFx) foi desenhado uma vez para o hit")
check(rig.Duration >= 0.10 and rig.Duration <= 0.16, string.format("golpe curto (%.2f s, entre 0,10 e 0,16)", rig.Duration))
check(math.abs((cutPlays[1].At - 1000) - impact) <= 1 / 60 + 1e-6, string.format("7. o corte aparece no IMPACTO do golpe (%.3f s depois do clique; impacto em %.3f s)", cutPlays[1].At - 1000, impact))
check(cutPlays[1].CutId == "Cut4", "7. o corte desenhado é o do melhor Corte (CutVisuals), não o da espada")
check(cutPlays[1].Roll >= -10 and cutPlays[1].Roll <= 10, "7. variação A: corte na diagonal do golpe A")

-- 4. Volta exata.
check(atBase(character, base), "4. depois do golpe, cada articulação volta EXATAMENTE ao C0 original")

-- 3. Alternância.
local variants = {}
for _ = 1, 14 do
	Slash.Play()
	table.insert(variants, Swing.LocalRig().Variant)
	frames(0.3)
end
local seq = table.concat(variants, "")
local expected = {}
for index = 2, 15 do
	table.insert(expected, SwordSwing.VariantFor(index))
end
check(seq == table.concat(expected, "") and string.find(seq, "AB") and string.find(seq, "BA") and string.find(seq, "C"), "3. golpes alternam A/B, com um C ocasional (" .. seq .. ")")
local rolls = {}
for index = 2, #cutPlays do
	rolls[variants[index - 1]] = cutPlays[index].Roll
end
check(rolls.A and rolls.B and rolls.A > -20 and rolls.B < -70, "7. o corte acompanha a variação (A e B em diagonais opostas)")

-- 2. Spam a 9 hits/s por 30 s.
local before = countInstances()
local maxActive = 0
local hits = 0
local t0 = now
local nextHit = now
while now - t0 < 30 do
	if now >= nextHit then
		Slash.Play()
		hits += 1
		nextHit += 1 / 9
	end
	now += 1 / 60
	renderStep()
	runDelayed()
	maxActive = math.max(maxActive, if Swing.LocalRig().Active then 1 else 0)
end
frames(0.3)
check(hits >= 268, string.format("2. %d hits em 30 s (~9/s)", hits))
check(countInstances() == before, string.format("2. nenhuma instância acumulando (%d antes, %d depois)", before, countInstances()))
check(countKind("Animation") == 0 and countKind("Animator") == 0, "2. nenhuma Animation/AnimationTrack criada (golpe procedural)")
check(Swing.LocalRig().Duration == SwordSwing.FAST_SECONDS, "2. em spam o golpe usa a versão curta (" .. SwordSwing.FAST_SECONDS .. " s)")
check(atBase(character, base), "2/4. depois do spam, o braço volta exatamente à pose original")

-- 8. Efeitos reduzidos: sem arco/corte, com golpe.
settings.ReducedEffects = true
local cutsBefore = #cutPlays
Slash.Play()
check(Swing.LocalRig().Active, "8. com Efeitos reduzidos o golpe da espada continua")
frames(0.3)
check(#cutPlays == cutsBefore, "8. com Efeitos reduzidos o arco/corte não é desenhado")
settings.ReducedEffects = false

-- 5/10. Trocar a skin no meio do golpe.
Slash.Play()
frames(0.04)
character.CutBlade:Destroy()
local tool = Instance.new("Tool")
tool.Name = "CutBlade"
part(tool, "Handle")
tool.Parent = character
frames(0.3)
check(atBase(character, base), "5/10. trocar a skin no meio do golpe: o braço volta ao normal")
check(same(character.RightHand.RightGrip.C0, gripBefore), "5. o golpe nunca mexe no RightGrip (a pegada da espada)")
Slash.Play()
check(Swing.LocalRig().Active, "5. depois da troca o golpe continua funcionando (mesma lógica para toda skin)")
frames(0.3)

-- 9. Morrer/respawnar no meio do golpe.
Slash.Play()
frames(0.04)
characterRemoving:Fire(character)
check(Swing.LocalRig() == nil and atBase(character, base), "9. personagem saindo no meio do golpe: rig descartado e C0 devolvido")
character:Destroy()
local fresh = newCharacter("Local")
localPlayer.Character = fresh
characterAdded:Fire(fresh)
local freshBase = baseOf(fresh)
check(Swing.LocalRig() ~= nil and Swing.LocalRig().Character == fresh, "9. o personagem novo ganha o próprio rig")
Slash.Play()
frames(0.04)
check(not same(joints(fresh).Shoulder.C0, freshBase.Shoulder), "9. golpe funciona no personagem novo")
frames(0.3)
check(atBase(fresh, freshBase), "9. e volta à pose original dele")

-- 10. Outro jogador: perto golpeia, longe não.
other.Character = newCharacter("Other")
other.Character.HumanoidRootPart.CFrame = CF.new(10, 0, 0)
local otherBase = baseOf(other.Character)
otherSwing:Fire()
frames(0.05)
check(not same(joints(other.Character).Shoulder.C0, otherBase.Shoulder), "10. o sinal do servidor faz o outro jogador golpear no meu cliente")
frames(0.6)
check(atBase(other.Character, otherBase), "10. a sequência dele é curta e volta à pose original")
other.Character.HumanoidRootPart.CFrame = CF.new(500, 0, 0)
otherSwing:Fire()
frames(0.05)
check(atBase(other.Character, otherBase), "10. jogador longe: nada é animado")

-- 6. O golpe não lê dano nem economia.
local sources = {
	fs.readFile(E.Root .. "/src/client/Effects/SwordSwing.luau"),
	fs.readFile(E.Root .. "/src/client/Controllers/SwordSwingController.luau"),
}
local clean = true
for _, source in sources do
	for _, word in { "CutConfig", "PowerFormula", "Currency", "ClientNet", "FireServer", "Damage", "SwordConfig" } do
		if string.find(source, word, 1, true) then
			clean = false
			print("      usa " .. word)
		end
	end
end
check(clean, "6. o golpe é só visual: não lê Corte, Power, moeda nem espada e não manda nada ao servidor")
local clickSource = fs.readFile(E.Root .. "/src/server/Services/ClickService.luau")
local processBody = string.match(clickSource, "local function processClick.-\nend\n")
check(processBody and not string.find(processBody, "SwingSeq", 1, true), "6. o sinal do golpe fica fora do cálculo do clique (processClick não muda)")

if #problems > 0 then
	print(#problems .. " problema(s).")
	process.exit(1)
end
print("OK: golpe da espada a cada hit, sincronizado com o corte, sem acumular nada.")
print("REQUER VALIDAÇÃO NO ROBLOX STUDIO: a pose real sobre o Animator, leitura em 3a pessoa e o rastro da lâmina.")
process.exit(0)
