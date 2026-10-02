--!strict
--[[
	SwordController
	Painel "Espadas": lista as skins, mostra o efeito de cada uma e o que falta
	para liberar as que ainda estão fechadas.

	Elas são cosméticas: nenhuma linha aqui mostra dano, porque nenhuma delas dá
	dano. O que dá dano é o Corte, comprado nos pads da torre.

	Equipar vai pelo "SwordAction"; o servidor revalida a posse. Desbloqueio
	não se pede — o servidor concede quando a progressão chega lá.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local NumberFormat = require(Shared:WaitForChild("Utils"):WaitForChild("NumberFormat"))
local SwordConfig = require(Shared:WaitForChild("Config"):WaitForChild("SwordConfig"))
local WallConfig = require(Shared:WaitForChild("Config"):WaitForChild("WallConfig"))
local PetConfig = require(Shared:WaitForChild("Config"):WaitForChild("PetConfig"))
local SwordLogic = require(Shared:WaitForChild("Formulas"):WaitForChild("SwordLogic"))
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

type SwordData = Types.SwordData
type Row = {
	Sword: SwordData,
	Frame: Frame,
	Button: TextButton,
	Blade: Frame,
}

local PANEL = "Swords"
local ROW_HEIGHT = 96
local BLADE_WIDTH = 14
local BLADE_HEIGHT = 64

local SwordController = {}

local rows: { Row } = {}
local menuButton: TextButton
local busy = false
-- Uma skin foi liberada e o jogador ainda não abriu o painel.
local unseenUnlock = false

-- O que falta para liberar esta skin, em uma linha.
local function lockText(sword: SwordData): string
	local unlock = sword.Unlock
	if unlock.Kind == "Rebirths" then
		return Text.Get("swords.needsRebirths", { count = NumberFormat.Short(unlock.Value or 0) })
	elseif unlock.Kind == "Wins" then
		return Text.Get("swords.needsWins", { count = NumberFormat.Short(unlock.Value or 0), icon = Theme.Icons.Wins })
	elseif unlock.Kind == "TowerStage" then
		local order = 0
		for _, stage in WallConfig.Stages do
			if stage.Id == unlock.Stage then
				order = stage.Order
			end
		end
		return Text.Get("swords.needsStage", { order = tostring(order) })
	end
	return ""
end

local function refresh()
	local swords = DataController.Get("Swords")
	if type(swords) ~= "table" or type(swords.Owned) ~= "table" then
		return
	end
	for _, row in rows do
		local owned = swords.Owned[row.Sword.Id] == true
		local equipped = swords.Equipped == row.Sword.Id
		Build.paint(row.Frame, "BackgroundColor3", if equipped then Theme.Colors.Accent else Theme.Colors.PanelLight)
		row.Blade.Visible = owned
		if equipped then
			row.Button.Text = Text.Get("swords.equipped")
			Build.paint(row.Button, "BackgroundColor3", Theme.Colors.Disabled)
		elseif owned then
			row.Button.Text = Text.Get("swords.equip")
			Build.paint(row.Button, "BackgroundColor3", Theme.Colors.Good)
		else
			row.Button.Text = lockText(row.Sword)
			Build.paint(row.Button, "BackgroundColor3", Theme.Colors.Disabled)
		end
	end
	--[[
		Sem badge permanente: ter uma espada guardada não é "algo novo". A
		bolinha só acende quando uma skin é desbloqueada, e apaga ao abrir o
		painel.
	]]
	MenuController.SetBadge(menuButton, unseenUnlock)
end

local function equip(row: Row)
	local swords = DataController.Get("Swords")
	if busy or type(swords) ~= "table" or swords.Equipped == row.Sword.Id then
		return
	end
	if swords.Owned[row.Sword.Id] ~= true then
		NotificationController.Show(lockText(row.Sword), "Bad")
		return
	end
	busy = true
	local response = ClientNet.Invoke("SwordAction", row.Sword.Id)
	busy = false
	if response.Ok then
		SoundController.Play("Click")
		Anim.Pop(row.Button, 1.12)
		Anim.Flash(row.Frame, row.Sword.ArcColor)
	else
		Anim.Shake(row.Button, 5, 0.25)
		NotificationController.Show(Messages.ForCode(response.Code), "Bad")
	end
end

local function createRow(list: ScrollingFrame, sword: SwordData)
	local frame: Frame = Build.new("Frame", {
		Name = sword.Id,
		BackgroundColor3 = Theme.Colors.PanelLight,
		Size = UDim2.new(1, -12, 0, ROW_HEIGHT),
		LayoutOrder = sword.Order,
		ZIndex = 22,
		Parent = list,
	})
	Build.corner(frame, Theme.CornerSmall)

	--[[
		A lâmina desenhada: um retângulo na cor e na proporção da skin, com a
		ponta em diagonal. É a forma honesta de mostrar a espada sem precisar de
		um render 3D dentro do painel.
	]]
	local blade: Frame = Build.new("Frame", {
		Name = "Blade",
		BackgroundColor3 = sword.Color,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(42, ROW_HEIGHT / 2),
		Size = UDim2.fromOffset(BLADE_WIDTH * sword.ArcScale, BLADE_HEIGHT * math.min(sword.BladeSize.Y / 4.2, 1.35)),
		Rotation = 24,
		ZIndex = 23,
		Parent = frame,
	})
	Build.corner(blade, UDim.new(0, 3))
	Build.stroke(blade, 2, sword.ArcColor)
	Build.new("Frame", {
		Name = "Guard",
		BackgroundColor3 = Color3.fromRGB(120, 110, 90),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(BLADE_WIDTH * 2.4, 5),
		ZIndex = 23,
		Parent = blade,
	})

	local rarity = PetConfig.Rarities[sword.Rarity]
	Build.label({
		Text = Text.Name("sword", sword),
		TextSize = 24,
		TextColor3 = if rarity then rarity.Color else Theme.Colors.Text,
		Position = UDim2.fromOffset(82, 10),
		Size = UDim2.new(1, -300, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 23,
		Parent = frame,
	})
	Build.label({
		Text = Text.Get("swords.effect", {
			rarity = Text.Get("rarity." .. sword.Rarity),
			trail = string.format("%.2f", sword.TrailSeconds),
		}),
		TextSize = 17,
		TextColor3 = Theme.Colors.TextDim,
		Position = UDim2.fromOffset(82, 42),
		Size = UDim2.new(1, -300, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 23,
		Parent = frame,
	})
	local button = Build.button({
		Text = "",
		TextSize = 20,
		TextScaled = true,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(200, 56),
		ZIndex = 23,
		Parent = frame,
	})
	Build.new("UITextSizeConstraint", { MaxTextSize = 20, Parent = button })
	local row: Row = { Sword = sword, Frame = frame, Button = button, Blade = blade }
	button.Activated:Connect(function()
		equip(row)
	end)
	table.insert(rows, row)
end

function SwordController.Init()
	local _, content = UIController.CreatePanel(PANEL, Text.Get("swords.title", { icon = Theme.Icons.Swords }), Vector2.new(700, 580))

	Build.label({
		Text = Text.Get("swords.hint"),
		TextSize = 17,
		TextColor3 = Theme.Colors.TextDim,
		Position = UDim2.fromOffset(4, 0),
		Size = UDim2.new(1, -8, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 22,
		Parent = content,
	})

	local list: ScrollingFrame = Build.new("ScrollingFrame", {
		Name = "List",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 36),
		Size = UDim2.new(1, 0, 1, -36),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 8,
		ZIndex = 22,
		Parent = content,
	})
	Build.new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })

	for _, sword in SwordLogic.Ordered() do
		createRow(list, sword)
	end

	menuButton = MenuController.AddButton(Text.Get("menu.swords"), Theme.Icons.Swords, Theme.Colors.Bad, 4, function()
		unseenUnlock = false
		MenuController.SetBadge(menuButton, false)
		UIController.TogglePanel(PANEL)
	end, "Swords")

	DataController.Changed:Connect(function(key: string)
		if key == "Swords" then
			refresh()
		end
	end)
	ClientNet.On("Notify", function(kind: any, payload: any)
		if kind ~= "SwordUnlocked" or type(payload) ~= "table" then
			return
		end
		local sword = SwordConfig.Swords[payload.SwordId]
		if sword then
			SoundController.Play("Reward")
			NotificationController.Show(Text.Get("swords.unlocked", { name = Text.Name("sword", sword) }), "Good")
			unseenUnlock = true
			refresh()
		end
	end)
	refresh()
end

return SwordController
