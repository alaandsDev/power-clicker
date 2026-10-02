--!strict
--[[
	SeasonController
	"Passe" panel, built like a battle pass track:

		[ free reward ]   ← top row
	────●──────────●────  ← rail with one numbered node per level
		[ VIP reward ]    ← bottom row

	The rail is lit up to the level the player reached, the node of the next
	claimable level pulses, and the track opens already scrolled to it.
	Rewards show their real picture (gems, bolt, egg, pet) when the image is
	uploaded, and fall back to the emoji when it is not.

	Claiming sends "SeasonAction"; the server re-checks level, track and
	whether it was already paid, so this panel only has to look right.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local NumberFormat = require(Shared:WaitForChild("Utils"):WaitForChild("NumberFormat"))
local SeasonConfig = require(Shared:WaitForChild("Config"):WaitForChild("SeasonConfig"))
local SeasonLogic = require(Shared:WaitForChild("Formulas"):WaitForChild("SeasonLogic"))
local Text = require(Shared:WaitForChild("Localization"))

local Theme = require(script.Parent.Parent.UI.Theme)
local Build = require(script.Parent.Parent.UI.Build)
local Anim = require(script.Parent.Parent.UI.Anim)
local Messages = require(script.Parent.Parent.UI.Messages)
local RewardText = require(script.Parent.Parent.UI.RewardText)
local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local UIController = require(script.Parent.UIController)
local MenuController = require(script.Parent.MenuController)
local DataController = require(script.Parent.DataController)
local SoundController = require(script.Parent.SoundController)
local NotificationController = require(script.Parent.NotificationController)

local PANEL = "Season"
local PANEL_SIZE = Vector2.new(780, 560)
local HEADER_HEIGHT = 74

local COLUMN_WIDTH = 142
local COLUMN_GAP = 12
local TILE_HEIGHT = 160
local NODE_SIZE = 46
local NODE_ROW = 56 -- vertical space between the two tiles
local RAIL_THICKNESS = 8
local ICON_SIZE = 68
local COLUMN_HEIGHT = TILE_HEIGHT * 2 + NODE_ROW
local NODE_CENTER_Y = TILE_HEIGHT + NODE_ROW / 2
-- Levels kept to the left of the current one when the track auto-scrolls.
local SCROLL_LEAD = 2

local TRACKS = { "Free", "Vip" }

type Tile = { Button: TextButton, Icon: GuiObject, Amount: TextLabel, Label: TextLabel, State: TextLabel, Lock: TextLabel, Stroke: UIStroke }
type Column = { Tiles: { [string]: Tile }, Node: Frame, NodeLabel: TextLabel, Rail: Frame }

local SeasonController = {}

local headerLabel: TextLabel
local setBar: (number) -> ()
local trackFrame: ScrollingFrame
local columns: { [number]: Column } = {}
local nodePulse: Tween? = nil
local busy = false

local function isVip(): boolean
	return Players.LocalPlayer:GetAttribute("VIP") == true
end

local function claim(level: number, trackId: string)
	if busy then
		return
	end
	busy = true
	local response = ClientNet.Invoke("SeasonAction", level, trackId)
	busy = false
	if response.Ok then
		SoundController.Play("Reward")
	else
		NotificationController.Show(Messages.ForCode(response.Code), "Bad")
	end
end

-- ── Building ────────────────────────────────────────────────────────────────

local function buildTile(column: Frame, level: number, trackId: string, top: number): Tile
	local isVipTrack = trackId == "Vip"
	local rewards = SeasonLogic.RewardsOf(level, trackId)
	-- The first reward is the face of the tile; extras are counted in the label.
	local visuals = RewardText.Visual(rewards[1] or { Type = "Currency", Currency = "Power", Amount = 0 })
	local labelText = if #rewards > 1
		then Text.Get("season.plusMore", { name = visuals.Label, count = #rewards - 1 })
		else visuals.Label
	local button = Build.button({
		Name = trackId,
		Text = "",
		BackgroundColor3 = Theme.Colors.Panel,
		Position = UDim2.fromOffset(0, top),
		Size = UDim2.new(1, 0, 0, TILE_HEIGHT),
		ZIndex = 23,
		Parent = column,
	})
	-- Build.button adds the border stroke first; it doubles as the state colour.
	local stroke = button:FindFirstChildOfClass("UIStroke") :: UIStroke
	stroke.Thickness = 3

	Build.label({
		Name = "Track",
		Text = Text.Get(if isVipTrack then "season.trackVip" else "season.trackFree"),
		Font = Theme.FontMono,
		TextSize = 12,
		TextColor3 = if isVipTrack then Theme.Colors.Power else Theme.Colors.TextDim,
		Position = UDim2.fromOffset(0, 6),
		Size = UDim2.new(1, 0, 0, 14),
		ZIndex = 24,
		Parent = button,
	})

	local icon: GuiObject
	if Build.isAsset(visuals.Image) then
		icon = Build.new("ImageLabel", {
			Name = "Icon",
			BackgroundTransparency = 1,
			Image = visuals.Image,
			ScaleType = Enum.ScaleType.Fit,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 22),
			Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE),
			ZIndex = 24,
			Parent = button,
		})
	else
		icon = Build.label({
			Name = "Icon",
			Text = visuals.Emoji,
			TextSize = 46,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 22),
			Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE),
			ZIndex = 24,
			Parent = button,
		})
	end

	local amount = Build.label({
		Name = "Amount",
		Text = visuals.Amount,
		Font = Theme.FontDisplay,
		TextSize = 24,
		TextColor3 = if isVipTrack then Theme.Colors.Power else Theme.Colors.Text,
		Position = UDim2.fromOffset(0, 96),
		Size = UDim2.new(1, 0, 0, 24),
		ZIndex = 24,
		Parent = button,
	})
	local label = Build.label({
		Name = "Label",
		Text = labelText,
		Font = Theme.FontRegular,
		TextSize = 12,
		TextScaled = true,
		TextColor3 = Theme.Colors.TextDim,
		Position = UDim2.fromOffset(6, 122),
		Size = UDim2.new(1, -12, 0, 16),
		ZIndex = 24,
		Parent = button,
	})
	Build.new("UITextSizeConstraint", { MaxTextSize = 13, Parent = label })

	local state = Build.label({
		Name = "State",
		Text = "",
		TextSize = 14,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.new(1, -10, 0, 16),
		ZIndex = 24,
		Parent = button,
	})

	-- Locked tiles show a small padlock instead of repeating the word twenty
	-- times; the wording is kept for the tiles that can actually be acted on.
	local lock = Build.label({
		Name = "Lock",
		Text = Theme.Icons.Locked,
		TextSize = 16,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.fromOffset(18, 18),
		Visible = false,
		ZIndex = 25,
		Parent = button,
	})

	button.Activated:Connect(function()
		claim(level, trackId)
	end)
	return { Button = button, Icon = icon, Amount = amount, Label = label, State = state, Lock = lock, Stroke = stroke }
