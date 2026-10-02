--!strict
--[[
	WorldAmbientController
	Applies the AmbientConfig preset of the player's current world to
	Lighting (client-side only, so players in different worlds each see their
	own sky). Tweens numeric/color values for a smooth transition.
]]

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local AmbientConfig = require(Config:WaitForChild("AmbientConfig"))
local WorldConfig = require(Config:WaitForChild("WorldConfig"))

local DataController = require(script.Parent.DataController)

local WorldAmbientController = {}

local currentPreset: string? = nil

local function getOrCreate(className: string): Instance
	local existing = Lighting:FindFirstChildOfClass(className)
	if existing then
		return existing
	end
	local created = Instance.new(className)
	created.Parent = Lighting
	return created
end

local function apply(presetId: string)
	if presetId == currentPreset then
		return
	end
	local preset = AmbientConfig.Presets[presetId] or AmbientConfig.Presets[AmbientConfig.Default]
	if not preset then
		return
	end
	local instant = currentPreset == nil
	currentPreset = presetId
	local info = TweenInfo.new(if instant then 0 else AmbientConfig.TransitionSeconds)

	TweenService:Create(Lighting, info, {
		ClockTime = preset.ClockTime,
		Brightness = preset.Brightness,
		Ambient = preset.Ambient,
		OutdoorAmbient = preset.OutdoorAmbient,
		FogColor = preset.FogColor,
		FogEnd = preset.FogEnd,
	}):Play()

	local atmosphere = getOrCreate("Atmosphere") :: Atmosphere
	TweenService:Create(atmosphere, info, {
		Density = preset.AtmosphereDensity,
		Color = preset.AtmosphereColor,
		Decay = preset.AtmosphereDecay,
	}):Play()

	local sky = getOrCreate("Sky") :: Sky
	sky.StarCount = preset.StarCount
end

local function refresh()
	local worlds = DataController.Get("Worlds")
	local world = worlds and WorldConfig.Worlds[worlds.Current]
	apply(if world then world.Ambient else AmbientConfig.Default)
end

function WorldAmbientController.Init()
	apply(AmbientConfig.Default)
	DataController.Changed:Connect(function(key: string)
		if key == "Worlds" then
			refresh()
		end
	end)
end

return WorldAmbientController
