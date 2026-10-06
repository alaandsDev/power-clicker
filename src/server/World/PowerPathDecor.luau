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
	-- Vulcânico (7): basalto, crosta quente.
	Basalt = Color3.fromRGB(50, 42, 40),
	BasaltDark = Color3.fromRGB(34, 29, 28),
	Crust = Color3.fromRGB(96, 38, 22),
	-- Magma cristalizado (8): rocha negra, cristal vermelho, núcleo laranja.
	BlackRock = Color3.fromRGB(26, 22, 22),
	MagmaCrystal = Color3.fromRGB(150, 26, 30),
	MagmaDeep = Color3.fromRGB(96, 16, 22),
	MagmaFlow = Color3.fromRGB(176, 58, 22),
	MagmaCore = Color3.fromRGB(255, 132, 40),
	-- Energia (9): grafite, azul profundo, violeta; energia violeta-branca.
	Graphite = Color3.fromRGB(32, 32, 42),
	Void = Color3.fromRGB(44, 30, 64),
	DeepBlue = Color3.fromRGB(38, 42, 82),
	Pulse = Color3.fromRGB(186, 140, 255),
	-- Colosso (10): pedra monumental escura + marfim mineral pesado, ouro
	-- antigo só em faixas finas, energia branco-dourada (a assinatura do fim).
	Monument = Color3.fromRGB(62, 62, 70),
	MonumentDark = Color3.fromRGB(44, 44, 52),
	Ivory = Color3.fromRGB(210, 202, 182),
	OldGold = Color3.fromRGB(178, 138, 60),
	Supreme = Color3.fromRGB(255, 236, 190),
	-- Portal do futuro: energia violeta profunda (ecoa o 9, sem ser ele).
	Future = Color3.fromRGB(150, 110, 255),
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
type Preset = { Rate: number, Life: NumberRange, Speed: NumberRange, Spread: number, Size: number, Color: Color3, Light: number, Accel: Vector3?, Texture: string?, Grow: number?, Fade: number? }
local PRESETS: { [string]: Preset } = {
	FrostSparkle = { Rate = 5, Life = NumberRange.new(1.4, 2.4), Speed = NumberRange.new(0.3, 1.2), Spread = 180, Size = 0.5, Color = C.Icicle, Light = 0.6 },
	-- Motes de energia subindo devagar dos cristais (estágio 4).
	CrystalMotes = { Rate = 4, Life = NumberRange.new(2.5, 3.5), Speed = NumberRange.new(0.6, 1.4), Spread = 25, Size = 0.35, Color = Color3.fromRGB(150, 236, 255), Light = 0.8 },
	-- Brasas raras no fim do 6: o primeiro sinal do vulcânico.
	Embers = { Rate = 3, Life = NumberRange.new(1.8, 2.8), Speed = NumberRange.new(1, 2.2), Spread = 20, Size = 0.25, Color = Color3.fromRGB(255, 130, 50), Light = 1, Accel = Vector3.new(0, 0.8, 0) },
	-- Fumaça MUITO controlada do respiro vulcânico (7): pouca, lenta, escura.
	Smoke = { Rate = 1.2, Life = NumberRange.new(4, 6), Speed = NumberRange.new(0.8, 1.6), Spread = 12, Size = 3, Grow = 7, Fade = 0.8, Color = Color3.fromRGB(58, 50, 48), Light = 0, Accel = Vector3.new(0, 0.4, 0), Texture = "rbxasset://textures/particles/smoke_main.dds" },
	-- Faíscas de magma subindo do cristal maior (8).
	MagmaSparks = { Rate = 5, Life = NumberRange.new(1.2, 2), Speed = NumberRange.new(1.5, 3), Spread = 30, Size = 0.3, Color = Color3.fromRGB(255, 120, 40), Light = 1, Accel = Vector3.new(0, 1.2, 0) },
	-- Motes branco-dourados subindo devagar do selo do Colosso (10).
	SealMotes = { Rate = 3, Life = NumberRange.new(3, 4.5), Speed = NumberRange.new(0.4, 1), Spread = 40, Size = 0.4, Color = Color3.fromRGB(255, 232, 180), Light = 0.9 },
	-- Motes violeta em volta do portal do futuro (inerte).
	PortalMotes = { Rate = 4, Life = NumberRange.new(2.5, 4), Speed = NumberRange.new(0.2, 0.7), Spread = 180, Size = 0.4, Color = Color3.fromRGB(190, 160, 255), Light = 0.9 },
	-- Motes de energia pairando em volta do arco flutuante (9): devagar, em todas as direções.
	EnergyMotes = { Rate = 4, Life = NumberRange.new(3, 4.5), Speed = NumberRange.new(0.2, 0.6), Spread = 180, Size = 0.35, Color = Color3.fromRGB(200, 170, 255), Light = 0.9 },
}

