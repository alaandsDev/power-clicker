--!strict
--[[
	CutShowcaseController
	A vitrine dos pads de Corte: em cada estação um ORBE de energia (não uma
	espada — espada é skin cosmética; o corte é dano) e, de tempos em tempos,
	a demonstração do corte: o MESMO efeito do golpe (CutVisuals + CutFx), em
	escala menor. Mudou a cor no CutConfig, mudam golpe e vitrine juntos.

	A placa de cada estação (CutCard_<id>, construída pelo WorldBuilder) recebe
	aqui bônus, requisito e o estado DESTE jogador:
	  ★ ATIVO      o melhor corte que ele tem — o que está dando dano agora
	               (corte não se equipa: possuir é usar, ver CutLogic.State);
	  ✔ COMPRADO   já tem, mas um melhor está ativo;
	  DISPONÍVEL   vitórias suficientes (contorno na cor do corte);
	  🔒 BLOQUEADO faltam vitórias (orbe e demonstração apagados, cinza).

	Só visual. Nada aqui compra, concede ou muda dano: a compra é o
	ProximityPrompt do pad, decidida no servidor (CutService.CanBuy). O
	cliente só esconde o "Comprar" de quem já tem o corte.

	Performance:
	- um único laço de 0,25 s (nada por frame) decide qual estação toca;
	- cada estação toca no máximo uma demonstração por vez e espera 1,5–3 s
	  depois que ela some;
	- demonstração só a até Layout.ShowcaseDistance do personagem; além de
	  Layout.ShowcaseKeepDistance as peças do efeito são apagadas (Destroy) e
	  recriadas ao voltar; com "Efeitos reduzidos" não toca nada;
	- faíscas são um Emit curto (no máximo CutVisuals.MAX_SPARKS), nunca um
	  emissor ligado.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local CutConfig = require(Shared:WaitForChild("Config"):WaitForChild("CutConfig"))
local CutLogic = require(Shared:WaitForChild("Formulas"):WaitForChild("CutLogic"))
local CutVisuals = require(Shared:WaitForChild("Formulas"):WaitForChild("CutVisuals"))
local NumberFormat = require(Shared:WaitForChild("Utils"):WaitForChild("NumberFormat"))
local Text = require(Shared:WaitForChild("Localization"))

local CutFx = require(script.Parent.Parent.Effects.CutFx)
local Theme = require(script.Parent.Parent.UI.Theme)
local DataController = require(script.Parent.DataController)

local SCAN_RETRY_SECONDS = 1
local TICK_SECONDS = 0.25
local SHOWCASE_SCALE = 0.55 -- o efeito do golpe, encolhido para caber no pedestal
local PAUSE_MIN = 1.5
local PAUSE_MAX = 3
local ORB_SIZE = 1.6
local CARD_PIXELS_PER_STUD = 60
local NAME_SIZE = Vector2.new(6, 1.3) -- studs

local STATE_COLORS = {
	Active = Theme.Colors.Power,
	Owned = Theme.Colors.Good,
	Available = Theme.Colors.Text,
	Locked = Theme.Colors.Disabled,
}

type Station = {
	CutId: string,
	Order: number,
	Anchor: BasePart,
	Card: BasePart?,
	Prompt: ProximityPrompt?,
	Orb: BasePart,
	NameGui: BillboardGui,
	NameLabel: TextLabel,
	CardGui: SurfaceGui?,
	Bonus: TextLabel?,
	Need: TextLabel?,
	Status: TextLabel?,
	StatusBar: Frame?,
	Stroke: UIStroke?,
	State: CutLogic.CutState,
	Rig: CutFx.Rig?,
	NextAt: number,
	Plays: number,
}

local CutShowcaseController = {}

local stations: { Station } = {}
local folder: Folder? = nil
local scanned = false
local started = false
local rng = Random.new()

local function label(parent: Instance, font: Enum.Font, color: Color3, y: number, height: number): TextLabel
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Font = font
	text.TextScaled = true
	text.TextColor3 = color
	text.TextStrokeTransparency = 0.4
	text.Position = UDim2.fromScale(0.05, y)
	text.Size = UDim2.fromScale(0.9, height)
	text.Parent = parent
	return text
end

local function playerGui(): Instance
	return Players.LocalPlayer:WaitForChild("PlayerGui")
end

-- Placa (SurfaceGui no PlayerGui: o texto depende de cada jogador).
local function buildCard(station: Station, card: BasePart)
	local cut = CutConfig.Cuts[station.CutId]
	local gui = Instance.new("SurfaceGui")
	gui.Name = "CutCard_" .. station.CutId
	gui.Face = Enum.NormalId.Front
	gui.Adornee = card
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = CARD_PIXELS_PER_STUD
	gui.LightInfluence = 0
	gui.MaxDistance = CutConfig.Layout.CardReadDistance
	gui.ResetOnSpawn = false

	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = Theme.Colors.Background
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(1, 1)
	frame.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = cut.Color
	stroke.Transparency = 1
	stroke.Parent = frame

	-- Faixa na cor do corte: liga a placa ao orbe acima dela.
	local stripe = Instance.new("Frame")
	stripe.BackgroundColor3 = cut.Color
	stripe.BorderSizePixel = 0
	stripe.Size = UDim2.fromScale(1, 0.08)
	stripe.Parent = frame

	station.Bonus = label(frame, Theme.FontDisplay, Theme.Colors.Text, 0.12, 0.36)
	station.Need = label(frame, Theme.Font, Theme.Colors.Power, 0.5, 0.2)

	local bar = Instance.new("Frame")
	bar.BorderSizePixel = 0
	bar.BackgroundColor3 = Theme.Colors.Panel
	bar.Position = UDim2.fromScale(0.15, 0.74)
	bar.Size = UDim2.fromScale(0.7, 0.2)
	bar.Parent = frame
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.4, 0)
	corner.Parent = bar
	local status = label(bar, Theme.FontDisplay, Theme.Colors.Text, 0, 1)
	status.Position = UDim2.fromScale(0.04, 0.05)
	status.Size = UDim2.fromScale(0.92, 0.9)

	station.Status = status
	station.StatusBar = bar
	station.Stroke = stroke
	station.CardGui = gui
	gui.Parent = playerGui()
end

local function buildStation(anchor: BasePart, cutId: string, world: Instance)
	local cut = CutConfig.Cuts[cutId]
	local parent = folder :: Folder

	local orb = Instance.new("Part")
	orb.Name = "CutOrb_" .. cutId
	orb.Shape = Enum.PartType.Ball
	orb.Size = Vector3.new(ORB_SIZE, ORB_SIZE, ORB_SIZE)
	orb.CFrame = anchor.CFrame
	orb.Anchored = true
	orb.CanCollide = false
	orb.CanQuery = false
	orb.CanTouch = false
	orb.CastShadow = false
	orb.Material = Enum.Material.Neon
	orb.Color = cut.Color
	orb.Parent = parent

	-- Nome logo acima do orbe, curto e só de perto.
	local nameGui = Instance.new("BillboardGui")
	nameGui.Name = "CutName_" .. cutId
	nameGui.Adornee = anchor
	nameGui.Size = UDim2.fromScale(NAME_SIZE.X, NAME_SIZE.Y)
	nameGui.StudsOffset = Vector3.new(0, ORB_SIZE / 2 + NAME_SIZE.Y / 2 + 0.4, 0)
	nameGui.MaxDistance = CutConfig.Layout.NameReadDistance
	nameGui.LightInfluence = 0
	nameGui.ResetOnSpawn = false
	local nameLabel = label(nameGui, Theme.FontDisplay, cut.Color, 0, 1)
	nameLabel.Position = UDim2.fromScale(0, 0)
	nameLabel.Size = UDim2.fromScale(1, 1)
	nameLabel.TextStrokeTransparency = 0.1
	nameLabel.Text = Text.Get("cut." .. cutId .. ".name")
	nameGui.Parent = playerGui()

	local pad = world:FindFirstChild("CutPad_" .. cutId, true)
	local station: Station = {
		CutId = cutId,
		Order = cut.Order,
		Anchor = anchor,
		Card = nil,
		Prompt = if pad then pad:FindFirstChildOfClass("ProximityPrompt") else nil,
		Orb = orb,
		NameGui = nameGui,
		NameLabel = nameLabel,
		State = "Locked",
		Rig = nil,
		-- Escalonado: as estações não disparam todas juntas.
		NextAt = 0,
		Plays = 0,
	}
	local card = world:FindFirstChild("CutCard_" .. cutId, true)
	if card and card:IsA("BasePart") then
		station.Card = card
		buildCard(station, card)
	end
	table.insert(stations, station)
end

local function requirementText(cutId: string): string
	local cut = CutConfig.Cuts[cutId]
	if cut.Price == 0 then
		return Text.Get("cut.card.starter")
	end
	if cut.RequiredWins <= 0 then
		return Text.Get("cut.card.needPower", { price = NumberFormat.Short(cut.Price) })
	end
	return Text.Get("cut.card.need", {
		price = NumberFormat.Short(cut.Price),
		wins = NumberFormat.Short(cut.RequiredWins),
	})
end

-- A receita que a vitrine toca: a do golpe real; apagada se bloqueado.
function CutShowcaseController.RecipeFor(cutId: string, state: CutLogic.CutState): CutVisuals.Recipe
	local recipe = CutVisuals.For(cutId) :: CutVisuals.Recipe
	return if state == "Locked" then CutVisuals.Locked(recipe) else recipe
end

local function applyState(station: Station, state: CutLogic.CutState)
	station.State = state
	local cut = CutConfig.Cuts[station.CutId]
	local locked = state == "Locked"
	local look = CutShowcaseController.RecipeFor(station.CutId, state)
	station.Orb.Color = look.Color
	station.Orb.Material = if locked then Enum.Material.SmoothPlastic else Enum.Material.Neon
	station.Orb.Transparency = if locked then 0.35 else 0
	station.NameLabel.TextColor3 = look.Color

	if station.Bonus then
		(station.Bonus :: TextLabel).Text = Text.Get("cut.card.bonus", { flat = NumberFormat.Short(cut.Flat) });
		(station.Bonus :: TextLabel).TextColor3 = if locked then Theme.Colors.TextDim else Theme.Colors.Text
	end
	if station.Need then
		(station.Need :: TextLabel).Text = requirementText(station.CutId);
		(station.Need :: TextLabel).TextColor3 = if locked then Theme.Colors.Bad else Theme.Colors.Power
	end
	if station.Status and station.StatusBar then
		(station.Status :: TextLabel).Text = Text.Get("cut.state." .. state);
		(station.StatusBar :: Frame).BackgroundColor3 = if state == "Available" then cut.Color:Lerp(Theme.Colors.Panel, 0.45) else Theme.Colors.Panel;
		(station.Status :: TextLabel).TextColor3 = STATE_COLORS[state]
	end
	if station.Stroke then
		-- Destaque discreto só no que dá para comprar agora.
		(station.Stroke :: UIStroke).Transparency = if state == "Available" then 0 else 1
	end
	if station.Prompt then
		-- Esconde "Comprar" de quem já tem (local; o servidor recusaria igual).
		(station.Prompt :: ProximityPrompt).Enabled = state ~= "Active" and state ~= "Owned"
	end
end

-- Recalcula o estado de todas as estações a partir dos dados do jogador.
function CutShowcaseController.Refresh()
	local cuts = DataController.Get("Cuts")
	local currencies = DataController.Get("Currencies")
	local wins = if type(currencies) == "table" then currencies.Wins else 0
	for _, station in stations do
		applyState(station, CutLogic.State(cuts, station.CutId, wins))
	end
end

local function reducedEffects(): boolean
	local settings = DataController.Get("Settings")
	return settings ~= nil and settings.ReducedEffects == true
end

--[[
	Um passo do laço (exposto para os testes). `position` é o personagem
	local (nil = sem personagem: nada toca e os efeitos são apagados).
]]
function CutShowcaseController.Tick(now: number, position: Vector3?, reduced: boolean)
	local layout = CutConfig.Layout
	for _, station in stations do
		local distance = if position then (station.Anchor.CFrame.Position - position).Magnitude else math.huge
		if reduced or distance > layout.ShowcaseKeepDistance then
			if station.Rig then
				CutFx.Destroy(station.Rig :: CutFx.Rig)
				station.Rig = nil
			end
		elseif distance <= layout.ShowcaseDistance and now >= station.NextAt then
			if not station.Rig then
				station.Rig = CutFx.NewRig("Showcase_" .. station.CutId, folder :: Folder, 1)
			end
			local recipe = CutShowcaseController.RecipeFor(station.CutId, station.State)
			-- Na frente do orbe, cortando na direção de quem olha da avenida.
			CutFx.Play(station.Rig :: CutFx.Rig, recipe, station.Anchor.CFrame * CFrame.new(0, 0, -(ORB_SIZE / 2 + 0.3)), SHOWCASE_SCALE, 0)
			station.Plays += 1
			station.NextAt = now + recipe.FadeSeconds + PAUSE_MIN + rng:NextNumber() * (PAUSE_MAX - PAUSE_MIN)
		end
	end
end

function CutShowcaseController.Stations(): { Station }
	return stations
end

local function scan(): boolean
	local map = Workspace:FindFirstChild("Map")
	if not map then
		return false
	end
	local anchors: { [string]: BasePart } = {}
	local world: Instance? = nil
	for _, descendant in map:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:GetAttribute("CutShowcase") == true then
			local cutId = descendant:GetAttribute("CutId")
			if type(cutId) == "string" and CutConfig.Cuts[cutId] and not anchors[cutId] then
				anchors[cutId] = descendant
				world = descendant.Parent
			end
		end
	end
	if not world then
		return false
	end
	for _, cut in CutLogic.Ordered() do
		local anchor = anchors[cut.Id]
		if anchor then
			buildStation(anchor, cut.Id, world :: Instance)
		end
	end
	for index, station in stations do
		station.NextAt = os.clock() + index * 0.4
	end
	return #stations > 0
end

local function characterPosition(): Vector3?
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root.CFrame.Position else nil
end

function CutShowcaseController.Init()
	local effects = Instance.new("Folder")
	effects.Name = "CutShowcase"
	effects.Parent = Workspace.CurrentCamera or Workspace
	folder = effects
end

function CutShowcaseController.Start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		while not scanned do
			scanned = scan()
			if not scanned then
				task.wait(SCAN_RETRY_SECONDS)
			end
		end
		CutShowcaseController.Refresh()
		-- Conectado UMA vez: a vitrine vive o jogo inteiro.
		DataController.Changed:Connect(function(key: string)
			if key == "Cuts" or key == "Currencies" then
				CutShowcaseController.Refresh()
			end
		end)
		Players.LocalPlayer:GetAttributeChangedSignal("BestCut"):Connect(CutShowcaseController.Refresh)
		while true do
			task.wait(TICK_SECONDS)
			CutShowcaseController.Tick(os.clock(), characterPosition(), reducedEffects())
		end
	end)
end

return CutShowcaseController
