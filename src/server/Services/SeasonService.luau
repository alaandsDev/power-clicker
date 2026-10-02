--!strict
--[[
	SeasonService
	Season pass: XP from playing, 20 levels, free + VIP tracks.

	XP is granted ONLY from server-side events (quests, daily rewards,
	playtime chests, bosses, broken targets) — never from a client message.
	Claims go through "SeasonAction", which re-checks the level, the track and
	whether it was claimed before (SeasonLogic), so a replayed request pays
	nothing twice.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Guard = require(Shared.Utils.Guard)
local Logger = require(Shared.Utils.Logger)
local SeasonConfig = require(Shared.Config.SeasonConfig)
local SeasonLogic = require(Shared.Formulas.SeasonLogic)

local NetService = require(script.Parent.NetService)
local DataService = require(script.Parent.DataService)
local RewardService = require(script.Parent.RewardService)
local QuestService = require(script.Parent.QuestService)
local DailyRewardService = require(script.Parent.DailyRewardService)
local SessionService = require(script.Parent.SessionService)
local BossService = require(script.Parent.BossService)
local TargetService = require(script.Parent.TargetService)

type RemoteResponse = Types.RemoteResponse

local log = Logger.new("Season")

local SeasonService = {}

local function seasonOf(player: Player): Types.SeasonData?
	local data = DataService.GetData(player)
	if not data then
		return nil
	end
	if SeasonLogic.EnsureCurrent(data) then
		DataService.MarkChanged(player, "Season")
		log:Info(string.format("user=%d started season %s", player.UserId, SeasonConfig.Id))
	end
	return data.Season
end

--[[
	Grants season XP. `source` must be a key of SeasonConfig.XpSources so the
	amounts stay in config; unknown sources are ignored (and reported).
]]
function SeasonService.AddXp(player: Player, source: string, times: number?)
	local perUnit = (SeasonConfig.XpSources :: { [string]: number })[source]
	if not perUnit then
		log:Warn("unknown XP source", source)
		return
	end
	local season = seasonOf(player)
	if not season then
		return
	end
	local before = SeasonLogic.LevelOf(season.Xp)
	season.Xp += perUnit * math.max(times or 1, 1)
	DataService.MarkChanged(player, "Season")
	local after = SeasonLogic.LevelOf(season.Xp)
	if after > before then
		NetService.FireClient("Notify", player, "SeasonLevelUp", { Level = after })
	end
end

local function claim(player: Player, level: number, track: string): RemoteResponse
	local season = seasonOf(player)
	if not season then
		return { Ok = false, Code = "NotReady" }
	end
	local isVip = player:GetAttribute("VIP") == true
	local allowed, reason = SeasonLogic.CanClaim(season, level, track, isVip)
	if not allowed then
		return { Ok = false, Code = reason }
	end
	-- Mark BEFORE granting: if a grant fails midway the level is still spent,
	-- never paid twice.
	SeasonLogic.MarkClaimed(season, level, track)
	DataService.MarkChanged(player, "Season")
	RewardService.Grant(player, SeasonLogic.RewardsOf(level, track), "Season:" .. track .. ":" .. tostring(level))
	log:Info(string.format("user=%d claimed season %s level %d", player.UserId, track, level))
	return { Ok = true, Data = { Level = level, Track = track } }
end

function SeasonService.Init()
	NetService.OnInvoke("SeasonAction", Guard.Args(Guard.Integer(1, SeasonConfig.LevelCount), Guard.OneOf({ "Free", "Vip" })), function(player: Player, level: number, track: string): RemoteResponse
		return claim(player, level, track)
	end)

	QuestService.Claimed:Connect(function(player: Player)
		SeasonService.AddXp(player, "QuestClaimed")
	end)
	DailyRewardService.Claimed:Connect(function(player: Player)
		SeasonService.AddXp(player, "DailyReward")
	end)

	SessionService.ChestClaimed:Connect(function(player: Player)
		SeasonService.AddXp(player, "PlaytimeChest")
	end)
	BossService.Defeated:Connect(function(player: Player)
		SeasonService.AddXp(player, "BossDefeated")
	end)
	TargetService.Broken:Connect(function(player: Player)
		SeasonService.AddXp(player, "TargetBroken")
	end)

	-- Starting a new season resets progress the first time the player is ready.
	DataService.PlayerReady:Connect(function(player: Player)
		seasonOf(player)
	end)
end

function SeasonService.Start()
	for _, player in Players:GetPlayers() do
		seasonOf(player)
	end
end

return SeasonService
