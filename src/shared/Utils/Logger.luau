--!strict
--[[
	Logger
	Leveled logging. Level comes from GameConfig.Logging (verbose in Studio,
	quiet in live servers).

	Rules:
	- Never log secrets, receipts' raw payloads, promo code lists or full player data.
	- Identify players by UserId only.

	Usage:
		local log = Logger.new("DataService")
		log:Info("Loaded", player.UserId)
]]

local RunService = game:GetService("RunService")

local GameConfig = require(script.Parent.Parent.Config.GameConfig)

export type Level = "Debug" | "Info" | "Warn" | "Error" | "None"

local LEVEL_VALUE: { [string]: number } = {
	Debug = 1,
	Info = 2,
	Warn = 3,
	Error = 4,
	None = 5,
}

local function resolveLevel(): number
	local configured = if RunService:IsStudio() then GameConfig.Logging.StudioLevel else GameConfig.Logging.LiveLevel
	return LEVEL_VALUE[configured] or LEVEL_VALUE.Warn
end

local currentLevel = resolveLevel()
local side = if RunService:IsServer() then "S" else "C"

export type Logger = {
	Debug: (self: Logger, ...any) -> (),
	Info: (self: Logger, ...any) -> (),
	Warn: (self: Logger, ...any) -> (),
	Error: (self: Logger, ...any) -> (),
}

local Logger = {}

local function format(tag: string, ...: any): string
	local parts = table.create(select("#", ...))
	for i = 1, select("#", ...) do
		parts[i] = tostring((select(i, ...)))
	end
	return string.format("[%s][%s] %s", side, tag, table.concat(parts, " "))
end

function Logger.new(tag: string): Logger
	local self = {}

	function self.Debug(_: Logger, ...: any)
		if currentLevel <= LEVEL_VALUE.Debug then
			print(format(tag, ...))
		end
	end

	function self.Info(_: Logger, ...: any)
		if currentLevel <= LEVEL_VALUE.Info then
			print(format(tag, ...))
		end
	end

	function self.Warn(_: Logger, ...: any)
		if currentLevel <= LEVEL_VALUE.Warn then
			warn(format(tag, ...))
		end
	end

	-- Uses warn() rather than error(): logging must never throw.
	function self.Error(_: Logger, ...: any)
		if currentLevel <= LEVEL_VALUE.Error then
			warn("[ERROR]" .. format(tag, ...))
		end
	end

	return (self :: any) :: Logger
end

-- Test/debug override. Accepts a Level name.
function Logger.SetLevel(level: Level)
	currentLevel = LEVEL_VALUE[level] or currentLevel
end

return Logger
