--!strict
--[[
	SwordSwing
	O braço da espada, PROCEDURAL e local, em duas camadas por cima do que o
	Animator do Roblox já toca (andar, pular, "toolnone"):

	- POSTURA DE COMBATE (parado com a espada): corpo solto, espada baixa e um
	  pouco para o lado (nunca vertical, nunca atravessando o corpo), braço
	  esquerdo levemente afastado, tronco levemente assimétrico e a cabeça
	  olhando para frente; com uma respiração bem sutil (tronco, ombros, peso).
	  Andando/correndo/pulando a postura vira "carregar": o braço da espada
	  continua afastado das pernas e o resto do corpo fica com a locomoção.
	- GOLPE (prioridade sobre a postura): PREPARAÇÃO → CORTE → IMPACTO →
	  RETORNO, partindo da pose em que o braço estava e terminando na postura.
	  Em COMBO VISUAL de 3: A (diagonal direita→esquerda), B (esquerda→direita,
	  espelho) e C (vertical, o "PÁ" mais marcado), sempre A→B→C→A...; volta
	  para A depois de COMBO_RESET sem golpes, no respawn e na troca de
	  espada. É só a ordem dos MOVIMENTOS: o C não dá dano nem Power a mais
	  (este módulo nem conhece dano).

	Por que procedural e não AnimationTrack:
	- a espada é uma Tool com ManualActivationOnly (clicar é a entrada do jogo),
	  então o "toolslash" padrão nunca toca — e um track de 0,3–0,5 s
	  reiniciado 9 vezes por segundo quebra e acumula;
	- aqui não existe track nenhum: cada quadro só calcula uma pose, e um golpe
	  novo no meio do anterior continua da pose atual (sem tranco).

	Como mexe no corpo: veja "Rig" abaixo — a pose é SOMADA por cima do que o
	Animator escreveu no quadro (camada "Transform", depois do Animator), na
	articulação que o Roblox realmente usa (AnimationConstraint do Avatar
	Joint Upgrade, ou Motor6D). Grip, Tool e skin não são tocados — toda espada usa o mesmo golpe; só o COMPRIMENTO da lâmina
	ergue um pouco a ponta das espadas grandes (para não tocar o chão). Sem
	espada, o C0 volta EXATAMENTE ao original. Pernas não entram.

	Puro na parte das poses; o rig só aplica.
]]

-- graus (X, Y, Z) somados a cada articulação; L* = braço esquerdo.
export type Pose = {
	Shoulder: Vector3,
	Elbow: Vector3,
	Wrist: Vector3,
	Waist: Vector3,
	Neck: Vector3,
	LShoulder: Vector3,
	LElbow: Vector3,
}
export type Variant = "A" | "B" | "C" | "T" -- T = teste mínimo (SwordDebug)

local SwordSwing = {}

-- Duração do golpe: curto quando o jogador está batendo rápido, um pouco mais
-- cheio quando é um golpe isolado.
SwordSwing.FAST_SECONDS = 0.12
-- Golpe isolado: tempo para ler o movimento (A, B e C precisam ser
-- reconhecíveis). No spam, o golpe seguinte interrompe este no meio.
SwordSwing.SLOW_SECONDS = 0.24
-- Teste mínimo (SwordDebug): o braço sobe isto e volta, neste tempo.
SwordSwing.MINIMAL_SECONDS = 0.2
SwordSwing.MINIMAL_DEGREES = 110
SwordSwing.FAST_INTERVAL = 0.2 -- golpes a menos que isso um do outro = "rápido"
-- Fração do golpe em que a lâmina passa pelo meio do corte (o impacto): é
-- aqui que o corte (CutFx) e o arco aparecem.
SwordSwing.IMPACT = 0.4
-- Sem golpe por tanto tempo, o combo visual recomeça no A.
SwordSwing.COMBO_RESET = 1.2
local ORDER: { Variant } = { "A", "B", "C" }

local ZERO = Vector3.zero
local KEYS = { "Shoulder", "Elbow", "Wrist", "Waist", "Neck", "LShoulder", "LElbow" }
local NEUTRAL: Pose = { Shoulder = ZERO, Elbow = ZERO, Wrist = ZERO, Waist = ZERO, Neck = ZERO, LShoulder = ZERO, LElbow = ZERO }