end

local function buildColumn(level: number)
	local column: Frame = Build.new("Frame", {
		Name = "Level" .. level,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(COLUMN_WIDTH, COLUMN_HEIGHT),
		LayoutOrder = level,
		ZIndex = 22,
		Parent = trackFrame,
	})

	-- Rail: runs behind the node and reaches into the next column's gap.
	local rail: Frame = Build.new("Frame", {
		Name = "Rail",
		BackgroundColor3 = Theme.Colors.Stroke,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0, NODE_CENTER_Y),
		Size = UDim2.new(1, COLUMN_GAP, 0, RAIL_THICKNESS),
		Visible = level < SeasonConfig.LevelCount, -- nothing to connect after the last
		ZIndex = 22,
		Parent = column,
	})

	local node: Frame = Build.new("Frame", {
		Name = "Node",
		BackgroundColor3 = Theme.Colors.Panel,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, NODE_CENTER_Y),
		Size = UDim2.fromOffset(NODE_SIZE, NODE_SIZE),
		ZIndex = 24,
		Parent = column,
	})
	Build.corner(node, UDim.new(1, 0))
	Build.stroke(node, 3)
	local nodeLabel = Build.label({
		Name = "Number",
		Text = tostring(level),
		Font = Theme.FontDisplay,
		TextSize = 20,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 25,
		Parent = node,
	})

	columns[level] = {
		Tiles = {
			Free = buildTile(column, level, "Free", 0),
			Vip = buildTile(column, level, "Vip", TILE_HEIGHT + NODE_ROW),
		},
		Node = node,
		NodeLabel = nodeLabel,
		Rail = rail,
	}
end

-- ── State ───────────────────────────────────────────────────────────────────

local function applyTileState(tile: Tile, claimed: boolean, allowed: boolean, reason: string, isVipTrack: boolean)
	if claimed then
		tile.State.Text = Text.Get("season.claimed")
		Build.paint(tile.State, "TextColor3", Theme.Colors.TextDim)
		Build.paint(tile.Button, "BackgroundColor3", Theme.Colors.Panel)
		Build.paint(tile.Stroke, "Color", Theme.Colors.Stroke)
		tile.Lock.Visible = false
		tile.Amount.TextTransparency = 0.5
		tile.Label.TextTransparency = 0.5
	elseif allowed then
		tile.State.Text = Text.Get("season.claim")
		Build.paint(tile.State, "TextColor3", Theme.Colors.Good)
		Build.paint(tile.Button, "BackgroundColor3", Theme.Colors.PanelLight)
		Build.paint(tile.Stroke, "Color", Theme.Colors.Good)
		tile.Lock.Visible = false
		tile.Amount.TextTransparency = 0
		tile.Label.TextTransparency = 0
	else
		-- Locked: the padlock carries the message, the line below stays empty
		-- except for the VIP case, which is worth spelling out (it sells).
		tile.State.Text = if reason == "VipOnly" then Text.Get("season.vipOnly") else ""
		Build.paint(tile.State, "TextColor3", Theme.Colors.Power)
		Build.paint(tile.Button, "BackgroundColor3", Theme.Colors.Panel)
		Build.paint(tile.Stroke, "Color", if isVipTrack then Theme.Colors.Power else Theme.Colors.Stroke)
		tile.Lock.Visible = true
		tile.Amount.TextTransparency = 0.35
		tile.Label.TextTransparency = 0.35
	end
