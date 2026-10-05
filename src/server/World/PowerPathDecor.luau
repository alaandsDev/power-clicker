--!strict
--[[
	PowerPathDecor
	O CENÁRIO de cada estágio do Caminho do Poder (Fase B em diante): landmark,
	peças secundárias, molduras das barreiras e as peças de transição. Só
	constrói — ONDE e QUANTO vem do CorridorThemes (Theme.Decor); nenhum
	`if estágio == ...` aqui: cada `Kind` é um builder reutilizável.

	Coordenadas: x ao longo do corredor (relativo à origem do mundo), y = 0 no
	topo do piso, z do centro da faixa (lado -1/1). Todos os builders respeitam
	as regras que o check_power_path confere:
	  · SAFE PLAY LANE: nada acima de 0,3 stud com |z| < 18 abaixo de y 14;
	  · frente da barreira (placa de HP): x ∈ [B-12, B], |z| < 38, y 0,3–14
	    livre; molduras ficam em |z| ≥ 38 ou acima das fileiras (y > 30,5);
	  · nada sobre os pads nem dentro das fileiras;
	  · câmera chegando na barreira: nada sobre a faixa entre y 14 e 24 nos
	    40 studs antes dela;
	  · Neon só como ACENTO (veios, runas, fissuras: peças finas);
	  · sem loop: tudo estático e ancorado. O único dinâmico são os poucos
	    emissores ambientais (tag PowerPathAmbient, desligados aqui; o cliente
	    liga perto da câmera e respeita "Efeitos reduzidos" —
	    PowerPathEnvironmentController, um sistema só para todos os estágios).
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local CorridorThemes = require(Shared.Config.CorridorThemes)
local CorridorLayout = require(Shared.Formulas.CorridorLayout)

local PowerPathDecor = {}

PowerPathDecor.TAG_AMBIENT = "PowerPathAmbient"

local M = Enum.Material
local RAD = math.rad
local VERTICAL = CFrame.Angles(0, 0, math.pi / 2) -- cilindro de pé (eixo X → Y)

-- Paleta do cenário (cores de material, não de identidade de estágio).
local C = {
	Bark = Color3.fromRGB(92, 64, 42),
	BarkDark = Color3.fromRGB(70, 48, 32),
	Leaves = Color3.fromRGB(62, 112, 50),
	LeavesLight = Color3.fromRGB(86, 136, 60),
	Moss = Color3.fromRGB(74, 116, 54),
	Boulder = Color3.fromRGB(112, 106, 94),
	Worked = Color3.fromRGB(150, 146, 136),
	Column = Color3.fromRGB(176, 170, 154),
	ColumnBase = Color3.fromRGB(122, 118, 110),
	Rubble = Color3.fromRGB(130, 126, 116),
	Frost = Color3.fromRGB(226, 238, 248),
	Ice = Color3.fromRGB(170, 214, 236),
	IceDeep = Color3.fromRGB(120, 180, 214),
	Icicle = Color3.fromRGB(205, 232, 246),
	Snow = Color3.fromRGB(236, 244, 250),
	-- Cristal energizado (4): mineral violeta, veio de energia claro.
	Crystal = Color3.fromRGB(108, 88, 184),
	CrystalDeep = Color3.fromRGB(72, 58, 132),
	Energy = Color3.fromRGB(140, 232, 255),
	CrystalRock = Color3.fromRGB(52, 48, 66),
	-- Templo dourado (5): pedra quente + ouro envelhecido (acabamento).
	Temple = Color3.fromRGB(164, 144, 112),
	TempleDark = Color3.fromRGB(118, 98, 74),
	Gold = Color3.fromRGB(196, 154, 64),
	-- Ancestral (6): granito pesado, runas de energia fria.
	Ancient = Color3.fromRGB(78, 78, 74),
	AncientDark = Color3.fromRGB(58, 58, 56),
	Rune = Color3.fromRGB(110, 226, 186),
	-- Calor (indício do 7).
	Scorched = Color3.fromRGB(46, 38, 36),
	Heat = Color3.fromRGB(255, 112, 40),
}

type Ctx = {
	Model: Model,
	Origin: Vector3,
	Segment: CorridorLayout.Segment,
	Theme: CorridorThemes.Theme,
	NextTheme: CorridorThemes.Theme,
	Half: number,
	Kind: string,
	Landmark: boolean,
	Fx: string?, -- VFX ambiental pedido pela entrada do Decor (preset)
}

type Opts = { Shape: Enum.PartType?, Wedge: boolean?, Transparency: number?, Shadow: boolean? }

local function piece(ctx: Ctx, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, collide: boolean, opts: Opts?): BasePart
	local o: Opts = opts or {}
	local p: BasePart
	if o.Wedge then
		p = Instance.new("WedgePart")
	else
		local block = Instance.new("Part")
		if o.Shape then
			block.Shape = o.Shape
		end
		p = block
	end
	p.Name = "PathDecor_" .. ctx.Kind
	p.Anchored = true
	p.Size = size
	p.CFrame = CFrame.new(ctx.Origin) * cframe
	p.Color = color
	p.Material = material
	p.Transparency = o.Transparency or 0
	p.CanCollide = collide
	p.CanTouch = false
	p.CanQuery = collide
	p.CastShadow = if o.Shadow ~= nil then o.Shadow else collide
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p:SetAttribute("Decor", ctx.Kind)
	if ctx.Landmark then
		p:SetAttribute("Landmark", true)
	end
	p.Parent = ctx.Model
	return p
end

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

-- Altura da parede lateral em `x` (perfil do tema por terço).
local function wallHeight(ctx: Ctx, x: number): number
	local segment = ctx.Segment
	if x >= segment.Barrier then
		return ctx.Theme.Profile[4]
	end
	local third = (segment.Barrier - segment.AreaStart) / 3
	return ctx.Theme.Profile[math.clamp(math.floor((x - segment.AreaStart) / third) + 1, 1, 3)]
end

type Builder = (ctx: Ctx, x: number, side: number, z: number, scale: number, yaw: number) -> ()

local B: { [string]: Builder } = {}

-- ── 1 Floresta ──────────────────────────────────────────────────────────────

-- Árvore antiga: tronco largo, duas raízes abertas para a faixa e a copa
-- acima de y 14 — duas delas, uma de cada lado, são a entrada natural.
B.AncientTree = function(ctx, x, side, z, s, _yaw)
	local height, d = 34 * s, 6 * s
	local tz = side * (z + 2)
	piece(ctx, Vector3.new(height, d, d), at(x, height / 2, tz) * VERTICAL, C.Bark, M.Wood, true, { Shape = Enum.PartType.Cylinder })
	-- Raízes: uma para a faixa (para em |z| ≈ 24), outra ao longo do corredor.
	piece(ctx, Vector3.new(2.6, 2.6, 9 * s), at(x + 0.5, 0.9, tz - side * 6 * s) * CFrame.Angles(side * RAD(-10), RAD(12), 0), C.BarkDark, M.Wood, false)
	piece(ctx, Vector3.new(10 * s, 2.4, 2.6), at(x - 4.5 * s, 0.8, tz + side * 0.5) * CFrame.Angles(0, RAD(-15 * side), RAD(9)), C.BarkDark, M.Wood, false)
	-- Copa: a grande se debruça sobre a faixa (sempre acima de y 14).
	local big = 24 * s
	piece(ctx, Vector3.new(big, big, big), at(x, math.max(height - 3 * s, 14 + big / 2 + 0.5), side * 28), C.Leaves, M.Grass, false, { Shape = Enum.PartType.Ball, Shadow = true })
	piece(ctx, Vector3.new(16 * s, 16 * s, 16 * s), at(x + 5 * s, height + 5 * s, side * 35), C.LeavesLight, M.Grass, false, { Shape = Enum.PartType.Ball, Shadow = true })
end

B.FoliageClump = function(ctx, x, side, z, s, _yaw)
	piece(ctx, Vector3.new(7, 7, 7) * s, at(x, 1.6, side * z), C.Leaves, M.Grass, false, { Shape = Enum.PartType.Ball })
	piece(ctx, Vector3.new(5, 5, 5) * s, at(x + 4 * s, 1.2, side * (z + 2)), C.LeavesLight, M.Grass, false, { Shape = Enum.PartType.Ball })
end

B.Boulder = function(ctx, x, side, z, s, yaw)
	piece(ctx, Vector3.new(7, 5, 6) * s, at(x, 2.2 * s, side * z) * CFrame.Angles(RAD(6), RAD(yaw), RAD(-5)), C.Boulder, M.Rock, true)
	piece(ctx, Vector3.new(5.5, 0.6, 4.6) * s, at(x, 4.8 * s, side * z) * CFrame.Angles(RAD(6), RAD(yaw + 8), RAD(-5)), C.Moss, M.Grass, false)
end

-- Raiz rasteira no chão, fora da safe lane (sem colisão: ninguém tropeça).
B.FloorRoot = function(ctx, x, side, z, s, yaw)
	piece(ctx, Vector3.new(12 * s, 1.2, 2), at(x, 0.4, side * z) * CFrame.Angles(0, RAD(yaw * side), 0), C.BarkDark, M.Wood, false)
end

B.Stump = function(ctx, x, side, z, s, _yaw)
	piece(ctx, Vector3.new(3.2, 5, 5) * s, at(x, 1.6 * s, side * z) * VERTICAL, C.Bark, M.Wood, true, { Shape = Enum.PartType.Cylinder })
end

B.FallenLog = function(ctx, x, side, z, s, _yaw)
	piece(ctx, Vector3.new(14, 3, 3) * s, at(x, 1.4 * s, side * z) * CFrame.Angles(0, RAD(8 * side), 0), C.Bark, M.Wood, false, { Shape = Enum.PartType.Cylinder })
end

-- Transição 1 → 2: pedra TRABALHADA (aresta reta) e tambor de coluna.
B.WorkedStone = function(ctx, x, side, z, s, yaw)
	piece(ctx, Vector3.new(5, 3.5, 4) * s, at(x, 1.6 * s, side * z) * CFrame.Angles(0, RAD(yaw), RAD(4)), C.Worked, M.Cobblestone, true)
end

B.ColumnDrum = function(ctx, x, side, z, s, _yaw)
	piece(ctx, Vector3.new(3, 5, 5) * s, at(x, 1.5 * s, side * z) * VERTICAL, C.Column, M.Concrete, true, { Shape = Enum.PartType.Cylinder })
	piece(ctx, Vector3.new(6, 4.4, 4.4) * s, at(x - 1, 2.2 * s, side * (z - 4)) * CFrame.Angles(0, RAD(-12 * side), 0), C.Column, M.Concrete, false, { Shape = Enum.PartType.Cylinder })
end

-- Barreira 1: troncos/raízes nas bordas e um galho grosso por cima das
-- fileiras — a barreira de madeira "nasce" da floresta.
B.BarrierRoots = function(ctx, x, _side, _z, _s, _yaw)
	local segment, half = ctx.Segment, ctx.Half
	for _, side in { -1, 1 } do
		piece(ctx, Vector3.new(3.2, 32, 4), at(x - 3, 16, side * (half - 2)) * CFrame.Angles(0, RAD(6 * side), 0), C.Bark, M.Wood, true)
		piece(ctx, Vector3.new(10, 1.5, 2.6), at(x - 7, 0.6, side * (half - 2)) * CFrame.Angles(0, RAD(10 * side), 0), C.BarkDark, M.Wood, false)
	end
	piece(ctx, Vector3.new(half * 2 - 2, 3.4, 3.4), at(segment.Barrier + 2, 32.4, 0) * CFrame.Angles(0, math.pi / 2, 0), C.Bark, M.Wood, false, { Shape = Enum.PartType.Cylinder, Shadow = true })
end

-- ── 2 Ruínas ────────────────────────────────────────────────────────────────

-- Coluna de templo; abaixo do tamanho cheio fica QUEBRADA (pedaço caído ao lado).
B.RuinColumn = function(ctx, x, side, z, s, _yaw)
	local shaft = 22 * s
	local cz = side * z
	piece(ctx, Vector3.new(6, 2, 6), at(x, 1, cz), C.ColumnBase, M.Slate, true)
	piece(ctx, Vector3.new(shaft, 4, 4), at(x, 2 + shaft / 2, cz) * VERTICAL, C.Column, M.Concrete, true, { Shape = Enum.PartType.Cylinder })
	if s >= 1 then
		piece(ctx, Vector3.new(6, 2, 6), at(x, 3 + shaft, cz), C.Column, M.Concrete, false)
	else
		piece(ctx, Vector3.new(4.4, 3.6, 3.6), at(x + 3, 1.6, side * (z - 5)) * CFrame.Angles(0, RAD(30), RAD(8)), C.Column, M.Concrete, false, { Shape = Enum.PartType.Cylinder })
	end
end

B.Rubble = function(ctx, x, side, z, s, yaw)
	piece(ctx, Vector3.new(5, 3, 4) * s, at(x, 1.3 * s, side * z) * CFrame.Angles(RAD(8), RAD(yaw), RAD(-6)), C.Rubble, M.Slate, true)
	piece(ctx, Vector3.new(3, 2, 3) * s, at(x + 3.5 * s, 0.8 * s, side * (z + 2)) * CFrame.Angles(RAD(-10), RAD(yaw + 35), RAD(12)), C.Rubble, M.Slate, false)
end

B.BrokenSlab = function(ctx, x, side, z, s, yaw)
	piece(ctx, Vector3.new(8, 0.8, 6) * s, at(x, 0.5, side * z) * CFrame.Angles(RAD(-7 * side), RAD(yaw), 0), C.Worked, M.Slate, false)
end

-- LANDMARK 2: arco de templo quebrado e ASSIMÉTRICO sobre a faixa — um lado
-- inteiro (coluna + capitel + verga que para no meio), o outro partido, com
-- o pedaço da verga caído no chão.
B.BrokenArch = function(ctx, x, _side, _z, _s, _yaw)
	local cz = 30
	-- Lado inteiro (-z).
	piece(ctx, Vector3.new(7, 2, 7), at(x, 1, -cz), C.ColumnBase, M.Slate, true)
	piece(ctx, Vector3.new(26, 5, 5), at(x, 15, -cz) * VERTICAL, C.Column, M.Concrete, true, { Shape = Enum.PartType.Cylinder })
	piece(ctx, Vector3.new(7, 2, 7), at(x, 29, -cz), C.Column, M.Concrete, false)
	-- Lado partido (+z).
	piece(ctx, Vector3.new(7, 2, 7), at(x, 1, cz), C.ColumnBase, M.Slate, true)
	piece(ctx, Vector3.new(12, 5, 5), at(x, 8, cz) * VERTICAL, C.Column, M.Concrete, true, { Shape = Enum.PartType.Cylinder })
	piece(ctx, Vector3.new(3.4, 2.4, 3.4), at(x + 0.6, 15, cz - 0.8) * CFrame.Angles(RAD(18), RAD(20), RAD(-14)), C.Column, M.Concrete, false)
	-- Verga: sai do capitel e para quebrada depois do meio (acima de y 30).
	piece(ctx, Vector3.new(6, 3.5, 44), at(x, 31.75, -cz - 4 + 22), C.Column, M.Concrete, false, { Shadow = true })
	-- O pedaço que caiu, deitado junto da parede.
	piece(ctx, Vector3.new(6, 3, 14), at(x + 7, 1.6, cz + 3) * CFrame.Angles(RAD(-6), RAD(20), RAD(4)), C.Column, M.Concrete, true)
end

-- Barreira 2: a entrada BLOQUEADA de uma construção antiga — umbrais de
-- pedra nas bordas e a verga partida em cima das fileiras.
B.RuinGate = function(ctx, x, _side, _z, _s, _yaw)
	local half = ctx.Half
	for _, side in { -1, 1 } do
		piece(ctx, Vector3.new(4, 34, 4), at(x - 3, 17, side * (half - 2)), C.Column, M.Concrete, true)
		piece(ctx, Vector3.new(5.4, 3, 5), at(x - 3, 1.5, side * (half - 2.3)), C.ColumnBase, M.Slate, true)
	end
	piece(ctx, Vector3.new(6, 3.5, 56), at(x + 1, 32.75, -half + 1 + 28), C.Column, M.Concrete, false, { Shadow = true })
end

-- ── Frost e gelo (transição 2 → 3 e estágio 3) ──────────────────────────────

B.FrostCap = function(ctx, x, side, z, s, _yaw)
	piece(ctx, Vector3.new(5.6, 0.5, 4.6) * s, at(x, 3, side * z) * CFrame.Angles(RAD(8), RAD(40), RAD(-6)), C.Frost, M.Snow, false)
end

-- Frost no chão junto da parede (rente: topo < 0,3) e subindo a base da parede.
B.FrostPatch = function(ctx, x, side, _z, s, _yaw)
	local half = ctx.Half
	piece(ctx, Vector3.new(10 * s, 0.12, 7), at(x, 0.06, side * (half - 4.5)), C.Frost, M.Snow, false)
	piece(ctx, Vector3.new(12 * s, 6, 0.4), at(x - 1, 3, side * (half - 0.2)), C.Frost, M.Snow, false)
end

-- Crosta de gelo colada na base da parede.
B.IceCrust = function(ctx, x, side, _z, s, _yaw)
	piece(ctx, Vector3.new(12 * s, 3.5, 1.6), at(x, 1.75, side * (ctx.Half - 0.8)), C.Ice, M.Ice, false, { Transparency = 0.15 })
end

B.IceShard = function(ctx, x, side, z, s, _yaw)
	local h = 10 * s
	piece(ctx, Vector3.new(2.4, h, 2.4), at(x, h / 2 - 0.4, side * z) * CFrame.Angles(side * RAD(-12), RAD(45), 0), C.Ice, M.Ice, false, { Transparency = 0.1 })
end

B.FrozenPuddle = function(ctx, x, side, z, s, _yaw)
	piece(ctx, Vector3.new(0.12, 8 * s, 8 * s), at(x, 0.06, side * z) * VERTICAL, C.IceDeep, M.Ice, false, { Shape = Enum.PartType.Cylinder })
end

-- Pingentes pendurados no capitel da parede (pedra sob gelo).
B.Icicles = function(ctx, x, side, _z, s, _yaw)
	local top = wallHeight(ctx, x)
	local z = side * (ctx.Half - 0.6)
	piece(ctx, Vector3.new(1.2, 6 * s, 1.2), at(x, top - 3 * s, z) * CFrame.Angles(0, RAD(45), 0), C.Icicle, M.Ice, false, { Transparency = 0.1 })
	piece(ctx, Vector3.new(1, 4 * s, 1), at(x + 2.6, top - 2 * s, z) * CFrame.Angles(0, RAD(45), 0), C.Icicle, M.Ice, false, { Transparency = 0.1 })
end

local function spire(ctx: Ctx, x: number, z: number, side: number, height: number, width: number, tilt: number, transparency: number): BasePart
	-- Inclina o topo para a faixa (tilt em graus) e gira 45° (seção em losango).
	return piece(ctx, Vector3.new(width, height, width), at(x, height / 2 - 0.5, side * z) * CFrame.Angles(side * RAD(-tilt), RAD(45), 0), C.Ice, M.Ice, true, { Transparency = transparency })
end

B.IceSpire = function(ctx, x, side, z, s, yaw)
	spire(ctx, x, z, side, 36 * s, 3.2, 8 + yaw * 0.2, 0.12)
	piece(ctx, Vector3.new(6, 3, 6), at(x, 1.3, side * z) * CFrame.Angles(0, RAD(20), 0), C.IceDeep, M.Glacier, false)
end

--[[
	VFX ambiental: poucas partículas, DESLIGADAS no servidor (tag
	PowerPathAmbient). Um único controlador no cliente (PowerPathEnvironment-
	Controller) liga cada um só perto da câmera e sem "Efeitos reduzidos".
	Presets por nome (Theme.Ambient / Decor.Fx).
]]
type Preset = { Rate: number, Life: NumberRange, Speed: NumberRange, Spread: number, Size: number, Color: Color3, Light: number, Accel: Vector3? }
local PRESETS: { [string]: Preset } = {
	FrostSparkle = { Rate = 5, Life = NumberRange.new(1.4, 2.4), Speed = NumberRange.new(0.3, 1.2), Spread = 180, Size = 0.5, Color = C.Icicle, Light = 0.6 },
	-- Motes de energia subindo devagar dos cristais (estágio 4).
	CrystalMotes = { Rate = 4, Life = NumberRange.new(2.5, 3.5), Speed = NumberRange.new(0.6, 1.4), Spread = 25, Size = 0.35, Color = Color3.fromRGB(150, 236, 255), Light = 0.8 },
	-- Brasas raras no fim do 6: o primeiro sinal do vulcânico.
	Embers = { Rate = 3, Life = NumberRange.new(1.8, 2.8), Speed = NumberRange.new(1, 2.2), Spread = 20, Size = 0.25, Color = Color3.fromRGB(255, 130, 50), Light = 1, Accel = Vector3.new(0, 0.8, 0) },
}

local function ambient(owner: BasePart, presetName: string)
	local preset = PRESETS[presetName]
	assert(preset, "PowerPathDecor: VFX ambiental desconhecido " .. presetName)
	local fx = Instance.new("ParticleEmitter")
	fx.Name = presetName
	fx.Enabled = false
	fx.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	fx.Rate = preset.Rate
	fx.Lifetime = preset.Life
	fx.Speed = preset.Speed
	fx.SpreadAngle = Vector2.new(preset.Spread, preset.Spread)
	fx.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, preset.Size), NumberSequenceKeypoint.new(1, 0) })
	fx.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	fx.LightEmission = preset.Light
	fx.Color = ColorSequence.new(preset.Color)
	if preset.Accel then
		fx.Acceleration = preset.Accel
	end
	fx.Parent = owner
	fx:AddTag(PowerPathDecor.TAG_AMBIENT)
