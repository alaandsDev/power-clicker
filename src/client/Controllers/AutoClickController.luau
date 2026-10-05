--!strict
--[[
	AutoClickController
	Entrada do Auto Clique ao lado do botão CLIQUE!:

		[AUTO ON] [ CLIQUE! ]

	O sistema já existia inteiro no servidor (passe "AutoClick",
	MonetizationService/ClickService, remote "SetAutoClick" que confere a posse)
	mas só dava para ligar/desligar escondido na aba Passes da Loja. Aqui:
	- tem o passe: clicar liga/desliga (o servidor valida e publica o estado
	  no atributo "AutoClickOn"; o botão só mostra o que o servidor diz);
	- não tem: clicar mostra o benefício em uma linha e o botão Comprar, que usa
	  o fluxo de compra que já existe ("PromptPurchase" → passe do
	  ProductConfig). Depois da compra o atributo "Pass_AutoClick" chega e o
	  botão vira o liga/desliga, sem relogar.
	Nenhum valor muda: velocidade, Poder e preço continuam os do passe.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Text = require(Shared:WaitForChild("Localization"))

local Theme = require(script.Parent.Parent.UI.Theme)
local Build = require(script.Parent.Parent.UI.Build)
local Anim = require(script.Parent.Parent.UI.Anim)
local Messages = require(script.Parent.Parent.UI.Messages)
local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local UIController = require(script.Parent.UIController)
local SoundController = require(script.Parent.SoundController)
local NotificationController = require(script.Parent.NotificationController)

local WIDTH = 84
local GAP = 10
local PASS_KEY = "AutoClick"

local AutoClickController = {}

local toggle: TextButton
local offer: Frame
local busy = false

local function owns(): boolean
	return Players.LocalPlayer:GetAttribute("Pass_" .. PASS_KEY) == true
end

-- O servidor liga o Auto Clique ao conceder o passe; sem o atributo ainda,
-- quem tem o passe está ligado.
function AutoClickController.IsOn(): boolean
	local value = Players.LocalPlayer:GetAttribute("AutoClickOn")
	if type(value) == "boolean" then
		return value
	end
	return owns()
end

function AutoClickController.Refresh()
	if not toggle then
		return
	end
	if not owns() then
		toggle.Text = Text.Get("autoClick.locked")
		Build.paint(toggle, "BackgroundColor3", Theme.Hud.Surface)
		toggle.TextColor3 = Theme.Colors.TextDim
		return
	end
	offer.Visible = false
	local on = AutoClickController.IsOn()
	toggle.Text = Text.Get(if on then "autoClick.on" else "autoClick.off")
	Build.paint(toggle, "BackgroundColor3", if on then Theme.Colors.Good else Theme.Hud.Surface)
	toggle.TextColor3 = Theme.Colors.Text
end

local function onToggle()
	if busy then
		return
	end
	if not owns() then
		offer.Visible = not offer.Visible
		if offer.Visible then
			Anim.PopIn(offer, 0.25)
		end
		return
	end
	busy = true
	local response = ClientNet.Invoke("SetAutoClick", not AutoClickController.IsOn())
	busy = false
	if response.Ok then
		SoundController.Play("Click")
		Anim.Pop(toggle, 1.1)
	else
		NotificationController.Show(Messages.ForCode(response.Code), "Bad")
	end
	AutoClickController.Refresh()
end

function AutoClickController.Init()
	local canvas = UIController.GetCanvas()
	local hud = Theme.Hud
	local touch = UIController.IsTouch()
	local clickWidth = hud.ClickWidth + (if touch then hud.ClickTouchExtra.X else 0)
	local clickHeight = hud.ClickHeight + (if touch then hud.ClickTouchExtra.Y else 0)
	local height = math.floor(clickHeight * 0.72)

	toggle = Build.button({
		Name = "AutoClick",
		Text = "",
		Font = Theme.FontDisplay,
		TextSize = if touch then 15 else 16,
		BackgroundColor3 = hud.Surface,
		BackgroundTransparency = 0.15,
		AnchorPoint = Vector2.new(1, 1),
		-- À esquerda do CLIQUE!, alinhado pela base.
		Position = UDim2.new(0.5, -(clickWidth / 2 + GAP), 1, -hud.ClickBottom),
		Size = UDim2.fromOffset(WIDTH, height),
		ZIndex = 10,
		Parent = canvas,
	})
	Build.corner(toggle, UDim.new(0, 12))
	toggle.Activated:Connect(onToggle)

	-- Oferta para quem não tem o passe: uma linha de benefício + Comprar.
	offer = Build.new("Frame", {
		Name = "AutoClickOffer",
		BackgroundColor3 = hud.Surface,
		BackgroundTransparency = 0.1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(0.5, -(clickWidth / 2 + GAP), 1, -(hud.ClickBottom + height + 8)),
		Size = UDim2.fromOffset(250, 96),
		Visible = false,
		ZIndex = 30,
		Parent = canvas,
	})
	Build.corner(offer, UDim.new(0, 12))
	Build.label({
		Text = Text.Get("pass." .. PASS_KEY .. ".name"),
		Font = Theme.FontDisplay,
		TextSize = 17,
		TextColor3 = Theme.Colors.Power,
		Position = UDim2.fromOffset(10, 6),
		Size = UDim2.new(1, -20, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 31,
		Parent = offer,
	})
	Build.label({
		Text = Text.Get("pass." .. PASS_KEY .. ".desc"),
		TextSize = 14,
		TextWrapped = true,
		TextColor3 = Theme.Colors.TextDim,
		Position = UDim2.fromOffset(10, 28),
		Size = UDim2.new(1, -20, 0, 32),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 31,
		Parent = offer,
	})
	local buy = Build.button({
		Text = Text.Get("autoClick.buy"),
		TextSize = 15,
		BackgroundColor3 = Theme.Colors.Good,
		Position = UDim2.fromOffset(10, 62),
		Size = UDim2.new(0.6, -14, 0, 28),
		ZIndex = 31,
		Parent = offer,
	})
	Build.corner(buy, UDim.new(0, 8))
	buy.Activated:Connect(function()
		offer.Visible = false
		local response = ClientNet.Invoke("PromptPurchase", PASS_KEY)
		if not response.Ok then
			NotificationController.Show(Messages.ForCode(response.Code), "Bad")
		end
	end)
	local close = Build.button({
		Text = Text.Get("autoClick.close"),
		TextSize = 15,
		BackgroundColor3 = Theme.Colors.PanelLight,
		Position = UDim2.new(0.6, 0, 0, 62),
		Size = UDim2.new(0.4, -10, 0, 28),
		ZIndex = 31,
		Parent = offer,
	})
	Build.corner(close, UDim.new(0, 8))
	close.Activated:Connect(function()
		offer.Visible = false
	end)

	local player = Players.LocalPlayer
	player:GetAttributeChangedSignal("Pass_" .. PASS_KEY):Connect(AutoClickController.Refresh)
	player:GetAttributeChangedSignal("AutoClickOn"):Connect(AutoClickController.Refresh)
	AutoClickController.Refresh()
end

return AutoClickController
