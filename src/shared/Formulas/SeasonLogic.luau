--!strict
--[[
	SeasonLogic
	Pure season-pass rules: level from XP, what can be claimed, and starting a
	fresh season. No player instances, no services — the server decides with
	these and the UI shows the same answers.
]]

local Shared = script.Parent.Parent
local Types = require(Shared.Types)
local SeasonConfig = require(Shared.Config.SeasonConfig)

type SeasonData = Types.SeasonData

local SeasonLogic = {}

-- A fresh, empty season record for the current season.
function SeasonLogic.Fresh(): SeasonData
	return { SeasonId = SeasonConfig.Id, Xp = 0, ClaimedFree = {}, ClaimedVip = {} }
end

--[[
	Ensures `data.Season` belongs to the season running now.
	Returns true when it had to be reset (a new season started).
]]
function SeasonLogic.EnsureCurrent(data: { Season: SeasonData }): boolean
	local season = data.Season
	if type(season) ~= "table" or season.SeasonId ~= SeasonConfig.Id then
		data.Season = SeasonLogic.Fresh()
		return true
	end
	return false
end

-- Level reached with `xp` (1 = first level, capped at LevelCount).
function SeasonLogic.LevelOf(xp: number): number
	if xp ~= xp or xp < 0 then -- NaN guard
		return 0
	end
	return math.min(math.floor(xp / SeasonConfig.XpPerLevel), SeasonConfig.LevelCount)
end

-- XP inside the current level and what the level needs (for the bar).
function SeasonLogic.Progress(xp: number): (number, number)
	local level = SeasonLogic.LevelOf(xp)
	if level >= SeasonConfig.LevelCount then
		return SeasonConfig.XpPerLevel, SeasonConfig.XpPerLevel
	end
	return math.max(xp - level * SeasonConfig.XpPerLevel, 0), SeasonConfig.XpPerLevel
end

--[[
	Can `level` of `track` ("Free" / "Vip") be claimed right now?
	Returns (false, reason) when not. `isVip` is the pass ownership.
]]
function SeasonLogic.CanClaim(season: SeasonData, level: number, track: string, isVip: boolean): (boolean, string)
	if track ~= "Free" and track ~= "Vip" then
		return false, "BadTrack"
	end
	if type(level) ~= "number" or level % 1 ~= 0 or level < 1 or level > SeasonConfig.LevelCount then
		return false, "BadLevel"
	end
	if track == "Vip" and not isVip then
		return false, "VipOnly"
	end
	if SeasonLogic.LevelOf(season.Xp) < level then
		return false, "LevelLocked"
	end
	local claimed = if track == "Vip" then season.ClaimedVip else season.ClaimedFree
	if claimed[tostring(level)] then
		return false, "AlreadyClaimed"
	end
	return true, ""
end

-- Marks a level as claimed (call only after CanClaim said yes).
function SeasonLogic.MarkClaimed(season: SeasonData, level: number, track: string)
	local claimed = if track == "Vip" then season.ClaimedVip else season.ClaimedFree
	claimed[tostring(level)] = true
end

-- Rewards of a level/track, or an empty list for an unknown level.
function SeasonLogic.RewardsOf(level: number, track: string): { Types.RewardData }
	local entry = SeasonConfig.Levels[level]
	if not entry then
		return {}
	end
	return if track == "Vip" then entry.Vip else entry.Free
end

return SeasonLogic
