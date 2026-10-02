--!strict
--[[
	SettingsService
	"UpdateSettings"(key, value): only known keys, each with its own type and
	range (booleans or volumes 0..1). Purely cosmetic player preferences,
	persisted in PlayerData.Settings.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Guard = require(Shared.Utils.Guard)

local NetService = require(script.Parent.NetService)
local DataService = require(script.Parent.DataService)

type RemoteResponse = Types.RemoteResponse

-- Per-key validators.
local SETTINGS: { [string]: Guard.Check } = {
	MusicVolume = Guard.Number(0, 1),
	SfxVolume = Guard.Number(0, 1),
	ShowFloatingNumbers = Guard.Boolean(),
	ReducedEffects = Guard.Boolean(),
}

local SettingsService = {}

local function validate(...: any): boolean
	if select("#", ...) ~= 2 then
		return false
	end
	local key, value = ...
	local check = type(key) == "string" and SETTINGS[key] or nil
	return check ~= nil and check(value)
end

local function update(player: Player, key: string, value: any): RemoteResponse
	local data = DataService.GetData(player)
	if not data then
		return { Ok = false, Code = "NotReady" }
	end
	if not SETTINGS[key] then
		return { Ok = false, Code = "UnknownSetting" }
	end
	local settings = data.Settings :: any
	settings[key] = value
	DataService.MarkChanged(player, "Settings")
	return { Ok = true }
end

function SettingsService.Init()
	NetService.OnInvoke("UpdateSettings", validate, update)
end

return SettingsService
