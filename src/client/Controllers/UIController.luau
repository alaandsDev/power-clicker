--!strict
--[[
	UIController
	Owns the root ScreenGui and uniform scaling.

	Layout is authored in reference pixels (Theme.ReferenceSize = 1280x720).
	The root "Canvas" frame is sized 1/scale of the screen and carries a
	UIScale of `scale`, so it always fills the (safe-area) screen exactly
	while every offset inside scales uniformly. Works for PC, mobile and
	console; the device safe area (notches) is respected via ScreenInsets.

	Panels: RegisterPanel(name, frame) + OpenPanel/ClosePanel/TogglePanel.
	Only one panel is open at a time.
]]

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Logger = require(Shared:WaitForChild("Utils"):WaitForChild("Logger"))
local Signal = require(Shared:WaitForChild("Utils"):WaitForChild("Signal"))
local Theme = require(script.Parent.Parent.UI.Theme)
local Build = require(script.Parent.Parent.UI.Build)

local log = Logger.new("UI")

local UIController = {
	PanelChanged = Signal.new() :: Signal.Signal<string?>,
}

local screenGui: ScreenGui
local canvas: Frame
local uiScale: UIScale
local panels: { [string]: GuiObject } = {}
local openPanel: string? = nil
local backdrop: TextButton
local CLOSE_SECONDS = 0.12

local function computeScale(viewport: Vector2): number
	local reference = Theme.ReferenceSize
	local scale = math.min(viewport.X / reference.X, viewport.Y / reference.Y)
	return math.clamp(scale, Theme.MinScale, Theme.MaxScale)
end

local function applyScale()
	local size = screenGui.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return -- not laid out yet; AbsoluteSize change will call again
	end
	local scale = computeScale(size)
	uiScale.Scale = scale
	canvas.Size = UDim2.fromScale(1 / scale, 1 / scale)
end

function UIController.GetCanvas(): Frame
	return canvas
end

-- Canvas (reference-pixel) size of the screen.
function UIController.GetCanvasSize(): Vector2
	return canvas.AbsoluteSize / math.max(uiScale.Scale, 0.01)
end

-- Converts a screen position (AbsolutePosition) to canvas offsets.
function UIController.ToCanvas(screenPosition: Vector2): Vector2
	return (screenPosition - canvas.AbsolutePosition) / math.max(uiScale.Scale, 0.01)
end

-- Centre of a GUI object in canvas offsets.
function UIController.CenterOf(gui: GuiObject): Vector2
	return UIController.ToCanvas(gui.AbsolutePosition + gui.AbsoluteSize / 2)
end

local function showBackdrop(show: boolean)
	if show then
		backdrop.Visible = true
		TweenService:Create(backdrop, TweenInfo.new(0.15), { BackgroundTransparency = 0.45 }):Play()
	else
		local tween = TweenService:Create(backdrop, TweenInfo.new(CLOSE_SECONDS), { BackgroundTransparency = 1 })
		tween.Completed:Once(function()
			if openPanel == nil then
				backdrop.Visible = false
			end
		end)
		tween:Play()
	end
end

local function hidePanel(name: string, panel: GuiObject)
	local scale = panel:FindFirstChild("OpenScale")
	if scale and scale:IsA("UIScale") and panel.Visible then
		local tween = TweenService:Create(scale, TweenInfo.new(CLOSE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.85 })
		tween.Completed:Once(function()
			if openPanel ~= name then
				panel.Visible = false
			end
		end)
		tween:Play()
	else
		panel.Visible = false
	end
end

function UIController.IsTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

function UIController.RegisterPanel(name: string, panel: GuiObject)
	panels[name] = panel
	panel.Visible = false
end

local function popIn(panel: GuiObject)
	local scale = panel:FindFirstChild("OpenScale")
	if not scale then
		scale = Build.new("UIScale", { Name = "OpenScale", Parent = panel })
	end
	local uiScaleInstance = scale :: UIScale
	uiScaleInstance.Scale = 0.85
	TweenService:Create(uiScaleInstance, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

function UIController.OpenPanel(name: string)
	openPanel = if panels[name] then name else nil
	for panelName, panel in panels do
		if panelName == name then
			if not panel.Visible then
				panel.Visible = true
				popIn(panel)
			end
		else
			panel.Visible = false
		end
	end
	showBackdrop(openPanel ~= nil)
	UIController.PanelChanged:Fire(openPanel)
end

function UIController.ClosePanel()
	openPanel = nil
	for name, panel in panels do
		hidePanel(name, panel)
	end
	showBackdrop(false)
	UIController.PanelChanged:Fire(nil)
end

function UIController.TogglePanel(name: string)
	if openPanel == name then
		UIController.ClosePanel()
	else
		UIController.OpenPanel(name)
	end
end

-- Standard centered panel with a title bar and close button.
-- Returns (panel, contentFrame).
function UIController.CreatePanel(name: string, title: string, size: Vector2): (Frame, Frame)
	local panel: Frame = Build.new("Frame", {
		Name = name .. "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundColor3 = Theme.Panel.Bg,
		Active = true, -- sink input so clicks don't fall through to the click button
		ZIndex = 20,
		Parent = canvas,
	})
	-- Modals are light; Build swaps the dark palette for everything built
	-- inside this frame (see Theme.Panel).
	panel:SetAttribute("LightPanel", true)
	Build.corner(panel)
	Build.stroke(panel, 4, Theme.Colors.Stroke)

	Build.label({
		Name = "Title",
		Text = title,
		TextSize = 34,
		Size = UDim2.new(1, -80, 0, 56),
		Position = UDim2.fromOffset(20, 4),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 21,
		Parent = panel,
	})

	local close = Build.button({
		Name = "Close",
		Text = Theme.Icons.Close,
		BackgroundColor3 = Theme.Colors.Bad,
		Size = UDim2.fromOffset(48, 48),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 10),
		TextSize = 26,
		ZIndex = 21,
		Parent = panel,
	})
	close.Activated:Connect(UIController.ClosePanel)

	local content: Frame = Build.new("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 66),
		Size = UDim2.new(1, -32, 1, -82),
		ZIndex = 21,
		Parent = panel,
	})

	UIController.RegisterPanel(name, panel)
	return panel, content
end

--[[
	Roblox's backpack hotbar would show the blade as a slot the player can
	unequip. The sword is not an item they manage — it is what their cut looks
	like — so the hotbar goes away.
]]
local function hideBackpack()
	-- SetCoreGuiEnabled throws while the CoreGui is still booting on a slow
	-- join, which must never take the whole UI down with it.
	local ok, err = pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)
	if not ok then
		log:Warn("Could not hide the backpack:", err)
	end
end

function UIController.Init()
	hideBackpack()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	screenGui = Build.new("ScreenGui", {
		Name = "PowerClickerUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		-- DeviceSafeInsets (notches). Roblox's own topbar buttons are avoided by
		-- Theme.Hud.TopSafe instead: TopbarSafeInsets shrinks the canvas and
		-- breaks the uniform-scale maths below.
		ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	})
	canvas = Build.new("Frame", {
		Name = "Canvas",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = screenGui,
	})
	uiScale = Build.new("UIScale", { Parent = canvas })

	-- Dimmed backdrop behind open panels; tapping it closes the panel.
	backdrop = Build.new("TextButton", {
		Name = "PanelBackdrop",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 19,
		Parent = canvas,
	})
	backdrop.Activated:Connect(UIController.ClosePanel)

	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyScale)
	applyScale()
end

return UIController
