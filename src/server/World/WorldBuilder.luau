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
local NumberFormat = require(Shared.Utils.NumberFormat)
local Text = require(Shared.Localization)

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
	MURALHA. A ilha é fechada por montanhas em degraus, não por cerca: cerca de
	madeira é decoração, e o jogador passa por cima dela.

	Cada degrau tem HILL_STEP_HEIGHT studs de altura. O pulo do Roblox sobe
	~7,2 studs, então um degrau de 14 não é escalável — e são três, somando
	HILL_STEPS × HILL_STEP_HEIGHT de parede. A única abertura é a boca do
	corredor (inCorridor).
]]
local HILL_STEPS = 3
local HILL_STEP_HEIGHT = 14
local HILL_CAP = 2 -- topo de grama em cada degrau
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

-- Random point on the island ring between minRadius and maxRadius, avoiding
-- the central plaza (|x| < clearX and |z| < clearZ).
local function ringPoint(rng: Random, minRadius: number, maxRadius: number): Vector3
	for _ = 1, 20 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = rng:NextNumber(minRadius, maxRadius)
		local x, z = math.cos(angle) * radius, math.sin(angle) * radius
		-- keep the station lanes clear
		if not (math.abs(x) < 40 and z > 30) and not (math.abs(z + 70) < 25 and math.abs(x) < 70) then
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

local function billboard(parent: BasePart, text: string, color: Color3, offsetY: number)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(SIGN_STUDS.X, SIGN_STUDS.Y)
	gui.StudsOffset = Vector3.new(0, offsetY, 0)
	gui.MaxDistance = 120
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
-- The win corridor leaves the island going east; the hills open up for it.
local function inCorridor(offset: Vector3): boolean
	return offset.X > 0 and math.abs(offset.Z) <= WallConfig.Layout.Width / 2 + TILE_STUDS
end

local function buildGround(model: Model, origin: Vector3, palette: Palette)
	-- +1 tile de folga: sem ela, os cantos do anel ficavam com fresta.
	local reach = math.ceil((GROUND_RADIUS + HILL_STEPS * TILE_STUDS) / TILE_STUDS) + 1
	local groundDark = shade(palette.Ground, TILE_DARKEN)
	local plazaDark = shade(palette.Pad, TILE_DARKEN)
	local hillBody = shade(palette.Rim, 1)

	for ix = -reach, reach do
		for iz = -reach, reach do
			local offset = Vector3.new(ix * TILE_STUDS, 0, iz * TILE_STUDS)
			local distance = offset.Magnitude
			local checker = (ix + iz) % 2 == 0
			if distance <= GROUND_RADIUS then
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
			elseif not inCorridor(offset) then
				local step = math.clamp(math.ceil((distance - GROUND_RADIUS) / TILE_STUDS), 1, HILL_STEPS)
				local top = step * HILL_STEP_HEIGHT
				local height = GROUND_HEIGHT + top
				block(
					model,
					CFrame.new(origin + offset + Vector3.new(0, top - height / 2, 0)),
					Vector3.new(TILE_STUDS, height, TILE_STUDS),
					hillBody,
					palette.RimMaterial
				)
				-- Grass cap, so the hills read as terraces and not as dirt walls.
				block(
					model,
					CFrame.new(origin + offset + Vector3.new(0, top + HILL_CAP / 2, 0)),
					Vector3.new(TILE_STUDS, HILL_CAP, TILE_STUDS),
					if checker then palette.Ground else groundDark,
					palette.GroundMaterial
				)
			end
		end
	end

	-- Skirt under the tiles: from below the island still reads as one plate.
	disc(model, origin - Vector3.new(0, GROUND_HEIGHT - 1, 0), GROUND_RADIUS + 8, 10, palette.Rim, palette.RimMaterial)
end

