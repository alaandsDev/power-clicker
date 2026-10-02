--!strict
--[[
	AchievementService
	Evaluates AchievementLogic for players marked dirty by gameplay signals,
	at most once per second per player (cheap even with fast clicking).
	Rewards are granted automatically on unlock. If a reward can't be granted
	right now (e.g. pet inventory full), the achievement stays pending and is
	retried on the next evaluation — it is never lost.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Signal = require(Shared.Utils.Signal)
local AchievementConfig = require(Shared.Config.AchievementConfig)

local NetService = require(script.Parent.NetService)
local DataService = require(script.Parent.DataService)
local RewardService = require(script.Parent.RewardService)
local ClickService = require(script.Parent.ClickService)
local RebirthService = require(script.Parent.RebirthService)
local EggService = require(script.Parent.EggService)
local WorldService = require(script.Parent.WorldService)
local AchievementLogic = require(script.Parent.Parent.Logic.AchievementLogic)

local EVALUATE_SECONDS = 1

local AchievementService = {
	-- (player, achievementId)
	Unlocked = Signal.new() :: Signal.Signal<Player, string>,
}

local dirty: { [Player]: boolean } = {}

local function markDirty(player: Player)
	dirty[player] = true
end

local function evaluate(player: Player)
	local data = DataService.GetData(player)
	if not data then
		return
	end
	local now = os.time()
	for _, id in AchievementLogic.Pending(data) do
		local achievement = AchievementConfig.Achievements[id]
		local ok = RewardService.Grant(player, achievement.Rewards, "Achievement:" .. id)
		if ok then
			AchievementLogic.MarkUnlocked(data, id, now)
			DataService.MarkChanged(player, "Achievements")
			NetService.FireClient("Notify", player, "Achievement", { AchievementId = id })
			AchievementService.Unlocked:Fire(player, id)
		end
	end
end

function AchievementService.Init()
	ClickService.Clicked:Connect(markDirty)
	RebirthService.Rebirthed:Connect(markDirty)
	EggService.Hatched:Connect(markDirty)
	WorldService.Unlocked:Connect(markDirty)
	DataService.PlayerReady:Connect(markDirty)
	Players.PlayerRemoving:Connect(function(player)
		dirty[player] = nil
	end)
end

function AchievementService.Start()
	task.spawn(function()
		while true do
			task.wait(EVALUATE_SECONDS)
			for player in dirty do
				dirty[player] = nil
				evaluate(player)
			end
		end
	end)
end

return AchievementService
