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
StationMachines.TAG_SCREEN = "StationScreen" -- tela do console (barras sobem; reage a quem chega)
StationMachines.TAG_PARTICLES = "StationParticles" -- emissor desligado com "Efeitos reduzidos"
StationMachines.TAG_CUT_TINT = "StationCutTint" -- peça/emissor na cor do Corte do jogador local
StationMachines.TAG_FLASH = "StationFlash" -- de tempos em tempos um clarão curto (mini-impacto)
StationMachines.TAG_HOLO = "StationHolo" -- holograma (BillboardGui) que flutua e respira
StationMachines.TAG_ENGAGE = "StationEngage" -- ponto de uso (jogador perto = a estação "acorda")
StationMachines.TAG_RISE = "StationRise" -- emissor: poucos idle, mais com o jogador perto (IdleRate/EngagedRate)
StationMachines.TAG_BURST = "StationBurst" -- emissor: rajada local quando o jogador renasce de verdade
StationMachines.TAG_REWARD = "StationReward" -- baú de Prêmios: Role Glow / Mark / Sparkle, aceso só com prêmio disponível (cliente)

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
	-- Pets: laboratório de companheiros, roxo com ciano.
	Pets = {
		Stone = Color3.fromRGB(108, 106, 122),
		StoneDark = Color3.fromRGB(74, 72, 90),
		Metal = Color3.fromRGB(48, 46, 60),
		Plate = Color3.fromRGB(64, 62, 78),
		Gold = Color3.fromRGB(188, 152, 86),
		Energy = Color3.fromRGB(170, 116, 255),
		Crystal = Color3.fromRGB(176, 150, 255),
		Core = Color3.fromRGB(126, 226, 255),
	} :: Theme,
	-- Treino: academia industrial (amarelo/laranja com um toque de ciano).
	Training = {
		Stone = Color3.fromRGB(112, 114, 124),
		StoneDark = Color3.fromRGB(70, 72, 82),
		Metal = Color3.fromRGB(56, 60, 72),
		Plate = Color3.fromRGB(66, 70, 82),
		Gold = Color3.fromRGB(196, 158, 84),
		Energy = Color3.fromRGB(255, 176, 60),
		Crystal = Color3.fromRGB(255, 200, 110),
		Core = Color3.fromRGB(110, 210, 240),
	} :: Theme,
	-- Renascer: altar ritual dourado + violeta + luz clara (sem ciano).
	Rebirth = {
		Stone = Color3.fromRGB(150, 144, 160),
		StoneDark = Color3.fromRGB(92, 86, 104),
		Metal = Color3.fromRGB(56, 50, 66),
		Plate = Color3.fromRGB(72, 66, 84),
		Gold = Color3.fromRGB(206, 168, 90),
		Energy = Color3.fromRGB(176, 120, 255),
		Crystal = Color3.fromRGB(190, 150, 255),
		Core = Color3.fromRGB(255, 232, 186),
	} :: Theme,
	-- Cortes: forja de energia vermelho/laranja (o slash pega a cor do Corte
	-- do jogador no cliente).
	Cuts = {
		Stone = Color3.fromRGB(104, 104, 112),
		StoneDark = Color3.fromRGB(70, 70, 80),
		Metal = Color3.fromRGB(44, 44, 52),
		Plate = Color3.fromRGB(62, 60, 66),
		Gold = Color3.fromRGB(188, 152, 86),
		Energy = Color3.fromRGB(255, 122, 52),
		Crystal = Color3.fromRGB(255, 150, 90),
		Core = Color3.fromRGB(255, 176, 96),
	} :: Theme,
}

export type Options = {
	Title: string, -- "⬆️ MELHORIAS"
	Subtitle: string, -- "AUMENTE SEU PODER"
	Npc: boolean,
	Theme: Theme?,
}

-- MAIÚSCULAS com os acentos do português (string.upper só cuida de A–Z).
local ACCENTS = {
	["á"] = "Á", ["à"] = "À", ["â"] = "Â", ["ã"] = "Ã", ["é"] = "É", ["ê"] = "Ê",
	["í"] = "Í", ["ó"] = "Ó", ["ô"] = "Ô", ["õ"] = "Õ", ["ú"] = "Ú", ["ç"] = "Ç",
}
function StationMachines.Upper(text: string): string
	local upper = string.upper(text)
	for lower, capital in ACCENTS do
		upper = string.gsub(upper, lower, capital)
	end
	return upper
end

-- Mesma cor, mais escura/clara.
local function shade(color: Color3, factor: number): Color3
	return Color3.new(math.clamp(color.R * factor, 0, 1), math.clamp(color.G * factor, 0, 1), math.clamp(color.B * factor, 0, 1))
end

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

-- Rampa (WedgePart): a face inclinada olha para -Z local e sobe para +Z.
local function wedge(kit: Kit, name: string, size: Vector3, localFrame: CFrame, color: Color3, material: Enum.Material): WedgePart
	local part = Instance.new("WedgePart")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = kit.Base * localFrame
	part.Color = color
	part.Material = material
	part.CanCollide = true
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = kit.Parent
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
local function chevron(kit: Kit, name: string, centre: CFrame, width: number, thickness: number, color: Color3, material: Enum.Material, transparency: number?, order: number?, depth: number?): { Part }
	local bars = {}
	local half = width / 2
	local length = half * math.sqrt(2)
	for _, side in { -1, 1 } do
		local bar = piece(kit, name, Vector3.new(thickness, length, depth or thickness * 0.6), centre * CFrame.new(side * half / 2, 0, 0) * CFrame.Angles(0, 0, math.rad(45 * side)), color, material, false, transparency)
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

local function emitter(parent: BasePart, name: string, color: Color3, rate: number, speed: NumberRange, lifetime: NumberRange, size: number, spread: number, acceleration: Vector3): ParticleEmitter
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
	-- "Efeitos reduzidos" desliga as partículas das estações (cliente).
	particles:AddTag(StationMachines.TAG_PARTICLES)
	return particles
end

-- ── Componentes (mesma linguagem; cada estação monta a sua silhueta) ────────

-- Cilindro deitado entre dois pontos (tubo, cabo).
local function tube(kit: Kit, name: string, from: Vector3, to: Vector3, thickness: number, color: Color3)
	local length = (to - from).Magnitude
	piece(kit, name, Vector3.new(length, thickness, thickness), CFrame.lookAt((from + to) / 2, to) * CFrame.Angles(0, math.rad(90), 0), color, Enum.Material.Metal, false, nil, Enum.PartType.Cylinder)
end

--[[
	EmbeddedPanel: painel de energia EMBUTIDO na face da frente de um bloco
	(z = face). Duas pilastras salientes fazem a moldura, com acabamento em
	cima (dourado) e embaixo; dentro, um rebaixo escuro e um canal de energia
	bem apagado atrás das setas, que acendem de baixo para cima.
]]
local function embeddedPanel(kit: Kit, x: number, face: number, bottom: number, top: number, arrows: number)
	local theme = kit.Theme
	local height = top - bottom
	local middle = (top + bottom) / 2
	for _, side in { -1, 1 } do
		piece(kit, "PanelPilaster", Vector3.new(0.38, height, 0.42), CFrame.new(x + side * 0.96, middle, face - 0.2), theme.StoneDark, Enum.Material.Slate, false)
	end
	piece(kit, "PanelCapTop", Vector3.new(2.3, 0.34, 0.5), CFrame.new(x, top + 0.17, face - 0.22), theme.Gold, Enum.Material.Metal, false)
	piece(kit, "PanelCapBottom", Vector3.new(2.3, 0.34, 0.5), CFrame.new(x, bottom - 0.17, face - 0.22), theme.StoneDark, Enum.Material.Slate, false)
	piece(kit, "PanelRecess", Vector3.new(1.54, height, 0.1), CFrame.new(x, middle, face - 0.05), theme.Plate, Enum.Material.DiamondPlate, false)
	piece(kit, "PanelChannel", Vector3.new(0.42, height - 0.6, 0.05), CFrame.new(x, middle, face - 0.12), theme.Energy, Enum.Material.Neon, false, 0.8)
	local step = height / (arrows + 0.6)
	for order = 1, arrows do
		chevron(kit, "EnergyArrow", CFrame.new(x, bottom + step * (order - 0.2), face - 0.2), 1.0, 0.22, theme.Energy, Enum.Material.Neon, 0.25, order, 0.1)
	end
end

--[[
	ColumnFrame: coluna de pedra com base, anel dourado, capitel, painel
	embutido na frente, engrenagem do lado de fora e cristais no topo.
]]
local function columnFrame(kit: Kit, side: number, x: number, z: number, height: number)
	local theme = kit.Theme
	local stone, stoneDark = theme.Stone, theme.StoneDark
	local Slate, Metal = Enum.Material.Slate, Enum.Material.Metal
	local half = 1.2
	piece(kit, "ColumnBase", Vector3.new(3.2, 1.4, 3.2), CFrame.new(x, 2.3, z), stoneDark, Slate, true)
	piece(kit, "Column", Vector3.new(2.4, height, 2.4), CFrame.new(x, 3 + height / 2, z), stone, Slate, true)
	piece(kit, "ColumnBand", Vector3.new(2.7, 0.35, 2.7), CFrame.new(x, 4.05, z), theme.Gold, Metal, false)
	piece(kit, "Capital", Vector3.new(3.2, 0.9, 3.2), CFrame.new(x, 3 + height - 0.2, z), stoneDark, Slate, true)
	embeddedPanel(kit, x, z - half, 4.6, 11.4, 3)
	-- Engrenagem de fora (disco + cubo + dois dentes em cruz).
	local outer = x + side * (half + 0.2)
	piece(kit, "Gear", Vector3.new(0.4, 2.6, 2.6), CFrame.new(outer, 9.6, z), theme.Metal, Metal, false, nil, Enum.PartType.Cylinder)
	piece(kit, "GearHub", Vector3.new(0.5, 1, 1), CFrame.new(outer + side * 0.22, 9.6, z), theme.Gold, Metal, false, nil, Enum.PartType.Cylinder)
	for tooth = 0, 1 do
		piece(kit, "GearTooth", Vector3.new(0.36, 0.5, 3.2), CFrame.new(outer, 9.6, z) * CFrame.Angles(math.rad(tooth * 90), 0, 0), theme.Metal, Metal, false)
	end
	crystal(kit, "ColumnCrystal", Vector3.new(x, 3 + height + 1.2, z), 2.1, Vector3.new(0, 0, side * 6), theme.Crystal)
	crystal(kit, "ColumnCrystal", Vector3.new(x + side * 0.7, 3 + height + 0.6, z + 0.5), 1.2, Vector3.new(0, 20, side * 28), theme.Crystal)
end

--[[
	EnergyCore: o coração da máquina, em camadas de profundidade —
	anel FRONTAL (energia) → núcleo (cristal de vidro com o brilho Neon por
	dentro) → anel interno (dourado) → halo TRASEIRO (disco de metal com aro
	dourado) preso às colunas por dois braços. Pedestal/bacia embaixo e tampa
	em cima. Os anéis ficam quase de frente para quem chega, inclinados em
	sentidos diferentes, e giram em sentidos opostos (cliente).
]]
local function energyCore(kit: Kit, centre: Vector3, reach: number): BasePart
	local theme = kit.Theme
	local metal, gold = theme.Metal, theme.Gold
	local Metal = Enum.Material.Metal
	local x, y, z = centre.X, centre.Y, centre.Z
	piece(kit, "CorePedestal", Vector3.new(1.5, 2.3, 1.5), CFrame.new(x, 2.75, z), metal, Metal, true)
	piece(kit, "CoreCradleRing", Vector3.new(0.3, 3.9, 3.9), CFrame.new(x, 3.95, z) * UPRIGHT, gold, Metal, false, nil, Enum.PartType.Cylinder)
	piece(kit, "CoreCradle", Vector3.new(0.6, 3.3, 3.3), CFrame.new(x, 4.3, z) * UPRIGHT, metal, Metal, false, nil, Enum.PartType.Cylinder)
	piece(kit, "CoreCap", Vector3.new(0.6, 2.8, 2.8), CFrame.new(x, 11.3, z) * UPRIGHT, metal, Metal, false, nil, Enum.PartType.Cylinder)
	piece(kit, "CoreCapRod", Vector3.new(0.55, 1.2, 0.55), CFrame.new(x, 12.2, z), metal, Metal, false)
	-- Halo traseiro + aro, e os braços até as colunas.
	piece(kit, "CoreHalo", Vector3.new(0.25, 5.4, 5.4), CFrame.new(x, y, z + 1.35) * FACING, metal, Metal, false, nil, Enum.PartType.Cylinder)
	piece(kit, "CoreHaloRim", Vector3.new(0.14, 5.9, 5.9), CFrame.new(x, y, z + 1.49) * FACING, gold, Metal, false, nil, Enum.PartType.Cylinder)
	for _, side in { -1, 1 } do
		piece(kit, "CoreArm", Vector3.new(reach - 2.6, 0.45, 0.5), CFrame.new(x + side * (2.6 + (reach - 2.6) / 2), y, z + 1.15), metal, Metal, false)
	end
	-- Cristal: casca de vidro + brilho Neon por dentro (gira ao contrário).
	local frame = CFrame.new(x, y, z)
	local outer = piece(kit, "CoreCrystal", Vector3.new(2.1, 3.7, 2.1), frame * CFrame.Angles(0, math.rad(20), 0), theme.Crystal, Enum.Material.Glass, false, 0.55)
	outer:SetAttribute("SpinSpeed", -14)
	outer:AddTag(StationMachines.TAG_SPIN)
	local core = piece(kit, "PowerCore", Vector3.new(1.7, 3.2, 1.7), frame * CFrame.Angles(0, math.rad(45), 0), theme.Core, Enum.Material.Neon, false, 0.08)
	core:SetAttribute("SpinSpeed", 26)
	core:AddTag(StationMachines.TAG_SPIN)
	core:AddTag(StationMachines.TAG_CORE)
	-- Anel interno (dourado), de frente e virado de lado; anel frontal
	-- (energia), maior e um pouco à frente do núcleo.
	local facingRing = CFrame.Angles(math.rad(90), 0, 0)
	ring(kit, "CoreRingGold", frame * CFrame.Angles(0, math.rad(24), 0) * facingRing, 2.3, 0.2, gold, Metal, 0, 34)
	ring(kit, "CoreRingEnergy", CFrame.new(x, y, z - 0.4) * CFrame.Angles(math.rad(-12), math.rad(-14), 0) * facingRing, 2.8, 0.15, theme.Energy, Enum.Material.Neon, 0.35, -46)
	emitter(core, "CoreSparks", theme.Core, 6, NumberRange.new(1.2, 2.2), NumberRange.new(1.0, 1.6), 0.22, 30, Vector3.new(0, 1.2, 0))
	local cradle = kit.Parent:FindFirstChild("CoreCradle") :: BasePart
	emitter(cradle, "RisingMotes", theme.Energy, 4, NumberRange.new(0.8, 1.4), NumberRange.new(1.6, 2.4), 0.16, 60, Vector3.new(0, 1.4, 0))
	return core
end

