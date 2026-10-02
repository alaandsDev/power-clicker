--!strict
--[[
	LeaderboardService
	1. leaderstats (Roblox player list): Power (formatted) and Rebirths,
	   refreshed at most once per second per player.
	2. Global boards (LeaderboardConfig): each player's stat is written to an
	   OrderedDataStore every UpdateIntervalSeconds (only when changed); the
	   top N are read every RefreshIntervalSeconds and broadcast
	   ("Leaderboards"). Never per frame.
	   OrderedDataStores store integers, so huge stats use log scale:
	   stored = floor(log10(value) * LogScale); clients decode for display.

	Studio with the Mock data backend: boards are built from the players in
	this server only and flagged Local = true (never presented as global).
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Logger = require(Shared.Utils.Logger)
local NumberFormat = require(Shared.Utils.NumberFormat)
local LeaderboardConfig = require(Shared.Config.LeaderboardConfig)

local NetService = require(script.Parent.NetService)
local DataService = require(script.Parent.DataService)
local CurrencyService = require(script.Parent.CurrencyService)

export type Entry = { Rank: number, UserId: number, Name: string, Value: number }
export type Board = { Entries: { Entry }, Local: boolean }

local log = Logger.new("Leaderboards")

local LeaderboardService = {}

local boards: { [string]: Board } = {}
local lastWritten: { [Player]: { [string]: number } } = {}
local statsDirty: { [Player]: boolean } = {}
local nameCache: { [number]: string } = {}

local function encode(boardConfig: LeaderboardConfig.BoardConfig, value: number): number
	if value ~= value or value <= 0 then
		return 0
	end
	if boardConfig.UseLogScale then
		return math.max(0, math.floor(math.log10(value) * (boardConfig.LogScale or 1)))
	end
	return math.floor(math.min(value, 2 ^ 53))
end

local function statValue(player: Player, stat: string): number
	local data = DataService.GetData(player)
	local value = if data then (data.Stats :: any)[stat] else nil
	return if type(value) == "number" then value else 0
end

local function nameFor(userId: number): string
	local cached = nameCache[userId]
	if cached then
		return cached
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		nameCache[userId] = player.DisplayName
		return player.DisplayName
	end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	local resolved = if ok and type(name) == "string" then name else ("#" .. userId)
	nameCache[userId] = resolved
	return resolved
end

-- ── leaderstats ─────────────────────────────────────────────────────────────

local function refreshLeaderstats(player: Player)
	local data = DataService.GetData(player)
	local folder = player:FindFirstChild("leaderstats")
	if not data or not folder then
		return
	end
	local power = folder:FindFirstChild("Power")
	local rebirths = folder:FindFirstChild("Rebirths")
	if power and power:IsA("StringValue") then
		power.Value = NumberFormat.Short(data.Currencies.Power)
	end
	if rebirths and rebirths:IsA("IntValue") then
		rebirths.Value = data.Stats.Rebirths
	end
end

local function createLeaderstats(player: Player)
	if player:FindFirstChild("leaderstats") then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	local power = Instance.new("StringValue")
	power.Name = "Power"
	power.Parent = folder
	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Rebirths"
	rebirths.Parent = folder
	folder.Parent = player
	refreshLeaderstats(player)
end

-- ── Global boards ───────────────────────────────────────────────────────────

local function writeScores()
	if DataService.IsUsingMockBackend() then
		return
	end
	for _, player in Players:GetPlayers() do
		if DataService.IsLoaded(player) then
			local written = lastWritten[player] or {}
			lastWritten[player] = written
			for boardId, boardConfig in LeaderboardConfig.Boards do
				local encoded = encode(boardConfig, statValue(player, boardConfig.Stat))
				if encoded > 0 and written[boardId] ~= encoded then
					local ok, err = pcall(function()
						DataStoreService:GetOrderedDataStore(boardConfig.StoreName):SetAsync(tostring(player.UserId), encoded)
					end)
					if ok then
						written[boardId] = encoded
					else
						log:Warn("Write failed", boardId, err)
					end
				end
			end
		end
	end
end

local function readBoards()
	local isLocal = DataService.IsUsingMockBackend()
	for boardId, boardConfig in LeaderboardConfig.Boards do
		local entries: { Entry } = {}
		if isLocal then
			local players = Players:GetPlayers()
			table.sort(players, function(a, b)
				return statValue(a, boardConfig.Stat) > statValue(b, boardConfig.Stat)
			end)
			for rank, player in players do
				if rank > LeaderboardConfig.TopCount then
					break
				end
				table.insert(entries, { Rank = rank, UserId = player.UserId, Name = player.DisplayName, Value = encode(boardConfig, statValue(player, boardConfig.Stat)) })
			end
		else
			local ok, err = pcall(function()
				local pages = DataStoreService:GetOrderedDataStore(boardConfig.StoreName):GetSortedAsync(false, LeaderboardConfig.TopCount)
				for rank, item in pages:GetCurrentPage() do
					local userId = tonumber(item.key)
					if userId then
						table.insert(entries, { Rank = rank, UserId = userId, Name = nameFor(userId), Value = item.value })
					end
				end
			end)
			if not ok then
				log:Warn("Read failed", boardId, err)
				continue -- keep the previous snapshot
			end
		end
		boards[boardId] = { Entries = entries, Local = isLocal }
	end
	NetService.FireAllClients("Leaderboards", boards)
end

function LeaderboardService.GetBoards(): { [string]: Board }
	return boards
end

function LeaderboardService.Init()
	DataService.PlayerLoaded:Connect(function(player)
		createLeaderstats(player)
	end)
	DataService.PlayerReady:Connect(function(player)
		NetService.FireClient("Leaderboards", player, boards)
	end)
	CurrencyService.Changed:Connect(function(player)
		statsDirty[player] = true
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastWritten[player] = nil
		statsDirty[player] = nil
	end)
end

function LeaderboardService.Start()
	-- leaderstats: 1 Hz max per player.
	task.spawn(function()
		while true do
			task.wait(1)
			for player in statsDirty do
				statsDirty[player] = nil
				refreshLeaderstats(player)
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(LeaderboardConfig.UpdateIntervalSeconds)
			writeScores()
		end
	end)
	task.spawn(function()
		task.wait(5) -- let the first players load
		while true do
			readBoards()
			task.wait(LeaderboardConfig.RefreshIntervalSeconds)
		end
	end)
end

return LeaderboardService
