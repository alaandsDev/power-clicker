--!strict
--[[
	StationMachines
	PROTÓTIPO VISUAL: estações do lobby como MÁQUINAS temáticas em vez de
	quiosque de balcão + toldo. Por enquanto só a de MELHORIAS ("Estação de
	Poder"); se a linguagem for aprovada no Studio, Cortes (forja), Pets
	(cápsulas), Renascer (reator), Treino (academia) e Ovos (incubadoras)
	usam as mesmas peças-base (Kit abaixo) com outra paleta e outro núcleo.

	Linguagem: PEDRA + METAL escuro (estrutura) + ENERGIA e CRISTAIS (cor da
	estação) + DOURADO discreto (acabamento). "Fantasia tecnológica de poder",
	não sci-fi puro. Nada de PointLight: o que chama atenção é a silhueta, o
	material Neon em poucos lugares e o movimento (cliente:
	StationFxController — núcleo girando e pulsando, anéis, setas de energia
	subindo, técnico olhando para quem chega).

	Escala (avatar R15 ≈ 5,5 studs): estrutura principal ≈ 14,5 studs
	(2,6x), com o emblema ⬆ em cima chegando a ≈ 19. Pegada ≈ 15 x 16 studs
	contando a plataforma de interação.

	Leitura em três distâncias:
	  LONGE  — duas colunas + verga + emblema de seta e o núcleo ciano;
	  MÉDIA  — placa física "⬆ MELHORIAS" na verga (SurfaceGui, some longe);
	  PERTO  — núcleo com anéis, cristais, setas subindo, painel, técnico e
	           a plataforma com seta no chão (onde ficar).

	Interação: NENHUM sistema novo. A máquina devolve a peça do console
	("Station_<Painel>") e o WorldBuilder põe nela o MESMO ProximityPrompt
	de antes (OpenPanel = "Upgrades") → abre a interface atual.

	Referência local: origem no centro da máquina, no chão; -Z = frente (para
	a praça, de onde o jogador vem). Quem olha a máquina de frente tem a
	direita em -X local; o técnico fica em +X (à esquerda de quem olha, longe
	da calçada que entra na área); o resto é simétrico.
]]

local StationMachines = {}

-- Com StreamingEnabled, anel/técnico chegam inteiros ao cliente (o cliente
-- guarda a posição de cada peça em relação ao centro).
local function atomic(model: Model)
	pcall(function()
		(model :: any).ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end)
end

-- Tags lidas pelo StationFxController (cliente).
StationMachines.TAG_SPIN = "StationSpin" -- peça que gira no lugar (atributo SpinSpeed, graus/s)
StationMachines.TAG_RING = "StationRing" -- Model de anel que gira em volta do centro (SpinSpeed, Tilt)
StationMachines.TAG_PULSE = "StationPulse" -- seta de energia (atributo Order 1..n)
StationMachines.TAG_CORE = "StationCore" -- núcleo que pulsa (Transparency)
StationMachines.TAG_NPC = "StationNpc" -- Model do técnico (respira, olha para quem chega)

export type Theme = {
	Stone: Color3,
	StoneDark: Color3,
	Metal: Color3,
	Plate: Color3,
	Gold: Color3,
	Energy: Color3,
	Crystal: Color3,
	Core: Color3,
}

-- Melhorias: azul/ciano, com o núcleo como a coisa mais viva da máquina.
StationMachines.Themes = {
	Upgrades = {
		Stone = Color3.fromRGB(104, 110, 124),
		StoneDark = Color3.fromRGB(74, 79, 92),
		Metal = Color3.fromRGB(46, 50, 60),
		Plate = Color3.fromRGB(60, 65, 76),
		Gold = Color3.fromRGB(188, 152, 86),
		Energy = Color3.fromRGB(86, 196, 236),
		Crystal = Color3.fromRGB(120, 200, 232),
		Core = Color3.fromRGB(130, 228, 255),
	} :: Theme,
}

-- ── Kit de construção (base para as próximas estações) ──────────────────────

type Kit = {
	Parent: Instance,
	Base: CFrame,
	Theme: Theme,
	Count: number,
}

local function piece(kit: Kit, name: string, size: Vector3, localFrame: CFrame, color: Color3, material: Enum.Material, collide: boolean?, transparency: number?, shape: Enum.PartType?, parent: Instance?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = kit.Base * localFrame
	part.Color = color
	part.Material = material
	if shape then
		part.Shape = shape
	end
	part.CanCollide = collide == true
	part.CanTouch = false
	part.CanQuery = collide == true
	part.Transparency = transparency or 0
	-- Peças pequenas e brilhantes não fazem sombra (custo e sujeira visual).
	part.CastShadow = collide == true and material ~= Enum.Material.Neon
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent or kit.Parent
	kit.Count += 1
	return part
end

-- Cilindro com o eixo em Y (um "disco" deitado / coluna redonda).
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90))
-- Cilindro com o eixo em Z (disco de frente para quem olha).
local FACING = CFrame.Angles(0, math.rad(90), 0)

