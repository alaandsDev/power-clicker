--!strict
--[[
	RebirthController
	Painel de renascimento. Antes de confirmar, o jogador lê:
		- quantos renascimentos ele tem;
		- quanto Power o próximo exige e quanto falta;
		- o que ganha (gemas e multiplicador, de x para y);
		- o que reseta e, principalmente, O QUE FICA.

	A linha do que fica existe porque renascer é a decisão mais assustadora de
	um clicker: sem ela, o jogador acha que vai perder os pets e não clica.

	O servidor é quem executa o renascimento ("Rebirth").
]]

local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local NumberFormat = require(Shared:WaitForChild("Utils"):WaitForChild("NumberFormat"))
local EconomyFormulas = require(Shared:WaitForChild("Formulas"):WaitForChild("EconomyFormulas"))
local Text = require(Shared:WaitForChild("Localization"))

local Theme = require(script.Parent.Parent.UI.Theme)
local Build = require(script.Parent.Parent.UI.Build)
local Anim = require(script.Parent.Parent.UI.Anim)
local Messages = require(script.Parent.Parent.UI.Messages)
local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local UIController = require(script.Parent.UIController)
local MenuController = require(script.Parent.MenuController)
local DataController = require(script.Parent.DataController)
local SoundController = require(script.Parent.SoundController)
local NotificationController = require(script.Parent.NotificationController)

local PANEL = "Rebirth"

local RebirthController = {}

local infoLabel: TextLabel
local keepsLabel: TextLabel
local progressLabel: TextLabel
local setProgress: (number) -> ()
local confirmButton: TextButton
local menuButton: TextButton
local flash: Frame
local busy = false

local function refresh()
	local currencies = DataController.Get("Currencies")
	local stats = DataController.Get("Stats")
	if not currencies or not stats then
		return
	end
	local rebirths = stats.Rebirths or 0
	local power = currencies.Power or 0
	local cost = EconomyFormulas.RebirthCost(rebirths, stats.RebirthAnchor)
	local ready = power >= cost

	infoLabel.Text = Text.Get("rebirth.info", {
		count = rebirths,
		gems = NumberFormat.Short(EconomyFormulas.RebirthGems(rebirths)),
		icon = Theme.Icons.Gems,
		from = NumberFormat.Short(EconomyFormulas.RebirthMultiplier(rebirths)),
		to = NumberFormat.Short(EconomyFormulas.RebirthMultiplier(rebirths + 1)),
	})
	progressLabel.Text = Theme.Icons.Power
		.. " "
		.. NumberFormat.Short(power)
		.. " / "
		.. NumberFormat.Short(cost)
		.. "   "
		.. (
			if ready
				then Text.Get("rebirth.ready")
				else Text.Get("rebirth.missing", {
					amount = NumberFormat.Short(cost - power),
					icon = Theme.Icons.Power,
				})
		)
	setProgress(power / cost)
	Build.paint(confirmButton, "BackgroundColor3", if ready then Theme.Colors.Accent else Theme.Colors.Disabled)
	confirmButton.Text = Text.Get(if ready then "rebirth.button" else "rebirth.notEnough")
	MenuController.SetBadge(menuButton, ready)
end

local function playFlash()
	local settings = DataController.Get("Settings")
	if settings and settings.ReducedEffects == true then
		return
	end
	flash.Visible = true
	flash.BackgroundTransparency = 0.1
	local tween = TweenService:Create(flash, TweenInfo.new(0.8), { BackgroundTransparency = 1 })
	tween:Play()
	tween.Completed:Once(function()
		flash.Visible = false
	end)
end

local function rebirth()
	if busy then
		return
	end
	busy = true
	local response = ClientNet.Invoke("Rebirth")
	busy = false
	if response.Ok then
		SoundController.Play("Rebirth")
		playFlash()
		Anim.Shake(UIController.GetCanvas(), 10, 0.4)
		UIController.ClosePanel()
	else
		NotificationController.Show(Messages.ForCode(response.Code), "Bad")
	end
end

function RebirthController.Init()
	local _, content = UIController.CreatePanel(PANEL, Text.Get("rebirth.title", { icon = Theme.Icons.Rebirth }), Vector2.new(520, 460))

	infoLabel = Build.label({
		Text = "",
		TextSize = 24,
		Size = UDim2.new(1, 0, 0, 150),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		LineHeight = 1.2,
		ZIndex = 22,
		Parent = content,
	})
	-- O que NÃO se perde, logo abaixo do resumo: é a linha que faz o jogador
	-- apertar o botão.
	keepsLabel = Build.label({
		Text = Text.Get("rebirth.keeps"),
		TextSize = 18,
		TextColor3 = Theme.Colors.Good,
		TextWrapped = true,
		Position = UDim2.fromOffset(0, 150),
		Size = UDim2.new(1, 0, 0, 48),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 22,
		Parent = content,
	})

	local bar, set = Build.progressBar({
		Position = UDim2.fromOffset(0, 206),
		Size = UDim2.new(1, 0, 0, 30),
		ZIndex = 22,
		Parent = content,
	}, Theme.Colors.Power)
	setProgress = set
	progressLabel = Build.label({
		Text = "",
		TextSize = 20,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 24,
		Parent = bar,
	})
	confirmButton = Build.button({
		Text = "",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 0, 0, 80),
		TextSize = 34,
		ZIndex = 22,
		Parent = content,
	})
	confirmButton.Activated:Connect(rebirth)

	flash = Build.new("Frame", {
		Name = "RebirthFlash",
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 100,
		Parent = UIController.GetCanvas(),
	})

	menuButton = MenuController.AddButton(Text.Get("menu.rebirth"), Theme.Icons.Rebirth, Theme.Colors.Accent, 2, function()
		UIController.TogglePanel(PANEL)
	end, "Rebirth")

	DataController.Changed:Connect(function(key: string)
		if key == "Currencies" or key == "Stats" then
			refresh()
		end
	end)
end

return RebirthController