local function buildSpawn(model: Model, origin: Vector3, palette: Palette, world: WorldData, spawns: Folder, withSpawnLocation: boolean)
	local spawnArea = areaOf("Spawn")
	local padCenter = origin + spawnArea.Offset + Vector3.new(0, 0.3, 0)
	disc(model, padCenter, 12, 0.6, palette.Accent, Enum.Material.Neon)
	disc(model, padCenter + Vector3.new(0, 0.1, 0), 10, 0.6, palette.Pad, Enum.Material.SmoothPlastic)

	local marker = Instance.new("Part")
	marker.Name = world.SpawnName
	marker:SetAttribute("TODO_ASSET", true)
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.Transparency = 1
	marker.Size = Vector3.new(4, 1, 4)
	marker.CFrame = CFrame.new(padCenter + Vector3.new(0, 3, 0)) * CFrame.Angles(0, math.pi, 0) -- facing north (eggs)
	marker.Parent = spawns

	if withSpawnLocation then
		-- Roblox's default spawn for brand-new characters (before data loads).
		local spawnLocation = Instance.new("SpawnLocation")
		spawnLocation.Name = "SpawnLocation"
		spawnLocation.Anchored = true
		spawnLocation.Size = Vector3.new(8, 0.4, 8)
		spawnLocation.CFrame = CFrame.new(padCenter + Vector3.new(0, 0.5, 0))
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
			local ring = disc(model, base + Vector3.new(0, 4.8, 0), 6.4, 0.3, palette.Accent, Enum.Material.Neon, false)
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
			billboard(eggPart, string.format("%s\n%s %s", Text.GetFor(nil, "egg." .. eggId .. ".name"), icon, NumberFormat.Short(egg.Price)), Color3.new(1, 1, 1), 7)
			prompt(eggPart, "Eggs", "world.prompt.hatch", "egg." .. eggId .. ".name")
		end
	end
end

local function buildAltar(model: Model, origin: Vector3, palette: Palette)
	local base = origin + areaOf("Rebirth").Offset
	disc(model, base + Vector3.new(0, 1, 0), 10, 1, palette.Rim, Enum.Material.Marble)
	for step = 1, 3 do
		disc(model, base + Vector3.new(0, 1 + step * 1.2, 0), 10 - step * 2, 1.2, palette.Pad, Enum.Material.Marble)
	end
	local orb = ball(model, base + Vector3.new(0, 10, 0), 5, Color3.fromRGB(140, 90, 255), Enum.Material.Neon, false)
	orb.Name = "RebirthOrb"
	light(orb, Color3.fromRGB(140, 90, 255), 18, 2)
	billboard(orb, "🔁 " .. Text.GetFor(nil, "menu.rebirth"), Color3.fromRGB(200, 170, 255), 5)
	prompt(orb, "Rebirth", "world.prompt.rebirth")
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

-- Kiosk: counter + canopy + floating sign, with a prompt that opens `Panel`.
local function buildStations(model: Model, origin: Vector3, palette: Palette)
	for _, station in LobbyConfig.Stations do
		local base = origin + areaOf(station.Area).Offset + station.Local
		local facing = CFrame.lookAt(base, origin + Vector3.new(0, 0, 0)) -- always faces the plaza
		local yaw = facing - facing.Position
		disc(model, base + Vector3.new(0, 0.5, 0), 9, 0.5, palette.Pad, Enum.Material.Concrete)
		local counter = block(model, CFrame.new(base + Vector3.new(0, 2.5, 0)) * yaw, Vector3.new(12, 5, 5), palette.Rim, Enum.Material.WoodPlanks)
		counter.Name = "Station_" .. station.Panel
		block(model, CFrame.new(base + Vector3.new(0, 5.4, 0)) * yaw, Vector3.new(13, 0.8, 6), station.Color, Enum.Material.SmoothPlastic)
		for side = -1, 1, 2 do
			block(model, CFrame.new(base + Vector3.new(0, 8, 0)) * yaw * CFrame.new(side * 5.6, 0, -2), Vector3.new(0.8, 6, 0.8), palette.Rim, Enum.Material.Wood)
		end
		local canopy = block(model, CFrame.new(base + Vector3.new(0, 11.4, 0)) * yaw, Vector3.new(14, 0.8, 8), station.Color, Enum.Material.SmoothPlastic, false)
		canopy.Name = "Canopy"
		light(canopy, station.Color, 16, 1)
		-- Above the canopy (which sits at y = 11.4): at 9 the sign was inside it.
		billboard(counter, string.format("%s %s", station.Icon, Text.GetFor(nil, station.NameKey)), Color3.new(1, 1, 1), 15)
		prompt(counter, station.Panel, station.TextKey, station.NameKey)
	end
