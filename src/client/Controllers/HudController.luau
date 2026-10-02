--!strict
--[[
	HudController
	HUD: fileira de moedas no topo, chip de missões à esquerda e a composição do
	rodapé (ganho por clique → botão → barra de nível).

	Passada de UX: o painel grande de metas saiu da tela. Ele ocupava um quarto
	da altura mostrando três barras que o jogador raramente lia; virou um chip
	"📋 Missões 2/3" que abre o painel quando clicado. O texto solto de Power
	por clique também saiu da coluna e virou a linha logo acima do botão, onde
	ele é olhado de verdade.

	(Histórico) Antes: coluna superior esquerda e a antiga grade de 3 níveis
	goal tracker:
		Immediate → next upgrade to buy
		Medium    → progress to next rebirth
		Long      → next world
	Everything shown is derived from replicated data; purely informative.
]]

local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local NumberFormat = require(Shared:WaitForChild("Utils"):WaitForChild("NumberFormat"))
local LevelFormula = require(Shared:WaitForChild("Formulas"):WaitForChild("LevelFormula"))
local OverdriveConfig = require(Shared:WaitForChild("Config"):WaitForChild("OverdriveConfig"))
local Text = require(Shared:WaitForChild("Localization"))

local Theme = require(script.Parent.Parent.UI.Theme)
local Build = require(script.Parent.Parent.UI.Build)
local Anim = require(script.Parent.Parent.UI.Anim)
local SoundController = require(script.Parent.SoundController)
local UIController = require(script.Parent.UIController)
local DataController = require(script.Parent.DataController)
local GameStateController = require(script.Parent.GameStateController)

local HudController = {}

local powerLabel: TextLabel
local gemsLabel: TextLabel
local winsLabel: TextLabel
local levelFrame: Frame
local levelLabel: TextLabel -- "Nv. 50"
local overdriveLabel: TextLabel -- "Overdrive 55%" / contagem quando ativo
local setLevelBar: (number) -> ()
local lastLevel = -1
local boostLabel: TextLabel
local boostsReceivedAt = 0
local powerIcon: GuiObject
local questChip: TextButton
-- Level bar: directly above the click button. ClickController reserves this
-- room (Theme.Hud.LevelBar) and starts its own stack above it.
local function levelBottom(): number
	local hud = Theme.Hud
	local buttonHeight = hud.ClickHeight + (if UIController.IsTouch() then hud.ClickTouchExtra.Y else 0)
	return hud.ClickBottom + buttonHeight + hud.LevelGap
end

local lastPower = -1
local lastGems = -1
local lastWins = -1