--[[
	Ângulos no espaço do tronco (graus). Ombro: +X leva a mão para FRENTE/cima,
	+Y leva o braço para a esquerda (através do corpo), +Z abre o braço
	direito para fora (no esquerdo, -Z abre). Cintura: -X inclina o tronco
	para frente, +Y gira o peito para a esquerda. Os ângulos somam por cima
	do "toolnone" do Roblox (braço direito esticado à frente, espada em pé).
	Windup = preparação; Strike = fim do corte (o impacto fica no caminho).
	Articulação que o golpe não cita fica na postura do momento.
]]
local SHAPES: { [Variant]: { Windup: { [string]: Vector3 }, Strike: { [string]: Vector3 } } } = {
	-- A: diagonal de cima/direita para baixo/esquerda. O tronco gira junto e
	-- o braço esquerdo recua para equilibrar.
	A = {
		Windup = {
			Shoulder = Vector3.new(55, -30, -25), Elbow = Vector3.new(25, 0, 0), Wrist = Vector3.new(15, 0, 0),
			Waist = Vector3.new(2, -10, 0), LShoulder = Vector3.new(10, 0, -14), LElbow = Vector3.new(25, 0, 0),
		},
		Strike = {
			Shoulder = Vector3.new(-35, 40, 20), Elbow = Vector3.new(5, 0, 0), Wrist = Vector3.new(-40, 0, 0),
			Waist = Vector3.new(-3, 12, 0), LShoulder = Vector3.new(-12, 0, -20), LElbow = Vector3.new(18, 0, 0),
		},
	},
	-- B: diagonal de cima/esquerda para baixo/direita (o espelho do A).
	B = {
		Windup = {
			Shoulder = Vector3.new(50, 30, 25), Elbow = Vector3.new(30, 0, 0), Wrist = Vector3.new(15, 0, 0),
			Waist = Vector3.new(2, 10, 0), LShoulder = Vector3.new(-8, 0, -18), LElbow = Vector3.new(18, 0, 0),
		},
		Strike = {
			Shoulder = Vector3.new(-35, -35, -20), Elbow = Vector3.new(5, 0, 0), Wrist = Vector3.new(-40, 0, 0),
			Waist = Vector3.new(-3, -12, 0), LShoulder = Vector3.new(12, 0, -10), LElbow = Vector3.new(25, 0, 0),
		},
	},
	-- C: de cima para baixo, o fecho do combo: preparação mais alta, o tronco
	-- recua e desce junto com a lâmina, os dois braços entram.
	C = {
		Windup = {
			Shoulder = Vector3.new(85, 0, 5), Elbow = Vector3.new(40, 0, 0), Wrist = Vector3.new(25, 0, 0),
			Waist = Vector3.new(6, 0, 0), LShoulder = Vector3.new(20, 0, -12), LElbow = Vector3.new(30, 0, 0),
		},
		Strike = {
			-- punho -40: a lâmina termina à frente, na horizontal (a do Colosso não chega ao chão)
			Shoulder = Vector3.new(-50, 5, 5), Elbow = Vector3.new(0, 0, 0), Wrist = Vector3.new(-40, 0, 0),
			Waist = Vector3.new(-8, 0, 0), LShoulder = Vector3.new(-15, 0, -18), LElbow = Vector3.new(15, 0, 0),
		},
	},
}

-- Quanto do tempo vai em cada fase.
local WINDUP_END = 0.25
local STRIKE_END = 0.55

local function lerpPose(a: Pose, b: Pose, t: number): Pose
	local out = {}
	for _, key in KEYS do
		out[key] = (a :: any)[key]:Lerp((b :: any)[key], t)
	end
	return out :: any
end

-- Uma pose do golpe completada pela postura (o que o golpe não cita).
local function fill(partial: { [string]: Vector3 }, rest: Pose): Pose
	local out = {}
	for _, key in KEYS do
		out[key] = partial[key] or (rest :: any)[key]
	end
	return out :: any
end

local function easeOut(t: number): number
	return 1 - (1 - t) * (1 - t)
end
local function easeInOut(t: number): number
	return if t < 0.5 then 2 * t * t else 1 - (-2 * t + 2) ^ 2 / 2
end

function SwordSwing.Neutral(): Pose
	return NEUTRAL
end

function SwordSwing.Keys(): { string }
	return KEYS
end

-- ── Postura de combate ─────────────────────────────────────────────────────
--[[
	A inclinação da espada é medida no plano do corpo, em graus a partir de
	"apontando para o chão" (90 = horizontal à frente, 180 = em pé). No
	"toolnone" o braço está a 90 e a espada a 180; ombro, cotovelo e punho
	somam: espada = 180 + ombro.X + cotovelo.X + punho.X. A postura escolhe a
	inclinação da ESPADA e o punho fecha a conta (sem punho, como no R6, quem
	fecha é o ombro).
]]
SwordSwing.STANCE = {
	SwordPitch = 84, -- espada baixa, um pouco abaixo da horizontal
	Shoulder = Vector3.new(-80, -14, 12), -- braço solto, um pouco aberto; espada para o lado
	Elbow = 15,
	LShoulder = Vector3.new(4, 0, -10), -- braço esquerdo levemente afastado
	LElbow = Vector3.new(14, 0, 0),
	Waist = Vector3.new(-3, -6, 0), -- leve inclinação à frente, lado da espada um pouco atrás
}
-- Andando/correndo/pulando: a espada um pouco mais alta, longe das pernas.
SwordSwing.CARRY = {
	SwordPitch = 112,
	Shoulder = Vector3.new(-62, -10, 14),
	Elbow = 18,
}
-- Lâminas maiores sobem a ponta (graus por stud acima da inicial, com teto).
SwordSwing.BASE_BLADE = 4.2
SwordSwing.LIFT_PER_STUD = 4
SwordSwing.LIFT_MAX = 10
-- Sem punho (R6) a espada sobe junto com o braço: um pouco mais alta.
SwordSwing.NO_WRIST_LIFT = 12

