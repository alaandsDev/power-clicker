--!strict
--[[
	DailyRewardService
	"ClaimDaily"() → DailyRewardLogic.Preview (server clock) → RewardService
	(atomic grant) → Commit. No yields between check and commit.
	The client shows the countdown using workspace:GetServerTimeNow(), which
	is synced to the server clock — the device clock is never trusted.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Guard = require(Shared.Utils.Guard)
local Signal = require(Shared.Utils.Signal)

local NetService = require(script.Parent.NetService)
local DataService = require(script.Parent.DataService)
local RewardService = require(script.Parent.RewardService)
local DailyRewardLogic = require(Shared.Formulas.DailyRewardLogic)

type RemoteResponse = Types.RemoteResponse

local DailyRewardService = {
	-- (player, day, streak)
	Claimed = Signal.new() :: Signal.Signal<Player, number, number>,
}

local function claim(player: Player): RemoteResponse
	local data = DataService.GetData(player)
	if not data then
		return { Ok = false, Code = "NotReady" }
	end
	local now = os.time()
	local preview = DailyRewardLogic.Preview(data, now)
	if not preview.CanClaim then
		return { Ok = false, Code = "NotYet", Data = { SecondsUntilClaim = preview.SecondsUntilClaim } }
	end
	local ok, code, summary = RewardService.Grant(player, DailyRewardLogic.RewardsFor(preview.Day), "Daily")
	if not ok then
		return { Ok = false, Code = code }
	end
	DailyRewardLogic.Commit(data, now, preview.NewStreak)
	DataService.MarkChanged(player, "DailyRewards")
	DailyRewardService.Claimed:Fire(player, preview.Day, preview.NewStreak)
	return { Ok = true, Data = { Day = preview.Day, Streak = preview.NewStreak, Summary = summary } }
end

function DailyRewardService.Init()
	NetService.OnInvoke("ClaimDaily", Guard.Args(), claim)
end

return DailyRewardService
