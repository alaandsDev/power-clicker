--!strict
--[[
	PetController
	Pets panel: inventory grid (equipped first, then strongest), selection bar
	with Equip/Unequip, Lock/Unlock, Delete (two-tap confirm) and Equip best.
	Cards are created/removed incrementally by uid (no full rebuild).
	Every action is a "PetAction" request validated by the server.

]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local NumberFormat = require(Shared:WaitForChild("Utils"):WaitForChild("NumberFormat"))
local PetConfig = require(Config:WaitForChild("PetConfig"))
local Text = require(Shared:WaitForChild("Localization"))

local Theme = require(script.Parent.Parent.UI.Theme)
local Build = require(script.Parent.Parent.UI.Build)
local Messages = require(script.Parent.Parent.UI.Messages)
local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local UIController = require(script.Parent.UIController)
local MenuController = require(script.Parent.MenuController)
local DataController = require(script.Parent.DataController)
local GameStateController = require(script.Parent.GameStateController)
local NotificationController = require(script.Parent.NotificationController)

type Card = { Button: TextButton, Status: TextLabel, Portrait: ImageLabel }

local PANEL = "Pets"
local DELETE_CONFIRM_SECONDS = 3

local PetController = {}

local grid: ScrollingFrame
local emptyLabel: TextLabel
local equippedLabel: TextLabel
local storageLabel: TextLabel
local multiplierLabel: TextLabel
local actionBar: Frame
local selectedLabel: TextLabel
local equipButton: TextButton
local lockButton: TextButton
local deleteButton: TextButton
local cards: { [string]: Card } = {}
local selectedUid: string? = nil
local deleteArmedAt = 0
local busy = false

local function petBonus(pet: any): number
	local config = PetConfig.Pets[pet.PetId]
	local variant = PetConfig.Variants[pet.Variant]
	if not config or not variant then
		return 0
	end
	return config.Bonus * variant.MultiplierScale
end

local function petName(pet: any): string
	local config = PetConfig.Pets[pet.PetId]
	return if config then Text.Name("pet", config) else tostring(pet.PetId)
end

local function rarityColor(pet: any): Color3
	local config = PetConfig.Pets[pet.PetId]
	local rarity = config and PetConfig.Rarities[config.Rarity]
	return if rarity then rarity.Color else Theme.Colors.Disabled
end

local function refreshSelection()
	local pets = DataController.Get("Pets")
	local pet = if pets and selectedUid then pets.Inventory[selectedUid] else nil
	if not pet or not selectedUid then
		selectedUid = nil
		selectedLabel.Text = Text.Get("pets.select")
		equipButton.Visible = false
		lockButton.Visible = false
		deleteButton.Visible = false
		return
	end
	local config = PetConfig.Pets[pet.PetId]
	local rarity = if config then Text.Get("rarity." .. config.Rarity) else "?"
	selectedLabel.Text = string.format("%s (%s) — %s", petName(pet), rarity, Text.Get("pets.bonus", { percent = NumberFormat.Short(petBonus(pet) * 100) }))
	local equipped = table.find(pets.Equipped, selectedUid) ~= nil
	equipButton.Visible = true
	equipButton.Text = Text.Get(if equipped then "pets.unequip" else "pets.equip")
	Build.paint(equipButton, "BackgroundColor3", if equipped then Theme.Colors.PanelLight else Theme.Colors.Good)
	lockButton.Visible = true
	lockButton.Text = Text.Get(if pet.Locked then "pets.unlock" else "pets.lock")
	deleteButton.Visible = not pet.Locked
	deleteButton.Text = Text.Get("pets.delete")
end

local function selectPet(uid: string)
	selectedUid = uid
	deleteArmedAt = 0
	refreshSelection()
end

local function createCard(uid: string): Card
	local button = Build.button({
		Name = uid,
		Text = "",
		BackgroundColor3 = Theme.Colors.PanelLight,
		ZIndex = 23,
		Parent = grid,
	})
	local status = Build.label({
		Name = "Status",
		Text = "",
		TextSize = 16,
		TextWrapped = true,
		Size = UDim2.new(1, -8, 1, -8),
		Position = UDim2.fromOffset(4, 4),
		ZIndex = 24,
		Parent = button,
	})
	local portrait: ImageLabel = Build.new("ImageLabel", {
		Name = "Portrait",
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 4),
		Size = UDim2.fromOffset(54, 54),
		Visible = false,
		ZIndex = 24,
		Parent = button,
	})
	button.Activated:Connect(function()
		selectPet(uid)
	end)
	return { Button = button, Status = status, Portrait = portrait }
