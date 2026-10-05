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

	Combo visual (SwordSwing A→B→C): cada golpe diz a DIREÇÃO do risco — A
	"/" (direita→esquerda), B "\" (esquerda→direita), C vertical — e o
	arco/corte segue, um pouco deslocado para o lado onde a lâmina termina.
	O C (fecho) desenha o MESMO Corte um pouco maior; cor, quantidade de
	riscos e partículas continuam sendo do Corte. Espada = movimento,
	Corte = poder, skin = aparência. Dano: nenhum número passa por aqui.

	Auto Click: enquanto o servidor diz que está ligado (atributo
	"AutoClickOn"), o personagem golpeia no MESMO ritmo dos ticks do
	servidor (EconomyConfig.AutoClick.TicksPerSecond), seguindo o mesmo
	combo. Só visual: os ticks de verdade continuam no servidor. Se o
	jogador está clicando, os golpes manuais já mostram o ataque.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local SwordConfig = require(Shared:WaitForChild("Config"):WaitForChild("SwordConfig"))
local CutVisuals = require(Shared:WaitForChild("Formulas"):WaitForChild("CutVisuals"))
local EconomyConfig = require(Shared:WaitForChild("Config"):WaitForChild("EconomyConfig"))

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
-- O fecho do combo (C): o mesmo Corte, um pouco maior.
local FINISHER_SCALE = 1.15
-- Auto Click: um golpe visual por tick do servidor.
local AUTO_INTERVAL = 1 / EconomyConfig.AutoClick.TicksPerSecond

local SlashController = {}

local pool: { BasePart } = {}
local poolIndex = 0
local lastAt = 0
local lastCutAt = 0
local lastManualAt = -math.huge
local nextAutoAt = 0
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

--[[
	Cada variação do golpe: inclinação do risco (graus em torno do olhar;
	positivo = topo para a ESQUERDA de quem olha por trás), sentido em que ele
	varre enquanto some e para que lado (studs) ele nasce.
	A "/" direita→esquerda, B "\" esquerda→direita, C vertical no centro.
]]
local VARIANTS: { [string]: { Roll: number, Sweep: number, Side: number } } = {
	A = { Roll = -45, Sweep = 1, Side = -0.5 },
	B = { Roll = 45, Sweep = -1, Side = 0.5 },
	C = { Roll = 0, Sweep = 1, Side = 0 },
}
local ROLL_JITTER = 8

function SlashController.VariantInfo(variant: string): { Roll: number, Sweep: number, Side: number }?
	return VARIANTS[variant]
end

local function draw(variant: string?)
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		return
	end
	local now = os.clock()
	-- Sem golpe (personagem montando): inclinação variada, como antes.
	local info = if variant then VARIANTS[variant] else nil
	local roll = if info then info.Roll + math.random(-ROLL_JITTER, ROLL_JITTER)
		else math.random(25, 65) * (if math.random() < 0.5 then 1 else -1)
	local side = if info then info.Side else 0
	local finisher = variant == "C"
	local scale = if finisher then FINISHER_SCALE else 1

	poolIndex = (poolIndex % POOL_SIZE) + 1
	local arc = pool[poolIndex]
	local sword = equippedSword()
	arc.Color = sword.ArcColor
	local arcScale = sword.ArcScale * scale
	arc.CFrame = root.CFrame
		* CFrame.new(side + math.random(-4, 4) / 10, 0.4, -ARC_DISTANCE)
		* CFrame.Angles(0, 0, math.rad(roll))
	arc.Transparency = 0.25
	arc.Size = ARC_SIZE * arcScale

	TweenService:Create(arc, TweenInfo.new(ARC_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Size = Vector3.new(
			ARC_SIZE.X * arcScale,
			ARC_SIZE.Y * arcScale * 1.5,
			ARC_SIZE.Z * arcScale * 0.4
		),
	}):Play()

	local recipe = CutVisuals.ForBest(Players.LocalPlayer:GetAttribute("BestCut"))
	if now - lastCutAt >= CUT_MIN_INTERVAL then
		lastCutAt = now
		local origin = root.CFrame * CFrame.new(side + math.random(-3, 3) / 10, 0.4, -ARC_DISTANCE - 0.3)
		-- O Corte tem a própria inclinação (1 risco = 45°): soma para cair na do golpe.
		CutFx.Play(cutRig, recipe, origin, scale, roll - 45, if info then info.Sweep else 1)
	end
	-- No mesmo instante: o impacto na barreira (se o golpe acertou uma).
	CombatFxController.OnSwingImpact(recipe, variant)
end

--[[
	Um hit do jogador local: o personagem golpeia (SwordSwingController) e, no
	momento do impacto do golpe, o arco da espada e o corte (CutFx) aparecem.
	Seguro a cada clique: limita a própria frequência e reusa as peças.
	"Efeitos reduzidos" tira o arco e o corte, mas NÃO o golpe da espada nem
	a indicação básica do impacto (o flash no ponto de contato).
]]
function SlashController.Play(auto: boolean?)
	local now = os.clock()
	if not auto then
		lastManualAt = now
	end
	local impact, variant = SwordSwingController.Swing()
	local settings = DataController.Get("Settings")
	if settings and settings.ReducedEffects == true then
		if impact > 0 then
			task.delay(impact, CombatFxController.OnSwingImpact, nil, variant)
		else
			CombatFxController.OnSwingImpact(nil, variant)
		end
		return
	end
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

--[[
	Um quadro do golpe automático (exposto para os testes): com o Auto Click
	ligado e o jogador sem clicar, um golpe por tick do servidor.
]]
function SlashController.StepAuto(at: number)
	if Players.LocalPlayer:GetAttribute("AutoClickOn") ~= true then
		nextAutoAt = at
		return
	end
	if at - lastManualAt < AUTO_INTERVAL then
		nextAutoAt = at + AUTO_INTERVAL -- clicando: os golpes manuais já aparecem
		return
	end
	if at >= nextAutoAt then
		-- Ritmo fixo; depois de uma pausa longa recomeça daqui (sem rajada).
		nextAutoAt = if at - nextAutoAt > AUTO_INTERVAL then at + AUTO_INTERVAL else nextAutoAt + AUTO_INTERVAL
		SlashController.Play(true)
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

function SlashController.Start()
	RunService.Heartbeat:Connect(function()
		SlashController.StepAuto(os.clock())
	end)
end

return SlashController