local function ambient(owner: BasePart, presetName: string)
	local preset = PRESETS[presetName]
	assert(preset, "PowerPathDecor: VFX ambiental desconhecido " .. presetName)
	local fx = Instance.new("ParticleEmitter")
	fx.Name = presetName
	fx.Enabled = false
	fx.Texture = preset.Texture or "rbxasset://textures/particles/sparkles_main.dds"
	fx.Rate = preset.Rate
	fx.Lifetime = preset.Life
	fx.Speed = preset.Speed
	fx.SpreadAngle = Vector2.new(preset.Spread, preset.Spread)
	fx.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, preset.Size), NumberSequenceKeypoint.new(1, preset.Grow or 0) })
	fx.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, preset.Fade or 0.3), NumberSequenceKeypoint.new(1, 1) })
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
local function prism(ctx: Ctx, base: CFrame, w: number, h: number, tip: number, color: Color3, material: Enum.Material, vein: boolean, veinColor: Color3?): BasePart
	local body = piece(ctx, Vector3.new(w, h, w), base * CFrame.new(0, h / 2, 0), color, material, true, { Transparency = if material == M.Glass then 0.15 else 0 })
	piece(ctx, Vector3.new(w, tip, w), base * CFrame.new(0, h + tip / 2, 0), color, material, false, { Wedge = true, Transparency = if material == M.Glass then 0.15 else 0 })
	if vein then
		piece(ctx, Vector3.new(math.min(w * 0.16, 0.5), h * 0.7, w + 0.12), base * CFrame.new(0, h * 0.42, 0), veinColor or C.Energy, M.Neon, false)
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

-- ── 7 Rocha vulcânica ───────────────────────────────────────────────────────

-- Fissura quente que corta o chão (rente; pode cruzar a faixa VISUALMENTE,
-- topo < 0,3): crosta escura + linha de brasa. Sem colisão, sem hazard.
B.LavaCrack = function(ctx, x, side, z, s, yaw)
	local cf = at(x, 0, side * z) * CFrame.Angles(0, RAD(yaw * side), 0)
	piece(ctx, Vector3.new(16 * s, 0.1, 2.4 * s), cf * CFrame.new(0, 0.05, 0), C.Crust, M.CrackedLava, false)
	piece(ctx, Vector3.new(14 * s, 0.16, 0.35), cf * CFrame.new(0, 0.08, 0), C.Heat, M.Neon, false)
end

-- Ponta de basalto (prisma sem veio).
B.VolcanicSpire = function(ctx, x, side, z, s, yaw)
	prism(ctx, lean(x, z, side, 12, yaw), 4.5 * s, 16 * s, 6 * s, C.Basalt, M.Basalt, false)
end

-- Colunas de basalto saindo da parede (camadas de rocha, alturas diferentes).
B.BasaltColumns = function(ctx, x, side, _z, s, _yaw)
	local top = wallHeight(ctx, x)
	for index, f in { 0.5, 0.78, 0.62 } do
		local h = top * f * s
		piece(ctx, Vector3.new(h, 4, 4), at(x + (index - 2) * 4, h / 2, side * (ctx.Half - 1.5)) * VERTICAL, if index == 2 then C.BasaltDark else C.Basalt, M.Basalt, true, { Shape = Enum.PartType.Cylinder })
	end
end

--[[
	LANDMARK 7: paredão de rocha vulcânica QUEBRADO — duas lajes enormes de
	basalto inclinadas (como se o Caminho tivesse rachado a montanha), duas
	pontas e uma fissura quente subindo pela face. Faz o jogador parecer
	pequeno; a avenida fica livre.
]]
B.VolcanicCliff = function(ctx, x, side, z, s, yaw)
	local h1 = 34 * s
	local slab = at(x, -0.5, side * (z + 4)) * CFrame.Angles(side * RAD(-8), RAD(yaw), RAD(4 * side))
	local main = piece(ctx, Vector3.new(14 * s, h1, 7), slab * CFrame.new(0, h1 / 2, 0), C.Basalt, M.Basalt, true, { Shadow = true })
	piece(ctx, Vector3.new(0.5, h1 * 0.65, 0.3), slab * CFrame.new(1.5, h1 * 0.45, -side * 3.6), C.Heat, M.Neon, false)
	local h2 = 26 * s
	piece(ctx, Vector3.new(10 * s, h2, 6), at(x + 9 * s, -0.5, side * (z + 1)) * CFrame.Angles(side * RAD(-14), RAD(-yaw - 10), 0) * CFrame.new(0, h2 / 2, 0), C.BasaltDark, M.Basalt, true, { Shadow = true })
	prism(ctx, lean(x - 7 * s, z - 1, side, 18, 25 + yaw), 4 * s, 18 * s, 6 * s, C.BasaltDark, M.Basalt, false)
	prism(ctx, lean(x + 3 * s, z + 8, side, 6, -20 + yaw), 5 * s, 26 * s, 8 * s, C.Basalt, M.Basalt, false)
	if ctx.Fx then
		ambient(main, ctx.Fx)
	end
