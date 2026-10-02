--!strict
--[[
	SoundController
	Plays sounds from AudioConfig by name. Empty SoundIds (TODO_ASSET) are
	skipped silently, so gameplay code can call Play() before audio exists.
	One Sound instance per name (no per-play Instance creation); per-sound
	MinInterval throttles spammy sounds like clicks.
]]

local SoundService = game:GetService("SoundService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local AudioConfig = require(Shared:WaitForChild("Config"):WaitForChild("AudioConfig"))
local DataController = require(script.Parent.DataController)

local DEFAULT_SFX_VOLUME = 0.8

local function sfxVolume(): number
	local settings = DataController.Get("Settings")
	local value = if settings then settings.SfxVolume else nil
	return if type(value) == "number" then math.clamp(value, 0, 1) else DEFAULT_SFX_VOLUME
end

local SoundController = {}

local sounds: { [string]: Sound } = {}
local lastPlayed: { [string]: number } = {}
local random = Random.new()

function SoundController.Play(name: string)
	local config = AudioConfig.Sounds[name]
	if not config or config.SoundId == "" then
		return
	end
	local volume = sfxVolume()
	if volume <= 0 then
		return
	end
	local now = os.clock()
	if lastPlayed[name] and now - lastPlayed[name] < config.MinInterval then
		return
	end
	lastPlayed[name] = now

	local sound = sounds[name]
	if not sound then
		local created = Instance.new("Sound")
		created.Name = "SFX_" .. name
		created.SoundId = config.SoundId
		created.Parent = SoundService
		sounds[name] = created
		sound = created
	end
	sound.Volume = config.Volume * volume
	sound.PlaybackSpeed = 1 + random:NextNumber(-config.PitchVariation, config.PitchVariation)
	sound.TimePosition = 0
	sound:Play()
end

return SoundController
