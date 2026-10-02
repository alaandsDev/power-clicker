--!strict
--[[
	QuestService
	Feeds QuestLogic from gameplay signals (no per-quest code):
		Clicks          ← ClickService.Clicked (manual + auto)
		Rebirths        ← RebirthService.Rebirthed
		EggsOpened      ← EggService.Hatched
		PetsHatched     ← EggService.Hatched
		Overdrives      ← OverdriveService.Activated
		WorldsUnlocked  ← WorldService.Unlocked (absolute count)
		Playtime        ← internal tick (also updates Stats.PlaytimeSeconds)
	"ClaimQuest"(questId) → QuestLogic.CanClaim → RewardService (atomic) → MarkClaimed.
	Daily quests reset on the server clock (checked on load and every minute).
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Guard = require(Shared.Utils.Guard)
local Signal = require(Shared.Utils.Signal)
local QuestConfig = require(Shared.Config.QuestConfig)

local NetService = require(script.Parent.NetService)
local DataService = require(script.Parent.DataService)
local RewardService = require(script.Parent.RewardService)
local ClickService = require(script.Parent.ClickService)
local RebirthService = require(script.Parent.RebirthService)
local EggService = require(script.Parent.EggService)
local OverdriveService = require(script.Parent.OverdriveService)
local WorldService = require(script.Parent.WorldService)
local QuestLogic = require(script.Parent.Parent.Logic.QuestLogic)

type RemoteResponse = Types.RemoteResponse

local PLAYTIME_TICK_SECONDS = 10
local RESET_CHECK_SECONDS = 60

local QuestService = {
	-- (player, questId)
	Completed = Signal.new() :: Signal.Signal<Player, string>,
	Claimed = Signal.new() :: Signal.Signal<Player, string>,
}

local function announce(player: Player, completed: { string })
	for _, questId in completed do
		NetService.FireClient("Notify", player, "QuestComplete", { QuestId = questId })
		QuestService.Completed:Fire(player, questId)
	end
end

local function add(player: Player, questType: string, amount: number)
	local data = DataService.GetData(player)
	if not data then
		return
	end
	local completed = QuestLogic.AddProgress(data, questType, amount)
	DataService.MarkChanged(player, "Quests")
	announce(player, completed)
end

local function worldsUnlocked(player: Player)
	local data = DataService.GetData(player)
	if not data then
		return
	end
	local count = 0
	for _ in data.Worlds.Unlocked do
		count += 1
	end
	-- The starting world doesn't count as "unlocked by the player".
	local completed = QuestLogic.SetProgressAtLeast(data, "WorldsUnlocked", count - 1)
	DataService.MarkChanged(player, "Quests")
	announce(player, completed)
end

local function claim(player: Player, questId: string): RemoteResponse
	local data = DataService.GetData(player)
	if not data then
		return { Ok = false, Code = "NotReady" }
	end
	QuestLogic.ApplyDailyReset(data, os.time())
	local ok, code, quest = QuestLogic.CanClaim(data, questId)
	if not ok or not quest then
		return { Ok = false, Code = code }
	end
	local granted, grantCode, summary = RewardService.Grant(player, quest.Rewards, "Quest:" .. questId)
	if not granted then
		return { Ok = false, Code = grantCode }
	end
	QuestLogic.MarkClaimed(data, questId)
	DataService.MarkChanged(player, "Quests")
	QuestService.Claimed:Fire(player, questId)
	return { Ok = true, Data = { Summary = summary } }
end

function QuestService.Init()
	NetService.OnInvoke("ClaimQuest", Guard.Args(Guard.KeyOf(QuestConfig.Quests)), claim)

	ClickService.Clicked:Connect(function(player)
		add(player, "Clicks", 1)
	end)
	RebirthService.Rebirthed:Connect(function(player)
		add(player, "Rebirths", 1)
	end)
	EggService.Hatched:Connect(function(player)
		add(player, "EggsOpened", 1)
		add(player, "PetsHatched", 1)
	end)
	OverdriveService.Activated:Connect(function(player)
		add(player, "Overdrives", 1)
	end)
	WorldService.Unlocked:Connect(worldsUnlocked)

	DataService.PlayerLoaded:Connect(function(_player, data)
		QuestLogic.ApplyDailyReset(data, os.time())
	end)
end

function QuestService.Start()
	task.spawn(function()
		local sinceResetCheck = 0
		while true do
			task.wait(PLAYTIME_TICK_SECONDS)
			sinceResetCheck += PLAYTIME_TICK_SECONDS
			local checkReset = sinceResetCheck >= RESET_CHECK_SECONDS
			if checkReset then
				sinceResetCheck = 0
			end
			local now = os.time()
			for _, player in Players:GetPlayers() do
				local data = DataService.GetData(player)
				if data then
					data.Stats.PlaytimeSeconds += PLAYTIME_TICK_SECONDS
					DataService.MarkChanged(player, "Stats")
					if checkReset and QuestLogic.ApplyDailyReset(data, now) then
						DataService.MarkChanged(player, "Quests")
					end
					add(player, "Playtime", PLAYTIME_TICK_SECONDS)
				end
			end
		end
	end)
end

return QuestService