end

-- Respiro vulcânico junto da parede: monte de basalto com fresta quente e,
-- se a entrada pedir, um fio de fumaça controlada.
B.VolcanicVent = function(ctx, x, side, z, s, _yaw)
	local mound = piece(ctx, Vector3.new(8, 3, 7) * s, at(x, 1, side * z) * CFrame.Angles(0, RAD(15), RAD(4)), C.BasaltDark, M.Basalt, true)
	piece(ctx, Vector3.new(5 * s, 0.3, 0.35), at(x, 2.55 * s, side * z) * CFrame.Angles(0, RAD(15), 0), C.Heat, M.Neon, false)
	if ctx.Fx then
		ambient(mound, ctx.Fx)
	end
end

-- Barreira 7: MASSA DE ROCHA VULCÂNICA — dois blocos de basalto com pontas
-- nas bordas, fissura quente na face interna, laje bruta por cima das
-- fileiras com uma veia de brasa.
B.VolcanicGate = function(ctx, x, _side, _z, _s, _yaw)
	local segment, half = ctx.Segment, ctx.Half
	for _, side in { -1, 1 } do
		piece(ctx, Vector3.new(4.4, 34, 4.4), at(x - 3, 17, side * (half - 2)) * CFrame.Angles(0, RAD(5 * side), 0), C.Basalt, M.Basalt, true)
		piece(ctx, Vector3.new(4.4, 8, 4.4), at(x - 3, 38, side * (half - 2)) * CFrame.Angles(0, if side > 0 then math.pi else 0, 0), C.BasaltDark, M.Basalt, false, { Wedge = true })
		piece(ctx, Vector3.new(0.4, 18, 0.4), at(x - 3, 9, side * (half - 4.4)), C.Heat, M.Neon, false)
	end
	piece(ctx, Vector3.new(8, 4, half * 2), at(segment.Barrier + 3, 32.5, 0), C.BasaltDark, M.Basalt, false, { Shadow = true })
	piece(ctx, Vector3.new(0.3, 0.6, 50), at(segment.Barrier - 1.15, 32.5, 0), C.Heat, M.Neon, false)
end

-- ── 8 Magma cristalizado ────────────────────────────────────────────────────

-- Transição 7 → 8: o primeiro cristal vermelho rompendo o basalto.
B.MagmaShard = function(ctx, x, side, z, s, _yaw)
	piece(ctx, Vector3.new(4.4, 2, 4) * s, at(x, 0.8, side * z) * CFrame.Angles(RAD(6), RAD(30), 0), C.BasaltDark, M.Basalt, true)
	prism(ctx, at(x, 1, side * z) * CFrame.Angles(side * RAD(-10), RAD(40), 0), 2.6 * s, 6 * s, 2.6 * s, C.MagmaCrystal, M.Glass, false)
end

--[[
	LANDMARK 8: formação de CRISTAL DE MAGMA que rompeu o chão — duas lajes de
	rocha negra levantadas, um cristal vermelho enorme com núcleo laranja
	(veio) e cristais menores. Magma = corpo quente + linha brilhante.
]]
B.MagmaFormation = function(ctx, x, side, z, s, yaw)
	for index, dx in { -5, 6 } do
		piece(ctx, Vector3.new(10 * s, 3, 6 * s), at(x + dx * s, 0.6, side * (z - 2)) * CFrame.Angles(side * RAD(if index == 1 then 25 else 18), RAD(yaw + index * 20), 0), C.BlackRock, M.Basalt, true)
	end
	local main = prism(ctx, lean(x, z + 2, side, 10, 15 + yaw), 6.5 * s, 30 * s, 9 * s, C.MagmaCrystal, M.Glass, true, C.MagmaCore)
	prism(ctx, lean(x - 6 * s, z - 2, side, 22, -20 + yaw), 4 * s, 17 * s, 5 * s, C.MagmaDeep, M.Glass, false)
	if s >= 0.9 then
		prism(ctx, lean(x + 6 * s, z + 5, side, 6, 35 + yaw), 4.5 * s, 22 * s, 6 * s, C.MagmaCrystal, M.Glass, false)
	end
	if ctx.Fx then
		ambient(main, ctx.Fx)
	end
end

-- Magma correndo entre as formações (rente): crosta quente + núcleo.
B.MagmaFlow = function(ctx, x, side, z, s, yaw)
	local cf = at(x, 0, side * z) * CFrame.Angles(0, RAD(yaw * side), 0)
	piece(ctx, Vector3.new(18 * s, 0.12, 3), cf * CFrame.new(0, 0.06, 0), C.MagmaFlow, M.CrackedLava, false)
	piece(ctx, Vector3.new(16 * s, 0.18, 0.5), cf * CFrame.new(0, 0.09, 0), C.MagmaCore, M.Neon, false)
end

