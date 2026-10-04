--!strict
--[[
	SwordSwing
	O golpe da espada, PROCEDURAL e local: o braço direito (ombro, cotovelo e
	punho) e um pouco do tronco fazem PREPARAÇÃO → CORTE → IMPACTO → RETORNO
	por cima da pose de "segurar arma" que o Animator do Roblox já toca.

	Por que procedural e não AnimationTrack:
	- a espada é uma Tool com ManualActivationOnly (clicar é a entrada do jogo),
	  então o "toolslash" padrão nunca toca — e um track de 0,3–0,5 s
	  reiniciado 9 vezes por segundo quebra e acumula;
	- aqui não existe track nenhum: cada golpe só troca o alvo de uma curva, e
	  um golpe novo no meio do anterior continua da pose atual (sem tranco).

	Como mexe no corpo: soma uma rotação ao C0 dos Motor6D do R15 (a pose do
	Animator vai no Transform, que continua intacto). Grip, Tool e skin não
	são tocados — por isso toda espada usa o mesmo golpe. Ao parar, o C0 volta
	EXATAMENTE ao original. Pernas não entram: andar/correr continua igual.

	Puro na parte da curva (Pose); o rig só aplica.
]]

export type Pose = { Shoulder: Vector3, Elbow: Vector3, Wrist: Vector3, Waist: Vector3 } -- graus (X, Y, Z)
export type Variant = "A" | "B" | "C"

local SwordSwing = {}

-- Duração do golpe: curto quando o jogador está batendo rápido, um pouco mais
-- cheio quando é um golpe isolado.
SwordSwing.FAST_SECONDS = 0.12
SwordSwing.SLOW_SECONDS = 0.16
SwordSwing.FAST_INTERVAL = 0.2 -- golpes a menos que isso um do outro = "rápido"
-- Fração do golpe em que a lâmina passa pelo meio do corte (o impacto): é
-- aqui que o corte (CutFx) e o arco aparecem.
SwordSwing.IMPACT = 0.4
-- A terceira variação (de cima para baixo) entra a cada tantos golpes.
SwordSwing.OVERHEAD_EVERY = 7

local ZERO = Vector3.zero
local NEUTRAL: Pose = { Shoulder = ZERO, Elbow = ZERO, Wrist = ZERO, Waist = ZERO }

--[[
	Ângulos no espaço da articulação (graus). Ombro: +X ergue o braço que está à
	frente, +Y leva para a esquerda (através do corpo), Z inclina o plano da
	lâmina. Waist = um giro curto do tronco (nunca o personagem inteiro).
	Windup = preparação; Strike = fim do corte (o impacto fica no caminho).
]]
local SHAPES: { [Variant]: { Windup: Pose, Strike: Pose } } = {
	-- A: diagonal de cima/direita para baixo/esquerda.
	A = {
		Windup = { Shoulder = Vector3.new(55, -30, -25), Elbow = Vector3.new(25, 0, 0), Wrist = Vector3.new(15, 0, 0), Waist = Vector3.new(0, -8, 0) },
		Strike = { Shoulder = Vector3.new(-35, 40, 20), Elbow = Vector3.new(0, 0, 0), Wrist = Vector3.new(-20, 0, 0), Waist = Vector3.new(0, 10, 0) },
	},
	-- B: diagonal de cima/esquerda para baixo/direita (volta do A).
	B = {
		Windup = { Shoulder = Vector3.new(50, 30, 25), Elbow = Vector3.new(30, 0, 0), Wrist = Vector3.new(15, 0, 0), Waist = Vector3.new(0, 8, 0) },
		Strike = { Shoulder = Vector3.new(-35, -35, -20), Elbow = Vector3.new(0, 0, 0), Wrist = Vector3.new(-20, 0, 0), Waist = Vector3.new(0, -10, 0) },
	},
	-- C: de cima para baixo, ocasional.
	C = {
		Windup = { Shoulder = Vector3.new(75, 0, 0), Elbow = Vector3.new(30, 0, 0), Wrist = Vector3.new(20, 0, 0), Waist = Vector3.new(-4, 0, 0) },
		Strike = { Shoulder = Vector3.new(-45, 5, 0), Elbow = Vector3.new(0, 0, 0), Wrist = Vector3.new(-25, 0, 0), Waist = Vector3.new(6, 0, 0) },
	},
}

-- Quanto do tempo vai em cada fase.
local WINDUP_END = 0.25
local STRIKE_END = 0.55

local function lerpPose(a: Pose, b: Pose, t: number): Pose
	return {
		Shoulder = a.Shoulder:Lerp(b.Shoulder, t),
		Elbow = a.Elbow:Lerp(b.Elbow, t),
		Wrist = a.Wrist:Lerp(b.Wrist, t),
		Waist = a.Waist:Lerp(b.Waist, t),
	}
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

-- A variação do golpe número `count` (1, 2, 3...): A, B, A, B... e um C de vez em quando.
function SwordSwing.VariantFor(count: number): Variant
	if count % SwordSwing.OVERHEAD_EVERY == 0 then
		return "C"
	end
	return if count % 2 == 1 then "A" else "B"
end

-- Duração do golpe dado o intervalo desde o anterior.
function SwordSwing.DurationFor(sinceLast: number): number
	return if sinceLast < SwordSwing.FAST_INTERVAL then SwordSwing.FAST_SECONDS else SwordSwing.SLOW_SECONDS
end