-- Placa física com texto (SurfaceGui na face da frente): só aparece de perto.
local function plate(kit: Kit, name: string, size: Vector3, localFrame: CFrame, text: string, textColor: Color3, maxDistance: number): Part
	local part = piece(kit, name, size, localFrame, kit.Theme.Metal, Enum.Material.Metal, false)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Text"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0.2
	gui.MaxDistance = maxDistance
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = textColor
	label.TextStrokeTransparency = 0.55
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.Text = text
	label.Parent = gui
	gui.Parent = part
	return part
end

-- Seta "^" de duas barras (no plano XY local, apontando para +Y).
local function chevron(kit: Kit, name: string, centre: CFrame, width: number, thickness: number, color: Color3, material: Enum.Material, transparency: number?, order: number?): { Part }
	local bars = {}
	local half = width / 2
	local length = half * math.sqrt(2)
	for _, side in { -1, 1 } do
		local bar = piece(kit, name, Vector3.new(thickness, length, thickness * 0.6), centre * CFrame.new(side * half / 2, 0, 0) * CFrame.Angles(0, 0, math.rad(45 * side)), color, material, false, transparency)
		if order then
			bar:SetAttribute("Order", order)
			bar:AddTag(StationMachines.TAG_PULSE)
		end
		table.insert(bars, bar)
	end
	return bars
end

-- Cristal facetado (bloco em losango), opcionalmente inclinado.
local function crystal(kit: Kit, name: string, at: Vector3, height: number, tilt: Vector3, color: Color3, transparency: number?): Part
	local width = height * 0.45
	return piece(kit, name, Vector3.new(width, height, width), CFrame.new(at) * CFrame.Angles(math.rad(tilt.X), math.rad(45 + tilt.Y), math.rad(tilt.Z)), color, Enum.Material.Glass, false, transparency or 0.15)
end

-- Anel de energia: octógono de barras num Model (o cliente gira o conjunto).
local function ring(kit: Kit, name: string, centre: CFrame, radius: number, thickness: number, color: Color3, material: Enum.Material, transparency: number, spin: number): Model
	local model = Instance.new("Model")
	model.Name = name
	local sides = 8
	local length = 2 * radius * math.tan(math.pi / sides) + thickness * 0.4
	for index = 0, sides - 1 do
		local angle = index * 2 * math.pi / sides
		piece(kit, name .. "Segment", Vector3.new(length, thickness, thickness), centre * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -radius), color, material, false, transparency, nil, model)
	end
	model:SetAttribute("SpinSpeed", spin)
	model:SetAttribute("Centre", (kit.Base * centre).Position)
	model:SetAttribute("Axis", (kit.Base * centre).UpVector)
	atomic(model)
	model.Parent = kit.Parent
	model:AddTag(StationMachines.TAG_RING)
	return model
end

