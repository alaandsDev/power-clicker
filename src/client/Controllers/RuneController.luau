--!strict
--[[
	RuneController
	"Runas" panel: the equipped slots on top (click a slot to free it) and the
	runes the player owns below, grouped by world, with how many copies of
	each. Runes only come from world bosses, so the list starts empty and the
	panel says where to get them.

	Everything here reads the replicated data; RuneService decides every equip.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local RuneConfig = require(Shared:WaitForChild("Config"):WaitForChild("RuneConfig"))
local WorldConfig = require(Shared:WaitForChild("Config"):WaitForChild("WorldConfig"))
local PetConfig = require(Shared:WaitForChild("Config"):WaitForChild("PetConfig"))
local RuneLogic = require(Shared:WaitForChild("Formulas"):WaitForChild("RuneLogic"))
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

type RuneData = Types.RuneData
type Card = {
	Rune: RuneData,
	Frame: Frame,
	Count: TextLabel,
	Button: TextButton,
}

local PANEL = "Runes"
local SLOT_HEIGHT = 74
local CARD_HEIGHT = 78
local HEADER_HEIGHT = 28

local RuneController = {}

local cards: { Card } = {}
local slotButtons: { TextButton } = {}
local totalLabel: TextLabel
local menuButton: TextButton
local busy = false

local function runesData(): Types.RunesData?
	local runes = DataController.Get("Runes")
	if type(runes) ~= "table" or type(runes.Owned) ~= "table" or type(runes.Equipped) ~= "table" then
		return nil
	end
	return runes
end

local function nameOf(rune: RuneData): string
	local world = WorldConfig.Worlds[rune.WorldId]
	return Text.Get("runes.label", {
		world = if world then Text.Name("world", world) else rune.WorldId,
		rarity = Text.Get("rarity." .. rune.Rarity),
	})
end

local function percentText(multiplier: number): string
	return tostring(math.floor((multiplier - 1) * 100 + 0.5))
end

local function refresh()
	local runes = runesData()
	if not runes then
		return
	end
	for index, button in slotButtons do
		local runeId = runes.Equipped[index]
		local rune = if runeId then RuneConfig.Runes[runeId] else nil
		button.Text = if rune then nameOf(rune) else Text.Get("runes.emptySlot")
		local rarity = if rune then PetConfig.Rarities[rune.Rarity] else nil
		Build.paint(button, "BackgroundColor3", if rarity then rarity.Color else Theme.Colors.PanelLight)
	end

	local owned = 0
	for _, card in cards do
		local count = RuneLogic.Count(runes, card.Rune.Id)
		card.Frame.Visible = count > 0
		if count > 0 then
			owned += 1
			local inUse = RuneLogic.EquippedCount(runes, card.Rune.Id)
			card.Count.Text = Text.Get("runes.owned", { count = count, equipped = inUse })
			local canEquip = #runes.Equipped < RuneConfig.Slots and inUse < count
			card.Button.Text = Text.Get(if canEquip then "runes.equip" else "runes.inUse")
			Build.paint(card.Button, "BackgroundColor3", if canEquip then Theme.Colors.Good else Theme.Colors.Disabled)
		end
	end

	totalLabel.Text = if owned > 0
		then Text.Get("runes.total", { percent = percentText(RuneLogic.Multiplier(runes)), icon = Theme.Icons.Power })
		else Text.Get("runes.none")
	-- Badge só quando há runa guardada E espaço para ela: antes, qualquer runa
	-- no inventário deixava a bolinha vermelha acesa para sempre.
	local spare = false
	for _, card in cards do
		if RuneLogic.Count(runes, card.Rune.Id) > RuneLogic.EquippedCount(runes, card.Rune.Id) then
			spare = true
			break
		end
	end
	MenuController.SetBadge(menuButton, spare and #runes.Equipped < RuneConfig.Slots)
end

local function send(action: string, value: (string | number)?, button: TextButton)
	if busy then
		return
	end
	busy = true
	local response = ClientNet.Invoke("RuneAction", action, value)
	busy = false
	if response.Ok then
		SoundController.Play("Click")
		Anim.Pop(button, 1.12)
	else
		Anim.Shake(button, 5, 0.25)
		NotificationController.Show(Messages.ForCode(response.Code), "Bad")
	end
end

local function createCard(list: ScrollingFrame, rune: RuneData, order: number)
	local frame: Frame = Build.new("Frame", {
		Name = rune.Id,
		BackgroundColor3 = Theme.Colors.PanelLight,
		Size = UDim2.new(1, -12, 0, CARD_HEIGHT),
		LayoutOrder = order,
		Visible = false,
		ZIndex = 22,
		Parent = list,
	})
	Build.corner(frame, Theme.CornerSmall)
	local rarity = PetConfig.Rarities[rune.Rarity]
	Build.label({
		Text = nameOf(rune),
		TextSize = 22,
		TextColor3 = if rarity then rarity.Color else Theme.Colors.Text,
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.new(1, -190, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 23,
		Parent = frame,
	})
	Build.label({
		Text = Text.Get("runes.bonus", { percent = percentText(rune.PowerMultiplier), icon = Theme.Icons.Power }),
		TextSize = 17,
		TextColor3 = Theme.Colors.TextDim,
		Position = UDim2.fromOffset(14, 36),
		Size = UDim2.new(1, -190, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 23,
		Parent = frame,
	})
	local count = Build.label({
		Text = "",
		TextSize = 16,
		TextColor3 = Theme.Colors.TextDim,
		Position = UDim2.fromOffset(14, 56),
		Size = UDim2.new(1, -190, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 23,
		Parent = frame,
	})
	local button = Build.button({
		Text = "",
		TextSize = 20,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(160, 52),
		ZIndex = 23,
		Parent = frame,
	})
	button.Activated:Connect(function()
		send("Equip", rune.Id, button)
	end)
	table.insert(cards, { Rune = rune, Frame = frame, Count = count, Button = button })
end

function RuneController.Init()
	local _, content = UIController.CreatePanel(PANEL, Text.Get("runes.title", { icon = Theme.Icons.Runes }), Vector2.new(660, 580))

	-- Equipped slots.
	local slots: Frame = Build.new("Frame", {
		Name = "Slots",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, SLOT_HEIGHT),
		ZIndex = 22,
		Parent = content,
	})
	Build.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = slots,
	})
	for index = 1, RuneConfig.Slots do
		local button = Build.button({
			Name = "Slot" .. tostring(index),
			Text = "",
			TextSize = 18,
			TextWrapped = true,
			BackgroundColor3 = Theme.Colors.PanelLight,
			Size = UDim2.new(1 / RuneConfig.Slots, -6, 1, -8),
			LayoutOrder = index,
			ZIndex = 22,
			Parent = slots,
		})
		button.Activated:Connect(function()
			send("Unequip", index, button)
		end)
		slotButtons[index] = button
	end

	totalLabel = Build.label({
		Name = "Total",
		Text = "",
		TextSize = 18,
		TextColor3 = Theme.Colors.TextDim,
		Position = UDim2.fromOffset(4, SLOT_HEIGHT),
		Size = UDim2.new(1, -8, 0, HEADER_HEIGHT),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 22,
		Parent = content,
	})

	local top = SLOT_HEIGHT + HEADER_HEIGHT + 4
	local list: ScrollingFrame = Build.new("ScrollingFrame", {
		Name = "List",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, top),
		Size = UDim2.new(1, 0, 1, -top),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 8,
		ZIndex = 22,
		Parent = content,
	})
	Build.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })

	-- Worlds in play order; a rune card stays hidden until one drops.
	local worlds: { Types.WorldData } = {}
	for _, world in WorldConfig.Worlds do
		table.insert(worlds, world)
	end
	table.sort(worlds, function(a, b)
		return a.Order < b.Order
	end)
	for _, world in worlds do
		for _, rune in RuneLogic.OfWorld(world.Id) do
			createCard(list, rune, rune.Order)
		end
	end

	menuButton = MenuController.AddButton(Text.Get("menu.runes"), Theme.Icons.Runes, Theme.Colors.Gems, 3, function()
		UIController.TogglePanel(PANEL)
	end, "Runes")

	DataController.Changed:Connect(function(key: string)
		if key == "Runes" then
			refresh()
		end
	end)
	ClientNet.On("Notify", function(kind: any, payload: any)
		if kind ~= "RuneDropped" or type(payload) ~= "table" then
			return
		end
		local rune = RuneConfig.Runes[payload.RuneId]
		if rune then
			SoundController.Play("Reward")
			NotificationController.Show(Text.Get("runes.dropped", { name = nameOf(rune) }), "Good")
		end
	end)
	refresh()
end

return RuneController
