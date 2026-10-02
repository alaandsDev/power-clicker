--!strict
--[[
	AmbientConfig
	Per-world lighting presets (WorldConfig.Ambient → preset id). Applied on
	the CLIENT only (WorldAmbientController), so each player sees the lighting
	of the world they are in. Purely cosmetic.
]]

export type AmbientPreset = {
	ClockTime: number,
	Brightness: number,
	Ambient: Color3,
	OutdoorAmbient: Color3,
	FogColor: Color3,
	FogEnd: number,
	AtmosphereDensity: number,
	AtmosphereColor: Color3,
	AtmosphereDecay: Color3,
	StarCount: number,
}

local Presets: { [string]: AmbientPreset } = {
	Training = {
		ClockTime = 14,
		Brightness = 2.2,
		Ambient = Color3.fromRGB(110, 110, 120),
		OutdoorAmbient = Color3.fromRGB(150, 150, 160),
		FogColor = Color3.fromRGB(190, 215, 240),
		FogEnd = 1200,
		AtmosphereDensity = 0.3,
		AtmosphereColor = Color3.fromRGB(199, 215, 235),
		AtmosphereDecay = Color3.fromRGB(106, 112, 125),
		StarCount = 0,
	},
	City = {
		ClockTime = 18.3, -- sunset
		Brightness = 1.6,
		Ambient = Color3.fromRGB(110, 90, 90),
		OutdoorAmbient = Color3.fromRGB(170, 130, 120),
		FogColor = Color3.fromRGB(240, 170, 130),
		FogEnd = 1000,
		AtmosphereDensity = 0.35,
		AtmosphereColor = Color3.fromRGB(255, 190, 150),
		AtmosphereDecay = Color3.fromRGB(150, 90, 110),
		StarCount = 500,
	},
	Volcano = {
		ClockTime = 19.5,
		Brightness = 1.2,
		Ambient = Color3.fromRGB(130, 60, 40),
		OutdoorAmbient = Color3.fromRGB(150, 70, 50),
		FogColor = Color3.fromRGB(120, 40, 20),
		FogEnd = 700,
		AtmosphereDensity = 0.45,
		AtmosphereColor = Color3.fromRGB(255, 130, 70),
		AtmosphereDecay = Color3.fromRGB(90, 30, 20),
		StarCount = 0,
	},
	Space = {
		ClockTime = 0,
		Brightness = 1,
		Ambient = Color3.fromRGB(80, 85, 120),
		OutdoorAmbient = Color3.fromRGB(90, 95, 130),
		FogColor = Color3.fromRGB(10, 10, 25),
		FogEnd = 2000,
		AtmosphereDensity = 0,
		AtmosphereColor = Color3.fromRGB(20, 20, 40),
		AtmosphereDecay = Color3.fromRGB(10, 10, 20),
		StarCount = 6000,
	},
	Galaxy = {
		ClockTime = 0,
		Brightness = 1.1,
		Ambient = Color3.fromRGB(120, 80, 160),
		OutdoorAmbient = Color3.fromRGB(140, 90, 180),
		FogColor = Color3.fromRGB(60, 20, 90),
		FogEnd = 1600,
		AtmosphereDensity = 0.2,
		AtmosphereColor = Color3.fromRGB(190, 120, 255),
		AtmosphereDecay = Color3.fromRGB(70, 30, 110),
		StarCount = 9000,
	},
}

return {
	Presets = Presets,
	Default = "Training",
	TransitionSeconds = 1.5,
}
