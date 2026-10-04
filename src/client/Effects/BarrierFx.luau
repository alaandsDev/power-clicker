--!strict
--[[
	BarrierFx
	O que a BARREIRA faz quando apanha e quando quebra, só neste cliente e só
	com as barreiras DESTE jogador (quem chama é o CombatFxController, a
	partir do golpe local e do WallState próprio).

	IMPACTO (cada hit, no ponto de contato):
		flash curto · fragmentos do material · partículas na direção do golpe ·
		poeira · onda curta (hit forte / corte forte) · linhas de energia
	RACHADURAS (pelo HP da fileira, CrackTier):
		0 intacta (>75%) · 1 primeiras (>50%) · 2 maiores + lascas (>25%) ·
		3 fortes + energia escapando (>10%) · 4 instável: brilho pulsando e
		fragmentos caindo (<10%)
	QUEBRA (a fileira cai):
		flash forte · rachaduras explodem · blocos voam para frente/laterais ·
		onda de choque atravessando a fileira · poeira · partícula do tema
		(a última fileira e o Colosso: maior e com segunda onda)

	Identidade de cada barreira: BarrierThemes (cores do WallConfig).

	Orçamento: tudo é pool fixo criado uma vez (flash, fragmentos, anéis,
	linhas, blocos), emissores por tema criados na primeira vez que o tema
	aparece, e rachaduras só nas fileiras perto (no máximo MAX_CRACK_SETS ao
	mesmo tempo), apagadas quando a fileira volta inteira ou fica longe.
	"Efeitos reduzidos": impacto vira só o flash; quebra vira flash + onda
	curta; rachaduras ficam (são informação de HP), sem brilho nem partícula.
]]

local TweenService = game:GetService("TweenService")

local BarrierThemes = require(script.Parent.BarrierThemes)

type Theme = BarrierThemes.Theme

type ThemeRig = { Anchor: BasePart, Burst: ParticleEmitter, Dust: ParticleEmitter }
type CrackSet = { Row: BasePart, Tier: number, Parts: { BasePart }, Light: PointLight?, Pulse: Tween?, Falling: ParticleEmitter? }

export type Fx = {
	Folder: Folder,
	Flashes: { BasePart },
	Chips: { BasePart },
	Rings: { BasePart },
	Lines: { BasePart },
	Debris: { BasePart },
	Index: { [string]: number },
	Themes: { [string]: ThemeRig },
	Cracks: { [BasePart]: CrackSet },
	CrackCount: number,
	Alive: boolean,
}

local POOLS = { Flashes = 3, Chips = 18, Rings = 3, Lines = 8, Debris = 28 }
local MAX_CRACK_SETS = 12
local CRACK_SEGMENTS = 7
-- Quanto de cada rachadura aparece em cada tier (segmentos, comprimento).
local CRACK_TIERS = {
	{ Count = 2, Length = 0.35 },
	{ Count = 4, Length = 0.55 },
	{ Count = 6, Length = 0.75 },
	{ Count = 7, Length = 0.9 },
}

local BarrierFx = {}

-- Tier de rachadura pela fração de HP que sobrou na fileira (0..1).
function BarrierFx.CrackTier(fraction: number): number
	if fraction > 0.75 then
		return 0
	elseif fraction > 0.5 then
		return 1
	elseif fraction > 0.25 then
		return 2
	elseif fraction > 0.1 then
		return 3
	end
	return if fraction > 0 then 4 else 0
end

local function newPart(folder: Instance, name: string, shape: Enum.PartType?): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(0.3, 0.3, 0.3)
	if shape then
		part.Shape = shape
	end
	part.Parent = folder
	return part
end

