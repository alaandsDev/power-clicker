--!strict
--[[
	NotificationController
	Short toasts at the top-right. Reuses a small pool of labels.
	Also handles server "Notify" events that only need a toast.
]]

local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local NumberFormat = require(Shared:WaitForChild("Utils"):WaitForChild("NumberFormat"))
local Text = require(Shared:WaitForChild("Localization"))

local Theme = require(script.Parent.Parent.UI.Theme)
local Build = require(script.Parent.Parent.UI.Build)
local Anim = require(script.Parent.Parent.UI.Anim)
local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local UIController = require(script.Parent.UIController)
local SoundController = require(script.Parent.SoundController)

export type Style = "Info" | "Good" | "Bad"

local MAX_TOASTS = 4
local TOAST_SECONDS = 2.5

local NotificationController = {}

local container: Frame
local pool: { TextLabel } = {}
local nextIndex = 0

local STYLE_COLORS: { [string]: Color3 } = {
	Info = Theme.Colors.PanelLight,
	Good = Theme.Colors.Good,
	Bad = Theme.Colors.Bad,
}

function NotificationController.Show(text: string, style: Style?)
	nextIndex = (nextIndex % MAX_TOASTS) + 1
	local toast = pool[nextIndex]
	toast.Text = text
	Build.paint(toast, "BackgroundColor3", STYLE_COLORS[style or "Info"])
	toast.LayoutOrder = -math.floor(os.clock() * 1000) -- newest on top
	toast.BackgroundTransparency = 0.1
	toast.TextTransparency = 0
	toast.Visible = true
	Anim.PopIn(toast, 0.7, 0.25)
	if style == "Bad" then
		SoundController.Play("Error")
	end

	local shownAt = toast:GetAttribute("ShownAt")
	local stamp = (if type(shownAt) == "number" then shownAt else 0) + 1
	toast:SetAttribute("ShownAt", stamp)
	task.delay(TOAST_SECONDS, function()
		if toast:GetAttribute("ShownAt") ~= stamp then
			return -- reused by a newer toast
		end
		local tween = TweenService:Create(toast, Theme.Tween.Normal, { BackgroundTransparency = 1, TextTransparency = 1 })
		tween:Play()
		tween.Completed:Wait()
		if toast:GetAttribute("ShownAt") == stamp then
			toast.Visible = false
		end
	end)
end

--[[
	O HudController põe este contêiner na coluna central ABAIXO das moedas
	(HudController.GetTopStack). Antes ele ficava em y = 78, em cima de
	Power/Gemas/Vitórias.
]]
function NotificationController.GetContainer(): Frame
	return container
end

function NotificationController.Init()
	container = Build.new("Frame", {
		Name = "Toasts",
		BackgroundTransparency = 1,
		-- Posição provisória; HudController.Init move para a coluna central.
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, Theme.Hud.TopBarY + Theme.Hud.PillSize.Y + 12),
		Size = UDim2.fromOffset(340, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 50,
		Parent = UIController.GetCanvas(),
	})
	Build.new("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = container,
	})
	for i = 1, MAX_TOASTS do
		local toast = Build.label({
			Name = "Toast" .. i,
			Size = UDim2.fromOffset(340, 52),
			BackgroundTransparency = 0.1,
			TextSize = 22,
			TextWrapped = true,
			Visible = false,
			ZIndex = 51,
			Parent = container,
		})
		Build.corner(toast, Theme.CornerSmall)
		table.insert(pool, toast)
	end

	ClientNet.On("Notify", function(kind: any, payload: any)
		if kind == "Rebirth" and type(payload) == "table" then
			NotificationController.Show(
				Text.Get("rebirth.toast", { count = payload.Rebirths or 0, gems = NumberFormat.Short(payload.Gems or 0), icon = Theme.Icons.Gems }),
				"Good"
			)
		end
	end)
end

return NotificationController
