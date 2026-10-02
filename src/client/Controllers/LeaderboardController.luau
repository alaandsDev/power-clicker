--!strict
--[[
	LeaderboardController
	"Ranking" panel with one tab per LeaderboardConfig board. Data comes from
	the server ("Leaderboards") every RefreshIntervalSeconds. Log-scaled
	boards (Power) are decoded for display: value = 10 ^ (stored / LogScale).
	The player's own row is highlighted.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local NumberFormat = require(Shared:WaitForChild("Utils"):WaitForChild("NumberFormat"))
local LeaderboardConfig = require(Shared:WaitForChild("Config"):WaitForChild("LeaderboardConfig"))
local Text = require(Shared:WaitForChild("Localization"))

local Signal = require(Shared:WaitForChild("Utils"):WaitForChild("Signal"))
local Theme = require(script.Parent.Parent.UI.Theme)
local Build = require(script.Parent.Parent.UI.Build)
local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local UIController = require(script.Parent.UIController)
local MenuController = require(script.Parent.MenuController)

local PANEL = "Ranking"
local BOARD_ORDER = { "Power", "Rebirths", "Clicks" }

local LeaderboardController = {
	-- Fired whenever a fresh snapshot arrives (the 3D scoreboards listen).
	BoardsChanged = Signal.new() :: Signal.Signal<{ [string]: any }>,
}

local list: ScrollingFrame
local noteLabel: TextLabel
local tabButtons: { [string]: TextButton } = {}
local currentBoard = BOARD_ORDER[1]
local boards: { [string]: any } = {}

local function decode(boardId: string, value: number): number
	local config = (LeaderboardConfig.Boards :: any)[boardId]
	if config and config.UseLogScale then
		return 10 ^ (value / config.LogScale)
	end
	return value
end

local function render()
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for id, button in tabButtons do
		Build.paint(button, "BackgroundColor3", if id == currentBoard then Theme.Colors.Accent else Theme.Colors.PanelLight)
	end
	local board = boards[currentBoard]
	if not board or #board.Entries == 0 then
		noteLabel.Text = Text.Get("ranking.empty")
		return
	end
	noteLabel.Text = if board.Local then Text.Get("ranking.local") else ""
	local myId = Players.LocalPlayer.UserId
	for _, entry in board.Entries do
		local mine = entry.UserId == myId
		local row = Build.label({
			Text = string.format("#%d  %s  —  %s", entry.Rank, tostring(entry.Name), NumberFormat.Short(decode(currentBoard, entry.Value))),
			TextSize = 20,
			TextColor3 = if mine then Theme.Colors.Power else Theme.Colors.Text,
			BackgroundTransparency = if mine then 0.6 else 1,
			BackgroundColor3 = Theme.Colors.Accent,
			Size = UDim2.new(1, -12, 0, 34),
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = entry.Rank,
			ZIndex = 23,
			Parent = list,
		})
		Build.padding(row, 6)
	end
end

function LeaderboardController.Init()
	local _, content = UIController.CreatePanel(PANEL, Text.Get("ranking.title", { icon = Theme.Icons.Ranking }), Vector2.new(600, 580))
	local tabBar: Frame = Build.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 46), ZIndex = 22, Parent = content })
	Build.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), Parent = tabBar })
	for _, boardId in BOARD_ORDER do
		local button = Build.button({ Text = Text.Get("ranking." .. boardId), TextSize = 18, Size = UDim2.new(1 / #BOARD_ORDER, -6, 1, 0), ZIndex = 22, Parent = tabBar })
		button.Activated:Connect(function()
			currentBoard = boardId
			render()
		end)
		tabButtons[boardId] = button
	end
	noteLabel = Build.label({ Text = "", TextSize = 16, TextColor3 = Theme.Colors.TextDim, Position = UDim2.fromOffset(0, 52), Size = UDim2.new(1, 0, 0, 22), ZIndex = 22, Parent = content })
	list = Build.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 80),
		Size = UDim2.new(1, 0, 1, -80),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 8,
		ZIndex = 22,
		Parent = content,
	})
	Build.new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })

	MenuController.AddButton(Text.Get("menu.ranking"), Theme.Icons.Ranking, Theme.Colors.PanelLight, 8, function()
		UIController.TogglePanel(PANEL)
	end)

	ClientNet.On("Leaderboards", function(payload: any)
		if type(payload) == "table" then
			boards = payload
			render()
			LeaderboardController.BoardsChanged:Fire(boards)
		end
	end)
	render()
end

-- Board ids in the order the panel (and the 3D scoreboards) show them.
function LeaderboardController.BoardOrder(): { string }
	return table.clone(BOARD_ORDER)
end

function LeaderboardController.GetBoards(): { [string]: any }
	return boards
end

function LeaderboardController.Decode(boardId: string, value: number): number
	return decode(boardId, value)
end

return LeaderboardController