end

-- LANDMARK 3: formação de gelo — três agulhas em leque sobre um monte de
-- geleira, a maior com a cintilação local (se o tema permitir).
B.IceFormation = function(ctx, x, side, z, s, _yaw)
	piece(ctx, Vector3.new(14, 4, 10) * s, at(x, 1.2, side * (z + 4)), C.IceDeep, M.Glacier, true)
	local main = spire(ctx, x, z + 4, side, 38 * s, 5, 10, 0.08)
	spire(ctx, x - 5 * s, z - 1, side, 18 * s, 3.4, 16, 0.12)
	spire(ctx, x + 5.5 * s, z + 7, side, 22 * s, 3.6, 4, 0.12)
	if ctx.Theme.Ambient == "FrostSparkle" then
		ambient(main, "FrostSparkle")
	end
end

-- LANDMARK de entrada do 3: portal de gelo — duas presas inclinadas para a
-- faixa (em |z| ≥ 22) e uma verga de gelo bem acima da cabeça.
B.IceGate = function(ctx, x, _side, _z, _s, _yaw)
	for _, side in { -1, 1 } do
		spire(ctx, x, 26, side, 27, 4, 8, 0.05)
		piece(ctx, Vector3.new(7, 7, 7), at(x, 0, side * 28), C.Snow, M.Snow, false, { Shape = Enum.PartType.Ball })
		piece(ctx, Vector3.new(1.4, 6, 1.4), at(x, 22.5, side * 10) * CFrame.Angles(0, RAD(45), 0), C.Icicle, M.Ice, false, { Transparency = 0.1 })
	end
	piece(ctx, Vector3.new(5, 3, 60), at(x, 27, 0), C.Ice, M.Glacier, false, { Shadow = true })