-- Parede de rocha negra vazando magma (e, grande, um cristal crescendo dela).
B.WallMagma = function(ctx, x, side, _z, s, yaw)
	local top = wallHeight(ctx, x)
	piece(ctx, Vector3.new(3, top * 0.6, 0.4), at(x, top * 0.3, side * (ctx.Half - 0.2)), C.MagmaFlow, M.CrackedLava, false)
	piece(ctx, Vector3.new(0.4, top * 0.5, 0.3), at(x, top * 0.32, side * (ctx.Half - 0.45)), C.MagmaCore, M.Neon, false)
	if s >= 1 then
		prism(ctx, at(x + 5, top * 0.3, side * (ctx.Half + 1)) * CFrame.Angles(side * RAD(-60), RAD(yaw), 0), 4, 9, 4, C.MagmaCrystal, M.Glass, false)
	end
end

-- Barreira 8: MAGMA CRISTALIZADO bloqueando — pilares de cristal vermelho
-- com núcleo laranja nas bordas e a laje de rocha negra rachada por cima.
B.MagmaSeal = function(ctx, x, _side, _z, _s, _yaw)
	local segment, half = ctx.Segment, ctx.Half
	for _, side in { -1, 1 } do
		piece(ctx, Vector3.new(3.6, 30, 3.6), at(x - 3, 15, side * (half - 2)), C.MagmaCrystal, M.Glass, true, { Transparency = 0.15 })
		piece(ctx, Vector3.new(3.6, 7, 3.6), at(x - 3, 33.5, side * (half - 2)) * CFrame.Angles(0, if side > 0 then math.pi else 0, 0), C.MagmaDeep, M.Glass, false, { Wedge = true, Transparency = 0.15 })
		piece(ctx, Vector3.new(0.45, 20, 3.8), at(x - 3, 11, side * (half - 2)), C.MagmaCore, M.Neon, false)
	end
	piece(ctx, Vector3.new(8, 4, half * 2), at(segment.Barrier + 3, 32.5, 0), C.BlackRock, M.Basalt, false, { Shadow = true })
	piece(ctx, Vector3.new(0.3, 0.6, 60), at(segment.Barrier - 1.15, 32.5, 0), C.MagmaCore, M.Neon, false)
end

-- Transição 8 → 9: cristal ESCURECENDO, o veio já é de outra energia (fria).
B.DarkCrystal = function(ctx, x, side, z, s, yaw)
	prism(ctx, lean(x, z, side, 14, 30 + yaw), 3.6 * s, 14 * s, 5 * s, C.Void, M.Glass, true, C.Pulse)
end

-- Linha de energia no chão (rente) sobre placa escura: substitui a fissura.
B.EnergyLine = function(ctx, x, side, z, s, yaw)
	local cf = at(x, 0, side * z) * CFrame.Angles(0, RAD(yaw * side), 0)
	piece(ctx, Vector3.new(16 * s, 0.08, 2), cf * CFrame.new(0, 0.04, 0), C.Graphite, M.Slate, false)
	piece(ctx, Vector3.new(14 * s, 0.12, 0.4), cf * CFrame.new(0, 0.07, 0), C.Pulse, M.Neon, false)
end

-- ── 9 Energia / cósmico ─────────────────────────────────────────────────────

-- Circuito atravessando a faixa (rente): uma "interrupção" visual do
-- Caminho — placa escura + linha de energia. O piso físico continua inteiro.
B.EnergyCircuit = function(ctx, x, _side, _z, s, _yaw)
	piece(ctx, Vector3.new(2.4 * s, 0.06, ctx.Half * 2 - 10), at(x, 0.03, 0), C.Graphite, M.Slate, false)
	piece(ctx, Vector3.new(0.4, 0.1, 20), at(x, 0.05, 0), C.Pulse, M.Neon, false)
end

-- Painel recuado na parede com uma linha vertical de energia.
B.EnergyPanel = function(ctx, x, side, _z, s, _yaw)
	local top = wallHeight(ctx, x)
	piece(ctx, Vector3.new(6 * s, top * 0.7, 0.6), at(x, top * 0.4, side * (ctx.Half - 0.3)), C.DeepBlue, M.Metal, false)
	piece(ctx, Vector3.new(0.4, top * 0.4, 0.3), at(x, top * 0.4, side * (ctx.Half - 0.7)), C.Pulse, M.Neon, false)
end

-- Estrutura INTERROMPIDA: um trecho de parede cuja parte de cima se soltou
-- e flutua, com a energia segurando o vão.
B.BrokenWall = function(ctx, x, side, _z, s, _yaw)
	local z = side * (ctx.Half - 2)
	piece(ctx, Vector3.new(12 * s, 16, 3), at(x, 8, z), C.Graphite, M.Metal, true)
	piece(ctx, Vector3.new(12 * s, 8, 3), at(x, 24.5, z) * CFrame.Angles(side * RAD(-5), 0, RAD(4)), C.Graphite, M.Metal, false, { Shadow = true })
	piece(ctx, Vector3.new(11 * s, 0.4, 0.4), at(x, 18.2, z - side * 1.2), C.Pulse, M.Neon, false)
