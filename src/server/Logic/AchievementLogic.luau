--!strict
--[[
	AchievementLogic
	Data-driven achievements (AchievementConfig). No per-achievement code:
	each one is "Stat >= Threshold" or "WorldId unlocked".
	Unlocking is idempotent: data.Achievements.Unlocked[id] = unlock time.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local AchievementConfig = require(Shared.Config.AchievementConfig)

type PlayerData = Types.PlayerData
type AchievementData = Types.AchievementData

local AchievementLogic = {}

function AchievementLogic.IsMet(data: PlayerData, achievement: AchievementData): boolean
	if achievement.Stat and achievement.Threshold then
		local value = (data.Stats :: any)[achievement.Stat]
		return type(value) == "number" and value >= achievement.Threshold
	end
	if achievement.WorldId then
		return data.Worlds.Unlocked[achievement.WorldId] == true
	end
	return false
end

-- Ids of achievements that are met but not yet unlocked (sorted, deterministic).
function AchievementLogic.Pending(data: PlayerData): { string }
	local pending: { string } = {}
	for id, achievement in AchievementConfig.Achievements do
		if not data.Achievements.Unlocked[id] and AchievementLogic.IsMet(data, achievement) then
			table.insert(pending, id)
		end
	end
	table.sort(pending)
	return pending
end

function AchievementLogic.MarkUnlocked(data: PlayerData, id: string, now: number)
	if not data.Achievements.Unlocked[id] then
		data.Achievements.Unlocked[id] = now
	end
end

return AchievementLogic
