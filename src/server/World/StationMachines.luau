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

return StationMachines
