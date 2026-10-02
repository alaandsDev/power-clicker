--!strict
--[[
	QuestController
	"Missões" panel with two tabs: quests (progress + claim) and achievements
	(auto-unlocked by the server). Shows the daily reset countdown and a menu
	badge when something can be claimed. Toasts for completions/unlocks.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Types = require(Shared:WaitForChild("Types"))
local NumberFormat = require(Shared:WaitForChild("Utils"):WaitForChild("NumberFormat"))
local QuestConfig = require(Config:WaitForChild("QuestConfig"))
local AchievementConfig = require(Config:WaitForChild("AchievementConfig"))
local TimeRules = require(Shared:WaitForChild("Formulas"):WaitForChild("TimeRules"))
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

type QuestData = Types.QuestData
type AchievementData = Types.AchievementData
type QuestRow = { Quest: QuestData, Progress: TextLabel, SetBar: (number) -> (), Button: TextButton }
type AchievementRow = { Achievement: AchievementData, Status: TextLabel }

local PANEL = "Quests"

local QuestController = {}

local questRows: { QuestRow } = {}
local achievementRows: { AchievementRow } = {}
local resetLabel: TextLabel
local menuButton: TextButton
local tabs: { [string]: { Button: TextButton, List: ScrollingFrame } } = {}
local busy = false

local function questName(id: string): string
	return Text.Get("quest." .. id .. ".name")
end

local function achievementName(id: string): string
	return Text.Get("achievement." .. id .. ".name")
end

local function refreshQuests()
	local quests = DataController.Get("Quests")
	if not quests then
		return
	end
	local anyClaimable = false
	for _, row in questRows do
		local progress = quests.Progress[row.Quest.Id] or { Progress = 0, Claimed = false }
		local have = math.min(progress.Progress or 0, row.Quest.Target)
		row.Progress.Text = Text.Get("quests.progress", { have = NumberFormat.Short(have), need = NumberFormat.Short(row.Quest.Target) })
		row.SetBar(have / row.Quest.Target)
		if progress.Claimed then
			row.Button.Text = Text.Get("quests.claimed")
			Build.paint(row.Button, "BackgroundColor3", Theme.Colors.PanelLight)
		elseif have >= row.Quest.Target then
			row.Button.Text = Text.Get("quests.claim")
			Build.paint(row.Button, "BackgroundColor3", Theme.Colors.Good)
			anyClaimable = true
		else
			row.Button.Text = Text.Get("quests.progress", { have = NumberFormat.Short(have), need = NumberFormat.Short(row.Quest.Target) })
			Build.paint(row.Button, "BackgroundColor3", Theme.Colors.Disabled)
		end
	end
	MenuController.SetBadge(menuButton, anyClaimable)
end

local function refreshAchievements()
	local unlocked = (DataController.Get("Achievements") or {}).Unlocked or {}
	local stats = DataController.Get("Stats") or {}
	for _, row in achievementRows do
		local achievement = row.Achievement
		if unlocked[achievement.Id] then
			row.Status.Text = Text.Get("achievements.done")
			Build.paint(row.Status, "TextColor3", Theme.Colors.Good)
		elseif achievement.Stat and achievement.Threshold then
			local value = stats[achievement.Stat] or 0
			row.Status.Text = Text.Get("quests.progress", { have = NumberFormat.Short(math.min(value, achievement.Threshold)), need = NumberFormat.Short(achievement.Threshold) })
			Build.paint(row.Status, "TextColor3", Theme.Colors.TextDim)
		else
			row.Status.Text = "🔒"
			Build.paint(row.Status, "TextColor3", Theme.Colors.TextDim)
		end
	end
end

local function claim(questId: string)
	if busy then
		return
	end
	busy = true
	local response = ClientNet.Invoke("ClaimQuest", questId)
	busy = false
	if response.Ok then
		SoundController.Play("Reward")
	else
		NotificationController.Show(Messages.ForCode(response.Code), "Bad")
	end
end

local function showTab(name: string)
	for tabName, tab in tabs do
		tab.List.Visible = tabName == name
		Build.paint(tab.Button, "BackgroundColor3", if tabName == name then Theme.Colors.Accent else Theme.Colors.PanelLight)
	end
	resetLabel.Visible = name == "Quests"
end

local function makeList(content: Frame, top: number): ScrollingFrame
	local list: ScrollingFrame = Build.new("ScrollingFrame", {
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
	return list
end

function QuestController.Init()
	local _, content = UIController.CreatePanel(PANEL, Text.Get("quests.title", { icon = Theme.Icons.Quests }), Vector2.new(700, 600))

	local tabBar: Frame = Build.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 46), ZIndex = 22, Parent = content })
	Build.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), Parent = tabBar })
	resetLabel = Build.label({ Text = "", TextSize = 18, TextColor3 = Theme.Colors.TextDim, Position = UDim2.fromOffset(0, 52), Size = UDim2.new(1, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 22, Parent = content })

	for _, tabName in { "Quests", "Achievements" } do
		local button = Build.button({
			Text = Text.Get(if tabName == "Quests" then "quests.tabQuests" else "quests.tabAchievements"),
			TextSize = 20,
			BackgroundColor3 = Theme.Colors.PanelLight,
			Size = UDim2.new(0.5, -5, 1, 0),
			ZIndex = 22,
			Parent = tabBar,
		})
		button.Activated:Connect(function()
			showTab(tabName)
		end)
		tabs[tabName] = { Button = button, List = makeList(content, 82) }
	end

	-- Quests: "Once" first, then dailies; stable order by id.
	local quests: { QuestData } = {}
	for _, quest in QuestConfig.Quests do
		table.insert(quests, quest)
	end
	table.sort(quests, function(a, b)
		if a.Repeat ~= b.Repeat then
			return a.Repeat == "Once"
		end
		return a.Id < b.Id
	end)
	for index, quest in quests do
		local frame: Frame = Build.new("Frame", { BackgroundColor3 = Theme.Colors.PanelLight, Size = UDim2.new(1, -12, 0, 92), LayoutOrder = index, ZIndex = 22, Parent = tabs.Quests.List })
		Build.corner(frame, Theme.CornerSmall)
		Build.label({ Text = questName(quest.Id), TextSize = 20, Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -200, 0, 26), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 23, Parent = frame })
		Build.label({ Text = Text.Get("quests.reward", { reward = RewardText.List(quest.Rewards) }), TextSize = 16, TextColor3 = Theme.Colors.TextDim, Position = UDim2.fromOffset(12, 34), Size = UDim2.new(1, -200, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 23, Parent = frame })
		local bar, setBar = Build.progressBar({ Position = UDim2.fromOffset(12, 64), Size = UDim2.new(1, -200, 0, 14), ZIndex = 23, Parent = frame }, Theme.Colors.Power)
		local progressLabel = Build.label({ Text = "", TextSize = 12, Size = UDim2.fromScale(1, 1), ZIndex = 24, Parent = bar })
		local button = Build.button({ Text = "", TextSize = 18, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(170, 56), ZIndex = 23, Parent = frame })
		button.Activated:Connect(function()
			claim(quest.Id)
		end)
		table.insert(questRows, { Quest = quest, Progress = progressLabel, SetBar = setBar, Button = button })
	end

	local achievements: { AchievementData } = {}
	for _, achievement in AchievementConfig.Achievements do
		table.insert(achievements, achievement)
	end
	table.sort(achievements, function(a, b)
		return a.Id < b.Id
	end)
	for index, achievement in achievements do
		local frame: Frame = Build.new("Frame", { BackgroundColor3 = Theme.Colors.PanelLight, Size = UDim2.new(1, -12, 0, 76), LayoutOrder = index, ZIndex = 22, Parent = tabs.Achievements.List })
		Build.corner(frame, Theme.CornerSmall)
		Build.label({ Text = "🏅 " .. achievementName(achievement.Id), TextSize = 20, Position = UDim2.fromOffset(12, 4), Size = UDim2.new(1, -200, 0, 26), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 23, Parent = frame })
		Build.label({
			Text = Text.Get("achievement." .. achievement.Id .. ".desc") .. "  •  " .. Text.Get("quests.reward", { reward = RewardText.List(achievement.Rewards) }),
			TextSize = 15,
			TextColor3 = Theme.Colors.TextDim,
			Position = UDim2.fromOffset(12, 34),
			Size = UDim2.new(1, -200, 0, 34),
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 23,
			Parent = frame,
		})
		local status = Build.label({ Text = "", TextSize = 18, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(170, 40), ZIndex = 23, Parent = frame })
		table.insert(achievementRows, { Achievement = achievement, Status = status })
	end
	showTab("Quests")

	menuButton = MenuController.AddButton(Text.Get("menu.quests"), Theme.Icons.Quests, Theme.Colors.Accent, 7, function()
		UIController.TogglePanel(PANEL)
	end)

	DataController.Changed:Connect(function(key: string)
		if key == "Quests" then
			refreshQuests()
		elseif key == "Achievements" or key == "Stats" then
			refreshAchievements()
		end
	end)

	ClientNet.On("Notify", function(kind: any, payload: any)
		if type(payload) ~= "table" then
			return
		end
		if kind == "QuestComplete" and type(payload.QuestId) == "string" then
			SoundController.Play("Reward")
			NotificationController.Show(Text.Get("quests.completeToast", { name = questName(payload.QuestId) }), "Good")
		elseif kind == "Achievement" and type(payload.AchievementId) == "string" then
			SoundController.Play("Reward")
			NotificationController.Show(Text.Get("achievements.unlockedToast", { name = achievementName(payload.AchievementId) }), "Good")
		end
	end)

	task.spawn(function()
		while true do
			resetLabel.Text = Text.Get("quests.dailyReset", { time = NumberFormat.Duration(TimeRules.SecondsUntilReset(workspace:GetServerTimeNow())) })
			task.wait(1)
		end
	end)
end

return QuestController