end

--[[
	LANDMARK 9: ARCO FLUTUANTE — a base de um pilar continua no chão, mas os
	blocos de cima e metade da verga se desprenderam e estão suspensos por
	energia (feixes finos entre as peças), cada vez mais inclinados. Só
	visual: nenhuma peça é plataforma, nada é alcançável, a avenida é livre.
]]
B.FloatingArch = function(ctx, x, side, z, s, yaw)
	local stubH = 10 * s
	piece(ctx, Vector3.new(7, stubH, 7), at(x, stubH / 2, side * z) * CFrame.Angles(0, RAD(yaw), 0), C.Graphite, M.Metal, true)
	local y1 = stubH + 4
	local c1h = 8 * s
	local chunk1 = piece(ctx, Vector3.new(6.4, c1h, 6.4), at(x, y1 + c1h / 2, side * z) * CFrame.Angles(side * RAD(-6), RAD(yaw + 12), RAD(3)), C.DeepBlue, M.Metal, false, { Shadow = true })
	local y2 = y1 + c1h + 3
	local c2h = 6 * s
	piece(ctx, Vector3.new(5.4, c2h, 5.4), at(x + 0.6, y2 + c2h / 2, side * (z + 0.5)) * CFrame.Angles(side * RAD(-14), RAD(yaw - 15), RAD(-6)), C.Graphite, M.Metal, false)
	local y3 = y2 + c2h + 5
	piece(ctx, Vector3.new(5, 4, 20), at(x - 1, y3 + 2, side * (z - 6)) * CFrame.Angles(side * RAD(8), RAD(yaw + 6), RAD(5)), C.DeepBlue, M.Metal, false, { Shadow = true })
	for _, beam in { { stubH, y1 }, { y1 + c1h, y2 }, { y2 + c2h, y3 } } do
		local gap = beam[2] - beam[1]
		piece(ctx, Vector3.new(0.4, gap, 0.4), at(x, beam[1] + gap / 2, side * z), C.Pulse, M.Neon, false)
	end
	if ctx.Fx then
		ambient(chunk1, ctx.Fx)
	end
end

-- Fragmentos soltos pairando junto da parede (estáticos: a composição vende
-- a gravidade estranha; nada se mexe, nada custa por quadro).
B.FloatingShards = function(ctx, x, side, z, s, _yaw)
	for index, spec in { { 0, 18, 0 }, { 5, 24, 3 }, { -4, 29, -2 } } do
		local size = (3.2 - index * 0.5) * s
		piece(ctx, Vector3.new(size, size * 1.4, size), at(x + spec[1], spec[2], side * (z + spec[3])) * CFrame.Angles(RAD(20 * index), RAD(35 * index), RAD(-15 * index)), if index == 2 then C.DeepBlue else C.Graphite, M.Metal, false)
	end
end

-- Barreira 9: CONTENÇÃO DE ENERGIA — pilones escuros com anéis de energia
-- nas bordas e a viga de contenção por cima com uma linha de energia.
-- (Contido de propósito: a 10 é o grande momento.)
B.EnergyContainment = function(ctx, x, _side, _z, _s, _yaw)
	local segment, half = ctx.Segment, ctx.Half
	for _, side in { -1, 1 } do
		local z = side * (half - 2)
		piece(ctx, Vector3.new(4.4, 36, 4.4), at(x - 3, 18, z), C.Graphite, M.Metal, true)
		for _, y in { 10, 24 } do
			piece(ctx, Vector3.new(5.2, 0.5, 5.2), at(x - 3, y, z), C.Pulse, M.Neon, false)
		end
	end
	piece(ctx, Vector3.new(6, 3, half * 2), at(segment.Barrier + 3, 32, 0), C.Graphite, M.Metal, false, { Shadow = true })
	piece(ctx, Vector3.new(0.3, 0.5, 40), at(segment.Barrier - 0.15, 32, 0), C.Pulse, M.Neon, false)
end

-- Pré-10: energia CONVERGINDO para frente no fim do trecho (rente).
B.ConvergenceLines = function(ctx, x, _side, _z, s, _yaw)
	for _, side in { -1, 1 } do
		piece(ctx, Vector3.new(7 * s, 0.12, 0.4), at(x, 0.06, side * 11) * CFrame.Angles(0, RAD(-40 * side), 0), C.Pulse, M.Neon, false)
	end
end

-- Pré-10: pilones enormes no fim do trecho, MAIS ALTOS que as paredes e
-- abrindo para fora — a escala começa a mudar ("tem algo grande depois").
B.OpeningPylon = function(ctx, x, side, _z, s, _yaw)
	local h = 64 * s
	local base = at(x, -0.5, side * (ctx.Half + 1)) * CFrame.Angles(side * RAD(5), 0, 0)
	piece(ctx, Vector3.new(4, h, 4), base * CFrame.new(0, h / 2, 0), C.Graphite, M.Metal, true, { Shadow = true })
	piece(ctx, Vector3.new(0.4, h * 0.45, 0.3), base * CFrame.new(0, h * 0.62, -side * 2.15), C.Pulse, M.Neon, false)
