--!strict
--[[
	WorldBuilder
	Procedurally builds each world's map from Roblox primitives (low-poly
	style). Deterministic: every world uses a fixed Random seed, so the layout
	is identical on every server.

	Common layout of every world (relative to its origin, ground top at y = 0):
		spawn pad            south  (z = +60)
		service kiosks       around the plaza (upgrades, pets, quests, rewards, shop)
		scoreboard           east   (x = +86), filled by the client with the live ranking
		egg stands           north  (z = -70), one per WorldConfig.Eggs
		rebirth altar        west   (x = -75)
		world portal         south edge (z = +115)
	+ themed decoration (trees / buildings / lava / asteroids / crystals).

	Interactive stations carry a ProximityPrompt with attributes:
		OpenPanel = "<panel id>"   → the client opens that UI panel
		TextKey   = "<loc key>"    → the client localizes the prompt text
	Prompts only OPEN UI; every action still goes through validated remotes.

	Art replacement: put a hand-made model in Workspace.Map.Worlds.<Id> and a
	part in Workspace.Map.Spawns.<SpawnName>; WorldService then skips this
	builder for that world. All generated content is tagged TODO_ASSET.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local AssetIds = require(Shared.Config.AssetIds)
local EggConfig = require(Shared.Config.EggConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local WallConfig = require(Shared.Config.WallConfig)
local CutConfig = require(Shared.Config.CutConfig)
local LobbyConfig = require(Shared.Config.LobbyConfig)
local TrainingConfig = require(Shared.Config.TrainingConfig)
local CutLogic = require(Shared.Formulas.CutLogic)
local ZoneRules = require(Shared.Formulas.ZoneRules)
local WorldRules = require(Shared.Formulas.WorldRules)
local WinPadRules = require(Shared.Formulas.WinPadRules)
local CorridorThemes = require(Shared.Config.CorridorThemes)
local CorridorLayout = require(Shared.Formulas.CorridorLayout)
local NumberFormat = require(Shared.Utils.NumberFormat)
local Text = require(Shared.Localization)
local StationMachines = require(script.Parent.StationMachines)
local PowerPath = require(script.Parent.PowerPath)

type WorldData = Types.WorldData
type ZoneData = Types.ZoneData

local GROUND_RADIUS = 150
local GROUND_HEIGHT = 8
-- The ground is a grid of square blocks in two shades (the "quadradinho" look
-- of the big clicker maps) instead of one smooth disc.
local TILE_STUDS = 20
local TILE_DARKEN = 0.87 -- every other tile is this much darker
local PLAZA_HALF = 46 -- the pale square in the middle (same reach as before)
--[[
	PAREDÕES. A ilha é fechada por paredões de rocha (LobbyConfig.Cliffs), não
	por degraus de bloco: cada segmento tem a face interna VERTICAL e mais de
	58 studs de altura — o pulo do Roblox sobe ~7,2 —, então não há como
	escalar. A única abertura é a boca do Caminho do Poder, fechada dos lados
	pelos pilares do portão (buildPathGate).
	A muralha antiga em degraus custava ~840 peças; os paredões, ~100.
]]
local EGG_SPACING = 32

--[[
	Everything in the lobby is placed from LobbyConfig: each system has an AREA
	with a floor, a sign and a radius, instead of the hand-written coordinates
	this file used to carry (SPAWN_Z, EGG_Z, ALTAR_X...). That is what makes the
	island read as a place and not as props dropped on grass.
]]
local function areaOf(id: string): LobbyConfig.Area
	local area = LobbyConfig.Areas[id]
	assert(area, "LobbyConfig has no area " .. id)
	return area
end

type Palette = {
	Ground: Color3,
	GroundMaterial: Enum.Material,
	Rim: Color3,
	RimMaterial: Enum.Material,
	Accent: Color3, -- stations / neon details
	Pad: Color3,
}

local PALETTES: { [string]: Palette } = {
	Training = { Ground = Color3.fromRGB(96, 170, 72), GroundMaterial = Enum.Material.Grass, Rim = Color3.fromRGB(120, 92, 62), RimMaterial = Enum.Material.Ground, Accent = Color3.fromRGB(255, 196, 45), Pad = Color3.fromRGB(235, 235, 240) },
	City = { Ground = Color3.fromRGB(62, 64, 72), GroundMaterial = Enum.Material.Asphalt, Rim = Color3.fromRGB(150, 150, 155), RimMaterial = Enum.Material.Concrete, Accent = Color3.fromRGB(80, 220, 255), Pad = Color3.fromRGB(200, 200, 210) },
	Volcano = { Ground = Color3.fromRGB(52, 42, 40), GroundMaterial = Enum.Material.Basalt, Rim = Color3.fromRGB(90, 40, 30), RimMaterial = Enum.Material.Rock, Accent = Color3.fromRGB(255, 110, 30), Pad = Color3.fromRGB(120, 70, 60) },
	Space = { Ground = Color3.fromRGB(58, 62, 78), GroundMaterial = Enum.Material.DiamondPlate, Rim = Color3.fromRGB(36, 38, 50), RimMaterial = Enum.Material.Metal, Accent = Color3.fromRGB(120, 200, 255), Pad = Color3.fromRGB(90, 96, 120) },
	Galaxy = { Ground = Color3.fromRGB(62, 40, 96), GroundMaterial = Enum.Material.Slate, Rim = Color3.fromRGB(34, 20, 60), RimMaterial = Enum.Material.Glass, Accent = Color3.fromRGB(210, 110, 255), Pad = Color3.fromRGB(120, 80, 170) },
}

local EGG_COLORS: { [string]: Color3 } = {
	BasicEgg = Color3.fromRGB(245, 240, 225),
	ForestEgg = Color3.fromRGB(110, 190, 90),
	MysticEgg = Color3.fromRGB(170, 90, 255),
}

local WorldBuilder = {}

-- ── Primitive helpers ───────────────────────────────────────────────────────

type PartOptions = {
	Name: string?,
	Size: Vector3,
	CFrame: CFrame,
	Color: Color3,
	Material: Enum.Material?,
	Shape: Enum.PartType?,
	CanCollide: boolean?,
	Transparency: number?,
	CastShadow: boolean?,
}

local function makePart(parent: Instance, options: PartOptions): Part
	local part = Instance.new("Part")
	part.Name = options.Name or "Part"
	part.Anchored = true
	part.Size = options.Size
	part.CFrame = options.CFrame
	part.Color = options.Color
	part.Material = options.Material or Enum.Material.SmoothPlastic
	if options.Shape then
		part.Shape = options.Shape
	end
	part.CanCollide = if options.CanCollide == nil then true else options.CanCollide
	part.Transparency = options.Transparency or 0
	part.CastShadow = if options.CastShadow == nil then true else options.CastShadow
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Flat disc (a cylinder lying on the ground), top face at `top`.
local function disc(parent: Instance, center: Vector3, radius: number, height: number, color: Color3, material: Enum.Material, collide: boolean?): Part
	return makePart(parent, {
		Name = "Disc",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, radius * 2, radius * 2),
		CFrame = CFrame.new(center - Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = material,
		CanCollide = collide,
	})
end

local function block(parent: Instance, cframe: CFrame, size: Vector3, color: Color3, material: Enum.Material?, collide: boolean?): Part
	return makePart(parent, { Name = "Block", Size = size, CFrame = cframe, Color = color, Material = material, CanCollide = collide })
end

local function ball(parent: Instance, position: Vector3, diameter: number, color: Color3, material: Enum.Material?, collide: boolean?): Part
	return makePart(parent, {
		Name = "Ball",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(diameter, diameter, diameter),
		CFrame = CFrame.new(position),
		Color = color,
		Material = material,
		CanCollide = collide,
	})
end

-- Same colour, darker/lighter by a factor (the second tile shade).
local function shade(color: Color3, factor: number): Color3
	return Color3.new(
		math.clamp(color.R * factor, 0, 1),
		math.clamp(color.G * factor, 0, 1),
		math.clamp(color.B * factor, 0, 1)
	)
end

local function light(part: BasePart, color: Color3, range: number, brightness: number)
	local pointLight = Instance.new("PointLight")
	pointLight.Color = color
	pointLight.Range = range
	pointLight.Brightness = brightness
	pointLight.Shadows = false
	pointLight.Parent = part
end

local WALKWAY_WIDTH = 7

-- Distância de (x, z) até a calçada da praça para a área (eixo origem->área).
local function nearWalkway(x: number, z: number, margin: number): boolean
	for _, area in LobbyConfig.Areas do
		if area.Id ~= "Tower" then
			local target = Vector3.new(area.Offset.X, 0, area.Offset.Z)
			local length = target.Magnitude
			if length > 1 then
				local direction = target / length
				local t = math.clamp(x * direction.X + z * direction.Z, 0, length)
				local dx, dz = x - direction.X * t, z - direction.Z * t
				if dx * dx + dz * dz < (WALKWAY_WIDTH / 2 + margin + 3) ^ 2 then
					return true
				end
			end
		end
	end
	return false
end

--[[
	O Caminho do Poder como zona proibida para decoração (relativo à origem):
	do portão ao fim da praça do portal, na largura do trecho mais largo mais
	as paredes. Toda decoração procedural (árvores, pedras, ilhas do céu)
	passa por aqui — foi uma ilha do céu sorteada sem exclusão que ficou
	pairando sobre a Barreira 1.
]]
local function inCorridorBand(x: number, z: number, margin: number): boolean
	local segments = CorridorLayout.Segments()
	local widest = 0
	for _, segment in segments do
		widest = math.max(widest, segment.Width)
	end
	local fromX = WallConfig.Layout.StartX - 30
	local toX = CorridorLayout.FinalStart() + CorridorLayout.FINAL_PLAZA + 40
	local halfZ = widest / 2 + WallConfig.Layout.SideThickness + 20
	return x > fromX - margin and x < toX + margin and math.abs(z) < halfZ + margin
end

-- True when (x, z) is outside every lobby area, the main path, the walkways
-- and the pond, with `margin` studs to spare.
local function clearOfLayout(x: number, z: number, margin: number): boolean
	if nearWalkway(x, z, margin) or inCorridorBand(x, z, margin) then
		return false
	end
	for _, area in LobbyConfig.Areas do
		local dx, dz = x - area.Offset.X, z - area.Offset.Z
		if dx * dx + dz * dz < (area.Radius + margin) ^ 2 then
			return false
		end
		-- Piso retangular passa do círculo (Missões/Prêmios: 64x30 com raio
		-- 16): sem isto, árvores nasciam nos cantos do piso, em cima das
		-- estações e na frente dos letreiros.
		-- (+4: a copa de uma árvore tem até ~6,5 studs de raio.)
		local floor = area.FloorSize
		if floor and math.abs(dx) < floor.X / 2 + margin + 4 and math.abs(dz) < floor.Y / 2 + margin + 4 then
			return false
		end
	end
	if x > 0 and math.abs(z) < LobbyConfig.Path.Width / 2 + margin + 6 then
		return false
	end
	-- Linha de visão de quem nasce até o portão: nada alto no meio dela.
	local spawnArea = LobbyConfig.SpawnPoint
	local gateX = WallConfig.Layout.StartX
	local sx, sz = gateX - spawnArea.X, -spawnArea.Z
	local t = math.clamp(((x - spawnArea.X) * sx + (z - spawnArea.Z) * sz) / (sx * sx + sz * sz), 0, 1)
	local cx, cz = spawnArea.X + sx * t - x, spawnArea.Z + sz * t - z
	if cx * cx + cz * cz < (14 + margin) ^ 2 then
		return false
	end
	local pond = LobbyConfig.Decoration.Pond
	local px, pz = x - pond.X, z - pond.Z
	if px * px + pz * pz < (LobbyConfig.Decoration.PondRadius + margin + 4) ^ 2 then
		return false
	end
	-- a praça clara do meio fica livre
	return not (math.abs(x) < 52 and math.abs(z) < 52)
end

-- Random point on the island ring between minRadius and maxRadius, clear of
-- the lobby layout (clearOfLayout).
local function ringPoint(rng: Random, minRadius: number, maxRadius: number): Vector3
	for _ = 1, 20 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = rng:NextNumber(minRadius, maxRadius)
		local x, z = math.cos(angle) * radius, math.sin(angle) * radius
		-- Fora de qualquer área do lobby, do caminho principal e do lago: antes
		-- árvores e pedras caíam dentro das áreas e no meio do caminho.
		if clearOfLayout(x, z, 4) then
			return Vector3.new(x, 0, z)
		end
	end
	return Vector3.new(minRadius, 0, 0)
end

local function prompt(parent: BasePart, panel: string, textKey: string, objectKey: string?)
	local proximity = Instance.new("ProximityPrompt")
	proximity.ActionText = Text.GetFor(nil, textKey)
	proximity.ObjectText = if objectKey then Text.GetFor(nil, objectKey) else ""
	proximity.HoldDuration = 0
	proximity.MaxActivationDistance = 14
	proximity.RequiresLineOfSight = false
	proximity.KeyboardKeyCode = Enum.KeyCode.E
	proximity.GamepadKeyCode = Enum.KeyCode.ButtonY
	proximity:SetAttribute("OpenPanel", panel)
	proximity:SetAttribute("TextKey", textKey)
	if objectKey then
		proximity:SetAttribute("ObjectKey", objectKey)
	end
	proximity.Parent = parent
end

-- World signs are sized in STUDS (the Scale part of the UDim2), so they shrink
-- with distance instead of covering the screen like a pixel-sized billboard.
local SIGN_STUDS = Vector2.new(16, 3.4)

--[[
	`maxDistance` decide quando o texto aparece: letreiro de identificação
	(curto) pode ser visto de longe; detalhe (preço, requisito, rendimento)
	só aparece de perto. É isso que tira a "massa de texto" do lobby sem
	precisar de script no cliente.
]]
local function billboard(parent: BasePart, text: string, color: Color3, offsetY: number, maxDistance: number?, scale: number?)
	local gui = Instance.new("BillboardGui")
	local factor = scale or 1
	gui.Size = UDim2.fromScale(SIGN_STUDS.X * factor, SIGN_STUDS.Y * factor)
	gui.StudsOffset = Vector3.new(0, offsetY, 0)
	gui.MaxDistance = maxDistance or 120
	gui.AlwaysOnTop = false
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.2
	label.Text = text
	label.Parent = gui
	gui.Parent = parent
end

-- ── Common structure ────────────────────────────────────────────────────────

--[[
	The island floor: square tiles in a checkerboard of two shades, with the
	plaza as a pale square in the middle and stepped hills on the sides.
	Tiles whose centre falls outside the radius are simply not placed, which is
	what gives the edge its blocky silhouette.
]]
local function buildGround(model: Model, origin: Vector3, palette: Palette)
	local reach = math.ceil(GROUND_RADIUS / TILE_STUDS) + 1
	local groundDark = shade(palette.Ground, TILE_DARKEN)
	local plazaDark = shade(palette.Pad, TILE_DARKEN)

	for ix = -reach, reach do
		for iz = -reach, reach do
			local offset = Vector3.new(ix * TILE_STUDS, 0, iz * TILE_STUDS)
			local checker = (ix + iz) % 2 == 0
			if offset.Magnitude <= GROUND_RADIUS then
				local onPlaza = math.abs(offset.X) <= PLAZA_HALF and math.abs(offset.Z) <= PLAZA_HALF
				local color = if onPlaza
					then (if checker then palette.Pad else plazaDark)
					else (if checker then palette.Ground else groundDark)
				block(
					model,
					CFrame.new(origin + offset - Vector3.new(0, GROUND_HEIGHT / 2, 0)),
					Vector3.new(TILE_STUDS, GROUND_HEIGHT, TILE_STUDS),
					color,
					if onPlaza then Enum.Material.Concrete else palette.GroundMaterial
				)
			end
		end
	end

	--[[
		Chapa contínua logo abaixo dos ladrilhos, até debaixo dos paredões. Os
		ladrilhos são quadrados num círculo, então a borda deles é serrilhada;
		sem esta chapa sobravam frestas entre o último ladrilho e o paredão.
		Fica 0,05 abaixo do topo para não brigar (z-fighting) com os ladrilhos.
	]]
	local plateRadius = GROUND_RADIUS + LobbyConfig.Cliffs.Depth
	local plate = disc(model, origin - Vector3.new(0, 0.05, 0), plateRadius, GROUND_HEIGHT, groundDark, palette.GroundMaterial)
	plate.Name = "GroundPlate"
	-- Skirt under the tiles: from below the island still reads as one plate.
	disc(model, origin - Vector3.new(0, GROUND_HEIGHT - 1, 0), plateRadius + 12, 10, palette.Rim, palette.RimMaterial)
end

--[[
	Paredões em volta da ilha. Cada segmento: uma parede de rocha com a face
	interna vertical, um topo de grama e, atrás dela, um segundo maciço mais
	alto (profundidade). Alturas variam por segmento (rng do mundo), então a
	silhueta parece montanha e não muro. A abertura de +X é a boca do
	corredor; o portão fecha os lados dela.
]]
local function buildCliffs(model: Model, origin: Vector3, palette: Palette, rng: Random, hasCorridor: boolean)
	local cliffs = LobbyConfig.Cliffs
	local gate = LobbyConfig.Gate
	local layout = WallConfig.Layout
	-- Metade da abertura: até o MEIO dos pilares do portão, para o primeiro
	-- segmento de cada lado se cruzar com o pilar (sem fresta para cair).
	-- Mundo sem corredor: paredão fechado, sem abertura.
	local openingZ = layout.Width / 2 + 2 + gate.PillarWidth / 2
	local openingAngle = if hasCorridor then math.asin(math.clamp(openingZ / GROUND_RADIUS, 0, 1)) else 0
	local span = math.pi * 2 - openingAngle * 2
	local step = span / cliffs.Segments
	local rock = shade(palette.Rim, 1.05)
	for index = 0, cliffs.Segments - 1 do
		local angle = openingAngle + (index + 0.5) * step
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		-- Largura com sobra: segmentos vizinhos se cruzam, sem fresta.
		local width = 2 * (GROUND_RADIUS + cliffs.Depth) * math.tan(step / 2) * 1.12
		local height = rng:NextNumber(cliffs.MinHeight, cliffs.MaxHeight)
		local tint = rng:NextNumber(0.86, 1.08)
		local centre = origin + direction * (GROUND_RADIUS + cliffs.Depth / 2)
		local facing = CFrame.lookAt(centre, centre - direction)
		local wall = block(model, facing + Vector3.new(0, height / 2 - GROUND_HEIGHT / 2, 0), Vector3.new(width, height + GROUND_HEIGHT, cliffs.Depth), shade(rock, tint), Enum.Material.Slate)
		wall.Name = "Cliff"
		-- Topo de grama, levemente maior: o paredão lê como montanha estilizada.
		block(model, facing + Vector3.new(0, height + 1, 0), Vector3.new(width + 1, 2, cliffs.Depth + 1), shade(palette.Ground, tint * 0.92), palette.GroundMaterial)
		-- Maciço de trás, mais alto e recuado, um pouco girado: profundidade.
		local backHeight = height + rng:NextNumber(14, 38)
		local backCentre = origin + direction * (GROUND_RADIUS + cliffs.Depth + cliffs.BackDepth / 2 - 4)
		local back = CFrame.lookAt(backCentre, backCentre - direction) * CFrame.Angles(0, rng:NextNumber(-0.18, 0.18), 0)
		block(model, back + Vector3.new(0, backHeight / 2 - GROUND_HEIGHT / 2, 0), Vector3.new(width * 1.05, backHeight + GROUND_HEIGHT, cliffs.BackDepth), shade(rock, tint * 0.82), Enum.Material.Rock)
		if index % 2 == 0 then
			block(model, back + Vector3.new(0, backHeight + 1, 0), Vector3.new(width * 1.05 + 1, 2, cliffs.BackDepth + 1), shade(palette.Ground, tint * 0.8), palette.GroundMaterial)
		end

		--[[
			Passada leve de acabamento (sem voltar às centenas de blocos): a face
			lisa de cada segmento ganha UMA faixa de estrato saliente e UM bloco
			de rocha na base, e segmentos alternados um arbusto. Tudo sem
			colisão — é só para a superfície não ler como "blockout".
		]]
		-- Gerador próprio: o acabamento não muda a sequência do mapa (árvores
		-- e enfeites continuam onde estavam).
		local detail = Random.new(9_001 + index * 7_919)
		local face = facing - direction * (cliffs.Depth / 2 + 0.6)
		local strataY = height * detail:NextNumber(0.35, 0.6)
		local strata = block(model, face * CFrame.Angles(0, 0, detail:NextNumber(-0.04, 0.04)) + Vector3.new(0, strataY - GROUND_HEIGHT / 2, 0), Vector3.new(width * detail:NextNumber(0.6, 0.85), detail:NextNumber(1.6, 3), 2.4), shade(rock, tint * 0.78), Enum.Material.Slate, false)
		strata.Name = "CliffStrata"
		local outcropHeight = detail:NextNumber(9, 18)
		local lateral = detail:NextNumber(-0.3, 0.3) * width
		local outcrop = block(
			model,
			face * CFrame.new(lateral, outcropHeight / 2 - 2, -1.5) * CFrame.Angles(detail:NextNumber(-0.12, 0.05), detail:NextNumber(-0.5, 0.5), detail:NextNumber(-0.15, 0.15)),
			Vector3.new(detail:NextNumber(8, 14), outcropHeight, detail:NextNumber(5, 8)),
			shade(rock, tint * detail:NextNumber(0.9, 1.05)),
			Enum.Material.Rock,
			false
		)
		outcrop.Name = "CliffOutcrop"
		if index % 2 == 1 then
			local bushAt = (face * CFrame.new(lateral + detail:NextNumber(6, 10) * (if lateral > 0 then -1 else 1), 1.4, -4)).Position
			ball(model, bushAt, detail:NextNumber(4, 6), shade(palette.Ground, detail:NextNumber(0.75, 0.9)), palette.GroundMaterial, false).Name = "CliffBush"
			ball(model, bushAt + Vector3.new(detail:NextNumber(-2.5, 2.5), 0.6, detail:NextNumber(-1.5, 1.5)), detail:NextNumber(3, 4.5), shade(palette.Ground, detail:NextNumber(0.85, 1)), palette.GroundMaterial, false).Name = "CliffBush"
		end
	end
end

local function buildSpawn(model: Model, origin: Vector3, palette: Palette, world: WorldData, spawns: Folder, withSpawnLocation: boolean)
	local padCenter = origin + LobbyConfig.SpawnPoint + Vector3.new(0, 0.3, 0)
	-- Tablado de pedra com friso dourado fino (antes: disco neon amarelo inteiro).
	disc(model, padCenter, 9, 0.6, shade(LobbyConfig.Gate.Trim, 0.8), Enum.Material.SmoothPlastic)
	disc(model, padCenter + Vector3.new(0, 0.1, 0), 8, 0.6, palette.Pad, Enum.Material.Marble)
	local glow = disc(model, padCenter + Vector3.new(0, 0.18, 0), 3, 0.2, LobbyConfig.Gate.Energy, Enum.Material.Neon, false)
	glow.Transparency = 0.45
	--[[
		O jogador nasce olhando para +X, ao longo da avenida, de frente para o
		portão do Caminho do Poder. A orientação é montada com fromMatrix (sem
		lookAt) para não depender de nenhuma convenção: LookVector = +X.
		ATENÇÃO: no Roblox a câmera NÃO acompanha o PivotTo do servidor; quem
		alinha a câmera depois do teleporte é o SpawnCameraController (cliente).
	]]
	local spawnFrame = CFrame.fromMatrix(padCenter + Vector3.new(0, 3, 0), Vector3.new(0, 0, 1), Vector3.new(0, 1, 0))
	local marker = Instance.new("Part")
	marker.Name = world.SpawnName
	marker:SetAttribute("TODO_ASSET", true)
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.Transparency = 1
	marker.Size = Vector3.new(4, 1, 4)
	marker.CFrame = spawnFrame
	marker.Parent = spawns

	if withSpawnLocation then
		-- Roblox's default spawn for brand-new characters (before data loads).
		local spawnLocation = Instance.new("SpawnLocation")
		spawnLocation.Name = "SpawnLocation"
		spawnLocation.Anchored = true
		spawnLocation.Size = Vector3.new(8, 0.4, 8)
		spawnLocation.CFrame = spawnFrame - Vector3.new(0, 2.5, 0)
		spawnLocation.Transparency = 1
		spawnLocation.CanCollide = false
		spawnLocation.Duration = 0 -- no force field bubble
		spawnLocation.Neutral = true
		local decal = spawnLocation:FindFirstChildOfClass("Decal")
		if decal then
			decal:Destroy()
		end
		spawnLocation.Parent = model
	end
end

--[[
	As bancadas de ovo ficam num ARCO dentro da área: em linha reta, cinco
	bancadas (160 studs) estouravam o piso de 88 de diâmetro. O arco também
	deixa todas de frente para quem chega da praça.
]]
local function buildEggStands(model: Model, origin: Vector3, palette: Palette, world: WorldData)
	local count = #world.Eggs
	local area = areaOf("Eggs")
	local radius = math.max(area.Radius - 16, 10)
	local incubation = LobbyConfig.IncubationArea == true
	local stands = {}
	for index, eggId in world.Eggs do
		local egg = EggConfig.Eggs[eggId]
		if egg then
			-- Arco de 140 graus virado para a praça (+Z).
			local spread = math.rad(140)
			local step = if count > 1 then spread / (count - 1) else 0
			local angle = math.rad(90) - spread / 2 + (index - 1) * step
			local base = origin + area.Offset + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
			disc(model, base + Vector3.new(0, 1.5, 0), 9, 1.5, palette.Rim, Enum.Material.Marble)
			disc(model, base + Vector3.new(0, 4.5, 0), 6, 3, palette.Pad, Enum.Material.Marble)
			-- Friso dourado discreto (antes: anel neon amarelo em cada bancada).
			local ring = disc(model, base + Vector3.new(0, 4.8, 0), 6.4, 0.3, shade(LobbyConfig.Gate.Trim, 0.9), Enum.Material.SmoothPlastic, false)
			ring.Name = "Glow"
			local eggPart = makePart(model, {
				Name = "Egg_" .. eggId,
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(7, 7, 7),
				CFrame = CFrame.new(base + Vector3.new(0, 9, 0)),
				Color = EGG_COLORS[eggId] or Color3.new(1, 1, 1),
				Material = Enum.Material.SmoothPlastic,
			})
			-- Stretch to an egg shape.
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Scale = Vector3.new(1, 1.3, 1)
			mesh.Parent = eggPart
			local icon = if egg.Currency == "Gems" then "💎" else "⚡"
			if incubation then
				-- Placa física da incubadora (StationMachines) no lugar do letreiro.
				local requirement = nil
				if egg.RequiredStage then
					for _, stage in WallConfig.Stages do
						if stage.Id == egg.RequiredStage then
							requirement = Text.GetFor(nil, "eggs.stageLocked", { order = stage.Order })
						end
					end
				end
				table.insert(stands, {
					Id = eggId,
					Base = base,
					Facing = Vector3.new(base.X - (origin + area.Offset).X, 0, base.Z - (origin + area.Offset).Z).Unit,
					Tier = index,
					EggCentre = 9,
					EggRadius = 3.5,
					PedestalTop = 4.5,
					PedestalRadius = 6,
					Title = Text.GetFor(nil, "egg." .. eggId .. ".name"),
					Price = string.format("%s %s", icon, NumberFormat.Short(egg.Price)),
					Requirement = requirement,
				})
			else
				billboard(eggPart, string.format("%s\n%s %s", Text.GetFor(nil, "egg." .. eggId .. ".name"), icon, NumberFormat.Short(egg.Price)), Color3.new(1, 1, 1), 7, 60, 0.8)
			end
			prompt(eggPart, "Eggs", "world.prompt.hatch", "egg." .. eggId .. ".name")
		end
	end

	--[[
		MARCO DOS OVOS: um ovo gigante num pedestal, atrás das bancadas. De
		longe ele diz "ovos" sem precisar do letreiro. Baixo de propósito
		(~17 studs): o protagonista do lobby é o portão do Caminho do Poder.
	]]
	local back = origin + area.Offset + Vector3.new(0, 0, -1) * (area.Radius - 13)
	disc(model, back + Vector3.new(0, 1, 0), 6.5, 1, palette.Rim, Enum.Material.Marble)
	disc(model, back + Vector3.new(0, 3, 0), 5, 2, palette.Pad, Enum.Material.Marble)
	local giant = makePart(model, {
		Name = "EggLandmark",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(9, 9, 9),
		CFrame = CFrame.new(back + Vector3.new(0, 9.4, 0)),
		Color = Color3.fromRGB(250, 244, 228),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
	})
	local giantMesh = Instance.new("SpecialMesh")
	giantMesh.MeshType = Enum.MeshType.Sphere
	giantMesh.Scale = Vector3.new(1, 1.35, 1)
	giantMesh.Parent = giant
	local band = disc(model, back + Vector3.new(0, 9.9, 0), 4.6, 1.4, LobbyConfig.Gate.Trim, Enum.Material.Metal, false)
	band.Name = "EggLandmarkBand"
	if incubation then
		StationMachines.DecorateEggs(model, {
			Title = "🥚 " .. StationMachines.Upper(Text.GetFor(nil, "station.eggs.name")),
			Subtitle = Text.GetFor(nil, "station.eggs.subtitle"),
		}, stands, back, Vector3.new(0, 0, 1))
	else
		light(giant, Color3.fromRGB(255, 226, 150), 18, 0.9)
	end
end

local function buildAltar(model: Model, origin: Vector3, palette: Palette)
	local base = origin + areaOf("Rebirth").Offset
	if LobbyConfig.RebirthStation == "Altar" then
		-- Altar do Renascimento (o prompt de sempre, no núcleo).
		local facing = CFrame.lookAt(base, Vector3.new(origin.X, base.Y, origin.Z))
		local _, core = StationMachines.BuildRebirthAltar(model, facing, {
			Title = "♻️ " .. StationMachines.Upper(Text.GetFor(nil, "station.rebirth.name")),
			Subtitle = Text.GetFor(nil, "station.rebirth.subtitle"),
		}, 0.35)
		prompt(core, "Rebirth", "world.prompt.rebirth")
		return
	end
	disc(model, base + Vector3.new(0, 1, 0), 10, 1, palette.Rim, Enum.Material.Marble)
	for step = 1, 3 do
		disc(model, base + Vector3.new(0, 1 + step * 1.2, 0), 10 - step * 2, 1.2, palette.Pad, Enum.Material.Marble)
	end
	local orb = ball(model, base + Vector3.new(0, 10, 0), 5, Color3.fromRGB(140, 90, 255), Enum.Material.Neon, false)
	orb.Name = "RebirthOrb"
	light(orb, Color3.fromRGB(140, 90, 255), 18, 2)
	billboard(orb, "🔁 " .. Text.GetFor(nil, "menu.rebirth"), Color3.fromRGB(200, 170, 255), 5, 60, 0.8)
	prompt(orb, "Rebirth", "world.prompt.rebirth")

	--[[
		MARCO DO RENASCER: um halo roxo vertical sobre o altar, virado para a
		praça (oito segmentos, como a moldura do portal). Reconhecível de longe,
		baixo o bastante para não competir com o portão.
	]]
	local towardPlaza = Vector3.new(-base.X + origin.X, 0, -base.Z + origin.Z).Unit
	local haloCentre = base + Vector3.new(0, 13, 0)
	local haloFrame = CFrame.lookAt(haloCentre, haloCentre + towardPlaza)
	for segment = 0, 7 do
		local angle = segment * math.pi / 4
		local piece = block(
			model,
			haloFrame * CFrame.new(math.cos(angle) * 7, math.sin(angle) * 7, 0) * CFrame.Angles(0, 0, angle + math.pi / 2),
			Vector3.new(5.6, 0.9, 0.9),
			Color3.fromRGB(170, 120, 255),
			Enum.Material.Neon,
			false
		)
		piece.Name = "RebirthHalo"
	end
end

local function buildPortal(model: Model, origin: Vector3, palette: Palette)
	-- The portal to the other worlds stands behind the spawn (dormant: the
	-- tower is the progression now, see docs/PLANO_TORRE.md §C3).
	local base = origin + areaOf("Spawn").Offset + Vector3.new(0, 0, 54)
	local frameColor = palette.Rim
	block(model, CFrame.new(base + Vector3.new(-9, 9, 0)), Vector3.new(3, 18, 3), frameColor, Enum.Material.Marble)
	block(model, CFrame.new(base + Vector3.new(9, 9, 0)), Vector3.new(3, 18, 3), frameColor, Enum.Material.Marble)
	block(model, CFrame.new(base + Vector3.new(0, 19, 0)), Vector3.new(21, 3, 3), frameColor, Enum.Material.Marble)
	local field = block(model, CFrame.new(base + Vector3.new(0, 9, 0)), Vector3.new(15, 17, 0.6), palette.Accent, Enum.Material.Neon, false)
	field.Name = "PortalField"
	field.Transparency = 0.35
	light(field, palette.Accent, 20, 2)
	billboard(field, "🌍 " .. Text.GetFor(nil, "menu.worlds"), Color3.new(1, 1, 1), 12)
	prompt(field, "Worlds", "world.prompt.travel")
end

--[[
	Quiosque: balcão + toldo + letreiro curto, com o prompt que abre `Panel`.
	Na área da LOJA o quiosque vira barraca de mercado — toldo listrado,
	caixotes e uma vitrine com uma gema gigante —, então a estrutura diz
	"loja" sem precisar de uma palavra enorme no céu.
]]
local function buildStations(model: Model, origin: Vector3, palette: Palette)
	for _, station in LobbyConfig.Stations do
		local base = origin + areaOf(station.Area).Offset + station.Local
		local facing = CFrame.lookAt(base, origin + Vector3.new(0, 0, 0)) -- always faces the plaza
		local yaw = facing - facing.Position
		if station.Style == "Machine" then
			-- Protótipo: estação-máquina; o prompt é o mesmo, no console dela.
			local _, console = StationMachines.BuildUpgrades(model, CFrame.new(base) * yaw, station.Panel, {
				Title = string.format("%s %s", station.Icon, StationMachines.Upper(Text.GetFor(nil, station.NameKey))),
				Subtitle = Text.GetFor(nil, "station.upgrades.subtitle"),
				Npc = station.Npc == true,
			})
			prompt(console, station.Panel, station.TextKey, station.NameKey)
			continue
		elseif station.Style == "PetLab" then
			-- Estação de companheiros: o prompt de Pets de sempre, no terminal.
			local previews = {}
			for _, petId in station.Previews or {} do
				table.insert(previews, AssetIds["pet_" .. petId] or "")
			end
			local _, terminal = StationMachines.BuildPetLab(model, CFrame.new(base) * yaw, station.Panel, {
				Title = string.format("%s %s", station.Icon, StationMachines.Upper(Text.GetFor(nil, station.NameKey))),
				Subtitle = Text.GetFor(nil, "station.pets.subtitle"),
				Previews = previews,
			})
			prompt(terminal, station.Panel, station.TextKey, station.NameKey)
			continue
		elseif station.Style == "QuestBoard" or station.Style == "RewardTotem" then
			-- Central do Aventureiro: quadro de missões / totem de prêmios,
			-- com o mesmo prompt de antes (abre o painel atual).
			local build = if station.Style == "QuestBoard" then StationMachines.BuildQuestBoard else StationMachines.BuildRewardTotem
			local _, anchor = build(model, CFrame.new(base) * yaw, station.Panel, {
				Title = string.format("%s %s", station.Icon, StationMachines.Upper(Text.GetFor(nil, station.NameKey))),
				Subtitle = Text.GetFor(nil, "station." .. string.lower(station.Panel) .. ".subtitle"),
			})
			prompt(anchor, station.Panel, station.TextKey, station.NameKey)
			continue
		end
		local market = station.Area == "Shop"
		local counter = block(model, CFrame.new(base + Vector3.new(0, 2.5, 0)) * yaw, Vector3.new(12, 5, 5), palette.Rim, Enum.Material.WoodPlanks)
		counter.Name = "Station_" .. station.Panel
		block(model, CFrame.new(base + Vector3.new(0, 5.4, 0)) * yaw, Vector3.new(13, 0.8, 6), shade(station.Color, 0.85), Enum.Material.WoodPlanks)
		for side = -1, 1, 2 do
			block(model, CFrame.new(base + Vector3.new(0, 8, 0)) * yaw * CFrame.new(side * 5.6, 0, -2), Vector3.new(0.8, 6, 0.8), palette.Rim, Enum.Material.Wood)
		end
		if market then
			-- Toldo listrado inclinado (cor da estação + creme).
			for stripe = -2, 2 do
				local color = if stripe % 2 == 0 then station.Color else Color3.fromRGB(250, 240, 220)
				local strip = block(model, CFrame.new(base + Vector3.new(0, 11.4, 0)) * yaw * CFrame.new(stripe * 2.8, 0, 0) * CFrame.Angles(math.rad(-14), 0, 0), Vector3.new(2.8, 0.6, 9), color, Enum.Material.Fabric, false)
				strip.Name = "Canopy"
			end
			-- Caixotes e um saco ao lado do balcão.
			block(model, CFrame.new(base + Vector3.new(0, 1.6, 0)) * yaw * CFrame.new(8.5, 0, 1), Vector3.new(3.2, 3.2, 3.2), Color3.fromRGB(176, 128, 78), Enum.Material.WoodPlanks)
			block(model, CFrame.new(base + Vector3.new(0, 1.2, 0)) * yaw * CFrame.new(-8.2, 0, 0.5) * CFrame.Angles(0, 0.4, 0), Vector3.new(2.4, 2.4, 2.4), Color3.fromRGB(150, 108, 66), Enum.Material.WoodPlanks)
		else
			local canopy = block(model, CFrame.new(base + Vector3.new(0, 11.4, 0)) * yaw, Vector3.new(14, 0.8, 8), station.Color, Enum.Material.Fabric, false)
			canopy.Name = "Canopy"
		end
		-- Above the canopy (which sits at y = 11.4): at 9 the sign was inside it.
		billboard(counter, string.format("%s %s", station.Icon, Text.GetFor(nil, station.NameKey)), Color3.new(1, 1, 1), 14, 60, 0.7)
		prompt(counter, station.Panel, station.TextKey, station.NameKey)
	end

	-- Vitrine da loja: pedestal com uma gema gigante girada (o símbolo de loja
	-- de gemas que todo jogador de simulator reconhece).
	local shop = areaOf("Shop")
	local showcase = origin + shop.Offset
	block(model, CFrame.new(showcase + Vector3.new(0, 1.5, 0)), Vector3.new(6, 3, 6), palette.Pad, Enum.Material.Marble)
	-- 30% menor, mais baixa, um pouco mais translúcida e com luz mais curta:
	-- era do mesmo ciano do núcleo da estação de Melhorias ao lado e
	-- disputava a atenção com ele. (A Loja será revista à parte.)
	local gem = block(model, CFrame.new(showcase + Vector3.new(0, 6.6, 0)) * CFrame.Angles(math.rad(45), 0, math.rad(45)), Vector3.new(3.2, 3.2, 3.2), Color3.fromRGB(90, 210, 255), Enum.Material.Neon, false)
	gem.Name = "ShopGem"
	gem.Transparency = 0.25
	light(gem, Color3.fromRGB(90, 210, 255), 9, 0.6)
end

-- Board frame; the live ranking is drawn by the client (ScoreboardController),
-- which finds it by the "Scoreboard" attribute. Server-side it stays empty.
local function buildScoreboard(model: Model, origin: Vector3, palette: Palette)
	local base = origin + LobbyConfig.Scoreboard
	local turn = CFrame.Angles(0, math.rad(LobbyConfig.ScoreboardYaw or 0), 0)
	local yaw = turn * CFrame.Angles(0, -math.pi / 2, 0) -- light bar faces the plaza
	disc(model, base + Vector3.new(0, 0.5, 0), 16, 0.5, palette.Pad, Enum.Material.Concrete)
	for side = -1, 1, 2 do
		block(model, CFrame.new(base + Vector3.new(0, 9, side * 14)), Vector3.new(3, 18, 3), palette.Rim, Enum.Material.Metal)
	end
	local panel = makePart(model, {
		Name = "Scoreboard",
		Size = Vector3.new(1, 22, 34),
		CFrame = CFrame.new(base + Vector3.new(0, 20, 0)) * turn,
		Color = Color3.fromRGB(18, 20, 32),
		Material = Enum.Material.SmoothPlastic,
	})
	panel:SetAttribute("Scoreboard", true)
	panel:SetAttribute("TODO_ASSET", true)
	block(model, CFrame.new(base + Vector3.new(0, 32, 0)), Vector3.new(2, 2.2, 36), palette.Accent, Enum.Material.Neon, false)
	local topLight = block(model, CFrame.new(base + Vector3.new(0, 31.4, 0)) * yaw, Vector3.new(34, 1, 2), palette.Accent, Enum.Material.Neon, false)
	light(topLight, palette.Accent, 26, 2)
	return panel
end

-- ── Training zones ──────────────────────────────────────────────────────────

--[[
	A monster as a standee: a pedestal on the ground and the artwork on a
	BillboardGui, which always faces whoever is looking. Roblox has no cheap way
	to turn a PNG into a 3D model, and a flat cut-out is what simulators use for
	this; it also keeps the art readable from any angle.
	Returns the anchor part (invisible) that TargetService tracks.
]]
local MONSTER_HEIGHT = 16 -- studs
local MONSTER_WIDTH = 15

local function buildStandee(model: Model, zone: ZoneData, position: Vector3, image: string): BasePart
	disc(model, position + Vector3.new(0, 1.2, 0), 7, 1.2, zone.Color, Enum.Material.SmoothPlastic)
	disc(model, position + Vector3.new(0, 1.5, 0), 5.6, 0.4, Color3.fromRGB(240, 240, 245), Enum.Material.Concrete, false)

	-- The anchor is what takes the hits: invisible, but solid so players cannot
	-- walk through the monster.
	local anchor = makePart(model, {
		Name = "Anchor",
		Size = Vector3.new(MONSTER_WIDTH * 0.45, MONSTER_HEIGHT * 0.7, MONSTER_WIDTH * 0.45),
		CFrame = CFrame.new(position + Vector3.new(0, MONSTER_HEIGHT * 0.45, 0)),
		Color = zone.Color,
		Transparency = 1,
	})
	anchor.CastShadow = false
	anchor:SetAttribute("Standee", true)
	-- The artwork rises above the anchor, so the client's HP bar needs to know
	-- how high to float instead of guessing from the part's size.
	anchor:SetAttribute("BarHeight", MONSTER_HEIGHT * 0.78)

	local gui = Instance.new("BillboardGui")
	gui.Name = "Monster"
	gui.Size = UDim2.fromScale(MONSTER_WIDTH, MONSTER_HEIGHT) -- studs, so it shrinks with distance
	gui.StudsOffset = Vector3.new(0, MONSTER_HEIGHT * 0.12, 0)
	gui.MaxDistance = 260
	gui.Parent = anchor

	local art = Instance.new("ImageLabel")
	art.Name = "Art"
	art.BackgroundTransparency = 1
	art.Image = image
	art.ScaleType = Enum.ScaleType.Fit
	art.Size = UDim2.fromScale(1, 1)
	art.Parent = gui
	return anchor
end

-- One breakable target. The returned part carries the attributes TargetService
-- looks for; children are decoration and fade with it when it breaks.
local function buildTarget(model: Model, zone: ZoneData, index: number, position: Vector3): BasePart
	local kind = zone.Target.Kind
	local artwork = AssetIds["mob_" .. zone.Id]
	local main: BasePart
	if artwork and artwork ~= "" then
		main = buildStandee(model, zone, position, artwork)
	elseif kind == "Rock" then
		main = block(model, CFrame.new(position + Vector3.new(0, 5, 0)) * CFrame.Angles(0, index * 0.7, 0), Vector3.new(11, 10, 11), zone.Color, Enum.Material.Rock)
	elseif kind == "Crystal" then
		main = block(model, CFrame.new(position + Vector3.new(0, 8, 0)) * CFrame.Angles(0.12, index * 0.9, 0), Vector3.new(5, 16, 5), zone.Color, Enum.Material.Neon)
		main.Transparency = 0.15
	elseif kind == "Orb" then
		main = ball(model, position + Vector3.new(0, 9, 0), 11, zone.Color, Enum.Material.Neon, true)
		light(main, zone.Color, 18, 2)
	else -- Dummy: a punching bag on a post
		block(model, CFrame.new(position + Vector3.new(0, 1.5, 0)), Vector3.new(6, 3, 6), Color3.fromRGB(90, 70, 50), Enum.Material.Wood)
		block(model, CFrame.new(position + Vector3.new(0, 6, 0)), Vector3.new(1.2, 9, 1.2), Color3.fromRGB(120, 95, 65), Enum.Material.Wood)
		main = block(model, CFrame.new(position + Vector3.new(0, 11, 0)), Vector3.new(6, 9, 6), zone.Color, Enum.Material.Fabric)
		ball(model, position + Vector3.new(0, 16, 0), 5, zone.Color, Enum.Material.Fabric, false)
	end
	main.Name = string.format("Target_%s_%d", zone.Id, index)
	main:SetAttribute("Target", true)
	main:SetAttribute("ZoneId", zone.Id)
	main:SetAttribute("TargetIndex", index)
	main:SetAttribute("TODO_ASSET", true)
	return main
end

--[[
	Walkway from `fromEdge` up to `toEdge`. It is a RAMP, not stairs: a step
	taller than ~2 studs forces the player to jump, and a staircase of those is
	miserable to climb. One tilted slab keeps the surface continuous, and the
	slope stays gentle because the bridges are far longer than they are tall
	(tools/check_world_layout.py checks the angle).
]]
local BRIDGE_WIDTH = 14
local BRIDGE_THICKNESS = 1.4
local RAIL_HEIGHT = 4

local function buildBridge(model: Model, fromEdge: Vector3, toEdge: Vector3, color: Color3)
	local span = toEdge - fromEdge
	if span.Magnitude < 1 then
		return
	end
	local middle = fromEdge + span / 2
	-- lookAt along the full direction (Y included) tilts the slab into a ramp.
	-- The slab hangs BELOW the line between the two points, so its walking
	-- surface meets the island and the platform instead of sinking into them.
	local orientation = CFrame.lookAt(middle, middle + span.Unit) * CFrame.new(0, -BRIDGE_THICKNESS / 2, 0)
	local deck = makePart(model, {
		Name = "Bridge",
		Size = Vector3.new(BRIDGE_WIDTH, BRIDGE_THICKNESS, span.Magnitude),
		CFrame = orientation,
		Color = color,
		Material = Enum.Material.WoodPlanks,
	})
	deck.TopSurface = Enum.SurfaceType.Smooth

	-- Solid rails: without collision a player walks straight off the side and
	-- falls out of the world.
	for side = -1, 1, 2 do
		block(
			model,
			orientation * CFrame.new(side * (BRIDGE_WIDTH / 2 - 0.3), RAIL_HEIGHT / 2 + BRIDGE_THICKNESS / 2, 0),
			Vector3.new(0.8, RAIL_HEIGHT, span.Magnitude),
			color,
			Enum.Material.Wood,
			true
		)
	end
end

--[[
	A zone island: floating platform, entrance gate with its requirement, and a
	ring of breakable targets. `previousEdge` is where the walkway comes from.
]]
local function buildZone(model: Model, zone: ZoneData, center: Vector3, previousEdge: Vector3): Vector3
	disc(model, center, zone.Radius, 8, zone.Color, Enum.Material.Grass)
	disc(model, center - Vector3.new(0, 7, 0), zone.Radius - 10, 12, Color3.fromRGB(70, 60, 80), Enum.Material.Rock)
	disc(model, center + Vector3.new(0, 0.3, 0), zone.Radius - 14, 0.5, Color3.fromRGB(240, 240, 245), Enum.Material.Concrete)

	-- Entrance gate on the south rim, facing the walkway.
	local gateCenter = center + Vector3.new(0, 0, zone.Radius - 2)
	for side = -1, 1, 2 do
		block(model, CFrame.new(gateCenter + Vector3.new(side * 10, 9, 0)), Vector3.new(3, 18, 3), Color3.fromRGB(60, 55, 80), Enum.Material.Marble)
	end
	local banner = block(model, CFrame.new(gateCenter + Vector3.new(0, 19, 0)), Vector3.new(23, 4, 3), zone.Color, Enum.Material.Neon, false)
	banner.Name = "ZoneBanner_" .. zone.Id
	light(banner, zone.Color, 22, 2)
	local signText = string.format(
		"%s\nx%s ⚡  •  %s %s",
		Text.GetFor(nil, "zone." .. zone.Id .. ".name"),
		NumberFormat.Short(zone.Multiplier),
		NumberFormat.Short(zone.Requirement.Power),
		Text.GetFor(nil, "zone.requirementShort")
	)
	billboard(banner, signText, Color3.new(1, 1, 1), 6)

	-- Shimmering wall inside the gate. It is SOLID by default; each client
	-- turns it off for itself once it qualifies (ZoneController), which is safe
	-- because the zone's multiplier and targets are gated on the server too.
	local barrier = makePart(model, {
		Name = "Barrier_" .. zone.Id,
		Size = Vector3.new(20, 18, 1.2),
		CFrame = CFrame.new(gateCenter + Vector3.new(0, 9, 0)),
		Color = zone.Color,
		Material = Enum.Material.ForceField,
		Transparency = 0.45,
	})
	barrier:SetAttribute("ZoneBarrier", zone.Id)
	barrier:SetAttribute("TODO_ASSET", true)
	barrier.CastShadow = false

	for index = 1, zone.Target.Count do
		local angle = (index - 1) / zone.Target.Count * math.pi * 2
		local radius = zone.Radius - 26
		buildTarget(model, zone, index, center + Vector3.new(math.cos(angle) * radius, 4, math.sin(angle) * radius))
	end

	buildBridge(model, previousEdge, gateCenter - Vector3.new(0, 0, 6), Color3.fromRGB(150, 115, 75))
	return center - Vector3.new(0, 0, zone.Radius - 8) -- north rim: where the next bridge starts
end

local function buildZones(model: Model, origin: Vector3, world: WorldData)
	-- Start on the island floor and a little inside the rim, so the ramp is
	-- stepped onto, never jumped onto.
	local edge = origin + Vector3.new(0, 0.5, -(GROUND_RADIUS - 8))
	for _, zone in ZoneRules.ForWorld(world.Id) do
		local center = origin + zone.Offset + Vector3.new(0, ZoneConfig.PlatformHeight, 0)
		edge = buildZone(model, zone, center, edge)
	end
end

--[[
	Área de treino: uma máquina por estação do TrainingConfig, cada uma com o
	seu pad (é o pad que o TrainingService usa como referência de posição) e um
	letreiro dizendo quanto rende e o que exige.

	Cada tipo tem um visual próprio para a área não parecer quatro caixas
	iguais: saco de pancada, halteres, esteira e máquina de força.
]]
--[[
	CAMPO DE TREINAMENTO: quatro alvos de treino em arco (StationMachines).
	O TrainingService mede pela config (Local + Radius), não pelas peças: o
	pedestal de cada alvo tem o mesmo tamanho do raio que conta. Requisito em
	Renascimentos, decidido no servidor; a placa sai com o texto "bloqueado"
	e o cliente troca para "liberado" para quem já pode treinar.
]]
local function buildTrainingMachines(model: Model, origin: Vector3, _palette: Palette)
	local area = areaOf(TrainingConfig.Area)
	local spots = {}
	for _, station in TrainingConfig.Stations do
		local required = math.max(math.floor(station.RequiredRebirths), 0)
		local locked, unlocked
		if required <= 0 then
			locked = Text.GetFor(nil, "training.free")
			unlocked = locked
		elseif required == 1 then
			locked = Text.GetFor(nil, "training.requiresOne")
			unlocked = Text.GetFor(nil, "training.unlockedOne")
		else
			locked = Text.GetFor(nil, "training.requires", { count = tostring(required) })
			unlocked = Text.GetFor(nil, "training.unlocked", { count = tostring(required) })
		end
		table.insert(spots, {
			Id = station.Id,
			Kind = station.Kind,
			Tier = math.clamp(station.Order, 1, 4),
			Centre = station.Local,
			Radius = station.Radius,
			Name = Text.GetFor(nil, "training." .. station.Id .. ".name"),
			Rebirths = required,
			Locked = locked,
			Unlocked = unlocked,
		})
	end
	local half = (area.FloorSize or Vector2.new(area.Radius * 1.6, area.Radius * 1.2)).Y / 2
	StationMachines.BuildTrainingField(model, CFrame.new(origin + area.Offset), {
		Title = "🏋️ " .. StationMachines.Upper(Text.GetFor(nil, "station.training.name")),
		Subtitle = Text.GetFor(nil, "station.training.subtitle"),
	}, spots, -half + 1.2, Vector3.new(0, 0, -half - 90))
end

--[[
	Pads de corte, em grade no adro diante do portão. CutService answers the
	prompt (PromptTriggered is a server event), so the price and the wins
	requirement are never checked on the client.

	Cada pad é uma ESTAÇÃO (vitrine), lida de quem anda pela avenida:
	- pedestal no meio do pad e, acima dele, a âncora `CutShowcase_<id>`
	  onde o cliente põe o orbe de energia e toca a demonstração do corte
	  (CutShowcaseController; o efeito é o mesmo do golpe);
	- placa baixa `CutCard_<id>` na borda do pad que dá para a avenida,
	  virada para ela e um pouco para quem chega (CardYaw) e inclinada como um
	  balcão (CardTilt). O cliente escreve nela bônus, requisito e estado, que
	  dependem de cada jogador.
	Antes eram duas placas flutuando no alto de cada pad: vistas da avenida,
	as quatro de cada fileira se empilhavam umas sobre as outras.

	Posição lateral (LobbyConfig.CutStations): as fileiras ficam por fora da
	zona livre central da avenida, e a placa fica recuada para dentro do pad,
	para que nada da estação avance sobre o caminho até a barreira 1.
]]
local function buildCutPads(model: Model, origin: Vector3, palette: Palette)
	local layout = CutConfig.Layout
	local cuts = CutLogic.Ordered()
	local area = areaOf(layout.Area)
	local columns = layout.Columns
	local rows = math.ceil(#cuts / columns)
	local steel = Color3.fromRGB(104, 112, 134)
	local slate = Color3.fromRGB(58, 62, 78)
	local stations = LobbyConfig.CutStations
	local cardSize = stations.CardSize
	local yaw = math.rad(stations.CardYaw)
	local tilt = math.rad(layout.CardTilt)
	-- Fileiras encostadas por fora da zona livre (simétricas em volta do eixo).
	local rowDistance = stations.ClearHalfWidth + layout.PadSize / 2
	-- Quanto a placa girada e inclinada avança, em z, além do seu centro.
	local cardReach = cardSize.X / 2 * math.sin(yaw) + cardSize.Y / 2 * math.sin(tilt) * math.cos(yaw) + 0.125
	local cardFromPadCentre = layout.PadSize / 2 - stations.CardEdgeGap - cardReach
	for index, cut in cuts do
		-- Grid at the foot of the gate: cheapest at the front-left.
		local column = (index - 1) % columns
		local row = math.floor((index - 1) / columns)
		local offsetX = (column - (columns - 1) / 2) * layout.Spacing.X
		local side = if rows == 1 then -1 elseif row < (rows - 1) / 2 then -1 else 1
		local offsetZ = side * rowDistance
		local pad = makePart(model, {
			Name = "CutPad_" .. cut.Id,
			Size = Vector3.new(layout.PadSize, 1, layout.PadSize),
			CFrame = CFrame.new(origin + area.Offset + Vector3.new(offsetX, 0.5, offsetZ)),
			Color = if cut.Price == 0 then palette.Pad else steel,
			Material = Enum.Material.Metal,
			CanCollide = false,
		})
		pad:SetAttribute("CutPad", true)
		pad:SetAttribute("CutId", cut.Id)
		-- Inserto de energia fino no meio do pad (um lado do "fio da lâmina").
		local inset = block(model, CFrame.new(pad.CFrame.Position + Vector3.new(0, 0.55, 0)), Vector3.new(layout.PadSize - 4, 0.12, 1.2), LobbyConfig.Gate.Energy, Enum.Material.Neon, false)
		inset.Transparency = 0.2

		local top = pad.CFrame.Position + Vector3.new(0, 0.5, 0)
		-- Para que lado fica a avenida (o eixo do adro) e para onde a estação olha.
		local inward = if offsetZ > 0 then -1 elseif offsetZ < 0 then 1 else -1
		local facing = Vector3.new(-math.sin(yaw), 0, inward * math.cos(yaw))

		-- Pedestal (sem colisão: o pad fica no caminho da avenida).
		local pedestal = block(model, CFrame.new(top + Vector3.new(0, layout.PedestalHeight / 2, 0)), Vector3.new(2.4, layout.PedestalHeight, 2.4), slate, Enum.Material.Slate, false)
		pedestal.Name = "CutPedestal_" .. cut.Id
		block(model, CFrame.new(top + Vector3.new(0, layout.PedestalHeight + 0.15, 0)), Vector3.new(3.2, 0.3, 3.2), steel, Enum.Material.Metal, false)

		local anchorPosition = top + Vector3.new(0, layout.OrbHeight, 0)
		local anchor = makePart(model, {
			Name = "CutShowcase_" .. cut.Id,
			Size = Vector3.new(1, 1, 1),
			CFrame = CFrame.lookAt(anchorPosition, anchorPosition + facing),
			Color = cut.Color,
			CanCollide = false,
			Transparency = 1,
			CastShadow = false,
		})
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor:SetAttribute("CutShowcase", true)
		anchor:SetAttribute("CutId", cut.Id)

		-- Placa-balcão na borda do pad que dá para a avenida.
		local cardCentre = top + Vector3.new(0, 0.5 + cardSize.Y / 2 * math.cos(tilt), inward * cardFromPadCentre)
		local card = makePart(model, {
			Name = "CutCard_" .. cut.Id,
			Size = Vector3.new(cardSize.X, cardSize.Y, 0.25),
			CFrame = CFrame.lookAt(cardCentre, cardCentre + facing) * CFrame.Angles(tilt, 0, 0),
			Color = Color3.fromRGB(30, 32, 46),
			CanCollide = false,
			CastShadow = false,
		})
		card.CanQuery = false
		card.CanTouch = false
		card:SetAttribute("CutCard", true)
		card:SetAttribute("CutId", cut.Id)
		block(model, CFrame.lookAt(cardCentre, cardCentre + facing) - Vector3.new(0, cardCentre.Y - top.Y - 0.25, 0), Vector3.new(cardSize.X * 0.6, 0.5, 0.6), slate, Enum.Material.Slate, false)

		if cut.Price > 0 then
			local proximity = Instance.new("ProximityPrompt")
			proximity.ActionText = Text.GetFor(nil, "cut.buy")
			proximity.ObjectText = Text.GetFor(nil, "cut." .. cut.Id .. ".name")
			proximity.HoldDuration = 0
			proximity.MaxActivationDistance = 12
			proximity.RequiresLineOfSight = false
			proximity.KeyboardKeyCode = Enum.KeyCode.E
			proximity.GamepadKeyCode = Enum.KeyCode.ButtonY
			proximity:SetAttribute("CutId", cut.Id)
			proximity:SetAttribute("TextKey", "cut.buy")
			proximity:SetAttribute("ObjectKey", "cut." .. cut.Id .. ".name")
			proximity.Parent = pad
		end
	end

	-- Forja de Cortes: o marco da galeria (sem prompt; os pads continuam sendo
	-- a compra). O trilho no chão passa pelas bordas de fora da fileira norte.
	local forge = LobbyConfig.CutForge
	if forge then
		local at = origin + forge.Position
		local frame = CFrame.lookAt(at, at + forge.Facing)
		local xs = {}
		for column = 0, columns - 1 do
			local worldX = area.Offset.X + (column - (columns - 1) / 2) * layout.Spacing.X
			table.insert(xs, frame:PointToObjectSpace(origin + Vector3.new(worldX, 0, 0)).X)
		end
		local railWorldZ = -(rowDistance + layout.PadSize / 2 + 1.3)
		local railZ = frame:PointToObjectSpace(origin + Vector3.new(area.Offset.X, 0, railWorldZ)).Z
		StationMachines.BuildCutForge(model, frame, {
			Title = string.format("⚔️ %s", StationMachines.Upper(Text.GetFor(nil, "station.cuts.name"))),
			Subtitle = Text.GetFor(nil, "station.cuts.subtitle"),
		}, xs, railZ)
	end
end

--[[
	ÁREAS DO LOBBY. Antes cada área era um disco saturado (amarelo, rosa,
	ciano...) com anel neon e um poste com placa enorme: o lobby parecia um
	monte de plataformas independentes. Agora:
	- o piso é da mesma pedra clara da praça, com um friso fino na cor da área
	  (Floor = "Stone"), piso de academia (Mat) ou o adro escuro do portão;
	- a identidade vem de um ESTANDARTE pequeno (mastro + flâmula na cor da
	  área + cristal), virado para a praça, com ícone e nome curtos e que só
	  aparecem a uma distância razoável;
	- áreas cuja arquitetura já diz o que são (Treino, Loja) mostram só o
	  ícone (Label = "Icon").
]]
--[[
	Piso retangular de cantos arredondados (6 peças): uma cruz de dois blocos
	e quatro discos nos cantos. Alinhado aos eixos do mundo, como a praça.
]]
local function roundedRect(model: Model, centre: Vector3, size: Vector2, corner: number, height: number, color: Color3, material: Enum.Material)
	local w, d = size.X, size.Y
	block(model, CFrame.new(centre - Vector3.new(0, height / 2, 0)), Vector3.new(w - corner * 2, height, d), color, material)
	block(model, CFrame.new(centre - Vector3.new(0, height / 2, 0)), Vector3.new(w, height, d - corner * 2), color, material)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			disc(model, centre + Vector3.new(sx * (w / 2 - corner), 0, sz * (d / 2 - corner)), corner, height, color, material)
		end
	end
end

--[[
	Áreas cuja ESTAÇÃO física já diz o nome (placa na arquitetura): o
	estandarte com cristal e luz vira repetição e sai. Desligar a estação no
	LobbyConfig traz o estandarte de volta.
]]
local function bannerReplaced(areaId: string): boolean
	if areaId == "Training" then
		return true
	elseif areaId == "Eggs" then
		return LobbyConfig.IncubationArea == true
	elseif areaId == "Rebirth" then
		return LobbyConfig.RebirthStation == "Altar"
	elseif areaId == "Pets" then
		for _, station in LobbyConfig.Stations do
			if station.Area == "Pets" and station.Style == "PetLab" then
				return true
			end
		end
	end
	return false
end

local function buildAreas(model: Model, origin: Vector3, palette: Palette)
	for _, area in LobbyConfig.Areas do
		local centre = origin + area.Offset
		local size = area.FloorSize or Vector2.new(area.Radius * 1.6, area.Radius * 1.2)
		if area.Floor == "Square" then
			-- Praça retangular de pedra clara com friso fino na cor da área.
			-- Topo em 0,34 (o adro do portão fica em 0,4): onde se encostam, o
			-- adro fica por cima, sem cintilação de faces na mesma altura.
			roundedRect(model, centre + Vector3.new(0, 0.26, 0), size + Vector2.new(2, 2), 5, 0.5, area.Color:Lerp(Color3.fromRGB(120, 116, 110), 0.55), Enum.Material.SmoothPlastic)
			roundedRect(model, centre + Vector3.new(0, 0.34, 0), size, 4, 0.5, palette.Pad:Lerp(area.Color, 0.06), Enum.Material.Slate)
		elseif area.Floor == "Adventure" then
			-- Central do Aventureiro: pedra quente com friso dourado; o centro
			-- (medalhão, caminhos e placa de direção) é do StationMachines.
			roundedRect(model, centre + Vector3.new(0, 0.26, 0), size + Vector2.new(2, 2), 5, 0.5, Color3.fromRGB(176, 140, 76), Enum.Material.SmoothPlastic)
			roundedRect(model, centre + Vector3.new(0, 0.34, 0), size, 4, 0.5, Color3.fromRGB(176, 168, 152), Enum.Material.Slate)
			local plazaStations = {}
			for _, station in LobbyConfig.Stations do
				if station.Area == area.Id then
					table.insert(plazaStations, {
						Local = station.Local,
						Color = station.Color,
						Label = string.format("%s %s", station.Icon, StationMachines.Upper(Text.GetFor(nil, station.NameKey))),
						Flow = if station.Style == "RewardTotem" then "In" else "Out",
					})
				end
			end
			local front = CFrame.lookAt(centre, Vector3.new(origin.X, centre.Y, origin.Z))
			StationMachines.DecorateAdventurePlaza(model, front, plazaStations, size.Y)
		elseif area.Floor == "Deck" then
			-- Deck de madeira um degrau acima da grama.
			roundedRect(model, centre + Vector3.new(0, 0.6, 0), size, 3, 1, Color3.fromRGB(176, 136, 94), Enum.Material.WoodPlanks)
		elseif area.Floor == "MatSquare" then
			roundedRect(model, centre + Vector3.new(0, 0.26, 0), size + Vector2.new(2, 2), 5, 0.5, area.Color:Lerp(Color3.fromRGB(60, 60, 60), 0.5), Enum.Material.SmoothPlastic)
			roundedRect(model, centre + Vector3.new(0, 0.34, 0), size, 4, 0.5, Color3.fromRGB(58, 62, 74), Enum.Material.Rubber)
		elseif area.Floor == "Stone" then
			disc(model, centre + Vector3.new(0, 0.25, 0), area.Radius, 0.5, area.Color:Lerp(Color3.fromRGB(120, 116, 110), 0.55), Enum.Material.SmoothPlastic)
			disc(model, centre + Vector3.new(0, 0.35, 0), area.Radius - 1.6, 0.5, palette.Pad:Lerp(area.Color, 0.08), Enum.Material.Slate)
		elseif area.Floor == "Mat" then
			disc(model, centre + Vector3.new(0, 0.25, 0), area.Radius, 0.5, area.Color:Lerp(Color3.fromRGB(60, 60, 60), 0.5), Enum.Material.SmoothPlastic)
			disc(model, centre + Vector3.new(0, 0.35, 0), area.Radius - 1.6, 0.5, Color3.fromRGB(58, 62, 74), Enum.Material.Rubber)
		elseif area.Floor == "Forecourt" then
			-- Adro retangular até a boca do corredor, onde ficam os pads de corte.
			local fromX = area.Offset.X - area.Radius
			local toX = WallConfig.Layout.StartX
			local depth = area.Radius * 2
			block(model, CFrame.new(origin + Vector3.new((fromX + toX) / 2, 0.2, area.Offset.Z)), Vector3.new(toX - fromX, 0.4, depth), Color3.fromRGB(78, 82, 98), Enum.Material.Slate)
			for _, side in { -1, 1 } do
				block(model, CFrame.new(origin + Vector3.new((fromX + toX) / 2, 0.3, area.Offset.Z + side * (depth / 2 - 1))), Vector3.new(toX - fromX, 0.4, 1.2), shade(LobbyConfig.Gate.Trim, 0.85), Enum.Material.SmoothPlastic)
			end
		end

		if area.Label ~= "None" and not bannerReplaced(area.Id) then
			-- Estandarte no lado de FORA da área (de quem olha da praça).
			local outward = if area.Offset.Magnitude > 1 then Vector3.new(area.Offset.X, 0, area.Offset.Z).Unit else Vector3.new(0, 0, 1)
			local base = centre + outward * (area.Radius - 5)
			local poleHeight = math.min(area.SignHeight, 16)
			block(model, CFrame.new(base + Vector3.new(0, poleHeight / 2, 0)), Vector3.new(1, poleHeight, 1), palette.Rim, Enum.Material.Wood, false)
			local facing = CFrame.lookAt(base, base - outward)
			local flag = block(model, facing + Vector3.new(0, poleHeight - 3.6, 0) + facing.RightVector * 2.4, Vector3.new(4, 6, 0.3), area.Color, Enum.Material.Fabric, false)
			flag.Name = "AreaSign_" .. area.Id
			local crystal = block(model, CFrame.new(base + Vector3.new(0, poleHeight + 1.4, 0)) * CFrame.Angles(math.rad(45), math.rad(45), 0), Vector3.new(1.6, 1.6, 1.6), area.Color, Enum.Material.Neon, false)
			light(crystal, area.Color, 12, 0.8)
			local text = if area.Label == "Name" then string.format("%s %s", area.Icon, Text.GetFor(nil, area.NameKey)) else area.Icon
			billboard(flag, text, Color3.new(1, 1, 1), 5.5, 90, if area.Label == "Name" then 0.75 else 0.5)
		end
	end
end

--[[
	Calçadas de pedra da praça até cada área: é o que costura o lobby num
	lugar só, em vez de ilhas de cor soltas na grama. Uma peça por calçada.
]]
local function buildWalkways(model: Model, origin: Vector3, palette: Palette)
	for _, area in LobbyConfig.Areas do
		if area.Id ~= "Tower" then
			local target = Vector3.new(area.Offset.X, 0, area.Offset.Z)
			local direction = if target.Magnitude > 1 then target.Unit else Vector3.new(0, 0, 1)
			-- Da borda da praça (quadrado de ±PLAZA_HALF) até a borda da área.
			local fromDistance = PLAZA_HALF / math.max(math.abs(direction.X), math.abs(direction.Z))
			local toDistance = target.Magnitude - area.Radius + 2
			if toDistance > fromDistance + 1 then
				local a = origin + direction * fromDistance
				local b = origin + direction * toDistance
				local middle = (a + b) / 2 + Vector3.new(0, 0.2, 0)
				-- Caminho secundário: mais estreito e mais escuro que a avenida do
				-- Caminho do Poder (24 de largura, pedra clara), para não competir.
				local walk = block(model, CFrame.lookAt(middle, middle + direction), Vector3.new(WALKWAY_WIDTH, 0.3, (b - a).Magnitude), shade(palette.Pad, 0.82), Enum.Material.Slate, false)
				walk.Name = "Walkway_" .. area.Id
			end
		end
	end
end

--[[
	O caminho de pedra da praça até o portão do Caminho do Poder: a única
	estrada do lobby, então "para onde eu vou" tem resposta visual. Uma faixa
	de energia no meio e pilares com cristal dos dois lados conduzem o olhar
	até o portão.
]]
local function buildTowerPath(model: Model, origin: Vector3, palette: Palette)
	local path = LobbyConfig.Path
	local gate = LobbyConfig.Gate
	local fromX = PLAZA_HALF
	local toX = WallConfig.Layout.StartX
	local tiles = math.max(math.floor((toX - fromX) / path.TileLength), 1)
	local tileLength = (toX - fromX) / tiles
	for index = 0, tiles - 1 do
		local x = fromX + (index + 0.5) * tileLength
		block(
			model,
			CFrame.new(origin + Vector3.new(x, 0.25, 0)),
			Vector3.new(tileLength - 1, 0.5, path.Width),
			if index % 2 == 0 then palette.Pad else shade(palette.Pad, 0.92),
			Enum.Material.Cobblestone,
			false
		)
	end
	-- Faixa de energia no eixo do caminho.
	local runner = block(model, CFrame.new(origin + Vector3.new((fromX + toX) / 2, 0.55, 0)), Vector3.new(toX - fromX, 0.15, 1.4), gate.Energy, Enum.Material.Neon, false)
	runner.Name = "PathRunner"
	runner.Transparency = 0.25
	for _, x in path.Pylons do
		for _, side in { -1, 1 } do
			local base = origin + Vector3.new(x, 0, side * path.PylonOffsetZ)
			block(model, CFrame.new(base + Vector3.new(0, 2.5, 0)), Vector3.new(2.4, 5, 2.4), gate.Stone, Enum.Material.Slate)
			local crystal = block(model, CFrame.new(base + Vector3.new(0, 7, 0)) * CFrame.Angles(0, math.rad(45), math.rad(12 * side)), Vector3.new(1.4, 4, 1.4), gate.Energy, Enum.Material.Neon, false)
			crystal.Name = "PathCrystal"
		end
	end
end

--[[
	PORTÃO DO CAMINHO DO PODER — o marco do lobby (LobbyConfig.Gate).

	Na boca do corredor, de frente para a praça:
		- dois pilares de pedra sobre plintos, com friso dourado e cristais de
		  energia na base — eles também FECHAM o vão entre a parede do corredor
		  e o paredão da ilha (por isso vão até a face do paredão);
		- uma verga larga com a placa CAMINHO DO PODER (SurfaceGui, presa à
		  pedra, e não um texto flutuante);
		- uma espada gigante de energia cravada no alto da verga, visível de
		  qualquer ponto do lobby.
	A abertura entre os pilares deixa ver a primeira área e a barreira 1 lá
	dentro. Não é torre nem teleporte: é a entrada do corredor reto.
]]
local function buildPathGate(model: Model, origin: Vector3)
	local gate = LobbyConfig.Gate
	local layout = WallConfig.Layout
	local x = layout.StartX
	local halfOpening = layout.Width / 2 + 2 -- pilares começam logo fora do piso do corredor
	local pillarZ = halfOpening + gate.PillarWidth / 2
	local top = gate.PlinthHeight + gate.PillarHeight

	for _, side in { -1, 1 } do
		local z = side * pillarZ
		block(model, CFrame.new(origin + Vector3.new(x, gate.PlinthHeight / 2, z)), Vector3.new(gate.PillarWidth + 8, gate.PlinthHeight, gate.PillarWidth + 8), shade(gate.Stone, 0.8), Enum.Material.Slate)
		local pillar = block(model, CFrame.new(origin + Vector3.new(x, gate.PlinthHeight + gate.PillarHeight / 2, z)), Vector3.new(gate.PillarWidth, gate.PillarHeight, gate.PillarWidth), gate.Stone, Enum.Material.Slate)
		pillar.Name = "GatePillar"
		-- Friso dourado no alto do pilar.
		block(model, CFrame.new(origin + Vector3.new(x, top - 3, z)), Vector3.new(gate.PillarWidth + 1.2, 2, gate.PillarWidth + 1.2), gate.Trim, Enum.Material.Metal)
		-- Veio de energia na face do pilar que dá para a praça.
		local vein = block(model, CFrame.new(origin + Vector3.new(x - gate.PillarWidth / 2 - 0.2, gate.PlinthHeight + gate.PillarHeight * 0.45, z)), Vector3.new(0.4, gate.PillarHeight * 0.7, 2.2), gate.Energy, Enum.Material.Neon, false)
		vein.Name = "GateVein"
		-- Cristais na base, do lado da praça.
		for index, height in { 9, 14, 6 } do
			local crystal = block(
				model,
				CFrame.new(origin + Vector3.new(x - gate.PillarWidth / 2 - 5 - index * 1.5, height / 2 + 0.5, z - side * (index - 2) * 4))
					* CFrame.Angles(math.rad(-10 * side), math.rad(30 * index), math.rad(14 * side)),
				Vector3.new(2.6, height, 2.6),
				gate.Energy,
				Enum.Material.Neon,
				false
			)
			crystal.Name = "GateCrystal"
			crystal.Transparency = 0.1
		end
		local lamp = block(model, CFrame.new(origin + Vector3.new(x - gate.PillarWidth / 2 - 6, 4, z)), Vector3.new(1, 1, 1), gate.Energy, Enum.Material.Neon, false)
		lamp.Transparency = 1
		light(lamp, gate.Energy, 30, 1.6)
	end

	-- Verga: atravessa os dois pilares de ponta a ponta.
	local spanZ = (pillarZ + gate.PillarWidth / 2) * 2 + 6
	local lintelY = top + gate.LintelHeight / 2
	block(model, CFrame.new(origin + Vector3.new(x, lintelY, 0)), Vector3.new(gate.LintelDepth, gate.LintelHeight, spanZ), gate.Stone, Enum.Material.Slate)
	block(model, CFrame.new(origin + Vector3.new(x, top + 0.6, 0)), Vector3.new(gate.LintelDepth + 1, 1.2, spanZ + 1), gate.Trim, Enum.Material.Metal)
	-- Coroa escalonada no meio, onde a espada fica cravada.
	local crownTop = top + gate.LintelHeight + 6
	block(model, CFrame.new(origin + Vector3.new(x, top + gate.LintelHeight + 3, 0)), Vector3.new(gate.LintelDepth - 6, 6, spanZ * 0.45), shade(gate.Stone, 0.9), Enum.Material.Slate)

	-- Placa presa na face da verga que olha para a praça: quase a verga
	-- inteira, fundo escuro e letras douradas grossas, sem emoji (emoji num
	-- TextScaled encolhe o texto todo).
	local plateWidth = spanZ * 0.82
	local plateHeight = gate.LintelHeight - 2.4
	local plate = block(
		model,
		CFrame.lookAt(origin + Vector3.new(x - gate.LintelDepth / 2 - 0.3, lintelY, 0), origin + Vector3.new(x - gate.LintelDepth, lintelY, 0)),
		Vector3.new(plateWidth, plateHeight, 0.6),
		Color3.fromRGB(16, 18, 32),
		Enum.Material.SmoothPlastic
	)
	plate.Name = "GateSign"
	-- Moldura dourada fina em volta da placa.
	for _, edge in { -1, 1 } do
		block(model, CFrame.new(origin + Vector3.new(x - gate.LintelDepth / 2 - 0.35, lintelY + edge * (plateHeight / 2 + 0.4), 0)), Vector3.new(0.7, 0.8, plateWidth + 1.6), gate.Trim, Enum.Material.Metal, false)
		-- Friso de energia fino por fora da moldura: dá presença à placa sem
		-- acender a praça (é a cor de identidade do Caminho).
		local strip = block(model, CFrame.new(origin + Vector3.new(x - gate.LintelDepth / 2 - 0.4, lintelY + edge * (plateHeight / 2 + 1.05), 0)), Vector3.new(0.5, 0.35, plateWidth * 0.9), gate.Energy, Enum.Material.Neon, false)
		strip.Name = "GateSignGlow"
	end
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Front
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 30
	surface.LightInfluence = 0
	surface.MaxDistance = 1000
	local signLabel = Instance.new("TextLabel")
	signLabel.Size = UDim2.fromScale(0.97, 0.9)
	signLabel.Position = UDim2.fromScale(0.015, 0.05)
	signLabel.BackgroundTransparency = 1
	signLabel.Font = Enum.Font.GothamBlack
	signLabel.TextScaled = true
	signLabel.TextColor3 = Color3.fromRGB(255, 214, 110)
	signLabel.TextStrokeTransparency = 1
	-- Contorno grosso (legível de longe e sobre o céu claro) e dourado em
	-- degradê, em vez do contorno fino de antes.
	local signStroke = Instance.new("UIStroke")
	signStroke.Thickness = 4
	signStroke.Color = Color3.fromRGB(46, 24, 0)
	signStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	signStroke.Parent = signLabel
	local signGradient = Instance.new("UIGradient")
	signGradient.Rotation = 90
	signGradient.Color = ColorSequence.new(Color3.fromRGB(255, 236, 160), Color3.fromRGB(255, 186, 60))
	signGradient.Parent = signLabel
	signLabel.Text = StationMachines.Upper(Text.GetFor(nil, "area.tower"))
	signLabel.Parent = surface
	surface.Parent = plate

	--[[
		A ESPADA, de pé sobre a coroa, ponta para cima — a silhueta de espada
		que qualquer um reconhece: pomo, empunhadura, guarda larga, lâmina de
		aço claro com ponta e um fio de energia nas duas bordas. Antes era uma
		barra neon com a ponta enterrada na coroa, que de longe lia como um
		tubo de luz.
	]]
	local steel = Color3.fromRGB(214, 224, 236)
	local thickness = 1.2
	local bladeWidth = 6
	local tipHeight = 6
	local gripHeight = 6
	local guardHeight = 2.4
	local bladeHeight = gate.SwordHeight - gripHeight - guardHeight - tipHeight - 2
	local baseY = crownTop
	ball(model, origin + Vector3.new(x, baseY + 1.6, 0), 3.6, gate.Trim, Enum.Material.Metal, false)
	block(model, CFrame.new(origin + Vector3.new(x, baseY + 2 + gripHeight / 2, 0)), Vector3.new(1.8, gripHeight, 1.8), Color3.fromRGB(70, 46, 34), Enum.Material.Wood, false)
	local guardY = baseY + 2 + gripHeight + guardHeight / 2
	block(model, CFrame.new(origin + Vector3.new(x, guardY, 0)), Vector3.new(3, guardHeight, 20), gate.Trim, Enum.Material.Metal, false)
	for _, side in { -1, 1 } do
		-- Pontas da guarda levemente viradas para cima.
		block(model, CFrame.new(origin + Vector3.new(x, guardY + 1.2, side * 10.4)) * CFrame.Angles(math.rad(-25 * side), 0, 0), Vector3.new(3, 3.2, 1.6), gate.Trim, Enum.Material.Metal, false)
	end
	local bladeBottom = guardY + guardHeight / 2
	local bladeCentre = origin + Vector3.new(x, bladeBottom + bladeHeight / 2, 0)
	local blade = block(model, CFrame.new(bladeCentre), Vector3.new(thickness, bladeHeight, bladeWidth), steel, Enum.Material.Metal, false)
	blade.Name = "GateSword"
	-- Sulco central (fuller) e fio de energia nas bordas.
	block(model, CFrame.new(bladeCentre + Vector3.new(-thickness / 2 - 0.05, -1, 0)), Vector3.new(0.2, bladeHeight - 4, 1), Color3.fromRGB(150, 165, 185), Enum.Material.Metal, false)
	for _, side in { -1, 1 } do
		local edge = block(model, CFrame.new(bladeCentre + Vector3.new(0, 0, side * (bladeWidth / 2 + 0.25))), Vector3.new(thickness + 0.3, bladeHeight, 0.5), gate.Energy, Enum.Material.Neon, false)
		edge.Name = "GateSwordEdge"
	end
	-- Ponta: duas cunhas formando o triângulo.
	local tipY = bladeBottom + bladeHeight + tipHeight / 2
	for _, side in { -1, 1 } do
		local tip = Instance.new("WedgePart")
		tip.Name = "GateSwordTip"
		tip.Anchored = true
		tip.CanCollide = false
		tip.Size = Vector3.new(thickness, tipHeight, bladeWidth / 2)
		-- A face vertical da cunha (local +Z) fica no meio da lâmina.
		tip.CFrame = CFrame.new(origin + Vector3.new(x, tipY, side * bladeWidth / 4)) * CFrame.Angles(0, if side > 0 then math.pi else 0, 0)
		tip.Color = steel
		tip.Material = Enum.Material.Metal
		tip.TopSurface = Enum.SurfaceType.Smooth
		tip.BottomSurface = Enum.SurfaceType.Smooth
		tip.Parent = model
	end
	light(blade, gate.Energy, 40, 1.6)
end

-- ── Win corridor ────────────────────────────────────────────────────────────

--[[
	APARÊNCIA DE OBSTÁCULO QUEBRÁVEL. Cada fileira era um bloco liso de uma cor
	— a barreira 1, vista da entrada, parecia só uma parede marrom. Agora a
	face da fileira que dá para o jogador (-X) ganha detalhes do tema:
		Planks — tábuas com frestas, travessas em X e cintas de ferro (madeira)
		Bricks — juntas de alvenaria desencontradas (pedra, ruínas, vulcânica)
		Cracks — moldura e rachaduras em raio (gelo, cristal, magma)
		Plates — placas rebitadas com emendas (ouro, energia, colosso)
	Os detalhes são FILHOS da fileira, sem colisão, sem consulta e sem toque:
	não mudam HP, alcance, colisão nem lógica. O WallService esconde e mostra
	os filhos junto com a fileira (atributo WallDetail).
]]
local BARRIER_PATTERNS: { [string]: string } = {
	Wood = "Planks",
	Ruins = "Bricks",
	Ice = "Cracks",
	Crystal = "Cracks",
	Gold = "Plates",
	Ancient = "Bricks",
	Volcanic = "Bricks",
	Magma = "Cracks",
	Tech = "Plates",
	Colossus = "Plates",
}

local function barrierDetails(row: BasePart, stage: any, thickness: number)
	local pattern = BARRIER_PATTERNS[stage.Id] or "Bricks"
	local size = row.Size
	local height, width = size.Y, size.Z
	-- Plano da face da frente, um pouco para fora dela.
	local faceX = -thickness / 2 - 0.15
	local dark = shade(stage.Color, 0.55)
	local light = shade(stage.Color, 1.18)
	local glow = stage.Accent
	local function piece(localFrame: CFrame, pieceSize: Vector3, color: Color3, material: Enum.Material?)
		local part = makePart(row, {
			Name = "WallDetail",
			Size = pieceSize,
			CFrame = row.CFrame * localFrame,
			Color = color,
			Material = material or row.Material,
			CanCollide = false,
			CastShadow = false,
		})
		part.CanQuery = false
		part.CanTouch = false
		part:SetAttribute("WallDetail", true)
		part:SetAttribute("BaseTransparency", 0)
		return part
	end
	local function strip(y: number, z: number, length: number, angle: number, thick: number, color: Color3, material: Enum.Material?)
		piece(CFrame.new(faceX, y, z) * CFrame.Angles(angle, 0, 0), Vector3.new(0.4, thick, length), color, material)
	end
	if pattern == "Planks" then
		for index = 1, 4 do
			strip(-height / 2 + index * height / 5, 0, width - 1, 0, 0.5, dark)
		end
		local diagonal = math.atan2(height - 6, width - 6)
		strip(0, 0, math.sqrt((height - 6) ^ 2 + (width - 6) ^ 2), diagonal, 2.2, light)
		strip(0, 0, math.sqrt((height - 6) ^ 2 + (width - 6) ^ 2), -diagonal, 2.2, light)
		for _, y in { -height / 2 + 2.5, height / 2 - 2.5 } do
			strip(y, 0, width - 0.5, 0, 1.6, Color3.fromRGB(70, 70, 78), Enum.Material.Metal)
		end
	elseif pattern == "Bricks" then
		local courses = 4
		local courseHeight = height / courses
		for index = 1, courses - 1 do
			strip(-height / 2 + index * courseHeight, 0, width - 0.5, 0, 0.6, dark)
		end
		for course = 1, courses do
			local y = -height / 2 + (course - 0.5) * courseHeight
			local joints = if course % 2 == 1 then { -width / 4, width / 4 } else { 0 }
			for _, z in joints do
				piece(CFrame.new(faceX, y, z), Vector3.new(0.4, courseHeight - 0.6, 0.6), dark)
			end
		end
		if stage.Neon or stage.Id == "Volcanic" then
			-- Fissura incandescente atravessando os blocos.
			strip(height * 0.05, width * 0.08, height * 0.7, math.rad(62), 0.6, glow, Enum.Material.Neon)
		end
	elseif pattern == "Cracks" then
		for _, y in { -height / 2 + 1, height / 2 - 1 } do
			strip(y, 0, width - 0.5, 0, 1.2, dark)
		end
		-- Rachadura em raio a partir de um ponto de impacto.
		local centre = Vector3.new(0, height * 0.08, -width * 0.06)
		for index, angle in { 20, 75, 140, 205, 290 } do
			local radians = math.rad(angle)
			local length = height * (0.28 + 0.06 * (index % 3))
			local offset = Vector3.new(0, math.sin(radians) * length / 2, math.cos(radians) * length / 2)
			-- Rachadura grossa e clara (gelo) ou incandescente (cristal, magma):
			-- fina e escura, de longe ela some.
			piece(CFrame.new(faceX, centre.Y + offset.Y, centre.Z + offset.Z) * CFrame.Angles(-radians, 0, 0), Vector3.new(0.4, 1.1, length), if stage.Neon then glow else light:Lerp(Color3.new(1, 1, 1), 0.6), if stage.Neon then Enum.Material.Neon else Enum.Material.SmoothPlastic)
		end
	else -- Plates
		strip(0, 0, width - 0.5, 0, 0.7, dark, Enum.Material.Metal)
		piece(CFrame.new(faceX, 0, 0), Vector3.new(0.4, height - 1, 0.7), dark, Enum.Material.Metal)
		for _, y in { -height / 2 + 1, height / 2 - 1 } do
			strip(y, 0, width - 0.5, 0, 1.2, light, Enum.Material.Metal)
		end
		for _, corner in { Vector2.new(-1, -1), Vector2.new(-1, 1), Vector2.new(1, -1), Vector2.new(1, 1) } do
			local rivet = piece(CFrame.new(faceX - 0.2, corner.Y * height / 4, corner.X * width / 4), Vector3.new(1.4, 1.4, 1.4), if stage.Neon then glow else light, if stage.Neon then Enum.Material.Neon else Enum.Material.Metal)
			rivet.Shape = Enum.PartType.Ball
		end
	end
end

--[[
	O CORREDOR: dez áreas temáticas em linha reta a leste da praça, todas no
	mesmo nível do chão. Cada área termina na sua barreira; passando dela vêm os
	pads de vitória e, logo em seguida, a área do tema seguinte.

	Três coisas fazem o corredor não ser "parede, chão vazio, parede":
	1. o piso e as paredes fazem TRANSIÇÃO gradual para o tema seguinte ao longo
	   da área, em vez de trocar de cor de uma vez;
	2. um arco emoldura cada barreira, marcando o checkpoint;
	3. postes acesos na cor do PRÓXIMO tema deixam o jogador ver de longe que há
	   algo diferente adiante.

	WallService encontra tudo por atributo (nada disto mudou com o layout):
		Wall = true, StageId, Row, Rows               (uma fileira da barreira)
		WinPad = true, StageId, Wins = <quantidade>   (pad que paga vitórias)
		WinPad = true, StageId, Return = true         (pad que volta pra praça)
]]
local function buildCorridor(world: Model, origin: Vector3, palette: Palette)
	local layout = WallConfig.Layout
	local stages = WallConfig.Stages
	--[[
		Fase A (fundação): tudo do corredor fica num Model "PowerPath"; piso,
		paredes, silhueta, transições e zona de decisão vêm do PowerPath
		(CorridorThemes + CorridorLayout). Aqui ficam só o que tem função:
		fileiras, arcos (checkpoint), pads e o fim com o portal. WallService e
		WallController acham fileiras e pads por atributo, onde estiverem.
	]]
	local model = Instance.new("Model")
	model.Name = "PowerPath"
	model.Parent = world
	local _ = palette

	for index, segment in CorridorLayout.Segments() do
		local stage = stages[index]
		local isFinal = segment.Final
		local width = segment.Width
		local half = width / 2
		local height = segment.Height
		local areaEnd = segment.Barrier
		local blockDepth = segment.Depth

		-- Piso, paredes, silhueta e transição deste trecho (PowerPath). Os
		-- postes com PointLight e as faixas de cor saíram: o ritmo agora é
		-- dado por paredes em alturas diferentes, pilares e a faixa central.
		PowerPath.BuildStage(model, origin, segment)

		--[[
			A barreira fecha o fim da área: várias fileiras do mesmo material,
			uma atrás da outra. Cada fileira tem HP próprio e cai sozinha —
			WallService é dono disso, e nada aqui mudou com o corredor.
		]]
		for row = 1, stage.Rows do
			local rowX = areaEnd + (row - 0.5) * layout.RowThickness + (row - 1) * layout.RowGap
			local part = makePart(model, {
				Name = string.format("Wall_%s_%d", stage.Id, row),
				Size = Vector3.new(layout.RowThickness, height, width),
				CFrame = CFrame.new(origin + Vector3.new(rowX, height / 2, 0)),
				-- Fileiras mais escuras atrás, para a profundidade se ler.
				Color = shade(stage.Color, 1 - (row - 1) * 0.05),
				Material = stage.Material,
			})
			part:SetAttribute("Wall", true)
			part:SetAttribute("StageId", stage.Id)
			part:SetAttribute("Row", row)
			part:SetAttribute("MaxHp", stage.Hp)
			part:SetAttribute("Hp", stage.Hp)
			part:SetAttribute("Rows", stage.Rows)
			-- (Sem PointLight por fileira: o material Neon dos estágios de
			-- energia já brilha; eram 29 luzes só nas barreiras.)
			barrierDetails(part, stage, layout.RowThickness)
		end

		-- Arco emoldurando a barreira: o portão que marca o checkpoint. No
		-- Colosso o arco fica no marfim do tema (o Accent rosa continua nos
		-- pads; uma laje rosa por cima do Portão do Colosso brigava com ele).
		local archX = areaEnd + blockDepth / 2
		local archColor = if isFinal then CorridorThemes.For(stage.Id).Trim.Color :: Color3 else stage.Accent
		for _, side in { -1, 1 } do
			block(
				model,
				CFrame.new(origin + Vector3.new(archX, (height + layout.ArchExtra) / 2, side * (half + layout.ArchThickness / 2))),
				Vector3.new(blockDepth + 6, height + layout.ArchExtra, layout.ArchThickness),
				shade(archColor, 0.8),
				Enum.Material.Marble,
				false
			)
		end
		local lintel = block(
			model,
			CFrame.new(origin + Vector3.new(archX, height + layout.ArchExtra, 0)),
			Vector3.new(blockDepth + 6, layout.ArchThickness, width + layout.ArchThickness * 2),
			shade(archColor, 0.9),
			Enum.Material.Marble,
			false
		)
		lintel.Name = "Arch_" .. stage.Id
		light(lintel, archColor, 30, 1.4)

		-- Pads de vitória logo depois da barreira, já na entrada da próxima área.
		local padX = segment.PadsX
		local count = #stage.Pads
		for padIndex, amount in stage.Pads do
			local offsetZ = (padIndex - (count + 1) / 2) * layout.PadSpacing
			local pad = makePart(model, {
				Name = "WinPad_" .. stage.Id .. "_" .. tostring(padIndex),
				Size = Vector3.new(layout.PadSize, 1, layout.PadSize),
				CFrame = CFrame.new(origin + Vector3.new(padX, 0.5, offsetZ)),
				Color = stage.Accent,
				Material = Enum.Material.Neon,
				CanCollide = false,
			})
			pad:SetAttribute("WinPad", true)
			pad:SetAttribute("StageId", stage.Id)
			pad:SetAttribute("Wins", amount)
			-- 1 = prêmio normal, 2 = "x2" (o dobro). A placa mostra o valor cheio;
			-- o cliente troca pelo que este jogador recebe (WinPadRules).
			pad:SetAttribute("PadIndex", padIndex)
			billboard(pad, Text.Get(if WinPadRules.IsDouble(stage, padIndex) then "wall.padWinsDouble" else "wall.padWins", { amount = NumberFormat.Short(amount) }), stage.Accent, 6)
		end

		-- Pad de voltar: ninguém fica preso no fundo do corredor.
		local returnPad = makePart(model, {
			Name = "ReturnPad_" .. stage.Id,
			Size = Vector3.new(layout.PadSize, 1, layout.PadSize),
			CFrame = CFrame.new(origin + Vector3.new(segment.ReturnX, 0.5, half - layout.PadSize)),
			Color = Color3.fromRGB(235, 80, 80),
			Material = Enum.Material.Neon,
			CanCollide = false,
		})
		returnPad:SetAttribute("WinPad", true)
		returnPad:SetAttribute("StageId", stage.Id)
		returnPad:SetAttribute("Return", true)
		billboard(returnPad, Text.Get("wall.padReturn"), Color3.fromRGB(235, 80, 80), 6)

		local cursor = segment.End

		--[[
			Fim da primeira jornada: depois da décima barreira, uma área aberta
			e o portal do próximo mundo — inerte e rotulado "em breve", porque um
			teleporte vazio que engole o jogador seria pior que portal nenhum.
		]]
		if isFinal then
			local plazaLength = CorridorLayout.FINAL_PLAZA
			-- Piso e paredes da praça final: mesma fundação, faixa central até
			-- o portal (PowerPath.BuildFinal).
			PowerPath.BuildFinal(model, origin)
			--[[
				CONTENÇÃO DO FIM. Antes a praça final terminava no vazio: dava
				para andar além do portal e cair. Agora o fundo é um MACIÇO do
				Colosso — blocos de rocha em alturas diferentes, mais altos que
				qualquer pulo, com cristais na cor do tema — e o portal fica
				encostado nele, como se tivesse sido escavado na montanha. É uma
				parede de verdade, não uma cerca, e não fica na frente do portal.
			]]
			-- Energia do portal do futuro: violeta profundo (ecoa o 9, menor que o Colosso).
			local portalColor = Color3.fromRGB(150, 110, 255)
			local backX = cursor + plazaLength
			local rockColor = shade(stage.Color, 0.32)
			-- {deslocamento Z (fração da largura), largura, altura, recuo}
			local massif = {
				{ -0.42, 0.30, 1.55, 6 },
				{ -0.17, 0.26, 1.95, 0 },
				{ 0.17, 0.26, 1.95, 0 },
				{ 0.42, 0.30, 1.45, 8 },
			}
			for _, piece in massif do
				local pieceWidth = (width + layout.SideThickness * 2) * piece[2]
				local pieceHeight = layout.SideHeight * piece[3]
				-- A face da frente fica sempre 1 stud SOBRE o piso: sem fresta.
				local depth = 16 + piece[4]
				block(
					model,
					CFrame.new(origin + Vector3.new(backX - 1 + depth / 2, pieceHeight / 2 - layout.FloorThickness, piece[1] * width)),
					Vector3.new(depth, pieceHeight + layout.FloorThickness, pieceWidth),
					rockColor,
					Enum.Material.Basalt
				)
			end
			-- Faixa central mais baixa: é a "boca" escavada onde o portal fica.
			block(
				model,
				CFrame.new(origin + Vector3.new(backX - 1 + 12, layout.SideHeight * 0.75 - layout.FloorThickness / 2, 0)),
				Vector3.new(24, layout.SideHeight * 1.5 + layout.FloorThickness, width * 0.36),
				shade(rockColor, 0.8),
				Enum.Material.Basalt
			)
			-- (Fase E: os cristais Neon dos cantos saíram — a moldura do portal e a
			-- área de conclusão agora são o cenário do PowerPath_Final.)

			-- O portal: disco virado para o jogador, com moldura de pedra.
			local portalX = backX - 4
			local portalCenter = origin + Vector3.new(portalX, 22, 0)
			local portal = makePart(model, {
				Name = "NextWorldPortal",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(1.5, 34, 34),
				CFrame = CFrame.new(portalCenter),
				Color = portalColor,
				-- Interior instável e BLOQUEADO (não é passagem): ForceField, não Neon.
				Material = Enum.Material.ForceField,
				CanCollide = false,
				Transparency = 0.15,
			})
			portal.CanTouch = false
			-- Moldura: oito pedras em anel (barato e lê como um portal).
			for segment = 0, 7 do
				local angle = segment * math.pi / 4
				block(
					model,
					-- Gira em X para o lado comprido ficar tangente ao anel.
					CFrame.new(portalCenter + Vector3.new(0.5, math.sin(angle) * 19, math.cos(angle) * 19))
						* CFrame.Angles(-angle - math.pi / 2, 0, 0),
					Vector3.new(4, 5, 15),
					Color3.fromRGB(52, 50, 60),
					Enum.Material.Slate,
					false
				)
			end
			light(portal, portalColor, 60, 3)
			-- "EM BREVE" e uma linha curta: existe mais, mas ainda não.
			billboard(portal, Text.GetFor(nil, "wall.portalSoon"), Color3.fromRGB(226, 210, 255), 31, 180, 1.2)
			billboard(portal, Text.GetFor(nil, "wall.portalContinues"), Color3.fromRGB(200, 180, 240), 26.5, 180, 0.75)
		end
	end
end

-- ── Themes ──────────────────────────────────────────────────────────────────

local function tree(model: Model, position: Vector3, rng: Random)
	local height = rng:NextNumber(10, 18)
	block(model, CFrame.new(position + Vector3.new(0, height / 2, 0)), Vector3.new(2.2, height, 2.2), Color3.fromRGB(110, 76, 48), Enum.Material.Wood)
	local leaves = Color3.fromRGB(rng:NextInteger(50, 80), rng:NextInteger(140, 175), rng:NextInteger(50, 70))
	ball(model, position + Vector3.new(0, height + 3, 0), rng:NextNumber(9, 13), leaves, Enum.Material.Grass)
	ball(model, position + Vector3.new(rng:NextNumber(-3, 3), height + 6, rng:NextNumber(-3, 3)), rng:NextNumber(6, 9), leaves, Enum.Material.Grass)
end

local function rock(model: Model, position: Vector3, rng: Random, color: Color3, scale: number)
	local size = Vector3.new(rng:NextNumber(3, 7), rng:NextNumber(2, 5), rng:NextNumber(3, 7)) * scale
	block(model, CFrame.new(position + Vector3.new(0, size.Y / 2 - 0.5, 0)) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, math.pi), rng:NextNumber(-0.3, 0.3)), size, color, Enum.Material.Rock)
end

local function decorateTraining(model: Model, origin: Vector3, rng: Random)
	--[[
		Árvores em GRUPOS de 2–3 (antes eram 26 soltas, espaçadas de forma
		uniforme). Os grupos separam as atividades e deixam livres as áreas,
		as calçadas, a avenida e a linha de visão do spawn (clearOfLayout).
	]]
	for _ = 1, 10 do
		local centre = ringPoint(rng, 70, GROUND_RADIUS - 14)
		for _ = 1, rng:NextInteger(2, 3) do
			for _ = 1, 8 do
				local angle = rng:NextNumber(0, math.pi * 2)
				local p = centre + Vector3.new(math.cos(angle), 0, math.sin(angle)) * rng:NextNumber(4, 8)
				if p.Magnitude < GROUND_RADIUS - 8 and clearOfLayout(p.X, p.Z, 4) then
					tree(model, origin + p, rng)
					break
				end
			end
		end
	end
	for _ = 1, 14 do
		rock(model, origin + ringPoint(rng, 55, GROUND_RADIUS - 6), rng, Color3.fromRGB(130, 130, 136), 1)
	end
	-- Flowers.
	local flowerColors = { Color3.fromRGB(255, 90, 120), Color3.fromRGB(255, 220, 80), Color3.fromRGB(150, 110, 255) }
	for _ = 1, 28 do
		local p = origin + ringPoint(rng, 50, GROUND_RADIUS - 8)
		ball(model, p + Vector3.new(0, 0.6, 0), 1.2, flowerColors[rng:NextInteger(1, #flowerColors)], Enum.Material.SmoothPlastic, false)
	end
	-- Lago com vitórias-régias e pedras (LobbyConfig.Decoration.Pond). Antes
	-- ficava em cima da área de Pets.
	local pond = origin + LobbyConfig.Decoration.Pond
	local pondRadius = LobbyConfig.Decoration.PondRadius
	disc(model, pond + Vector3.new(0, 0.5, 0), pondRadius + 3, 1, Color3.fromRGB(150, 140, 120), Enum.Material.Slate)
	local water = disc(model, pond + Vector3.new(0, 0.9, 0), pondRadius, 0.6, Color3.fromRGB(70, 170, 220), Enum.Material.Glass, false)
	water.Transparency = 0.25
	for _ = 1, 5 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = rng:NextNumber(0, pondRadius - 4)
		disc(model, pond + Vector3.new(math.cos(angle) * distance, 1.2, math.sin(angle) * distance), rng:NextNumber(1.6, 2.8), 0.3, Color3.fromRGB(80, 160, 70), Enum.Material.Grass, false)
	end
	for index = 1, 4 do
		local angle = index / 4 * math.pi * 2 + 0.4
		rock(model, pond + Vector3.new(math.cos(angle) * (pondRadius + 3), 0, math.sin(angle) * (pondRadius + 3)), rng, Color3.fromRGB(140, 138, 142), 0.8)
	end

	--[[
		O moinho, os fardos de feno e os bonecos de treino saíram: o moinho
		ficava dentro da área da Loja e os bonecos no meio do caminho para o
		Caminho do Poder (sobras do layout antigo). A academia agora tem
		arquitetura própria (buildTrainingMachines).
	]]

	-- Benches facing the plaza.
	for i = -1, 1, 2 do
		local p = origin + Vector3.new(i * 30, 0, -48)
		block(model, CFrame.new(p + Vector3.new(0, 2.2, 0)), Vector3.new(12, 0.7, 3.6), Color3.fromRGB(170, 130, 90), Enum.Material.WoodPlanks)
		block(model, CFrame.new(p + Vector3.new(0, 3.6, -1.6)), Vector3.new(12, 3, 0.7), Color3.fromRGB(170, 130, 90), Enum.Material.WoodPlanks)
		for side = -1, 1, 2 do
			block(model, CFrame.new(p + Vector3.new(side * 5, 1, 0)), Vector3.new(0.8, 2, 3.6), Color3.fromRGB(120, 90, 60), Enum.Material.Wood)
		end
	end

	-- Lamp posts along the plaza rim.
	for i = 0, 7 do
		local angle = i / 8 * math.pi * 2 + math.pi / 8
		local p = origin + Vector3.new(math.cos(angle) * 50, 0, math.sin(angle) * 50)
		block(model, CFrame.new(p + Vector3.new(0, 6, 0)), Vector3.new(0.8, 12, 0.8), Color3.fromRGB(90, 70, 50), Enum.Material.Metal)
		local lamp = ball(model, p + Vector3.new(0, 12.6, 0), 2.2, Color3.fromRGB(255, 230, 160), Enum.Material.Neon, false)
		light(lamp, Color3.fromRGB(255, 225, 150), 20, 1.1)
	end

	-- Balloons floating over the island.
	local balloonColors = { Color3.fromRGB(255, 90, 120), Color3.fromRGB(80, 220, 255), Color3.fromRGB(255, 196, 45), Color3.fromRGB(150, 110, 255) }
	for _ = 1, 6 do
		local p = origin + ringPoint(rng, 60, GROUND_RADIUS - 20) + Vector3.new(0, rng:NextNumber(40, 78), 0)
		local color = balloonColors[rng:NextInteger(1, #balloonColors)]
		ball(model, p, rng:NextNumber(7, 11), color, Enum.Material.SmoothPlastic, false)
		block(model, CFrame.new(p - Vector3.new(0, 7, 0)), Vector3.new(0.3, 8, 0.3), Color3.fromRGB(240, 240, 240), Enum.Material.SmoothPlastic, false)
	end
end

local function decorateCity(model: Model, origin: Vector3, rng: Random)
	-- Roads (cross) + sidewalks.
	block(model, CFrame.new(origin + Vector3.new(0, 0.15, 0)), Vector3.new(GROUND_RADIUS * 2 - 20, 0.3, 22), Color3.fromRGB(40, 40, 46), Enum.Material.Asphalt)
	block(model, CFrame.new(origin + Vector3.new(0, 0.15, 0)), Vector3.new(22, 0.3, GROUND_RADIUS * 2 - 20), Color3.fromRGB(40, 40, 46), Enum.Material.Asphalt)
	for i = -6, 6 do
		if i ~= 0 then
			block(model, CFrame.new(origin + Vector3.new(i * 20, 0.35, 0)), Vector3.new(8, 0.1, 1), Color3.fromRGB(240, 220, 90), Enum.Material.Neon, false)
			block(model, CFrame.new(origin + Vector3.new(0, 0.35, i * 20)), Vector3.new(1, 0.1, 8), Color3.fromRGB(240, 220, 90), Enum.Material.Neon, false)
		end
	end
	-- Buildings.
	local windowColors = { Color3.fromRGB(255, 230, 150), Color3.fromRGB(120, 220, 255), Color3.fromRGB(255, 140, 200) }
	for _ = 1, 26 do
		local p = origin + ringPoint(rng, 80, GROUND_RADIUS - 18)
		if math.abs(p.X - origin.X) > 18 and math.abs(p.Z - origin.Z) > 18 then
			local width, depth = rng:NextNumber(14, 22), rng:NextNumber(14, 22)
			local height = rng:NextNumber(30, 95)
			local shade = rng:NextInteger(70, 130)
			local body = block(model, CFrame.new(p + Vector3.new(0, height / 2, 0)), Vector3.new(width, height, depth), Color3.fromRGB(shade, shade, shade + 12), Enum.Material.Concrete)
			body.Name = "Building"
			local windowColor = windowColors[rng:NextInteger(1, #windowColors)]
			for floor = 1, math.floor(height / 10) do
				block(model, CFrame.new(p + Vector3.new(0, floor * 10 - 3, 0)), Vector3.new(width + 0.2, 1.4, depth + 0.2), windowColor, Enum.Material.Neon, false)
			end
		end
	end
	-- Street lamps.
	for i = -5, 5 do
		if i ~= 0 then
			for _, side in { -1, 1 } do
				local p = origin + Vector3.new(i * 24, 0, side * 15)
				block(model, CFrame.new(p + Vector3.new(0, 6, 0)), Vector3.new(0.8, 12, 0.8), Color3.fromRGB(50, 50, 55), Enum.Material.Metal)
				local lamp = ball(model, p + Vector3.new(0, 12.5, 0), 2, Color3.fromRGB(255, 235, 170), Enum.Material.Neon, false)
				light(lamp, Color3.fromRGB(255, 225, 160), 22, 1.2)
			end
		end
	end
	-- Cars.
	local carColors = { Color3.fromRGB(220, 60, 60), Color3.fromRGB(60, 120, 220), Color3.fromRGB(240, 200, 60), Color3.fromRGB(240, 240, 240) }
	for i = 1, 8 do
		local alongX = i % 2 == 0
		local offset = rng:NextNumber(-110, 110)
		if math.abs(offset) > 30 then
			local p = origin + (if alongX then Vector3.new(offset, 0, rng:NextNumber(-6, 6)) else Vector3.new(rng:NextNumber(-6, 6), 0, offset))
			local cf = CFrame.new(p + Vector3.new(0, 1.6, 0)) * CFrame.Angles(0, if alongX then math.pi / 2 else 0, 0)
			local color = carColors[rng:NextInteger(1, #carColors)]
			block(model, cf, Vector3.new(5, 2, 10), color, Enum.Material.SmoothPlastic)
			block(model, cf * CFrame.new(0, 1.8, 0.5), Vector3.new(4.4, 1.8, 5.5), Color3.fromRGB(30, 40, 60), Enum.Material.Glass)
		end
	end
end

local function decorateVolcano(model: Model, origin: Vector3, rng: Random)
	-- Big volcano behind the egg stands.
	local center = origin + Vector3.new(0, 0, -128)
	for level = 0, 6 do
		local radius = 44 - level * 6
		disc(model, center + Vector3.new(0, 6 + level * 6, 0), radius, 6.2, Color3.fromRGB(70 - level * 3, 45, 40), Enum.Material.Rock)
	end
	local crater = disc(model, center + Vector3.new(0, 42.5, 0), 7, 0.6, Color3.fromRGB(255, 110, 30), Enum.Material.Neon, false)
	local fire = Instance.new("Fire")
	fire.Size = 25
	fire.Heat = 20
	fire.Color = Color3.fromRGB(255, 120, 40)
	fire.SecondaryColor = Color3.fromRGB(255, 60, 20)
	fire.Parent = crater
	light(crater, Color3.fromRGB(255, 110, 40), 60, 3)
	-- Lava pools and rivers (decorative, no damage).
	for _ = 1, 9 do
		local p = origin + ringPoint(rng, 60, GROUND_RADIUS - 20)
		local pool = disc(model, p + Vector3.new(0, 0.25, 0), rng:NextNumber(6, 12), 0.5, Color3.fromRGB(255, 100, 20), Enum.Material.Neon, false)
		light(pool, Color3.fromRGB(255, 100, 30), 18, 1.5)
	end
	for _, angle in { 0.6, 2.2, 3.9, 5.3 } do
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local mid = origin + direction * 105
		block(model, CFrame.lookAt(mid + Vector3.new(0, 0.2, 0), mid + direction + Vector3.new(0, 0.2, 0)), Vector3.new(5, 0.4, 70), Color3.fromRGB(255, 120, 30), Enum.Material.Neon, false)
	end
	-- Spiky basalt rocks.
	for _ = 1, 22 do
		local p = origin + ringPoint(rng, 55, GROUND_RADIUS - 6)
		local height = rng:NextNumber(6, 18)
		block(model, CFrame.new(p + Vector3.new(0, height / 2, 0)) * CFrame.Angles(rng:NextNumber(-0.25, 0.25), rng:NextNumber(0, math.pi), rng:NextNumber(-0.25, 0.25)), Vector3.new(rng:NextNumber(3, 6), height, rng:NextNumber(3, 6)), Color3.fromRGB(38, 32, 32), Enum.Material.Basalt)
	end
end

local function decorateSpace(model: Model, origin: Vector3, rng: Random)
	-- Neon grid lines on the platform.
	for i = -6, 6 do
		block(model, CFrame.new(origin + Vector3.new(i * 22, 0.1, 0)), Vector3.new(0.5, 0.2, GROUND_RADIUS * 1.6), Color3.fromRGB(90, 180, 255), Enum.Material.Neon, false)
		block(model, CFrame.new(origin + Vector3.new(0, 0.1, i * 22)), Vector3.new(GROUND_RADIUS * 1.6, 0.2, 0.5), Color3.fromRGB(90, 180, 255), Enum.Material.Neon, false)
	end
	-- Floating asteroids around the station.
	for _ = 1, 28 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = rng:NextNumber(GROUND_RADIUS + 20, GROUND_RADIUS + 140)
		local p = origin + Vector3.new(math.cos(angle) * radius, rng:NextNumber(-30, 70), math.sin(angle) * radius)
		ball(model, p, rng:NextNumber(8, 26), Color3.fromRGB(rng:NextInteger(90, 120), rng:NextInteger(85, 105), rng:NextInteger(80, 100)), Enum.Material.Rock, false)
	end
	-- Antenna towers with blinking tips.
	for _ = 1, 6 do
		local p = origin + ringPoint(rng, 90, GROUND_RADIUS - 15)
		local height = rng:NextNumber(20, 40)
		block(model, CFrame.new(p + Vector3.new(0, height / 2, 0)), Vector3.new(1.4, height, 1.4), Color3.fromRGB(170, 175, 190), Enum.Material.Metal)
		local tip = ball(model, p + Vector3.new(0, height + 1, 0), 2.4, Color3.fromRGB(255, 70, 70), Enum.Material.Neon, false)
		light(tip, Color3.fromRGB(255, 70, 70), 16, 1.5)
	end
	-- Cargo crates.
	for _ = 1, 16 do
		local p = origin + ringPoint(rng, 60, GROUND_RADIUS - 10)
		local size = rng:NextNumber(4, 7)
		block(model, CFrame.new(p + Vector3.new(0, size / 2, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0), Vector3.new(size, size, size), Color3.fromRGB(120, 130, 150), Enum.Material.DiamondPlate)
	end
end

local function decorateGalaxy(model: Model, origin: Vector3, rng: Random)
	local crystalColors = { Color3.fromRGB(210, 110, 255), Color3.fromRGB(110, 200, 255), Color3.fromRGB(255, 120, 200) }
	-- Crystal clusters.
	for _ = 1, 24 do
		local p = origin + ringPoint(rng, 60, GROUND_RADIUS - 8)
		local color = crystalColors[rng:NextInteger(1, #crystalColors)]
		for _ = 1, rng:NextInteger(2, 4) do
			local height = rng:NextNumber(8, 24)
			local crystal = block(model, CFrame.new(p + Vector3.new(rng:NextNumber(-3, 3), height / 2, rng:NextNumber(-3, 3))) * CFrame.Angles(rng:NextNumber(-0.35, 0.35), rng:NextNumber(0, math.pi), rng:NextNumber(-0.35, 0.35)), Vector3.new(2.5, height, 2.5), color, Enum.Material.Neon, true)
			crystal.Transparency = 0.15
		end
	end
	-- Floating rings (segments in a circle) above the plaza.
	for ringIndex = 1, 3 do
		local radius = 22 + ringIndex * 10
		local height = 40 + ringIndex * 12
		local segments = 24
		for i = 0, segments - 1 do
			local angle = i / segments * math.pi * 2
			local p = origin + Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius)
			block(model, CFrame.lookAt(p, p + Vector3.new(-math.sin(angle), 0, math.cos(angle))), Vector3.new(1.2, 1.2, 2 * math.pi * radius / segments + 0.3), crystalColors[ringIndex], Enum.Material.Neon, false)
		end
	end
	-- Stars.
	for _ = 1, 60 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = rng:NextNumber(GROUND_RADIUS + 30, GROUND_RADIUS + 220)
		ball(model, origin + Vector3.new(math.cos(angle) * radius, rng:NextNumber(20, 160), math.sin(angle) * radius), rng:NextNumber(1, 3), Color3.fromRGB(255, 255, 255), Enum.Material.Neon, false)
	end
end

local DECORATORS: { [string]: (Model, Vector3, Random) -> () } = {
	Training = decorateTraining,
	City = decorateCity,
	Volcano = decorateVolcano,
	Space = decorateSpace,
	Galaxy = decorateGalaxy,
}

--[[
	Sky dressing: small islands floating around, flat clouds above and a
	waterfall pouring off the south rim. Everything is CanCollide = false and
	CastShadow = false — it is scenery, and scenery must not cost physics or
	shadows on a phone.
]]
local function decorateSky(model: Model, origin: Vector3, palette: Palette, rng: Random, hasCorridor: boolean)
	local decoration = LobbyConfig.Decoration

	for index = 1, decoration.FloatingIslands do
		local angle = (index - 1) / decoration.FloatingIslands * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		local radius = rng:NextNumber(decoration.IslandMinRadius, decoration.IslandMaxRadius)
		local height = decoration.IslandHeight + rng:NextNumber(-30, 50)
		local size = rng:NextNumber(18, 34)
		-- Fora do Caminho do Poder (com a copa da árvore): gira a ilha em volta
		-- do centro até sair da faixa. Sem sorteio extra — o resto do céu e da
		-- decoração continua igual.
		if hasCorridor then
			for _ = 1, 12 do
				if not inCorridorBand(math.cos(angle) * radius, math.sin(angle) * radius, size + 12) then
					break
				end
				angle += 0.3
			end
		end
		local centre = origin + Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius)
		disc(model, centre, size, 5, palette.Ground, palette.GroundMaterial, false)
		disc(model, centre - Vector3.new(0, 4, 0), size * 0.7, 9, palette.Rim, palette.RimMaterial, false)
		if rng:NextNumber() < 0.7 then
			tree(model, centre + Vector3.new(rng:NextNumber(-8, 8), 0, rng:NextNumber(-8, 8)), rng)
		end
	end

	for index = 1, decoration.Clouds do
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = rng:NextNumber(60, 320)
		local centre = origin + Vector3.new(math.cos(angle) * radius, decoration.CloudHeight + rng:NextNumber(-40, 60), math.sin(angle) * radius)
		for puff = 1, 3 do
			local part = ball(
				model,
				centre + Vector3.new(rng:NextNumber(-16, 16), rng:NextNumber(-4, 4), rng:NextNumber(-10, 10)),
				rng:NextNumber(18, 32),
				Color3.fromRGB(252, 252, 255),
				Enum.Material.SmoothPlastic,
				false
			)
			part.Name = "Cloud"
			part.CastShadow = false
			part.Transparency = 0.1
			if puff == 3 then
				part.Transparency = 0.2
			end
		end
	end

	--[[
		(A cascata no paredão sul saiu: era uma lâmina de água de 22 x 58 studs
		encostada no paredão; de cima e de longe ela lia como uma placa azul
		grande e inclinada, sem função — foi o objeto azul estranho visto no
		teste do Studio.)
	]]
end

-- ── Public API ──────────────────────────────────────────────────────────────

--[[
	Builds `world` at `origin` into `worldsFolder` (model named world.Id) and
	its spawn marker into `spawnsFolder`. `withSpawnLocation` adds Roblox's
	SpawnLocation (only for the default world).
]]
function WorldBuilder.Build(world: WorldData, origin: Vector3, worldsFolder: Folder, spawnsFolder: Folder, withSpawnLocation: boolean): Model
	local palette = PALETTES[world.Id] or PALETTES.Training
	local model = Instance.new("Model")
	model.Name = world.Id
	model:SetAttribute("TODO_ASSET", true)
	model:SetAttribute("Generated", true)

	local rng = Random.new(world.Order * 7919)
	local hasCorridor = world.Id == WallConfig.WorldId
	buildGround(model, origin, palette)
	-- Paredões com rng próprio: mexer neles não muda a decoração do resto.
	buildCliffs(model, origin, palette, Random.new(world.Order * 104729), hasCorridor)
	buildAreas(model, origin, palette)
	buildWalkways(model, origin, palette)
	if hasCorridor then
		buildTowerPath(model, origin, palette)
		buildPathGate(model, origin)
	end
	buildSpawn(model, origin, palette, world, spawnsFolder, withSpawnLocation)
	buildEggStands(model, origin, palette, world)
	buildAltar(model, origin, palette)
	-- Portal de mundos só existe se houver mundo para onde ir (WorldRules).
	if WorldRules.TravelAvailable() then
		buildPortal(model, origin, palette)
	end
	buildStations(model, origin, palette)
	buildScoreboard(model, origin, palette)
	if ZoneConfig.Build then
		buildZones(model, origin, world)
	end
	if hasCorridor then
		buildCutPads(model, origin, palette)
		buildTrainingMachines(model, origin, palette)
		buildCorridor(model, origin, palette)
	end
	decorateSky(model, origin, palette, rng, hasCorridor)
	local decorate = DECORATORS[world.Id]
	if decorate then
		decorate(model, origin, rng)
	end
	model.Parent = worldsFolder
	return model
end

return WorldBuilder
