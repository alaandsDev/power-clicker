--!strict
--[[
	SocialService
	Rewards playing with other people (Phase 13):

	- Friend bonus: +BonusPerFriend of Power for every friend of yours online
	  in this server, capped at MaxFriends. Published as the "Social" power
	  layer and as the "FriendsOnline" attribute (the HUD shows it).
	- Group reward: a one-time gift for members of the game's group, tracked
	  in Purchases.OneTimeOffersClaimed so it is paid once per account.

	Friendship and group membership are web calls: both are wrapped in pcall
	(a failed call means "no bonus this round", never an error to the player)
	and cached per pair/player.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Logger = require(Shared.Utils.Logger)
local SocialConfig = require(Shared.Config.SocialConfig)

local NetService = require(script.Parent.NetService)
local DataService = require(script.Parent.DataService)
local PowerService = require(script.Parent.PowerService)
local RewardService = require(script.Parent.RewardService)

local log = Logger.new("Social")

local SocialService = {}

local friendsOnline: { [Player]: number } = {}
local lastRefresh: { [Player]: number } = {}
-- Friendship never changes mid-session in practice; cache it per pair.
local friendCache: { [string]: boolean } = {}

local function pairKey(a: number, b: number): string
	local low, high = math.min(a, b), math.max(a, b)
	return tostring(low) .. ":" .. tostring(high)
end

local function areFriends(player: Player, other: Player): boolean
	local key = pairKey(player.UserId, other.UserId)
	local cached = friendCache[key]
	if cached ~= nil then
		return cached
	end
	-- The API types this parameter as "User", which is an alias for the user id
	-- (an int64); the cast keeps the analyzer quiet without changing the call.
	local otherId: any = other.UserId
	local ok, result = pcall(function()
		return player:IsFriendsWithAsync(otherId)
	end)
	if not ok then
		return false -- try again on the next refresh
	end
	friendCache[key] = result == true
	return result == true
end

local function countFriends(player: Player): number
	local count = 0
	for _, other in Players:GetPlayers() do
		if other ~= player and areFriends(player, other) then
			count += 1
		end
	end
	return math.min(count, SocialConfig.Friends.MaxFriends)
end

-- Recounts a player's friends (throttled) and republishes the bonus.
local function refresh(player: Player, force: boolean)
	local now = os.clock()
	if not force and now - (lastRefresh[player] or 0) < SocialConfig.RefreshSeconds then
		return
	end
	lastRefresh[player] = now
	local count = countFriends(player)
	if friendsOnline[player] == count then
		return
	end
	friendsOnline[player] = count
	player:SetAttribute("FriendsOnline", count)
	PowerService.Invalidate(player)
	if count > 0 then
		NetService.FireClient("Notify", player, "FriendBonus", {
			Friends = count,
			Percent = math.floor(count * SocialConfig.Friends.BonusPerFriend * 100),
		})
	end
end

local function refreshAll(force: boolean)
	for _, player in Players:GetPlayers() do
		task.spawn(refresh, player, force)
	end
end

-- One-time gift for group members.
local function checkGroup(player: Player)
	local groupId = SocialConfig.Group.GroupId
	local data = DataService.GetData(player)
	if groupId <= 0 or not data or data.Purchases.OneTimeOffersClaimed[SocialConfig.Group.ClaimKey] then
		return
	end
	local ok, inGroup = pcall(function()
		return player:IsInGroupAsync(groupId)
	end)
	if not ok or inGroup ~= true then
		return
	end
	data.Purchases.OneTimeOffersClaimed[SocialConfig.Group.ClaimKey] = true
	DataService.MarkChanged(player, "Purchases")
	RewardService.Grant(player, SocialConfig.Group.Rewards, "GroupReward")
	NetService.FireClient("Notify", player, "GroupReward", {})
	log:Info(string.format("user=%d claimed the group reward", player.UserId))
end

function SocialService.Init()
	PowerService.RegisterProvider("Social", function(player: Player): number
		return 1 + (friendsOnline[player] or 0) * SocialConfig.Friends.BonusPerFriend
	end)

	DataService.PlayerReady:Connect(function(player: Player)
		-- Both web calls yield: never block the signal that fires them.
		task.spawn(checkGroup, player)
		task.spawn(refresh, player, true)
		-- Everyone else may have just gained a friend in the server.
		task.defer(refreshAll, true)
	end)
	Players.PlayerRemoving:Connect(function(player)
		friendsOnline[player] = nil
		lastRefresh[player] = nil
		task.defer(refreshAll, true)
	end)
end

function SocialService.Start()
	task.spawn(function()
		while true do
			task.wait(SocialConfig.RefreshSeconds)
			refreshAll(false)
		end
	end)
end

return SocialService