-- Tela do console: seta grande + três barras subindo (UI na superfície, sem
-- Neon; o cliente anima as barras).
local function screenGui(part: BasePart, color: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Screen"
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 0
	gui.MaxDistance = 60
	local arrow = Instance.new("TextLabel")
	arrow.Name = "Arrow"
	arrow.BackgroundTransparency = 1
	arrow.Size = UDim2.fromScale(0.36, 0.9)
	arrow.Position = UDim2.fromScale(0.06, 0.05)
	arrow.Font = Enum.Font.GothamBlack
	arrow.TextScaled = true
	arrow.TextColor3 = color
	arrow.Text = "↑"
	arrow.Parent = gui
	for index = 1, 3 do
		local bar = Instance.new("Frame")
		bar.Name = "Bar" .. index
		bar.BorderSizePixel = 0
		bar.BackgroundColor3 = color
		bar.BackgroundTransparency = 0.15
		bar.AnchorPoint = Vector2.new(0, 1)
		local height = 0.25 + index * 0.2
		bar.Size = UDim2.fromScale(0.13, height)
		bar.Position = UDim2.fromScale(0.46 + (index - 1) * 0.17, 0.9)
		bar:SetAttribute("BaseHeight", height)
		bar.Parent = gui
	end
	gui.Parent = part
end

--[[
	StationConsole: o terminal onde o jogador interage. Pedestal, cabeça
	inclinada para quem chega (é a peça do prompt), tela embutida com seta e
	barras, bochechas laterais, friso dourado e um cabo até a máquina.
]]
local function stationConsole(kit: Kit, name: string, z: number, machineZ: number): BasePart
	local theme = kit.Theme
	local Metal = Enum.Material.Metal
	piece(kit, "ConsoleBase", Vector3.new(2.8, 2.3, 1.3), CFrame.new(0, 2.75, z + 0.25), theme.Metal, Metal, true)
	local tilt = CFrame.new(0, 4.15, z) * CFrame.Angles(math.rad(-26), 0, 0)
	local head = piece(kit, name, Vector3.new(4.4, 0.7, 2.3), tilt, theme.Plate, Metal, true)
	local screen = piece(kit, "ConsoleScreen", Vector3.new(3.5, 0.06, 1.55), tilt * CFrame.new(0, 0.37, 0.05), Color3.fromRGB(16, 26, 38), Enum.Material.SmoothPlastic, false)
	screenGui(screen, theme.Core)
	screen:AddTag(StationMachines.TAG_SCREEN)
	piece(kit, "ConsoleBezel", Vector3.new(4.4, 0.16, 0.16), tilt * CFrame.new(0, 0.3, -1.12), theme.Gold, Metal, false)
	for _, side in { -1, 1 } do
		piece(kit, "ConsoleCheek", Vector3.new(0.22, 1.2, 2.5), tilt * CFrame.new(side * 2.3, -0.05, 0), theme.StoneDark, Enum.Material.Slate, false)
	end
	tube(kit, "ConsoleCable", Vector3.new(0, 2.0, z + 0.9), Vector3.new(0, 2.0, machineZ - 0.75), 0.3, theme.Metal)
	return head
end

--[[
	FloorDock: a transição PISO → MARCA → BASE. Plataforma de metal encaixada
	num aro (fica rente ao piso), seta dourada gravada, duas linhas finas de
	energia nas bordas e uma rampa curta até a base, com um trilho de
	energia no meio ligando a marca à máquina.
]]
local function floorDock(kit: Kit, padZ: number, plinthFront: number, plinthTop: number)
	local theme = kit.Theme
	local floorTop = 0.59
	local padTop = floorTop + 0.18
	piece(kit, "PadFrame", Vector3.new(6.4, 0.16, 5.2), CFrame.new(0, floorTop + 0.01, padZ), shade(theme.Gold, 0.55), Enum.Material.Metal, true)
	piece(kit, "InteractPad", Vector3.new(5.6, 0.18, 4.4), CFrame.new(0, floorTop + 0.09, padZ), theme.Plate, Enum.Material.DiamondPlate, true)
	for _, side in { -1, 1 } do
		piece(kit, "PadEdge", Vector3.new(0.18, 0.05, 4.4), CFrame.new(side * 2.7, padTop + 0.02, padZ), theme.Energy, Enum.Material.Neon, false, 0.5)
	end
	-- Seta gravada (rente ao piso, aponta para a máquina = +Z).
	local inlay = shade(theme.Gold, 0.8)
	chevron(kit, "PadArrow", CFrame.new(0, padTop + 0.01, padZ + 0.6) * CFrame.Angles(math.rad(90), 0, 0), 2.2, 0.34, inlay, Enum.Material.Metal, nil, nil, 0.04)
	piece(kit, "PadArrowShaft", Vector3.new(0.34, 0.04, 1.5), CFrame.new(0, padTop + 0.01, padZ - 0.7), inlay, Enum.Material.Metal, false)
	-- Rampa da borda da plataforma até a base.
	local padBack = padZ + 2.2
	local length = plinthFront - padBack
	local rise = plinthTop - padTop
	wedge(kit, "Ramp", Vector3.new(7.2, rise, length + 0.1), CFrame.new(0, padTop + rise / 2, (padBack + plinthFront) / 2), theme.StoneDark, Enum.Material.Slate)
	local slope = math.atan2(rise, length)
	piece(kit, "RampRail", Vector3.new(0.18, 0.05, math.sqrt(length * length + rise * rise)), CFrame.new(0, padTop + rise / 2 + 0.03, (padBack + plinthFront) / 2) * CFrame.Angles(-slope, 0, 0), theme.Energy, Enum.Material.Neon, false, 0.5)
end

--[[
	StationHeader: verga com placa (moldura dourada, título grande e
	subtítulo menor) e o emblema em cima, assentado num pedestal com dois
	braços inclinados que o ligam à verga — não um disco flutuando.
]]
local function stationHeader(kit: Kit, options: Options, y: number, z: number, width: number)
	local theme = kit.Theme
	local Slate, Metal = Enum.Material.Slate, Enum.Material.Metal
	local height = 2.2
	local face = z - 1.7
	piece(kit, "Lintel", Vector3.new(width, height, 3.4), CFrame.new(0, y, z), theme.Stone, Slate, true)
	piece(kit, "LintelTrim", Vector3.new(7.2, 0.22, 0.26), CFrame.new(0, y - height / 2 - 0.1, face + 0.1), theme.Gold, Metal, false)
	piece(kit, "SignFrame", Vector3.new(10.6, 1.55, 0.16), CFrame.new(0, y + 0.35, face - 0.08), theme.Gold, Metal, false)
	plate(kit, "SignTitle", Vector3.new(10.2, 1.25, 0.2), CFrame.new(0, y + 0.35, face - 0.18), options.Title, Color3.fromRGB(242, 247, 255), 110)
	plate(kit, "SignSubtitle", Vector3.new(5.6, 0.46, 0.18), CFrame.new(0, y - 0.72, face - 0.1), options.Subtitle, theme.Crystal, 55)
	local top = y + height / 2
	piece(kit, "CrestPedestal", Vector3.new(3.4, 0.5, 2.2), CFrame.new(0, top + 0.25, z + 0.1), theme.StoneDark, Slate, false)
	for _, side in { -1, 1 } do
		piece(kit, "CrestBrace", Vector3.new(0.45, 2.1, 0.5), CFrame.new(side * 2.15, top + 1.0, z + 0.15) * CFrame.Angles(0, 0, math.rad(side * 28)), theme.Gold, Metal, false)
	end
	local crestY = top + 2.4
	piece(kit, "CrestBack", Vector3.new(0.3, 5, 5), CFrame.new(0, crestY, z + 0.35) * FACING, theme.Gold, Metal, false, nil, Enum.PartType.Cylinder)
	piece(kit, "Crest", Vector3.new(0.5, 4.4, 4.4), CFrame.new(0, crestY, z + 0.05) * FACING, theme.StoneDark, Slate, false, nil, Enum.PartType.Cylinder)
	piece(kit, "CrestArrowShaft", Vector3.new(0.75, 1.9, 0.3), CFrame.new(0, crestY - 0.65, z - 0.32), theme.Energy, Enum.Material.Neon, false, 0.05)
	chevron(kit, "CrestArrowHead", CFrame.new(0, crestY + 0.55, z - 0.32), 2.6, 0.75, theme.Energy, Enum.Material.Neon, 0.05)
end

-- ── Técnico de Energia (NPC pequeno, estilizado em blocos) ──────────────────

local function technician(kit: Kit, at: CFrame): Model
	local theme = kit.Theme
	local npc = Instance.new("Model")
	npc.Name = "Technician"
	-- Mesma paleta da máquina: corpo de metal escuro, braços de chapa,
	-- cabeça clara (legível), visor ciano e cinto dourado.
	local body = Color3.fromRGB(64, 70, 84)
	local limbs = Color3.fromRGB(118, 124, 138)
	local shell = Color3.fromRGB(176, 182, 192)
	local root = piece(kit, "Torso", Vector3.new(2, 2, 1.1), at * CFrame.new(0, 3.2, 0), body, Enum.Material.Metal, false, nil, nil, npc)
	piece(kit, "Belt", Vector3.new(2.1, 0.32, 1.2), at * CFrame.new(0, 2.35, 0), theme.Gold, Enum.Material.Metal, false, nil, nil, npc)
	for _, side in { -1, 1 } do
		piece(kit, "Leg", Vector3.new(0.85, 2.2, 0.95), at * CFrame.new(side * 0.5, 1.1, 0), theme.Metal, Enum.Material.Metal, false, nil, nil, npc)
		piece(kit, "Arm", Vector3.new(0.7, 1.9, 0.8), at * CFrame.new(side * 1.38, 3.15, 0) * CFrame.Angles(math.rad(if side > 0 then 12 else 0), 0, 0), limbs, Enum.Material.Metal, false, nil, nil, npc)
	end
	local head = piece(kit, "Head", Vector3.new(1.45, 1.3, 1.3), at * CFrame.new(0, 4.9, 0), shell, Enum.Material.Metal, false, nil, nil, npc)
	head:SetAttribute("NpcHead", true)
	piece(kit, "Visor", Vector3.new(1.15, 0.36, 0.12), at * CFrame.new(0, 4.98, -0.66), theme.Energy, Enum.Material.Neon, false, 0.1, nil, npc)
	piece(kit, "Antenna", Vector3.new(0.14, 0.8, 0.14), at * CFrame.new(0.42, 5.9, 0), theme.Metal, Enum.Material.Metal, false, nil, nil, npc)
	piece(kit, "AntennaTip", Vector3.new(0.34, 0.34, 0.34), at * CFrame.new(0.42, 6.36, 0) * CFrame.Angles(math.rad(45), math.rad(45), 0), theme.Core, Enum.Material.Neon, false, 0.1, nil, npc)
	-- Chave de energia na mão.
	piece(kit, "Wrench", Vector3.new(0.22, 1.3, 0.22), at * CFrame.new(1.45, 2.05, -0.35), theme.Gold, Enum.Material.Metal, false, nil, nil, npc)
	npc.PrimaryPart = root
	atomic(npc)
	npc.Parent = kit.Parent
	npc:AddTag(StationMachines.TAG_NPC)
	return npc
end

-- ── Estação de Poder (Melhorias) ────────────────────────────────────────────

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
	local Slate, Metal = Enum.Material.Slate, Enum.Material.Metal

	-- Base em dois níveis (a máquina "assenta" no chão).
	piece(kit, "Plinth", Vector3.new(15, 1, 9), CFrame.new(0, 0.5, 0.5), theme.StoneDark, Slate, true)
	piece(kit, "Dais", Vector3.new(12.4, 0.6, 7), CFrame.new(0, 1.3, 0.7), theme.Stone, Slate, true)
	piece(kit, "DaisTrim", Vector3.new(12.6, 0.16, 0.22), CFrame.new(0, 1.62, -2.82), theme.Gold, Metal, false)
	floorDock(kit, -8.6, -4.0, 1.0)

	-- Colunas, verga/placa/emblema, painel de fundo.
	for _, side in { -1, 1 } do
		columnFrame(kit, side, side * 5.2, 0.8, 9.2)
	end
	stationHeader(kit, options, 13.8, 0.8, 14)
	piece(kit, "BackPanel", Vector3.new(7.8, 10.9, 0.6), CFrame.new(0, 7.3, 2.25), theme.Plate, Enum.Material.DiamondPlate, true)
	for _, side in { -1, 1 } do
		piece(kit, "BackRib", Vector3.new(0.3, 10.9, 0.3), CFrame.new(side * 3.3, 7.3, 1.85), theme.Gold, Metal, false)
		-- Tubo da base da coluna até o pedestal do núcleo.
		tube(kit, "Pipe", Vector3.new(side * 4, 2.2, 1.6), Vector3.new(side * 0.8, 3.4, 0.7), 0.42, theme.Metal)
	end

	-- Núcleo (o coração) e o terminal na frente.
	energyCore(kit, Vector3.new(0, 7.75, 0.45), 4.0)
	local console = stationConsole(kit, "Station_" .. panel, -2.55, 0.45)

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

-- ── Componentes compartilhados pelas próximas estações ──────────────────────

--[[
	Nameplate: o mesmo FORMATO de placa de Melhorias (moldura dourada, título
	grande, subtítulo pequeno, SurfaceGui de perto) sem precisar da verga —
	cada estação decide onde a placa fica na própria arquitetura.
	`at` = centro do título, olhando para -Z (frente).
]]
local function nameplate(kit: Kit, at: CFrame, title: string, subtitle: string, width: number)
	local theme = kit.Theme
	piece(kit, "SignFrame", Vector3.new(width + 0.4, 1.45, 0.14), at * CFrame.new(0, 0, 0.1), theme.Gold, Enum.Material.Metal, false)
	plate(kit, "SignTitle", Vector3.new(width, 1.15, 0.18), at, title, Color3.fromRGB(242, 247, 255), 110)
	plate(kit, "SignSubtitle", Vector3.new(width * 0.55, 0.44, 0.16), at * CFrame.new(0, -1.05, 0.02), subtitle, theme.Crystal, 55)
end

-- Bloco inclinado entre dois pontos no plano XY local (braço, escora).
local function strut(kit: Kit, name: string, from: Vector3, to: Vector3, width: number, depth: number, color: Color3, material: Enum.Material, collide: boolean?): Part
	local delta = to - from
	local angle = math.atan2(-delta.X, delta.Y)
	return piece(kit, name, Vector3.new(width, delta.Magnitude, depth), CFrame.new((from + to) / 2) * CFrame.Angles(0, 0, angle), color, material, collide)
end

export type PlateOptions = { Title: string, Subtitle: string }

-- ── Forja de Cortes ─────────────────────────────────────────────────────────

--[[
	FORJA DE CORTES. Não é loja nem espada: é onde o PODER do corte é forjado.
	Silhueta horizontal e pesada (bem diferente das colunas de Melhorias):
	base de forja larga com bisel até o piso, uma lareira no meio com a
	bigorna tecnológica, dois BRAÇOS CONDUTORES inclinados que apontam para um
	SLASH de energia suspenso (o corte, em arco) na frente de uma placa de
	fundo com a "fenda", fragmentos orbitando, canais de energia levando
	energia dos braços para o centro e um trilho no chão que liga a forja aos
	pads da galeria de Cortes.

	Interação: NENHUMA nova. Os Cortes continuam sendo comprados nos pads da
	galeria (um prompt por Corte, CutId) — a forja é o fundo/marco dela.
	O slash, a bigorna e as faíscas pegam a cor do Corte do jogador local
	(cliente, StationFxController + CutVisuals); a estrutura fica laranja.
	Referência local: -Z = frente (para a avenida).
]]
function StationMachines.BuildCutForge(parent: Instance, base: CFrame, options: PlateOptions, galleryXs: { number }, railZ: number): Model
	local model = Instance.new("Model")
	model.Name = "Station_Cuts_Machine"
	local theme = StationMachines.Themes.Cuts
	local kit: Kit = { Parent = model, Base = base, Theme = theme, Count = 0 }
	local Slate, Metal, Neon = Enum.Material.Slate, Enum.Material.Metal, Enum.Material.Neon

	-- Base de forja: plataforma larga + bisel até o piso + lareira central.
	piece(kit, "ForgeBase", Vector3.new(24, 1.2, 12), CFrame.new(0, 0.6, 0), theme.StoneDark, Slate, true)
	wedge(kit, "ForgeBevel", Vector3.new(24, 0.8, 1.6), CFrame.new(0, 0.8, -6.8), theme.StoneDark, Slate)
	piece(kit, "ForgeTrim", Vector3.new(24.2, 0.16, 0.22), CFrame.new(0, 1.22, -6.0), theme.Gold, Metal, false)
	piece(kit, "Hearth", Vector3.new(10, 0.8, 7), CFrame.new(0, 1.6, 0.5), theme.Stone, Slate, true)
	-- Canais de energia dos pés dos braços até a lareira (a onda vai para dentro).
	for _, side in { -1, 1 } do
		for order = 1, 3 do
			local piece_ = piece(kit, "ForgeConduit", Vector3.new(1.55, 0.08, 0.42), CFrame.new(side * (9.6 - order * 1.7), 1.24, -1.6), theme.Energy, Neon, false, 0.6)
			piece_:SetAttribute("Order", order)
			piece_:AddTag(StationMachines.TAG_PULSE)
		end
	end

	-- Braços condutores: pé de metal, braço inclinado com faixas douradas e
	-- filete de energia, cabeça emissora e cristal apontando para o slash.
	local slashCentre = Vector3.new(0, 7.8, 0.4)
	for _, side in { -1, 1 } do
		local foot = Vector3.new(side * 10, 4.2, 1.0)
		local tip = Vector3.new(side * 5.4, 14.4, 1.0)
		piece(kit, "ArmFoot", Vector3.new(4, 3, 4.4), CFrame.new(side * 10, 2.7, 1.0), theme.Metal, Metal, true)
		piece(kit, "ArmFootTrim", Vector3.new(4.2, 0.3, 4.6), CFrame.new(side * 10, 4.3, 1.0), theme.Gold, Metal, false)
		-- Aberturas de ventilação na frente do pé (brilho baixo da forja).
		for vent = 0, 1 do
			piece(kit, "FootVent", Vector3.new(2.8, 0.22, 0.12), CFrame.new(side * 10, 2.3 + vent * 0.7, -1.23), theme.Energy, Neon, false, 0.55)
		end
		-- Cabo do pé do braço até a lateral da fenda.
		tube(kit, "ForgeCable", Vector3.new(side * 8.6, 2.0, 2.6), Vector3.new(side * 5.4, 3.0, 3.9), 0.4, theme.Metal)
		local arm = strut(kit, "ConductorArm", foot, tip, 2.2, 2.6, theme.Stone, Slate, true)
		local armLocal = base:ToObjectSpace(arm.CFrame) -- o braço no referencial da forja
		for _, along in { -3, 3 } do
			piece(kit, "ArmBand", Vector3.new(2.5, 0.35, 2.9), armLocal * CFrame.new(0, along, 0), theme.Gold, Metal, false)
		end
		piece(kit, "ArmEnergy", Vector3.new(0.3, 8.6, 0.3), armLocal * CFrame.new(-side * 1.12, 0, -0.7), theme.Energy, Neon, false, 0.45)
		piece(kit, "EmitterHead", Vector3.new(2.6, 2.0, 3.0), armLocal * CFrame.new(0, (tip - foot).Magnitude / 2, 0), theme.Metal, Metal, false)
		local aim = (slashCentre - tip).Unit
		crystal(kit, "EmitterCrystal", tip + aim * 1.6, 1.6, Vector3.new(0, 0, side * 55), theme.Crystal)
	end

	-- Placa de fundo com a "fenda" e a cornija com a placa CORTES.
	piece(kit, "ForgeBack", Vector3.new(9, 10.4, 1.2), CFrame.new(0, 7.2, 4.2), theme.Plate, Enum.Material.DiamondPlate, true)
	for _, side in { -1, 1 } do
		piece(kit, "BackPilaster", Vector3.new(1, 10.4, 1.6), CFrame.new(side * 4.9, 7.2, 4.0), theme.StoneDark, Slate, true)
	end
	-- Costelas e contrafortes: a placa de fundo ganha relevo e corpo.
	for _, y in { 4.4, 10.0 } do
		piece(kit, "BackRib", Vector3.new(8.8, 0.34, 0.26), CFrame.new(0, y, 3.55), theme.Gold, Metal, false)
	end
	for _, side in { -1, 1 } do
		wedge(kit, "BackButtress", Vector3.new(1.4, 6, 1.2), CFrame.new(side * 4.9, 4.2, 5.4) * CFrame.Angles(0, math.rad(180), 0), theme.StoneDark, Slate)
	end
	piece(kit, "Rift", Vector3.new(0.9, 8.6, 0.1), CFrame.new(0, 7.6, 3.55) * CFrame.Angles(0, 0, math.rad(-34)), Color3.fromRGB(20, 14, 18), Enum.Material.SmoothPlastic, false)
	piece(kit, "Cornice", Vector3.new(12, 1.7, 2.8), CFrame.new(0, 13.25, 4.0), theme.Stone, Slate, true)
	nameplate(kit, CFrame.new(0, 13.35, 2.48), options.Title, options.Subtitle, 8.4)
	-- Coroa de estilhaços (silhueta de longe: "chama/fragmento", não ⬆).
	crystal(kit, "CrownShard", Vector3.new(0, 15.3, 4.0), 2.6, Vector3.new(0, 0, 0), theme.Crystal)
	crystal(kit, "CrownShard", Vector3.new(-1.3, 14.7, 4.1), 1.6, Vector3.new(0, 10, 24), theme.Crystal)
	crystal(kit, "CrownShard", Vector3.new(1.3, 14.7, 4.1), 1.6, Vector3.new(0, -10, -24), theme.Crystal)

	-- O SLASH: arco de energia em três trechos + véu de brilho atrás, que
	-- pulsa e, de tempos em tempos, dá um clarão curto (mini-impacto).
	local slashFrame = CFrame.new(slashCentre)
	local slashParts = {
		piece(kit, "CutSlash", Vector3.new(0.34, 5.2, 0.2), slashFrame * CFrame.Angles(0, 0, math.rad(-32)), theme.Core, Neon, false, 0.05),
		piece(kit, "CutSlash", Vector3.new(0.24, 3.2, 0.18), slashFrame * CFrame.Angles(0, 0, math.rad(-32)) * CFrame.new(0, 3.6, 0) * CFrame.Angles(0, 0, math.rad(-16)), theme.Core, Neon, false, 0.15),
		piece(kit, "CutSlash", Vector3.new(0.24, 3.2, 0.18), slashFrame * CFrame.Angles(0, 0, math.rad(-32)) * CFrame.new(0, -3.6, 0) * CFrame.Angles(0, 0, math.rad(16)), theme.Core, Neon, false, 0.15),
	}
	local veil = piece(kit, "CutSlashVeil", Vector3.new(1.2, 9.4, 0.1), slashFrame * CFrame.new(0, 0, 0.25) * CFrame.Angles(0, 0, math.rad(-32)), theme.Core, Neon, false, 0.8)
	for _, part in slashParts do
		part:AddTag(StationMachines.TAG_CUT_TINT)
		part:AddTag(StationMachines.TAG_CORE)
	end
	veil:AddTag(StationMachines.TAG_CUT_TINT)
	veil:AddTag(StationMachines.TAG_FLASH)
	local sparks = emitter(slashParts[1], "ForgeSparks", theme.Core, 5, NumberRange.new(2, 4), NumberRange.new(0.5, 0.9), 0.16, 180, Vector3.new(0, -9, 0))
	sparks:AddTag(StationMachines.TAG_CUT_TINT)
	-- Fragmentos orbitando o slash (devagar).
	local fragments = Instance.new("Model")
	fragments.Name = "SlashFragments"
	for index = 0, 3 do
		local angle = index * math.pi / 2 + 0.4
		local at = slashCentre + Vector3.new(math.cos(angle) * 3.4, math.sin(angle) * 3.4, -0.2)
		piece(kit, "Fragment", Vector3.new(0.45, 0.9, 0.45), CFrame.new(at) * CFrame.Angles(math.rad(25), math.rad(45), math.rad(index * 40)), theme.Crystal, Enum.Material.Glass, false, 0.2, nil, fragments)
	end
	fragments:SetAttribute("SpinSpeed", 14)
	fragments:SetAttribute("Centre", (base * slashFrame).Position)
	fragments:SetAttribute("Axis", (base * slashFrame).LookVector)
	atomic(fragments)
	fragments.Parent = model
	fragments:AddTag(StationMachines.TAG_RING)

	-- Bigorna tecnológica (mesa de forja) na frente da lareira.
	local anvilZ = -2.2
	piece(kit, "AnvilFoot", Vector3.new(2.6, 0.6, 1.8), CFrame.new(0, 2.3, anvilZ), theme.Metal, Metal, true)
	piece(kit, "AnvilWaist", Vector3.new(1.3, 1.2, 1.1), CFrame.new(0, 3.2, anvilZ), theme.Metal, Metal, true)
	piece(kit, "AnvilTop", Vector3.new(3.8, 0.8, 1.7), CFrame.new(0, 4.2, anvilZ), theme.Plate, Metal, true)
	wedge(kit, "AnvilHorn", Vector3.new(1.7, 0.8, 1.6), CFrame.new(-2.7, 4.2, anvilZ) * CFrame.Angles(0, math.rad(90), 0), theme.Plate, Metal)
	piece(kit, "AnvilTrim", Vector3.new(3.9, 0.14, 0.14), CFrame.new(0, 3.84, anvilZ - 0.86), theme.Gold, Metal, false)
	local inlay = piece(kit, "AnvilInlay", Vector3.new(3.2, 0.06, 0.26), CFrame.new(0, 4.63, anvilZ), theme.Core, Neon, false, 0.2)
	inlay:AddTag(StationMachines.TAG_CUT_TINT)

	-- Trilho de energia no chão ligando a forja à galeria (um "tap" por pad).
	local railLength = 0
	for _, x in galleryXs do
		railLength = math.max(railLength, math.abs(x) * 2 + 4)
		piece(kit, "RailTap", Vector3.new(1.4, 0.18, 1.4), CFrame.new(x, 0.46, railZ), theme.Gold, Metal, false)
	end
	piece(kit, "ForgeRail", Vector3.new(railLength, 0.06, 0.36), CFrame.new(0, 0.44, railZ), theme.Energy, Neon, false, 0.6)

	model:SetAttribute("PartCount", kit.Count)
	model:SetAttribute("Prototype", "StationMachine")
	model.Parent = parent
	return model
end

-- ── Estação de Companheiros (Pets) ──────────────────────────────────────────

-- Cilindro de pé (eixo em Y) com centro em `at`.
local function upright(kit: Kit, name: string, at: Vector3, height: number, diameter: number, color: Color3, material: Enum.Material, collide: boolean?, transparency: number?, parent: Instance?): Part
	return piece(kit, name, Vector3.new(height, diameter, diameter), CFrame.new(at) * UPRIGHT, color, material, collide, transparency, Enum.PartType.Cylinder, parent)
end

-- Disco de frente (eixo em Z) com centro em `at`.
local function facingDisc(kit: Kit, name: string, at: Vector3, thickness: number, diameter: number, color: Color3, material: Enum.Material, transparency: number?): Part
	return piece(kit, name, Vector3.new(thickness, diameter, diameter), CFrame.new(at) * FACING, color, material, false, transparency, Enum.PartType.Cylinder)
end

-- Pegada (🐾) em discos: almofada + 4 dedos. `frame` = centro, plano XY local.
local function pawPrint(kit: Kit, name: string, frame: CFrame, size: number, color: Color3, material: Enum.Material, flat: boolean)
	local function toe(offset: Vector3, diameter: number)
		local at = frame * CFrame.new(offset * size)
		if flat then
			piece(kit, name, Vector3.new(0.06, diameter * size, diameter * size), at * UPRIGHT, color, material, false, nil, Enum.PartType.Cylinder)
		else
			piece(kit, name, Vector3.new(0.2, diameter * size, diameter * size), at * FACING, color, material, false, nil, Enum.PartType.Cylinder)
		end
	end
	local function v(x: number, y: number): Vector3
		-- No chão os dedos apontam para +Z (para a estação).
		return if flat then Vector3.new(x, 0, y) else Vector3.new(x, y, 0)
	end
	toe(v(0, -0.22), 1.0)
	toe(v(-0.62, 0.42), 0.42)
	toe(v(-0.22, 0.7), 0.42)
	toe(v(0.22, 0.7), 0.42)
	toe(v(0.62, 0.42), 0.42)
end

-- Holograma de um pet (a arte enviada, num BillboardGui pequeno dentro da
-- cápsula). Só imagem: não é pet de verdade, não salva, não equipa.
local function hologram(kit: Kit, at: Vector3, image: string?, size: number, tint: Color3)
	local anchor = piece(kit, "PetHologram", Vector3.new(0.2, 0.2, 0.2), CFrame.new(at), tint, Enum.Material.SmoothPlastic, false, 1)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Hologram"
	gui.Size = UDim2.fromScale(size, size)
	gui.MaxDistance = 70
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	if image and image ~= "" then
		local picture = Instance.new("ImageLabel")
		picture.Name = "Art"
		picture.Size = UDim2.fromScale(1, 1)
		picture.BackgroundTransparency = 1
		picture.Image = image
		picture.ImageColor3 = Color3.new(1, 1, 1):Lerp(tint, 0.15)
		picture.ImageTransparency = 0.15
		picture.Parent = gui
	end
	gui.Parent = anchor
	anchor:AddTag(StationMachines.TAG_HOLO)
end

export type PetLabOptions = {
	Title: string,
	Subtitle: string,
	Previews: { string }, -- imagens dos 3 previews (rbxassetid), esquerda → direita
}

--[[
	ESTAÇÃO DE COMPANHEIROS. Silhueta HORIZONTAL, aberta e amigável (nada de
	colunas com núcleo): três cápsulas de vidro sobre pedestais — a do meio
	um pouco maior — com hologramas de pets flutuando dentro, uma parede de
	laboratório baixa atrás com um tubo ligando as cápsulas e dois tanques
	nas pontas, a placa e um emblema de PATA (🐾) em peças acima dela, um
	terminal redondo e baixo na frente (o prompt de Pets de sempre) e uma
	pegada no chão marcando onde ficar. Sem NPC.
	Referência local: -Z = frente.
]]
function StationMachines.BuildPetLab(parent: Instance, base: CFrame, panel: string, options: PetLabOptions): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = "Station_" .. panel .. "_Machine"
	local theme = StationMachines.Themes.Pets
	local kit: Kit = { Parent = model, Base = base, Theme = theme, Count = 0 }
	local Slate, Metal, Neon, Glass = Enum.Material.Slate, Enum.Material.Metal, Enum.Material.Neon, Enum.Material.Glass
	local floorTop = 0.6

	-- Base larga e baixa com bisel na frente.
	piece(kit, "LabBase", Vector3.new(21, 0.6, 10), CFrame.new(0, floorTop + 0.3, 0.5), theme.StoneDark, Slate, true)
	wedge(kit, "LabBevel", Vector3.new(21, 0.6, 1.2), CFrame.new(0, floorTop + 0.3, -5.1), theme.StoneDark, Slate)
	piece(kit, "LabTrim", Vector3.new(21.2, 0.14, 0.2), CFrame.new(0, floorTop + 0.62, -4.5), theme.Gold, Metal, false)
	local top = floorTop + 0.6

	-- Parede de laboratório baixa, tubo de cima, tanques nas pontas.
	piece(kit, "LabWall", Vector3.new(19, 5, 0.8), CFrame.new(0, top + 2.5, 3.6), theme.Plate, Enum.Material.DiamondPlate, true)
	piece(kit, "LabWallTrim", Vector3.new(19.2, 0.3, 0.3), CFrame.new(0, top + 0.8, 3.15), theme.Gold, Metal, false)
	piece(kit, "LabPipe", Vector3.new(19.4, 0.8, 0.8), CFrame.new(0, top + 5.3, 3.3), theme.Metal, Metal, false, nil, Enum.PartType.Cylinder)
	for _, side in { -1, 1 } do
		upright(kit, "LabTank", Vector3.new(side * 10.2, top + 2.7, 2.6), 5.4, 2.6, theme.Metal, Metal, true)
		piece(kit, "TankWindow", Vector3.new(0.9, 3.4, 0.12), CFrame.new(side * 10.2, top + 2.7, 1.28), theme.Energy, Neon, false, 0.55)
		upright(kit, "TankCap", Vector3.new(side * 10.2, top + 5.6, 2.6), 0.4, 2.9, theme.Gold, Metal, false)
	end

	-- Cápsulas: pedestal, aro dourado, disco de energia, tubo de vidro, tampa
	-- com aro de energia, cano até o tubo de cima e o holograma do pet.
	local slots = { -6.4, 0, 6.4 }
	for index, x in slots do
		local scale = if index == 2 then 1.15 else 1
		local z = 0.4
		upright(kit, "CapsulePedestal", Vector3.new(x, top + 0.5 * scale, z), 1.0 * scale, 3.6 * scale, theme.Metal, Metal, true)
		upright(kit, "CapsuleRing", Vector3.new(x, top + 1.05 * scale, z), 0.24, 3.9 * scale, theme.Gold, Metal, false)
		upright(kit, "CapsuleFloor", Vector3.new(x, top + 1.08 * scale, z), 0.08, 2.4 * scale, theme.Core, Neon, false, 0.35)
		local glassBottom = top + 1.1 * scale
		local glassHeight = 4.2 * scale
		upright(kit, "CapsuleGlass", Vector3.new(x, glassBottom + glassHeight / 2, z), glassHeight, 3.0 * scale, theme.Crystal, Glass, false, 0.72)
		local capY = glassBottom + glassHeight + 0.3
		upright(kit, "CapsuleCap", Vector3.new(x, capY, z), 0.6, 3.6 * scale, theme.Metal, Metal, false)
		upright(kit, "CapsuleGlow", Vector3.new(x, capY - 0.34, z), 0.08, 2.7 * scale, theme.Energy, Neon, false, 0.65)
		tube(kit, "CapsuleFeed", Vector3.new(x, capY + 0.3, z + 0.6), Vector3.new(x, top + 5.3, 3.0), 0.36, theme.Metal)
		hologram(kit, Vector3.new(x, glassBottom + glassHeight * 0.5, z), options.Previews[index], 2.3 * scale, theme.Core)
	end
	local middle = model:FindFirstChild("CapsuleFloor") :: BasePart
	emitter(middle, "LabBubbles", theme.Crystal, 3, NumberRange.new(0.5, 0.9), NumberRange.new(2.0, 2.8), 0.14, 10, Vector3.new(0, 0.3, 0))

	-- Placa e emblema de pata acima da parede.
	piece(kit, "LabHeader", Vector3.new(11, 1.9, 1.2), CFrame.new(0, top + 5.95, 3.6), theme.Stone, Slate, true)
	nameplate(kit, CFrame.new(0, top + 6.2, 2.9), options.Title, options.Subtitle, 8)
	facingDisc(kit, "PawCrest", Vector3.new(0, top + 9.2, 3.7), 0.4, 3.6, theme.StoneDark, Slate)
	facingDisc(kit, "PawCrestRim", Vector3.new(0, top + 9.2, 3.95), 0.2, 4.0, theme.Gold, Metal)
	pawPrint(kit, "PawEmblem", CFrame.new(0, top + 9.05, 3.4), 2.0, theme.Energy, Neon, false)

	-- Terminal redondo e baixo, inclinado para quem chega (prompt de Pets).
	local termZ = -2.8
	upright(kit, "TerminalBase", Vector3.new(0, top + 0.12, termZ), 0.24, 2.4, theme.Gold, Metal, false)
	upright(kit, "TerminalStem", Vector3.new(0, top + 1.2, termZ), 2.2, 1.0, theme.Metal, Metal, true)
	local tilt = CFrame.new(0, top + 2.45, termZ) * CFrame.Angles(math.rad(-30), 0, 0)
	local head = piece(kit, "Station_" .. panel, Vector3.new(3.0, 0.45, 2.1), tilt, theme.Plate, Metal, true)
	local screen = piece(kit, "TerminalScreen", Vector3.new(2.4, 0.05, 1.5), tilt * CFrame.new(0, 0.25, 0.05), Color3.fromRGB(20, 18, 34), Enum.Material.SmoothPlastic, false)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Screen"
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 0
	gui.MaxDistance = 60
	local paw = Instance.new("TextLabel")
	paw.Name = "Arrow"
	paw.BackgroundTransparency = 1
	paw.Size = UDim2.fromScale(1, 0.9)
	paw.Position = UDim2.fromScale(0, 0.05)
	paw.Font = Enum.Font.GothamBlack
	paw.TextScaled = true
	paw.TextColor3 = theme.Core
	paw.Text = "🐾"
	paw.Parent = gui
	gui.Parent = screen
	screen:AddTag(StationMachines.TAG_SCREEN)

	-- Onde ficar: uma pegada gravada no piso, na frente do terminal.
	upright(kit, "PawPad", Vector3.new(0, floorTop + 0.04, -7.6), 0.08, 4.4, theme.Plate, Metal, true)
	pawPrint(kit, "PawFloor", CFrame.new(0, floorTop + 0.1, -7.4), 1.7, shade(theme.Gold, 0.8), Metal, true)

	model:SetAttribute("PartCount", kit.Count)
	model:SetAttribute("Prototype", "StationMachine")
	model.Parent = parent
	return model, head
end

-- ── Altar do Renascimento ───────────────────────────────────────────────────

--[[
	ALTAR DO RENASCIMENTO. Ritual, não loja nem máquina: um dais CIRCULAR em
	degraus com runas douradas e uma rampa na frente, o círculo ritual
	violeta no topo, quatro obeliscos nas diagonais (a frente fica aberta),
	e um HALO vertical de pedra com filetes violeta virado para a praça — a
	silhueta "◎" de longe —, com a placa "♻ RENASCER" no alto. No centro, um
	cristal violeta com brilho claro por dentro flutua sobre um pilar, com
	fragmentos orbitando. Sem console: o prompt de Renascer de sempre fica
	no próprio núcleo.

	Movimento (cliente): círculo pulsa devagar, núcleo gira, fragmentos
	orbitam; com o jogador perto, partículas sobem do círculo; quando ele
	RENASCE de verdade (Stats.Rebirths sobe), uma rajada local sobe do altar.
	Referência local: -Z = frente (para a praça).
]]
function StationMachines.BuildRebirthAltar(parent: Instance, base: CFrame, options: PlateOptions, floorTop: number): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = "Station_Rebirth_Machine"
	local theme = StationMachines.Themes.Rebirth
	local kit: Kit = { Parent = model, Base = base, Theme = theme, Count = 0 }
	local Slate, Metal, Neon, Marble = Enum.Material.Slate, Enum.Material.Metal, Enum.Material.Neon, Enum.Material.Marble

	-- Dais circular em três degraus + rampa de frente.
	local step1 = floorTop + 0.6
	local step2 = step1 + 0.6
	local top = step2 + 0.6
	upright(kit, "AltarRing", Vector3.new(0, floorTop + 0.3, 0), 0.6, 19, theme.StoneDark, Slate, true)
	upright(kit, "AltarRim", Vector3.new(0, step1 + 0.01, 0), 0.04, 19.4, theme.Gold, Metal, false)
	upright(kit, "AltarStep", Vector3.new(0, step1 + 0.3, 0), 0.6, 14, theme.Stone, Slate, true)
	upright(kit, "AltarTop", Vector3.new(0, step2 + 0.3, 0), 0.6, 9.2, Color3.fromRGB(226, 220, 232), Marble, true)
	local circle = upright(kit, "RitualCircle", Vector3.new(0, top + 0.03, 0), 0.06, 7, theme.Energy, Neon, false, 0.55)
	circle:AddTag(StationMachines.TAG_CORE)
	wedge(kit, "AltarRamp", Vector3.new(4.6, top - floorTop, 5.6), CFrame.new(0, (top + floorTop) / 2, -7.2), theme.Stone, Slate)
	-- Runas douradas no primeiro degrau (fora da rampa).
	for index = 0, 7 do
		local angle = (index + 0.5) * math.pi / 4
		if math.abs(math.cos(angle) * 8.2) > 2.8 or math.sin(angle) > 0 then
			local at = Vector3.new(math.cos(angle) * 8.2, step1 + 0.05, math.sin(angle) * 8.2)
			piece(kit, "Rune", Vector3.new(1.1, 0.08, 0.6), CFrame.new(at) * CFrame.Angles(0, -angle, 0), theme.Gold, Metal, false)
		end
	end
	-- Canais do pé dos obeliscos até o círculo (a energia converge).
	for index, angle in { math.rad(45), math.rad(135), math.rad(225), math.rad(315) } do
		local from = Vector3.new(math.cos(angle) * 6.6, step2 + 0.62, math.sin(angle) * 6.6)
		local to = Vector3.new(math.cos(angle) * 3.4, top + 0.04, math.sin(angle) * 3.4)
		local length = (to - from).Magnitude
		local channel = piece(kit, "RebirthChannel", Vector3.new(0.3, 0.06, length), CFrame.lookAt((from + to) / 2, to), theme.Energy, Neon, false, 0.55)
		channel:SetAttribute("Order", 1 + (index % 2))
		channel:AddTag(StationMachines.TAG_PULSE)
	end

	-- Quatro obeliscos nas diagonais: pedra, capitel dourado, cristal violeta.
	for _, angle in { math.rad(45), math.rad(135), math.rad(225), math.rad(315) } do
		local at = Vector3.new(math.cos(angle) * 8, 0, math.sin(angle) * 8)
		piece(kit, "Obelisk", Vector3.new(1.4, 6.4, 1.4), CFrame.new(at.X, step1 + 3.2, at.Z) * CFrame.Angles(0, angle, 0), theme.StoneDark, Slate, true)
		piece(kit, "ObeliskCap", Vector3.new(1.7, 0.4, 1.7), CFrame.new(at.X, step1 + 6.6, at.Z) * CFrame.Angles(0, angle, 0), theme.Gold, Metal, false)
		crystal(kit, "ObeliskCrystal", Vector3.new(at.X, step1 + 7.8, at.Z), 1.9, Vector3.new(0, 0, 0), theme.Crystal)
	end

	-- Halo vertical virado para a praça, sobre dois pés, com a placa no alto.
	local haloCentre = Vector3.new(0, top + 7.2, 2.4)
	local haloRadius = 6.6
	for index = 0, 7 do
		local angle = index * math.pi / 4 + math.pi / 8
		local frame = CFrame.new(haloCentre) * CFrame.Angles(0, 0, angle) * CFrame.new(haloRadius, 0, 0)
		local length = 2 * haloRadius * math.tan(math.pi / 8) + 0.5
		piece(kit, "HaloSegment", Vector3.new(1.1, length, 1.1), frame, theme.Stone, Slate, false)
		piece(kit, "HaloGlow", Vector3.new(0.14, length - 0.4, 0.5), frame * CFrame.new(-0.62, 0, -0.2), theme.Energy, Neon, false, 0.45)
	end
	for _, side in { -1, 1 } do
		strut(kit, "HaloFoot", Vector3.new(side * 3.6, step2, 2.4), Vector3.new(side * 2.4, top + 1.2, 2.4), 1.0, 1.0, theme.StoneDark, Slate, true)
	end
	local crestY = haloCentre.Y + haloRadius + 1.3
	piece(kit, "HaloCrest", Vector3.new(9.4, 1.8, 1.4), CFrame.new(0, crestY, 2.4), theme.StoneDark, Slate, false)
	nameplate(kit, CFrame.new(0, crestY + 0.1, 1.62), options.Title, options.Subtitle, 7.6)

	-- Núcleo: pilar central (ninguém fica dentro do cristal), cristal violeta
	-- com brilho claro por dentro, e fragmentos orbitando.
	upright(kit, "CorePillar", Vector3.new(0, top + 1.0, 0), 2.0, 2.4, theme.Stone, Marble, true)
	upright(kit, "CorePillarCap", Vector3.new(0, top + 2.05, 0), 0.2, 2.8, theme.Gold, Metal, false)
	local coreCentre = Vector3.new(0, top + 6.4, 0)
	local shell = piece(kit, "RebirthCrystal", Vector3.new(2.2, 3.8, 2.2), CFrame.new(coreCentre) * CFrame.Angles(0, math.rad(45), 0), theme.Crystal, Enum.Material.Glass, false, 0.35)
	shell:SetAttribute("SpinSpeed", 16)
	shell:AddTag(StationMachines.TAG_SPIN)
	local core = piece(kit, "RebirthCore", Vector3.new(1.3, 2.4, 1.3), CFrame.new(coreCentre) * CFrame.Angles(0, math.rad(20), 0), theme.Core, Neon, false, 0.1)
	core:SetAttribute("SpinSpeed", -22)
	core:AddTag(StationMachines.TAG_SPIN)
	core:AddTag(StationMachines.TAG_CORE)
	local shards = Instance.new("Model")
	shards.Name = "RebirthShards"
	for index = 0, 5 do
		local angle = index * math.pi / 3
		local at = coreCentre + Vector3.new(math.cos(angle) * 3, math.sin(index * 1.7) * 0.5, math.sin(angle) * 3)
		piece(kit, "Shard", Vector3.new(0.4, 0.9, 0.4), CFrame.new(at) * CFrame.Angles(math.rad(20), angle, math.rad(15)), if index % 2 == 0 then theme.Gold else theme.Crystal, if index % 2 == 0 then Metal else Enum.Material.Glass, false, if index % 2 == 0 then 0 else 0.2, nil, shards)
	end
	shards:SetAttribute("SpinSpeed", 18)
	shards:SetAttribute("Centre", (base * CFrame.new(coreCentre)).Position)
	shards:SetAttribute("Axis", (base * CFrame.new(coreCentre)).UpVector)
	atomic(shards)
	shards.Parent = model
	shards:AddTag(StationMachines.TAG_RING)

	-- Partículas: poucas subindo do círculo (mais com o jogador perto) e a
	-- rajada do renascimento (só quando acontece).
	local rise = emitter(circle, "RebirthRise", theme.Crystal, 1, NumberRange.new(1.5, 2.6), NumberRange.new(1.4, 2.2), 0.2, 15, Vector3.new(0, 1.0, 0))
	rise:SetAttribute("IdleRate", 1)
	rise:SetAttribute("EngagedRate", 7)
	rise:AddTag(StationMachines.TAG_RISE)
	local burst = emitter(circle, "RebirthBurst", theme.Core, 0, NumberRange.new(6, 10), NumberRange.new(0.8, 1.3), 0.35, 40, Vector3.new(0, 2, 0))
	burst:AddTag(StationMachines.TAG_BURST)
	core:AddTag(StationMachines.TAG_ENGAGE)

	model:SetAttribute("PartCount", kit.Count)
	model:SetAttribute("Prototype", "StationMachine")
	model.Parent = parent
	return model, core
end

-- ── Campo de Treinamento ────────────────────────────────────────────────────

export type TrainingSpot = {
	Id: string,
	Kind: string, -- Dummy / Scarecrow / Warrior / Guardian (TrainingConfig)
	Tier: number, -- 1..4 (ordem)
	Centre: Vector3, -- relativo ao centro da área
	Radius: number, -- meio pedestal (= raio do treino)
	Name: string,
	Rebirths: number, -- renascimentos exigidos (0 = livre)
	Locked: string, -- "🔒 REQUER ♻ 3 RENASCIMENTOS" / "LIVRE"
	Unlocked: string, -- "♻ 3 RENASCIMENTOS" / "LIVRE"
}

-- Tags do Campo de Treinamento (cliente: TrainingFieldController).
StationMachines.TAG_TRAINING = "TrainingStation" -- Model de cada alvo (atributos Station, Tier, RequiredRebirths, Reaction)
StationMachines.TAG_TRAINING_ENERGY = "TrainingEnergy" -- peça de energia: apagada enquanto bloqueado, responde ao golpe

local ROMAN = { "I", "II", "III", "IV" }
-- Cor da faixa de cada tier: madeira → prata → energia → ouro.
local TIER_COLORS = {
	Color3.fromRGB(176, 120, 72),
	Color3.fromRGB(176, 184, 198),
	Color3.fromRGB(90, 200, 255),
	Color3.fromRGB(232, 184, 80),
}
local REACTIONS = { Dummy = "Sway", Scarecrow = "Vibrate", Warrior = "Energy", Guardian = "Pulse" }

-- Peça de energia (Neon/Glass) que o cliente apaga no bloqueio e acende no golpe.
local function energy(part: BasePart): BasePart
	part:SetAttribute("BaseTransparency", part.Transparency)
	part:AddTag(StationMachines.TAG_TRAINING_ENERGY)
	return part
end

-- Placa do alvo: poste baixo + placa (tier, nome, requisito) e o cadeado.
local function trainingPlaque(kit: Kit, at: CFrame, spot: TrainingSpot, model: Model)
	local theme = kit.Theme
	-- Baixa (topo ≈ 2,4 studs): não esconde o boneco de quem olha de frente.
	piece(kit, "PlaquePost", Vector3.new(0.45, 1.2, 0.45), at * CFrame.new(0, 0.6, 0.3), theme.Metal, Enum.Material.Metal, false)
	local tilt = CFrame.Angles(math.rad(-24), 0, 0)
	local board = piece(kit, "TrainingPlaque_" .. spot.Id, Vector3.new(5.2, 1.5, 0.2), at * CFrame.new(0, 1.5, 0) * tilt, theme.Metal, Enum.Material.Metal, false)
	piece(kit, "PlaqueBand", Vector3.new(5.4, 0.2, 0.24), at * CFrame.new(0, 2.2, 0.32) * tilt, TIER_COLORS[spot.Tier], Enum.Material.Metal, false)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Text"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0.2
	gui.MaxDistance = 45
	local function label(name: string, text: string, position: UDim2, size: UDim2, color: Color3, align: Enum.TextXAlignment)
		local item = Instance.new("TextLabel")
		item.Name = name
		item.BackgroundTransparency = 1
		item.Position = position
		item.Size = size
		item.Font = Enum.Font.GothamBlack
		item.TextScaled = true
		item.TextColor3 = color
		item.TextXAlignment = align
		item.Text = text
		item.Parent = gui
	end
	label("Tier", ROMAN[spot.Tier], UDim2.fromScale(0.02, 0.1), UDim2.fromScale(0.18, 0.8), TIER_COLORS[spot.Tier], Enum.TextXAlignment.Center)
	label("Name", StationMachines.Upper(spot.Name), UDim2.fromScale(0.23, 0.08), UDim2.fromScale(0.74, 0.46), Color3.fromRGB(240, 244, 252), Enum.TextXAlignment.Left)
	label("Requirement", spot.Locked, UDim2.fromScale(0.23, 0.58), UDim2.fromScale(0.74, 0.32), theme.Crystal, Enum.TextXAlignment.Left)
	gui.Parent = board
	board:SetAttribute("LockedText", spot.Locked)
	board:SetAttribute("UnlockedText", spot.Unlocked)
	if spot.Rebirths > 0 then
		-- Cadeado discreto no canto da placa (some quando o jogador libera).
		local lock = Instance.new("Model")
		lock.Name = "Padlock"
		local corner = at * CFrame.new(2.3, 2.75, 0.4)
		local gold = Color3.fromRGB(206, 170, 92)
		piece(kit, "PadlockBody", Vector3.new(0.8, 0.66, 0.3), corner, gold, Enum.Material.Metal, false, nil, nil, lock)
		piece(kit, "PadlockKeyhole", Vector3.new(0.14, 0.26, 0.06), corner * CFrame.new(0, -0.04, -0.16), Color3.fromRGB(30, 30, 36), Enum.Material.SmoothPlastic, false, nil, nil, lock)
		for _, side in { -1, 1 } do
			piece(kit, "PadlockShackle", Vector3.new(0.12, 0.5, 0.12), corner * CFrame.new(side * 0.24, 0.52, 0), Color3.fromRGB(196, 200, 210), Enum.Material.Metal, false, nil, nil, lock)
		end
		piece(kit, "PadlockShackle", Vector3.new(0.6, 0.12, 0.12), corner * CFrame.new(0, 0.77, 0), Color3.fromRGB(196, 200, 210), Enum.Material.Metal, false, nil, nil, lock)
		lock.Parent = model
	end
end

--[[
	Pedestal de cada alvo: o PISO diz o tier sem texto.
	  I   tablado de madeira, borda de toras, alvo pintado;
	  II  pedra com chapa xadrez, moldura de metal e parafusos, "X" de metal;
	  III pedra em dois degraus, chapa de metal, filetes de energia, losango;
	  IV  base de pedra + degrau de mármore, friso dourado, quatro pilares
	      com runas e um círculo de runas que gira devagar.
	`kit.Base` = centro do pedestal no chão, -Z = frente (para a entrada).
]]
local function trainingPedestal(kit: Kit, spot: TrainingSpot, floorTop: number): number
	local theme = kit.Theme
	local side = spot.Radius * 2
	local half = spot.Radius
	local Metal, Slate, Neon = Enum.Material.Metal, Enum.Material.Slate, Enum.Material.Neon
	local tier = spot.Tier
	local top
	if tier == 1 then
		top = floorTop + 0.5
		piece(kit, "Pedestal", Vector3.new(side, 0.5, side), CFrame.new(0, floorTop + 0.25, 0), Color3.fromRGB(150, 108, 70), Enum.Material.WoodPlanks, true)
		for _, rot in { 0, 90 } do
			for _, s in { -1, 1 } do
				local frame = CFrame.Angles(0, math.rad(rot), 0) * CFrame.new(0, top + 0.05, s * (half - 0.3))
				piece(kit, "PedestalLog", Vector3.new(side - 0.2, 0.55, 0.55), frame, Color3.fromRGB(120, 84, 52), Enum.Material.Wood, false, nil, Enum.PartType.Cylinder)
			end
		end
		-- Alvo pintado no chão (onde ficar).
		piece(kit, "PedestalSymbol", Vector3.new(0.06, 3.0, 3.0), CFrame.new(0, top + 0.03, -half * 0.35) * UPRIGHT, Color3.fromRGB(196, 72, 60), Enum.Material.SmoothPlastic, false, nil, Enum.PartType.Cylinder)
		piece(kit, "PedestalSymbol", Vector3.new(0.08, 1.6, 1.6), CFrame.new(0, top + 0.04, -half * 0.35) * UPRIGHT, Color3.fromRGB(236, 224, 200), Enum.Material.SmoothPlastic, false, nil, Enum.PartType.Cylinder)
	elseif tier == 2 then
		top = floorTop + 0.7
		piece(kit, "Pedestal", Vector3.new(side, 0.7, side), CFrame.new(0, floorTop + 0.35, 0), theme.StoneDark, Slate, true)
		piece(kit, "PedestalTop", Vector3.new(side - 1.4, 0.08, side - 1.4), CFrame.new(0, top + 0.04, 0), theme.Plate, Enum.Material.DiamondPlate, false)
		for _, rot in { 0, 90 } do
			for _, s in { -1, 1 } do
				piece(kit, "PedestalBorder", Vector3.new(side, 0.24, 0.5), CFrame.Angles(0, math.rad(rot), 0) * CFrame.new(0, top + 0.12, s * (half - 0.25)), TIER_COLORS[2], Metal, false)
			end
		end
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				piece(kit, "PedestalBolt", Vector3.new(0.3, 0.7, 0.7), CFrame.new(sx * (half - 0.6), top + 0.2, sz * (half - 0.6)) * UPRIGHT, theme.Metal, Metal, false, nil, Enum.PartType.Cylinder)
			end
		end
		for _, angle in { 45, -45 } do
			piece(kit, "PedestalSymbol", Vector3.new(0.45, 0.06, 3.2), CFrame.new(0, top + 0.1, -half * 0.4) * CFrame.Angles(0, math.rad(angle), 0), TIER_COLORS[2], Metal, false)
		end
	elseif tier == 3 then
		top = floorTop + 1.1
		piece(kit, "Pedestal", Vector3.new(side, 0.6, side), CFrame.new(0, floorTop + 0.3, 0), theme.StoneDark, Slate, true)
		piece(kit, "PedestalStep", Vector3.new(side - 1.2, 0.5, side - 1.2), CFrame.new(0, floorTop + 0.85, 0), theme.Stone, Slate, true)
		piece(kit, "PedestalTop", Vector3.new(side - 2.4, 0.06, side - 2.4), CFrame.new(0, top + 0.03, 0), theme.Plate, Metal, false)
		for _, rot in { 0, 90 } do
			for _, s in { -1, 1 } do
				energy(piece(kit, "PedestalEnergy", Vector3.new(side - 2.0, 0.08, 0.22), CFrame.Angles(0, math.rad(rot), 0) * CFrame.new(0, top + 0.04, s * (half - 1.0)), TIER_COLORS[3], Neon, false, 0.35))
			end
		end
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				piece(kit, "PedestalPost", Vector3.new(0.7, 1.6, 0.7), CFrame.new(sx * (half - 0.35), floorTop + 0.8, sz * (half - 0.35)), theme.Metal, Metal, false)
			end
		end
		energy(piece(kit, "PedestalSymbol", Vector3.new(1.8, 0.07, 1.8), CFrame.new(0, top + 0.05, -half * 0.42) * CFrame.Angles(0, math.rad(45), 0), TIER_COLORS[3], Neon, false, 0.3))
	else
		top = floorTop + 1.2
		piece(kit, "Pedestal", Vector3.new(side, 0.6, side), CFrame.new(0, floorTop + 0.3, 0), theme.StoneDark, Slate, true)
		piece(kit, "PedestalStep", Vector3.new(side - 1.4, 0.6, side - 1.4), CFrame.new(0, floorTop + 0.9, 0), Color3.fromRGB(188, 182, 170), Enum.Material.Marble, true)
		for _, rot in { 0, 90 } do
			for _, s in { -1, 1 } do
				piece(kit, "PedestalBorder", Vector3.new(side - 1.2, 0.16, 0.3), CFrame.Angles(0, math.rad(rot), 0) * CFrame.new(0, top + 0.02, s * (half - 0.85)), TIER_COLORS[4], Metal, false)
			end
		end
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local x, z = sx * (half - 0.6), sz * (half - 0.6)
				piece(kit, "GuardianPillar", Vector3.new(1.1, 3.4, 1.1), CFrame.new(x, floorTop + 1.7, z), theme.Stone, Slate, true)
				piece(kit, "GuardianPillarCap", Vector3.new(1.4, 0.3, 1.4), CFrame.new(x, floorTop + 3.55, z), TIER_COLORS[4], Metal, false)
				energy(piece(kit, "GuardianRune", Vector3.new(0.6, 0.6, 0.06), CFrame.new(x, floorTop + 2.2, z - 0.58), theme.Energy, Neon, false, 0.2))
			end
		end
		piece(kit, "PedestalSymbol", Vector3.new(1.4, 0.06, 1.4), CFrame.new(0, top + 0.05, -half + 1.6) * CFrame.Angles(0, math.rad(45), 0), TIER_COLORS[4], Enum.Material.Metal, false)
		-- Círculo de runas no piso, girando devagar (StationRing).
		local runes = ring(kit, "GuardianRunes", CFrame.new(0, top + 0.06, 0), half - 2.2, 0.12, theme.Energy, Neon, 0.45, 6)
		for _, part in runes:GetChildren() do
			if part:IsA("BasePart") then
				energy(part)
			end
		end
	end
	return top
end

-- I: Boneco de Treino (madeira e palha, quase sem efeito; balança no golpe).
local function buildDummy(kit: Kit, top: number, dummy: Model)
	local wood, straw = Color3.fromRGB(128, 90, 56), Color3.fromRGB(214, 184, 116)
	local z = 1.2
	for _, angle in { 0, 90 } do
		piece(kit, "DummyStand", Vector3.new(3.2, 0.4, 0.8), CFrame.new(0, top + 0.2, z) * CFrame.Angles(0, math.rad(angle), 0), wood, Enum.Material.Wood, true)
	end
	piece(kit, "DummyPost", Vector3.new(0.7, 2.2, 0.7), CFrame.new(0, top + 1.3, z), wood, Enum.Material.Wood, true)
	upright(kit, "DummyBody", Vector3.new(0, top + 3.9, z), 3.0, 2.2, straw, Enum.Material.Fabric, true, nil, dummy)
	for _, y in { 3.0, 4.8 } do
		upright(kit, "DummyRope", Vector3.new(0, top + y, z), 0.2, 2.3, Color3.fromRGB(150, 110, 70), Enum.Material.Fabric, false, nil, dummy)
	end
	piece(kit, "DummyArm", Vector3.new(4.4, 0.42, 0.42), CFrame.new(0, top + 4.9, z), wood, Enum.Material.Wood, false, nil, nil, dummy)
	piece(kit, "DummyHead", Vector3.new(1.7, 1.7, 1.7), CFrame.new(0, top + 6.3, z), straw, Enum.Material.Fabric, false, nil, Enum.PartType.Ball, dummy)
	piece(kit, "DummyTarget", Vector3.new(0.1, 1.5, 1.5), CFrame.new(0, top + 4.0, z - 1.1) * FACING, Color3.fromRGB(196, 72, 60), Enum.Material.SmoothPlastic, false, nil, Enum.PartType.Cylinder, dummy)
	piece(kit, "DummyTarget", Vector3.new(0.12, 0.7, 0.7), CFrame.new(0, top + 4.0, z - 1.12) * FACING, Color3.fromRGB(236, 224, 200), Enum.Material.SmoothPlastic, false, nil, Enum.PartType.Cylinder, dummy)
	dummy:SetAttribute("Pivot", (kit.Base * CFrame.new(0, top + 2.4, z)).Position)
end

-- II: Espantalho Reforçado (madeira + metal, placas que vibram, correntes).
local function buildScarecrow(kit: Kit, top: number, dummy: Model)
	local theme = kit.Theme
	local wood = Color3.fromRGB(110, 78, 50)
	local steel = Color3.fromRGB(150, 156, 170)
	local z = 1.6
	piece(kit, "ScarecrowBase", Vector3.new(2.0, 0.4, 2.0), CFrame.new(0, top + 0.2, z), theme.Metal, Enum.Material.Metal, true)
	for _, s in { -1, 1 } do
		strut(kit, "ScarecrowBrace", Vector3.new(s * 1.6, top + 0.3, z), Vector3.new(0, top + 2.4, z), 0.35, 0.35, wood, Enum.Material.Wood, false)
	end
	piece(kit, "ScarecrowPost", Vector3.new(0.8, 7.2, 0.8), CFrame.new(0, top + 3.6, z), wood, Enum.Material.Wood, true)
	piece(kit, "ScarecrowShoulders", Vector3.new(5.6, 0.5, 0.5), CFrame.new(0, top + 5.6, z), wood, Enum.Material.Wood, false)
	piece(kit, "ScarecrowTorso", Vector3.new(2.6, 3.0, 1.2), CFrame.new(0, top + 4.2, z), Color3.fromRGB(96, 70, 48), Enum.Material.WoodPlanks, true, nil, nil, dummy)
	for index, spec in { { 0.62, 5.0, 1.1 }, { -0.62, 5.0, 1.1 }, { 0, 3.4, 2.2 } } do
		local plate = piece(kit, "ArmorPlate", Vector3.new(spec[3], 1.2, 0.22), CFrame.new(spec[1], top + spec[2], z - 0.72), steel, Enum.Material.DiamondPlate, false, nil, nil, dummy)
		plate:SetAttribute("Order", index)
	end
	upright(kit, "ScarecrowHelmet", Vector3.new(0, top + 6.7, z), 1.4, 1.5, steel, Enum.Material.Metal, false, nil, dummy)
	piece(kit, "ScarecrowVisor", Vector3.new(1.0, 0.16, 0.08), CFrame.new(0, top + 6.75, z - 0.76), Color3.fromRGB(26, 26, 32), Enum.Material.SmoothPlastic, false, nil, nil, dummy)
	-- Correntes penduradas nas pontas dos ombros (elos alternados).
	for _, s in { -1, 1 } do
		for link = 1, 3 do
			local y = top + 5.2 - link * 0.55
			piece(kit, "ScarecrowChain", Vector3.new(0.12, 0.5, 0.3), CFrame.new(s * 2.5, y, z) * CFrame.Angles(0, math.rad(if link % 2 == 0 then 90 else 0), 0), Color3.fromRGB(120, 124, 136), Enum.Material.Metal, false, nil, nil, dummy)
		end
		piece(kit, "ScarecrowWeight", Vector3.new(0.55, 0.55, 0.55), CFrame.new(s * 2.5, top + 3.15, z), theme.Metal, Enum.Material.Metal, false, nil, Enum.PartType.Ball, dummy)
	end
	-- Pequenos impactos: faíscas só no golpe (o cliente chama Emit).
	local chest = dummy:FindFirstChild("ArmorPlate") :: BasePart
	local sparks = emitter(chest, "ImpactSparks", Color3.fromRGB(255, 214, 140), 0, NumberRange.new(4, 8), NumberRange.new(0.15, 0.3), 0.18, 50, Vector3.new(0, -12, 0))
	sparks.EmissionDirection = Enum.NormalId.Front
	dummy:SetAttribute("Pivot", (kit.Base * CFrame.new(0, top + 4.2, z)).Position)
end

-- III: Guerreiro de Treino (manequim de combate de metal + energia, cristal no peito).
local function buildWarrior(kit: Kit, top: number, dummy: Model)
	local theme = kit.Theme
	local Metal, Neon = Enum.Material.Metal, Enum.Material.Neon
	local armour = Color3.fromRGB(78, 86, 104)
	local trim = Color3.fromRGB(176, 184, 198)
	local glow = TIER_COLORS[3]
	local z = 1.8
	upright(kit, "WarriorBase", Vector3.new(0, top + 0.25, z), 0.5, 3.2, theme.Metal, Metal, true)
	energy(upright(kit, "WarriorBaseRing", Vector3.new(0, top + 0.52, z), 0.08, 3.4, glow, Neon, false, 0.4))
	for _, s in { -1, 1 } do
		piece(kit, "WarriorLeg", Vector3.new(0.8, 3.0, 0.9), CFrame.new(s * 0.55, top + 2.0, z), armour, Metal, true)
	end
	piece(kit, "WarriorHip", Vector3.new(2.2, 0.8, 1.2), CFrame.new(0, top + 3.8, z), theme.Metal, Metal, false, nil, nil, dummy)
	piece(kit, "WarriorTorso", Vector3.new(2.7, 2.8, 1.4), CFrame.new(0, top + 5.5, z), armour, Metal, true, nil, nil, dummy)
	for _, s in { -1, 1 } do
		energy(piece(kit, "WarriorEnergy", Vector3.new(0.14, 2.2, 0.06), CFrame.new(s * 0.95, top + 5.5, z - 0.72), glow, Neon, false, 0.3, nil, dummy))
	end
	energy(piece(kit, "WarriorEnergy", Vector3.new(2.3, 0.14, 0.06), CFrame.new(0, top + 4.3, z - 0.72), glow, Neon, false, 0.3, nil, dummy))
	local heart = crystal(kit, "WarriorCrystal", Vector3.new(0, top + 5.7, z - 0.8), 1.3, Vector3.new(0, 0, 0), glow, 0.2)
	heart.Parent = dummy
	energy(heart)
	for _, s in { -1, 1 } do
		piece(kit, "WarriorPauldron", Vector3.new(1.3, 0.8, 1.6), CFrame.new(s * 1.75, top + 6.9, z) * CFrame.Angles(0, 0, math.rad(-s * 18)), trim, Metal, false, nil, nil, dummy)
		piece(kit, "WarriorUpperArm", Vector3.new(0.7, 1.8, 0.8), CFrame.new(s * 1.85, top + 5.6, z), armour, Metal, false, nil, nil, dummy)
		-- Antebraços em guarda, para a frente.
		piece(kit, "WarriorForearm", Vector3.new(0.65, 0.65, 1.8), CFrame.new(s * 1.85, top + 4.85, z - 0.8), armour, Metal, false, nil, nil, dummy)
	end
	-- Espada de treino na mão direita (lâmina sem fio, só forma).
	piece(kit, "WarriorSwordGuard", Vector3.new(0.9, 0.2, 0.3), CFrame.new(-1.85, top + 4.85, z - 1.75), trim, Metal, false, nil, nil, dummy)
	energy(piece(kit, "WarriorSwordBlade", Vector3.new(0.18, 2.6, 0.4), CFrame.new(-1.85, top + 6.2, z - 1.75), glow, Neon, false, 0.45, nil, dummy))
	facingDisc(kit, "WarriorShield", Vector3.new(1.85, top + 5.2, z - 1.75), 0.25, 2.4, trim, Metal).Parent = dummy
	piece(kit, "WarriorHead", Vector3.new(1.2, 1.4, 1.2), CFrame.new(0, top + 7.6, z), armour, Metal, false, nil, nil, dummy)
	energy(piece(kit, "WarriorVisor", Vector3.new(0.9, 0.18, 0.06), CFrame.new(0, top + 7.7, z - 0.62), glow, Neon, false, 0.2, nil, dummy))
	dummy:SetAttribute("Pivot", (kit.Base * CFrame.new(0, top + 3.5, z)).Position)
end

-- IV: Guardião de Poder (pedra + metal, braços robustos, núcleo que pulsa).
local function buildGuardian(kit: Kit, top: number, dummy: Model)
	local theme = kit.Theme
	local Metal, Neon, Slate = Enum.Material.Metal, Enum.Material.Neon, Enum.Material.Slate
	local stone = Color3.fromRGB(120, 116, 112)
	local z = 2.2
	piece(kit, "GuardianPlinth", Vector3.new(4.6, 1.0, 3.2), CFrame.new(0, top + 0.5, z), theme.StoneDark, Slate, true)
	for _, s in { -1, 1 } do
		piece(kit, "GuardianLeg", Vector3.new(1.6, 3.4, 1.7), CFrame.new(s * 1.1, top + 2.7, z), stone, Slate, true)
	end
	piece(kit, "GuardianTorso", Vector3.new(4.8, 4.0, 2.6), CFrame.new(0, top + 6.4, z), stone, Slate, true, nil, nil, dummy)
	piece(kit, "GuardianBelt", Vector3.new(4.4, 0.6, 2.7), CFrame.new(0, top + 4.6, z), theme.Metal, Metal, false, nil, nil, dummy)
	facingDisc(kit, "GuardianCoreFrame", Vector3.new(0, top + 6.6, z - 1.3), 0.3, 2.6, TIER_COLORS[4], Metal).Parent = dummy
	local core = piece(kit, "GuardianCore", Vector3.new(1.6, 1.6, 1.6), CFrame.new(0, top + 6.6, z - 1.45), theme.Energy, Neon, false, 0.05, Enum.PartType.Ball, dummy)
	energy(core)
	energy(piece(kit, "GuardianCoreShell", Vector3.new(2.2, 2.2, 2.2), CFrame.new(0, top + 6.6, z - 1.45), theme.Crystal, Enum.Material.Glass, false, 0.6, Enum.PartType.Ball, dummy))
	for _, s in { -1, 1 } do
		piece(kit, "GuardianShoulder", Vector3.new(2.0, 1.9, 2.4), CFrame.new(s * 3.2, top + 7.8, z), theme.Metal, Metal, false, nil, nil, dummy)
		piece(kit, "GuardianArm", Vector3.new(1.6, 3.2, 1.6), CFrame.new(s * 3.3, top + 5.6, z - 0.2), stone, Slate, false, nil, nil, dummy)
		piece(kit, "GuardianFist", Vector3.new(2.1, 2.0, 2.1), CFrame.new(s * 3.3, top + 3.6, z - 0.5), theme.Metal, Metal, false, nil, nil, dummy)
		energy(piece(kit, "GuardianArmRune", Vector3.new(0.5, 1.2, 0.06), CFrame.new(s * 3.3, top + 5.8, z - 1.03), theme.Energy, Neon, false, 0.25, nil, dummy))
	end
	piece(kit, "GuardianHead", Vector3.new(1.9, 1.6, 1.7), CFrame.new(0, top + 9.2, z), stone, Slate, false, nil, nil, dummy)
	energy(piece(kit, "GuardianEyes", Vector3.new(1.2, 0.2, 0.06), CFrame.new(0, top + 9.3, z - 0.87), theme.Energy, Neon, false, 0.15, nil, dummy))
	for _, s in { -1, 1 } do
		local shard = crystal(kit, "GuardianShard", Vector3.new(s * 1.3, top + 10.2, z + 0.6), 1.6, Vector3.new(0, 0, -s * 18), theme.Crystal, 0.25)
		shard.Parent = dummy
		energy(shard)
	end
	dummy:SetAttribute("Pivot", (kit.Base * CFrame.new(0, top + 4.6, z)).Position)
end

local DUMMY_BUILDERS = { Dummy = buildDummy, Scarecrow = buildScarecrow, Warrior = buildWarrior, Guardian = buildGuardian }

--[[
	CAMPO DE TREINAMENTO. Quatro alvos de treino em arco, cada um no próprio
	pedestal (piso + borda + símbolo + placa), do mais simples ao mais
	elaborado: a progressão se lê sem texto.
	  I   Boneco de Treino (madeira e palha)
	  II  Espantalho Reforçado (madeira, placas de metal, correntes)
	  III Guerreiro de Treino (manequim de metal, energia, cristal)
	  IV  Guardião de Poder (pedra e metal, núcleo, runas, braços robustos)
	Na entrada, o pórtico "🏋️ TREINO / FIQUE MAIS FORTE" com um alvo no alto.
	Sem HP, sem loot, sem IA, sem ataque: os bonecos só REAGEM a quem treina
	(cliente, TrainingFieldController). Quem decide se treina é o servidor
	(TrainingService, por Renascimentos); o cliente só mostra cadeado.
	`base` = centro da área (eixos do mundo); -Z = entrada (avenida).
	`focus` = ponto (local) para onde os alvos olham.
]]
function StationMachines.BuildTrainingField(parent: Instance, base: CFrame, options: PlateOptions, spots: { TrainingSpot }, entranceZ: number, focus: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "Station_Training_Machine"
	local theme = StationMachines.Themes.Training
	local kit: Kit = { Parent = model, Base = base, Theme = theme, Count = 0 }
	local Slate, Metal = Enum.Material.Slate, Enum.Material.Metal
	local floorTop = 0.6

	-- Pórtico de entrada com a placa da área e um alvo de treino no alto.
	for _, side in { -1, 1 } do
		piece(kit, "FieldGateBase", Vector3.new(2.2, 1, 2.2), CFrame.new(side * 6.2, floorTop + 0.5, entranceZ), theme.StoneDark, Slate, true)
		piece(kit, "FieldGatePillar", Vector3.new(1.4, 9.4, 1.4), CFrame.new(side * 6.2, floorTop + 5.7, entranceZ), Color3.fromRGB(128, 92, 58), Enum.Material.Wood, true)
		piece(kit, "FieldGateBand", Vector3.new(1.7, 0.3, 1.7), CFrame.new(side * 6.2, floorTop + 3.2, entranceZ), theme.Gold, Metal, false)
	end
	piece(kit, "FieldGateBeam", Vector3.new(14.4, 1.8, 1.8), CFrame.new(0, floorTop + 11.2, entranceZ), theme.Stone, Slate, true)
	nameplate(kit, CFrame.new(0, floorTop + 11.3, entranceZ - 1.0), options.Title, options.Subtitle, 9)
	piece(kit, "FieldGateTarget", Vector3.new(0.3, 3.4, 3.4), CFrame.new(0, floorTop + 14.0, entranceZ) * FACING, Color3.fromRGB(196, 72, 60), Metal, false, nil, Enum.PartType.Cylinder)
	piece(kit, "FieldGateTarget", Vector3.new(0.34, 2.2, 2.2), CFrame.new(0, floorTop + 14.0, entranceZ) * FACING, Color3.fromRGB(236, 224, 200), Metal, false, nil, Enum.PartType.Cylinder)
	piece(kit, "FieldGateTarget", Vector3.new(0.38, 1.0, 1.0), CFrame.new(0, floorTop + 14.0, entranceZ) * FACING, Color3.fromRGB(196, 72, 60), Metal, false, nil, Enum.PartType.Cylinder)

	for _, spot in spots do
		local station = Instance.new("Model")
		station.Name = "TrainingStation_" .. spot.Id
		local c = spot.Centre
		local frame = CFrame.lookAt(Vector3.new(c.X, 0, c.Z), Vector3.new(focus.X, 0, focus.Z))
		local sub: Kit = { Parent = station, Base = base * frame, Theme = theme, Count = 0 }
		local top = trainingPedestal(sub, spot, floorTop)
		-- Placa no chão, logo à frente do pedestal (de quem chega).
		trainingPlaque(sub, CFrame.new(0, floorTop, -spot.Radius - 0.8), spot, station)
		local dummy = Instance.new("Model")
		dummy.Name = "Dummy"
		DUMMY_BUILDERS[spot.Kind](sub, top, dummy)
		atomic(dummy)
		dummy.Parent = station
		station:SetAttribute("Station", spot.Id)
		station:SetAttribute("Tier", spot.Tier)
		station:SetAttribute("RequiredRebirths", spot.Rebirths)
		station:SetAttribute("Reaction", REACTIONS[spot.Kind] or "Sway")
		station:SetAttribute("Centre", (base * CFrame.new(c.X, floorTop, c.Z)).Position)
		station:SetAttribute("Front", (base * frame).LookVector)
		station:SetAttribute("PartCount", sub.Count)
		atomic(station)
		station.Parent = model
		station:AddTag(StationMachines.TAG_TRAINING)
		kit.Count += sub.Count
	end

	model:SetAttribute("PartCount", kit.Count)
	model:SetAttribute("Prototype", "StationMachine")
	model.Parent = parent
	return model
end

-- ── Área de Incubação (Ovos) ────────────────────────────────────────────────

export type EggStand = {
	Id: string,
	Base: Vector3, -- centro da bancada no chão (mundo)
	Facing: Vector3, -- para fora do arco (de onde se chega)
	Tier: number, -- 1..5 (ordem dos ovos)
	EggCentre: number, -- altura do centro do ovo
	EggRadius: number, -- meia largura do ovo
	PedestalTop: number,
	PedestalRadius: number,
	Title: string, -- nome do ovo
	Price: string, -- "⚡ 2K" / "💎 400"
	Requirement: string?, -- "⚔️ Estágio 5"
}

-- Cor do acabamento de cada nível de incubadora (não diz nada de chance).
local INCUBATOR_COLORS = {
	Color3.fromRGB(176, 120, 72), -- bronze
	Color3.fromRGB(176, 184, 198), -- prata
	Color3.fromRGB(222, 180, 80), -- ouro
	Color3.fromRGB(176, 120, 255), -- violeta
	Color3.fromRGB(255, 236, 190), -- perolado
}

--[[
	ÁREA DE INCUBAÇÃO. Os OVOS são os protagonistas e continuam iguais (peça,
	tamanho, cor, prompt); muda o ambiente em volta: cada bancada vira uma
	incubadora ABERTA — braços em garra ao redor do ovo, sem fechá-lo —, mais
	elaborada a cada nível (2 → 4 braços, cristais nas pontas, aro de
	energia no pedestal a partir do III, anel girando no IV e no V), uma
	placa física com nome, preço e o estágio exigido (o que já está na
	config; nada sobre chance), cabos no chão ligando cada incubadora ao ovo
	gigante (a "matriz") e a placa "🥚 OVOS" na frente dele.
	Trabalha nos eixos do mundo: `base` = identidade.
]]
function StationMachines.DecorateEggs(parent: Instance, options: PlateOptions, stands: { EggStand }, landmark: Vector3, landmarkFacing: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "Station_Eggs_Machine"
	local theme = StationMachines.Themes.Training
	local kit: Kit = { Parent = model, Base = CFrame.identity, Theme = theme, Count = 0 }
	local Metal, Neon, Slate = Enum.Material.Metal, Enum.Material.Neon, Enum.Material.Slate
	local dark = Color3.fromRGB(56, 58, 70)

	for _, stand in stands do
		local accent = INCUBATOR_COLORS[math.clamp(stand.Tier, 1, #INCUBATOR_COLORS)]
		local arms = if stand.Tier <= 1 then 2 elseif stand.Tier <= 3 then 3 else 4
		local frame = CFrame.lookAt(stand.Base, stand.Base + stand.Facing)
		-- Braços em garra: saem da borda do pedestal e sobem até perto do ovo.
		for index = 0, arms - 1 do
			local angle = (index + 0.5) * 2 * math.pi / arms + math.pi / 2
			local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local from = stand.Base + dir * (stand.PedestalRadius - 0.4) + Vector3.new(0, stand.PedestalTop, 0)
			local to = stand.Base + dir * (stand.EggRadius + 1.0) + Vector3.new(0, stand.EggCentre + 1.6, 0)
			local length = (to - from).Magnitude
			local arm = piece(kit, "IncubatorArm", Vector3.new(0.5, length, 0.5), CFrame.lookAt((from + to) / 2, to) * CFrame.Angles(math.rad(90), 0, 0), if stand.Tier >= 3 then accent else dark, Metal, false)
			arm:SetAttribute("Tier", stand.Tier)
			if stand.Tier >= 2 then
				crystal(kit, "IncubatorGem", to + dir * 0.2 + Vector3.new(0, 0.5, 0), 0.9, Vector3.new(0, 0, 0), accent, 0.15)
			end
		end
		-- Aro de energia no pedestal (III em diante).
		if stand.Tier >= 3 then
			piece(kit, "IncubatorGlow", Vector3.new(0.08, stand.PedestalRadius * 2 + 0.3, stand.PedestalRadius * 2 + 0.3), CFrame.new(stand.Base + Vector3.new(0, stand.PedestalTop - 0.2, 0)) * UPRIGHT, accent, Neon, false, 0.55, Enum.PartType.Cylinder)
		end
		-- Anel girando em volta do ovo (IV e V).
		if stand.Tier >= 4 then
			local ringCentre = CFrame.new(stand.Base + Vector3.new(0, stand.EggCentre - 1.0, 0))
			local spinning = Instance.new("Model")
			spinning.Name = "IncubatorRing"
			local sides = if stand.Tier >= 5 then 8 else 6
			local radius = stand.EggRadius + 1.6
			local length = 2 * radius * math.tan(math.pi / sides) + 0.1
			for index = 0, sides - 1 do
				piece(kit, "IncubatorRingSegment", Vector3.new(length, 0.22, 0.22), ringCentre * CFrame.Angles(0, index * 2 * math.pi / sides, 0) * CFrame.new(0, 0, -radius), accent, Metal, false, nil, nil, spinning)
			end
			spinning:SetAttribute("SpinSpeed", if stand.Tier >= 5 then 16 else 10)
			spinning:SetAttribute("Centre", ringCentre.Position)
			spinning:SetAttribute("Axis", Vector3.yAxis)
			atomic(spinning)
			spinning.Parent = model
			spinning:AddTag(StationMachines.TAG_RING)
		end
		-- Placa: nome, preço e estágio exigido (de frente para quem chega).
		local plaqueAt = frame * CFrame.new(0, 0, -(stand.PedestalRadius + 3.8))
		local board = piece(kit, "EggPlaque_" .. stand.Id, Vector3.new(5.6, 1.9, 0.2), plaqueAt * CFrame.new(0, 2.4, 0) * CFrame.Angles(math.rad(-18), 0, 0), dark, Metal, false)
		piece(kit, "EggPlaqueBand", Vector3.new(5.8, 0.22, 0.24), plaqueAt * CFrame.new(0, 3.4, 0.03) * CFrame.Angles(math.rad(-18), 0, 0), accent, Metal, false)
		piece(kit, "EggPlaquePost", Vector3.new(0.5, 1.8, 0.5), plaqueAt * CFrame.new(0, 0.9, 0.25), dark, Metal, false)
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Text"
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 50
		gui.LightInfluence = 0.2
		gui.MaxDistance = 50
		local function label(name: string, text: string, y: number, height: number, color: Color3)
			local item = Instance.new("TextLabel")
			item.Name = name
			item.BackgroundTransparency = 1
			item.Position = UDim2.fromScale(0.04, y)
			item.Size = UDim2.fromScale(0.92, height)
			item.Font = Enum.Font.GothamBlack
			item.TextScaled = true
			item.TextColor3 = color
			item.Text = text
			item.Parent = gui
		end
		label("Name", StationMachines.Upper(stand.Title), 0.06, 0.42, Color3.fromRGB(242, 246, 252))
		label("Price", stand.Price .. (if stand.Requirement then "   " .. stand.Requirement else ""), 0.54, 0.36, accent)
		gui.Parent = board
		-- Cabo no chão até a matriz (o ovo gigante).
		local from = stand.Base + Vector3.new(0, 0.42, 0) + (landmark - stand.Base).Unit * 9.2
		local to = landmark + Vector3.new(0, 0.42, 0) + (stand.Base - landmark).Unit * 6.8
		from = Vector3.new(from.X, 0.42, from.Z)
		to = Vector3.new(to.X, 0.42, to.Z)
		tube(kit, "IncubatorCable", from, to, 0.42, dark)
		local pulse = piece(kit, "IncubatorFeed", Vector3.new(0.14, 0.06, (to - from).Magnitude), CFrame.lookAt((from + to) / 2 + Vector3.new(0, 0.22, 0), to + Vector3.new(0, 0.22, 0)), accent, Neon, false, 0.6)
		pulse:SetAttribute("Order", stand.Tier)
		pulse:AddTag(StationMachines.TAG_PULSE)
	end

	-- Placa da área na frente do ovo gigante.
	local headerFrame = CFrame.lookAt(landmark, landmark + landmarkFacing) * CFrame.new(0, 0, -7.8)
	piece(kit, "EggHeaderStone", Vector3.new(10.4, 2.8, 1.4), headerFrame * CFrame.new(0, 1.4, 0.3), Color3.fromRGB(104, 106, 118), Slate, true)
	nameplate(kit, headerFrame * CFrame.new(0, 2.0, -0.45), options.Title, options.Subtitle, 8.6)

	model:SetAttribute("PartCount", kit.Count)
	model:SetAttribute("Prototype", "StationMachine")
	model.Parent = parent
	return model
end

-- ── Central do Aventureiro (Missões e Prêmios) ──────────────────────────────

--[[
	Linguagem própria, mais social e de aventura que as máquinas: MADEIRA +
	PEDRA + DOURADO, quase sem energia. Missões e Prêmios são sistemas
	secundários: silhueta baixa (≤ 12 studs), sem disputar com o Caminho do
	Poder. Nada aqui tem lógica: os prompts são os mesmos de antes e abrem os
	painéis atuais (Quests, Rewards).
]]
StationMachines.Themes.Adventure = {
	Stone = Color3.fromRGB(150, 142, 128),
	StoneDark = Color3.fromRGB(104, 98, 90),
	Metal = Color3.fromRGB(64, 52, 42), -- fundo das placas: madeira escura
	Plate = Color3.fromRGB(120, 86, 54),
	Gold = Color3.fromRGB(206, 166, 84),
	Energy = Color3.fromRGB(255, 204, 96),
	Crystal = Color3.fromRGB(255, 220, 150),
	Core = Color3.fromRGB(255, 236, 170),
} :: Theme

local WOOD = Color3.fromRGB(132, 94, 60)
local WOOD_DARK = Color3.fromRGB(96, 68, 44)
local PARCHMENT = Color3.fromRGB(238, 222, 184)
local INK = Color3.fromRGB(70, 56, 44)

--[[
	QUADRO DE MISSÕES: mural de madeira com telhadinho, moldura dourada e três
	pergaminhos presos (☐ ☐ ☑ — só desenho: as missões de verdade estão no
	painel). Ao lado, um caixote com um troféu pequeno. A peça do quadro é
	`Station_Quests` (o prompt de sempre). -Z = frente.
]]
function StationMachines.BuildQuestBoard(parent: Instance, base: CFrame, panel: string, options: PlateOptions): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = "Station_" .. panel .. "_Machine"
	local theme = StationMachines.Themes.Adventure
	local kit: Kit = { Parent = model, Base = base, Theme = theme, Count = 0 }
	local Wood, Slate, Metal = Enum.Material.Wood, Enum.Material.Slate, Enum.Material.Metal
	local floorTop = 0.6
	for _, side in { -1, 1 } do
		piece(kit, "BoardFooting", Vector3.new(2.4, 0.5, 2.4), CFrame.new(side * 5.6, floorTop + 0.25, 0), theme.StoneDark, Slate, true)
		piece(kit, "BoardFooting", Vector3.new(1.7, 0.7, 1.7), CFrame.new(side * 5.6, floorTop + 0.85, 0), theme.Stone, Slate, true)
		piece(kit, "BoardPost", Vector3.new(0.9, 10.2, 0.9), CFrame.new(side * 5.6, floorTop + 5.6, 0), WOOD_DARK, Wood, true)
		-- Mão-francesa atrás do poste (dá profundidade de perfil).
		strut(kit, "BoardBrace", Vector3.new(side * 5.6, floorTop + 1.2, 1.9), Vector3.new(side * 5.6, floorTop + 6.0, 0.35), 0.45, 0.45, WOOD_DARK, Wood, false)
	end
	-- Fundo do mural, mais largo e escuro: a moldura ganha espessura.
	piece(kit, "BoardBack", Vector3.new(11.4, 6.6, 0.3), CFrame.new(0, floorTop + 5.4, 0.42), WOOD_DARK, Enum.Material.WoodPlanks, false)
	local board = piece(kit, "Station_" .. panel, Vector3.new(10.6, 6.0, 0.6), CFrame.new(0, floorTop + 5.4, 0), WOOD, Enum.Material.WoodPlanks, true)
	-- Moldura dourada.
	for _, y in { 2.45, 8.35 } do
		piece(kit, "BoardFrame", Vector3.new(11.0, 0.32, 0.8), CFrame.new(0, floorTop + y, 0), theme.Gold, Metal, false)
	end
	for _, side in { -1, 1 } do
		piece(kit, "BoardFrame", Vector3.new(0.32, 6.2, 0.8), CFrame.new(side * 5.35, floorTop + 5.4, 0), theme.Gold, Metal, false)
	end
	-- Telhadinho de duas águas e a cumeeira.
	for _, side in { -1, 1 } do
		piece(kit, "BoardRoof", Vector3.new(13.2, 0.45, 2.3), CFrame.new(0, floorTop + 11.0, side * 0.85) * CFrame.Angles(math.rad(-side * 28), 0, 0), WOOD_DARK, Enum.Material.WoodPlanks, false)
	end
	piece(kit, "BoardRidge", Vector3.new(13.4, 0.3, 0.3), CFrame.new(0, floorTop + 11.6, 0), theme.Gold, Metal, false)
	-- Medalha no alto do telhado (o brasão das missões).
	piece(kit, "BoardMedal", Vector3.new(0.25, 1.5, 1.5), CFrame.new(0, floorTop + 12.4, -0.15) * FACING, theme.Gold, Metal, false, nil, Enum.PartType.Cylinder)
	piece(kit, "BoardMedal", Vector3.new(0.3, 0.8, 0.8), CFrame.new(0, floorTop + 12.4, -0.24) * FACING, Color3.fromRGB(150, 60, 50), Enum.Material.SmoothPlastic, false, nil, Enum.PartType.Cylinder)
	-- Placa logo abaixo do telhado, na frente do quadro.
	nameplate(kit, CFrame.new(0, floorTop + 9.55, -0.55), options.Title, options.Subtitle, 6.4)
	-- Três pergaminhos: dois em aberto, um concluído.
	for index, x in { -3.3, 0, 3.3 } do
		local tilt = CFrame.Angles(0, 0, math.rad(({ -3, 2, -2 })[index]))
		local at = CFrame.new(x, floorTop + 5.2, ({ -0.36, -0.46, -0.4 })[index]) * tilt
		piece(kit, "QuestCard", Vector3.new(2.6, 3.4, 0.08), at, PARCHMENT, Enum.Material.SmoothPlastic, false)
		piece(kit, "QuestPin", Vector3.new(0.12, 0.4, 0.4), at * CFrame.new(0, 1.5, -0.06) * FACING, theme.Gold, Metal, false, nil, Enum.PartType.Cylinder)
		piece(kit, "QuestBox", Vector3.new(0.7, 0.7, 0.06), at * CFrame.new(-0.7, 0.55, -0.06), INK, Enum.Material.SmoothPlastic, false)
		piece(kit, "QuestLines", Vector3.new(1.9, 0.9, 0.05), at * CFrame.new(0, -0.75, -0.05), Color3.fromRGB(196, 180, 146), Enum.Material.SmoothPlastic, false)
		if index == 3 then
			-- ☑: marca verde sobre a caixinha.
			piece(kit, "QuestCheck", Vector3.new(0.18, 0.45, 0.06), at * CFrame.new(-0.86, 0.5, -0.1) * CFrame.Angles(0, 0, math.rad(40)), Color3.fromRGB(70, 190, 90), Enum.Material.SmoothPlastic, false)
			piece(kit, "QuestCheck", Vector3.new(0.18, 0.8, 0.06), at * CFrame.new(-0.58, 0.62, -0.1) * CFrame.Angles(0, 0, math.rad(-35)), Color3.fromRGB(70, 190, 90), Enum.Material.SmoothPlastic, false)
		end
	end
	-- Caixote com um troféu pequeno (lado de dentro, virado para o centro).
	piece(kit, "QuestCrate", Vector3.new(2.2, 2.2, 2.2), CFrame.new(-7.6, floorTop + 1.1, -0.6) * CFrame.Angles(0, math.rad(12), 0), WOOD, Enum.Material.WoodPlanks, true)
	piece(kit, "QuestTrophy", Vector3.new(0.3, 1.1, 1.1), CFrame.new(-7.6, floorTop + 2.35, -0.6) * UPRIGHT, theme.Gold, Metal, false, nil, Enum.PartType.Cylinder)
	piece(kit, "QuestTrophy", Vector3.new(0.9, 0.35, 0.35), CFrame.new(-7.6, floorTop + 2.9, -0.6) * UPRIGHT, theme.Gold, Metal, false, nil, Enum.PartType.Cylinder)
	piece(kit, "QuestTrophy", Vector3.new(1.0, 1.2, 1.2), CFrame.new(-7.6, floorTop + 3.8, -0.6) * UPRIGHT, theme.Gold, Metal, false, nil, Enum.PartType.Cylinder)
	model:SetAttribute("PartCount", kit.Count)
	model:SetAttribute("Prototype", "StationMachine")
	model.Parent = parent
	return model, board
end

--[[
	TOTEM DE PRÊMIOS: arco de pedra com a placa e um presente no alto; no
	meio, sobre um pedestal de dois degraus, o BAÚ entreaberto com um brilho
	dourado discreto saindo pela fresta, moedas empilhadas e duas gemas.
	"Tenho alguma coisa para coletar aqui." A peça do baú é
	`Station_Rewards` (o prompt de sempre). -Z = frente.
]]
function StationMachines.BuildRewardTotem(parent: Instance, base: CFrame, panel: string, options: PlateOptions): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = "Station_" .. panel .. "_Machine"
	local theme = StationMachines.Themes.Adventure
	local kit: Kit = { Parent = model, Base = base, Theme = theme, Count = 0 }
	local Slate, Metal, Neon = Enum.Material.Slate, Enum.Material.Metal, Enum.Material.Neon
	local floorTop = 0.6
	--[[
		O BAÚ é o protagonista do lado de Prêmios (~25% mais presença que a
		primeira versão, sem escalar o resto): pedestal de três degraus com
		friso dourado e cantoneiras, baú maior com pés e tampa em dois níveis
		bem aberta, e o conteúdo à mostra (moedas e uma gema saindo).
	]]
	piece(kit, "TotemStep", Vector3.new(8.2, 0.6, 6.0), CFrame.new(0, floorTop + 0.3, -0.1), theme.StoneDark, Slate, true)
	piece(kit, "TotemStep", Vector3.new(7.0, 0.6, 5.0), CFrame.new(0, floorTop + 0.9, 0.1), theme.Stone, Slate, true)
	piece(kit, "TotemStep", Vector3.new(5.8, 0.4, 4.0), CFrame.new(0, floorTop + 1.4, 0.2), Color3.fromRGB(188, 182, 170), Enum.Material.Marble, true)
	piece(kit, "TotemTrim", Vector3.new(8.3, 0.18, 0.2), CFrame.new(0, floorTop + 0.55, -3.1), theme.Gold, Metal, false)
	piece(kit, "TotemTrim", Vector3.new(7.1, 0.18, 0.2), CFrame.new(0, floorTop + 1.15, -2.4), theme.Gold, Metal, false)
	for _, side in { -1, 1 } do
		piece(kit, "TotemCorner", Vector3.new(0.5, 1.6, 0.5), CFrame.new(side * 3.85, floorTop + 0.8, -2.85), theme.Gold, Metal, false)
	end
	local top = floorTop + 1.6
	-- Pés, corpo, cintas e fecho.
	for _, x in { -2.2, 2.2 } do
		piece(kit, "ChestFoot", Vector3.new(0.6, 0.3, 3.3), CFrame.new(x, top + 0.15, 0.2), theme.Gold, Metal, false)
	end
	local chest = piece(kit, "Station_" .. panel, Vector3.new(5.0, 2.4, 3.2), CFrame.new(0, top + 1.5, 0.2), WOOD, Enum.Material.WoodPlanks, true)
	for _, x in { -1.6, 1.6 } do
		piece(kit, "ChestBand", Vector3.new(0.36, 2.46, 3.26), CFrame.new(x, top + 1.5, 0.2), theme.Gold, Metal, false)
	end
	piece(kit, "ChestRim", Vector3.new(5.1, 0.24, 3.3), CFrame.new(0, top + 2.62, 0.2), theme.Gold, Metal, false)
	piece(kit, "ChestLock", Vector3.new(0.85, 1.0, 0.3), CFrame.new(0, top + 2.0, -1.5), theme.Gold, Metal, false)
	-- Tampa bem aberta (52°), em dois níveis para ler como baú de longe.
	local hinge = CFrame.new(0, top + 2.7, 1.8) * CFrame.Angles(math.rad(52), 0, 0)
	piece(kit, "ChestLid", Vector3.new(5.1, 0.6, 3.3), hinge * CFrame.new(0, 0.3, -1.62), WOOD_DARK, Enum.Material.WoodPlanks, false)
	piece(kit, "ChestLid", Vector3.new(4.4, 0.45, 2.5), hinge * CFrame.new(0, 0.8, -1.62), WOOD_DARK, Enum.Material.WoodPlanks, false)
	for _, x in { -1.6, 1.6 } do
		piece(kit, "ChestBand", Vector3.new(0.36, 1.1, 3.36), hinge * CFrame.new(x, 0.55, -1.62), theme.Gold, Metal, false)
	end
	-- Conteúdo: brilho dourado por dentro (o cliente acende quando há prêmio
	-- para pegar), moedas por cima e uma gema saindo.
	local glow = piece(kit, "ChestGlow", Vector3.new(4.5, 0.25, 2.7), CFrame.new(0, top + 2.62, 0.2), theme.Energy, Neon, false, 0.75)
	glow:SetAttribute("Role", "Glow")
	glow:AddTag(StationMachines.TAG_REWARD)
	for index, at in { Vector3.new(-1.0, 2.8, -0.2), Vector3.new(0.2, 2.85, 0.5), Vector3.new(1.1, 2.8, -0.3) } do
		piece(kit, "ChestCoin", Vector3.new(0.24, 1.0, 1.0), CFrame.new(at.X, top + at.Y, at.Z) * UPRIGHT * CFrame.Angles(math.rad(index * 30), 0, 0), theme.Gold, Metal, false, nil, Enum.PartType.Cylinder)
	end
	crystal(kit, "RewardGem", Vector3.new(-0.3, top + 3.2, 0.7), 1.3, Vector3.new(0, 0, 14), Color3.fromRGB(120, 210, 255), 0.1)
	-- Fora do baú: uma pilha de moedas e uma gema rosa no degrau.
	for index, at in { Vector3.new(-3.0, 0.12, -1.6), Vector3.new(-3.0, 0.36, -1.6), Vector3.new(-2.55, 0.12, -2.2) } do
		piece(kit, "RewardCoin", Vector3.new(0.24, 0.9, 0.9), CFrame.new(at.X, top - 0.4 + at.Y, at.Z) * UPRIGHT * CFrame.Angles(math.rad(index * 25), 0, 0), theme.Gold, Metal, false, nil, Enum.PartType.Cylinder)
	end
	crystal(kit, "RewardGem", Vector3.new(2.9, top - 0.1, -1.7), 0.9, Vector3.new(0, 0, -10), Color3.fromRGB(255, 120, 180), 0.1)
	-- Faíscas douradas e um "!" pequeno: só com prêmio disponível (cliente).
	local sparkle = emitter(glow, "ChestSparkle", theme.Energy, 3, NumberRange.new(1, 2.5), NumberRange.new(0.8, 1.4), 0.25, 25, Vector3.new(0, 1, 0))
	sparkle.Enabled = false
	-- Só o RewardChestController liga/desliga (com prêmio e sem "Efeitos reduzidos").
	sparkle:RemoveTag(StationMachines.TAG_PARTICLES)
	sparkle:SetAttribute("Role", "Sparkle")
	sparkle:AddTag(StationMachines.TAG_REWARD)
	for _, spec in { { "Bar", Vector3.new(0.34, 1.0, 0.34), 5.35 }, { "Dot", Vector3.new(0.36, 0.36, 0.36), 4.6 } } do
		local mark = piece(kit, "ChestMark" .. spec[1], spec[2], CFrame.new(0, top + spec[3], -0.3), theme.Energy, Neon, false, 1)
		mark:SetAttribute("Role", "Mark")
		mark:AddTag(StationMachines.TAG_REWARD)
	end
	-- Arco de pedra atrás, com a placa e o presente no alto.
	for _, side in { -1, 1 } do
		piece(kit, "TotemPillar", Vector3.new(1.4, 8.4, 1.4), CFrame.new(side * 4.9, floorTop + 4.2, 2.6), theme.Stone, Slate, true)
		piece(kit, "TotemCap", Vector3.new(1.8, 0.4, 1.8), CFrame.new(side * 4.9, floorTop + 8.6, 2.6), theme.Gold, Metal, false)
	end
	piece(kit, "TotemBeam", Vector3.new(11.6, 1.5, 1.6), CFrame.new(0, floorTop + 9.55, 2.6), theme.StoneDark, Slate, false)
	nameplate(kit, CFrame.new(0, floorTop + 9.6, 1.65), options.Title, options.Subtitle, 7.2)
	local giftAt = CFrame.new(0, floorTop + 11.4, 2.6) * CFrame.Angles(0, math.rad(20), 0)
	piece(kit, "TotemGift", Vector3.new(2.2, 2.2, 2.2), giftAt, Color3.fromRGB(226, 92, 70), Enum.Material.SmoothPlastic, false)
	piece(kit, "TotemRibbon", Vector3.new(2.3, 2.3, 0.45), giftAt, theme.Gold, Metal, false)
	piece(kit, "TotemRibbon", Vector3.new(0.45, 2.3, 2.3), giftAt, theme.Gold, Metal, false)
	for _, side in { -1, 1 } do
		piece(kit, "TotemBow", Vector3.new(0.9, 0.6, 0.4), giftAt * CFrame.new(side * 0.45, 1.35, 0) * CFrame.Angles(0, 0, math.rad(side * 30)), theme.Gold, Metal, false)
	end
	model:SetAttribute("PartCount", kit.Count)
	model:SetAttribute("Prototype", "StationMachine")
	model.Parent = parent
	return model, chest
end

export type PlazaStation = { Local: Vector3, Color: Color3, Label: string, Flow: string? } -- Flow: "Out" (Missões) / "In" (Prêmios)

--[[
	CENTRO DA PRAÇA: medalhão de pedra com aro dourado e, encaixado nele, um
	pedestal baixo com TROFÉU (a conquista entre a missão e o prêmio); um
	caminho no piso até cada estação, com setas douradas no sentido
	mural → troféu → baú. A frente fica livre para circular. (A placa de
	direção do fundo saiu: o mural e o baú já dizem o que são.)
	`base` = centro da área no chão, -Z = frente (de onde se chega).
]]
function StationMachines.DecorateAdventurePlaza(parent: Instance, base: CFrame, stations: { PlazaStation }, depth: number): Model
	local model = Instance.new("Model")
	model.Name = "AdventurePlaza"
	local theme = StationMachines.Themes.Adventure
	local kit: Kit = { Parent = model, Base = base, Theme = theme, Count = 0 }
	local Slate, Metal = Enum.Material.Slate, Enum.Material.Metal
	local floorTop = 0.6
	local medallion = 5.5
	piece(kit, "PlazaMedallion", Vector3.new(0.08, medallion * 2, medallion * 2), CFrame.new(0, floorTop + 0.04, 0) * UPRIGHT, theme.StoneDark, Slate, false, nil, Enum.PartType.Cylinder)
	piece(kit, "PlazaRing", Vector3.new(0.1, medallion * 2 - 1.2, medallion * 2 - 1.2), CFrame.new(0, floorTop + 0.05, 0) * UPRIGHT, theme.Gold, Metal, false, nil, Enum.PartType.Cylinder)
	piece(kit, "PlazaMedallion", Vector3.new(0.12, medallion * 2 - 2.2, medallion * 2 - 2.2), CFrame.new(0, floorTop + 0.06, 0) * UPRIGHT, theme.Stone, Slate, false, nil, Enum.PartType.Cylinder)
	--[[
		CONQUISTA no centro: pedestal baixo de pedra encaixado no medalhão
		(aro dourado) com um troféu em cima. Missão → 🏆 → Prêmio. Baixo o
		bastante (~6 studs) para não tapar o mural nem o baú.
	]]
	upright(kit, "TrophyPlinth", Vector3.new(0, floorTop + 0.3, 0), 0.6, 5.2, theme.StoneDark, Slate, true)
	upright(kit, "TrophyPedestal", Vector3.new(0, floorTop + 1.3, 0), 1.4, 3.8, theme.Stone, Slate, true)
	upright(kit, "TrophyBand", Vector3.new(0, floorTop + 1.95, 0), 0.22, 4.0, theme.Gold, Metal, false)
	piece(kit, "TrophyBase", Vector3.new(1.5, 0.6, 1.5), CFrame.new(0, floorTop + 2.3, 0), WOOD_DARK, Enum.Material.Wood, false)
	upright(kit, "TrophyStem", Vector3.new(0, floorTop + 3.0, 0), 0.9, 0.45, theme.Gold, Metal, false)
	piece(kit, "TrophyKnot", Vector3.new(0.8, 0.8, 0.8), CFrame.new(0, floorTop + 3.4, 0), theme.Gold, Metal, false, nil, Enum.PartType.Ball)
	upright(kit, "TrophyCup", Vector3.new(0, floorTop + 4.45, 0), 1.7, 2.0, theme.Gold, Metal, false)
	upright(kit, "TrophyRim", Vector3.new(0, floorTop + 5.35, 0), 0.18, 2.3, theme.Crystal, Metal, false)
	for _, side in { -1, 1 } do
		piece(kit, "TrophyHandle", Vector3.new(0.6, 1.1, 0.25), CFrame.new(side * 1.25, floorTop + 4.6, 0) * CFrame.Angles(0, 0, math.rad(side * -15)), theme.Gold, Metal, false)
	end
	-- Caminho até cada estação, na cor dela, com setas douradas no sentido
	-- da história: do mural PARA o troféu, do troféu PARA o baú.
	for _, station in stations do
		local target = Vector3.new(station.Local.X, 0, station.Local.Z)
		local direction = target.Unit
		local from = direction * (medallion + 0.2)
		local to = target - direction * 5.5
		local length = (to - from).Magnitude
		if length > 1 then
			local mid = (from + to) / 2
			local frame = CFrame.lookAt(Vector3.new(mid.X, floorTop + 0.04, mid.Z), Vector3.new(to.X, floorTop + 0.04, to.Z))
			piece(kit, "PlazaPath", Vector3.new(3.2, 0.08, length), frame, station.Color:Lerp(theme.Stone, 0.55), Slate, false)
			for _, side in { -1, 1 } do
				piece(kit, "PlazaPathEdge", Vector3.new(0.22, 0.1, length), frame * CFrame.new(side * 1.7, 0.01, 0), theme.Gold, Metal, false)
			end
			-- As setas correm do mural para o troféu e do troféu para o baú:
			-- apontam para a estação "In" (Prêmios) e para o centro na "Out".
			local towards = if station.Flow == "In" then 1 else -1
			for _, along in { -0.22, 0.22 } do
				for _, side in { -1, 1 } do
					-- "V" deitado no piso, apontando para `towards` ao longo do caminho.
					piece(kit, "PlazaFlow", Vector3.new(0.26, 0.1, 1.3), frame * CFrame.new(side * 0.42, 0.02, along * length) * CFrame.Angles(0, math.rad(side * towards * 35), 0), theme.Gold, Metal, false)
				end
			end
		end
	end
	model:SetAttribute("PartCount", kit.Count)
	model.Parent = parent
	return model
end

return StationMachines
