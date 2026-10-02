--!strict
--[[
	LoadingScreen (ReplicatedFirst)
	Replaces Roblox's default loading screen with a branded one that stays
	until the player's data snapshot has arrived (DataController sets the
	local attribute "ClientDataLoaded"), so players never see an empty UI.
	Hard timeout so a problem never traps the player behind it.
]]

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local TIMEOUT_SECONDS = 45
local FADE_SECONDS = 0.5

ReplicatedFirst:RemoveDefaultLoadingScreen()

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "LoadingScreen"
gui.IgnoreGuiInset = true
gui.DisplayOrder = 100
gui.ResetOnSpawn = false

local background = Instance.new("Frame")
background.Size = UDim2.fromScale(1, 1)
background.BackgroundColor3 = Color3.fromRGB(24, 26, 40)
background.BorderSizePixel = 0
background.Parent = gui

-- Text title first (instant); swapped for the uploaded logo if there is one.
local title = Instance.new("TextLabel")
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Position = UDim2.fromScale(0.5, 0.42)
title.Size = UDim2.fromScale(0.8, 0.14)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBlack
title.TextScaled = true
title.TextColor3 = Color3.fromRGB(255, 196, 45)
title.Text = "⚡ POWER CLICKER ⚡"
title.Parent = background

local status = Instance.new("TextLabel")
status.AnchorPoint = Vector2.new(0.5, 0.5)
status.Position = UDim2.fromScale(0.5, 0.58)
status.Size = UDim2.fromScale(0.6, 0.05)
status.BackgroundTransparency = 1
status.Font = Enum.Font.GothamBold
status.TextScaled = true
status.TextColor3 = Color3.fromRGB(180, 186, 215)
status.Text = "..."
status.Parent = background

gui.Parent = playerGui

local logo: ImageLabel? = nil

-- Localized text and the logo image once Shared has replicated (fallbacks stay).
task.spawn(function()
	local shared = ReplicatedStorage:WaitForChild("Shared", 10)
	local module = shared and shared:WaitForChild("Localization", 10)
	if module and module:IsA("ModuleScript") then
		local ok, Text = pcall(require, module)
		if ok then
			status.Text = (Text :: any).Get("loading.text")
		end
	end
	local config = shared and shared:WaitForChild("Config", 10)
	local ids = config and config:FindFirstChild("AssetIds")
	if not (ids and ids:IsA("ModuleScript")) then
		return
	end
	local ok, AssetIds = pcall(require, ids)
	local image = if ok then (AssetIds :: any).logo_title else nil
	if type(image) ~= "string" or image == "" then
		return
	end
	local label = Instance.new("ImageLabel")
	label.AnchorPoint = title.AnchorPoint
	label.Position = title.Position
	label.Size = UDim2.fromScale(0.7, 0.3)
	label.BackgroundTransparency = 1
	label.ScaleType = Enum.ScaleType.Fit
	label.Image = image
	label.Parent = background
	title.Visible = false
	logo = label
end)

-- Pulse while waiting.
local pulse = TweenService:Create(title, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { TextTransparency = 0.3 })
pulse:Play()

local started = os.clock()
while player:GetAttribute("ClientDataLoaded") ~= true and os.clock() - started < TIMEOUT_SECONDS do
	task.wait(0.1)
end

pulse:Cancel()
local fadeInfo = TweenInfo.new(FADE_SECONDS)
TweenService:Create(background, fadeInfo, { BackgroundTransparency = 1 }):Play()
TweenService:Create(title, fadeInfo, { TextTransparency = 1 }):Play()
if logo then
	TweenService:Create(logo, fadeInfo, { ImageTransparency = 1 }):Play()
end
TweenService:Create(status, fadeInfo, { TextTransparency = 1 }):Play()
task.wait(FADE_SECONDS)
gui:Destroy()
