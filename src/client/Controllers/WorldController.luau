--!strict
--[[
	WorldController
	Worlds panel: every world in order with multiplier, requirement and one
	action (Travel / Unlock / Locked / Coming soon / You are here).
	Unlock and travel are server requests; the server teleports the character.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local NumberFormat = require(Shared:WaitForChild("Utils"):WaitForChild("NumberFormat"))
local WorldRules = require(Shared:WaitForChild("Formulas"):WaitForChild("WorldRules"))
local Text = require(Shared:WaitForChild("Localization"))

local Theme = require(script.Parent.Parent.UI.Theme)
local Build = require(script.Parent.Parent.UI.Build)
local Messages = require(script.Parent.Parent.UI.Messages)
local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local UIController = require(script.Parent.UIController)
local MenuController = require(script.Parent.MenuController)
local DataController = require(script.Parent.DataController)
local SoundController = require(script.Parent.SoundController)
local NotificationController = require(script.Parent.NotificationController)

type WorldData = Types.WorldData
type Row = { World: WorldData, Status: TextLabel, Button: TextButton }

local PANEL = "Worlds"

local WorldController = {}

local rows: { Row } = {}
local busy = false

local function iconFor(currency: string): string
	return if currency == "Gems" then Theme.Icons.Gems else Theme.Icons.Power
end

local function refresh()
	local worlds = DataController.Get("Worlds")
	local stats = DataController.Get("Stats")
	if not worlds or not stats then
		return
	end
	for _, row in rows do
		local world = row.World
		local unlocked = worlds.Unlocked[world.Id] == true
		local requirement = world.Requirement
		row.Status.Text = Text.Get("worlds.multiplier", { mult = NumberFormat.Short(world.Multiplier) })
			.. "\n"
			.. (if requirement.Cost > 0
				then Text.Get("worlds.requirement", { rebirths = requirement.Rebirths, icon = iconFor(requirement.Currency), cost = NumberFormat.Short(requirement.Cost) })
				else Text.Get("worlds.requirementFree", { rebirths = requirement.Rebirths }))

		local key: string, color: Color3, active: boolean
		if not WorldRules.IsEnabled(world) then
			key, color, active = "worlds.soon", Theme.Colors.Disabled, false
		elseif worlds.Current == world.Id then
			key, color, active = "worlds.current", Theme.Colors.PanelLight, false
		elseif unlocked then
			key, color, active = "worlds.travel", Theme.Colors.Good, true
		else
			local previous = WorldRules.Previous(world)
			local reachable = (previous == nil or worlds.Unlocked[previous.Id] == true) and (stats.Rebirths or 0) >= requirement.Rebirths
			key, color, active = if reachable then "worlds.unlock" else "worlds.locked", if reachable then Theme.Colors.Accent else Theme.Colors.Disabled, true
		end
		row.Button.Text = Text.Get(key)
		Build.paint(row.Button, "BackgroundColor3", color)
		row.Button.Active = active
		row.Button.AutoButtonColor = active
	end
end

local function act(world: WorldData)
	local worlds = DataController.Get("Worlds")
	if busy or not worlds or not WorldRules.IsEnabled(world) or worlds.Current == world.Id then
		return
	end
	busy = true
	local unlocked = worlds.Unlocked[world.Id] == true
	local response = ClientNet.Invoke(if unlocked then "TravelWorld" else "UnlockWorld", world.Id)
	busy = false
	if not response.Ok then
		NotificationController.Show(Messages.ForCode(response.Code), "Bad")
		return
	end
	local name = Text.Name("world", world)
	if unlocked then
		UIController.ClosePanel()
		NotificationController.Show(Text.Get("worlds.welcome", { name = name }), "Good")
	else
		SoundController.Play("Reward")
		NotificationController.Show(Text.Get("worlds.unlockedToast", { name = name }), "Good")
	end
end

function WorldController.Init()
	local _, content = UIController.CreatePanel(PANEL, Text.Get("worlds.title", { icon = Theme.Icons.Worlds }), Vector2.new(640, 580))
	local list: ScrollingFrame = Build.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 8,
		ZIndex = 22,
		Parent = content,
	})
	Build.new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })

	for _, world in WorldRules.Ordered() do
		local frame: Frame = Build.new("Frame", {
			Name = world.Id,
			BackgroundColor3 = Theme.Colors.PanelLight,
			Size = UDim2.new(1, -12, 0, 96),
			LayoutOrder = world.Order,
			ZIndex = 22,
			Parent = list,
		})
		Build.corner(frame, Theme.CornerSmall)
		Build.label({
			Text = Theme.Icons.Worlds .. " " .. Text.Name("world", world),
			TextSize = 26,
			Position = UDim2.fromOffset(14, 6),
			Size = UDim2.new(1, -220, 0, 32),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 23,
			Parent = frame,
		})
		local status = Build.label({
			Text = "",
			TextSize = 17,
			TextColor3 = Theme.Colors.TextDim,
			Position = UDim2.fromOffset(14, 40),
			Size = UDim2.new(1, -220, 0, 48),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = 23,
			Parent = frame,
		})
		local button = Build.button({
			Text = "",
			TextSize = 20,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(190, 60),
			ZIndex = 23,
			Parent = frame,
		})
		button.Activated:Connect(function()
			act(world)
		end)
		table.insert(rows, { World = world, Status = status, Button = button })
	end

	--[[
		Sem entrada no menu: a torre é a progressão agora e os mundos 2–5 estão
		dormentes (docs/PLANO_TORRE.md §C3). O painel continua registrado e
		funcional — o portal do lobby ainda o abre, e religar os mundos é
		trocar um `Enabled` no WorldConfig, sem reescrever nada aqui.
	]]

	DataController.Changed:Connect(function(key: string)
		if key == "Worlds" or key == "Stats" or key == "Currencies" then
			refresh()
		end
	end)
end

return WorldController