end

-- ── 10 Colosso (o DESTINO) ──────────────────────────────────────────────────
--[[
	O 10 não é "o 9 + um tema": é o fim do corredor. Poucas formas GRANDES,
	espaço negativo e uma escala que cresce até a barreira: soleira que abre
	o corredor → contrafortes → massas escalonadas → obeliscos → paredes que
	sobem → o PORTÃO DO COLOSSO (duas torres, verga colossal e o selo). Tudo
	ao REDOR do volume lógico da barreira (as fileiras não mudam).
]]

-- Transição 9 → 10: o corredor de 86 studs ABRE para os 138 do Colosso —
-- dois blocos escalonados fecham o canto e mostram que o espaço cresceu.
B.ColossusThreshold = function(ctx, x, _side, _z, s, _yaw)
	for _, side in { -1, 1 } do
		piece(ctx, Vector3.new(8, 50 * s, 30), at(x, 25 * s - 0.5, side * 62), C.Monument, M.Slate, true, { Shadow = true })
		piece(ctx, Vector3.new(6, 12 * s, 20), at(x + 1, 50 * s + 6 * s - 0.5, side * 66), C.Ivory, M.Marble, false, { Shadow = true })
	end
end

-- Linha de ouro no piso (rente), diagonal, conduzindo para a faixa.
B.GoldInlay = function(ctx, x, side, z, s, yaw)
	piece(ctx, Vector3.new(40 * s, 0.1, 0.8), at(x, 0.05, side * z) * CFrame.Angles(0, RAD(yaw * side), 0), C.OldGold, M.Metal, false)
end

-- Contraforte monumental na parede: massa de pedra + topo em rampa.
B.Buttress = function(ctx, x, side, _z, s, _yaw)
	local h = 40 * s
	local z = side * (ctx.Half - 4)
	piece(ctx, Vector3.new(12 * s, h, 8), at(x, h / 2 - 0.5, z), C.MonumentDark, M.Slate, true, { Shadow = true })
	piece(ctx, Vector3.new(12 * s, 12 * s, 8), at(x, h + 6 * s - 0.5, z) * CFrame.Angles(0, if side > 0 then math.pi else 0, 0), C.Ivory, M.Marble, false, { Wedge = true })
end

-- Massa escalonada (três degraus de marfim sobre pedra) com uma faixa de ouro.
B.StepMass = function(ctx, x, side, _z, s, _yaw)
	local tiers = { { 26, 20, 12 }, { 20, 16, 9 }, { 13, 12, 6 } }
	local y = -0.5
	for index, t in tiers do
		local len, h, depth = t[1] * s, t[2] * s, t[3]
		piece(ctx, Vector3.new(len, h, depth), at(x, y + h / 2, side * (ctx.Half - depth / 2)), if index == 1 then C.MonumentDark else C.Ivory, if index == 1 then M.Slate else M.Marble, true, { Shadow = true })
		y += h
	end
	piece(ctx, Vector3.new(26.4 * s, 1.2, 12.4), at(x, 20 * s - 0.5, side * (ctx.Half - 6)), C.OldGold, M.Metal, false)
end

-- Obelisco de marfim com pirâmide de ouro: vertical, conduz o olho para cima.
B.Obelisk = function(ctx, x, side, z, s, _yaw)
	local h = 56 * s
	piece(ctx, Vector3.new(6, h, 6), at(x, h / 2 - 0.5, side * z), C.Ivory, M.Marble, true, { Shadow = true })
	piece(ctx, Vector3.new(6, 6 * s, 6), at(x, h + 3 * s - 0.5, side * z), C.OldGold, M.Metal, false, { Wedge = true })
end

-- A parede SOBE perto do portão (um bloco escalonado por cima da parede).
B.WallRise = function(ctx, x, side, _z, s, _yaw)
	local top = wallHeight(ctx, x)
	local h = 20 * s
	piece(ctx, Vector3.new(50, h, 7), at(x, top + 1 + h / 2, side * (ctx.Half + 4.5)), C.Monument, M.Slate, true, { Shadow = true })
end

