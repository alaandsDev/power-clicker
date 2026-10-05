--!strict
--[[
	CutFx
	Desenha a receita de um corte (CutVisuals.Recipe): riscos, varredura
	(trail), luz e faíscas. É o MESMO desenho no golpe do jogador
	(SlashController) e na vitrine dos pads (CutShowcaseController) — a vitrine
	não é uma propaganda à parte, é o efeito real em escala menor.

	Um "rig" é um conjunto fixo de peças criado uma vez: `plays` grupos de
	CutVisuals.MAX_SLASHES riscos, reaproveitados em rodízio, mais uma peça
	invisível com a luz e o emissor de faíscas e um anel de onda de choque. Tocar o efeito só muda
	propriedades e dispara tweens; nada é criado nem destruído por golpe, e
	Destroy apaga tudo de uma vez (sem conexões: não há nenhuma).
]]

local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local CutVisuals = require(Shared:WaitForChild("Formulas"):WaitForChild("CutVisuals"))

export type Rig = {
	Folder: Folder,
	Slots: { { BasePart } },
	Index: number,
	Core: BasePart,
	Ring: BasePart, -- onda de choque dos cortes fortes (Recipe.Shock)
	Light: PointLight,
	Emitter: ParticleEmitter,
	SparkCooldown: number,
	LastSparkAt: number,
	Alive: boolean,
}

local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

local CutFx = {}

local function newStreak(parent: Instance, name: string): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Transparency = 1
	part.Size = Vector3.new(CutVisuals.THICKNESS, 1, 1)
	part.Parent = parent
	return part
end

--[[
	Cria um rig com `plays` efeitos simultâneos possíveis. `sparkCooldown`
	limita as faíscas (o golpe pode tocar 9 vezes por segundo; faísca a cada
	golpe seria partícula demais).
]]
function CutFx.NewRig(name: string, parent: Instance, plays: number, sparkCooldown: number?): Rig
	local folder = Instance.new("Folder")
	folder.Name = name
	local slots = {}
	for play = 1, math.max(plays, 1) do
		local slot = {}
		for index = 1, CutVisuals.MAX_SLASHES do
			slot[index] = newStreak(folder, string.format("Streak%d_%d", play, index))
		end
		slots[play] = slot
	end

	local core = newStreak(folder, "Core")
	core.Size = Vector3.new(0.2, 0.2, 0.2)
	local ring = newStreak(folder, "Ring")
	ring.Shape = Enum.PartType.Cylinder
	local light = Instance.new("PointLight")
	light.Enabled = false
	light.Shadows = false
	light.Parent = core
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Texture = SPARK_TEXTURE
	emitter.LightEmission = 1
	emitter.Lifetime = NumberRange.new(0.25, 0.45)
	emitter.Speed = NumberRange.new(6, 12)
	emitter.Drag = 4
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new(0.35, 0)
	emitter.Transparency = NumberSequence.new(0, 1)
	emitter.Parent = core

	folder.Parent = parent
	return {
		Folder = folder,
		Slots = slots,
		Index = 0,
		Core = core,
		Ring = ring,
		Light = light,
		Emitter = emitter,
		SparkCooldown = sparkCooldown or 0,
		LastSparkAt = -math.huge,
		Alive = true,
	}
end

--[[
	Toca o corte em `origin` (o olhar de `origin` é para onde o risco "corta").
	`scale` encolhe só o tamanho (a vitrine usa < 1); `roll` gira o conjunto em
	graus (a direção do golpe do combo); `sweep` = 1 ou -1, o sentido em que
	o risco varre enquanto some (o golpe espelhado varre ao contrário).
]]
function CutFx.Play(rig: Rig, recipe: CutVisuals.Recipe, origin: CFrame, scale: number?, roll: number?, sweep: number?)
	if not rig.Alive then
		return
	end
	local size = scale or 1
	rig.Index = (rig.Index % #rig.Slots) + 1
	local slot = rig.Slots[rig.Index]
	local angles = CutVisuals.Angles(recipe.Slashes)
	local info = TweenInfo.new(recipe.FadeSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local length = recipe.Length * size
	local width = recipe.Width * size
	local half = recipe.Sweep / 2 * (if sweep and sweep < 0 then -1 else 1)
	for index, part in slot do
		local angle = angles[index]
		if angle == nil then
			part.Transparency = 1
			continue
		end
		local tilt = angle + (roll or 0)
		part.Color = recipe.Color
		part.Material = if recipe.Glow then Enum.Material.Neon else Enum.Material.SmoothPlastic
		part.Size = Vector3.new(recipe.Thickness, length * 0.45, width)
		part.CFrame = origin * CFrame.Angles(0, 0, math.rad(tilt - half))
		part.Transparency = if recipe.Glow then 0.1 else 0.3
		TweenService:Create(part, info, {
			Transparency = 1,
			Size = Vector3.new(recipe.Thickness, length, width * 0.4),
			CFrame = origin * CFrame.Angles(0, 0, math.rad(tilt + half)),
		}):Play()
	end

	rig.Core.CFrame = origin
	if recipe.LightRange > 0 then
		rig.Light.Color = recipe.Color
		rig.Light.Range = recipe.LightRange * size
		rig.Light.Brightness = 2
		rig.Light.Enabled = true
		TweenService:Create(rig.Light, info, { Brightness = 0 }):Play()
	else
		rig.Light.Enabled = false
	end

	--[[
		Onda de choque: anel no plano do corte, crescendo e sumindo. Cortes em X
		ganham um anel curto; o leque de 3, uma onda; o último corte, a SUPREMA
		(maior, mais clara e mais lenta).
	]]
	if recipe.Shock > 0 then
		local ring = rig.Ring
		local reach = (1.2 + recipe.Shock * 1.1) * size
		ring.Color = if recipe.Shock >= 3 then recipe.Color:Lerp(Color3.new(1, 1, 1), 0.35) else recipe.Color
		ring.Material = Enum.Material.Neon
		ring.CFrame = origin * CFrame.Angles(0, math.rad(90), 0)
		ring.Size = Vector3.new(0.12, reach * 0.3, reach * 0.3)
		ring.Transparency = if recipe.Shock >= 3 then 0.05 else 0.35
		TweenService:Create(ring, TweenInfo.new(recipe.FadeSeconds + 0.04 * recipe.Shock, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.05, reach * 2, reach * 2),
			Transparency = 1,
		}):Play()
	end

	local now = os.clock()
	if recipe.Sparks > 0 and now - rig.LastSparkAt >= rig.SparkCooldown then
		rig.LastSparkAt = now
		rig.Emitter.Color = ColorSequence.new(recipe.Color)
		rig.Emitter.Size = NumberSequence.new(recipe.SparkSize * size, 0)
		rig.Emitter:Emit(recipe.Sparks)
	end
end

-- Apaga o rig inteiro. Chamar de novo não faz nada.
function CutFx.Destroy(rig: Rig)
	if not rig.Alive then
		return
	end
	rig.Alive = false
	rig.Folder:Destroy()
	table.clear(rig.Slots)
end

return CutFx
