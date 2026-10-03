--!strict
--[[
	TutorialController
	Onboarding through gameplay, no long tutorial. The current step is
	DERIVED from replicated data (first unmet condition), so there is nothing
	extra to save and it can never get out of sync:

		1 click the button            (TotalClicks < 15)
		2 buy the first upgrade       (no Power upgrade and never rebirthed)
		3 hatch the first egg         (EggsOpened == 0)
		4 equip the pet               (nothing equipped)
		5 rebirth                     (Rebirths == 0)
		→ done: short "next goal" message, then hidden

	A hint banner explains the step and the relevant button pulses.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Text = require(Shared:WaitForChild("Localization"))

local Theme = require(script.Parent.Parent.UI.Theme)
local Build = require(script.Parent.Parent.UI.Build)
local UIController = require(script.Parent.UIController)
local MenuController = require(script.Parent.MenuController)
local HudController = require(script.Parent.HudController)
local DataController = require(script.Parent.DataController)
local NotificationController = require(script.Parent.NotificationController)

type Step = { Key: string, Target: string?, IsDone: (data: { [string]: any }) -> boolean }

local CLICK_GOAL = 15

local STEPS: { Step } = {
	{
		Key = "tutorial.click",
		Target = nil, -- the click button itself
		IsDone = function(d)
			return (d.Stats.TotalClicks or 0) >= CLICK_GOAL
		end,
	},
	{
		Key = "tutorial.upgrade",
		Target = "Upgrades",
		IsDone = function(d)
			return next(d.Upgrades) ~= nil or (d.Stats.Rebirths or 0) > 0
		end,
	},
	{
		Key = "tutorial.egg",
		Target = "Eggs",
		IsDone = function(d)
			return (d.Stats.EggsOpened or 0) > 0
		end,
	},
	{
		Key = "tutorial.equip",
		Target = "Pets",
		IsDone = function(d)
			return #d.Pets.Equipped > 0
		end,
	},
	{
		Key = "tutorial.rebirth",
		Target = "Rebirth",
		IsDone = function(d)
			return (d.Stats.Rebirths or 0) > 0
		end,
	},
}

local TutorialController = {}

local banner: TextLabel
local highlight: UIStroke? = nil
local highlightTween: Tween? = nil
local currentIndex: number? = nil
local sawIncomplete = false

local function snapshot(): { [string]: any }?
	local stats = DataController.Get("Stats")
	local upgrades = DataController.Get("Upgrades")
	local pets = DataController.Get("Pets")
	if not stats or not upgrades or not pets then
		return nil
	end
	return { Stats = stats, Upgrades = upgrades, Pets = pets }
end

local function clearHighlight()
	if highlightTween then
		highlightTween:Cancel()
		highlightTween = nil
	end
	if highlight then
		highlight:Destroy()
		highlight = nil
	end
end

local function setHighlight(target: string?)
	clearHighlight()
	local button = if target then MenuController.GetButton(target) else nil
	if not button then
		return
	end
	local stroke = Build.stroke(button, 5, Theme.Colors.Power)
	stroke.Name = "TutorialHighlight"
	highlight = stroke
	local tween = TweenService:Create(stroke, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.8 })
	tween:Play()
	highlightTween = tween
end

local function refresh()
	local data = snapshot()
	if not data then
		return
	end
	local index: number? = nil
	for i, step in STEPS do
		if not step.IsDone(data) then
			index = i
			break
		end
	end
	if index == currentIndex then
		return
	end
	currentIndex = index

	if index == nil then
		banner.Visible = false
		clearHighlight()
		-- Only congratulate players who actually went through it this session.
		if sawIncomplete then
			NotificationController.Show(Text.Get("tutorial.done"), "Good")
		end
		return
	end
	sawIncomplete = true
	local step = STEPS[index]
	banner.Text = Text.Get(step.Key)
	banner.Visible = true
	setHighlight(step.Target)
end

function TutorialController.Init()
	banner = Build.label({
		Name = "TutorialBanner",
		Text = "",
		TextSize = 20,
		TextWrapped = true,
		BackgroundTransparency = 0.15,
		BackgroundColor3 = Theme.Colors.Accent,
		-- Primeiro item da coluna central, logo ABAIXO das moedas (antes ficava
		-- em y = 18 e cobria Power/Gemas/Vitórias).
		Size = UDim2.fromOffset(540, 44),
		Visible = false,
		ZIndex = 30,
		LayoutOrder = 0,
		Parent = HudController.GetTopStack(),
	})
	Build.corner(banner, Theme.CornerSmall)
	Build.padding(banner, 6)

	DataController.Changed:Connect(function(key: string)
		if key == "Stats" or key == "Upgrades" or key == "Pets" then
			refresh()
		end
	end)
	-- Don't nag during first frames of a returning player.
	Players.LocalPlayer:GetAttributeChangedSignal("ClientDataLoaded"):Connect(refresh)
end

return TutorialController