end

-- Barreira 3 SELADA pelo gelo: blocos de gelo nas bordas, placas de gelo
-- tomando os cantos da face e a crosta por cima das fileiras.
B.IceSeal = function(ctx, x, _side, _z, _s, _yaw)
	local segment, half = ctx.Segment, ctx.Half
	for _, side in { -1, 1 } do
		piece(ctx, Vector3.new(3.4, 32, 4.4), at(x - 3, 16, side * (half - 2.2)) * CFrame.Angles(0, RAD(4 * side), 0), C.Ice, M.Ice, true, { Transparency = 0.1 })
		piece(ctx, Vector3.new(1.2, 26, 4), at(x - 0.7, 13, side * (half - 2.6)), C.Icicle, M.Ice, false, { Transparency = 0.25 })
	end
	piece(ctx, Vector3.new(segment.Depth, 3, half * 2 - 2), at(segment.Barrier + segment.Depth / 2, 32, 0), C.Ice, M.Glacier, false, { Transparency = 0.1, Shadow = true })
end

-- Indício do estágio 4 (cristal energizado): uma lasca, discreta.
B.CrystalHint = function(ctx, x, side, z, s, _yaw)
	local color = ctx.NextTheme.Trim.Color :: Color3
	piece(ctx, Vector3.new(1.6, 5, 1.6) * s, at(x, 2, side * z) * CFrame.Angles(side * RAD(-14), RAD(30), 0), color, M.Glass, false, { Transparency = 0.2 })