--[[
	O SELO DO COLOSSO: um símbolo próprio do Caminho do Poder — anel (discos
	escuro/marfim/escuro), um losango de ouro e a LÂMINA de energia no meio
	(a espada que trouxe o jogador até aqui). `vertical` = na verga.
]]
local function sigil(ctx: Ctx, cf: CFrame, s: number, vertical: boolean): BasePart
	local disc = if vertical then CFrame.identity else VERTICAL
	local step = if vertical then function(i: number) return CFrame.new(-i * 0.12, 0, 0) end else function(i: number) return CFrame.new(i * 0.03, 0, 0) end
	piece(ctx, Vector3.new(0.1, 26 * s, 26 * s), cf * disc * step(0), C.MonumentDark, M.Slate, false, { Shape = Enum.PartType.Cylinder })
	piece(ctx, Vector3.new(0.1, 21 * s, 21 * s), cf * disc * step(1), C.Ivory, M.Marble, false, { Shape = Enum.PartType.Cylinder })
	piece(ctx, Vector3.new(0.1, 17 * s, 17 * s), cf * disc * step(2), C.MonumentDark, M.Slate, false, { Shape = Enum.PartType.Cylinder })
	local diamond = if vertical then CFrame.new(-0.4, 0, 0) * CFrame.Angles(math.rad(45), 0, 0) else CFrame.new(0, 0.12, 0) * CFrame.Angles(0, math.rad(45), 0)
	piece(ctx, if vertical then Vector3.new(0.2, 9 * s, 9 * s) else Vector3.new(9 * s, 0.1, 9 * s), cf * diamond, C.OldGold, M.Metal, false)
	return piece(ctx, if vertical then Vector3.new(0.3, 15 * s, 0.5) else Vector3.new(15 * s, 0.14, 0.5), cf * (if vertical then CFrame.new(-0.6, 0, 0) else CFrame.new(0, 0.15, 0)), C.Supreme, M.Neon, false)
end

-- O selo no piso da faixa (rente: topo < 0,3).
B.ColossusSigil = function(ctx, x, _side, _z, s, _yaw)
	sigil(ctx, at(x, 0.05, 0), s, false)
end

-- Energia branco-dourada correndo no piso para o selo (rente).
B.SealLines = function(ctx, x, _side, _z, s, _yaw)
	for _, side in { -1, 1 } do
		piece(ctx, Vector3.new(34 * s, 0.12, 0.4), at(x, 0.06, side * 24) * CFrame.Angles(0, RAD(-10 * side), 0), C.Supreme, M.Neon, false)
	end
end

--[[
	LANDMARK 10 / BARREIRA 10: o PORTÃO DO COLOSSO — duas torres enormes
	(passando de 90 studs) nas bordas, recuadas em cima e com uma faixa de
	ouro, energia na face interna; a verga colossal por cima das fileiras
	com a coroa escalonada e o SELO vertical (com a única luz nova do fim).
	A barreira fica SELADA dentro da arquitetura; a frente dela (placa de HP,
	golpe, Corte, rachaduras) continua livre.
]]
B.ColossusGate = function(ctx, x, _side, _z, _s, _yaw)
	local segment, half = ctx.Segment, ctx.Half
	for _, side in { -1, 1 } do
		local z = side * (half + 2.1)
		piece(ctx, Vector3.new(16, 84, 13.6), at(x - 8, 41.5, z), C.MonumentDark, M.Slate, true, { Shadow = true })
		piece(ctx, Vector3.new(14, 30, 10), at(x - 6, 98.5, side * (half + 3.8)), C.Ivory, M.Marble, false, { Shadow = true })
		piece(ctx, Vector3.new(16.4, 2, 13.8), at(x - 8, 62, z), C.OldGold, M.Metal, false)
		piece(ctx, Vector3.new(0.5, 48, 0.3), at(x - 4, 26, side * (half - 4.75)), C.Supreme, M.Neon, false)
	end
	-- Verga colossal + coroa (acima das fileiras e do arco; nada abaixo de y 60).
	piece(ctx, Vector3.new(24, 18, half * 2 + 16), at(segment.Barrier, 71, 0), C.Monument, M.Slate, false, { Shadow = true })
	piece(ctx, Vector3.new(24.4, 1.4, half * 2 + 16.4), at(segment.Barrier, 62.6, 0), C.OldGold, M.Metal, false)
	piece(ctx, Vector3.new(18, 22, 54), at(segment.Barrier + 2, 91, 0), C.Ivory, M.Marble, false, { Shadow = true })
	local core = sigil(ctx, at(segment.Barrier - 12.1, 71, 0), 0.62, true)
	local light = Instance.new("PointLight")
	light.Color = C.Supreme
	light.Range = 48
	light.Brightness = 1.2
	light.Shadows = false
	light.Parent = core
	if ctx.Fx then
		ambient(core, ctx.Fx)
	end
end

-- Atrás das fileiras: o "outro lado" do portão (atravessar o Colosso).
B.ColossusRear = function(ctx, x, _side, _z, s, _yaw)
	for _, side in { -1, 1 } do
		piece(ctx, Vector3.new(12, 48 * s, 13.6), at(x, 24 * s - 0.5, side * (ctx.Half + 2.1)), C.MonumentDark, M.Slate, true, { Shadow = true })
	end
end

