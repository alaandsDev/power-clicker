--!strict
--[[
	SlashController
	What flashes in front of the character on every click, in two layers:
	- the ARC, in the colour of the equipped sword skin (cosmetic, SwordConfig);
	- the CUT, the effect of the best cut the player owns (CutService mirrors
	  it on the "BestCut" attribute): colour, streaks, trail, glow and sparks
	  from CutVisuals, drawn by CutFx. The cut pads' showcase plays this exact
	  recipe, so what the pad shows is what the swing does.

	Purely local: the slash is drawn on this client only, so a 9-clicks-a-second
	hold costs the network nothing. The blade, its trail and its glow are the
	server-built part everyone else sees.

	The arcs are pooled — creating and destroying parts at click speed is what
	makes a clicker stutter on a weak phone.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local SwordConfig = require(Shared:WaitForChild("Config"):WaitForChild("SwordConfig"))
local CutVisuals = require(Shared:WaitForChild("Formulas"):WaitForChild("CutVisuals"))

local CutFx = require(script.Parent.Parent.Effects.CutFx)

local DataController = require(script.Parent.DataController)
local SwordSwingController = require(script.Parent.SwordSwingController)
local CombatFxController = require(script.Parent.CombatFxController)

local POOL_SIZE = 4
-- A thin, wide streak. A cylinder read as a round blob from the front, which
-- is not what a slash looks like.
local ARC_SIZE = Vector3.new(0.25, 6.5, 1.1)
local ARC_DISTANCE = 3.4 -- studs in front of the character
local ARC_SECONDS = 0.16
local MIN_INTERVAL = 0.05 -- never more than ~20 arcs a second
-- Cut layer: at most ~10 a second, and the rig holds enough plays for the
-- longest trail (CutVisuals: 0.16 + 0.5 s) at that rate.
local CUT_MIN_INTERVAL = 0.1
local CUT_PLAYS = 7
local CUT_SPARK_COOLDOWN = 0.3 -- sparks at most ~3 times a second

local SlashController = {}

local pool: { BasePart } = {}
local poolIndex = 0
local lastAt = 0
local lastCutAt = 0
local folder: Folder
local cutRig: CutFx.Rig

-- A skin equipada decide a cor e o tamanho do arco (SwordService escreve o
-- atributo). Cosmético: não há número de dano nenhum aqui.
local function equippedSword(): SwordConfig.SwordData
	local swordId = Players.LocalPlayer:GetAttribute("EquippedSword")
	local sword = if type(swordId) == "string" then SwordConfig.Swords[swordId] else nil
	return sword or SwordConfig.Swords[SwordConfig.DefaultSword]
end

local function createArc(): BasePart
	local part = Instance.new("Part")
	part.Name = "Slash"
	part.Size = ARC_SIZE
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Parent = folder
	return part
end

-- Inclinação do arco/corte de cada variação do golpe (graus em torno do
-- olhar): o risco segue a diagonal que a lâmina faz.
local VARIANT_ROLL = { A = 45, B = -45, C = 0 }

local function draw(variant: string?)
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		return
	end
	local now = os.clock()
	-- Sem golpe (R6, montando): inclinação variada, como antes.
	local roll = if variant then VARIANT_ROLL[variant] + math.random(-10, 10)
		else math.random(25, 65) * (if math.random() < 0.5 then 1 else -1)

	poolIndex = (poolIndex % POOL_SIZE) + 1
	local arc = pool[poolIndex]
	local sword = equippedSword()
	arc.Color = sword.ArcColor
	arc.CFrame = root.CFrame
		* CFrame.new(math.random(-12, 12) / 10, 0.4, -ARC_DISTANCE)
		* CFrame.Angles(0, 0, math.rad(roll))
	arc.Transparency = 0.25
	arc.Size = ARC_SIZE * sword.ArcScale

	TweenService:Create(arc, TweenInfo.new(ARC_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Size = Vector3.new(
			ARC_SIZE.X * sword.ArcScale,
			ARC_SIZE.Y * sword.ArcScale * 1.5,
			ARC_SIZE.Z * sword.ArcScale * 0.4
		),
	}):Play()

	local recipe = CutVisuals.ForBest(Players.LocalPlayer:GetAttribute("BestCut"))
	if now - lastCutAt >= CUT_MIN_INTERVAL then
		lastCutAt = now
		local origin = root.CFrame * CFrame.new(math.random(-8, 8) / 10, 0.4, -ARC_DISTANCE - 0.3)
		CutFx.Play(cutRig, recipe, origin, 1, roll - 45)
	end
	-- No mesmo instante: o impacto na barreira (se o golpe acertou uma).
	CombatFxController.OnSwingImpact(recipe)
end

--[[
	Um hit do jogador local: o personagem golpeia (SwordSwingController) e, no
	momento do impacto do golpe, o arco da espada e o corte (CutFx) aparecem.
	Seguro a cada clique: limita a própria frequência e reusa as peças.
	"Efeitos reduzidos" tira o arco e o corte, mas NÃO o golpe da espada nem
	a indicação básica do impacto (o flash no ponto de contato).
]]
function SlashController.Play()
	local impact, variant = SwordSwingController.Swing()
	local settings = DataController.Get("Settings")
	if settings and settings.ReducedEffects == true then
		if impact > 0 then
			task.delay(impact, CombatFxController.OnSwingImpact, nil)
		else
			CombatFxController.OnSwingImpact(nil)
		end
		return
	end
	local now = os.clock()
	if now - lastAt < MIN_INTERVAL then
		return
	end
	lastAt = now
	if impact > 0 then
		task.delay(impact, draw, variant)
	else
		draw(variant)
	end
end

function SlashController.Init()
	folder = Instance.new("Folder")
	folder.Name = "SlashEffects"
	folder.Parent = Workspace.CurrentCamera or Workspace
	for index = 1, POOL_SIZE do
		pool[index] = createArc()
	end
	cutRig = CutFx.NewRig("Cut", folder, CUT_PLAYS, CUT_SPARK_COOLDOWN)
end

return SlashController