end

-- ── 4 Cristal energizado ────────────────────────────────────────────────────

--[[
	Prisma de cristal: corpo + ponta em CUNHA (o corte angular que o gelo não
	tem) + veio de energia atravessando as faces (Neon fino: o cristal
	continua sólido, a energia é o detalhe). `base` = centro da base, já com
	inclinação e giro. 2–3 peças por prisma.
]]
local function prism(ctx: Ctx, base: CFrame, w: number, h: number, tip: number, color: Color3, material: Enum.Material, vein: boolean): BasePart
	local body = piece(ctx, Vector3.new(w, h, w), base * CFrame.new(0, h / 2, 0), color, material, true, { Transparency = if material == M.Glass then 0.15 else 0 })
	piece(ctx, Vector3.new(w, tip, w), base * CFrame.new(0, h + tip / 2, 0), color, material, false, { Wedge = true, Transparency = if material == M.Glass then 0.15 else 0 })
	if vein then
		piece(ctx, Vector3.new(math.min(w * 0.16, 0.5), h * 0.7, w + 0.12), base * CFrame.new(0, h * 0.42, 0), C.Energy, M.Neon, false)
	end
	return body
end

-- Inclina o topo para a faixa (tilt em graus) e gira (yaw).
local function lean(x: number, z: number, side: number, tilt: number, yaw: number): CFrame
	return at(x, -0.4, side * z) * CFrame.Angles(side * RAD(-tilt), RAD(yaw), 0)
