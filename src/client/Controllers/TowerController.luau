--!strict
--[[
	TowerController
	Painel "Progresso": os dez estágios do corredor, em ordem, dizendo onde o
	jogador está.

	Cada linha mostra o estágio, o material, a vida de uma fileira, quantas
	fileiras tem, o prêmio em vitórias e as gemas da primeira conquista — e o
	estado: conquistado, atual ou ainda fechado.

	Substituiu "Mundos" no menu principal: a torre é a progressão agora (os
	mundos 2–5 estão dormentes, ver docs/PLANO_TORRE.md §C3). O painel de
	mundos continua existindo no código, só não tem mais entrada no menu.

	Leitura pura: tudo vem de PlayerData.Tower, que o servidor escreve.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local NumberFormat = require(Shared:WaitForChild("Utils"):WaitForChild("NumberFormat"))
local WallConfig = require(Shared:WaitForChild("Config"):WaitForChild("WallConfig"))
local HitDisplay = require(Shared:WaitForChild("Formulas"):WaitForChild("HitDisplay"))
local Text = require(Shared:WaitForChild("Localization"))

local Theme = require(script.Parent.Parent.UI.Theme)
local Build = require(script.Parent.Parent.UI.Build)
local UIController = require(script.Parent.UIController)
local MenuController = require(script.Parent.MenuController)
local DataController = require(script.Parent.DataController)
local GameStateController = require(script.Parent.GameStateController)

type Row = {
	Stage: WallConfig.WallStage,
	Frame: Frame,
	Status: TextLabel,
	Dot: Frame,
}

local PANEL = "Tower"
local ROW_HEIGHT = 84
local DOT_SIZE = 18

local TowerController = {}

local rows: { Row } = {}
local summaryLabel: TextLabel
local attackLabel: TextLabel
local breakdownLabel: TextLabel
local menuButton: TextButton

-- Camadas do PowerInfo que valem mostrar (≠ 1), na ordem da fórmula.
local LAYERS = { "Upgrade", "Permanent", "Rebirth", "Pet", "Aura", "Rune", "World", "Zone", "Event", "Social", "GamePass", "TemporaryBoost", "Overdrive" }

--[[
	"Seu ataque": a decomposição COMPLETA do golpe, só aqui (o HUD mostra só
	⚡ saldo e ⚔ golpe). ⚔ golpe = ⚡ por clique (base × camadas) × combo.
]]
local function refreshAttack()
	if not attackLabel then
		return
	end
	local info = GameStateController.GetPowerInfo()
	local currencies = DataController.Get("Currencies") or {}
	attackLabel.Text = Text.Get("tower.attack", {
		powerIcon = Theme.Icons.Power,
		power = NumberFormat.Short(currencies.Power or 0),
		hitIcon = Theme.Icons.Damage,
		hit = NumberFormat.Short(GameStateController.GetHitDamage()),
	})
	local parts = { Text.Get("tower.layer.Base", { value = NumberFormat.Short(info.Base or info.PerClick) }) }
	for _, layer in LAYERS do
		local value = (info.Layers or {})[layer]
		if type(value) == "number" and math.abs(value - 1) > 1e-6 then
			table.insert(parts, Text.Get("tower.layer." .. layer, { value = NumberFormat.Short(value) }))
		end
	end
	local combo = HitDisplay.Damage(1, GameStateController.GetCombo())
	if combo > 1 then
		table.insert(parts, Text.Get("tower.layer.Combo", { value = NumberFormat.Short(combo) }))
	end
	breakdownLabel.Text = table.concat(parts, "  ·  ")
end

local function refresh()
	local tower = DataController.Get("Tower")
	local cleared: { [string]: boolean } = {}
	local highest = 0
	if type(tower) == "table" then
		cleared = tower.Cleared or {}
		highest = tower.Highest or 0
	end

	for _, row in rows do
		local done = cleared[row.Stage.Id] == true
		local current = not done and row.Stage.Order == highest + 1
		if done then
			row.Status.Text = Text.Get("tower.cleared")
			Build.paint(row.Status, "TextColor3", Theme.Colors.Good)
			Build.paint(row.Dot, "BackgroundColor3", Theme.Colors.Good)
		elseif current then
			row.Status.Text = Text.Get("tower.current")
			Build.paint(row.Status, "TextColor3", Theme.Colors.Power)
			Build.paint(row.Dot, "BackgroundColor3", Theme.Colors.Power)
		else
			row.Status.Text = Text.Get("tower.locked")
			Build.paint(row.Status, "TextColor3", Theme.Colors.TextDim)
			Build.paint(row.Dot, "BackgroundColor3", Theme.Colors.Disabled)
		end
		Build.paint(row.Frame, "BackgroundColor3", if current then Theme.Colors.Accent else Theme.Colors.PanelLight)
	end

	summaryLabel.Text = Text.Get("tower.summary", {
		done = tostring(highest),
		total = tostring(#WallConfig.Stages),
	})
	refreshAttack()
	-- Sem badge: "ainda falta barreira" é o estado normal do jogo, não um
	-- aviso. A faixa contextual no Caminho já mostra onde o jogador está.
end

local function createRow(list: ScrollingFrame, stage: WallConfig.WallStage)
	local frame: Frame = Build.new("Frame", {
		Name = stage.Id,
		BackgroundColor3 = Theme.Colors.PanelLight,
		Size = UDim2.new(1, -12, 0, ROW_HEIGHT),
		LayoutOrder = stage.Order,
		ZIndex = 22,
		Parent = list,
	})
	Build.corner(frame, Theme.CornerSmall)

	-- Marcador de estado + amostra da cor do estágio: a "trilha" do corredor.
	local dot: Frame = Build.new("Frame", {
		Name = "Dot",
		BackgroundColor3 = Theme.Colors.Disabled,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.fromOffset(DOT_SIZE, DOT_SIZE),
		ZIndex = 23,
		Parent = frame,
	})
	Build.corner(dot, UDim.new(1, 0))
	local sample: Frame = Build.new("Frame", {
		Name = "Sample",
		BackgroundColor3 = stage.Color,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 44, 0.5, 0),
		Size = UDim2.fromOffset(10, ROW_HEIGHT - 24),
		ZIndex = 23,
		Parent = frame,
	})
	Build.corner(sample, UDim.new(0, 4))

	Build.label({
		Text = Text.Get("corridor.stage", { order = stage.Order, name = Text.Get("wall." .. stage.Id .. ".name") }),
		TextSize = 22,
		Position = UDim2.fromOffset(66, 8),
		Size = UDim2.new(1, -220, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 23,
		Parent = frame,
	})
	Build.label({
		Text = Text.Get("tower.detail", {
			rows = tostring(stage.Rows),
			hp = NumberFormat.Short(stage.Hp),
			wins = NumberFormat.Short(math.max(table.unpack(stage.Pads))),
			winsIcon = Theme.Icons.Wins,
			gems = NumberFormat.Short(stage.FirstClearGems),
			gemsIcon = Theme.Icons.Gems,
		}),
		TextSize = 16,
		TextColor3 = Theme.Colors.TextDim,
		TextWrapped = true,
		Position = UDim2.fromOffset(66, 38),
		Size = UDim2.new(1, -220, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 23,
		Parent = frame,
	})
	local status = Build.label({
		Name = "Status",
		Text = "",
		Font = Theme.FontDisplay,
		TextSize = 20,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.fromOffset(160, 30),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 23,
		Parent = frame,
	})
	table.insert(rows, { Stage = stage, Frame = frame, Status = status, Dot = dot })
end

function TowerController.Init()
	local _, content = UIController.CreatePanel(PANEL, Text.Get("tower.title", { icon = Theme.Icons.Tower }), Vector2.new(660, 580))

	summaryLabel = Build.label({
		Name = "Summary",
		Text = "",
		Font = Theme.FontDisplay,
		TextSize = 20,
		TextColor3 = Theme.Colors.Power,
		Position = UDim2.fromOffset(4, 0),
		Size = UDim2.new(1, -8, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 22,
		Parent = content,
	})

	attackLabel = Build.label({
		Name = "Attack",
		Text = "",
		Font = Theme.FontDisplay,
		TextSize = 18,
		Position = UDim2.fromOffset(4, 30),
		Size = UDim2.new(1, -8, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 22,
		Parent = content,
	})
	breakdownLabel = Build.label({
		Name = "AttackBreakdown",
		Text = "",
		TextSize = 14,
		TextColor3 = Theme.Colors.TextDim,
		Position = UDim2.fromOffset(4, 54),
		Size = UDim2.new(1, -8, 0, 32),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 22,
		Parent = content,
	})

	local list: ScrollingFrame = Build.new("ScrollingFrame", {
		Name = "List",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 92),
		Size = UDim2.new(1, 0, 1, -92),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 8,
		ZIndex = 22,
		Parent = content,
	})
	Build.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })

	for _, stage in WallConfig.Stages do
		createRow(list, stage)
	end

	menuButton = MenuController.AddButton(Text.Get("menu.tower"), Theme.Icons.Tower, Theme.Colors.Bad, 5, function()
		UIController.TogglePanel(PANEL)
	end, "Tower")

	DataController.Changed:Connect(function(key: string)
		if key == "Tower" then
			refresh()
		elseif key == "Currencies" and UIController.GetOpenPanel() == PANEL then
			refreshAttack()
		end
	end)
	GameStateController.PowerInfoChanged:Connect(refreshAttack)
	refresh()
end

return TowerController