-- Respiração (bem sutil): amplitude em graus e período em segundos.
local BREATH_SECONDS = 3.6
local SHIFT_SECONDS = 6.2
local BREATH_WAIST = 1.2
local BREATH_SHOULDER = 1.5
local BREATH_LEFT = 1
local SHIFT_WAIST = 0.8

type Holding = { SwordPitch: number, Shoulder: Vector3, Elbow: number }

local function hold(spec: Holding, bladeLength: number, hasElbow: boolean, hasWrist: boolean): (Vector3, Vector3, Vector3)
	local pitch = spec.SwordPitch
		+ math.clamp((bladeLength - SwordSwing.BASE_BLADE) * SwordSwing.LIFT_PER_STUD, 0, SwordSwing.LIFT_MAX)
	local elbow = if hasElbow then spec.Elbow else 0
	local shoulder = spec.Shoulder
	local wrist = 0
	if hasWrist then
		wrist = pitch - (180 + shoulder.X + elbow)
	else
		shoulder = Vector3.new(pitch + SwordSwing.NO_WRIST_LIFT - 180 - elbow, shoulder.Y, shoulder.Z)
	end
	return shoulder, Vector3.new(elbow, 0, 0), Vector3.new(wrist, 0, 0)
end

-- Inclinação da espada (ver acima) que uma pose produz. Para os testes.
function SwordSwing.SwordPitch(pose: Pose): number
	return 180 + pose.Shoulder.X + pose.Elbow.X + pose.Wrist.X
end

-- Postura parada (sem respiração).
function SwordSwing.Stance(bladeLength: number, hasElbow: boolean, hasWrist: boolean): Pose
	local spec = SwordSwing.STANCE
	local shoulder, elbow, wrist = hold(spec, bladeLength, hasElbow, hasWrist)
	return {
		Shoulder = shoulder,
		Elbow = elbow,
		Wrist = wrist,
		Waist = spec.Waist,
		Neck = Vector3.new(0, -spec.Waist.Y, 0), -- a cabeça continua olhando para frente
		LShoulder = spec.LShoulder,
		LElbow = spec.LElbow,
	}
end

-- Em movimento: só o braço da espada; tronco e braço esquerdo ficam com a
-- locomoção do Roblox.
function SwordSwing.Carry(bladeLength: number, hasElbow: boolean, hasWrist: boolean): Pose
	local shoulder, elbow, wrist = hold(SwordSwing.CARRY, bladeLength, hasElbow, hasWrist)
	return { Shoulder = shoulder, Elbow = elbow, Wrist = wrist, Waist = ZERO, Neck = ZERO, LShoulder = ZERO, LElbow = ZERO }
end

-- A respiração somada à postura no instante `time` (amount 0..1).
function SwordSwing.Breathe(pose: Pose, time: number, amount: number): Pose
	if amount <= 0 then
		return pose
	end
	local breath = math.sin(time * 2 * math.pi / BREATH_SECONDS) * amount
	local lifted = math.sin(time * 2 * math.pi / BREATH_SECONDS + 0.6) * amount
	local shift = math.sin(time * 2 * math.pi / SHIFT_SECONDS) * amount
	return {
		Shoulder = pose.Shoulder + Vector3.new(lifted * BREATH_SHOULDER, 0, 0),
		Elbow = pose.Elbow,
		Wrist = pose.Wrist,
		Waist = pose.Waist + Vector3.new(breath * BREATH_WAIST, 0, shift * SHIFT_WAIST),
		Neck = pose.Neck + Vector3.new(-breath * BREATH_WAIST, 0, -shift * SHIFT_WAIST),
		LShoulder = pose.LShoulder + Vector3.new(lifted * BREATH_LEFT, 0, 0),
		LElbow = pose.LElbow,
	}
end

function SwordSwing.Lerp(a: Pose, b: Pose, t: number): Pose
	return lerpPose(a, b, t)
end