--[[
	Pose do golpe `variant` na fração `t` (0..1), partindo de `from` (a pose em
	que o braço estava quando o golpe começou: neutra, ou o meio do golpe
	anterior). t >= 1 = neutra.
]]
function SwordSwing.Pose(variant: Variant, t: number, from: Pose?): Pose
	local shape = SHAPES[variant]
	local start = from or NEUTRAL
	if t <= 0 then
		return start
	elseif t < WINDUP_END then
		return lerpPose(start, shape.Windup, easeOut(t / WINDUP_END))
	elseif t < STRIKE_END then
		return lerpPose(shape.Windup, shape.Strike, easeOut((t - WINDUP_END) / (STRIKE_END - WINDUP_END)))
	elseif t < 1 then
		return lerpPose(shape.Strike, NEUTRAL, easeInOut((t - STRIKE_END) / (1 - STRIKE_END)))
	end
	return NEUTRAL
end

-- ── Rig: aplica a pose no personagem ────────────────────────────────────────
--[[
	Funciona com os três formatos de personagem que o Roblox entrega:
	- R15 clássico: Motor6D (RightShoulder, RightElbow, RightWrist, Waist) — mexe
	  no C0;
	- R15 com o "Avatar Joint Upgrade": as articulações viram AnimationConstraint
	  — mexe na Attachment0 dela (o equivalente do C0);
	- R6: só "Right Shoulder" (no Torso), com orientação própria.
	A rotação é aplicada no espaço do TRONCO (posição * rotação * orientação
	original), então os mesmos ângulos servem para os três.
]]

type Joint = { Target: Instance, Property: string, Base: CFrame }
export type Rig = {
	Character: Model,
	Joints: { [string]: Joint },
	Kind: string, -- "Motor6D" | "AnimationConstraint" (diagnóstico)
	Variant: Variant,
	Started: number,
	Duration: number,
	From: Pose,
	Current: Pose,
	Active: boolean,
	Count: number,
	LastAt: number,
}

local JOINTS: { [string]: { string } } = {
	Shoulder = { "RightShoulder", "Right Shoulder" },
	Elbow = { "RightElbow" },
	Wrist = { "RightWrist" },
	Waist = { "Waist" },
}

local function rotation(degrees: Vector3): CFrame
	return CFrame.Angles(math.rad(degrees.X), math.rad(degrees.Y), math.rad(degrees.Z))
end

local function findJoint(character: Model, names: { string }): Joint?
	local constraint: Joint? = nil
	for _, name in names do
		for _, item in character:GetDescendants() do
			if item.Name == name then
				if item:IsA("Motor6D") and (item :: any).Enabled ~= false then
					return { Target = item, Property = "C0", Base = (item :: Motor6D).C0 }
				elseif item.ClassName == "AnimationConstraint" and not constraint then
					local attachment = (item :: any).Attachment0
					if attachment and attachment:IsA("Attachment") then
						constraint = { Target = attachment, Property = "CFrame", Base = attachment.CFrame }
					end
				end
			end
		end
	end
	return constraint
end

-- Monta o rig (nil se o personagem não tiver ombro direito reconhecível).
function SwordSwing.NewRig(character: Model): Rig?
	local joints: { [string]: Joint } = {}
	for key, names in JOINTS do
		local joint = findJoint(character, names)
		if joint then
			joints[key] = joint
		end
	end
	local shoulder = joints.Shoulder
	if not shoulder then
		return nil
	end
	return {
		Character = character,
		Joints = joints,
		Kind = if shoulder.Property == "C0" then "Motor6D" else "AnimationConstraint",
		Variant = "A",
		Started = 0,
		Duration = SwordSwing.SLOW_SECONDS,
		From = NEUTRAL,
		Current = NEUTRAL,
		Active = false,
		Count = 0,
		LastAt = -math.huge,
	}
end

-- A pose de uma articulação: rotação no espaço do tronco, mantendo a posição.
function SwordSwing.Posed(base: CFrame, degrees: Vector3): CFrame
	if degrees == ZERO then
		return base
	end
	return CFrame.new(base.Position) * rotation(degrees) * (base - base.Position)
end

local function apply(rig: Rig, pose: Pose)
	rig.Current = pose
	for key, joint in rig.Joints do
		if joint.Target.Parent then
			local degrees = (pose :: any)[key] :: Vector3;
			(joint.Target :: any)[joint.Property] = SwordSwing.Posed(joint.Base, degrees)
		end
	end
end

--[[
	Começa um golpe agora. Devolve (variação, segundos até o impacto). Um golpe
	no meio do anterior parte da pose atual: nunca há dois golpes ao mesmo tempo.
]]
function SwordSwing.Start(rig: Rig, now: number): (Variant, number)
	rig.Count += 1
	local duration = SwordSwing.DurationFor(now - rig.LastAt)
	rig.LastAt = now
	rig.Variant = SwordSwing.VariantFor(rig.Count)
	rig.From = rig.Current
	rig.Started = now
	rig.Duration = duration
	rig.Active = true
	return rig.Variant, duration * SwordSwing.IMPACT
end

-- Um quadro: aplica a pose do momento. Devolve se ainda está em movimento.
function SwordSwing.Step(rig: Rig, now: number): boolean
	if not rig.Active then
		return false
	end
	local t = (now - rig.Started) / rig.Duration
	if t >= 1 then
		rig.Active = false
		apply(rig, NEUTRAL)
		return false
	end
	apply(rig, SwordSwing.Pose(rig.Variant, t, rig.From))
	return true
end

-- Devolve tudo ao original (personagem saindo, morrendo, sendo trocado).
function SwordSwing.Reset(rig: Rig)
	rig.Active = false
	apply(rig, NEUTRAL)
end

return SwordSwing
