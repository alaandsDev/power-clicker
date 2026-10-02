--!strict
--[[
	MenuController
	Menu da direita, com HIERARQUIA (o pedido é explícito em não deixar todo
	botão do mesmo tamanho):

		PRINCIPAIS  — Melhorias, Pets, Ovos, Renascer. Só esses quatro ficam
		              sempre visíveis, mais o botão "Mais".
		SECUNDÁRIOS — Progresso, Auras, Espadas, Missões, Prêmios, Ranking,
		              Loja, Ajustes. Abrem no "Mais".

	O Progresso saiu da grade permanente: ele já aparece de forma contextual no
	Caminho do Poder, e lá é onde o jogador quer vê-lo.

	Quem decide o que é principal é PRIMARY_IDS aqui embaixo, e não cada
	controller: assim a hierarquia é uma decisão só, num lugar só.

	Cada tile mostra o nome sob o ícone, e uma dica ao passar o mouse.
]]

local Theme = require(script.Parent.Parent.UI.Theme)
local Build = require(script.Parent.Parent.UI.Build)
local Anim = require(script.Parent.Parent.UI.Anim)
local Text = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Localization"))
local UIController = require(script.Parent.UIController)

local MenuController = {}

local TOOLTIP_HEIGHT = 30

-- Os cinco sistemas que o jogador usa o tempo todo.
local PRIMARY_IDS: { [string]: boolean } = {
	Upgrades = true,
	Pets = true,
	Eggs = true,
	Rebirth = true,
}
local PRIMARY_SCALE = 1.15 -- tile principal é um pouco maior
local MORE_ID = "MoreToggle"

local menu: Frame? = nil
local secondaryMenu: Frame? = nil
local tooltip: TextLabel? = nil
local buttonsById: { [string]: TextButton } = {}
local badgePulses: { [Instance]: Tween } = {}
local secondaryOpen = false

local function getMenu(): Frame
	local existing = menu
	if existing then
		return existing
	end
	local hud = Theme.Hud
	local width = hud.MenuColumns * hud.MenuCell + (hud.MenuColumns - 1) * hud.Gap
	local height = hud.MenuRows * hud.MenuCell + (hud.MenuRows - 1) * hud.Gap
	local frame: Frame = Build.new("Frame", {
		Name = "Menu",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -hud.Margin, hud.MenuCenterY, 0),
		Size = UDim2.fromOffset(width, height),
		Parent = UIController.GetCanvas(),
	})
	Build.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(hud.MenuCell, hud.MenuCell),
		CellPadding = UDim2.fromOffset(hud.Gap, hud.Gap),
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Parent = frame,
	})
	menu = frame

	-- Grade dos secundários: mesma coluna, logo abaixo, fechada por padrão.
	local secondary: Frame = Build.new("Frame", {
		Name = "MenuSecondary",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -hud.Margin, hud.MenuCenterY, height / 2 + hud.Gap),
		Size = UDim2.fromOffset(width, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = UIController.GetCanvas(),
	})
	Build.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(hud.MenuCell, hud.MenuCell),
		CellPadding = UDim2.fromOffset(hud.Gap, hud.Gap),
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = secondary,
	})
	secondaryMenu = secondary

	local tip = Build.label({
		Name = "MenuTooltip",
		Text = "",
		TextSize = 16,
		BackgroundColor3 = Theme.Hud.Surface,
		BackgroundTransparency = 0.1,
		AnchorPoint = Vector2.new(1, 0.5),
		Size = UDim2.fromOffset(0, TOOLTIP_HEIGHT),
		AutomaticSize = Enum.AutomaticSize.X,
		Visible = false,
		ZIndex = 5,
		Parent = UIController.GetCanvas(),
	})
	Build.corner(tip, UDim.new(1, 0))
	Build.new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), Parent = tip })
	tooltip = tip
	return frame
end

local function showTooltip(button: TextButton, text: string?)
	local tip = tooltip
	if not tip then
		return
	end
	if not text then
		tip.Visible = false
		return
	end
	local hud = Theme.Hud
	local centre = UIController.CenterOf(button)
	-- As duas grades ficam coladas na direita, então a dica vai para a esquerda.
	tip.Text = text
	tip.Position = UDim2.fromOffset(centre.X - (hud.MenuCell / 2 + hud.Gap), centre.Y)
	tip.Visible = true
end