local function emitter(parent: BasePart, name: string, color: Color3, rate: number, speed: NumberRange, lifetime: NumberRange, size: number, spread: number, acceleration: Vector3)
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.Parent = parent
	local particles = Instance.new("ParticleEmitter")
	particles.Name = name
	particles.Color = ColorSequence.new(color)
	particles.LightEmission = 0.6
	particles.LightInfluence = 0.3
	particles.Rate = rate
	particles.Speed = speed
	particles.Lifetime = lifetime
	particles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	particles.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
	particles.EmissionDirection = Enum.NormalId.Top
	particles.SpreadAngle = Vector2.new(spread, spread)
	particles.Acceleration = acceleration
	particles.LockedToPart = false
	particles.Parent = attachment
end

-- ── Técnico de Energia (NPC pequeno, estilizado em blocos) ──────────────────

local function technician(kit: Kit, at: CFrame): Model
	local theme = kit.Theme
	local npc = Instance.new("Model")
	npc.Name = "Technician"
	local suit = Color3.fromRGB(58, 92, 112)
	local shell = Color3.fromRGB(176, 182, 192)
	local root = piece(kit, "Torso", Vector3.new(2, 2, 1.1), at * CFrame.new(0, 3.2, 0), suit, Enum.Material.SmoothPlastic, false, nil, nil, npc)
	piece(kit, "Belt", Vector3.new(2.1, 0.32, 1.2), at * CFrame.new(0, 2.35, 0), theme.Gold, Enum.Material.Metal, false, nil, nil, npc)
	for _, side in { -1, 1 } do
		piece(kit, "Leg", Vector3.new(0.85, 2.2, 0.95), at * CFrame.new(side * 0.5, 1.1, 0), theme.Metal, Enum.Material.SmoothPlastic, false, nil, nil, npc)
		piece(kit, "Arm", Vector3.new(0.7, 1.9, 0.8), at * CFrame.new(side * 1.38, 3.15, 0) * CFrame.Angles(math.rad(if side > 0 then 12 else 0), 0, 0), shell, Enum.Material.Metal, false, nil, nil, npc)
	end
	local head = piece(kit, "Head", Vector3.new(1.45, 1.3, 1.3), at * CFrame.new(0, 4.9, 0), shell, Enum.Material.Metal, false, nil, nil, npc)
	head:SetAttribute("NpcHead", true)
	piece(kit, "Visor", Vector3.new(1.15, 0.36, 0.12), at * CFrame.new(0, 4.98, -0.66), theme.Energy, Enum.Material.Neon, false, 0.1, nil, npc)
	piece(kit, "Antenna", Vector3.new(0.14, 0.8, 0.14), at * CFrame.new(0.42, 5.9, 0), theme.Metal, Enum.Material.Metal, false, nil, nil, npc)
	piece(kit, "AntennaTip", Vector3.new(0.34, 0.34, 0.34), at * CFrame.new(0.42, 6.36, 0) * CFrame.Angles(math.rad(45), math.rad(45), 0), theme.Core, Enum.Material.Neon, false, 0.1, nil, npc)
	-- Chave de energia na mão direita (de quem é o técnico: -X local dele).
	piece(kit, "Wrench", Vector3.new(0.22, 1.3, 0.22), at * CFrame.new(1.45, 2.05, -0.35), theme.Gold, Enum.Material.Metal, false, nil, nil, npc)
	npc.PrimaryPart = root
	atomic(npc)
	npc.Parent = kit.Parent
	npc:AddTag(StationMachines.TAG_NPC)
	return npc
end

-- ── Estação de Poder (Melhorias) ────────────────────────────────────────────

export type Options = {
	Title: string, -- "⬆️ MELHORIAS"
	Subtitle: string, -- "AUMENTE SEU PODER"
	Npc: boolean,
	Theme: Theme?,
}

