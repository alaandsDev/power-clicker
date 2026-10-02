--!strict
--[[
	WorldLogic
	Pure world unlock/travel rules.

	Unlock(worldId) requires, in order:
		exists → enabled → not already unlocked → previous world unlocked
		→ rebirths >= requirement → pay cost (Requirement.Currency)
	Travel(worldId) requires the world to be enabled and unlocked.
	`isEnabled` is injected (WorldRules.IsEnabled in production) so tests can
	control it.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local WorldConfig = require(Shared.Config.WorldConfig)
local WorldRules = require(Shared.Formulas.WorldRules)
local CurrencyLogic = require(script.Parent.CurrencyLogic)
local RebirthLogic = require(script.Parent.RebirthLogic)

type PlayerData = Types.PlayerData
type WorldData = Types.WorldData
type EnabledFn = (WorldData) -> boolean

local WorldLogic = {}

-- Codes: "UnknownWorld" | "WorldDisabled" | "AlreadyUnlocked" | "PreviousWorldLocked"
--        | "NotEnoughRebirths" | "NotEnoughCurrency"
function WorldLogic.Unlock(data: PlayerData, worldId: string, isEnabled: EnabledFn?): (boolean, string?)
	local enabled = isEnabled or WorldRules.IsEnabled
	local world = WorldConfig.Worlds[worldId]
	if not world then
		return false, "UnknownWorld"
	end
	if not enabled(world) then
		return false, "WorldDisabled"
	end
	if data.Worlds.Unlocked[worldId] then
		return false, "AlreadyUnlocked"
	end
	local previous = WorldRules.Previous(world)
	if previous and not data.Worlds.Unlocked[previous.Id] then
		return false, "PreviousWorldLocked"
	end
	if RebirthLogic.GetRebirths(data) < world.Requirement.Rebirths then
		return false, "NotEnoughRebirths"
	end
	local cost = world.Requirement.Cost
	if cost > 0 and not CurrencyLogic.Remove(data, world.Requirement.Currency, cost) then
		return false, "NotEnoughCurrency"
	end
	data.Worlds.Unlocked[worldId] = true
	return true, nil
end

-- Codes: "UnknownWorld" | "WorldDisabled" | "WorldNotUnlocked"
function WorldLogic.Travel(data: PlayerData, worldId: string, isEnabled: EnabledFn?): (boolean, string?)
	local enabled = isEnabled or WorldRules.IsEnabled
	local world = WorldConfig.Worlds[worldId]
	if not world then
		return false, "UnknownWorld"
	end
	if not enabled(world) then
		return false, "WorldDisabled"
	end
	if not data.Worlds.Unlocked[worldId] then
		return false, "WorldNotUnlocked"
	end
	data.Worlds.Current = worldId
	return true, nil
end

-- On load: the default world is always unlocked, and the current world must
-- be valid (a world disabled by an update sends the player back home).
-- Unlocks of disabled worlds are KEPT (never remove progress).
function WorldLogic.Sanitize(data: PlayerData, isEnabled: EnabledFn?): boolean
	local enabled = isEnabled or WorldRules.IsEnabled
	local changed = false
	if not data.Worlds.Unlocked[WorldConfig.DefaultWorld] then
		data.Worlds.Unlocked[WorldConfig.DefaultWorld] = true
		changed = true
	end
	local current = WorldConfig.Worlds[data.Worlds.Current]
	if not current or not enabled(current) or not data.Worlds.Unlocked[current.Id] then
		data.Worlds.Current = WorldConfig.DefaultWorld
		changed = true
	end
	return changed
end

return WorldLogic