end

-- Board frame; the live ranking is drawn by the client (ScoreboardController),
-- which finds it by the "Scoreboard" attribute. Server-side it stays empty.
local function buildScoreboard(model: Model, origin: Vector3, palette: Palette)
	local base = origin + LobbyConfig.Scoreboard
	local yaw = CFrame.Angles(0, -math.pi / 2, 0) -- face the plaza (west)
	disc(model, base + Vector3.new(0, 0.5, 0), 16, 0.5, palette.Pad, Enum.Material.Concrete)
	for side = -1, 1, 2 do
		block(model, CFrame.new(base + Vector3.new(0, 9, side * 14)), Vector3.new(3, 18, 3), palette.Rim, Enum.Material.Metal)
	end
	local panel = makePart(model, {
		Name = "Scoreboard",
		Size = Vector3.new(1, 22, 34),
		CFrame = CFrame.new(base + Vector3.new(0, 20, 0)),
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
local function buildTrainingMachines(model: Model, origin: Vector3, palette: Palette)
	local area = areaOf(TrainingConfig.Area)
	for _, station in TrainingConfig.Stations do
		local centre = origin + area.Offset + station.Local

		-- O pad onde se fica: é ele que o serviço mede.
		local pad = disc(model, centre + Vector3.new(0, 0.7, 0), station.Radius, 0.6, station.Color, Enum.Material.SmoothPlastic, false)
		pad.Name = "TrainingPad_" .. station.Id
		pad:SetAttribute("TrainingStation", station.Id)

		if station.Kind == "Bag" then
			-- Poste, corrente e o saco pendurado.
			block(model, CFrame.new(centre + Vector3.new(0, 7, 0)), Vector3.new(1.2, 14, 1.2), palette.Rim, Enum.Material.Metal)
			block(model, CFrame.new(centre + Vector3.new(2.5, 13.5, 0)), Vector3.new(6, 1, 1), palette.Rim, Enum.Material.Metal)
			local bag = makePart(model, {
				Name = "Bag",
				Size = Vector3.new(3.4, 7, 3.4),
				CFrame = CFrame.new(centre + Vector3.new(4.5, 8, 0)),
				Color = station.Color,
				Material = Enum.Material.Fabric,
				CanCollide = false,
			})
			block(model, CFrame.new(centre + Vector3.new(4.5, 12.2, 0)), Vector3.new(0.5, 2, 0.5), palette.Rim, Enum.Material.Metal, false)
			bag.Name = "Bag"
		elseif station.Kind == "Weights" then
			-- Suporte com duas barras e discos.
			for side = -1, 1, 2 do
				block(model, CFrame.new(centre + Vector3.new(side * 4, 3, 0)), Vector3.new(1.5, 6, 1.5), palette.Rim, Enum.Material.Metal)
			end
			local bar = block(model, CFrame.new(centre + Vector3.new(0, 6.5, 0)), Vector3.new(12, 0.8, 0.8), Color3.fromRGB(190, 195, 205), Enum.Material.Metal, false)
			bar.Name = "Bar"
			for side = -1, 1, 2 do
				local plate = makePart(model, {
					Name = "Plate",
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(1.2, 5, 5),
					CFrame = CFrame.new(centre + Vector3.new(side * 5.2, 6.5, 0)),
					Color = station.Color,
					Material = Enum.Material.Metal,
					CanCollide = false,
				})
				plate.Name = "Plate"
			end
		elseif station.Kind == "Treadmill" then
			-- Base, esteira e painel.
			block(model, CFrame.new(centre + Vector3.new(0, 1.2, 0)), Vector3.new(16, 2.4, 9), palette.Rim, Enum.Material.Metal)
			local belt = block(model, CFrame.new(centre + Vector3.new(0, 2.5, 0)), Vector3.new(14, 0.6, 7), Color3.fromRGB(40, 44, 58), Enum.Material.Rubber, false)
			belt.Name = "Belt"
			block(model, CFrame.new(centre + Vector3.new(-8, 6, 0)), Vector3.new(1, 8, 8), palette.Rim, Enum.Material.Metal)
			local panel = block(model, CFrame.new(centre + Vector3.new(-8.6, 9, 0)), Vector3.new(0.4, 3, 6), station.Color, Enum.Material.Neon, false)
			panel.Name = "Panel"
			light(panel, station.Color, 14, 1)
		else
			-- Máquina de força: gaiola com barra e pesos.
			for x = -1, 1, 2 do
				for z = -1, 1, 2 do
					block(model, CFrame.new(centre + Vector3.new(x * 6, 8, z * 5)), Vector3.new(1.2, 16, 1.2), palette.Rim, Enum.Material.Metal)
				end
			end
			block(model, CFrame.new(centre + Vector3.new(0, 16, 0)), Vector3.new(13, 1.2, 11), palette.Rim, Enum.Material.Metal, false)
			local stack = block(model, CFrame.new(centre + Vector3.new(0, 5, -4)), Vector3.new(8, 10, 2.5), station.Color, Enum.Material.Metal, false)
			stack.Name = "Stack"
			light(stack, station.Color, 16, 1)
		end

		-- Letreiro: o que rende e o que exige, em cima da máquina.
		local sign = makePart(model, {
			Name = "TrainingSign_" .. station.Id,
			Size = Vector3.new(2, 2, 2),
			CFrame = CFrame.new(centre + Vector3.new(0, 18, 0)),
			Color = station.Color,
			Material = Enum.Material.Neon,
			CanCollide = false,
			Transparency = 1,
		})
		local label = Text.GetFor(nil, "training.sign", {
			name = Text.GetFor(nil, "training." .. station.Id .. ".name"),
			rate = string.format("%.2f", math.min(station.Rate, 99)),
		})
		if station.RequiredWins > 0 then
			label = label .. Text.GetFor(nil, "training.signWins", { wins = NumberFormat.Short(station.RequiredWins) })
		end
		billboard(sign, label, station.Color, 3)
	end
end

--[[
	Cut pads: a row of plates in front of the spawn, each selling one cut.
	CutService answers the prompt (PromptTriggered is a server event), so the
	price and the wins requirement are never checked on the client.
	The sign shows what it gives, what it costs and what it asks for.
]]
local function buildCutPads(model: Model, origin: Vector3, palette: Palette)
	local layout = CutConfig.Layout
	local cuts = CutLogic.Ordered()
	local area = areaOf(layout.Area)
	local columns = layout.Columns
	local rows = math.ceil(#cuts / columns)
	for index, cut in cuts do
		-- Grid at the foot of the tower: cheapest at the front-left.
		local column = (index - 1) % columns
		local row = math.floor((index - 1) / columns)
		local offsetX = (column - (columns - 1) / 2) * layout.Spacing.X
		local offsetZ = (row - (rows - 1) / 2) * layout.Spacing.Y
		local pad = makePart(model, {
			Name = "CutPad_" .. cut.Id,
			Size = Vector3.new(layout.PadSize, 1, layout.PadSize),
			CFrame = CFrame.new(origin + area.Offset + Vector3.new(offsetX, 0.5, offsetZ)),
			Color = if cut.Price == 0 then palette.Pad else palette.Accent,
			Material = Enum.Material.Neon,
			CanCollide = false,
		})
		pad:SetAttribute("CutPad", true)
		pad:SetAttribute("CutId", cut.Id)

		local text = if cut.Price == 0
			then Text.GetFor(nil, "cut.starter", { flat = NumberFormat.Short(cut.Flat) })
			else Text.GetFor(nil, "cut.sign", {
				flat = NumberFormat.Short(cut.Flat),
				price = NumberFormat.Short(cut.Price),
				wins = NumberFormat.Short(cut.RequiredWins),
			})
		billboard(pad, text, palette.Accent, layout.SignHeight)

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
end

--[[
	Area floor + sign: a round plate in the area's colour, a ring of accent and
	a tall billboard with icon and name. This is what tells a new player where
	the eggs, the pets and the tower are without a tutorial.
]]
local function buildAreas(model: Model, origin: Vector3, palette: Palette)
	for _, area in LobbyConfig.Areas do
		local centre = origin + area.Offset
		disc(model, centre + Vector3.new(0, 0.35, 0), area.Radius, 0.7, shade(area.Color, 0.5), Enum.Material.Concrete)
		disc(model, centre + Vector3.new(0, 0.5, 0), area.Radius - 3, 0.6, palette.Pad, Enum.Material.Concrete)
		local ring = disc(model, centre + Vector3.new(0, 0.6, 0), area.Radius - 1, 0.3, area.Color, Enum.Material.Neon, false)
		ring.Name = "AreaRing_" .. area.Id

		-- The sign post, so the name is readable from across the island.
		local post = makePart(model, {
			Name = "AreaSign_" .. area.Id,
			Size = Vector3.new(1.6, area.SignHeight, 1.6),
			CFrame = CFrame.new(centre + Vector3.new(0, area.SignHeight / 2, -(area.Radius - 4))),
			Color = palette.Rim,
			Material = Enum.Material.Wood,
			CanCollide = false,
		})
		light(post, area.Color, 18, 1)
		billboard(
			post,
			string.format("%s %s", area.Icon, Text.GetFor(nil, area.NameKey)),
			area.Color,
			area.SignHeight / 2 + 4
		)
	end
end

--[[
	The stone path from the plaza to the mouth of the tower. It is the one road
	in the lobby, so "where do I go next" has a visual answer.
]]
local function buildTowerPath(model: Model, origin: Vector3, palette: Palette)
	local tower = areaOf("Tower")
	local path = LobbyConfig.Path
	local fromX = 0
	local toX = tower.Offset.X
	local tiles = math.max(math.floor((toX - fromX) / path.TileLength), 1)
	for index = 0, tiles - 1 do
		local x = fromX + (index + 0.5) * path.TileLength
		block(
			model,
			CFrame.new(origin + Vector3.new(x, 0.25, 0)),
			Vector3.new(path.TileLength - 2, 0.5, path.Width),
			if index % 2 == 0 then palette.Pad else shade(palette.Pad, 0.92),
			Enum.Material.Cobblestone,
			false
		)
	end
end

-- ── Win corridor ────────────────────────────────────────────────────────────

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
local function buildCorridor(model: Model, origin: Vector3, palette: Palette)
	local layout = WallConfig.Layout
	local stages = WallConfig.Stages
	local cursor = layout.StartX

	for index, stage in stages do
		local isFinal = index == #stages
		local nextStage = stages[math.min(index + 1, #stages)]
		local scale = if isFinal then layout.FinalScale else 1
		local width = layout.Width * scale
		local length = layout.RoomLength * scale
		local half = width / 2
		local height = layout.WallHeight * scale

		local areaStart = cursor
		local areaEnd = areaStart + length
		--[[
			O trecho do estágio não é só a área temática: ele vai até depois da
			barreira, porque os pads de vitória e o pad de voltar ficam do outro
			lado dela. O piso TEM de cobrir isso tudo — senão o jogador quebra a
			parede, dá dois passos e cai no vazio (foi exatamente o que
			aconteceu na primeira versão).
		]]
		local blockDepth = stage.Rows * layout.RowThickness + (stage.Rows - 1) * layout.RowGap
		-- 72 e não 48: o pad de voltar fica a 48 do fim da barreira, e meio pad
		-- pendurado na borda do piso é o mesmo que buraco.
		local tailLength = blockDepth + 72
		local segmentLength = length + tailLength

		--[[
			Piso em faixas: cada faixa é um passo da transição entre o tema
			desta área e o da próxima. É o que dá a sensação de ir "entrando"
			no ambiente seguinte em vez de atravessar uma porta de cor.
		]]
		local strips = math.max(math.floor(segmentLength / TILE_STUDS), 2)
		local stripLength = segmentLength / strips
		for strip = 0, strips - 1 do
			local blend = strip / (strips - 1)
			local centreX = areaStart + (strip + 0.5) * stripLength
			local floorColor = shade(stage.Accent, 0.7):Lerp(shade(nextStage.Accent, 0.7), blend * 0.6)
			block(
				model,
				CFrame.new(origin + Vector3.new(centreX, -layout.FloorThickness / 2, 0)),
				-- +0.2 de sobreposição: faixas exatamente encostadas deixam
				-- fresta por arredondamento, e fresta no chão é queda.
				Vector3.new(stripLength + 0.2, layout.FloorThickness, width),
				floorColor,
				Enum.Material.Slate
			)
			-- Paredes laterais, com a mesma mistura.
			local wallColor = shade(stage.Color, 0.55):Lerp(shade(nextStage.Color, 0.55), blend * 0.6)
			for _, side in { -1, 1 } do
				block(
					model,
					CFrame.new(origin + Vector3.new(
						centreX,
						layout.SideHeight / 2,
						side * (half + layout.SideThickness / 2)
					)),
					Vector3.new(stripLength + 0.2, layout.SideHeight, layout.SideThickness),
					wallColor,
					stage.Material
				)
			end
		end

		-- Postes na cor do próximo tema: a pista visual de que há algo adiante.
		local lamps = math.max(math.floor(length / layout.LampSpacing), 1)
		for lamp = 1, lamps do
			local lampX = areaStart + lamp * (length / (lamps + 1))
			for _, side in { -1, 1 } do
				local base = origin + Vector3.new(lampX, 0, side * (half - 4))
				block(model, CFrame.new(base + Vector3.new(0, layout.LampHeight / 2, 0)), Vector3.new(1.2, layout.LampHeight, 1.2), palette.Rim, Enum.Material.Metal, false)
				local bulb = ball(model, base + Vector3.new(0, layout.LampHeight + 1, 0), 3, nextStage.Accent, Enum.Material.Neon, false)
				bulb.Name = "CorridorLamp"
				light(bulb, nextStage.Accent, 26, 1.6)
			end
		end

		-- Placa do estágio na entrada da área.
		local marker = makePart(model, {
			Name = "StageMarker_" .. stage.Id,
			Size = Vector3.new(2, 2, 2),
			CFrame = CFrame.new(origin + Vector3.new(areaStart + 10, layout.SideHeight - 6, 0)),
			Color = stage.Accent,
			Material = Enum.Material.Neon,
			CanCollide = false,
			Transparency = 1,
		})
		billboard(
			marker,
			Text.GetFor(nil, "wall.marker", { order = stage.Order, name = Text.GetFor(nil, "wall." .. stage.Id .. ".name") }),
			stage.Accent,
			4
		)

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
			if stage.Neon then
				light(part, stage.Accent, 24, 1.2)
			end
		end

		-- Arco emoldurando a barreira: o portão que marca o checkpoint.
		local archX = areaEnd + blockDepth / 2
		for _, side in { -1, 1 } do
			block(
				model,
				CFrame.new(origin + Vector3.new(archX, (height + layout.ArchExtra) / 2, side * (half + layout.ArchThickness / 2))),
				Vector3.new(blockDepth + 6, height + layout.ArchExtra, layout.ArchThickness),
				shade(stage.Accent, 0.8),
				Enum.Material.Marble,
				false
			)
		end
		local lintel = block(
			model,
			CFrame.new(origin + Vector3.new(archX, height + layout.ArchExtra, 0)),
			Vector3.new(blockDepth + 6, layout.ArchThickness, width + layout.ArchThickness * 2),
			shade(stage.Accent, 0.9),
			Enum.Material.Marble,
			false
		)
		lintel.Name = "Arch_" .. stage.Id
		light(lintel, stage.Accent, 30, 1.4)

		-- Pads de vitória logo depois da barreira, já na entrada da próxima área.
		local padX = areaEnd + blockDepth + 24
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
			billboard(pad, Text.Get("wall.padWins", { amount = NumberFormat.Short(amount) }), stage.Accent, 6)
		end

		-- Pad de voltar: ninguém fica preso no fundo do corredor.
		local returnPad = makePart(model, {
			Name = "ReturnPad_" .. stage.Id,
			Size = Vector3.new(layout.PadSize, 1, layout.PadSize),
			CFrame = CFrame.new(origin + Vector3.new(padX + layout.ReturnPadInset, 0.5, half - layout.PadSize)),
			Color = Color3.fromRGB(235, 80, 80),
			Material = Enum.Material.Neon,
			CanCollide = false,
		})
		returnPad:SetAttribute("WinPad", true)
		returnPad:SetAttribute("StageId", stage.Id)
		returnPad:SetAttribute("Return", true)
		billboard(returnPad, Text.Get("wall.padReturn"), Color3.fromRGB(235, 80, 80), 6)

		cursor = areaStart + segmentLength

		--[[
			Fim da primeira jornada: depois da décima barreira, uma área aberta
			e o portal do próximo mundo — inerte e rotulado "em breve", porque um
			teleporte vazio que engole o jogador seria pior que portal nenhum.
		]]
		if isFinal then
			local plazaLength = 120
			for strip = 0, 5 do
				block(
					model,
					CFrame.new(origin + Vector3.new(cursor + (strip + 0.5) * (plazaLength / 6), -layout.FloorThickness / 2, 0)),
					Vector3.new(plazaLength / 6 + 0.2, layout.FloorThickness, width),
					shade(stage.Accent, 0.6),
					Enum.Material.Marble
				)
			end
			-- Paredes da praça final, para ela não ser uma varanda sem beirada.
			for _, side in { -1, 1 } do
				block(
					model,
					CFrame.new(origin + Vector3.new(
						cursor + plazaLength / 2,
						layout.SideHeight / 2,
						side * (half + layout.SideThickness / 2)
					)),
					Vector3.new(plazaLength, layout.SideHeight, layout.SideThickness),
					shade(stage.Color, 0.5),
					stage.Material
				)
			end
			local portal = makePart(model, {
				Name = "NextWorldPortal",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(3, 36, 36),
				CFrame = CFrame.new(origin + Vector3.new(cursor + plazaLength * 0.7, 20, 0)) * CFrame.Angles(0, 0, math.rad(90)),
				Color = Color3.fromRGB(190, 120, 255),
				Material = Enum.Material.Neon,
				CanCollide = false,
				Transparency = 0.35,
			})
			light(portal, Color3.fromRGB(190, 120, 255), 60, 3)
			billboard(portal, Text.GetFor(nil, "wall.portalSoon"), Color3.fromRGB(210, 160, 255), 24)
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
	for _ = 1, 26 do
		tree(model, origin + ringPoint(rng, 70, GROUND_RADIUS - 10), rng)
	end
	for _ = 1, 14 do
		rock(model, origin + ringPoint(rng, 55, GROUND_RADIUS - 6), rng, Color3.fromRGB(130, 130, 136), 1)
	end
	-- Flowers.
	local flowerColors = { Color3.fromRGB(255, 90, 120), Color3.fromRGB(255, 220, 80), Color3.fromRGB(150, 110, 255) }
	for _ = 1, 40 do
		local p = origin + ringPoint(rng, 50, GROUND_RADIUS - 8)
		ball(model, p + Vector3.new(0, 0.6, 0), 1.2, flowerColors[rng:NextInteger(1, #flowerColors)], Enum.Material.SmoothPlastic, false)
	end
	-- Pond with lily pads (north-west).
	local pond = origin + Vector3.new(-96, 0, -58)
	disc(model, pond + Vector3.new(0, 0.5, 0), 26, 1, Color3.fromRGB(150, 120, 80), Enum.Material.Ground)
	local water = disc(model, pond + Vector3.new(0, 0.9, 0), 23, 0.6, Color3.fromRGB(70, 170, 220), Enum.Material.Glass, false)
	water.Transparency = 0.25
	for _ = 1, 7 do
		local p = pond + Vector3.new(rng:NextNumber(-17, 17), 1.2, rng:NextNumber(-17, 17))
		disc(model, p, rng:NextNumber(2, 3.4), 0.3, Color3.fromRGB(80, 160, 70), Enum.Material.Grass, false)
	end

	-- Windmill (north-east): a landmark visible from the plaza.
	local mill = origin + Vector3.new(104, 0, -52)
	for level = 0, 3 do
		disc(model, mill + Vector3.new(0, 8 + level * 8, 0), 11 - level * 1.6, 8.2, Color3.fromRGB(226, 214, 190), Enum.Material.Sandstone)
	end
	disc(model, mill + Vector3.new(0, 42, 0), 12, 5, Color3.fromRGB(180, 70, 60), Enum.Material.Slate)
	local hub = ball(model, mill + Vector3.new(0, 36, 11), 3, Color3.fromRGB(120, 90, 60), Enum.Material.Wood, false)
	hub.Name = "MillHub"
	for blade = 0, 3 do
		local angle = blade * math.pi / 2 + math.pi / 6
		block(model, CFrame.new(mill + Vector3.new(0, 36, 12)) * CFrame.Angles(0, 0, angle) * CFrame.new(0, 13, 0), Vector3.new(3.4, 26, 0.8), Color3.fromRGB(240, 235, 220), Enum.Material.WoodPlanks, false)
	end

	-- Hay bales and crates near the windmill.
	for _ = 1, 9 do
		local p = mill + Vector3.new(rng:NextNumber(-26, 26), 0, rng:NextNumber(10, 34))
		local bale = block(model, CFrame.new(p + Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), math.rad(90)), Vector3.new(5, 5, 5), Color3.fromRGB(226, 196, 110), Enum.Material.Grass)
		bale.Name = "HayBale"
	end

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
	for _ = 1, 10 do
		local p = origin + ringPoint(rng, 60, GROUND_RADIUS - 20) + Vector3.new(0, rng:NextNumber(40, 78), 0)
		local color = balloonColors[rng:NextInteger(1, #balloonColors)]
		ball(model, p, rng:NextNumber(7, 11), color, Enum.Material.SmoothPlastic, false)
		block(model, CFrame.new(p - Vector3.new(0, 7, 0)), Vector3.new(0.3, 8, 0.3), Color3.fromRGB(240, 240, 240), Enum.Material.SmoothPlastic, false)
	end

	-- Training dummies near the plaza (east).
	for i = 1, 4 do
		local p = origin + Vector3.new(70, 0, -30 + i * 14)
		block(model, CFrame.new(p + Vector3.new(0, 2.5, 0)), Vector3.new(1, 5, 1), Color3.fromRGB(120, 90, 60), Enum.Material.Wood)
		block(model, CFrame.new(p + Vector3.new(0, 6, 0)), Vector3.new(3, 4, 2), Color3.fromRGB(210, 180, 140), Enum.Material.Fabric)
		ball(model, p + Vector3.new(0, 9, 0), 2.6, Color3.fromRGB(210, 180, 140), Enum.Material.Fabric)
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
local function decorateSky(model: Model, origin: Vector3, palette: Palette, rng: Random)
	local decoration = LobbyConfig.Decoration

	for index = 1, decoration.FloatingIslands do
		local angle = (index - 1) / decoration.FloatingIslands * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		local radius = rng:NextNumber(decoration.IslandMinRadius, decoration.IslandMaxRadius)
		local height = decoration.IslandHeight + rng:NextNumber(-30, 50)
		local centre = origin + Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius)
		local size = rng:NextNumber(18, 34)
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

	local fall = decoration.Waterfall
	local top = origin + fall.Offset
	-- The spout, then the sheet of water falling into nothing.
	disc(model, top + Vector3.new(0, 1, 0), fall.Width / 2, 2, Color3.fromRGB(120, 200, 235), Enum.Material.Water, false)
	local sheet = makePart(model, {
		Name = "Waterfall",
		Size = Vector3.new(fall.Width, fall.Drop, 2),
		CFrame = CFrame.new(top - Vector3.new(0, fall.Drop / 2, 0)),
		Color = Color3.fromRGB(150, 215, 245),
		Material = Enum.Material.Water,
		CanCollide = false,
		Transparency = 0.35,
	})
	sheet.CastShadow = false
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
	buildGround(model, origin, palette)
	buildAreas(model, origin, palette)
	buildTowerPath(model, origin, palette)
	buildSpawn(model, origin, palette, world, spawnsFolder, withSpawnLocation)
	buildEggStands(model, origin, palette, world)
	buildAltar(model, origin, palette)
	buildPortal(model, origin, palette)
	buildStations(model, origin, palette)
	buildScoreboard(model, origin, palette)
	if ZoneConfig.Build then
		buildZones(model, origin, world)
	end
	if world.Id == WallConfig.WorldId then
		buildCutPads(model, origin, palette)
		buildTrainingMachines(model, origin, palette)
		buildCorridor(model, origin, palette)
	end
	decorateSky(model, origin, palette, rng)
	local decorate = DECORATORS[world.Id]
	if decorate then
		decorate(model, origin, rng)
	end
	model.Parent = worldsFolder
	return model
end

return WorldBuilder