--[[
	Constrói a máquina em `base` (CFrame no chão, -Z = frente) dentro de
	`parent`. Devolve (o Model da estação, a peça do console onde vai o
	ProximityPrompt).
]]
function StationMachines.BuildUpgrades(parent: Instance, base: CFrame, panel: string, options: Options): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = "Station_" .. panel .. "_Machine"
	local theme = options.Theme or StationMachines.Themes.Upgrades
	local kit: Kit = { Parent = model, Base = base, Theme = theme, Count = 0 }
	local stone, stoneDark, metal, gold = theme.Stone, theme.StoneDark, theme.Metal, theme.Gold
	local Slate, Metal = Enum.Material.Slate, Enum.Material.Metal

	-- Base em dois níveis + degrau (a máquina "assenta" no chão).
	piece(kit, "Plinth", Vector3.new(15, 1, 9), CFrame.new(0, 0.5, 0.5), stoneDark, Slate, true)
	piece(kit, "Dais", Vector3.new(12.4, 0.6, 7), CFrame.new(0, 1.3, 0.7), stone, Slate, true)
	piece(kit, "DaisTrim", Vector3.new(12.6, 0.16, 0.22), CFrame.new(0, 1.62, -2.82), gold, Metal, false)
	piece(kit, "Step", Vector3.new(8, 0.5, 2.2), CFrame.new(0, 0.25, -5.1), stoneDark, Slate, true)

	-- Colunas: base, fuste de pedra, anel dourado, capitel, painel com setas
	-- de energia, engrenagem do lado de fora e cristal no topo.
	for _, side in { -1, 1 } do
		local x = side * 5.2
		piece(kit, "ColumnBase", Vector3.new(3.2, 1.4, 3.2), CFrame.new(x, 2.3, 0.8), stoneDark, Slate, true)
		piece(kit, "Column", Vector3.new(2.4, 9.2, 2.4), CFrame.new(x, 7.6, 0.8), stone, Slate, true)
		piece(kit, "ColumnBand", Vector3.new(2.7, 0.35, 2.7), CFrame.new(x, 4.4, 0.8), gold, Metal, false)
		piece(kit, "Capital", Vector3.new(3.2, 0.9, 3.2), CFrame.new(x, 12.4, 0.8), stoneDark, Slate, true)
		piece(kit, "ColumnPanel", Vector3.new(1.6, 6, 0.22), CFrame.new(x, 8, -0.51), theme.Plate, Enum.Material.DiamondPlate, false)
		for order = 1, 3 do
			chevron(kit, "EnergyArrow", CFrame.new(x, 5.9 + (order - 1) * 1.7, -0.68), 1.1, 0.24, theme.Energy, Enum.Material.Neon, 0.25, order)
		end
		local outer = side * (5.2 + 1.2)
		piece(kit, "Gear", Vector3.new(0.4, 2.6, 2.6), CFrame.new(outer + side * 0.2, 9.6, 0.8), metal, Metal, false, nil, Enum.PartType.Cylinder)
		piece(kit, "GearHub", Vector3.new(0.5, 1, 1), CFrame.new(outer + side * 0.42, 9.6, 0.8), gold, Metal, false, nil, Enum.PartType.Cylinder)
		for tooth = 0, 3 do
			piece(kit, "GearTooth", Vector3.new(0.36, 0.5, 3.2), CFrame.new(outer + side * 0.2, 9.6, 0.8) * CFrame.Angles(math.rad(tooth * 45), 0, 0), metal, Metal, false)
		end
		crystal(kit, "ColumnCrystal", Vector3.new(x, 14.1, 0.8), 2.1, Vector3.new(0, 0, side * 6), theme.Crystal)
		crystal(kit, "ColumnCrystal", Vector3.new(x + side * 0.7, 13.5, 1.3), 1.2, Vector3.new(0, 20, side * 28), theme.Crystal)
		-- Cristais na quina da frente da base.
		crystal(kit, "BaseCrystal", Vector3.new(side * 6.7, 1.9, -3.3), 2.0, Vector3.new(-8, 10, side * 14), theme.Crystal)
		crystal(kit, "BaseCrystal", Vector3.new(side * 7.2, 1.5, -2.5), 1.2, Vector3.new(6, 30, side * 30), theme.Crystal)
		-- Tubo da coluna até o pedestal do núcleo.
		local from = Vector3.new(side * 4, 2.2, 1.6)
		local to = Vector3.new(side * 0.8, 3.6, 1.2)
		local length = (to - from).Magnitude
		piece(kit, "Pipe", Vector3.new(length, 0.42, 0.42), CFrame.lookAt((from + to) / 2, to) * CFrame.Angles(0, math.rad(90), 0), metal, Metal, false, nil, Enum.PartType.Cylinder)
	end

	-- Verga com as placas, e o emblema ⬆ em cima (silhueta de longe).
	piece(kit, "Lintel", Vector3.new(14, 1.9, 3.4), CFrame.new(0, 13.75, 0.8), stone, Slate, true)
	piece(kit, "LintelTrim", Vector3.new(10.2, 0.28, 0.3), CFrame.new(0, 12.72, -0.85), gold, Metal, false)
	plate(kit, "SignTitle", Vector3.new(9.6, 1.15, 0.24), CFrame.new(0, 14.05, -1.0), options.Title, Color3.fromRGB(240, 246, 255), 110)
	plate(kit, "SignSubtitle", Vector3.new(6.4, 0.55, 0.22), CFrame.new(0, 13.13, -0.99), options.Subtitle, theme.Core, 55)
	piece(kit, "CrestBack", Vector3.new(0.3, 5, 5), CFrame.new(0, 17.2, 1.15) * FACING, gold, Metal, false, nil, Enum.PartType.Cylinder)
	piece(kit, "Crest", Vector3.new(0.5, 4.4, 4.4), CFrame.new(0, 17.2, 0.85) * FACING, stoneDark, Slate, false, nil, Enum.PartType.Cylinder)
	piece(kit, "CrestArrowShaft", Vector3.new(0.75, 1.9, 0.3), CFrame.new(0, 16.55, 0.48), theme.Energy, Enum.Material.Neon, false, 0.05)
	chevron(kit, "CrestArrowHead", CFrame.new(0, 17.75, 0.48), 2.6, 0.75, theme.Energy, Enum.Material.Neon, 0.05)
	piece(kit, "CrestPedestal", Vector3.new(3, 0.6, 2), CFrame.new(0, 14.95, 0.9), stoneDark, Slate, false)

	-- Painel de fundo entre as colunas (profundidade atrás do núcleo).
	piece(kit, "BackPanel", Vector3.new(7.8, 10.9, 0.6), CFrame.new(0, 7.3, 2.25), theme.Plate, Enum.Material.DiamondPlate, true)
	for _, side in { -1, 1 } do
		piece(kit, "BackRib", Vector3.new(0.3, 10.9, 0.3), CFrame.new(side * 3.3, 7.3, 1.85), gold, Metal, false)
	end

	-- Núcleo de poder: pedestal + bacia embaixo, tampa em cima, cristal que
	-- gira e pulsa dentro de dois anéis.
	piece(kit, "CorePedestal", Vector3.new(1.5, 2.6, 1.5), CFrame.new(0, 2.9, 1.0), metal, Metal, true)
	piece(kit, "CoreCradleRing", Vector3.new(0.3, 3.9, 3.9), CFrame.new(0, 4.25, 1.0) * UPRIGHT, gold, Metal, false, nil, Enum.PartType.Cylinder)
	piece(kit, "CoreCradle", Vector3.new(0.7, 3.4, 3.4), CFrame.new(0, 4.6, 1.0) * UPRIGHT, metal, Metal, false, nil, Enum.PartType.Cylinder)
	piece(kit, "CoreCapRod", Vector3.new(0.55, 1.3, 0.55), CFrame.new(0, 12.1, 1.0), metal, Metal, false)
	piece(kit, "CoreCap", Vector3.new(0.6, 2.8, 2.8), CFrame.new(0, 11.25, 1.0) * UPRIGHT, metal, Metal, false, nil, Enum.PartType.Cylinder)
	local centre = CFrame.new(0, 7.75, 1.0)
	local core = piece(kit, "PowerCore", Vector3.new(1.7, 3.1, 1.7), centre * CFrame.Angles(0, math.rad(45), 0), theme.Core, Enum.Material.Neon, false, 0.08)
	core:SetAttribute("SpinSpeed", 24)
	core:AddTag(StationMachines.TAG_SPIN)
	core:AddTag(StationMachines.TAG_CORE)
	local shell = piece(kit, "CoreShell", Vector3.new(2.5, 4, 2.5), centre * CFrame.Angles(0, math.rad(20), 0), theme.Crystal, Enum.Material.Glass, false, 0.6)
	shell:SetAttribute("SpinSpeed", -12)
	shell:AddTag(StationMachines.TAG_SPIN)
	ring(kit, "CoreRingGold", centre * CFrame.Angles(math.rad(18), 0, math.rad(8)), 2.25, 0.2, gold, Metal, 0, 30)
	ring(kit, "CoreRingEnergy", centre * CFrame.Angles(math.rad(-24), 0, math.rad(-12)), 2.7, 0.14, theme.Energy, Enum.Material.Neon, 0.35, -42)
	-- Partículas: centelhas subindo do núcleo (o "upgrade" acontecendo) e uns
	-- pontos de energia saindo da bacia. Poucas, pequenas, sem luz.
	emitter(core, "CoreSparks", theme.Core, 7, NumberRange.new(1.2, 2.2), NumberRange.new(1.0, 1.6), 0.22, 30, Vector3.new(0, 1.2, 0))
	local cradle = model:FindFirstChild("CoreCradle") :: BasePart
	emitter(cradle, "RisingMotes", theme.Energy, 4, NumberRange.new(0.8, 1.4), NumberRange.new(1.6, 2.4), 0.16, 60, Vector3.new(0, 1.4, 0))

	-- Console de frente (onde fica o prompt): corpo de metal, tampo inclinado
	-- com tela de energia.
	local console = piece(kit, "Station_" .. panel, Vector3.new(4.2, 2.8, 1.6), CFrame.new(0, 3.0, -2.6), metal, Metal, true)
	piece(kit, "ConsoleTop", Vector3.new(4.5, 0.3, 2), CFrame.new(0, 4.55, -2.55) * CFrame.Angles(math.rad(-22), 0, 0), stoneDark, Slate, false)
	piece(kit, "ConsoleScreen", Vector3.new(3.5, 0.08, 1.3), CFrame.new(0, 4.73, -2.55) * CFrame.Angles(math.rad(-22), 0, 0), theme.Energy, Enum.Material.Neon, false, 0.35)
	piece(kit, "ConsoleTrim", Vector3.new(4.4, 0.22, 0.22), CFrame.new(0, 1.8, -3.45), gold, Metal, false)

	-- Plataforma de interação: piso de metal diferente, com seta dourada
	-- apontando para a máquina e duas linhas finas de energia nas bordas.
	piece(kit, "InteractPad", Vector3.new(5.6, 0.3, 4.4), CFrame.new(0, 0.62, -8.6), theme.Plate, Enum.Material.DiamondPlate, true)
	for _, side in { -1, 1 } do
		piece(kit, "PadEdge", Vector3.new(0.22, 0.08, 4.4), CFrame.new(side * 2.69, 0.8, -8.6), theme.Energy, Enum.Material.Neon, false, 0.45)
	end
	-- No chão, a seta aponta para +Z local (para a máquina).
	chevron(kit, "PadArrow", CFrame.new(0, 0.79, -8.1) * CFrame.Angles(math.rad(90), 0, 0), 2.2, 0.36, gold, Metal, nil)
	piece(kit, "PadArrowShaft", Vector3.new(0.36, 0.06, 1.4), CFrame.new(0, 0.79, -9.4), gold, Metal, false)

	if options.Npc then
		-- Ao lado da coluna ESQUERDA de quem olha de frente (+X local): do outro
		-- lado fica a calçada que entra na área. Meio de lado, virado para quem
		-- chega.
		technician(kit, CFrame.new(8.6, 0.6, -1.4) * CFrame.Angles(0, math.rad(25), 0))
	end

	model:SetAttribute("PartCount", kit.Count)
	model:SetAttribute("Prototype", "StationMachine")
	model.Parent = parent
	return model, console
end

return StationMachines