end

-- Transição 3 → 4: formação de GELO (corpo irregular, translúcido) que
-- termina em ponta de CRISTAL — o gelo virando mineral.
B.FrostCrystal = function(ctx, x, side, z, s, yaw)
	local h = 14 * s
	local base = lean(x, z, side, 10, 45 + yaw)
	piece(ctx, Vector3.new(4.4, h, 4.4) * Vector3.new(s, 1, s), base * CFrame.new(0, h / 2, 0), C.Ice, M.Ice, true, { Transparency = 0.12 })
	piece(ctx, Vector3.new(4.4 * s, 6 * s, 4.4 * s), base * CFrame.new(0, h + 3 * s, 0), C.Crystal, M.Glass, false, { Wedge = true, Transparency = 0.15 })
end

-- LANDMARK 4: formação de cristais energizados — três prismas de alturas
-- diferentes saindo de uma base de rocha, inclinados para enquadrar a
-- barreira. Só o maior tem veio (e o VFX, se a entrada pedir).
B.CrystalFormation = function(ctx, x, side, z, s, yaw)
	piece(ctx, Vector3.new(14, 3.5, 10) * s, at(x, 1, side * (z + 3)) * CFrame.Angles(0, RAD(yaw), RAD(4)), C.CrystalRock, M.Rock, true)
	local main = prism(ctx, lean(x, z + 2, side, 8, 20 + yaw), 6 * s, 30 * s, 8 * s, C.Crystal, M.Glass, true)
	prism(ctx, lean(x - 6 * s, z - 1, side, 18, -15 + yaw), 4 * s, 18 * s, 5 * s, C.CrystalDeep, M.Glass, false)
	if s >= 0.9 then
		prism(ctx, lean(x + 6 * s, z + 4, side, 4, 40 + yaw), 3.6 * s, 13 * s, 4 * s, C.Crystal, M.Glass, false)
	end
	if ctx.Fx then
		ambient(main, ctx.Fx)
	end