-- Adds a menu button; returns it so callers can badge/highlight it.
-- `id` (optional, stable, not localized) lets other controllers find it (tutorial).
-- `color` tints the tile border so each function keeps its identity.
function MenuController.AddButton(name: string, icon: string, color: Color3, order: number, onActivated: () -> (), id: string?): TextButton
	local primary = id ~= nil and PRIMARY_IDS[id] == true
	local parent = if primary then getMenu() else MenuController.GetSecondaryMenu()
	local button = Build.button({
		Name = (id or name) .. "Button",
		Text = "",
		LayoutOrder = order,
		Parent = parent,
	})
	if primary then
		-- Tiles principais ficam maiores: o UIGridLayout dá o tamanho da célula,
		-- então o destaque vem de uma escala por cima.
		Build.new("UIScale", { Scale = PRIMARY_SCALE, Parent = button })
	end
	-- Build.button adds corner + stroke; restyle them as a HUD tile.
	for _, child in button:GetChildren() do
		if child:IsA("UICorner") or (child:IsA("UIStroke") and child.ApplyStrokeMode == Enum.ApplyStrokeMode.Border) then
			child:Destroy()
		end
	end
	Build.hudSurface(button, UDim.new(0, 18), color)
	local hud = Theme.Hud
	Build.icon(icon, {
		Name = "Icon",
		TextSize = 28,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 4),
		Size = UDim2.new(0.72, 0, 1, -(hud.MenuCaption + 8)),
		Parent = button,
	})
	Build.label({
		Name = "Caption",
		Text = name,
		TextSize = hud.MenuCaption,
		TextScaled = true,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -3),
		Size = UDim2.new(1, -6, 0, hud.MenuCaption),
		Parent = button,
	})
	local badge = Build.label({
		Name = "Badge",
		Text = "!",
		TextSize = 18,
		BackgroundColor3 = Theme.Colors.Bad,
		BackgroundTransparency = 0,
		Size = UDim2.fromOffset(24, 24),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.9, 0.1),
		Visible = false,
		Parent = button,
	})
	Build.corner(badge, UDim.new(1, 0))
	button.Activated:Connect(onActivated)
	button.MouseEnter:Connect(function()
		showTooltip(button, name)
	end)
	button.MouseLeave:Connect(function()
		showTooltip(button, nil)
	end)
	if id then
		buttonsById[id] = button
	end
	return button
end

--[[
	A grade dos secundários, criando o menu se ele ainda não existe. O botão
	"Mais" nasce junto na grade principal, para o grupo ter como abrir.
]]
function MenuController.GetSecondaryMenu(): Frame
	if not secondaryMenu then
		getMenu()
	end
	local secondary = secondaryMenu
	assert(secondary, "secondary menu was not created")
	if not buttonsById[MORE_ID] then
		local toggle = Build.button({
			Name = "MoreButton",
			Text = "",
			LayoutOrder = 999,
			Parent = getMenu(),
		})
		for _, child in toggle:GetChildren() do
			if child:IsA("UICorner") or (child:IsA("UIStroke") and child.ApplyStrokeMode == Enum.ApplyStrokeMode.Border) then
				child:Destroy()
			end
		end
		Build.hudSurface(toggle, UDim.new(0, 18), Theme.Colors.TextDim)
		local hud = Theme.Hud
		Build.icon("⋯", {
			Name = "Icon",
			TextSize = 28,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 4),
			Size = UDim2.new(0.72, 0, 1, -(hud.MenuCaption + 8)),
			Parent = toggle,
		})
		local caption = Build.label({
			Name = "Caption",
			Text = Text.Get("menu.more"),
			TextSize = hud.MenuCaption,
			TextScaled = true,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -3),
			Size = UDim2.new(1, -6, 0, hud.MenuCaption),
			Parent = toggle,
		})
		toggle.Activated:Connect(function()
			secondaryOpen = not secondaryOpen
			secondary.Visible = secondaryOpen
			caption.Text = Text.Get(if secondaryOpen then "menu.less" else "menu.more")
		end)
		buttonsById[MORE_ID] = toggle
	end
	return secondary
end

function MenuController.GetButton(id: string): TextButton?
	return buttonsById[id]
end

-- Shows/hides the "!" badge on a menu button (e.g. something affordable).
function MenuController.SetBadge(button: TextButton, visible: boolean)
	local badge = button:FindFirstChild("Badge")
	if not badge or not badge:IsA("GuiObject") then
		return
	end
	if visible and not badge.Visible then
		Anim.PopIn(badge, 0.3)
		badgePulses[badge] = Anim.Pulse(badge, 1.2, 1)
	elseif not visible then
		local pulse = badgePulses[badge]
		if pulse then
			pulse:Cancel()
			badgePulses[badge] = nil
		end
	end
	badge.Visible = visible
end

return MenuController
