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

	Tudo vem de atributos que o servidor já escreve nas peças; este controller
	não decide nada.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local NumberFormat = require(Shared:WaitForChild("Utils"):WaitForChild("NumberFormat"))
local WallConfig = require(Shared:WaitForChild("Config"):WaitForChild("WallConfig"))
local Text = require(Shared:WaitForChild("Localization"))

local Theme = require(script.Parent.Parent.UI.Theme)
local Build = require(script.Parent.Parent.UI.Build)
local UIController = require(script.Parent.UIController)
local GameStateController = require(script.Parent.GameStateController)

-- A que distância da barreira a faixa aparece. Um pouco além do alcance do
-- golpe, para o jogador já chegar lendo o que tem pela frente.
local SHOW_RANGE = WallConfig.HitRange * 3
-- Compacta: uma linha de texto e uma barra fina. Clicar abre o painel
-- completo de Progresso, que é onde o detalhe pertence.
local PANEL_WIDTH = 340
local PANEL_HEIGHT = 48

local CorridorHudController = {}

local panel: TextButton
local titleLabel: TextLabel
local statusLabel: TextLabel
local rewardLabel: TextLabel
local setBar: (number) -> ()
local rows: { BasePart } = {}
local scanned = false

local function stageOf(stageId: string): WallConfig.WallStage?
	for _, stage in WallConfig.Stages do
		if stage.Id == stageId then
			return stage
		end
	end
	return nil
end

local function scan()
	local map = Workspace:FindFirstChild("Map")
	local worlds = if map then map:FindFirstChild("Worlds") else nil
	local world = if worlds then worlds:FindFirstChild(WallConfig.WorldId) else nil
	if not world then
		return
	end
	table.clear(rows)
	for _, descendant in world:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:GetAttribute("Wall") == true then
			table.insert(rows, descendant)
		end
	end
	scanned = #rows > 0
end

-- A fileira de pé mais próxima do jogador, se houver alguma por perto.
local function nearestRow(position: Vector3): (BasePart?, number)
	local best: BasePart? = nil
	local bestDistance = SHOW_RANGE
	for _, row in rows do
		if row:GetAttribute("Broken") ~= true then
			local distance = (row.Position - position).Magnitude
			if distance <= bestDistance then
				best, bestDistance = row, distance
			end
		end
	end
	return best, bestDistance
end

local function refresh()
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not scanned or not root or not root:IsA("BasePart") then
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

	local hp = row:GetAttribute("Hp")
	local maxHp = row:GetAttribute("MaxHp")
	local fraction = if type(hp) == "number" and type(maxHp) == "number" and maxHp > 0 then hp / maxHp else 1
	local perClick = GameStateController.GetPowerInfo().PerClick

	titleLabel.Text = Text.Get("corridor.stage", {
		order = stage.Order,
		name = Text.Get("wall." .. stage.Id .. ".name"),
	})
	statusLabel.Text = Text.Get("corridor.status", {
		hp = NumberFormat.Short(math.max(tonumber(hp) or 0, 0)),
		max = NumberFormat.Short(tonumber(maxHp) or 0),
		icon = Theme.Icons.Power,
		power = NumberFormat.Short(perClick),
	})
	-- O painel completo abre no clique; aqui fica só o essencial.
	rewardLabel.Text = Text.Get("corridor.reward", {
		wins = NumberFormat.Short(math.max(table.unpack(stage.Pads))),
		icon = Theme.Icons.Wins,
	})
	setBar(math.clamp(fraction, 0, 1))
end

function CorridorHudController.Init()
	local hud = Theme.Hud
	panel = Build.button({
		Name = "CorridorHud",
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0),
		-- Abaixo da fileira de moedas e acima do meio da tela: não cobre a
		-- barreira, que é o que o jogador precisa ver.
		Position = UDim2.new(0.5, 0, 0, hud.TopBarY + hud.PillSize.Y + hud.Gap * 2),
		Size = UDim2.fromOffset(PANEL_WIDTH, PANEL_HEIGHT),
		BackgroundColor3 = hud.Surface,
		BackgroundTransparency = 0.25,
		Visible = false,
		Parent = UIController.GetCanvas(),
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
		Size = UDim2.new(1, -24, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	})
	rewardLabel = Build.label({
		Name = "Reward",
		TextSize = 15,
		TextColor3 = Theme.Colors.Power,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 6),
		Size = UDim2.new(0.45, -12, 0, 20),
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
	task.spawn(function()
		while not scanned do
			scan()
			if not scanned then
				task.wait(1)
			end
		end
		-- Uma varredura por quadro é mais barata (e mais simples) que um
		-- listener por fileira, e são poucas dezenas de peças.
		RunService.Heartbeat:Connect(refresh)
	end)
end

return CorridorHudController
