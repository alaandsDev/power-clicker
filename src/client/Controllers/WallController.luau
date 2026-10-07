--!strict
--[[
	WallController
	As barreiras do Caminho do Poder COMO ELAS SÃO PARA ESTE JOGADOR. Cada
	jogador tem o próprio caminho: o servidor (WallService) guarda o HP de cada
	fileira por jogador e manda a este cliente só o estado dele (WallState).

	As peças das fileiras no Workspace são compartilhadas e ficam sempre
	inteiras e sólidas no servidor. Aqui, e só neste cliente, a fileira que
	ESTE jogador quebrou some e deixa de colidir (propriedades locais, que não
	replicam): a física do personagem roda no cliente dono dele, então ele
	atravessa e os outros continuam batendo na fileira inteira. Se a peça sair
	e voltar pelo streaming, o estado é aplicado de novo.

	Também desenha a PLACA DE HP da barreira à frente do jogador (nome, barra,
	HP e fileiras), o flash dos golpes, os estilhaços e o aviso
	"BARREIRA N DESTRUÍDA!".

	Placa de HP (Fase 0 do Caminho do Poder): presa à FACE da barreira, não
	ao topo — a 1,5 stud na frente dela e a 7,5 studs do chão, a mesma altura
	da barreira 1 ao Colosso, seguindo o lado em que o jogador está.
	(Ver PLATE_FLOOR_HEIGHT: 7,5 studs, medido contra a HUD real.) Assim a
	câmera normal de 3ª pessoa sempre enxerga o HP. Só a barreira à frente
	do jogador (até 70 studs) mostra a placa; as outras ficam desligadas.

	Colosso: a placa dele ganha UMA linha a mais, discreta, com o estado do
	jogador ("🔴 DESAFIO EXTREMO ≈10,5K golpes/fileira"; curta no
	celular), calculado em ProgressionUx com o HP da fileira e o MESMO ⚔ da
	HUD (GameStateController.GetHitDamage). É só informação: não muda HP, não
	bloqueia nada. Subir de estado mostra um aviso curto, uma vez por estado
	por sessão. Cada cliente calcula o seu (o dano é de cada jogador).

	Nada aqui decide nada: HP, abertura, janela e vitórias são do WallService,
	que também confere a posição de quem tenta atravessar sem ter quebrado.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local NumberFormat = require(Shared:WaitForChild("Utils"):WaitForChild("NumberFormat"))
local Signal = require(Shared:WaitForChild("Utils"):WaitForChild("Signal"))
local WallConfig = require(Shared:WaitForChild("Config"):WaitForChild("WallConfig"))
local WinPadRules = require(Shared:WaitForChild("Formulas"):WaitForChild("WinPadRules"))
local ProgressionUx = require(Shared:WaitForChild("Formulas"):WaitForChild("ProgressionUx"))
local HitDisplay = require(Shared:WaitForChild("Formulas"):WaitForChild("HitDisplay"))
local Text = require(Shared:WaitForChild("Localization"))

local SwordConfig = require(Shared:WaitForChild("Config"):WaitForChild("SwordConfig"))

local Theme = require(script.Parent.Parent.UI.Theme)
local Build = require(script.Parent.Parent.UI.Build)
local Anim = require(script.Parent.Parent.UI.Anim)
local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local SoundController = require(script.Parent.SoundController)
local NotificationController = require(script.Parent.NotificationController)
local HudController = require(script.Parent.HudController)
local DataController = require(script.Parent.DataController)
local GameStateController = require(script.Parent.GameStateController)
local UIController = require(script.Parent.UIController)

type Sign = {
	Gui: BillboardGui,
	Name: TextLabel,
	Bar: Frame,
	BarFill: Frame,
	Trail: Frame,
	BarText: TextLabel,
	Pips: { Frame },
	-- Rastro do HP perdido: de onde a barra saiu e quando.
	Shown: number,
	TrailFrom: number,
	TrailAt: number,
	Row: BasePart?,
	-- Só a placa do Colosso: a linha do estado do jogador.
	Readiness: TextLabel?,
	ReadinessText: string?,
}

-- Placa de HP: tamanho em studs (encolhe com a distância como as outras
-- placas do mundo) + um mínimo em pixels para continuar legível no celular.
local PLATE_WIDTH = 10
local PLATE_HEIGHT = 3
local PLATE_MIN_PIXELS = Vector2.new(60, 18)
--[[
	Onde ela fica: altura FIXA do chão (não depende da altura da barreira),
	um pouco à frente da face, acompanhando o lado do jogador.
	7,5 e não 9,5 (o valor da proposta): medido com a câmera de 3ª pessoa
	(8 / 12,5 / 28 studs) em 1920x1080, 1366x768, tablet e celular, a 9,5 a
	placa subia até a coluna do topo da HUD (moedas, faixa do corredor) nas
	câmeras próxima e padrão; a 7,5 ela fica entre essa coluna e a cabeça do
	personagem em todos os casos (check_power_hud).
]]
local PLATE_FLOOR_HEIGHT = 7.5
local PLATE_FRONT = 1.5
local PLATE_EDGE_MARGIN = 10
local PLATE_MAX_DISTANCE = 70
--[[
	Colosso: a linha do estado acrescenta só isto à altura da placa
	(studs/pixels) e as linhas de dentro ficam um pouco mais baixas. Medido
	(check_progression_ux): na câmera próxima do celular a placa normal já
	sobra só ~10 px entre a coluna do topo da HUD e a cabeça; +0,2 stud e
	+2 px cabem, +0,25 já encosta.
]]
local READINESS_HEIGHT = 0.2
local READINESS_PIXELS = 2
-- Posição/altura (escala da placa) de nome, barra, fileiras e linha do estado.
local LAYOUT = {
	Normal = { Name = { 0.04, 0.34 }, Bar = { 0.42, 0.36 }, Pips = { 0.83, 0.1 } },
	Colossus = { Name = { 0.03, 0.27 }, Bar = { 0.33, 0.28 }, Pips = { 0.645, 0.065 }, Line = { 0.735, 0.235 } },
}
-- Abaixo desta largura de tela o texto do estado usa a forma curta.
local COMPACT_VIEWPORT = 900
-- Feedback: rastro do HP perdido, HP baixo e crítico.
local TRAIL_SECONDS = 0.25
local LOW_FRACTION = 0.25
local CRITICAL_FRACTION = 0.1
local COLOR_OK = Color3.fromRGB(90, 210, 120)
local COLOR_LOW = Color3.fromRGB(255, 176, 64)
local COLOR_CRITICAL = Color3.fromRGB(240, 92, 72)
local COLOR_TRAIL = Color3.fromRGB(255, 236, 200)
local SCAN_RETRY_SECONDS = 1
-- A superfície da fileira pisca quando toma dano (com teto de frequência). O
-- resto do impacto, as rachaduras e a quebra são do CombatFxController, que
-- escuta os sinais abaixo.
local HIT_FLASH_SECONDS = 0.08
local HIT_MIN_INTERVAL = 0.09
-- Anúncio "BARREIRA N DESTRUÍDA!": curto, no topo, não bloqueia nada.
local BANNER_SECONDS = 2.6

local WallController = {
	-- Eventos das fileiras DESTE jogador (vindos do WallState próprio):
	-- (row, stageId, hpAntes, hpDepois) quando toma dano e continua de pé.
	RowDamaged = Signal.new() :: Signal.Signal<BasePart, string, number, number>,
	-- (row, stageId, final) quando cai; final = era a última fileira de pé.
	RowBroken = Signal.new() :: Signal.Signal<BasePart, string, boolean>,
	-- (row, stageId) quando volta inteira (a barreira se refez).
	RowRestored = Signal.new() :: Signal.Signal<BasePart, string>,
}

-- Para os testes e para o mock de câmera.
WallController.PLATE_FLOOR_HEIGHT = PLATE_FLOOR_HEIGHT
WallController.PLATE_FRONT = PLATE_FRONT
WallController.PLATE_MAX_DISTANCE = PLATE_MAX_DISTANCE
WallController.PLATE_SIZE = Vector2.new(PLATE_WIDTH, PLATE_HEIGHT)
WallController.PLATE_MIN_PIXELS = PLATE_MIN_PIXELS

export type StageView = { Hp: { number }, Open: boolean }

-- rowsByStage[stageId][row] = peça (substituída se o streaming trocar a peça).
local rowsByStage: { [string]: { [number]: BasePart } } = {}
-- O estado deste jogador (WallState). Estágio sem entrada = inteiro.
local views: { [string]: StageView } = {}
local signs: { [string]: Sign } = {}
local scanned = false
local lastHitAt: { [BasePart]: number } = {}
local banner: TextLabel
local bannerStamp = 0
local objectiveChip: TextLabel
local colossusNotice = ProgressionUx.NewColossusNotice()
-- Pads de vitória (placa reescrita com o valor deste jogador) e, por estágio,
-- até quando vale a "primeira conquista" que acabou de acontecer.
local winPads: { BasePart } = {}
local firstClearUntil: { [string]: number } = {}
-- Quanto o pad some quando a barreira dele não está aberta para este jogador.
local PAD_CLOSED_FADE = 0.6

local function stageOrder(stageId: string): number
	for _, stage in WallConfig.Stages do
		if stage.Id == stageId then
			return stage.Order
		end
	end
	return 0
end

local function stageName(stageId: string): string
	local key = "wall." .. stageId .. ".name"
	local value = Text.Get(key)
	if value ~= key then
		return value
	end
	for _, stage in WallConfig.Stages do
		if stage.Id == stageId then
			return stage.DisplayName
		end
	end
	return stageId
end

local function swordColor(): Color3
	local swordId = Players.LocalPlayer:GetAttribute("EquippedSword")
	local sword = if type(swordId) == "string" then SwordConfig.Swords[swordId] else nil
	return if sword then sword.ArcColor else Color3.new(1, 1, 1)
end

local function stageOfId(stageId: any): WallConfig.WallStage?
	for _, stage in WallConfig.Stages do
		if stage.Id == stageId then
			return stage
		end
	end
	return nil
end

--[[
	(hp, maxHp, quebrada) da fileira PARA ESTE JOGADOR. Sem estado recebido,
	a fileira está inteira.
]]
function WallController.RowState(row: BasePart): (number, number, boolean)
	local stageId = row:GetAttribute("StageId")
	local index = row:GetAttribute("Row")
	local stage = stageOfId(stageId)
	local maxHp = if stage then stage.Hp else (tonumber(row:GetAttribute("MaxHp")) or 0)
	local view = if type(stageId) == "string" then views[stageId] else nil
	local hp = if view and type(index) == "number" then view.Hp[index] else nil
	if type(hp) ~= "number" then
		hp = maxHp
	end
	return hp :: number, maxHp, (hp :: number) <= 0
end

-- As fileiras do corredor, por estágio e número (para a faixa do corredor).
function WallController.Rows(): { [string]: { [number]: BasePart } }
	return rowsByStage
end

--[[
	Aparência e colisão LOCAIS da fileira: quebrada para este jogador = some,
	sem colisão, sem luz, detalhes escondidos. Só mexe quando difere, então
	pode rodar a cada quadro (e reaplica se o streaming trouxer a peça de novo).
]]
local function applyRow(row: BasePart, broken: boolean)
	local wantCollide = not broken
	local wantTransparency = if broken then 1 else 0
	if row.CanCollide == wantCollide and row.Transparency == wantTransparency then
		return
	end
	row.CanCollide = wantCollide
	row.Transparency = wantTransparency
	if not broken then
		row.LocalTransparencyModifier = 0
	end
	for _, child in row:GetChildren() do
		if child:IsA("BasePart") and child:GetAttribute("WallDetail") == true then
			local base = child:GetAttribute("BaseTransparency")
			child.Transparency = if broken then 1 else (if type(base) == "number" then base else 0)
		elseif child:IsA("Light") then
			child.Enabled = not broken
		end
	end
end

--[[
	O ponto da face da fileira em que um golpe de quem está em `position` bate
	(a face voltada para a praça, na altura do peito, alinhado ao jogador).
]]
function WallController.ContactPoint(row: BasePart, position: Vector3): Vector3
	local half = row.Size / 2
	return Vector3.new(
		row.Position.X - half.X - 0.3,
		math.clamp(position.Y + 1, row.Position.Y - half.Y + 1, row.Position.Y + half.Y - 1),
		math.clamp(position.Z, row.Position.Z - half.Z + 1, row.Position.Z + half.Z - 1)
	)
end

--[[
	A fileira que um golpe de quem está em `position` acerta AGORA, pela mesma
	regra do servidor: de pé para este jogador, À FRENTE dele e a até
	WallConfig.HitRange. Só para o efeito do impacto sair junto com o golpe; o
	dano de verdade continua sendo decidido no servidor.
]]
function WallController.TargetRow(position: Vector3): BasePart?
	local best: BasePart? = nil
	local bestDistance = WallConfig.HitRange
	for _, rows in rowsByStage do
		for _, row in rows do
			if row.Parent and position.X < row.Position.X then
				local _, _, broken = WallController.RowState(row)
				local distance = (row.Position - position).Magnitude
				if not broken and distance <= bestDistance then
					best, bestDistance = row, distance
				end
			end
		end
	end
	return best
end

-- A superfície reage ao dano: um flash curto na cor da espada (cosmético).
local function flashSurface(row: BasePart)
	local now = os.clock()
	if now - (lastHitAt[row] or 0) < HIT_MIN_INTERVAL then
		return
	end
	lastHitAt[row] = now
	local flash = swordColor()
	local original = row.Color
	row.Color = original:Lerp(flash, 0.5)
	task.delay(HIT_FLASH_SECONDS, function()
		if row.Parent then
			row.Color = original
		end
	end)
end

--[[
	Onde a placa de HP fica para quem está em `position`: 1,5 stud à frente
	da face da fileira, a 7,5 studs do chão (o pé da fileira), e no Z do
	jogador limitado à largura da barreira. Não depende da altura da barreira:
	o Colosso (48 de altura) tem a placa na mesma altura de leitura da
	barreira 1 (30).
]]
function WallController.PlateAnchor(row: BasePart, position: Vector3?): Vector3
	local centre = row.CFrame.Position
	local half = row.Size / 2
	local reach = math.max(half.Z - PLATE_EDGE_MARGIN, 0)
	local z = if position then math.clamp(position.Z, centre.Z - reach, centre.Z + reach) else centre.Z
	return Vector3.new(centre.X - half.X - PLATE_FRONT, centre.Y - half.Y + PLATE_FLOOR_HEIGHT, z)
end

local function createSign(stageId: string, row: BasePart): Sign
	local stage = stageOfId(stageId)
	local colossus = stageId == ProgressionUx.Colossus.StageId
	local extra = if colossus then READINESS_HEIGHT else 0
	local gui = Instance.new("BillboardGui")
	gui.Name = "WallSign"
	gui.Size = UDim2.new(PLATE_WIDTH, PLATE_MIN_PIXELS.X, PLATE_HEIGHT + extra, PLATE_MIN_PIXELS.Y + (if colossus then READINESS_PIXELS else 0))
	gui.MaxDistance = PLATE_MAX_DISTANCE
	-- Só a placa da barreira à frente fica ligada (refresh), então ela pode
	-- ficar por cima de tudo sem aparecer através das outras barreiras.
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Adornee = row
	gui.Enabled = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local back = Instance.new("Frame")
	back.Name = "Back"
	back.BackgroundColor3 = Color3.fromRGB(14, 16, 26)
	back.BackgroundTransparency = 0.35
	back.Size = UDim2.fromScale(1, 1)
	local layout = if colossus then LAYOUT.Colossus else LAYOUT.Normal
	back.Parent = gui
	local backCorner = Instance.new("UICorner")
	backCorner.CornerRadius = UDim.new(0.22, 0)
	backCorner.Parent = back
	local stroke = Instance.new("UIStroke")
	stroke.Color = if stage then stage.Accent else Color3.new(1, 1, 1)
	stroke.Thickness = 1.5
	stroke.Transparency = 0.2
	stroke.Parent = back

	local name = Instance.new("TextLabel")
	name.Name = "StageName"
	name.BackgroundTransparency = 1
	name.Font = Theme.FontDisplay
	name.TextScaled = true
	name.TextColor3 = Color3.new(1, 1, 1)
	name.TextStrokeTransparency = 0.3
	name.Position = UDim2.fromScale(0.05, layout.Name[1])
	name.Size = UDim2.fromScale(0.9, layout.Name[2])
	name.Parent = back

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.BackgroundColor3 = Color3.fromRGB(28, 30, 44)
	bar.BorderSizePixel = 0
	bar.Position = UDim2.fromScale(0.05, layout.Bar[1])
	bar.Size = UDim2.fromScale(0.9, layout.Bar[2])
	bar.ClipsDescendants = true
	bar.Parent = back
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.45, 0)
	corner.Parent = bar

	-- Rastro: o pedaço de HP que acabou de sair fica claro por ~0,25 s.
	local trail = Instance.new("Frame")
	trail.Name = "Trail"
	trail.BackgroundColor3 = COLOR_TRAIL
	trail.BorderSizePixel = 0
	trail.Size = UDim2.fromScale(1, 1)
	trail.Parent = bar

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = COLOR_OK
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(1, 1)
	fill.ZIndex = 2
	fill.Parent = bar

	local barText = Instance.new("TextLabel")
	barText.Name = "Hp"
	barText.BackgroundTransparency = 1
	barText.Font = Theme.FontDisplay
	barText.TextScaled = true
	barText.TextColor3 = Color3.new(1, 1, 1)
	barText.TextStrokeTransparency = 0.3
	barText.Size = UDim2.fromScale(1, 1)
	barText.ZIndex = 3
	barText.Parent = bar

	-- Fileiras: um ponto por fileira (as quebradas apagam).
	local pips = {}
	local count = if stage then stage.Rows else 1
	if count > 1 then
		local pipWidth = math.min(0.08, 0.6 / count)
		local gap = pipWidth * 0.5
		local total = count * pipWidth + (count - 1) * gap
		for index = 1, count do
			local pip = Instance.new("Frame")
			pip.Name = "Row" .. index
			pip.BackgroundColor3 = Color3.new(1, 1, 1)
			pip.BorderSizePixel = 0
			pip.Position = UDim2.fromScale(0.5 - total / 2 + (index - 1) * (pipWidth + gap), layout.Pips[1])
			pip.Size = UDim2.fromScale(pipWidth, layout.Pips[2])
			pip.Parent = back
			local pipCorner = Instance.new("UICorner")
			pipCorner.CornerRadius = UDim.new(0.5, 0)
			pipCorner.Parent = pip
			table.insert(pips, pip)
		end
	end

	local readiness: TextLabel? = nil
	if colossus then
		local line = Instance.new("TextLabel")
		line.Name = "Readiness"
		line.BackgroundTransparency = 1
		line.Font = Theme.FontDisplay
		line.TextScaled = true
		line.TextColor3 = COLOR_CRITICAL
		line.TextStrokeTransparency = 0.3
		line.Text = ""
		line.Position = UDim2.fromScale(0.08, LAYOUT.Colossus.Line[1])
		line.Size = UDim2.fromScale(0.84, LAYOUT.Colossus.Line[2])
		line.Parent = back
		readiness = line
	end

	return {
		Gui = gui,
		Name = name,
		Bar = bar,
		BarFill = fill,
		Trail = trail,
		BarText = barText,
		Pips = pips,
		Shown = 1,
		TrailFrom = 1,
		TrailAt = -math.huge,
		Row = nil,
		Readiness = readiness,
		ReadinessText = nil,
	}
end

local function reducedEffects(): boolean
	local settings = DataController.Get("Settings")
	return type(settings) == "table" and settings.ReducedEffects == true
end

export type ColossusReadout = {
	Level: ProgressionUx.ColossusLevel,
	StateHits: number, -- golpes para uma fileira CHEIA (define o estado)
	Hits: number, -- golpes para a fileira da frente (o "≈ N" mostrado)
	Damage: number,
	RowHp: number,
	RowMaxHp: number,
	Row: number,
}

--[[
	Estado do Colosso PARA ESTE JOGADOR: fileira da frente (de pé) e o ⚔ dano
	atual (o mesmo da HUD). nil se não há fileira do Colosso de pé por aqui.
	A faixa do corredor (CorridorHudController) lê daqui, então placa e faixa
	nunca mostram números diferentes.
]]
function WallController.ColossusReadout(): ColossusReadout?
	local stageId = ProgressionUx.Colossus.StageId
	local rows = rowsByStage[stageId]
	local stage = stageOfId(stageId)
	if not rows or not stage then
		return nil
	end
	for index = 1, stage.Rows do
		local row = rows[index]
		if row and row.Parent then
			local hp, maxHp, broken = WallController.RowState(row)
			if not broken then
				local damage = GameStateController.GetHitDamage()
				local level, stateHits = ProgressionUx.ColossusState(maxHp, damage)
				return {
					Level = level,
					StateHits = stateHits,
					Hits = HitDisplay.HitsFor(hp, damage),
					Damage = damage,
					RowHp = hp,
					RowMaxHp = maxHp,
					Row = index,
				}
			end
		end
	end
	return nil
end

-- Celular ou tela estreita: textos curtos.
function WallController.CompactLabels(): boolean
	if UIController.IsTouch() then
		return true
	end
	local camera = Workspace.CurrentCamera
	return camera ~= nil and camera.ViewportSize.X > 0 and camera.ViewportSize.X < COMPACT_VIEWPORT
end

local READINESS_COLORS: { [string]: Color3 } = {
	Extreme = COLOR_CRITICAL,
	Preparing = COLOR_LOW,
	Ready = COLOR_OK,
}

-- A linha do estado na placa do Colosso + o aviso ao subir de estado.
local function drawReadiness(sign: Sign)
	local line = sign.Readiness
	if not line then
		return
	end
	local readout = WallController.ColossusReadout()
	if not readout then
		line.Visible = false
		return
	end
	line.Visible = true
	local compact = WallController.CompactLabels()
	local text = Text.Get(if compact then "colossus.lineShort" else "colossus.line", {
		state = Text.Get(ProgressionUx.ColossusLabelKey(readout.Level, compact)),
		hits = if readout.Hits == math.huge then "—" else NumberFormat.Short(readout.Hits),
	})
	if text ~= sign.ReadinessText then
		sign.ReadinessText = text
		line.Text = text
		line.TextColor3 = READINESS_COLORS[readout.Level] or COLOR_CRITICAL
	end
	local crossed = colossusNotice:Update(readout.Level, readout.StateHits)
	if crossed then
		NotificationController.Show(Text.Get("colossus.notice." .. crossed), if crossed == "Ready" then "Good" else "Info")
	end
end

-- Desenha a placa com o HP da fileira da frente DESTE jogador.
local function drawSign(sign: Sign, stageId: string, front: BasePart, index: number, now: number)
	sign.Name.Text = string.format("%d · %s", stageOrder(stageId), stageName(stageId))
	local hp, maxHp = WallController.RowState(front)
	local fraction = if maxHp > 0 then math.clamp(hp / maxHp, 0, 1) else 1
	-- Fileira nova (a anterior caiu, ou a barreira se refez): sem rastro.
	if sign.Row ~= front then
		sign.Row = front
		sign.Shown = fraction
		sign.TrailFrom = fraction
		sign.TrailAt = -math.huge
	elseif fraction < sign.Shown then
		-- Golpe: a barra cai NA HORA; o rastro sai do valor anterior.
		sign.TrailFrom = math.max(sign.TrailFrom, sign.Shown)
		sign.TrailAt = now
		sign.Shown = fraction
	else
		sign.Shown = fraction
	end
	local progress = math.clamp((now - sign.TrailAt) / TRAIL_SECONDS, 0, 1)
	local trail = sign.TrailFrom + (fraction - sign.TrailFrom) * progress
	if progress >= 1 then
		sign.TrailFrom = fraction
	end
	sign.BarFill.Size = UDim2.fromScale(fraction, 1)
	sign.Trail.Size = UDim2.fromScale(math.max(trail, fraction), 1)
	local color = COLOR_OK
	if fraction <= CRITICAL_FRACTION then
		color = COLOR_CRITICAL
	elseif fraction <= LOW_FRACTION then
		color = COLOR_LOW
	end
	sign.BarFill.BackgroundColor3 = color
	-- Crítico: pulso leve no preenchimento (sem piscar a placa inteira).
	sign.BarFill.BackgroundTransparency = if fraction <= CRITICAL_FRACTION and not reducedEffects() then 0.18 * (1 + math.sin(now * 2 * math.pi * 1.6)) / 2 else 0
	sign.BarText.Text = NumberFormat.Short(math.max(hp, 0)) .. " / " .. NumberFormat.Short(maxHp)
	for pipIndex, pip in sign.Pips do
		pip.BackgroundTransparency = if pipIndex < index then 0.8 elseif pipIndex == index then 0 else 0.35
	end
	drawReadiness(sign)
	sign.Gui.Enabled = true
end

local function playerPosition(): Vector3?
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root.CFrame.Position else nil
end

local function refresh()
	local position = playerPosition()
	local now = os.clock()
	-- A barreira À FRENTE do jogador mais próxima: só ela mostra a placa.
	local chosen: string? = nil
	local chosenFront: BasePart? = nil
	local chosenIndex, chosenDistance = 0, PLATE_MAX_DISTANCE
	for stageId, rows in rowsByStage do
		-- Colisão/aparência locais de cada fileira, conforme o estado DESTE jogador.
		local front: BasePart? = nil
		local frontIndex = 0
		local stage = stageOfId(stageId)
		local count = if stage then stage.Rows else #rows
		for index = 1, count do
			local row = rows[index]
			if row and row.Parent then
				local _, _, broken = WallController.RowState(row)
				applyRow(row, broken)
				if not broken and front == nil then
					front, frontIndex = row, index
				end
			end
		end
		if front and position then
			local face = front.CFrame.Position.X - front.Size.X / 2
			local ahead = face - position.X
			if ahead > -2 and ahead <= chosenDistance then
				chosen, chosenFront, chosenIndex, chosenDistance = stageId, front, frontIndex, ahead
			end
		end
	end
	for stageId, sign in signs do
		if stageId ~= chosen or not chosenFront then
			if sign.Gui.Enabled then
				sign.Gui.Enabled = false
			end
			sign.Row = nil
			continue
		end
		local front = chosenFront :: BasePart
		sign.Gui.Adornee = front
		sign.Gui.StudsOffsetWorldSpace = WallController.PlateAnchor(front, position) - front.CFrame.Position
		drawSign(sign, stageId, front, chosenIndex, now)
	end
end

-- Para os testes: a placa de cada estágio (BillboardGui) e qual está ligada.
function WallController.Signs(): { [string]: Sign }
	return signs
end

function WallController.Refresh()
	refresh()
end

--[[
	Novo estado DESTE jogador vindo do servidor: golpe na fileira (flash e
	rachadura), fileira caindo (estilhaços) e barreira se refazendo.
]]
local function onWallState(payload: any)
	if type(payload) ~= "table" then
		return
	end
	for stageId, incoming in payload do
		if type(stageId) ~= "string" or type(incoming) ~= "table" or type(incoming.Hp) ~= "table" then
			continue
		end
		local stage = stageOfId(stageId)
		local previous = views[stageId]
		local rows = rowsByStage[stageId] or {}
		for index, hp in incoming.Hp do
			local before = if previous then previous.Hp[index] else (if stage then stage.Hp else hp)
			local row = rows[index]
			if row and type(hp) == "number" and type(before) == "number" then
				if hp <= 0 and before > 0 then
					row.LocalTransparencyModifier = 0
					SoundController.Play("WallBreak")
					local standing = 0
					for _, other in incoming.Hp do
						if type(other) == "number" and other > 0 then
							standing += 1
						end
					end
					WallController.RowBroken:Fire(row, stageId, standing == 0)
				elseif hp > 0 and hp < before and stage then
					flashSurface(row)
					WallController.RowDamaged:Fire(row, stageId, before, hp)
				elseif hp > before then
					row.LocalTransparencyModifier = 0
					WallController.RowRestored:Fire(row, stageId)
				end
			end
		end
		views[stageId] = { Hp = table.clone(incoming.Hp), Open = incoming.Open == true }
	end
	refresh()
end

local function addRow(descendant: Instance)
	if not descendant:IsA("BasePart") or descendant:GetAttribute("Wall") ~= true then
		return
	end
	local stageId = descendant:GetAttribute("StageId")
	local index = descendant:GetAttribute("Row")
	if type(stageId) ~= "string" or type(index) ~= "number" then
		return
	end
	local list = rowsByStage[stageId]
	if not list then
		list = {}
		rowsByStage[stageId] = list
	end
	list[index] = descendant
end

local function scan()
	local map = Workspace:FindFirstChild("Map")
	local worlds = if map then map:FindFirstChild("Worlds") else nil
	local world = if worlds then worlds:FindFirstChild(WallConfig.WorldId) else nil
	if not world then
		return
	end
	table.clear(rowsByStage)
	table.clear(winPads)
	for _, descendant in world:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:GetAttribute("WinPad") == true and descendant:GetAttribute("Return") ~= true then
			table.insert(winPads, descendant)
		end
		addRow(descendant)
	end
	for stageId, rows in rowsByStage do
		if not signs[stageId] and rows[1] then
			signs[stageId] = createSign(stageId, rows[1])
		end
	end
	scanned = next(rowsByStage) ~= nil
	if scanned then
		-- Streaming: uma fileira que volta é uma peça nova; ela entra no lugar
		-- da antiga e o próximo quadro aplica o estado deste jogador nela.
		world.DescendantAdded:Connect(addRow)
	end
end

--[[
	"BARREIRA N DESTRUÍDA!" para quem quebrou: estágio, gemas da primeira vez
	e para onde ir agora. Some sozinho em poucos segundos.
]]
local function showDestroyed(payload: any)
	local order = tonumber(payload.Order) or stageOrder(tostring(payload.StageId))
	local lines = { Text.Get("wall.destroyed", { order = tostring(order) }) }
	local gems = tonumber(payload.FirstClearGems) or 0
	if gems > 0 then
		table.insert(lines, Text.Get("wall.destroyedGems", { gems = NumberFormat.Short(gems), icon = Theme.Icons.Gems }))
	end
	local nextStage = WallConfig.Stages[order + 1]
	if nextStage then
		table.insert(lines, Text.Get("wall.destroyedNext", { next = tostring(nextStage.Order), name = stageName(nextStage.Id) }))
	else
		table.insert(lines, Text.Get("wall.destroyedLast"))
	end
	banner.Text = table.concat(lines, "\n")
	banner.Size = UDim2.fromOffset(470, 30 + 22 * (#lines - 1))
	banner.Visible = true
	Anim.PopIn(banner, 0.6, 0.3)
	SoundController.Play("Reward")
	bannerStamp += 1
	local stamp = bannerStamp
	task.delay(BANNER_SECONDS, function()
		if bannerStamp == stamp then
			banner.Visible = false
		end
	end)
end

local function stageOf(stageId: any): WallConfig.WallStage?
	for _, stage in WallConfig.Stages do
		if stage.Id == stageId then
			return stage
		end
	end
	return nil
end

--[[
	A placa de cada pad mostra o que ESTE jogador recebe se pisar nele agora
	(WinPadRules — a mesma conta do servidor): valor cheio na abertura da
	primeira conquista, fração de repetição depois. O pad x2 é sempre o dobro.
]]
local function refreshPads()
	local tower = DataController.Get("Tower")
	for _, pad in winPads do
		local stage = stageOf(pad:GetAttribute("StageId"))
		local gui = pad:FindFirstChildOfClass("BillboardGui")
		local label = if gui then gui:FindFirstChildOfClass("TextLabel") else nil
		if stage and label then
			--[[
				O pad só paga logo depois de ESTE jogador quebrar ESTA barreira
				(a janela de WallConfig.OpenSeconds). Fora dela a placa diz o que
				fazer e o pad fica apagado — antes ela mostrava o prêmio e o pad
				não pagava nada, o que parecia defeito.
			]]
			local view = views[stage.Id]
			local open = view ~= nil and view.Open
			pad.LocalTransparencyModifier = if open then 0 else PAD_CLOSED_FADE
			if open then
				local index = tonumber(pad:GetAttribute("PadIndex")) or WinPadRules.IndexOf(stage, tonumber(pad:GetAttribute("Wins")) or 0) or 1
				local firstClear = (firstClearUntil[stage.Id] or 0) > os.clock()
				local amount = WinPadRules.Payout(stage, index, WinPadRules.Share(stage, tower, firstClear))
				label.Text = Text.Get(if WinPadRules.IsDouble(stage, index) then "wall.padWinsDouble" else "wall.padWins", { amount = NumberFormat.Short(amount) })
			else
				label.Text = Text.Get("wall.padClosed", { order = tostring(stage.Order) })
			end
		end
	end
end

-- Objetivo até a primeira barreira cair: só no lobby (perto da barreira, a
-- faixa do corredor assume) e some de vez depois do primeiro estágio.
local function refreshObjective()
	local tower = DataController.Get("Tower")
	local highest = if type(tower) == "table" then tonumber(tower.Highest) or 0 else 0
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local inLobby = root ~= nil and root:IsA("BasePart") and root.Position.X < WallConfig.Layout.StartX + 40
	objectiveChip.Visible = DataController.IsLoaded() and highest < 1 and inLobby
end

function WallController.Init()
	banner = Build.label({
		Name = "WallBanner",
		Text = "",
		Font = Theme.FontDisplay,
		TextSize = 20,
		TextWrapped = true,
		TextColor3 = Theme.Colors.Power,
		BackgroundColor3 = Theme.Hud.Surface,
		BackgroundTransparency = 0.15,
		Size = UDim2.fromOffset(470, 30),
		Visible = false,
		ZIndex = 25,
		LayoutOrder = 1,
		Parent = HudController.GetTopStack(),
	})
	Build.corner(banner, UDim.new(0, 12))
	Build.textStroke(banner, 2)
	objectiveChip = Build.label({
		Name = "ObjectiveChip",
		Text = Text.Get("objective.firstBarrier"),
		TextSize = 16,
		BackgroundColor3 = Theme.Hud.Surface,
		BackgroundTransparency = 0.25,
		Size = UDim2.fromOffset(0, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		Visible = false,
		LayoutOrder = 6,
		Parent = HudController.GetTopStack(),
	})
	Build.corner(objectiveChip, UDim.new(1, 0))
	Build.new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), Parent = objectiveChip })
	task.spawn(function()
		while true do
			refreshObjective()
			refreshPads()
			task.wait(0.5)
		end
	end)

	ClientNet.On("WallState", onWallState)
	ClientNet.On("Notify", function(kind: any, payload: any)
		if type(payload) ~= "table" then
			return
		end
		if kind == "WinPad" then
			SoundController.Play("Reward")
			local share = tonumber(payload.Share) or 1
			if share < 1 then
				-- Repetição: diz quanto do prêmio cheio veio (WallConfig.Repeat).
				NotificationController.Show(Text.Get("wall.gotWinsRepeat", {
					amount = NumberFormat.Short(tonumber(payload.Wins) or 0),
					icon = Theme.Icons.Wins,
					percent = tostring(math.floor(share * 100 + 0.5)),
				}), "Good")
			else
				NotificationController.Show(Text.Get("wall.gotWins", {
					amount = NumberFormat.Short(tonumber(payload.Wins) or 0),
					icon = Theme.Icons.Wins,
				}), "Good")
			end
		elseif kind == "WinPadClosed" then
			NotificationController.Show(Text.Get("wall.padClosedHint", {
				order = tostring(tonumber(payload.Order) or stageOrder(tostring(payload.StageId))),
			}), "Info")
		elseif kind == "WallBroken" then
			-- Só chega para quem quebrou: a barreira dos outros continua inteira.
			if payload.ById == Players.LocalPlayer.UserId then
				if payload.FirstClear == true and type(payload.StageId) == "string" then
					firstClearUntil[payload.StageId] = os.clock() + (tonumber(payload.Seconds) or WallConfig.OpenSeconds)
				end
				refreshPads()
				showDestroyed(payload)
			end
		elseif kind == "TowerCleared" then
			-- As gemas da primeira vez entram no anúncio grande (WallBroken traz
			-- FirstClearGems); aqui só o som.
			SoundController.Play("Rebirth")
		elseif kind == "WallRow" then
			NotificationController.Show(Text.Get("wall.rowsLeft", {
				count = tostring(payload.Remaining or 0),
			}), "Info")
		end
	end)
end

function WallController.Start()
	task.spawn(function()
		while not scanned do
			scan()
			if not scanned then
				task.wait(SCAN_RETRY_SECONDS)
			end
		end
		-- Attributes change often while a wall is being broken; one cheap sweep
		-- per heartbeat is simpler (and lighter) than a listener per row.
		RunService.Heartbeat:Connect(refresh)
	end)
end

return WallController