end

-- Cristal crescendo DA parede (metade enterrada nela), apontando para a faixa.
B.WallCrystal = function(ctx, x, side, _z, s, yaw)
	local top = wallHeight(ctx, x)
	local base = at(x, top * 0.35, side * (ctx.Half + 1)) * CFrame.Angles(side * RAD(-62), RAD(yaw), 0)
	prism(ctx, base, 4 * s, 9 * s, 4 * s, C.Crystal, M.Glass, false)
end

-- Veio de energia rachando o chão das laterais (rente: topo < 0,3).
B.CrystalVein = function(ctx, x, side, z, s, yaw)
	piece(ctx, Vector3.new(16 * s, 0.14, 0.6), at(x, 0.07, side * z) * CFrame.Angles(0, RAD(yaw * side), 0), C.Energy, M.Neon, false)
end

-- Transição 4 → 5: cristal num PEDESTAL construído, preso por uma cinta de
-- ouro — "alguém construiu ao redor dessa energia".
B.GoldBracket = function(ctx, x, side, z, s, _yaw)
	piece(ctx, Vector3.new(5, 3, 5) * s, at(x, 1.5 * s, side * z), C.Temple, M.Sandstone, true)
	prism(ctx, at(x, 3 * s, side * z) * CFrame.Angles(0, RAD(45), 0), 2.6 * s, 7 * s, 3 * s, C.Crystal, M.Glass, false)
	piece(ctx, Vector3.new(5.4, 0.7, 5.4) * s, at(x, 2.9 * s, side * z), C.Gold, M.Metal, false)
end

-- Barreira 4 ALIMENTADA pelos cristais: dois pilares de cristal com veio nas
-- bordas, linhas de energia no chão junto às paredes convergindo para eles
-- e a barra de cristal por cima das fileiras.
B.CrystalConduit = function(ctx, x, _side, _z, _s, _yaw)
	local segment, half = ctx.Segment, ctx.Half
	for _, side in { -1, 1 } do
		piece(ctx, Vector3.new(3.4, 30, 3.4), at(x - 3, 15, side * (half - 2)), C.Crystal, M.Glass, true, { Transparency = 0.15 })
		piece(ctx, Vector3.new(0.5, 22, 3.6), at(x - 3, 12, side * (half - 2)), C.Energy, M.Neon, false)
		piece(ctx, Vector3.new(26, 0.12, 0.5), at(x - 17, 0.06, side * (half - 1.5)), C.Energy, M.Neon, false)
	end
	piece(ctx, Vector3.new(6, 2.5, half * 2 - 2), at(segment.Barrier + 3, 32, 0), C.CrystalDeep, M.Glass, false, { Transparency = 0.15, Shadow = true })
end

-- ── 5 Templo dourado ────────────────────────────────────────────────────────

-- Bloco de cantaria com friso de ouro (transição 4 → 5).
B.TempleBlock = function(ctx, x, side, z, s, yaw)
	piece(ctx, Vector3.new(6, 4, 5) * s, at(x, 2 * s, side * z) * CFrame.Angles(0, RAD(yaw), 0), C.Temple, M.Sandstone, true)
	piece(ctx, Vector3.new(6.2, 0.6, 5.2) * s, at(x, 3.7 * s, side * z) * CFrame.Angles(0, RAD(yaw), 0), C.Gold, M.Metal, false)
end

-- Resto de cristal num berço de ouro (começo do 5: a energia ficou para trás).
B.GoldRemnant = function(ctx, x, side, z, s, _yaw)
	prism(ctx, at(x, 0.6, side * z) * CFrame.Angles(side * RAD(-6), RAD(45), 0), 2.4 * s, 5 * s, 2.4 * s, C.CrystalDeep, M.Glass, false)
	piece(ctx, Vector3.new(4.6, 1.2, 4.6) * s, at(x, 0.6, side * z), C.Gold, M.Metal, false)
end

