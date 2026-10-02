--!strict
--[[
	UpgradeController
	Upgrades panel with two tabs: Power upgrades (reset on rebirth) and Gem
	upgrades (permanent). Rows are built once and only their texts/colors are
	updated when data changes. Buying sends only the upgrade id; the server
	computes cost and level.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local NumberFormat = require(Shared:WaitForChild("Utils"):WaitForChild("NumberFormat"))
local EconomyFormulas = require(Shared:WaitForChild("Formulas"):WaitForChild("EconomyFormulas"))
local UpgradeConfig = require(Shared:WaitForChild("Config"):WaitForChild("UpgradeConfig"))
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

type UpgradeData = Types.UpgradeData
type Row = {
	Upgrade: UpgradeData,
	Group: string, -- "Temporary" | "Permanent"
	Level: TextLabel,
	Buy: TextButton,
}

local PANEL = "Upgrades"

local UpgradeController = {}

local rows: { Row } = {}
local lists: { [string]: ScrollingFrame } = {}
local tabButtons: { [string]: TextButton } = {}
local menuButton: TextButton
local busy = false
-- How many levels the buy buttons purchase: 1, 10 or 0 (as many as affordable).
local bulkAmount = UpgradeConfig.BulkOptions[1]
local bulkButtons: { [number]: TextButton } = {}

local function iconFor(currency: string): string
	return if currency == "Gems" then Theme.Icons.Gems else Theme.Icons.Power
end

local function refresh()
	local currencies = DataController.Get("Currencies") or {}
	local temporary = DataController.Get("Upgrades") or {}
	local permanent = DataController.Get("PermanentUpgrades") or {}
	local anyAffordable = false

	for _, row in rows do
		local levels = if row.Group == "Temporary" then temporary else permanent
		local level = levels[row.Upgrade.Id] or 0
		local balance = currencies[row.Upgrade.Currency] or 0
		row.Level.Text = Text.Get("upgrades.level", { level = level, max = row.Upgrade.MaxLevel })

		if level >= row.Upgrade.MaxLevel then
			row.Buy.Text = Text.Get("upgrades.max")
			Build.paint(row.Buy, "BackgroundColor3", Theme.Colors.Disabled)
			continue
		end
		-- Price of the NEXT levels, summed one by one: each costs more than the
		-- last, so ten levels is not ten times the first.
		local room = row.Upgrade.MaxLevel - level
		local wanted = if bulkAmount <= 0 then room else math.min(bulkAmount, room)
		local affordableLevels, affordableCost = 0, 0
		local total = 0
		for step = 0, wanted - 1 do
			local cost = EconomyFormulas.UpgradeCost(row.Upgrade, level + step)
			total += cost
			if total <= balance then
				affordableLevels = step + 1
				affordableCost = total
			end
		end
		-- "Max" shows what the player can actually take; 1x/10x show the full price.
		local shownLevels = if bulkAmount <= 0 then affordableLevels else wanted
		local shownCost = if bulkAmount <= 0 then affordableCost else total
		local affordable = affordableLevels >= shownLevels and shownLevels > 0
		row.Buy.Text = if shownLevels > 1
			then Text.Get("upgrades.buyMany", { count = shownLevels, icon = iconFor(row.Upgrade.Currency), cost = NumberFormat.Short(shownCost) })
			else iconFor(row.Upgrade.Currency) .. " " .. NumberFormat.Short(if shownLevels == 0 then EconomyFormulas.UpgradeCost(row.Upgrade, level) else shownCost)
		Build.paint(row.Buy, "BackgroundColor3", if affordable then Theme.Colors.Good else Theme.Colors.Disabled)
		if affordable and row.Group == "Temporary" then
			anyAffordable = true
		end
	end
	MenuController.SetBadge(menuButton, anyAffordable)
end

local function buy(upgradeId: string, button: TextButton)
	if busy then
		return
	end
	busy = true
	local response = ClientNet.Invoke("BuyUpgrade", upgradeId, bulkAmount)
	busy = false
	if response.Ok then
		SoundController.Play("Upgrade")
		Anim.Pop(button, 1.2)
		local row = button.Parent
		if row and row:IsA("GuiObject") then
			Anim.Flash(row, Theme.Colors.Good)
			-- Sparks inside the row (so they render above the panel), at the button.
			local at = UIController.CenterOf(button) - UIController.ToCanvas(row.AbsolutePosition)
			Anim.Burst(row, at, Theme.Colors.Power, 10, 50)
		end
	else
		Anim.Shake(button, 5, 0.25)
		NotificationController.Show(Messages.ForCode(response.Code), "Bad")
	end
end

local function showTab(group: string)
	for name, list in lists do
		list.Visible = name == group
		Build.paint(tabButtons[name], "BackgroundColor3", if name == group then Theme.Colors.Accent else Theme.Colors.PanelLight)
	end
end

local function createRow(list: ScrollingFrame, upgrade: UpgradeData, group: string)
	local frame: Frame = Build.new("Frame", {
		Name = upgrade.Id,
		BackgroundColor3 = Theme.Colors.PanelLight,
		Size = UDim2.new(1, -12, 0, 96),
		LayoutOrder = upgrade.Order,
		ZIndex = 22,
		Parent = list,
	})
	Build.corner(frame, Theme.CornerSmall)
	local texts = Text.Upgrade(upgrade)
	Build.label({
		Text = texts.Name,
		TextSize = 26,
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.new(1, -200, 0, 32),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 23,
		Parent = frame,
	})
	Build.label({
		Text = texts.Desc,
		TextSize = 18,
		TextColor3 = Theme.Colors.TextDim,
		Position = UDim2.fromOffset(14, 40),
		Size = UDim2.new(1, -200, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 23,
		Parent = frame,
	})
	local level = Build.label({
		Text = "",
		TextSize = 18,
		TextColor3 = Theme.Colors.TextDim,
		Position = UDim2.fromOffset(14, 64),
		Size = UDim2.new(1, -200, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 23,
		Parent = frame,
	})
	local buyButton = Build.button({
		Text = "",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(170, 60),
		TextSize = 24,
		ZIndex = 23,
		Parent = frame,
	})
	buyButton.Activated:Connect(function()
		buy(upgrade.Id, buyButton)
	end)
	table.insert(rows, { Upgrade = upgrade, Group = group, Level = level, Buy = buyButton })
end

function UpgradeController.Init()
	local _, content = UIController.CreatePanel(PANEL, Text.Get("upgrades.title", { icon = Theme.Icons.Upgrades }), Vector2.new(620, 560))

	local tabs: Frame = Build.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 48),
		ZIndex = 22,
		Parent = content,
	})
	Build.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), Parent = tabs })

	-- How many levels each buy button takes.
	local bulkBar: Frame = Build.new("Frame", {
		Name = "Bulk",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 54),
		Size = UDim2.new(1, 0, 0, 34),
		ZIndex = 22,
		Parent = content,
	})
	Build.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), Parent = bulkBar })
	for _, option in UpgradeConfig.BulkOptions do
		local button = Build.button({
			Name = "Bulk" .. tostring(option),
			Text = if option <= 0 then Text.Get("upgrades.bulkMax") else Text.Get("upgrades.bulkTimes", { count = option }),
			TextSize = 16,
			BackgroundColor3 = Theme.Colors.PanelLight,
			Size = UDim2.new(1 / #UpgradeConfig.BulkOptions, -6, 1, 0),
			ZIndex = 22,
			Parent = bulkBar,
		})
		button.Activated:Connect(function()
			bulkAmount = option
			for value, other in bulkButtons do
				Build.paint(other, "BackgroundColor3", if value == option then Theme.Colors.Accent else Theme.Colors.PanelLight)
			end
			refresh()
		end)
		bulkButtons[option] = button
	end

	for _, group in { "Temporary", "Permanent" } do
		local tab = Build.button({
			Text = if group == "Temporary" then Text.Get("upgrades.tabPower", { icon = Theme.Icons.Power }) else Text.Get("upgrades.tabGems", { icon = Theme.Icons.Gems }),
			BackgroundColor3 = Theme.Colors.PanelLight,
			Size = UDim2.new(0.5, -5, 1, 0),
			TextSize = 18,
			ZIndex = 22,
			Parent = tabs,
		})
		tab.Activated:Connect(function()
			showTab(group)
		end)
		tabButtons[group] = tab

		local list: ScrollingFrame = Build.new("ScrollingFrame", {
			Name = group,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, 96),
			Size = UDim2.new(1, 0, 1, -96),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(),
			ScrollBarThickness = 8,
			ZIndex = 22,
			Parent = content,
		})
		Build.new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
		lists[group] = list

		local configs: { [string]: UpgradeData } = if group == "Temporary" then UpgradeConfig.Temporary else UpgradeConfig.Permanent
		for _, upgrade in configs do
			createRow(list, upgrade, group)
		end
	end
	showTab("Temporary")
	Build.paint(bulkButtons[bulkAmount], "BackgroundColor3", Theme.Colors.Accent)

	menuButton = MenuController.AddButton(Text.Get("menu.upgrades"), Theme.Icons.Upgrades, Theme.Colors.Good, 1, function()
		UIController.TogglePanel(PANEL)
	end, "Upgrades")

	DataController.Changed:Connect(function(key: string)
		if key == "Currencies" or key == "Upgrades" or key == "PermanentUpgrades" then
			refresh()
		end
	end)
end

return UpgradeController
