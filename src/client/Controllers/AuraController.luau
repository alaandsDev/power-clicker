--!strict
--[[
	AuraController
	Painel "Auras", com duas abas:

		Poder  — as auras compradas com gemas (velocidade + Power). São as que
		         já estavam vendidas; ninguém perde o que pagou.
		Visual — as auras cosméticas por raridade, ganhas por progressão. Não
		         dão multiplicador nenhum, e a linha de cada uma diz isso.

	O painel só mostra o que os dados replicados dizem; comprar e equipar é
	decidido no servidor (AuraService e AuraSkinService).
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local NumberFormat = require(Shared:WaitForChild("Utils"):WaitForChild("NumberFormat"))
local AuraConfig = require(Shared:WaitForChild("Config"):WaitForChild("AuraConfig"))
local PetConfig = require(Shared:WaitForChild("Config"):WaitForChild("PetConfig"))
local AuraLogic = require(Shared:WaitForChild("Formulas"):WaitForChild("AuraLogic"))
local AuraSkinConfig = require(Shared:WaitForChild("Config"):WaitForChild("AuraSkinConfig"))
local AuraSkinLogic = require(Shared:WaitForChild("Formulas"):WaitForChild("AuraSkinLogic"))
local WallConfig = require(Shared:WaitForChild("Config"):WaitForChild("WallConfig"))
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

type AuraData = Types.AuraData
type Row = {
	Aura: AuraData,
	Frame: Frame,
	Button: TextButton,
	Bullet: Frame,
}

local PANEL = "Auras"
local ROW_HEIGHT = 96
local BULLET_SIZE = 66

local AuraController = {}

type SkinRow = {
	Skin: AuraSkinConfig.AuraSkinData,
	Frame: Frame,
	Button: TextButton,
}

local rows: { Row } = {}
local skinRows: { SkinRow } = {}
local tabs: { [string]: { Button: TextButton, List: ScrollingFrame } } = {}
local menuButton: TextButton
local busy = false

-- "1.2" for 1.2x (one decimal, no trailing ".0").
local function multiplierText(multiplier: number): string
	local rounded = math.floor(multiplier * 10 + 0.5) / 10
	return if rounded % 1 == 0 then tostring(math.floor(rounded)) else string.format("%.1f", rounded)
end

local function refresh()
	local auras = DataController.Get("Auras")
	local currencies = DataController.Get("Currencies") or {}
	if type(auras) ~= "table" then
		return
	end
	local winsTotal = currencies.Wins or 0
	local gems = currencies[AuraConfig.Currency] or 0
	local anyAffordable = false

	for _, row in rows do
		local owned = auras.Owned[row.Aura.Id] == true
		local equipped = auras.Equipped == row.Aura.Id
		Build.paint(row.Frame, "BackgroundColor3", if equipped then Theme.Colors.Accent else Theme.Colors.PanelLight)

		if equipped then
			row.Button.Text = Text.Get("auras.equipped")
			Build.paint(row.Button, "BackgroundColor3", Theme.Colors.Disabled)
		elseif owned then
			row.Button.Text = Text.Get("auras.equip")
			Build.paint(row.Button, "BackgroundColor3", Theme.Colors.Good)
		elseif winsTotal < row.Aura.RequiredWins then
			row.Button.Text = Text.Get("auras.needsWins", { count = NumberFormat.Short(row.Aura.RequiredWins), icon = Theme.Icons.Wins })
			Build.paint(row.Button, "BackgroundColor3", Theme.Colors.Disabled)
		else
			local affordable = gems >= row.Aura.Price
			row.Button.Text = Theme.Icons.Gems .. " " .. NumberFormat.Short(row.Aura.Price)
			Build.paint(row.Button, "BackgroundColor3", if affordable then Theme.Colors.Good else Theme.Colors.Disabled)
			anyAffordable = anyAffordable or affordable
		end
	end
	MenuController.SetBadge(menuButton, anyAffordable)
end

local function send(row: Row)
	if busy then
		return
	end
	local auras = DataController.Get("Auras")
	if type(auras) ~= "table" or auras.Equipped == row.Aura.Id then
		return
	end
	local action = if auras.Owned[row.Aura.Id] == true then "Equip" else "Buy"
	busy = true
	local response = ClientNet.Invoke("AuraAction", action, row.Aura.Id)
	busy = false
	if response.Ok then
		SoundController.Play(if action == "Buy" then "Purchase" else "Click")
		Anim.Pop(row.Button, 1.15)
		Anim.Flash(row.Frame, row.Aura.Color)
	else
		Anim.Shake(row.Button, 5, 0.25)
		NotificationController.Show(Messages.ForCode(response.Code), "Bad")
	end
end

local function showTab(name: string)
	for tabName, tab in tabs do
		tab.List.Visible = tabName == name
		Build.paint(tab.Button, "BackgroundColor3", if tabName == name then Theme.Colors.Accent else Theme.Colors.PanelLight)
	end
end

-- O que falta para liberar uma aura cosmética, em uma linha.
local function skinLockText(skin: AuraSkinConfig.AuraSkinData): string
	local unlock = skin.Unlock
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

local function refreshSkins()
	local skins = DataController.Get("AuraSkins")
	if type(skins) ~= "table" or type(skins.Owned) ~= "table" then
		return
	end
	for _, row in skinRows do
		local owned = skins.Owned[row.Skin.Id] == true
		local equipped = skins.Equipped == row.Skin.Id
		Build.paint(row.Frame, "BackgroundColor3", if equipped then Theme.Colors.Accent else Theme.Colors.PanelLight)
		if equipped then
			row.Button.Text = Text.Get("auras.equipped")
			Build.paint(row.Button, "BackgroundColor3", Theme.Colors.Disabled)
		elseif owned then
			row.Button.Text = Text.Get("auras.equip")
			Build.paint(row.Button, "BackgroundColor3", Theme.Colors.Good)
		else
			row.Button.Text = skinLockText(row.Skin)
			Build.paint(row.Button, "BackgroundColor3", Theme.Colors.Disabled)
		end
	end
end

local function equipSkin(row: SkinRow)
	local skins = DataController.Get("AuraSkins")
	if busy or type(skins) ~= "table" or skins.Equipped == row.Skin.Id then
		return
	end
	if skins.Owned[row.Skin.Id] ~= true then
		NotificationController.Show(skinLockText(row.Skin), "Bad")
		return
	end
	busy = true
	local response = ClientNet.Invoke("AuraSkinAction", row.Skin.Id)
	busy = false
	if response.Ok then
		SoundController.Play("Click")
		Anim.Pop(row.Button, 1.12)
		Anim.Flash(row.Frame, row.Skin.Color)
	else
		Anim.Shake(row.Button, 5, 0.25)
		NotificationController.Show(Messages.ForCode(response.Code), "Bad")
	end
end

local function createSkinRow(list: ScrollingFrame, skin: AuraSkinConfig.AuraSkinData)
	local frame: Frame = Build.new("Frame", {
		Name = skin.Id,
		BackgroundColor3 = Theme.Colors.PanelLight,
		Size = UDim2.new(1, -12, 0, ROW_HEIGHT),
		LayoutOrder = skin.Order,
		ZIndex = 22,
		Parent = list,
	})
	Build.corner(frame, Theme.CornerSmall)

	-- Amostra: um círculo na cor da aura, com a cor secundária por dentro.
	local sample: Frame = Build.new("Frame", {
		Name = "Sample",
		BackgroundColor3 = skin.Color,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(BULLET_SIZE, BULLET_SIZE),
		ZIndex = 23,
		Parent = frame,
	})
	Build.corner(sample, UDim.new(1, 0))
	local inner: Frame = Build.new("Frame", {
		BackgroundColor3 = skin.SecondaryColor,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.55, 0.55),
		ZIndex = 24,
		Parent = sample,
	})
	Build.corner(inner, UDim.new(1, 0))

	local rarity = PetConfig.Rarities[skin.Rarity]
	Build.label({
		Text = Text.Name("auraSkin", skin),
		TextSize = 24,
		TextColor3 = if rarity then rarity.Color else Theme.Colors.Text,
		Position = UDim2.fromOffset(92, 10),
		Size = UDim2.new(1, -300, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 23,
		Parent = frame,
	})
	Build.label({
		Text = Text.Get("auras.skinEffect", {
			rarity = Text.Get("rarity." .. skin.Rarity),
			rate = tostring(math.floor(AuraSkinLogic.SafeRate(skin))),
		}),
		TextSize = 17,
		TextColor3 = Theme.Colors.TextDim,
		Position = UDim2.fromOffset(92, 42),
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
	local row: SkinRow = { Skin = skin, Frame = frame, Button = button }
	button.Activated:Connect(function()
		equipSkin(row)
	end)
	table.insert(skinRows, row)
end

local function createRow(list: ScrollingFrame, aura: AuraData)
	local frame: Frame = Build.new("Frame", {
		Name = aura.Id,
		BackgroundColor3 = Theme.Colors.PanelLight,
		Size = UDim2.new(1, -12, 0, ROW_HEIGHT),
		LayoutOrder = aura.Order,
		ZIndex = 22,
		Parent = list,
	})
	Build.corner(frame, Theme.CornerSmall)

	-- Tile in the aura's own colour, with the flame on it: the ring the player
	-- will wear, readable before you buy it.
	local bullet: Frame = Build.new("Frame", {
		Name = "Color",
		BackgroundColor3 = aura.Color,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(BULLET_SIZE, BULLET_SIZE),
		ZIndex = 23,
		Parent = frame,
	})
	Build.corner(bullet, Theme.CornerSmall)
	Build.label({
		Text = Theme.Icons.Auras,
		TextSize = 34,
		TextScaled = true,
		Size = UDim2.fromScale(0.72, 0.72),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = 24,
		Parent = bullet,
	})

	local rarity = PetConfig.Rarities[aura.Rarity]
	Build.label({
		Text = Text.Name("aura", aura),
		TextSize = 24,
		Position = UDim2.fromOffset(92, 10),
		Size = UDim2.new(1, -250, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = if rarity then rarity.Color else Theme.Colors.Text,
		ZIndex = 23,
		Parent = frame,
	})
	Build.label({
		Text = Text.Get("auras.bonus", {
			speed = aura.WalkSpeedBonus,
			mult = multiplierText(aura.PowerMultiplier),
		}),
		TextSize = 20,
		-- The multiplier is what the player compares, so it gets the accent.
		TextColor3 = Theme.Colors.Power,
		Position = UDim2.fromOffset(92, 44),
		Size = UDim2.new(1, -250, 0, 40),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 23,
		Parent = frame,
	})
	local button = Build.button({
		Text = "",
		TextSize = 22,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(200, 58),
		ZIndex = 23,
		Parent = frame,
	})
	local row: Row = { Aura = aura, Frame = frame, Button = button, Bullet = bullet }
	button.Activated:Connect(function()
		send(row)
	end)
	table.insert(rows, row)
end

function AuraController.Init()
	local _, content = UIController.CreatePanel(PANEL, Text.Get("auras.title", { icon = Theme.Icons.Auras }), Vector2.new(640, 560))

	-- Abas: Poder (gemas) e Visual (cosmética).
	local tabBar: Frame = Build.new("Frame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 44),
		ZIndex = 22,
		Parent = content,
	})
	Build.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = tabBar,
	})

	local function makeList(): ScrollingFrame
		local list: ScrollingFrame = Build.new("ScrollingFrame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, 52),
			Size = UDim2.new(1, 0, 1, -52),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(),
			ScrollBarThickness = 8,
			ZIndex = 22,
			Parent = content,
		})
		Build.new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
		return list
	end

	for index, tabName in { "Power", "Looks" } do
		local button = Build.button({
			Name = "Tab" .. tabName,
			Text = Text.Get("auras.tab" .. tabName),
			TextSize = 19,
			BackgroundColor3 = Theme.Colors.PanelLight,
			Size = UDim2.new(0.5, -4, 1, 0),
			LayoutOrder = index,
			ZIndex = 22,
			Parent = tabBar,
		})
		button.Activated:Connect(function()
			showTab(tabName)
		end)
		tabs[tabName] = { Button = button, List = makeList() }
	end

	for _, aura in AuraLogic.Ordered() do
		createRow(tabs.Power.List, aura)
	end
	for _, skin in AuraSkinLogic.Ordered() do
		createSkinRow(tabs.Looks.List, skin)
	end
	showTab("Power")

	menuButton = MenuController.AddButton(Text.Get("menu.auras"), Theme.Icons.Auras, Theme.Colors.Accent, 2, function()
		UIController.TogglePanel(PANEL)
	end, "Auras")

	DataController.Changed:Connect(function(key: string)
		if key == "Auras" or key == "Currencies" then
			refresh()
		elseif key == "AuraSkins" then
			refreshSkins()
		end
	end)
	ClientNet.On("Notify", function(kind: any, payload: any)
		if kind ~= "AuraSkinUnlocked" or type(payload) ~= "table" then
			return
		end
		local skin = AuraSkinConfig.Skins[payload.SkinId]
		if skin then
			SoundController.Play("Reward")
			NotificationController.Show(Text.Get("auras.skinUnlocked", { name = Text.Name("auraSkin", skin) }), "Good")
		end
	end)
	refresh()
	refreshSkins()
end

return AuraController