end

local function refresh()
	local season = DataController.Get("Season")
	if not season then
		return
	end
	local xp = tonumber(season.Xp) or 0
	local level = SeasonLogic.LevelOf(xp)
	local inLevel, needed = SeasonLogic.Progress(xp)
	headerLabel.Text = Text.Get("season.header", {
		name = SeasonConfig.DisplayName,
		level = tostring(level),
		max = tostring(SeasonConfig.LevelCount),
		xp = NumberFormat.Short(inLevel),
		need = NumberFormat.Short(needed),
	})
	setBar(inLevel / needed)

	if nodePulse then
		nodePulse:Cancel()
		nodePulse = nil
	end
	local pulseLevel: number? = nil

	for levelIndex, column in columns do
		local reached = level >= levelIndex
		Build.paint(column.Rail, "BackgroundColor3", if reached and level > levelIndex then Theme.Colors.Power else Theme.Colors.Stroke)
		Build.paint(column.Node, "BackgroundColor3", if reached then Theme.Colors.Power else Theme.Colors.Panel)
		Build.paint(column.NodeLabel, "TextColor3", if reached then Theme.Colors.Stroke else Theme.Colors.TextDim)

		for _, trackId in TRACKS do
			local tile = column.Tiles[trackId]
			local claimedMap = (if trackId == "Vip" then season.ClaimedVip else season.ClaimedFree) or {}
			local claimed = claimedMap[tostring(levelIndex)] == true
			local allowed, reason = SeasonLogic.CanClaim(season, levelIndex, trackId, isVip())
			applyTileState(tile, claimed, allowed, reason, trackId == "Vip")
			if allowed and (pulseLevel == nil or levelIndex < pulseLevel) then
				pulseLevel = levelIndex
			end
		end
	end

	-- Only the first claimable node pulses; a screen full of pulsing is noise.
	local target = if pulseLevel then columns[pulseLevel] else nil
	if target then
		nodePulse = Anim.Pulse(target.Node, 1.12)
	end
end

-- Opens the track near the player's level instead of always at level 1.
local function scrollToCurrent()
	local season = DataController.Get("Season")
	local level = if season then SeasonLogic.LevelOf(tonumber(season.Xp) or 0) else 0
	local step = COLUMN_WIDTH + COLUMN_GAP
	local x = math.max((level - SCROLL_LEAD) * step, 0)
	task.defer(function()
		trackFrame.CanvasPosition = Vector2.new(x, 0)
	end)
end

function SeasonController.Init()
	local _, content = UIController.CreatePanel(PANEL, Text.Get("season.title", { icon = Theme.Icons.Season }), PANEL_SIZE)

	headerLabel = Build.label({
		Name = "Header",
		Text = "",
		Font = Theme.FontDisplay,
		TextSize = 22,
		Size = UDim2.new(1, 0, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 22,
		Parent = content,
	})
	local bar, set = Build.progressBar({
		Name = "Xp",
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(1, 0, 0, 14),
		ZIndex = 22,
		Parent = content,
	}, Theme.Colors.Power)
	Build.stroke(bar, 2)
	setBar = set
	Build.label({
		Name = "Hint",
		Text = Text.Get("season.dragHint"),
		Font = Theme.FontMono,
		TextSize = 12,
		TextColor3 = Theme.Colors.TextDim,
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.new(1, 0, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 22,
		Parent = content,
	})

	trackFrame = Build.new("ScrollingFrame", {
		Name = "Track",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, HEADER_HEIGHT),
		Size = UDim2.new(1, 0, 0, COLUMN_HEIGHT + 16),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 8,
		ZIndex = 22,
		Parent = content,
	})
	Build.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, COLUMN_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = trackFrame,
	})
	for level = 1, SeasonConfig.LevelCount do
		buildColumn(level)
	end

	-- Left column: the right grid is full (10 tiles) and reads best that way.
	MenuController.AddButton(Text.Get("menu.season"), Theme.Icons.Season, Theme.Colors.Power, 1, function()
		UIController.TogglePanel(PANEL)
	end, "Season")

	DataController.Changed:Connect(function(key: string)
		if key == "Season" then
			refresh()
		end
	end)
	Players.LocalPlayer:GetAttributeChangedSignal("VIP"):Connect(refresh)
	UIController.PanelChanged:Connect(function(name: string?)
		if name == PANEL then
			refresh()
			scrollToCurrent()
		end
	end)

	ClientNet.On("Notify", function(kind: any, payload: any)
		if kind == "SeasonLevelUp" and type(payload) == "table" then
			NotificationController.Show(Text.Get("season.levelUp", { level = tostring(payload.Level) }), "Good")
			SoundController.Play("Reward")
			local column = columns[tonumber(payload.Level) or 0]
			if column then
				Anim.Pop(column.Node, 1.25)
			end
		end
	end)
	refresh()
end

return SeasonController
