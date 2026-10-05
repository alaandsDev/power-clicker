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
	  · sem loop: tudo estático e ancorado. O único dinâmico são os emissores
	    do gelo (tag PowerPathAmbient, desligados aqui; o cliente liga perto da
	    câmera e respeita "Efeitos reduzidos" — PowerPathAmbientController).
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

-- Cintilação local do gelo: poucas partículas, DESLIGADAS no servidor.
local function frostSparkle(owner: BasePart)
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Name = "FrostSparkle"
	sparkle.Enabled = false
	sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkle.Rate = 5
	sparkle.Lifetime = NumberRange.new(1.4, 2.4)
	sparkle.Speed = NumberRange.new(0.3, 1.2)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	sparkle.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	sparkle.LightEmission = 0.6
	sparkle.Color = ColorSequence.new(C.Icicle)
	sparkle.Parent = owner
	sparkle:AddTag(PowerPathDecor.TAG_AMBIENT)
end

-- LANDMARK 3: formação de gelo — três agulhas em leque sobre um monte de
-- geleira, a maior com a cintilação local (se o tema permitir).
B.IceFormation = function(ctx, x, side, z, s, _yaw)
	piece(ctx, Vector3.new(14, 4, 10) * s, at(x, 1.2, side * (z + 4)), C.IceDeep, M.Glacier, true)
	local main = spire(ctx, x, z + 4, side, 38 * s, 5, 10, 0.08)
	spire(ctx, x - 5 * s, z - 1, side, 18 * s, 3.4, 16, 0.12)
	spire(ctx, x + 5.5 * s, z + 7, side, 22 * s, 3.6, 4, 0.12)
	if ctx.Theme.Ambient == "FrostSparkle" then
		frostSparkle(main)
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
	sem Decor no tema não ganham nada (Fases C–E).
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
	}
	for _, entry in theme.Decor do
		local builder = B[entry.Kind]
		assert(builder, "PowerPathDecor: Kind desconhecido " .. entry.Kind)
		ctx.Kind = entry.Kind
		ctx.Landmark = entry.Landmark == true
		builder(ctx, PowerPathDecor.XFor(segment, entry.At), entry.Side or 1, entry.Z or 34, entry.Scale or 1, entry.Yaw or 0)
	end
	model:SetAttribute("StageId", segment.Id)
	model.Parent = parent
	return model
end

return PowerPathDecor