function BarrierFx.new(parent: Instance): Fx
	local folder = Instance.new("Folder")
	folder.Name = "BarrierFx"
	folder.Parent = parent
	local fx: Fx = {
		Folder = folder,
		Flashes = {},
		Chips = {},
		Rings = {},
		Lines = {},
		Debris = {},
		Index = {},
		Themes = {},
		Cracks = {},
		CrackCount = 0,
		Alive = true,
	}
	for _ = 1, POOLS.Flashes do
		local flash = newPart(folder, "Flash", Enum.PartType.Ball)
		flash.Material = Enum.Material.Neon
		table.insert(fx.Flashes, flash)
	end
	for _ = 1, POOLS.Chips do
		table.insert(fx.Chips, newPart(folder, "Chip"))
	end
	for _ = 1, POOLS.Rings do
		local ring = newPart(folder, "Shockwave", Enum.PartType.Cylinder)
		ring.Material = Enum.Material.Neon
		table.insert(fx.Rings, ring)
	end
	for _ = 1, POOLS.Lines do
		local line = newPart(folder, "SpeedLine")
		line.Material = Enum.Material.Neon
		table.insert(fx.Lines, line)
	end
	for _ = 1, POOLS.Debris do
		table.insert(fx.Debris, newPart(folder, "Debris"))
	end
	return fx
end

