--!strict
--[[
	RewardService
	Grants RewardData lists from trusted server sources (daily rewards,
	quests, achievements, codes, products) via RewardLogic — atomically: if
	anything can't be granted (e.g. pet inventory full) nothing is.
	Handles replication/invalidation for every kind of reward.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Logger = require(Shared.Utils.Logger)
local Signal = require(Shared.Utils.Signal)

local DataService = require(script.Parent.DataService)
local CurrencyService = require(script.Parent.CurrencyService)
local PetService = require(script.Parent.PetService)
local BoostService = require(script.Parent.BoostService)
local RewardLogic = require(script.Parent.Parent.Logic.RewardLogic)

type RewardData = Types.RewardData

local log = Logger.new("Rewards")

local RewardService = {
	-- (player, summary, source)
	Granted = Signal.new() :: Signal.Signal<Player, RewardLogic.GrantSummary, string>,
}

function RewardService.CanGrant(player: Player, rewards: { RewardData }): (boolean, string?)
	local data = DataService.GetData(player)
	if not data then
		return false, "NotReady"
	end
	return RewardLogic.CanGrant(data, rewards)
end

-- Returns (true, nil, summary) or (false, code). Never partially grants.
function RewardService.Grant(player: Player, rewards: { RewardData }, source: string, options: RewardLogic.GrantOptions?): (boolean, string?, RewardLogic.GrantSummary?)
	local data = DataService.GetData(player)
	if not data then
		return false, "NotReady"
	end
	local ok, code, summary = RewardLogic.Grant(data, rewards, os.time(), options)
	if not ok or not summary then
		return false, code
	end

	for currency, amount in summary.Currencies do
		CurrencyService.NotifyChanged(player, currency :: any, amount, "Reward:" .. source)
	end
	if next(summary.Boosts) then
		BoostService.NotifyChanged(player)
	end
	if #summary.Pets > 0 then
		PetService.NotifyChanged(player)
	end
	log:Debug(string.format("user=%d granted reward (%s)", player.UserId, source))
	RewardService.Granted:Fire(player, summary, source)
	return true, nil, summary
end

return RewardService
