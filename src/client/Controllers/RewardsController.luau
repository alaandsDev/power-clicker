--!strict
--[[
	RewardsController
	"Prêmios" panel: 7-day daily reward track + promo code box.
	Countdown uses workspace:GetServerTimeNow() (synced with the server clock);
	the server alone decides whether a claim is valid.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local NumberFormat = require(Shared:WaitForChild("Utils"):WaitForChild("NumberFormat"))
local DailyRewardConfig = require(Config:WaitForChild("DailyRewardConfig"))
local DailyRewardLogic = require(Shared:WaitForChild("Formulas"):WaitForChild("DailyRewardLogic"))
local Text = require(Shared:WaitForChild("Localization"))

local Theme = require(script.Parent.Parent.UI.Theme)
local Build = require(script.Parent.Parent.UI.Build)
local Messages = require(script.Parent.Parent.UI.Messages)
local RewardText = require(script.Parent.Parent.UI.RewardText)
local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local UIController = require(script.Parent.UIController)
local MenuController = require(script.Parent.MenuController)
local DataController = require(script.Parent.DataController)
local SoundController = require(script.Parent.SoundController)
local NotificationController = require(script.Parent.NotificationController)

local PANEL = "Rewards"

local RewardsController = {}

local headerLabel: TextLabel
local dayCards: { Frame } = {}
local claimButton: TextButton
local codeBox: TextBox
local menuButton: TextButton
local busy = false

local function refresh()
	local daily = DataController.Get("DailyRewards")
	if not daily then
		return
	end
	local preview = DailyRewardLogic.Preview({ DailyRewards = daily } :: any, workspace:GetServerTimeNow())
	headerLabel.Text = Text.Get("daily.header", { streak = daily.Streak or 0 })
	for day, card in dayCards do
		local isNext = day == preview.Day
		Build.paint(card, "BackgroundColor3", if isNext then (if preview.CanClaim then Theme.Colors.Good else Theme.Colors.Accent) else Theme.Colors.PanelLight)
	end
	if preview.CanClaim then
		claimButton.Text = Text.Get("daily.claim")
		Build.paint(claimButton, "BackgroundColor3", Theme.Colors.Good)
	else
		claimButton.Text = Text.Get("daily.wait", { time = NumberFormat.Duration(preview.SecondsUntilClaim) })
		Build.paint(claimButton, "BackgroundColor3", Theme.Colors.Disabled)
	end
	MenuController.SetBadge(menuButton, preview.CanClaim)
end

local function claim()
	if busy then
		return
	end
	busy = true
	local response = ClientNet.Invoke("ClaimDaily")
	busy = false
	if response.Ok and type(response.Data) == "table" then
		SoundController.Play("Reward")
		NotificationController.Show(Text.Get("daily.claimed", { day = response.Data.Day or 1 }), "Good")
	else
		NotificationController.Show(Messages.ForCode(response.Code), "Bad")
	end
end

local function redeem()
	if busy or codeBox.Text == "" then
		return
	end
	busy = true
	local response = ClientNet.Invoke("RedeemCode", codeBox.Text)
	busy = false
	if response.Ok then
		codeBox.Text = ""
		SoundController.Play("Reward")
		NotificationController.Show(Text.Get("codes.success"), "Good")
	else
		NotificationController.Show(Messages.ForCode(response.Code), "Bad")
	end
end

function RewardsController.Init()
	local _, content = UIController.CreatePanel(PANEL, Text.Get("rewards.title", { icon = Theme.Icons.Rewards }), Vector2.new(700, 560))

	headerLabel = Build.label({ Text = "", TextSize = 22, Size = UDim2.new(1, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 22, Parent = content })

	local track: Frame = Build.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 38), Size = UDim2.new(1, 0, 0, 170), ZIndex = 22, Parent = content })
	Build.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = track })
	for day = 1, DailyRewardConfig.CycleLength do
		local card: Frame = Build.new("Frame", {
			BackgroundColor3 = Theme.Colors.PanelLight,
			Size = UDim2.new(1 / DailyRewardConfig.CycleLength, -6, 1, 0),
			LayoutOrder = day,
			ZIndex = 22,
			Parent = track,
		})
		Build.corner(card, Theme.CornerSmall)
		Build.label({ Text = Text.Get("daily.day", { day = day }), TextSize = 18, Size = UDim2.new(1, 0, 0, 28), ZIndex = 23, Parent = card })
		Build.label({
			Text = RewardText.List(DailyRewardLogic.RewardsFor(day)),
			TextSize = 15,
			TextWrapped = true,
			Position = UDim2.fromOffset(4, 30),
			Size = UDim2.new(1, -8, 1, -34),
			ZIndex = 23,
			Parent = card,
		})
		dayCards[day] = card
	end

	claimButton = Build.button({ Text = "", TextSize = 26, Position = UDim2.fromOffset(0, 220), Size = UDim2.new(1, 0, 0, 64), ZIndex = 22, Parent = content })
	claimButton.Activated:Connect(claim)

	Build.label({ Text = Text.Get("codes.header"), TextSize = 22, Position = UDim2.fromOffset(0, 306), Size = UDim2.new(1, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 22, Parent = content })
	codeBox = Build.new("TextBox", {
		PlaceholderText = Text.Get("codes.placeholder"),
		Text = "",
		ClearTextOnFocus = false,
		Font = Theme.Font,
		TextSize = 22,
		TextColor3 = Theme.Colors.Text,
		PlaceholderColor3 = Theme.Colors.TextDim,
		BackgroundColor3 = Theme.Colors.Background,
		Position = UDim2.fromOffset(0, 342),
		Size = UDim2.new(0.6, -8, 0, 56),
		ZIndex = 22,
		Parent = content,
	})
	Build.corner(codeBox, Theme.CornerSmall)
	local redeemButton = Build.button({
		Text = Text.Get("codes.redeem"),
		TextSize = 20,
		BackgroundColor3 = Theme.Colors.Accent,
		Position = UDim2.new(0.6, 0, 0, 342),
		Size = UDim2.new(0.4, 0, 0, 56),
		ZIndex = 22,
		Parent = content,
	})
	redeemButton.Activated:Connect(redeem)
	codeBox.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed then
			redeem()
		end
	end)

	menuButton = MenuController.AddButton(Text.Get("menu.rewards"), Theme.Icons.Rewards, Theme.Colors.Good, 6, function()
		UIController.TogglePanel(PANEL)
	end)

	DataController.Changed:Connect(function(key: string)
		if key == "DailyRewards" then
			refresh()
		end
	end)
	-- Countdown refresh (1 Hz is plenty).
	task.spawn(function()
		while true do
			task.wait(1)
			if DataController.IsLoaded() then
				refresh()
			end
		end
	end)
end

return RewardsController
