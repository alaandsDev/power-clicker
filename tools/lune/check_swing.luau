--[[
	check_swing.luau — o golpe da espada (SwordSwing + SwordSwingController) e
	a sincronia com o arco/corte (SlashController + CutFx), de verdade, sobre
	um personagem R15 montado aqui (ombros, cotovelos, punho, cintura,
	pescoço, Tool com lâmina e RightGrip), com relógio simulado.

		lune run tools/lune/check_swing.luau [raiz]

	Verifica:
	  1. um hit dispara o golpe (o braço sai da pose de segurar);
	  2. spam a 9 hits/s por 30 s: nenhuma instância nova acumulando, nenhuma
	     Animation/AnimationTrack, um golpe por vez;
	  3. combo visual estrito A→B→C→A... (ver bloco K);
	  4. o golpe volta para a POSTURA de combate (e, sem espada, cada C0 volta
	     EXATAMENTE ao original);
	  5. trocar a skin (a Tool inteira) no meio do golpe não quebra nada e o
	     RightGrip não é tocado;
	  6. o golpe não lê nada de dano/economia;
	  7. arco e corte (CutFx) desenhados no IMPACTO do golpe, na diagonal dele;
	  8. "Efeitos reduzidos" tira arco/corte mas mantém o golpe;
	  9. morrer/respawnar no meio do golpe: nada quebrado, golpe no corpo novo;
	 10. outros jogadores: o sinal do servidor (SwingSeq) faz golpes curtos no
	     personagem deles por perto, e nada longe.
	  P. POSTURA DE COMBATE (parado com espada): espada baixa e para o lado
	     (nem vertical, nem atravessando o corpo), braço esquerdo afastado,
	     tronco assimétrico com a cabeça para frente, respiração sutil;
	     andando/correndo/pulando vira "carregar" (sem tronco/braço esquerdo);
	     transições sem tranco (parado↔andando, golpe→postura, equipar/
	     desequipar, trocar de espada); lâminas grandes não tocam o chão
	     (modelo no plano do corpo, toda skin do SwordConfig); R6 e Joint
	     Upgrade também; respawn começa limpo; outros jogadores perto também.
	  K. COMBO VISUAL de 3 golpes: A, B, C e volta ao A; spam a 9/s e Auto
	     Click (no ritmo do servidor) seguem o ciclo; o Corte segue a
	     direção (A "/", B "\\", C vertical) e o sentido de varrer; o C não
	     muda dano/Power nem o ritmo; volta ao A depois de 1,2 s parado, no
	     respawn e na troca de espada; R6/R15/Joint Upgrade; "Efeitos
	     reduzidos" mantém o movimento; nada acumulando.

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
local attributes = { BestCut = "Cut4" }
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
-- O Lune não expõe BasePart.Position: o impacto do golpe (CombatFx) lê a posição.
E.patches["StarterPlayer.Client.Controllers.CombatFxController"] = {
	{ "row.Position", "row.CFrame.Position", "all" },
	{ "root.Position", "root.CFrame.Position", "all" },
}
E.patches["StarterPlayer.Client.Controllers.WallController"] = {
	{ "row.Position", "row.CFrame.Position", "all" },
	{ "root.Position", "root.CFrame.Position", "all" },
}
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
local function newTool(bladeLength)
	local tool = Instance.new("Tool")
	tool.Name = "CutBlade"
	part(tool, "Handle")
	local blade = part(tool, "Blade")
	blade.Size = V3.new(0.22, bladeLength, 0.9)
	return tool
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
	local leftUpper = part(model, "LeftUpperArm")
	local leftLower = part(model, "LeftLowerArm")
	local head = part(model, "Head")
	motor(lower, "Root", root, lower, CF.new(0, -1, 0))
	motor(upper, "Waist", lower, upper, CF.new(0, 0.2, 0))
	motor(upperArm, "RightShoulder", upper, upperArm, CF.new(1, 0.56, 0))
	motor(lowerArm, "RightElbow", upperArm, lowerArm, CF.new(0, -0.33, 0))
	motor(hand, "RightWrist", lowerArm, hand, CF.new(0, -0.5, 0))
	motor(leftUpper, "LeftShoulder", upper, leftUpper, CF.new(-1, 0.56, 0))
	motor(leftLower, "LeftElbow", leftUpper, leftLower, CF.new(0, -0.33, 0))
	motor(head, "Neck", upper, head, CF.new(0, 0.8, 0))
	local tool = newTool(4.2)
	local handle = tool.Handle
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
		return attributes[key]
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
	GetAttribute = function()
		return nil
	end,
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
CutFx.Play = function(rig, recipe, origin, scale, roll, sweep)
	table.insert(cutPlays, { At = now, Roll = roll, CutId = recipe.CutId, Scale = scale, Sweep = sweep, Slashes = recipe.Slashes, Color = recipe.Color })
	return originalPlay(rig, recipe, origin, scale, roll, sweep)
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
		Neck = character.Head.Neck,
		LShoulder = character.LeftUpperArm.LeftShoulder,
		LElbow = character.LeftLowerArm.LeftElbow,
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
-- Cada articulação exatamente na pose `pose` (graus somados ao C0 original).
local function close(a, b): boolean
	-- C0 é float32: 1e-4 de folga depois de compor rotações.
	return (a.Position - b.Position).Magnitude < 1e-4 and (a.LookVector - b.LookVector).Magnitude < 1e-4 and (a.UpVector - b.UpVector).Magnitude < 1e-4
end
local function atPose(character, base, pose): boolean
	for key, m in joints(character) do
		if not close(m.C0, SwordSwing.Posed(base[key], pose[key])) then
			return false
		end
	end
	return true
end
-- Na postura atual do rig (golpe terminado, corpo de volta à postura).
local function atRest(character, base, rig): boolean
	return rig ~= nil and not rig.Active and atPose(character, base, rig.Rest)
end
-- Ângulo (graus) entre duas orientações.
local function angle(a, b): number
	-- Pela corda (|u - v|): estável em float32 para ângulos pequenos.
	local function between(u, v)
		return math.deg(2 * math.asin(math.clamp((u - v).Magnitude / 2, 0, 1)))
	end
	return math.max(between(a.LookVector, b.LookVector), between(a.UpVector, b.UpVector), between(a.RightVector, b.RightVector))
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
-- Roll do CutFx = inclinação do golpe - 45 (o risco único do Corte já nasce a 45°).
check(cutPlays[1].Roll >= -98 and cutPlays[1].Roll <= -82, "7. golpe A: corte na diagonal \"/\" do golpe A")

-- 4. Volta para a postura.
check(atRest(character, base, rig) and not atBase(character, base), "4. depois do golpe, o corpo volta EXATAMENTE para a postura de combate (espada na mão)")

-- 3. Alternância.
local variants = {}
for _ = 1, 14 do
	Slash.Play()
	table.insert(variants, Swing.LocalRig().Variant)
	frames(0.3)
end
local seq = table.concat(variants, "")
check(seq == "BCABCABCABCABC", "3. combo estrito A→B→C→A... (depois do A do teste 1: " .. seq .. ")")
local rolls = {}
for index = 2, #cutPlays do
	rolls[variants[index - 1]] = cutPlays[index].Roll
end
check(rolls.A and rolls.B and rolls.C and rolls.A < -80 and rolls.B > -10 and rolls.B < 10 and rolls.C > -55 and rolls.C < -35, "7. o corte acompanha o golpe (A e B em diagonais opostas, C vertical)")

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
check(atRest(character, base, Swing.LocalRig()), "2/4. depois do spam, o corpo volta exatamente para a postura")

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
local tool = newTool(4.2)
tool.Parent = character
frames(0.3)
check(atRest(character, base, Swing.LocalRig()), "5/10. trocar a skin no meio do golpe: o corpo volta para a postura")
check(same(character.RightHand.RightGrip.C0, gripBefore), "5. o golpe nunca mexe no RightGrip (a pegada da espada)")
Slash.Play()
check(Swing.LocalRig().Active, "5. depois da troca o golpe continua funcionando (mesma lógica para toda skin)")
frames(0.3)

-- 9. Morrer/respawnar no meio do golpe.
Slash.Play()
frames(0.04)
characterRemoving:Fire(character)
check(Swing.LocalRig() == nil and atBase(character, base), "9. personagem saindo no meio do golpe: rig descartado e C0 devolvido EXATO")
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
check(atRest(fresh, freshBase, Swing.LocalRig()), "9. e volta para a postura dele")

-- 9b. Outros formatos de personagem: R6 e R15 com "Avatar Joint Upgrade"
-- (AnimationConstraint). Antes o golpe só reconhecia Motor6D do R15 e, em
-- outro formato, sumia em silêncio.
local function respawnAs(model)
	characterRemoving:Fire(localPlayer.Character)
	localPlayer.Character:Destroy()
	model.Parent = E.Workspace
	localPlayer.Character = model
	characterAdded:Fire(model)
end
do
	local r6 = Instance.new("Model")
	r6.Name = "LocalR6"
	part(r6, "HumanoidRootPart")
	local torso = part(r6, "Torso")
	local arm = part(r6, "Right Arm")
	local shoulder = Instance.new("Motor6D")
	shoulder.Name = "Right Shoulder"
	shoulder.Part0 = torso
	shoulder.Part1 = arm
	shoulder.C0 = CF.new(1, 0.5, 0) * CF.Angles(0, math.rad(90), 0)
	shoulder.Parent = torso
	local base = shoulder.C0
	respawnAs(r6)
	check(Swing.LocalRig() ~= nil and Swing.LocalRig().Kind == "Motor6D", "9b. personagem R6: rig montado no \"Right Shoulder\"")
	Slash.Play()
	frames(0.04)
	check(not same(shoulder.C0, base) and (shoulder.C0.Position - base.Position).Magnitude < 1e-6, "9b. R6: o braço golpeia (gira no ombro, sem sair do lugar)")
	frames(0.3)
	check(same(shoulder.C0, base), "9b. R6: volta exatamente à pose original")
	local cycle = { Swing.LocalRig().Variant }
	for _ = 1, 3 do
		Slash.Play()
		table.insert(cycle, Swing.LocalRig().Variant)
		frames(0.3)
	end
	check(table.concat(cycle) == "ABCA", "K13. R6: combo A→B→C→A (" .. table.concat(cycle) .. ")")
end
do
	local upgraded = Instance.new("Model")
	upgraded.Name = "LocalUpgraded"
	part(upgraded, "HumanoidRootPart")
	local upper = part(upgraded, "UpperTorso")
	local upperArm = part(upgraded, "RightUpperArm")
	local rigAttachment = Instance.new("Attachment")
	rigAttachment.Name = "RightShoulderRigAttachment"
	rigAttachment.CFrame = CF.new(1, 0.56, 0)
	rigAttachment.Parent = upper
	local other = Instance.new("Attachment")
	other.Name = "RightShoulderRigAttachment"
	other.Parent = upperArm
	local constraint = Instance.new("AnimationConstraint")
	constraint.Name = "RightShoulder"
	constraint.Attachment0 = rigAttachment
	constraint.Attachment1 = other
	constraint.Parent = upperArm
	local base = rigAttachment.CFrame
	respawnAs(upgraded)
	check(Swing.LocalRig() ~= nil and Swing.LocalRig().Kind == "AnimationConstraint", "9b. R15 com Avatar Joint Upgrade: rig montado na AnimationConstraint")
	Slash.Play()
	frames(0.04)
	check(not same(rigAttachment.CFrame, base), "9b. Joint Upgrade: o braço golpeia (pela Attachment0 da articulação)")
	frames(0.3)
	check(same(rigAttachment.CFrame, base), "9b. Joint Upgrade: volta exatamente à pose original")
	local cycle = { Swing.LocalRig().Variant }
	for _ = 1, 3 do
		Slash.Play()
		table.insert(cycle, Swing.LocalRig().Variant)
		frames(0.3)
	end
	check(table.concat(cycle) == "ABCA", "K15. Joint Upgrade: combo A→B→C→A (" .. table.concat(cycle) .. ")")
end
do
	local fresh = newCharacter("Local")
	fresh.Parent = nil
	respawnAs(fresh)
end

-- 10. Outro jogador: perto golpeia, longe não.
other.Character = newCharacter("Other")
other.Character.HumanoidRootPart.CFrame = CF.new(10, 0, 0)
local otherBase = baseOf(other.Character)
otherSwing:Fire()
frames(0.05)
check(not same(joints(other.Character).Shoulder.C0, otherBase.Shoulder), "10. o sinal do servidor faz o outro jogador golpear no meu cliente")
frames(0.6)
check(atRest(other.Character, otherBase, Swing.RemoteRig(other)) and not atBase(other.Character, otherBase), "10. a sequência dele é curta e volta para a postura de combate dele")
other.Character.HumanoidRootPart.CFrame = CF.new(500, 0, 0)
frames(0.6)
otherSwing:Fire()
frames(0.05)
check(Swing.RemoteRig(other) == nil and atBase(other.Character, otherBase), "10. jogador longe: rig descartado, C0 EXATO e nada é animado")
other.Character.HumanoidRootPart.CFrame = CF.new(10, 0, 0)
frames(0.6)
check(Swing.RemoteRig(other) ~= nil and atPose(other.Character, otherBase, Swing.RemoteRig(other).Rest) and not atBase(other.Character, otherBase), "P. outro jogador perto, parado com espada: postura de combate também no meu cliente")

-- ── P. POSTURA DE COMBATE ──────────────────────────────────────────────────
do
	local me = localPlayer.Character
	local root = me.HumanoidRootPart
	local rigP = Swing.LocalRig()
	-- O C0 original é o que o rig guardou ao montar (a postura já está aplicada).
	local meBase = {}
	for key, joint in rigP.Joints do
		meBase[key] = joint.Base
	end
	frames(1.5)
	local rest = rigP.Rest
	local stance = SwordSwing.Stance(4.2, true, true)
	local pitch = SwordSwing.SwordPitch(stance)
	check(rigP.Idle > 0.95 and rigP.Armed > 0.95, "P1. parado com espada: postura de combate ativa")
	check(atPose(me, meBase, rest) and not atBase(me, meBase), "P1. o corpo está na postura (C0 = original + postura)")
	check(pitch >= 70 and pitch <= 100, string.format("P1. espada baixa, perto da horizontal (inclinação %.0f°; 90 = horizontal, 180 = em pé)", pitch))
	check(stance.Shoulder.Y <= 0 and stance.Shoulder.Z > 0, "P1. braço da espada aberto para fora: a espada não cruza o corpo")
	check(stance.LShoulder.Z < 0 and stance.LShoulder ~= V3.zero, "P1. braço esquerdo levemente afastado")
	check(stance.Waist.Y ~= 0 and math.abs(stance.Neck.Y + stance.Waist.Y) < 1e-6, "P1. tronco assimétrico, cabeça compensada (olhando para frente)")
	-- Respiração: sutil e contínua.
	local minW, maxW, maxShoulder, maxStep = math.huge, -math.huge, 0, 0
	local last = me.UpperTorso.Waist.C0
	local s0 = rigP.Rest.Shoulder
	for _ = 1, 60 * 8 do
		now += 1 / 60
		renderStep()
		local waist = rigP.Rest.Waist.X
		minW = math.min(minW, waist)
		maxW = math.max(maxW, waist)
		maxShoulder = math.max(maxShoulder, (rigP.Rest.Shoulder - s0).Magnitude)
		maxStep = math.max(maxStep, angle(last, me.UpperTorso.Waist.C0))
		last = me.UpperTorso.Waist.C0
	end
	check(maxW - minW > 1 and maxW - minW < 4, string.format("P1. respiração: tronco oscila %.1f° (sutil, entre 1 e 4)", maxW - minW))
	check(maxShoulder < 4 and maxStep < 0.3, string.format("P1. sem balançar demais (ombro ±%.1f°, no máximo %.2f° por quadro)", maxShoulder, maxStep))

	-- Andando / correndo / pulando: "carregar", sem tranco.
	local function moveFor(seconds, velocity)
		local worst = 0
		local previous = {}
		for key, m in joints(me) do
			previous[key] = m.C0
		end
		for _ = 1, math.floor(seconds * 60 + 0.5) do
			now += 1 / 60
			root.CFrame = root.CFrame + velocity / 60
			renderStep()
			for key, m in joints(me) do
				worst = math.max(worst, angle(previous[key], m.C0))
				previous[key] = m.C0
			end
		end
		return worst
	end
	local carry = SwordSwing.Carry(4.2, true, true)
	local jump = moveFor(1, V3.new(16, 0, 0))
	check(rigP.Idle < 0.05 and atPose(me, meBase, rigP.Rest), "P2. andando (16 studs/s): o corpo vai para \"carregar\"")
	check((rigP.Rest.Shoulder - carry.Shoulder).Magnitude < 1 and rigP.Rest.Waist.Magnitude < 0.5 and rigP.Rest.LShoulder.Magnitude < 0.5, "P2. andando: só o braço da espada; tronco e braço esquerdo ficam com a locomoção")
	check(SwordSwing.SwordPitch(carry) > pitch and carry.Shoulder.Z > 0, string.format("P2. andando: espada mais alta (%.0f°) e afastada das pernas", SwordSwing.SwordPitch(carry)))
	check(jump < 5, string.format("P5. parado → andando sem tranco (maior passo %.2f° por quadro)", jump))
	local run = moveFor(1, V3.new(0, 0, 30))
	check(rigP.Idle < 0.05 and run < 5, "P3. correndo (30 studs/s): continua carregando, sem tranco")
	local stopped = moveFor(1.5, V3.zero)
	check(rigP.Idle > 0.95 and stopped < 5, string.format("P5. andando → parado: volta à postura sem tranco (maior passo %.2f°)", stopped))
	local up = moveFor(0.3, V3.new(0, 25, 0))
	local down = moveFor(0.3, V3.new(0, -25, 0))
	check(rigP.Idle < 0.5 and up < 5 and down < 5, "P4. pulando/caindo: carregar, sem tranco")
	moveFor(1.5, V3.zero)
	local teleport = root.CFrame
	root.CFrame = root.CFrame + V3.new(400, 0, 0)
	frames(0.1)
	check(rigP.Idle > 0.9, "P4. teleporte não conta como correr")
	root.CFrame = teleport

	-- Golpe a partir da postura e de volta (sem tranco no começo e no fim).
	frames(1)
	local from = rigP.Current
	for _, variant in { "A", "B", "C" } do
		local p0 = SwordSwing.Pose(variant, 0, from, rigP.Rest)
		local pEnd = SwordSwing.Pose(variant, 0.9999, from, rigP.Rest)
		local p1 = SwordSwing.Pose(variant, 1, from, rigP.Rest)
		local startsAt, endsAt = 0, 0
		for _, key in SwordSwing.Keys() do
			startsAt = math.max(startsAt, (p0[key] - from[key]).Magnitude)
			endsAt = math.max(endsAt, (pEnd[key] - p1[key]).Magnitude, (p1[key] - rigP.Rest[key]).Magnitude)
		end
		check(startsAt < 1e-6 and endsAt < 0.01, "P6. golpe " .. variant .. ": começa na postura e termina na postura (sem salto)")
	end
	Slash.Play()
	local swingVariant = rigP.Variant
	frames(0.3)
	check(atRest(me, meBase, rigP), "P6. IDLE → golpe " .. swingVariant .. " → IDLE: de volta à postura")
	-- Golpe tem prioridade: durante o golpe a pose é a do golpe, não a postura.
	Slash.Play()
	frames(0.03)
	check(rigP.Active and not atPose(me, meBase, rigP.Rest), "P6. o golpe tem prioridade sobre a postura")
	frames(0.3)

	-- Trocar de espada (lâmina maior): a ponta sobe, sem tranco.
	me.CutBlade:Destroy()
	newTool(6.6).Parent = me
	local swap = moveFor(1, V3.zero)
	local big = SwordSwing.Stance(6.6, true, true)
	check(SwordSwing.SwordPitch(big) > pitch and (rigP.Rest.Wrist - big.Wrist).Magnitude < 1 and swap < 5, string.format("P8. trocar para lâmina grande: ponta mais alta (%.0f° → %.0f°), sem tranco", pitch, SwordSwing.SwordPitch(big)))

	-- Sem espada: tudo volta EXATAMENTE ao original e para de escrever.
	me.CutBlade:Destroy()
	local unequip = moveFor(1.5, V3.zero)
	check(rigP.Armed == 0 and atBase(me, meBase) and not rigP.Applied and unequip < 5, "P9. guardar a espada: volta suave e EXATA ao C0 original")
	local shoulder = me.RightUpperArm.RightShoulder
	local c0 = shoulder.C0
	frames(0.2)
	check(same(shoulder.C0, c0), "P9. sem espada e parado: nada é escrito por quadro")
	newTool(4.2).Parent = me
	local equip = moveFor(1.5, V3.zero)
	check(rigP.Armed > 0.95 and equip < 5, "P9. equipar de novo: entra na postura sem tranco")

	-- Lâminas: nenhuma skin toca o chão (modelo no plano do corpo: ombro a 4,5
	-- studs, braço+antebraço 2,2 (R15) ou braço 2 (R6), cabo 0,6; margem de
	-- 20° de inclinação extra do encaixe). REQUER VALIDAÇÃO NO STUDIO.
	local SwordConfig = E.require(E.Shared.Config.SwordConfig)
	local worst = math.huge
	local worstName = ""
	for id, sword in SwordConfig.Swords do
		local length = 0.6 + sword.BladeSize.Y
		for _, kind in { "R15", "R6" } do
			local r15 = kind == "R15"
			local stanceOf = SwordSwing.Stance(sword.BladeSize.Y, r15, r15)
			local poses = { stanceOf, SwordSwing.Carry(sword.BladeSize.Y, r15, r15) }
			for _, variant in { "A", "B", "C" } do
				for step = 0, 50 do
					local pose = SwordSwing.Pose(variant, step / 50, stanceOf, stanceOf)
					if not r15 then
						pose = table.clone(pose)
						pose.Elbow, pose.Wrist = V3.zero, V3.zero
					end
					table.insert(poses, pose)
				end
			end
			for _, pose in poses do
				local arm = math.rad(90 + pose.Shoulder.X)
				local fore = math.rad(90 + pose.Shoulder.X + pose.Elbow.X)
				local hand = if r15 then 4.5 - 1.1 * math.cos(arm) - 1.1 * math.cos(fore) else 4.5 - 2 * math.cos(arm)
				local tip = hand - length * math.cos(math.rad(SwordSwing.SwordPitch(pose) - 20))
				if tip < worst then
					worst = tip
					worstName = id .. " " .. kind
				end
			end
		end
	end
	check(worst > 0.2, string.format("P13. nenhuma lâmina toca o chão parada, andando ou golpeando A/B/C (ponta mais baixa %.2f studs: %s)", worst, worstName))

	-- R6 e Joint Upgrade: postura também.
	local r6 = Instance.new("Model")
	r6.Name = "LocalR6Stance"
	part(r6, "HumanoidRootPart")
	local torso = part(r6, "Torso")
	local function r6motor(name, x)
		local m = Instance.new("Motor6D")
		m.Name = name
		m.Part0 = torso
		m.Part1 = part(r6, name .. "Part")
		m.C0 = CF.new(x, 0.5, 0) * CF.Angles(0, math.rad(if x > 0 then 90 else -90), 0)
		m.Parent = torso
		return m
	end
	local rs, ls = r6motor("Right Shoulder", 1), r6motor("Left Shoulder", -1)
	local neck = Instance.new("Motor6D")
	neck.Name = "Neck"
	neck.C0 = CF.new(0, 1, 0)
	neck.Parent = torso
	local rsBase, lsBase, neckBase = rs.C0, ls.C0, neck.C0
	newTool(4.2).Parent = r6
	respawnAs(r6)
	frames(1.5)
	local r6rig = Swing.LocalRig()
	check(r6rig and not r6rig.HasWrist and not same(rs.C0, rsBase) and not same(ls.C0, lsBase) and same(neck.C0, neckBase), "P11. R6: postura nos dois ombros (sem cotovelo/punho; pescoço fica com o Roblox)")
	check(r6rig and SwordSwing.SwordPitch(r6rig.Rest) >= 80 and SwordSwing.SwordPitch(r6rig.Rest) <= 110 and (rs.C0.Position - rsBase.Position).Magnitude < 1e-6, string.format("P11. R6: espada baixa só pelo ombro (%.0f°), sem sair do lugar", if r6rig then SwordSwing.SwordPitch(r6rig.Rest) else 0))
	Slash.Play()
	frames(0.3)
	check(r6rig and not r6rig.Active and close(rs.C0, SwordSwing.Posed(rsBase, r6rig.Rest.Shoulder)), "P11. R6: golpe → volta para a postura")

	local upgraded = Instance.new("Model")
	upgraded.Name = "LocalUpgradedStance"
	part(upgraded, "HumanoidRootPart")
	local upper = part(upgraded, "UpperTorso")
	local function constraint(name, x)
		local a0 = Instance.new("Attachment")
		a0.Name = name .. "RigAttachment"
		a0.CFrame = CF.new(x, 0.56, 0)
		a0.Parent = upper
		local c = Instance.new("AnimationConstraint")
		c.Name = name
		c.Attachment0 = a0
		c.Parent = upper
		return a0
	end
	local ra, la = constraint("RightShoulder", 1), constraint("LeftShoulder", -1)
	local raBase, laBase = ra.CFrame, la.CFrame
	newTool(4.2).Parent = upgraded
	respawnAs(upgraded)
	frames(1.5)
	check(Swing.LocalRig() and Swing.LocalRig().Kind == "AnimationConstraint" and not same(ra.CFrame, raBase) and not same(la.CFrame, laBase), "P12. Joint Upgrade: postura pelas Attachment0 (ombro direito e esquerdo)")
	upgraded.CutBlade:Destroy()
	frames(1.5)
	check(same(ra.CFrame, raBase) and same(la.CFrame, laBase), "P12. Joint Upgrade: sem espada, volta EXATA ao original")

	-- Respawn: o corpo novo começa limpo e entra na postura suave.
	local fresh = newCharacter("Local")
	fresh.Parent = nil
	respawnAs(fresh)
	local freshRig = Swing.LocalRig()
	check(freshRig ~= rigP and freshRig.Armed == 0 and freshRig.Count == 0, "P10. respawn: rig novo, sem estado do anterior")
	local freshBaseP = baseOf(fresh)
	renderStep()
	local firstStep = 0
	for key, m in joints(fresh) do
		firstStep = math.max(firstStep, angle(freshBaseP[key], m.C0))
	end
	check(firstStep < 8, string.format("P10. respawn: entra na postura sem estalo (primeiro quadro %.1f°)", firstStep))
	frames(1.5)
	check(atPose(fresh, freshBaseP, freshRig.Rest) and freshRig.Armed > 0.95, "P10. e chega à postura")
	check(countKind("Animation") == 0 and countKind("AnimationTrack") == 0, "P7. nenhuma Animation/AnimationTrack em nenhuma etapa")
end

-- ── K. COMBO VISUAL DE 3 GOLPES ────────────────────────────────────────────
do
	local Combat = E.require(E.Client.Controllers.CombatFxController)
	local impactsK = {}
	local originalImpactK = Combat.OnSwingImpact
	Combat.OnSwingImpact = function(recipe, variant)
		table.insert(impactsK, { At = now, Variant = variant })
		return originalImpactK(recipe, variant)
	end
	local swings = {}
	local originalSwing = Swing.Swing
	Swing.Swing = function()
		local impact, variant = originalSwing()
		table.insert(swings, { At = now, Variant = variant })
		return impact, variant
	end
	local function seqOf(list, from)
		local out = {}
		for index = from or 1, #list do
			table.insert(out, list[index].Variant or "?")
		end
		return table.concat(out)
	end
	local me = localPlayer.Character
	local blade = me.CutBlade.Blade

	-- K1–4: A, B, C e de volta ao A (golpes isolados).
	frames(1.5)
	local mark, cutMark = #swings, #cutPlays
	for _ = 1, 4 do
		Slash.Play()
		frames(0.3)
	end
	check(seqOf(swings, mark + 1) == "ABCA", "K1–4. 1º golpe A, 2º B, 3º C, 4º volta ao A (" .. seqOf(swings, mark + 1) .. ")")
	local byVariant = {}
	for index = cutMark + 1, #cutPlays do
		byVariant[swings[mark + index - cutMark].Variant] = cutPlays[index]
	end
	local a, b, c = byVariant.A, byVariant.B, byVariant.C
	-- Inclinação efetiva do risco único = 45 + Roll (CutFx): A -45 "/", B +45 "\", C 0.
	check(a and b and c and math.abs(45 + a.Roll + 45) <= 8 and math.abs(45 + b.Roll - 45) <= 8 and math.abs(45 + c.Roll) <= 8, "K7. o Corte segue a direção do golpe: A \"/\", B \"\\\", C vertical")
	check(a and b and a.Sweep == 1 and b.Sweep == -1, "K7. A e B varrem em sentidos opostos (espelho)")
	check(a and b and c and a.Slashes == c.Slashes and b.Slashes == c.Slashes and a.Color == c.Color and a.CutId == c.CutId, "K7. o Corte mantém a identidade (mesma cor e quantidade de riscos em A, B e C)")
	check(a and c and a.Scale == 1 and c.Scale > 1 and c.Scale <= 1.2, string.format("K-C. o 3º golpe marca um pouco mais o Corte (escala %.2f), sem virar outro Corte", if c then c.Scale else 0))

	-- Rastro do C um pouco mais longo; volta no golpe seguinte.
	frames(1.5)
	Slash.Play() -- A
	local trail = blade:FindFirstChild("SwingTrail")
	local lifeA = trail and trail.Lifetime
	frames(0.3)
	Slash.Play() -- B
	frames(0.3)
	Slash.Play() -- C
	local lifeC = trail and trail.Lifetime
	local durationC = Swing.LocalRig().Duration
	frames(0.3)
	Slash.Play() -- A
	local lifeA2 = trail and trail.Lifetime
	local durationA = Swing.LocalRig().Duration
	frames(0.3)
	check(lifeA and lifeC and lifeC > lifeA and math.abs(lifeA2 - lifeA) < 1e-6, string.format("K-C. rastro do C um pouco mais longo (%.2f → %.2f s) e volta no A", lifeA or 0, lifeC or 0))
	check(durationA == durationC, "K9. o C não muda o ritmo: mesma duração de golpe (nunca segura o próximo hit)")

	-- K5: spam a 9/s segue o ciclo, sem voltar à postura entre hits.
	frames(1.5)
	mark = #swings
	local nextHit = now
	local t0 = now
	local idleBetween = false
	while now - t0 < 3 do
		if now >= nextHit then
			Slash.Play()
			nextHit += 1 / 9
		end
		now += 1 / 60
		renderStep()
		runDelayed()
		if #swings > mark + 1 and not Swing.LocalRig().Active then
			idleBetween = true
		end
	end
	local spam = seqOf(swings, mark + 1)
	check(#spam >= 26 and spam == string.rep("ABC", math.floor(#spam / 3)) .. string.sub("ABC", 1, #spam % 3), "K5. spam a 9 hits/s: ciclo A-B-C sem quebrar (" .. #spam .. " golpes)")
	check(not idleBetween, "K5. hits contínuos: IDLE → A → B → C sem voltar à postura entre os hits")
	check(#impactsK > 0 and impactsK[#impactsK].Variant ~= nil, "K18. o impacto recebe o golpe do combo (para deslocar o ponto do efeito)")
	frames(0.5)

	-- K10: parado mais de 1,2 s → volta ao A.
	frames(1.5)
	mark = #swings
	Slash.Play()
	frames(0.3)
	Slash.Play()
	frames(1.3)
	Slash.Play()
	frames(0.3)
	check(seqOf(swings, mark + 1) == "ABA", "K10. depois de ~1,2 s sem golpe o combo recomeça no A (" .. seqOf(swings, mark + 1) .. ")")
	Slash.Play()
	frames(0.9)
	Slash.Play()
	frames(0.3)
	check(seqOf(swings, mark + 4) == "BC", "K10. pausa curta (< 1,2 s) continua o combo")

	-- K12: trocar de espada → A.
	frames(1.5)
	mark = #swings
	Slash.Play()
	frames(0.3)
	Slash.Play()
	frames(0.1)
	me.CutBlade:Destroy()
	newTool(5.4).Parent = me
	frames(0.1)
	Slash.Play()
	frames(0.3)
	check(seqOf(swings, mark + 1) == "ABA", "K12. trocar de espada recomeça o combo no A (" .. seqOf(swings, mark + 1) .. ")")
	blade = me.CutBlade.Blade

	-- K16: Efeitos reduzidos: o movimento A-B-C continua; arco/corte não.
	frames(1.5)
	settings.ReducedEffects = true
	mark = #swings
	local cutsBefore, impactsBefore = #cutPlays, #impactsK
	for _ = 1, 3 do
		Slash.Play()
		check(Swing.LocalRig().Active, "K16. reduzidos: golpe " .. Swing.LocalRig().Variant .. " continua")
		frames(0.3)
	end
	local reducedImpacts = {}
	for index = impactsBefore + 1, #impactsK do
		table.insert(reducedImpacts, impactsK[index].Variant)
	end
	check(seqOf(swings, mark + 1) == "ABC" and #cutPlays == cutsBefore and table.concat(reducedImpacts) == "ABC", "K16. reduzidos: ciclo A-B-C no movimento e no impacto básico, sem arco/corte")
	settings.ReducedEffects = false

	-- K6: Auto Click: mesmo ciclo, no ritmo dos ticks do servidor.
	local EconomyConfig = E.require(E.Shared.Config.EconomyConfig)
	local tick = 1 / EconomyConfig.AutoClick.TicksPerSecond
	frames(1.5)
	attributes.AutoClickOn = true
	mark = #swings
	local beforeAuto = countInstances()
	local autoStart = now
	while now - autoStart < 30 do
		now += 1 / 60
		Slash.StepAuto(now)
		renderStep()
		runDelayed()
	end
	local auto = seqOf(swings, mark + 1)
	local worstGap = 0
	for index = mark + 2, #swings do
		worstGap = math.max(worstGap, math.abs((swings[index].At - swings[index - 1].At) - tick))
	end
	local expectedAuto = math.floor(30 / tick)
	check(math.abs(#auto - expectedAuto) <= 1, string.format("K6. Auto Click: %d golpes em 30 s (servidor: %d ticks/s)", #auto, EconomyConfig.AutoClick.TicksPerSecond))
	check(worstGap <= 1 / 60 + 1e-6, string.format("K6. Auto Click: ritmo fixo de %.2f s (desvio máx. %.3f s)", tick, worstGap))
	check(string.sub(auto, 1, 9) == "ABCABCABC" and auto == string.rep("ABC", math.floor(#auto / 3)) .. string.sub("ABC", 1, #auto % 3), "K6. Auto Click segue o ciclo A-B-C")
	check(countInstances() == beforeAuto and countKind("Animation") == 0, "K17. 30 s de Auto Click: nenhuma instância acumulando, nenhuma Animation")
	-- Clicando com o Auto ligado: os golpes manuais mostram o ataque (o Auto não dobra).
	mark = #swings
	local manual = 0
	local manualStart = now
	nextHit = now
	while now - manualStart < 2 do
		if now >= nextHit then
			Slash.Play()
			manual += 1
			nextHit += 1 / 9
		end
		now += 1 / 60
		Slash.StepAuto(now)
		renderStep()
		runDelayed()
	end
	check(#swings - mark == manual, string.format("K6. clicando com Auto ligado: só os golpes dos cliques (%d), sem golpe extra do Auto", #swings - mark))
	attributes.AutoClickOn = nil
	mark = #swings
	frames(1)
	for _ = 1, 60 do
		now += 1 / 60
		Slash.StepAuto(now)
	end
	check(#swings == mark, "K6. Auto desligado: nenhum golpe automático")

	-- K18: ponto do efeito: A um pouco à esquerda, B à direita, C no centro;
	-- o alvo (a fileira) é o mesmo.
	local row = Instance.new("Part")
	row.Size = V3.new(4, 12, 20)
	row.CFrame = CF.new(50, 6, 0)
	local root = Instance.new("Part")
	root.CFrame = CF.lookAt(V3.new(40, 3, 0), V3.new(50, 3, 0))
	local pa, pb, pc = Combat.ImpactPoint(row, root, "A"), Combat.ImpactPoint(row, root, "B"), Combat.ImpactPoint(row, root, "C")
	check(pa.Z < pc.Z and pb.Z > pc.Z and math.abs(pa.Z - pc.Z) <= 1 and math.abs(pb.Z - pc.Z) <= 1 and pa.X == pc.X and pb.X == pc.X, string.format("K18. impacto: A à esquerda (%.1f), C no centro (%.1f), B à direita (%.1f), sempre na face", pa.Z, pc.Z, pb.Z))
	check(Combat.ImpactPoint(row, root, nil) == pc, "K18. sem golpe conhecido: ponto de contato normal")

	-- K11: respawn → A.
	frames(1.5)
	Slash.Play()
	frames(0.3)
	Slash.Play()
	frames(0.1)
	local fresh = newCharacter("Local")
	fresh.Parent = nil
	respawnAs(fresh)
	mark = #swings
	Slash.Play()
	frames(0.3)
	check(seqOf(swings, mark + 1) == "A", "K11/K14. respawn (R15): o combo recomeça no A")

	Swing.Swing = originalSwing
	Combat.OnSwingImpact = originalImpactK
end

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
check(processBody and not string.find(processBody, "SwingSeq", 1, true) and not string.find(processBody, "signalSwing", 1, true), "6. o sinal do golpe fica fora do cálculo do clique (processClick não muda)")
check(string.find(clickSource, "local interval = 1 / EconomyConfig.AutoClick.TicksPerSecond", 1, true) ~= nil, "K9. ritmo do Auto Click no servidor continua o mesmo (TicksPerSecond)")
-- K8: o C não dá nada a mais: nenhuma parte do combo conhece dano/Power.
local comboClean = true
for _, path in { "src/client/Controllers/SlashController.luau", "src/client/Effects/SwordTrail.luau", "src/client/Effects/CutFx.luau" } do
	local source = fs.readFile(E.Root .. "/" .. path)
	for _, word in { "PowerFormula", "FireServer", "Invoke(", "Damage", "PerClick" } do
		if string.find(source, word, 1, true) then
			comboClean = false
			print("      " .. path .. " usa " .. word)
		end
	end
end
local combat = fs.readFile(E.Root .. "/src/client/Controllers/CombatFxController.luau")
local impactBody = string.match(combat, "function CombatFxController.OnSwingImpact.-\nend\n")
check(comboClean and impactBody and not string.find(impactBody, "FireServer", 1, true), "K8. o combo é só visual: o C não muda dano, Power nem manda nada ao servidor")

if #problems > 0 then
	print(#problems .. " problema(s).")
	process.exit(1)
end
print("OK: golpe da espada a cada hit, sincronizado com o corte, sem acumular nada.")
print("REQUER VALIDAÇÃO NO ROBLOX STUDIO: a pose real sobre o Animator, leitura em 3a pessoa e o rastro da lâmina.")
process.exit(0)
