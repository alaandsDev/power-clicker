--!strict
--[[
	WorldRules
	Shared, pure world helpers (server authoritative; client uses them to
	display the same state).

	IsEnabled: a world is playable when WorldConfig says Enabled, or — in
	Studio only — when GameConfig.Dev.EnableAllWorldsInStudio is on (lets
	developers exercise every world with placeholder maps; no effect live).
]]

local RunService = game:GetService("RunService")

local Shared = script.Parent.Parent
local Types = require(Shared.Types)
local GameConfig = require(Shared.Config.GameConfig)
local WorldConfig = require(Shared.Config.WorldConfig)

type WorldData = Types.WorldData

local WorldRules = {}

local studioOverride = RunService:IsStudio() and GameConfig.Dev.EnableAllWorldsInStudio

function WorldRules.IsEnabled(world: WorldData): boolean
	return world.Enabled or studioOverride
end

-- Worlds sorted by Order.
function WorldRules.Ordered(): { WorldData }
	local list: { WorldData } = {}
	for _, world in WorldConfig.Worlds do
		table.insert(list, world)
	end
	table.sort(list, function(a, b)
		return a.Order < b.Order
	end)
	return list
end

-- The world right before `world` in Order (nil for the first).
function WorldRules.Previous(world: WorldData): WorldData?
	local previous: WorldData? = nil
	for _, candidate in WorldRules.Ordered() do
		if candidate.Order < world.Order then
			previous = candidate
		end
	end
	return previous
end

-- First world (by Order) that is not unlocked yet, or nil.
function WorldRules.NextLocked(unlocked: { [string]: boolean }): WorldData?
	for _, world in WorldRules.Ordered() do
		if not unlocked[world.Id] then
			return world
		end
	end
	return nil
end

return WorldRules