-- Pilastra na parede com capitel de ouro (parede organizada do templo).
B.TemplePilaster = function(ctx, x, side, _z, s, _yaw)
	local h = wallHeight(ctx, x) - 1
	piece(ctx, Vector3.new(3.4 * s, h, 2), at(x, h / 2, side * (ctx.Half - 0.9)), C.Temple, M.Sandstone, true)
	piece(ctx, Vector3.new(4.4 * s, 1.4, 2.8), at(x, h - 1.2, side * (ctx.Half - 1.3)), C.Gold, M.Metal, false)
end

-- Nicho na parede: painel recuado escuro com moldura de ouro.
B.TempleNiche = function(ctx, x, side, _z, s, _yaw)
	piece(ctx, Vector3.new(8 * s, 12 * s, 0.6), at(x, 9 * s, side * (ctx.Half - 0.25)), C.TempleDark, M.Sandstone, false)
	piece(ctx, Vector3.new(9 * s, 0.8, 0.9), at(x, 15.4 * s, side * (ctx.Half - 0.4)), C.Gold, M.Metal, false)
end

-- Medalhão no piso da faixa (rente: topo < 0,3) — a geometria antiga.
B.FloorMedallion = function(ctx, x, _side, _z, s, _yaw)
	piece(ctx, Vector3.new(0.1, 14 * s, 14 * s), at(x, 0.05, 0) * VERTICAL, C.TempleDark, M.Sandstone, false, { Shape = Enum.PartType.Cylinder })
	piece(ctx, Vector3.new(0.16, 9 * s, 9 * s), at(x, 0.08, 0) * VERTICAL, C.Gold, M.Metal, false, { Shape = Enum.PartType.Cylinder })
end

--[[
	LANDMARK 5: PÓRTICO dourado de cada lado do caminho (simétrico — é um
	templo, preservado): duas colunas, entablamento de pedra com friso de
	ouro e o símbolo (disco de ouro) na parede ao fundo. A avenida fica livre.
]]
B.GoldenPortico = function(ctx, x, _side, _z, s, _yaw)
	local h = 26 * s
	for _, side in { -1, 1 } do
		for _, dx in { -7, 7 } do
			piece(ctx, Vector3.new(h, 4.2, 4.2), at(x + dx, h / 2, side * 31) * VERTICAL, C.Temple, M.Sandstone, true, { Shape = Enum.PartType.Cylinder, Shadow = true })
		end
		piece(ctx, Vector3.new(20, 3.6, 8), at(x, h + 1.8, side * 32), C.TempleDark, M.Sandstone, false, { Shadow = true })
		piece(ctx, Vector3.new(20.4, 1, 8.4), at(x, h + 0.4, side * 32), C.Gold, M.Metal, false)
		piece(ctx, Vector3.new(0.6, 11, 11), at(x, 18, side * (ctx.Half - 0.3)) * CFrame.Angles(0, math.pi / 2, 0), C.Gold, M.Metal, false, { Shape = Enum.PartType.Cylinder })
	end
end

-- Barreira 5: PORTÃO SELADO do templo — pilares com capitel de ouro nas
-- bordas e o frontão triangular (duas cunhas) com o símbolo de ouro acima
-- das fileiras.
B.TempleGate = function(ctx, x, _side, _z, _s, _yaw)
	local segment, half = ctx.Segment, ctx.Half
	for _, side in { -1, 1 } do
		piece(ctx, Vector3.new(4, 32, 4), at(x - 3, 16, side * (half - 2)), C.Temple, M.Sandstone, true)
		piece(ctx, Vector3.new(5, 1.6, 5), at(x - 3, 31.4, side * (half - 2.4)), C.Gold, M.Metal, false)
		-- Meio frontão: a face vertical da cunha fica no centro.
		piece(ctx, Vector3.new(4, 5, half - 1), at(segment.Barrier + 2, 33.1, side * (half - 1) / 2) * CFrame.Angles(0, if side > 0 then math.pi else 0, 0), C.TempleDark, M.Sandstone, false, { Wedge = true, Shadow = true })
	end
	piece(ctx, Vector3.new(0.5, 4.4, 4.4), at(segment.Barrier - 0.3, 32.8, 0), C.Gold, M.Metal, false, { Shape = Enum.PartType.Cylinder })
end

-- ── 6 Pedra ancestral energizada ────────────────────────────────────────────

-- Bloco ancestral pesado com UMA runa (transição 5 → 6 e paredes do 6).
B.AncientBlock = function(ctx, x, side, z, s, yaw)
	piece(ctx, Vector3.new(8, 9, 6) * s, at(x, 4.2 * s, side * z) * CFrame.Angles(0, RAD(yaw), RAD(3)), C.Ancient, M.Granite, true)
	piece(ctx, Vector3.new(0.4, 4 * s, 0.4), at(x, 5 * s, side * (z - 3 * s - 0.15)) * CFrame.Angles(0, RAD(yaw), 0), C.Rune, M.Neon, false)
end

-- Bloco enorme EMBUTIDO na parede (massa, não ornamento).
B.MassiveBlock = function(ctx, x, side, _z, s, _yaw)
	piece(ctx, Vector3.new(16 * s, 20 * s, 4), at(x, 10 * s - 0.5, side * (ctx.Half - 1)), C.AncientDark, M.Granite, true)
end

-- Sulco rúnico no chão das laterais (rente).
B.RuneGroove = function(ctx, x, side, z, s, yaw)
	piece(ctx, Vector3.new(10 * s, 0.12, 0.45), at(x, 0.06, side * z) * CFrame.Angles(0, RAD(yaw * side), 0), C.Rune, M.Neon, false)
