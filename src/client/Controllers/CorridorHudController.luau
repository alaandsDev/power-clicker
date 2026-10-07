--!strict
--[[
	CorridorHudController
	A faixa de informação do corredor: aparece quando o jogador está perto de
	uma barreira e some no lobby.

	Fase 0 do Caminho do Poder: o NOME e o HP da barreira ficam na placa
	presa à própria barreira (WallController). Esta faixa mostra só o que
	COMPLETA a placa, numa linha:
		seu golpe · ≈golpes que faltam · prêmio   (ou o aviso "forte demais")

	Também apresenta o estágio ao ENTRAR na área dele: "⚔ 7 · ROCHA
	VULCÂNICA" por ~1,5 s e some (no lugar da placa flutuante permanente
	"Estágio N — Nome" que havia no corredor).

	O HP é o das barreiras DESTE jogador (cada um tem o próprio caminho), lido
	do WallController, que recebe o estado do servidor; este controller não
	decide nada.

	Colosso (estágio 10): no lugar do aviso "forte demais" (que, com 10
	fileiras, disparava a partir de ~60 golpes por fileira — até para quem já
	está PRONTO), a faixa mostra "≈N golpes · 🟢 PRONTO", lido do
	WallController.ColossusReadout (o mesmo número da placa). Estágios 1–9
	continuam iguais.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local NumberFormat = require(Shared:WaitForChild("Utils"):WaitForChild("NumberFormat"))
local WallConfig = require(Shared:WaitForChild("Config"):WaitForChild("WallConfig"))
local CorridorLayout = require(Shared:WaitForChild("Formulas"):WaitForChild("CorridorLayout"))
local ProgressionUx = require(Shared:WaitForChild("Formulas"):WaitForChild("ProgressionUx"))
local Text = require(Shared:WaitForChild("Localization"))
local TextCase = require(Shared:WaitForChild("Utils"):WaitForChild("TextCase"))

local Theme = require(script.Parent.Parent.UI.Theme)
local Build = require(script.Parent.Parent.UI.Build)
local Anim = require(script.Parent.Parent.UI.Anim)
local UIController = require(script.Parent.UIController)
local GameStateController = require(script.Parent.GameStateController)
local HudController = require(script.Parent.HudController)
local WallController = require(script.Parent.WallController)

-- A que distância da barreira a faixa aparece. Um pouco além do alcance do
-- golpe, para o jogador já chegar lendo o que tem pela frente.
local SHOW_RANGE = WallConfig.HitRange * 3
-- Compacta: uma linha de texto e uma barra fina. Clicar abre o painel
-- completo de Progresso, que é onde o detalhe pertence.
local PANEL_WIDTH = 360
-- Acima disto (golpes para o estágio inteiro, ~1 min segurando o clique) a
-- faixa avisa que o jogador ainda está fraco para esta barreira.
local WEAK_HITS = 600
local PANEL_HEIGHT = 30
-- Título de entrada do estágio: quanto fica na tela e o intervalo mínimo para
-- repetir o mesmo estágio (ir e voltar na fronteira não fica piscando).
local TITLE_SECONDS = 1.5
local TITLE_REPEAT_SECONDS = 8

local CorridorHudController = {}

local panel: TextButton
local statusLabel: TextLabel
local rewardLabel: TextLabel
local stageTitle: TextLabel
local titleStamp = 0
local lastArea: string? = nil
local titleShownAt: { [string]: number } = {}
-- X da origem do corredor no mundo, achado pela primeira fileira (o cliente
-- não sabe a origem do mundo; as fileiras sim).
local originX: number? = nil

local function stageOf(stageId: string): WallConfig.WallStage?
	for _, stage in WallConfig.Stages do
		if stage.Id == stageId then
			return stage
		end
	end
	return nil
end

-- A fileira de pé (para este jogador) mais próxima, se houver alguma por perto.
local function nearestRow(position: Vector3): (BasePart?, number)
	local best: BasePart? = nil
	local bestDistance = SHOW_RANGE
	for _, rows in WallController.Rows() do
		for _, row in rows do
			-- Só fileiras À FRENTE do jogador (o servidor só aceita golpe nelas).
			if row.Parent and position.X < row.Position.X then
				local _, _, broken = WallController.RowState(row)
				local distance = (row.Position - position).Magnitude
				if not broken and distance <= bestDistance then
					best, bestDistance = row, distance
				end
			end
		end
	end
	return best, bestDistance
end

local function corridorOrigin(): number?
	if originX then
		return originX
	end
	local first = WallConfig.Stages[1]
	local rows = first and WallController.Rows()[first.Id]
	local row = rows and rows[1]
	local segment = CorridorLayout.Segments()[1]
	if row and row.Parent and segment then
		originX = row.CFrame.Position.X - row.Size.X / 2 - segment.Barrier
	end
	return originX
end

-- "⚔ 7 · ROCHA VULCÂNICA" por ~1,5 s ao entrar na área de um estágio.
function CorridorHudController.ShowStageTitle(stageId: string)
	local stage = stageOf(stageId)
	if not stage then
		return
	end
	titleShownAt[stageId] = os.clock()
	stageTitle.Text = Text.Get("corridor.enter", {
		order = stage.Order,
		name = TextCase.Upper(Text.Get("wall." .. stage.Id .. ".name")),
	})
	stageTitle.Visible = true
	Anim.PopIn(stageTitle, 0.5, 0.25)
	titleStamp += 1
	local stamp = titleStamp
	task.delay(TITLE_SECONDS, function()
		if titleStamp == stamp then
			stageTitle.Visible = false
		end
	end)
end

local function checkArea(position: Vector3)
	local origin = corridorOrigin()
	local segment = if origin then CorridorLayout.AreaAt(position.X - origin) else nil
	local id = if segment then segment.Id else nil
	if id ~= lastArea then
		lastArea = id
		if id and os.clock() - (titleShownAt[id] or -math.huge) >= TITLE_REPEAT_SECONDS then
			CorridorHudController.ShowStageTitle(id)
		end
	end
end

local function refresh()
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		panel.Visible = false
		return
	end
	checkArea(root.CFrame.Position)
	local row = nearestRow(root.Position)
	if not row then
		panel.Visible = false
		return
	end
	local stageId = row:GetAttribute("StageId")
	local stage = if type(stageId) == "string" then stageOf(stageId) else nil
	if not stage then
		panel.Visible = false
		return
	end
	panel.Visible = true

	-- Nome e HP estão na placa da barreira; aqui, só o que a completa.
	-- ⚔ o dano REAL do próximo golpe (Poder por clique × combo), não o saldo
	-- de Poder: é o mesmo número que o servidor tira da fileira.
	local perClick = GameStateController.GetHitDamage()
	statusLabel.Text = Text.Get("corridor.hit", {
		icon = Theme.Icons.Damage,
		power = NumberFormat.Short(perClick),
	})
	Build.paint(statusLabel, "TextColor3", Theme.Colors.Damage)
	--[[
		Quantos golpes faltam para o estágio inteiro (fileiras de pé) com o
		golpe atual. Acima de WEAK_HITS (~1 minuto segurando o clique), avisa
		que o jogador está fraco para esta barreira em vez de deixá-lo bater
		sem perceber progresso.
	]]
	local remaining = 0
	for _, other in WallController.Rows()[stage.Id] or {} do
		local otherHp = WallController.RowState(other)
		remaining += math.max(otherHp, 0)
	end
	local hits = if perClick > 0 then math.ceil(remaining / perClick) else math.huge
	-- "≈N golpes" é a conta da FILEIRA da placa de HP (❤ 1B ÷ ⚔ 318M ≈ 4);
	-- o aviso de "forte demais" continua olhando o estágio inteiro.
	local rowHp = math.max(WallController.RowState(row) or 0, 0)
	local rowHits = if perClick > 0 then math.max(math.ceil(rowHp / perClick), 1) else math.huge
	if stage.Id == ProgressionUx.Colossus.StageId then
		local readout = WallController.ColossusReadout()
		if readout then
			local compact = WallController.CompactLabels()
			rewardLabel.Text = Text.Get("corridor.colossus", {
				hits = if readout.Hits == math.huge then "—" else NumberFormat.Short(readout.Hits),
				state = Text.Get(ProgressionUx.ColossusLabelKey(readout.Level, compact)),
			})
			local color = if readout.Level == "Ready" then Theme.Colors.Good elseif readout.Level == "Preparing" then Theme.Colors.Power else Theme.Colors.Bad
			Build.paint(rewardLabel, "TextColor3", color)
			return
		end
	end
	if hits > WEAK_HITS then
		rewardLabel.Text = Text.Get("corridor.weak")
		Build.paint(rewardLabel, "TextColor3", Theme.Colors.Bad)
		return
	end
	Build.paint(rewardLabel, "TextColor3", Theme.Colors.Power)
	-- O painel completo abre no clique; aqui fica só o essencial.
	rewardLabel.Text = Text.Get("corridor.hits", { hits = NumberFormat.Short(rowHits) }) .. "  ·  " .. Text.Get("corridor.reward", {
		wins = NumberFormat.Short(math.max(table.unpack(stage.Pads))),
		icon = Theme.Icons.Wins,
	})
end

-- A faixa da barreira está na tela? (o jogador está em combate no Caminho)
function CorridorHudController.IsActive(): boolean
	return panel ~= nil and panel.Visible
end

function CorridorHudController.Init()
	local hud = Theme.Hud
	panel = Build.button({
		Name = "CorridorHud",
		Text = "",
		-- Na coluna central abaixo das moedas (HudController.GetTopStack): não
		-- cobre a barreira, que é o que o jogador precisa ver.
		Size = UDim2.fromOffset(PANEL_WIDTH, PANEL_HEIGHT),
		BackgroundColor3 = hud.Surface,
		BackgroundTransparency = 0.25,
		Visible = false,
		LayoutOrder = 5,
		Parent = HudController.GetTopStack(),
	})
	for _, child in panel:GetChildren() do
		if child:IsA("UICorner") or (child:IsA("UIStroke") and child.ApplyStrokeMode == Enum.ApplyStrokeMode.Border) then
			child:Destroy()
		end
	end
	Build.corner(panel, UDim.new(0, 14))
	Build.stroke(panel, 2, hud.Border)
	panel.Activated:Connect(function()
		UIController.TogglePanel("Tower")
	end)

	-- Uma linha: "seu golpe" à esquerda, golpes/prêmio (ou o aviso) à direita.
	statusLabel = Build.label({
		Name = "Status",
		TextSize = 15,
		Position = UDim2.fromOffset(12, 5),
		Size = UDim2.new(0.42, -12, 0, 20),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	})
	rewardLabel = Build.label({
		Name = "Reward",
		TextSize = 15,
		TextColor3 = Theme.Colors.Power,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 5),
		Size = UDim2.new(0.58, -12, 0, 20),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = panel,
	})

	-- Título de entrada do estágio: na coluna central, logo abaixo das moedas
	-- (antes da faixa), sem fundo; some sozinho.
	stageTitle = Build.label({
		Name = "StageTitle",
		Text = "",
		Font = Theme.FontDisplay,
		TextSize = 30,
		TextColor3 = Theme.Colors.Power,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(PANEL_WIDTH + 80, 38),
		Visible = false,
		LayoutOrder = 4,
		Parent = HudController.GetTopStack(),
	})
	Build.textStroke(stageTitle, 3)
end

function CorridorHudController.Start()
	-- Uma varredura por quadro é mais barata (e mais simples) que um listener
	-- por fileira, e são poucas dezenas de peças.
	RunService.Heartbeat:Connect(refresh)
end

return CorridorHudController
