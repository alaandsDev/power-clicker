--!strict
--[[
	ScoreboardController
	Draws the live ranking on the in-world boards built by WorldBuilder
	(parts with the "Scoreboard" attribute). One column per board
	(Power / Rebirths / Clicks), top ROW_COUNT players each.

	Data is the snapshot LeaderboardController already receives from the
	server, so nothing extra is replicated. Boards appear/disappear with the
	world models, so new parts are picked up as they are added.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local NumberFormat = require(Shared:WaitForChild("Utils"):WaitForChild("NumberFormat"))
local Text = require(Shared:WaitForChild("Localization"))

local Theme = require(script.Parent.Parent.UI.Theme)
local Build = require(script.Parent.Parent.UI.Build)
local LeaderboardController = require(script.Parent.LeaderboardController)

local ROW_COUNT = 8
local SURFACE_PIXELS = Vector2.new(1360, 880) -- board is 34 x 22 studs
local COLUMN_GAP = 16
local HEADER_HEIGHT = 96
local ROW_HEIGHT = 74
local ATTRIBUTE = "Scoreboard"

local ScoreboardController = {}

type Column = { Title: TextLabel, Rows: { TextLabel }, Mine: TextLabel }

local columnsByPart: { [BasePart]: { [string]: Column } } = {}

local function buildColumn(parent: Frame, boardId: string, index: number, total: number): Column
	local width = 1 / total
	local frame: Frame = Build.new("Frame", {
		Name = boardId,
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.25,
		Position = UDim2.fromScale(width * (index - 1), 0),
		Size = UDim2.new(width, -COLUMN_GAP, 1, 0),
		Parent = parent,
	})
	Build.corner(frame, UDim.new(0, 18))
	Build.stroke(frame, 3, Theme.Colors.Stroke)
	Build.padding(frame, 14)

	local title = Build.label({
		Name = "Title",
		Text = Text.Get("ranking." .. boardId),
		Font = Theme.FontDisplay,
		TextSize = 54,
		TextColor3 = Theme.Colors.Power,
		Size = UDim2.new(1, 0, 0, HEADER_HEIGHT - 20),
		Parent = frame,
	})

	local rows: { TextLabel } = {}
	for row = 1, ROW_COUNT do
		rows[row] = Build.label({
			Name = "Row" .. row,
			Text = "",
			TextSize = 42,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(0, HEADER_HEIGHT + (row - 1) * ROW_HEIGHT),
			Size = UDim2.new(1, 0, 0, ROW_HEIGHT - 8),
			Parent = frame,
		})
	end
	-- Footer: where the local player stands on this board.
	local mine = Build.label({
		Name = "Mine",
		Text = "",
		Font = Theme.FontDisplay,
		TextSize = 40,
		TextColor3 = Theme.Colors.Power,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		Parent = frame,
	})

	return { Title = title, Rows = rows, Mine = mine }
end

local function buildBoard(part: BasePart)
	if columnsByPart[part] then
		return
	end
	local surface: SurfaceGui = Build.new("SurfaceGui", {
		Name = "ScoreboardSurface",
		Face = Enum.NormalId.Left, -- the board faces the plaza (-X of the part)
		SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
		CanvasSize = SURFACE_PIXELS,
		LightInfluence = 0,
		MaxDistance = 260,
		Parent = part,
	})
	local header = Build.label({
		Name = "Header",
		Text = Theme.Icons.Ranking .. " " .. Text.Get("scoreboard.title"),
		Font = Theme.FontDisplay,
		TextSize = 72,
		Size = UDim2.new(1, 0, 0, 96),
		Parent = surface,
	})
	header.Position = UDim2.fromOffset(0, 10)

	local body: Frame = Build.new("Frame", {
		Name = "Columns",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(COLUMN_GAP, 116),
		Size = UDim2.new(1, -COLUMN_GAP, 1, -132),
		Parent = surface,
	})
	local order = LeaderboardController.BoardOrder()
	local columns: { [string]: Column } = {}
	for index, boardId in order do
		columns[boardId] = buildColumn(body, boardId, index, #order)
	end
	columnsByPart[part] = columns
end

local function renderBoards(boards: { [string]: any })
	local myId = Players.LocalPlayer.UserId
	for part, columns in columnsByPart do
		if not part.Parent then
			columnsByPart[part] = nil
			continue
		end
		for boardId, column in columns do
			local board = boards[boardId]
			local entries = if board then board.Entries else nil
			local myRank: number? = nil
			if entries then
				for rank, entry in entries do
					if entry.UserId == myId then
						myRank = rank
						break
					end
				end
			end
			column.Mine.Text = if myRank
				then Text.Get("scoreboard.you", { rank = tostring(myRank) })
				else Text.Get("scoreboard.youUnranked")

			for rank, row in column.Rows do
				local entry = if entries then entries[rank] else nil
				if entry then
					row.Text = string.format("%d. %s  %s", rank, tostring(entry.Name), NumberFormat.Short(LeaderboardController.Decode(boardId, entry.Value)))
					Build.paint(row, "TextColor3", if entry.UserId == myId then Theme.Colors.Power else Theme.Colors.Text)
				else
					row.Text = if rank == 1 then Text.Get("scoreboard.empty") else ""
					Build.paint(row, "TextColor3", Theme.Colors.TextDim)
				end
			end
		end
	end
end

local function scan()
	local map = Workspace:FindFirstChild("Map")
	local worlds = if map then map:FindFirstChild("Worlds") else nil
	if not worlds then
		return
	end
	for _, descendant in worlds:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:GetAttribute(ATTRIBUTE) == true then
			buildBoard(descendant)
		end
	end
end

function ScoreboardController.Init()
	LeaderboardController.BoardsChanged:Connect(function(boards)
		scan()
		renderBoards(boards)
	end)
end

function ScoreboardController.Start()
	-- Worlds stream in after join; scan again until the first board is found.
	task.spawn(function()
		for _ = 1, 20 do
			scan()
			if next(columnsByPart) then
				renderBoards(LeaderboardController.GetBoards())
				return
			end
			task.wait(1)
		end
	end)
end

return ScoreboardController
