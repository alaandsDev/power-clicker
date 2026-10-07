--!strict
--[[
	BoostLogic
	Temporary boosts stored as remaining seconds (data.Boosts.Remaining).
	Rules (BoostConfig):
	- Adding a boost adds DurationSeconds × stacks, capped at MaxStoredSeconds.
	- Per Category only the HIGHEST active multiplier applies (never stacked).
	- Time is consumed only while the player is online (BoostService ticks it).
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local BoostConfig = require(Shared.Config.BoostConfig)

type PlayerData = Types.PlayerData

local BoostLogic = {}

-- Codes: "UnknownBoost" | "InvalidAmount"
function BoostLogic.Add(data: PlayerData, boostId: string, stacks: number): (boolean, string?)
	local boost = BoostConfig.Boosts[boostId]
	if not boost then
		return false, "UnknownBoost"
	end
	if type(stacks) ~= "number" or stacks ~= stacks or stacks < 1 or stacks % 1 ~= 0 or stacks > 1000 then
		return false, "InvalidAmount"
	end
	local remaining = data.Boosts.Remaining
	local current = remaining[boostId] or 0
	remaining[boostId] = math.min(current + boost.DurationSeconds * stacks, boost.MaxStoredSeconds)
	return true, nil
end

--[[
	Adds `seconds` of a boost (a reward with its own duration, e.g. the boss
	Power2x of EventConfig.Boss.VictoryBoostSeconds). Same storage cap as Add.
]]
function BoostLogic.AddSeconds(data: PlayerData, boostId: string, seconds: number): (boolean, string?)
	local boost = BoostConfig.Boosts[boostId]
	if not boost then
		return false, "UnknownBoost"
	end
	if type(seconds) ~= "number" or seconds ~= seconds or seconds <= 0 or seconds > boost.MaxStoredSeconds then
		return false, "InvalidAmount"
	end
	local remaining = data.Boosts.Remaining
	remaining[boostId] = math.min((remaining[boostId] or 0) + seconds, boost.MaxStoredSeconds)
	return true, nil
end

-- Consumes `elapsed` seconds from every active boost. Returns ids that expired.
function BoostLogic.Tick(data: PlayerData, elapsed: number): { string }
	local expired: { string } = {}
	if elapsed <= 0 or elapsed ~= elapsed then
		return expired
	end
	local remaining = data.Boosts.Remaining
	for boostId, seconds in remaining do
		local left = (tonumber(seconds) or 0) - elapsed
		if left <= 0 or not BoostConfig.Boosts[boostId] then
			remaining[boostId] = nil
			table.insert(expired, boostId)
		else
			remaining[boostId] = left
		end
	end
	return expired
end

-- Highest active multiplier for a category ("Power" | "Luck"); 1 when none.
function BoostLogic.GetMultiplier(data: PlayerData, category: string): number
	local best = 1
	for boostId, seconds in data.Boosts.Remaining do
		local boost = BoostConfig.Boosts[boostId]
		if boost and boost.Category == category and (tonumber(seconds) or 0) > 0 and boost.Multiplier > best then
			best = boost.Multiplier
		end
	end
	return best
end

function BoostLogic.HasActive(data: PlayerData): boolean
	return next(data.Boosts.Remaining) ~= nil
end

return BoostLogic