-- A variação do golpe número `count` do combo (1, 2, 3...): A, B, C, A, B, C...
function SwordSwing.VariantFor(count: number): Variant
	return ORDER[(math.max(count, 1) - 1) % #ORDER + 1]
end

-- O golpe que fecha o combo (só o visual fica um pouco mais marcado).
function SwordSwing.IsFinisher(variant: Variant?): boolean
	return variant == "C"
end

-- Duração do golpe dado o intervalo desde o anterior.
function SwordSwing.DurationFor(sinceLast: number): number
	return if sinceLast < SwordSwing.FAST_INTERVAL then SwordSwing.FAST_SECONDS else SwordSwing.SLOW_SECONDS
end

--[[
	Pose do golpe `variant` na fração `t` (0..1), partindo de `from` (a pose em
	que o corpo estava quando o golpe começou: a postura, ou o meio do golpe
	anterior) e voltando para `rest` (a postura do momento). t >= 1 = rest.
]]
function SwordSwing.Pose(variant: Variant, t: number, from: Pose?, rest: Pose?): Pose
	local home = rest or NEUTRAL
	local start = from or home
	if t <= 0 then
		return start
	elseif t >= 1 then
		return home
	end
	if variant == "T" then
		-- Teste mínimo: só o ombro, sobe e volta (seno), nada mais.
		local out = table.clone(home) :: any
		out.Shoulder = home.Shoulder + Vector3.new(SwordSwing.MINIMAL_DEGREES * math.sin(math.pi * t), 0, 0)
		return out
	end
	local shape = SHAPES[variant]
	local windup = fill(shape.Windup, home)
	if t < WINDUP_END then
		return lerpPose(start, windup, easeOut(t / WINDUP_END))
	end
	local strike = fill(shape.Strike, home)
	if t < STRIKE_END then
		return lerpPose(windup, strike, easeOut((t - WINDUP_END) / (STRIKE_END - WINDUP_END)))
	end
	return lerpPose(strike, home, easeInOut((t - STRIKE_END) / (1 - STRIKE_END)))
end

-- ── Rig: aplica a pose no personagem ────────────────────────────────────────
--[[
	QUAL articulação: a que o Roblox realmente usa para mover a parte.
	- Avatar Joint Upgrade (R15): AnimationConstraint ("RightShoulder"...);
	  o Motor6D antigo, se ainda existir, não move nada — por isso uma
	  AnimationConstraint ATIVA tem prioridade sobre um Motor6D;
	- R15 clássico: Motor6D (RightShoulder, RightElbow, RightWrist, Waist...);
	- R6: "Right Shoulder"/"Left Shoulder" no Torso (sem cotovelo/punho; a
	  postura fecha a conta no ombro; o pescoço fica com o Roblox).
	O personagem muda DEPOIS de nascer (aparência carregando troca partes e
	articulações, a conversão do Joint Upgrade, escala): o controller remonta
	o rig quando uma articulação some/é trocada (Valid / Rebind).

	COMO aplica (Backend):
	- "Transform" (padrão): todo quadro, DEPOIS do Animator (PreSimulation),
	  multiplica a rotação da pose no Transform que o Animator acabou de
	  escrever — o mesmo canal da animação, então nada "briga" com ele. Se o
	  Animator não reescrever o Transform num quadro, a base guardada é usada
	  (a rotação nunca acumula). Sem pose, o Transform volta ao do Animator.
	- "Offset": rotação no C0 (Motor6D) ou na Attachment0 (AnimationConstraint),
	  com a base lida AO VIVO (se o Roblox mexer nela, ex. escala, vira a base
	  nova). Fica como alternativa: o controller mede se a pose chegou às
	  partes (Measure) e troca de camada se não chegou.
	As duas dão a MESMA pose: rotação no espaço do tronco, em volta da junta.

	BRAÇO DA ESPADA É DONO DA POSE: com a espada na mão (peso rig.Own, que
	sobe/desce suave ao equipar/guardar), ombro, cotovelo e punho direitos
	ficam numa pose ABSOLUTA em relação ao tronco — a "pegada" HOLD (braço à
	frente, como o "toolnone" do Roblox) + os ângulos da postura/golpe — em
	vez de somar por cima do que o Animator tocou. Assim a postura e a
	direção de A/B/C não dependem de qual animação está tocando (toolnone,
	idle, andar, ou nenhuma). Tronco, braço esquerdo e pescoço continuam
	SOMANDO por cima do Animator (respirar, andar e pular seguem dele).
]]

type Joint = {
	Key: string,
	Target: Instance, -- Motor6D ou AnimationConstraint
	Kind: string, -- "Motor6D" | "AnimationConstraint"
	Name: string,
	-- camada Transform
	LastBase: CFrame?,
	LastWritten: CFrame?,
	-- camada Offset
	OffsetBase: CFrame?,
	OffsetWritten: CFrame?,
	-- verificação: Part0→Part1 esperado com e sem a pose, no último quadro
	PosedRel: CFrame?,
	PlainRel: CFrame?,
}
export type Rig = {
	Character: Model,
	Joints: { [string]: Joint },
	Kind: string, -- "Motor6D" | "AnimationConstraint" (a do ombro)
	Backend: string, -- "Transform" | "Offset"
	Minimal: boolean, -- teste mínimo (SwordDebug)
	HasElbow: boolean,
	HasWrist: boolean,
	-- Golpe
	Variant: Variant,
	Started: number,
	Duration: number,
	From: Pose,
	Current: Pose,
	Active: boolean,
	Count: number,
	LastAt: number,
	-- Postura
	Rest: Pose, -- para onde o corpo volta (postura/carregar/neutra, já suavizada)
	Armed: number, -- 0 sem espada .. 1 com espada (anda em ARMED_SECONDS)
	Idle: number, -- 0 andando .. 1 parado (suavizado)
	Applied: boolean, -- alguma articulação com pose
	Own: number, -- 0..1: quanto o braço da espada é dono da pose (equipar suave)
	Phase: number, -- defasagem da respiração (personagens não respiram juntos)
	Speed: number, -- velocidade do personagem (suavizada)
	Blade: Instance?, -- a lâmina na mão (trocou = combo recomeça)
	BladeLength: number, -- comprimento da lâmina (suavizado: trocar de espada não dá tranco)
	LastRoot: Vector3?,
}

local JOINTS: { [string]: { string } } = {
	Shoulder = { "RightShoulder", "Right Shoulder" },
	Elbow = { "RightElbow" },
	Wrist = { "RightWrist" },
	Waist = { "Waist" },
	Neck = { "Neck" },
	LShoulder = { "LeftShoulder", "Left Shoulder" },
	LElbow = { "LeftElbow" },
}
SwordSwing.JOINT_NAMES = JOINTS

-- Entrar/sair da postura (equipar, guardar, respawn): em tanto tempo, com
-- início e fim suaves.
local ARMED_SECONDS = 0.45
-- Suavização (por segundo): quanto maior, mais rápido chega.
local LENGTH_RATE = 8
local IDLE_RATE = 6
local SPEED_RATE = 12
-- Acima disto (studs/s) o personagem está andando; na vertical, pulando/caindo.
local MOVING_SPEED = 1.5
local AIR_SPEED = 3

local function rotation(degrees: Vector3): CFrame
	return CFrame.Angles(math.rad(degrees.X), math.rad(degrees.Y), math.rad(degrees.Z))
end

-- Ângulo (graus) entre duas orientações; pela corda, estável em float32.
function SwordSwing.Angle(a: CFrame, b: CFrame): number
	local function between(u: Vector3, v: Vector3): number
		return math.deg(2 * math.asin(math.clamp((u - v).Magnitude / 2, 0, 1)))
	end
	return math.max(between(a.RightVector, b.RightVector), between(a.UpVector, b.UpVector), between(a.LookVector, b.LookVector))
end

local function same(a: CFrame, b: CFrame): boolean
	return (a.Position - b.Position).Magnitude < 1e-4 and SwordSwing.Angle(a, b) < 0.01
end

local function enabled(item: Instance): boolean
	return (item :: any).Enabled ~= false
end

local function findJoint(character: Model, key: string, names: { string }): Joint?
	local motor: Joint? = nil
	for _, name in names do
		for _, item in character:GetDescendants() do
			if item.Name == name and enabled(item) then
				if item.ClassName == "AnimationConstraint" then
					local a0, a1 = (item :: any).Attachment0, (item :: any).Attachment1
					if a0 and a1 and a0:IsA("Attachment") and a1:IsA("Attachment") then
						return { Key = key, Target = item, Kind = "AnimationConstraint", Name = item.Name }
					end
				elseif item:IsA("Motor6D") and not motor then
					motor = { Key = key, Target = item, Kind = "Motor6D", Name = item.Name }
				end
			end
		end
	end
	return motor
end

local function findJoints(character: Model): { [string]: Joint }
	local joints: { [string]: Joint } = {}
	for key, names in JOINTS do
		local joint = findJoint(character, key, names)
		if joint then
			joints[key] = joint
		end
	end
	if not joints.Waist then
		joints.Neck = nil -- R6: o pescoço fica com o Roblox
	end
	return joints
end

-- Monta o rig (nil se o personagem não tiver ombro direito reconhecível).
function SwordSwing.NewRig(character: Model): Rig?
	local joints = findJoints(character)
	local shoulder = joints.Shoulder
	if not shoulder then
		return nil
	end
	return {
		Character = character,
		Joints = joints,
		Kind = shoulder.Kind,
		Backend = "Transform",
		Minimal = false,
		HasElbow = joints.Elbow ~= nil,
		HasWrist = joints.Wrist ~= nil,
		Variant = "A",
		Started = 0,
		Duration = SwordSwing.SLOW_SECONDS,
		From = NEUTRAL,
		Current = NEUTRAL,
		Active = false,
		Count = 0,
		LastAt = -math.huge,
		Rest = NEUTRAL,
		Armed = 0,
		Idle = 1,
		Applied = false,
		Own = 0,
		Phase = (#character.Name * 0.77) % BREATH_SECONDS,
		Speed = 0,
		Blade = nil,
		BladeLength = SwordSwing.BASE_BLADE,
		LastRoot = nil,
	}
end

-- A pose de uma articulação: rotação no espaço do tronco, mantendo a posição.
function SwordSwing.Posed(base: CFrame, degrees: Vector3): CFrame
	if degrees == ZERO then
		return base
	end
	return CFrame.new(base.Position) * rotation(degrees) * (base - base.Position)
end

-- Onde a junta fica em Part0 (C0 / Attachment0) e em Part1 (C1 / Attachment1).
local function frames(joint: Joint): (CFrame, CFrame)
	local target = joint.Target :: any
	if joint.Kind == "Motor6D" then
		return target.C0, target.C1
	end
	return target.Attachment0.CFrame, target.Attachment1.CFrame
end

local function parts(joint: Joint): (BasePart?, BasePart?)
	local target = joint.Target :: any
	if joint.Kind == "Motor6D" then
		return target.Part0, target.Part1
	end
	local a0, a1 = target.Attachment0, target.Attachment1
	return if a0 then a0.Parent else nil, if a1 then a1.Parent else nil
end

-- Onde a camada Offset escreve.
local function offsetSlot(joint: Joint): (Instance, string)
	local target = joint.Target :: any
	if joint.Kind == "Motor6D" then
		return target, "C0"
	end
	return target.Attachment0, "CFrame"
end

-- Articulações do braço da espada (donas da pose com a espada na mão) e a
-- "pegada" base delas, no espaço do tronco: braço à frente, reto.
local HOLD: { [string]: CFrame } = {
	Shoulder = CFrame.Angles(math.rad(90), 0, 0),
	Elbow = CFrame.identity,
	Wrist = CFrame.identity,
}
SwordSwing.HOLD = HOLD

--[[
	Onde a junta deve ficar (Part0 → junta, já com a pose), dado onde ela fica
	em Part0 (f0) e o Transform do Animator (anim). Somada: rotação no espaço
	do tronco por cima da animação. Dona (peso own): pegada + pose, sem a
	animação.
]]
local function target(joint: Joint, f0: CFrame, anim: CFrame, degrees: Vector3, own: number): CFrame
	local frame = f0 - f0.Position
	local turn = rotation(degrees)
	local added = CFrame.new(f0.Position) * turn * frame * anim
	local hold = HOLD[joint.Key]
	if not hold or own <= 0 then
		return added
	end
	local owned = CFrame.new(f0.Position) * turn * hold * frame
	return if own >= 1 then owned else added:Lerp(owned, own)
end

-- Para os testes: onde a junta `key` deve ficar.
function SwordSwing.Target(key: string, f0: CFrame, anim: CFrame, degrees: Vector3, own: number): CFrame
	return target({ Key = key } :: any, f0, anim, degrees, own)
end

local function posing(joint: Joint, degrees: Vector3, own: number): boolean
	return degrees ~= ZERO or (own > 0 and HOLD[joint.Key] ~= nil)
end

local function applyTransform(joint: Joint, degrees: Vector3, own: number)
	local target_ = joint.Target :: any
	local current: CFrame = target_.Transform
	-- O Animator não reescreveu desde o último quadro: a base é a guardada.
	local written = joint.LastWritten
	local base = if written and joint.LastBase and same(current, written) then joint.LastBase :: CFrame else current
	if not posing(joint, degrees, own) then
		if written then
			target_.Transform = base
		end
		joint.LastWritten, joint.LastBase, joint.PosedRel, joint.PlainRel = nil, nil, nil, nil
		return
	end
	local f0, f1 = frames(joint)
	local wanted = target(joint, f0, base, degrees, own)
	local posed = f0:Inverse() * wanted
	target_.Transform = posed
	joint.LastWritten, joint.LastBase = posed, base
	joint.PosedRel = wanted * f1:Inverse()
	joint.PlainRel = f0 * base * f1:Inverse()
end

local function applyOffset(joint: Joint, degrees: Vector3, own: number)
	local slot, property = offsetSlot(joint)
	local current: CFrame = (slot :: any)[property]
	-- Base ao vivo: se alguém mudou (escala, aparência), essa é a nova base.
	local written = joint.OffsetWritten
	local base = if written and joint.OffsetBase and same(current, written) then joint.OffsetBase :: CFrame else current
	if not posing(joint, degrees, own) then
		if written then
			(slot :: any)[property] = base
		end
		joint.OffsetWritten, joint.OffsetBase, joint.PosedRel, joint.PlainRel = nil, nil, nil, nil
		return
	end
	local _, f1 = frames(joint)
	local ok, transform = pcall(function()
		return (joint.Target :: any).Transform
	end)
	local anim = if ok and typeof(transform) == "CFrame" then transform else CFrame.identity
	local wanted = target(joint, base, anim, degrees, own)
	-- O Transform do Animator vem depois deste: desconta para cair em `wanted`.
	local posed = wanted * anim:Inverse();
	(slot :: any)[property] = posed
	joint.OffsetWritten, joint.OffsetBase = posed, base
	joint.PosedRel = wanted * f1:Inverse()
	joint.PlainRel = base * anim * f1:Inverse()
end

local function alive(rig: Rig, joint: Joint): boolean
	local target = joint.Target
	if not target.Parent or not target:IsDescendantOf(rig.Character) or not enabled(target) then
		return false
	end
	local p0, p1 = parts(joint)
	return p0 ~= nil and p1 ~= nil and p0.Parent ~= nil and p1.Parent ~= nil
end

local function apply(rig: Rig, pose: Pose)
	rig.Current = pose
	local applied = false
	local own = rig.Own
	for key, joint in rig.Joints do
		local degrees = (pose :: any)[key] :: Vector3
		if posing(joint, degrees, own) then
			applied = true
		end
		if alive(rig, joint) then
			if rig.Backend == "Offset" then
				applyOffset(joint, degrees, own)
			else
				applyTransform(joint, degrees, own)
			end
		end
	end
	rig.Applied = applied
end

-- Todas as articulações do rig ainda são as que o Roblox usa?
function SwordSwing.Valid(rig: Rig): boolean
	for _, joint in rig.Joints do
		if not alive(rig, joint) then
			return false
		end
	end
	return true
end

--[[
	Remonta as articulações do mesmo personagem (aparência carregada,
	Joint Upgrade convertendo, partes trocadas), mantendo golpe/postura/combo.
	Devolve se algo mudou.
]]
function SwordSwing.Rebind(rig: Rig): boolean
	local fresh = findJoints(rig.Character)
	local changed = false
	for key, joint in rig.Joints do
		if not fresh[key] or fresh[key].Target ~= joint.Target then
			changed = true
		end
	end
	for key in fresh do
		if not rig.Joints[key] then
			changed = true
		end
	end
	if not changed then
		return false
	end
	local current, own = rig.Current, rig.Own
	rig.Own = 0
	apply(rig, NEUTRAL) -- devolve o que dá nas antigas
	rig.Own = own
	rig.Joints = fresh
	if fresh.Shoulder then
		rig.Kind = fresh.Shoulder.Kind
	end
	rig.HasElbow = fresh.Elbow ~= nil
	rig.HasWrist = fresh.Wrist ~= nil
	rig.Current = current
	return true
end

-- Troca a camada que aplica a pose (devolve tudo pela camada antiga antes).
function SwordSwing.SetBackend(rig: Rig, backend: string)
	if rig.Backend == backend then
		return
	end
	local current, own = rig.Current, rig.Own
	rig.Own = 0
	apply(rig, NEUTRAL)
	rig.Own = own
	rig.Backend = backend
	rig.Current = current
end

--[[
	A pose CHEGOU às partes? Mede o braço de verdade (Part1 em relação a
	Part0, depois da física) e compara com o esperado com e sem a pose do
	último quadro. Devolve (tamanho da pose em graus, distância até o
	esperado COM a pose, distância até o esperado SEM a pose), ou nil sem
	pose no ombro.
]]
function SwordSwing.Measure(rig: Rig): (number?, number?, number?)
	local joint = rig.Joints.Shoulder
	if not joint or not joint.PosedRel or not joint.PlainRel then
		return nil, nil, nil
	end
	local p0, p1 = parts(joint)
	if not p0 or not p1 then
		return nil, nil, nil
	end
	local actual = p0.CFrame:ToObjectSpace(p1.CFrame)
	local posed, plain = joint.PosedRel :: CFrame, joint.PlainRel :: CFrame
	return SwordSwing.Angle(posed, plain), SwordSwing.Angle(actual, posed), SwordSwing.Angle(actual, plain)
end

-- Texto curto das articulações (para o log de diagnóstico).
function SwordSwing.Describe(rig: Rig): { string }
	local lines = {}
	for _, key in KEYS do
		local joint = rig.Joints[key]
		if joint then
			local p0, p1 = parts(joint)
			table.insert(lines, string.format("%s = %s (%s, %s -> %s)", key, joint.Name, joint.Kind, if p0 then p0.Name else "?", if p1 then p1.Name else "?"))
		else
			table.insert(lines, key .. " = (não encontrada)")
		end
	end
	return lines
end

local function approach(current: number, target: number, rate: number, dt: number): number
	return current + (target - current) * (1 - math.exp(-rate * dt))
end

--[[
	Movimento do personagem a partir da posição da raiz neste quadro: devolve
	se ele está andando/correndo/pulando. Um salto de posição grande demais
	(teleporte, respawn) não conta como correr.
]]
function SwordSwing.Track(rig: Rig, rootPosition: Vector3?, dt: number): boolean
	local last = rig.LastRoot
	rig.LastRoot = rootPosition
	if rootPosition and last and dt > 0 then
		local delta = rootPosition - last
		if delta.Magnitude < 20 then
			local horizontal = Vector3.new(delta.X, 0, delta.Z).Magnitude / dt
			local vertical = math.abs(delta.Y) / dt
			local speed = math.max(horizontal, vertical * MOVING_SPEED / AIR_SPEED)
			rig.Speed = approach(rig.Speed, speed, SPEED_RATE, dt)
		end
	end
	return rig.Speed > MOVING_SPEED
end

--[[
	Atualiza a postura para onde o corpo volta. `armed` = tem espada na mão;
	`moving` = andando/pulando; `bladeLength` = comprimento da lâmina. Tudo
	suavizado: entrar/sair da postura, parar/andar e trocar de espada nunca dão
	tranco. Sem espada, a postura vira EXATAMENTE a neutra (e o comprimento
	da última lâmina fica, para guardar a espada sem mexer o punho).
]]
function SwordSwing.Settle(rig: Rig, time: number, dt: number, armed: boolean, moving: boolean, bladeLength: number)
	if armed then
		rig.BladeLength = if rig.Armed <= 0 then bladeLength else approach(rig.BladeLength, bladeLength, LENGTH_RATE, dt)
	end
	local step = dt / ARMED_SECONDS
	rig.Armed = if armed then math.min(rig.Armed + step, 1) else math.max(rig.Armed - step, 0)
	rig.Idle = approach(rig.Idle, if moving then 0 else 1, IDLE_RATE, dt)
	if rig.Armed <= 0 then
		rig.Rest = NEUTRAL
		rig.Own = 0
		return
	end
	local length = rig.BladeLength
	local stance = SwordSwing.Breathe(SwordSwing.Stance(length, rig.HasElbow, rig.HasWrist), time + rig.Phase, rig.Idle)
	local carry = SwordSwing.Carry(length, rig.HasElbow, rig.HasWrist)
	local weight = rig.Armed * rig.Armed * (3 - 2 * rig.Armed)
	rig.Own = weight
	rig.Rest = lerpPose(NEUTRAL, lerpPose(carry, stance, rig.Idle), weight)
end

--[[
	Começa um golpe agora. Devolve (variação, segundos até o impacto). Um golpe
	no meio do anterior parte da pose atual: nunca há dois golpes ao mesmo tempo.
	No teste mínimo (rig.Minimal) é sempre o "T": o braço sobe e volta.
]]
function SwordSwing.Start(rig: Rig, now: number): (Variant, number)
	if now - rig.LastAt > SwordSwing.COMBO_RESET then
		rig.Count = 0
	end
	rig.Count += 1
	local duration = SwordSwing.DurationFor(now - rig.LastAt)
	rig.LastAt = now
	rig.Variant = SwordSwing.VariantFor(rig.Count)
	if rig.Minimal then
		rig.Variant = "T"
		duration = SwordSwing.MINIMAL_SECONDS
	end
	rig.From = rig.Current
	rig.Started = now
	rig.Duration = duration
	rig.Active = true
	return rig.Variant, duration * SwordSwing.IMPACT
end

--[[
	Um quadro (DEPOIS do Animator): o golpe (se houver) tem prioridade; fora
	dele, a postura. Devolve se o golpe ainda está em movimento. Sem espada e
	já sem pose, não escreve nada (custo zero).
]]
function SwordSwing.Step(rig: Rig, now: number): boolean
	if rig.Active then
		local t = (now - rig.Started) / rig.Duration
		if t < 1 then
			apply(rig, SwordSwing.Pose(rig.Variant, t, rig.From, rig.Rest))
			return true
		end
		rig.Active = false
		apply(rig, rig.Rest)
		return false
	end
	if rig.Armed > 0 or rig.Applied then
		apply(rig, rig.Rest)
	end
	return false
end

-- O combo visual recomeça no A (troca de espada).
function SwordSwing.ResetCombo(rig: Rig)
	rig.Count = 0
end

-- Devolve tudo ao original (personagem saindo, morrendo, sendo trocado).
function SwordSwing.Reset(rig: Rig)
	rig.Active = false
	rig.Armed = 0
	rig.Own = 0
	rig.Rest = NEUTRAL
	apply(rig, NEUTRAL)
end

return SwordSwing