local function take(fx: Fx, pool: string): BasePart
	local list = (fx :: any)[pool] :: { BasePart }
	local index = ((fx.Index[pool] or 0) % #list) + 1
	fx.Index[pool] = index
	return list[index]
end

local function tween(instance: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?)
	TweenService:Create(instance, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
end

-- Emissores do tema: criados na primeira vez que o tema aparece.
local function themeRig(fx: Fx, theme: Theme): ThemeRig
	local existing = fx.Themes[theme.StageId]
	if existing then
		return existing
	end
	local anchor = newPart(fx.Folder, "Emit_" .. theme.StageId)
	local burst = Instance.new("ParticleEmitter")
	burst.Rate = 0
	burst.Texture = BarrierThemes.Texture(theme.Particle)
	burst.Color = ColorSequence.new(if theme.Particle == "Smoke" then theme.Dust else theme.Energy)
	burst.LightEmission = if theme.Particle == "Smoke" then 0 else 1
	burst.Lifetime = NumberRange.new(0.2, 0.45)
	burst.Speed = NumberRange.new(8, 18)
	burst.Drag = 5
	burst.SpreadAngle = Vector2.new(30, 30)
	burst.EmissionDirection = Enum.NormalId.Front
	burst.Size = NumberSequence.new(if theme.Particle == "Smoke" then 0.8 else 0.35, 0)
	burst.Transparency = NumberSequence.new(0, 1)
	burst.Parent = anchor
	local dust = Instance.new("ParticleEmitter")
	dust.Rate = 0
	dust.Texture = BarrierThemes.Texture("Smoke")
	dust.Color = ColorSequence.new(theme.Dust)
	dust.LightEmission = 0
	dust.Lifetime = NumberRange.new(0.35, 0.8)
	dust.Speed = NumberRange.new(2, 6)
	dust.Drag = 3
	dust.SpreadAngle = Vector2.new(50, 50)
	dust.EmissionDirection = Enum.NormalId.Front
	dust.Size = NumberSequence.new(0.6, 2.2)
	dust.Transparency = NumberSequence.new(0.35, 1)
	dust.Parent = anchor
	local rig = { Anchor = anchor, Burst = burst, Dust = dust }
	fx.Themes[theme.StageId] = rig
	return rig
end

export type ImpactOptions = {
	Normal: Vector3, -- para onde a face da barreira olha (para o jogador)
	Intensity: number, -- CutVisuals.Recipe.Impact (1 = corte inicial)
	CutColor: Color3,
	Strong: boolean, -- o hit tirou uma fatia grande da fileira
	Reduced: boolean,
}

--[[
	Um hit no ponto `point` da face. Tudo nasce ali e vai na direção do golpe
	de volta (Normal) e um pouco para os lados — nada espalhado pela tela.
]]
function BarrierFx.Impact(fx: Fx, theme: Theme, point: Vector3, options: ImpactOptions)
	if not fx.Alive then
		return
	end
	local intensity = math.clamp(options.Intensity, 0.5, 3) * (if options.Strong then 1.4 else 1)
	local normal = options.Normal.Unit
	local face = CFrame.lookAt(point, point + normal)

	-- Flash no ponto de contato (o mínimo, mesmo com efeitos reduzidos).
	local flash = take(fx, "Flashes")
	flash.Color = Color3.new(1, 1, 1):Lerp(options.CutColor, 0.35)
	flash.CFrame = CFrame.new(point)
	flash.Size = Vector3.one * 0.6 * intensity
	flash.Transparency = 0
	tween(flash, 0.09, { Size = Vector3.one * 2.2 * intensity, Transparency = 1 })
	if options.Reduced then
		return
	end

	-- Fragmentos do material, voando de volta da face.
	local chips = math.min(2 + math.floor(intensity) + (if options.Strong then 3 else 0), 8)
	for _ = 1, chips do
		local chip = take(fx, "Chips")
		local size = (0.22 + math.random() * 0.25) * math.sqrt(intensity)
		chip.Size = Vector3.new(size, size * (0.6 + math.random() * 0.8), size)
		chip.Material = if theme.ChipGlow then Enum.Material.Neon else theme.ChipMaterial
		chip.Color = if theme.ChipGlow then theme.Chip:Lerp(theme.Energy, 0.5) else theme.Chip
		chip.CFrame = face * CFrame.Angles(math.random() * 6, math.random() * 6, 0)
		chip.Transparency = 0
		local out = point
			+ normal * (1.5 + math.random() * 2) * intensity
			+ face.RightVector * (math.random() - 0.5) * 3
			+ face.UpVector * (math.random() * 2.5 - 0.8)
		tween(chip, 0.32, { CFrame = CFrame.new(out) * CFrame.Angles(math.random() * 6, math.random() * 6, 0), Transparency = 1 })
	end

	-- Partículas do tema na direção do golpe e um pouco de poeira.
	local rig = themeRig(fx, theme)
	rig.Anchor.CFrame = face
	rig.Burst:Emit(math.floor(4 * intensity) + (if options.Strong then 6 else 0))
	rig.Dust:Emit(if options.Strong then 4 else 2)

	-- Onda curta na superfície (hit forte ou corte forte).
	if options.Strong or options.Intensity >= 1.5 then
		local ring = take(fx, "Rings")
		ring.Color = options.CutColor
		ring.CFrame = CFrame.new(point) -- eixo do cilindro em X = a normal da face do corredor
		ring.Size = Vector3.new(0.1, 1, 1)
		ring.Transparency = 0.2
		local reach = (if options.Strong then 6 else 4) * math.sqrt(intensity)
		tween(ring, 0.18, { Size = Vector3.new(0.05, reach, reach), Transparency = 1 })
	end

	-- Linhas de energia saindo do ponto, no plano da face.
	local lines = if options.Strong then 4 else 2
	local energy = theme.Particle == "Electric" or theme.ChipGlow
	for index = 1, lines do
		local line = take(fx, "Lines")
		local angle = (index / lines) * math.pi * 2 + math.random() * 0.8
		local dir = face.RightVector * math.cos(angle) + face.UpVector * math.sin(angle)
		local length = 1.4 * math.sqrt(intensity)
		line.Color = if energy then theme.Energy else options.CutColor:Lerp(Color3.new(1, 1, 1), 0.5)
		line.Size = Vector3.new(0.08, 0.08, length)
		line.CFrame = CFrame.lookAt(point + dir * 0.4, point + dir * 2)
		line.Transparency = 0.1
		tween(line, 0.12, { CFrame = CFrame.lookAt(point + dir * (0.6 + length), point + dir * (2 + length)), Transparency = 1, Size = Vector3.new(0.04, 0.04, length * 0.5) })
	end
end

-- ── Rachaduras ──────────────────────────────────────────────────────────────

local function seedOf(name: string): number
	local seed = 7
	for index = 1, #name do
		seed = (seed * 31 + string.byte(name, index)) % 100003
	end
	return seed
end

local function clearSet(fx: Fx, set: CrackSet, explode: boolean)
	if set.Pulse then
		set.Pulse:Cancel()
	end
	for _, part in set.Parts do
		if explode then
			local cf = part.CFrame
			tween(part, 0.18, { CFrame = cf + cf.LookVector * 1.5, Size = part.Size * Vector3.new(2, 2, 1.6), Transparency = 1 })
			task.delay(0.2, part.Destroy, part)
		else
			part:Destroy()
		end
	end
	fx.Cracks[set.Row] = nil
	fx.CrackCount -= 1
end

--[[
	Rachaduras da fileira `row` (só aparência, só neste cliente). As linhas
	são sempre as mesmas para a mesma fileira (semente pelo nome): o tier só
	revela mais e mais longas, então a fileira "vai abrindo" em vez de piscar.
]]
function BarrierFx.SetCracks(fx: Fx, row: BasePart, theme: Theme, tier: number, reduced: boolean)
	if not fx.Alive then
		return
	end
	local set = fx.Cracks[row]
	if tier <= 0 then
		if set then
			clearSet(fx, set, false)
		end
		return
	end
	if set and set.Tier == tier then
		return
	end
	if set then
		clearSet(fx, set, false)
	elseif fx.CrackCount >= MAX_CRACK_SETS then
		return -- orçamento: fileiras demais rachadas ao mesmo tempo
	end
	local level = CRACK_TIERS[math.clamp(tier, 1, #CRACK_TIERS)]
	local half = row.Size / 2
	local centre = row.CFrame.Position - Vector3.new(half.X + 0.06, 0, 0)
	local span = math.min(half.Y, half.Z)
	local random = Random.new(seedOf(row.Name))
	local parts = {}
	local dark = theme.Chip:Lerp(Color3.new(0, 0, 0), 0.7)
	for index = 1, CRACK_SEGMENTS do
		local angle = random:NextNumber(0, math.pi * 2)
		local length = span * random:NextNumber(0.5, 1) * level.Length
		local offset = Vector3.new(0, random:NextNumber(-0.2, 0.2) * span, random:NextNumber(-0.2, 0.2) * span)
		if index <= level.Count then
			local dir = Vector3.new(0, math.sin(angle), math.cos(angle))
			local start = centre + offset
			local part = newPart(fx.Folder, "Crack")
			local glowing = tier >= 3 and index % 2 == 0 and not reduced
			part.Material = if glowing then Enum.Material.Neon else Enum.Material.SmoothPlastic
			part.Color = if glowing then theme.Energy else dark
			part.Size = Vector3.new(0.12, 0.08 + 0.05 * tier, length)
			part.CFrame = CFrame.lookAt(start + dir * length / 2, start + dir * length, Vector3.xAxis)
			part.Transparency = 0
			table.insert(parts, part)
		end
	end
	local newSet: CrackSet = { Row = row, Tier = tier, Parts = parts }
	if tier >= 4 and not reduced and parts[1] then
		-- Instável: brilho pulsando e fragmentos caindo da face.
		local light = Instance.new("PointLight")
		light.Color = theme.Energy
		light.Range = 10
		light.Brightness = 0.5
		light.Shadows = false
		light.Parent = parts[1]
		local pulse = TweenService:Create(light, TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Brightness = 3 })
		pulse:Play()
		local falling = Instance.new("ParticleEmitter")
		falling.Rate = 5
		falling.Texture = BarrierThemes.Texture("Sparkle")
		falling.Color = ColorSequence.new(theme.Chip)
		falling.LightEmission = 0.2
		falling.Lifetime = NumberRange.new(0.6, 1)
		falling.Speed = NumberRange.new(1, 3)
		falling.Acceleration = Vector3.new(0, -30, 0)
		falling.Size = NumberSequence.new(0.3, 0.1)
		falling.Parent = parts[1]
		newSet.Light = light
		newSet.Pulse = pulse
		newSet.Falling = falling
	end
	fx.Cracks[row] = newSet
	fx.CrackCount += 1
end

-- Apaga as rachaduras de fileiras que não estão perto (LOD) ou que sumiram.
function BarrierFx.PruneCracks(fx: Fx, near: (BasePart) -> boolean)
	for row, set in fx.Cracks do
		if not row.Parent or not near(row) then
			clearSet(fx, set, false)
		end
	end
end

-- ── Quebra ──────────────────────────────────────────────────────────────────

export type BreakOptions = {
	Normal: Vector3, -- para o jogador
	Final: boolean, -- a última fileira da barreira (a passagem abre)
	CutColor: Color3,
	Reduced: boolean,
}

function BarrierFx.Break(fx: Fx, theme: Theme, row: BasePart, options: BreakOptions)
	if not fx.Alive then
		return
	end
	local epic = theme.Epic * (if options.Final then 1.4 else 1)
	local centre = row.CFrame.Position
	local half = row.Size / 2
	local normal = options.Normal.Unit
	local forward = -normal -- para longe do jogador: a abertura

	local set = fx.Cracks[row]
	if set then
		clearSet(fx, set, not options.Reduced) -- a rachadura explode pelo centro
	end

	-- Flash forte no centro.
	local flash = take(fx, "Flashes")
	flash.Color = Color3.new(1, 1, 1):Lerp(options.CutColor, 0.25)
	flash.CFrame = CFrame.new(centre - Vector3.new(half.X, 0, 0))
	flash.Size = Vector3.one * 2
	flash.Transparency = 0
	tween(flash, 0.16, { Size = Vector3.one * math.min(half.Y, half.Z) * 1.6 * math.sqrt(epic), Transparency = 1 })

	-- Onda de choque atravessando a fileira (no plano dela).
	local function shockwave(delay: number, scale: number)
		local ring = take(fx, "Rings")
		task.delay(delay, function()
			ring.Color = theme.Energy
			ring.CFrame = CFrame.new(centre)
			ring.Size = Vector3.new(0.2, 2, 2)
			ring.Transparency = 0.15
			local reach = row.Size.Z * 0.9 * scale
			tween(ring, 0.35, { Size = Vector3.new(0.05, reach, reach), Transparency = 1 })
		end)
	end
	shockwave(0, if options.Reduced then 0.4 else 1)
	if options.Reduced then
		return
	end
	if options.Final or theme.Epic >= 2 then
		shockwave(0.08, 1.3)
	end

	-- Blocos voando para frente e para os lados, caindo.
	local blocks = math.min(math.floor(10 * epic), #fx.Debris)
	for _ = 1, blocks do
		local piece = take(fx, "Debris")
		local size = math.clamp(math.min(half.Y, half.Z) * (0.12 + math.random() * 0.14) * math.sqrt(theme.Epic), 0.6, 5)
		piece.Size = Vector3.new(size * (0.6 + math.random() * 0.6), size, size * (0.6 + math.random() * 0.6))
		piece.Material = theme.ChipMaterial
		piece.Color = if math.random() < 0.3 and theme.ChipGlow then theme.Energy else theme.Chip:Lerp(Color3.new(0, 0, 0), math.random() * 0.25)
		local start = centre + Vector3.new((math.random() - 0.5) * row.Size.X, (math.random() - 0.5) * row.Size.Y * 0.8, (math.random() - 0.5) * row.Size.Z * 0.8)
		piece.CFrame = CFrame.new(start) * CFrame.Angles(math.random() * 6, math.random() * 6, 0)
		piece.Transparency = 0
		local lateral = Vector3.new(0, 0, (start.Z - centre.Z) / math.max(half.Z, 1)) * (4 + math.random() * 8)
		local target = start + forward * (6 + math.random() * 14) * math.sqrt(epic) + lateral + Vector3.new(0, -(3 + math.random() * 6), 0)
		tween(piece, 0.55 + math.random() * 0.3, { CFrame = CFrame.new(target) * CFrame.Angles(math.random() * 9, math.random() * 9, math.random() * 9), Transparency = 1 }, Enum.EasingStyle.Quad)
	end

	-- Poeira e partícula do tema na face.
	local rig = themeRig(fx, theme)
	rig.Anchor.CFrame = CFrame.lookAt(centre - Vector3.new(half.X, 0, 0), centre - Vector3.new(half.X, 0, 0) + normal)
	rig.Dust:Emit(math.floor(16 * epic))
	rig.Burst:Emit(math.floor(24 * epic))
	if theme.Smoke then
		rig.Dust:Emit(math.floor(8 * epic))
	end
end

-- Apaga tudo (o controller sai / testes).
function BarrierFx.Destroy(fx: Fx)
	if not fx.Alive then
		return
	end
	fx.Alive = false
	for _, set in fx.Cracks do
		if set.Pulse then
			set.Pulse:Cancel()
		end
	end
	table.clear(fx.Cracks)
	fx.Folder:Destroy()
end

return BarrierFx
