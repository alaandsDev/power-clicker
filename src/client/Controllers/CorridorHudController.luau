--!strict
--[[
	CorridorHudController
	A faixa de informação do corredor: aparece quando o jogador está perto de
	uma barreira e some no lobby.

	Mostra o que o pedido lista para a hora do combate:
		estágio atual · nome da barreira · força necessária · sua força
		progresso de dano · próxima recompensa

	Fica no ALTO da tela, estreita e sem fundo opaco: o pedido é explícito em
	não tapar a barreira com painel grande. A barra de vida da fileira continua
	flutuando sobre a própria barreira (WallController) — aqui é o resumo.

	O HP é o das barreiras DESTE jogador (cada um tem o próprio caminho), lido
	do WallController, que recebe o estado do servidor; este controller não
	decide nada.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local NumberFormat = require(Shared:WaitForChild("Utils"):WaitForChild("NumberFormat"))
local WallConfig = require(Shared:WaitForChild("Config"):WaitForChild("WallConfig"))
local Text = require(Shared:WaitForChild("Localization"))

local Theme = require(script.Parent.Parent.UI.Theme)
local Build = require(script.Parent.Parent.UI.Build)
local UIController = require(script.Parent.UIController)
local GameStateController = require(script.Parent.GameStateController)
local HudController = require(script.Parent.HudController)
local WallController = require(script.Parent.WallController)

-- A que distância da barreira a faixa aparece. Um pouco além do alcance do
-- golpe, para o jogador já chegar lendo o que tem pela frente.
local SHOW_RANGE = WallConfig.HitRange * 3
-- Compacta: uma linha de texto e uma barra fina. Clicar abre o painel
-- completo de Progresso, que é onde o detalhe pertence.
local PANEL_WIDTH = 380
-- Acima disto (golpes para o estágio inteiro, ~1 min segurando o clique) a
-- faixa avisa que o jogador ainda está fraco para esta barreira.
local WEAK_HITS = 600
local PANEL_HEIGHT = 48

local CorridorHudController = {}

local panel: TextButton
local titleLabel: TextLabel
local statusLabel: TextLabel
local rewardLabel: TextLabel
local setBar: (number) -> ()

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

local function refresh()
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		panel.Visible = false
		return
	end
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

	local hp, maxHp = WallController.RowState(row)
	local fraction = if maxHp > 0 then hp / maxHp else 1
	local perClick = GameStateController.GetPowerInfo().PerClick

	titleLabel.Text = Text.Get("corridor.stage", {
		order = stage.Order,
		name = Text.Get("wall." .. stage.Id .. ".name"),
	})
	statusLabel.Text = Text.Get("corridor.status", {
		hp = NumberFormat.Short(math.max(hp, 0)),
		max = NumberFormat.Short(maxHp),
		icon = Theme.Icons.Power,
		power = NumberFormat.Short(perClick),
	})
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
	setBar(math.clamp(fraction, 0, 1))
	if hits > WEAK_HITS then
		rewardLabel.Text = Text.Get("corridor.weak")
		Build.paint(rewardLabel, "TextColor3", Theme.Colors.Bad)
		return
	end
	Build.paint(rewardLabel, "TextColor3", Theme.Colors.Power)
	-- O painel completo abre no clique; aqui fica só o essencial.
	rewardLabel.Text = Text.Get("corridor.hits", { hits = NumberFormat.Short(hits) }) .. "  ·  " .. Text.Get("corridor.reward", {
		wins = NumberFormat.Short(math.max(table.unpack(stage.Pads))),
		icon = Theme.Icons.Wins,
	})
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

	titleLabel = Build.label({
		Name = "Stage",
		Font = Theme.FontDisplay,
		TextSize = 19,
		Position = UDim2.fromOffset(12, 4),
		-- Metade esquerda: a direita é de golpes/prêmio (não se sobrepõem).
		Size = UDim2.new(0.5, -12, 0, 22),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	})
	rewardLabel = Build.label({
		Name = "Reward",
		TextSize = 15,
		TextColor3 = Theme.Colors.Power,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 6),
		Size = UDim2.new(0.5, -12, 0, 20),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = panel,
	})
	local bar, set = Build.progressBar({
		Name = "Damage",
		Position = UDim2.fromOffset(12, 28),
		Size = UDim2.new(1, -24, 0, 12),
		Parent = panel,
	}, Theme.Colors.Good)
	setBar = set
	-- O HP exato fica DENTRO da barra: uma linha a menos na tela.
	statusLabel = Build.label({
		Name = "Status",
		TextSize = 12,
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		Parent = bar,
	})
end

function CorridorHudController.Start()
	-- Uma varredura por quadro é mais barata (e mais simples) que um listener
	-- por fileira, e são poucas dezenas de peças.
	RunService.Heartbeat:Connect(refresh)
end

return CorridorHudController