-- Zona de decisão final: duas linhas de ouro rentes ao longo da moldura.
B.DecisionGold = function(ctx, x, _side, _z, _s, _yaw)
	local segment = ctx.Segment
	local length = (segment.ReturnX - segment.PadsX) + 30
	for _, side in { -1, 1 } do
		piece(ctx, Vector3.new(length, 0.1, 0.8), at((segment.PadsX + segment.ReturnX) / 2, 0.05, side * (ctx.Half - 4)), C.OldGold, M.Metal, false)
	end
	local _ = x
end

-- ── Final atual (praça depois do Colosso) ───────────────────────────────────

-- Estela calma no caminho do portal: marfim com topo de ouro.
B.CalmStele = function(ctx, x, side, z, s, _yaw)
	piece(ctx, Vector3.new(3, 9 * s, 3), at(x, 4.5 * s - 0.5, side * z), C.Ivory, M.Marble, true)
	piece(ctx, Vector3.new(3.4, 0.6, 3.4), at(x, 9 * s - 0.2, side * z), C.OldGold, M.Metal, false)
end

-- Círculo no piso diante do portal (rente): o "fim do Caminho" atual.
B.PortalGlyph = function(ctx, x, _side, _z, s, _yaw)
	piece(ctx, Vector3.new(0.08, 30 * s, 30 * s), at(x, 0.04, 0) * VERTICAL, C.MonumentDark, M.Slate, false, { Shape = Enum.PartType.Cylinder })
	piece(ctx, Vector3.new(0.12, 25 * s, 25 * s), at(x, 0.06, 0) * VERTICAL, C.Ivory, M.Marble, false, { Shape = Enum.PartType.Cylinder })
	piece(ctx, Vector3.new(0.16, 22 * s, 22 * s), at(x, 0.08, 0) * VERTICAL, C.Monument, M.Slate, false, { Shape = Enum.PartType.Cylinder })
end

--[[
	PORTAL DO FUTURO (moldura): estrutura antiga — dois pilares com base, a
	verga — e fragmentos soltos com energia violeta (o 9 ecoando: "o caminho
	continua além"). MENOR que o Portão do Colosso de propósito: o Colosso é
	o clímax, o portal é o mistério. Inerte: sem toque, sem prompt.
]]
B.FuturePortal = function(ctx, x, _side, _z, s, _yaw)
	for _, side in { -1, 1 } do
		piece(ctx, Vector3.new(6, 44 * s, 6), at(x, 22 * s - 0.5, side * 25), C.MonumentDark, M.Slate, true, { Shadow = true })
		piece(ctx, Vector3.new(7, 3, 8), at(x, 1, side * 25), C.Ivory, M.Marble, true)
		piece(ctx, Vector3.new(0.4, 30 * s, 0.3), at(x - 3.1, 22 * s, side * 22.6), C.Future, M.Neon, false)
	end
	local lintel = piece(ctx, Vector3.new(7, 6, 60), at(x, 44 * s + 2.5, 0), C.Monument, M.Slate, false, { Shadow = true })
	for index, spec in { { -32, 34 }, { 33, 39 }, { -33, 45 } } do
		piece(ctx, Vector3.new(3, 4, 3), at(x - 1, spec[2], spec[1]) * CFrame.Angles(RAD(20 * index), RAD(30 * index), RAD(-12 * index)), C.MonumentDark, M.Slate, false)
	end
	if ctx.Fx then
		ambient(lintel, ctx.Fx)
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
	sem Decor no tema não ganham nada (Fase E: o Colosso).
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

--[[
	O cenário da praça final (Model "Decor" dentro do PowerPath_Final): a
	área de conclusão e a moldura do portal (CorridorThemes.Final). `At` é a
	fração da praça (0 = depois dos pads do Colosso, 1 = o fundo).
]]
function PowerPathDecor.BuildFinal(parent: Model, origin: Vector3): Model?
	local final = CorridorThemes.Final
	if #final.Decor == 0 then
		return nil
	end
	local segments = CorridorLayout.Segments()
	local last = segments[#segments]
	local start = CorridorLayout.FinalStart()
	local model = Instance.new("Model")
	model.Name = "Decor"
	local ctx: Ctx = {
		Model = model,
		Origin = origin,
		Segment = last,
		Theme = CorridorThemes.For(last.Id),
		NextTheme = CorridorThemes.For(last.Id),
		Half = last.Width / 2,
		Kind = "",
		Landmark = false,
		Fx = nil,
	}
	for _, entry in final.Decor do
		local builder = B[entry.Kind]
		assert(builder, "PowerPathDecor: Kind desconhecido " .. entry.Kind)
		ctx.Kind = entry.Kind
		ctx.Landmark = entry.Landmark == true
		ctx.Fx = entry.Fx
		builder(ctx, start + (entry.At :: number) * CorridorLayout.FINAL_PLAZA, entry.Side or 1, entry.Z or 34, entry.Scale or 1, entry.Yaw or 0)
	end
	model:SetAttribute("StageId", "Final")
	model.Parent = parent
	return model
end

return PowerPathDecor