end

local function refresh()
	local pets = DataController.Get("Pets")
	if not pets then
		return
	end
	local player = Players.LocalPlayer
	local equippedSet: { [string]: boolean } = {}
	for _, uid in pets.Equipped do
		equippedSet[uid] = true
	end

	local count = 0
	for uid, pet in pets.Inventory do
		count += 1
		local card = cards[uid] or createCard(uid)
		cards[uid] = card
		local equipped = equippedSet[uid] == true
		Build.paint(card.Button, "BackgroundColor3", rarityColor(pet))
		-- With an icon: image on top, text below. Without: text fills the card.
		local config = PetConfig.Pets[pet.PetId]
		local icon = if config then config.Icon else nil
		local hasIcon = Build.isAsset(icon)
		card.Portrait.Visible = hasIcon
		if hasIcon then
			card.Portrait.Image = icon :: string
			card.Status.Position = UDim2.fromOffset(4, 56)
			card.Status.Size = UDim2.new(1, -8, 0, 40)
			card.Status.TextSize = 13
		else
			card.Status.Position = UDim2.fromOffset(4, 4)
			card.Status.Size = UDim2.new(1, -8, 1, -8)
			card.Status.TextSize = 16
		end
		card.Status.Text = string.format(
			"%s%s\n%s",
			if equipped then Theme.Icons.Equipped .. " " else "",
			(if pet.Locked then Theme.Icons.Locked .. " " else "") .. petName(pet),
			Text.Get("pets.bonus", { percent = NumberFormat.Short(petBonus(pet) * 100) })
		)
		-- Equipped first, then strongest.
		card.Button.LayoutOrder = (if equipped then 0 else 1_000_000) - math.floor(petBonus(pet) * 1000)
	end
	for uid, card in cards do
		if not pets.Inventory[uid] then
			card.Button:Destroy()
			cards[uid] = nil
		end
	end

	emptyLabel.Visible = count == 0
	equippedLabel.Text = Text.Get("pets.equipped", { count = #pets.Equipped, max = player:GetAttribute("EquipCapacity") or PetConfig.BaseEquipSlots })
	storageLabel.Text = Text.Get("pets.storage", { count = count, max = player:GetAttribute("InventoryCapacity") or PetConfig.BaseInventorySlots })
	refreshSelection()
end

local function refreshMultiplier()
	local layers = GameStateController.GetPowerInfo().Layers
	multiplierLabel.Text = Text.Get("pets.multiplier", { mult = NumberFormat.Short(layers.Pet or 1) })
end

local function act(action: string, uid: string?)
	if busy then
		return
	end
	busy = true
	local response = ClientNet.Invoke("PetAction", action, uid)
	busy = false
	if not response.Ok then
		NotificationController.Show(Messages.ForCode(response.Code), "Bad")
	end
end

function PetController.Init()
	local _, content = UIController.CreatePanel(PANEL, Text.Get("pets.title", { icon = Theme.Icons.Pets }), Vector2.new(680, 600))

	local header: Frame = Build.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 56),
		ZIndex = 22,
		Parent = content,
	})
	equippedLabel = Build.label({ Text = "", TextSize = 20, Size = UDim2.new(0.5, -90, 0, 26), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 22, Parent = header })
	storageLabel = Build.label({ Text = "", TextSize = 20, Position = UDim2.fromOffset(0, 28), Size = UDim2.new(0.5, -90, 0, 26), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 22, Parent = header })
	multiplierLabel = Build.label({ Text = "", TextSize = 20, TextColor3 = Theme.Colors.Power, Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0.5, -200, 1, 0), ZIndex = 22, Parent = header })
	local best = Build.button({
		Text = Text.Get("pets.equipBest"),
		TextSize = 18,
		BackgroundColor3 = Theme.Colors.Accent,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(190, 52),
		ZIndex = 22,
		Parent = header,
	})
	best.Activated:Connect(function()
		act("EquipBest")
	end)

	grid = Build.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 64),
		Size = UDim2.new(1, 0, 1, -64 - 116),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 8,
		ZIndex = 22,
		Parent = content,
	})
	Build.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(120, 100),
		CellPadding = UDim2.fromOffset(10, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	emptyLabel = Build.label({
		Text = Text.Get("pets.empty"),
		TextSize = 22,
		TextColor3 = Theme.Colors.TextDim,
		Position = UDim2.fromOffset(0, 120),
		Size = UDim2.new(1, 0, 0, 40),
		ZIndex = 23,
		Parent = content,
	})

	actionBar = Build.new("Frame", {
		BackgroundColor3 = Theme.Colors.PanelLight,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 106),
		ZIndex = 22,
		Parent = content,
	})
	Build.corner(actionBar, Theme.CornerSmall)
	selectedLabel = Build.label({ Text = "", TextSize = 20, Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 30), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 23, Parent = actionBar })
	local buttons: Frame = Build.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 44), Size = UDim2.new(1, -24, 0, 52), ZIndex = 23, Parent = actionBar })
	Build.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), Parent = buttons })
	equipButton = Build.button({ Text = "", TextSize = 20, Size = UDim2.fromOffset(200, 52), ZIndex = 23, Parent = buttons })
	lockButton = Build.button({ Text = "", TextSize = 20, BackgroundColor3 = Theme.Colors.PanelLight, Size = UDim2.fromOffset(170, 52), ZIndex = 23, Parent = buttons })
	deleteButton = Build.button({ Text = "", TextSize = 20, BackgroundColor3 = Theme.Colors.Bad, Size = UDim2.fromOffset(170, 52), ZIndex = 23, Parent = buttons })

	equipButton.Activated:Connect(function()
		local pets = DataController.Get("Pets")
		local uid = selectedUid
		if not pets or not uid then
			return
		end
		act(if table.find(pets.Equipped, uid) then "Unequip" else "Equip", uid)
	end)
	lockButton.Activated:Connect(function()
		local pets = DataController.Get("Pets")
		local uid = selectedUid
		local pet = if pets and uid then pets.Inventory[uid] else nil
		if pet and uid then
			act(if pet.Locked then "Unlock" else "Lock", uid)
		end
	end)
	deleteButton.Activated:Connect(function()
		local uid = selectedUid
		if not uid then
			return
		end
		local now = os.clock()
		if now - deleteArmedAt > DELETE_CONFIRM_SECONDS then
			deleteArmedAt = now
			deleteButton.Text = "? " .. Text.Get("pets.delete") .. " ?"
			return
		end
		deleteArmedAt = 0
		act("Delete", uid)
	end)

	MenuController.AddButton(Text.Get("menu.pets"), Theme.Icons.Pets, Theme.Colors.Gems, 3, function()
		UIController.TogglePanel(PANEL)
	end, "Pets")

	DataController.Changed:Connect(function(key: string)
		if key == "Pets" then
			refresh()
		end
	end)
	GameStateController.PowerInfoChanged:Connect(refreshMultiplier)
	Players.LocalPlayer:GetAttributeChangedSignal("EquipCapacity"):Connect(refresh)
	Players.LocalPlayer:GetAttributeChangedSignal("InventoryCapacity"):Connect(refresh)
	refreshMultiplier()
	refreshSelection()
end

return PetController