-- Currency pill (Art Bible): round tinted icon, small caps caption, big number.
local function pill(parent: Instance, name: string, icon: string, color: Color3, caption: string, order: number): (TextLabel, GuiObject)
	local hud = Theme.Hud
	local frame: Frame = Build.new("Frame", {
		Name = name,
		Parent = parent,
		Size = UDim2.fromOffset(hud.PillSize.X, hud.PillSize.Y),
		LayoutOrder = order,
	})
	Build.hudSurface(frame, UDim.new(1, 0), color)
	local inset = (hud.PillSize.Y - hud.PillIcon) / 2
	local bubble: Frame = Build.new("Frame", {
		Name = "IconBubble",
		BackgroundColor3 = color,
		BackgroundTransparency = 0.85,
		Position = UDim2.fromOffset(inset, inset),
		Size = UDim2.fromOffset(hud.PillIcon, hud.PillIcon),
		Parent = frame,
	})
	Build.corner(bubble, UDim.new(1, 0))
	Build.icon(icon, {
		Name = "Icon",
		TextSize = 26,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.9),
		Parent = bubble,
	})
	local textX = inset * 2 + hud.PillIcon
	Build.label({
		Name = "Caption",
		Text = caption,
		Font = Theme.FontMono,
		TextSize = 12,
		TextColor3 = color,
		Position = UDim2.fromOffset(textX, 7),
		Size = UDim2.new(1, -textX - 14, 0, 14),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})
	local value = Build.label({
		Name = "Value",
		Text = "...", -- until the first snapshot arrives
		Font = Theme.FontDisplay,
		TextSize = 28,
		Position = UDim2.fromOffset(textX, 20),
		Size = UDim2.new(1, -textX - 14, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})
	return value, bubble
end

local function pop(label: TextLabel)
	local scale = label:FindFirstChildOfClass("UIScale") or Build.new("UIScale", { Parent = label })
	scale.Scale = 1.12
	TweenService:Create(scale, Theme.Tween.Normal, { Scale = 1 }):Play()
end

local function refresh()
	local currencies = DataController.Get("Currencies")
	local stats = DataController.Get("Stats")
	if not currencies or not stats then
		return
	end
	local power = currencies.Power or 0
	local gems = currencies.Gems or 0
	local winsTotal = currencies.Wins or 0

	-- Nível (derivado do Power em mãos) + estado do overdrive, numa linha só.
	local level, into, cost = LevelFormula.LevelOf(power)
	levelLabel.Text = Text.Get("hud.level", { level = NumberFormat.Short(level) })
	setLevelBar(if cost > 0 then into / cost else 0)
	if GameStateController.IsOverdriveActive() then
		overdriveLabel.Text = Text.Get("overdrive.active", {
			mult = NumberFormat.Short(OverdriveConfig.Multiplier),
			seconds = math.ceil(GameStateController.GetOverdriveRemaining()),
		})
		Build.paint(overdriveLabel, "TextColor3", Theme.Colors.OverdriveTop)
	else
		local cooldown = GameStateController.GetCooldownRemaining()
		local charge = (DataController.Get("Overdrive") or {}).Charge or 0
		overdriveLabel.Text = if cooldown > 0
			then Text.Get("overdrive.cooldown", { seconds = math.ceil(cooldown) })
			else Text.Get("overdrive.charge", { percent = math.floor(charge / OverdriveConfig.ChargeMax * 100) })
		Build.paint(overdriveLabel, "TextColor3", Theme.Colors.TextDim)
	end
	if lastLevel >= 0 and level > lastLevel then
		Anim.Pop(levelLabel, 1.2)
		SoundController.Play("Upgrade")
	end
	lastLevel = level
	-- Numbers count toward the new value instead of jumping.
	Anim.CountUp(powerLabel, if lastPower < 0 then power else lastPower, power, NumberFormat.Short, 0.25)
	Anim.CountUp(gemsLabel, if lastGems < 0 then gems else lastGems, gems, NumberFormat.Short, 0.4)
	if lastPower >= 0 and power < lastPower then
		pop(powerLabel) -- rebirth reset / purchase
	end
	if lastGems >= 0 and gems > lastGems then
		local pill = gemsLabel.Parent
		if pill and pill:IsA("GuiObject") then
			Anim.Pop(pill, 1.15)
		end
	end
	Anim.CountUp(winsLabel, if lastWins < 0 then winsTotal else lastWins, winsTotal, NumberFormat.Short, 0.4)
	if lastWins >= 0 and winsTotal > lastWins then
		local pill = winsLabel.Parent
		if pill and pill:IsA("GuiObject") then
			Anim.Pop(pill, 1.2)
		end
	end
	lastPower = power
	lastGems = gems
	lastWins = winsTotal

	-- Chip de missões: só o contador; o painel abre no clique.
	local quests = DataController.Get("Quests")
	local done, total = 0, 0
	if type(quests) == "table" and type(quests.Progress) == "table" then
		for _, entry in quests.Progress do
			total += 1
			if entry.Claimed then
				done += 1
			end
		end
	end
	questChip.Text = Text.Get("hud.questChip", { done = done, total = math.max(total, 0) })
	questChip.Visible = total > 0
end


-- Active boosts with a local countdown (server resyncs "Boosts" periodically).
local function refreshBoosts()
	local boosts = DataController.Get("Boosts")
	local remaining = if boosts then boosts.Remaining else nil
	if not remaining or next(remaining) == nil then
		boostLabel.Text = ""
		return
	end
	local elapsed = os.clock() - boostsReceivedAt
	local parts = {}
	for boostId, seconds in remaining do
		local left = seconds - elapsed
		if left > 0 then
			table.insert(parts, Text.Get("hud.boost", { name = Text.Get("boost." .. boostId .. ".name"), time = NumberFormat.Duration(left) }))
		end
	end
	table.sort(parts)
	boostLabel.Text = table.concat(parts, "   ")
	boostLabel.Visible = #parts > 0
end

-- Pills (frames) so other controllers can aim effects at them.
function HudController.GetPowerPill(): GuiObject?
	local pill = if powerLabel then powerLabel.Parent else nil
	return if pill and pill:IsA("GuiObject") then pill else nil
end

-- Where ⚡ flyers land (centre of the Power icon), in canvas pixels.
function HudController.GetPowerTarget(): Vector2?
	return if powerIcon then UIController.CenterOf(powerIcon) else nil
end

function HudController.Init()
	local canvas = UIController.GetCanvas()

	local hud = Theme.Hud

	--[[
		Currencies in one horizontal row at the top, centred: three numbers side
		by side read as "what I have" at a glance, and they leave the whole left
		side free for the goals.
	]]
	local topBar: Frame = Build.new("Frame", {
		Name = "HudTop",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, hud.TopBarY),
		Size = UDim2.fromOffset(hud.PillSize.X * 3 + hud.TopBarGap * 2, hud.PillSize.Y),
		Parent = canvas,
	})
	Build.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, hud.TopBarGap),
		Parent = topBar,
	})
	powerLabel, powerIcon = pill(topBar, "Power", Theme.Icons.Power, Theme.Colors.Power, Text.Get("hud.captionPower"), 1)
	gemsLabel = pill(topBar, "Gems", Theme.Icons.Gems, Theme.Colors.Gems, Text.Get("hud.captionGems"), 2)
	winsLabel = pill(topBar, "Wins", Theme.Icons.Wins, Theme.Colors.Power, Text.Get("hud.captionWins"), 3)

	--[[
		Não existe mais texto permanente de "+X por clique": o número sobe do
		botão e some (ClickController). Texto grande fixo em cima do personagem
		era justamente o que disputava espaço com tudo no rodapé.
	]]

	-- Buffs temporários: chip pequeno sob a fileira de moedas, não texto solto.
	boostLabel = Build.label({
		Name = "Boosts",
		TextSize = 15,
		TextColor3 = Theme.Colors.Good,
		BackgroundColor3 = hud.Surface,
		BackgroundTransparency = 0.25,
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, hud.TopBarY + hud.PillSize.Y + 4),
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		Visible = false,
		Parent = canvas,
	})
	Build.corner(boostLabel, UDim.new(1, 0))
	Build.new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = boostLabel })

	--[[
		Chip de missões no lugar do painel de metas. O painel grande mostrava
		três barras permanentes; isto mostra uma linha e abre o painel completo
		quando clicado — o jogador escolhe quando quer detalhe.
	]]
	questChip = Build.button({
		Name = "QuestChip",
		Text = "",
		TextSize = 17,
		BackgroundColor3 = hud.Surface,
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromOffset(hud.Margin, hud.TopBarY + hud.PillSize.Y + hud.Gap),
		Size = UDim2.fromOffset(150, 32),
		Visible = false,
		Parent = canvas,
	})
	Build.corner(questChip, UDim.new(1, 0))
	questChip.Activated:Connect(function()
		UIController.TogglePanel("Quests")
	end)

	--[[
		Level bar, bottom centre above the click button. It reads the Power the
		player is holding (LevelFormula), so it fills in the first seconds of a
		new game and starts over after a rebirth.
		It sits right above the click button; ClickController reserves the room
		and stacks the overdrive bar and the combo above it.
	]]
	--[[
		COMPONENTE ÚNICO do rodapé:

			Nv. 50          Overdrive 55%
			[==========barra==========]
			        [ CLIQUE! ]

		Antes isto eram quatro elementos soltos (nível, progresso, barra de
		overdrive e texto de overdrive) empilhados no mesmo espaço, e eles se
		sobrepunham. Agora é um quadro só, com duas linhas e uma barra.
	]]
	levelFrame = Build.new("Frame", {
		Name = "ClickStatus",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -levelBottom()),
		Size = UDim2.fromOffset(hud.LevelBar.X, hud.StatusRow + hud.LevelBar.Y),
		Parent = canvas,
	})
	levelLabel = Build.label({
		Name = "Level",
		Font = Theme.FontDisplay,
		TextSize = 17,
		Size = UDim2.new(0.5, 0, 0, hud.StatusRow),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = levelFrame,
	})
	Build.textStroke(levelLabel, 2)
	overdriveLabel = Build.label({
		Name = "Overdrive",
		Font = Theme.FontDisplay,
		TextSize = 17,
		TextColor3 = Theme.Colors.TextDim,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.5, 0, 0, hud.StatusRow),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = levelFrame,
	})
	Build.textStroke(overdriveLabel, 2)
	local bar, setBar = Build.progressBar({
		Name = "Fill",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(hud.LevelBar.X, hud.LevelBar.Y),
		Parent = levelFrame,
	}, Theme.Colors.Power)
	setLevelBar = setBar
	Build.stroke(bar, 2)

	DataController.Changed:Connect(function(key: string)
		if key == "Currencies" or key == "Stats" or key == "Quests" then
			refresh()
		elseif key == "Boosts" then
			boostsReceivedAt = os.clock()
			refreshBoosts()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			refreshBoosts()
		end
	end)
	-- O overdrive conta segundos: a linha de status precisa acompanhar.
	GameStateController.OverdriveChanged:Connect(refresh)
end

return HudController