end

--[[
	LANDMARK 6: monólito / estela ancestral — laje enorme, levemente
	inclinada, com UMA runa vertical de energia na face voltada para a faixa
	e um pé de pedra. Cada um com altura e inclinação diferentes.
]]
B.RunicMonolith = function(ctx, x, side, z, s, yaw)
	local h, w, d = 40 * s, 9 * s, 4.5 * s
	local base = at(x, -0.5, side * z) * CFrame.Angles(side * RAD(-4), RAD(yaw), RAD(3 * side))
	piece(ctx, Vector3.new(w, h, d), base * CFrame.new(0, h / 2, 0), C.AncientDark, M.Granite, true, { Shadow = true })
	piece(ctx, Vector3.new(0.6, h * 0.55, 0.3), base * CFrame.new(0, h * 0.55, -side * (d / 2 + 0.1)), C.Rune, M.Neon, false)
	piece(ctx, Vector3.new(w + 4, 2.4, d + 4), at(x, 0.8, side * z) * CFrame.Angles(0, RAD(yaw), 0), C.Ancient, M.Granite, true)
end

-- Barreira 6: SELO ANCESTRAL — duas pedras enormes nas bordas com energia
-- vazando pela face interna, e a pedra de cobertura com uma runa longa.
B.AncientSeal = function(ctx, x, _side, _z, _s, _yaw)
	local segment, half = ctx.Segment, ctx.Half
	for _, side in { -1, 1 } do
		piece(ctx, Vector3.new(4.4, 36, 4.4), at(x - 3, 17.5, side * (half - 1.8)) * CFrame.Angles(side * RAD(-2), 0, 0), C.AncientDark, M.Granite, true)
		piece(ctx, Vector3.new(0.4, 20, 0.4), at(x - 3, 10, side * (half - 4.3)), C.Rune, M.Neon, false)
	end
	piece(ctx, Vector3.new(10, 4, half * 2 + 2), at(segment.Barrier + 3, 32.5, 0), C.Ancient, M.Granite, false, { Shadow = true })
	piece(ctx, Vector3.new(0.3, 0.8, 30), at(segment.Barrier - 2.15, 32.5, 0), C.Rune, M.Neon, false)
end

-- ── Calor (indício do 7, discreto) ──────────────────────────────────────────

-- Fissura quente: pedra escurecida rente ao chão com uma linha de brasa.
B.HeatFissure = function(ctx, x, side, z, s, yaw)
	local cf = at(x, 0, side * z) * CFrame.Angles(0, RAD(yaw * side), 0)
	piece(ctx, Vector3.new(9 * s, 0.1, 3), cf * CFrame.new(0, 0.05, 0), C.Scorched, M.Basalt, false)
	piece(ctx, Vector3.new(7 * s, 0.16, 0.35), cf * CFrame.new(0, 0.08, 0), C.Heat, M.Neon, false)
end

-- Respiro quente junto da parede: pedra escura com uma fresta de brasa e
-- (se a entrada pedir) brasas raras subindo.
B.EmberVent = function(ctx, x, side, z, s, _yaw)
	local rock = piece(ctx, Vector3.new(5, 2.6, 4) * s, at(x, 1, side * z) * CFrame.Angles(0, RAD(25), RAD(5)), C.Scorched, M.Basalt, true)
	piece(ctx, Vector3.new(3 * s, 0.3, 0.3), at(x, 2.35 * s, side * z) * CFrame.Angles(0, RAD(25), 0), C.Heat, M.Neon, false)
	if ctx.Fx then
		ambient(rock, ctx.Fx)
	end
end

PowerPathDecor.Kinds = B

-- X de uma entrada do Decor: fração da área (0–1), zona de decisão (1–2) ou a barreira.
function PowerPathDecor.XFor(segment: CorridorLayout.Segment, position: number | string): number
	if position == "Barrier" then
		return segment.Barrier
	end
	local value = position :: number
	if value <= 1 then
		return segment.AreaStart + value * (segment.Barrier - segment.AreaStart)
	end
	local rowsEnd = segment.Barrier + segment.Depth
	return rowsEnd + (value - 1) * (segment.End - rowsEnd)
end

--[[
	O cenário de um estágio (Model "Decor" dentro do PowerPath_<Id>). Estágios
	sem Decor no tema não ganham nada (Fases D–E).
]]
function PowerPathDecor.Build(parent: Model, origin: Vector3, segment: CorridorLayout.Segment): Model?
	local theme = CorridorThemes.For(segment.Id)
	if #theme.Decor == 0 then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = "Decor"
	local ctx: Ctx = {
		Model = model,
		Origin = origin,
		Segment = segment,
		Theme = theme,
		NextTheme = CorridorThemes.For(CorridorThemes.Next(segment.Id)),
		Half = segment.Width / 2,
		Kind = "",
		Landmark = false,
		Fx = nil,
	}
	for _, entry in theme.Decor do
		local builder = B[entry.Kind]
		assert(builder, "PowerPathDecor: Kind desconhecido " .. entry.Kind)
		ctx.Kind = entry.Kind
		ctx.Landmark = entry.Landmark == true
		ctx.Fx = entry.Fx
		builder(ctx, PowerPathDecor.XFor(segment, entry.At), entry.Side or 1, entry.Z or 34, entry.Scale or 1, entry.Yaw or 0)
	end
	model:SetAttribute("StageId", segment.Id)
	model.Parent = parent
	return model
end

return PowerPathDecor
