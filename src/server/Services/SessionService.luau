--!strict
--[[
	SessionService
	Session retention (Phase 12):

	1. Playtime chests — every SessionConfig.Chests milestone of the CURRENT
	   session is paid automatically, once per session. Session time is counted
	   here from the join clock (never from the client), so a reconnect cannot
	   farm the same chest twice within a session.

	2. Happy Hour — the scheduled server-wide multiplier, published as the
	   "Event" power layer and pushed to clients for the banner.

	Both are server-authoritative; the client only displays.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Logger = require(Shared.Utils.Logger)
local Signal = require(Shared.Utils.Signal)
local SessionConfig = require(Shared.Config.SessionConfig)
local ScheduleRules = require(Shared.Formulas.ScheduleRules)

local NetService = require(script.Parent.NetService)
local CurrencyService = require(script.Parent.CurrencyService)
local PowerService = require(script.Parent.PowerService)
local RewardService = require(script.Parent.RewardService)

local log = Logger.new("Session")

local SessionService = {
	-- (player, minutes, power)
	ChestClaimed = Signal.new() :: Signal.Signal<Player, number, number>,
}

local joinedAt: { [Player]: number } = {}
local claimed: { [Player]: { [number]: boolean } } = {}
local currentMultiplier = 1
local currentEventId: string? = nil

-- Seconds the player has been in THIS server.
function SessionService.SessionSeconds(player: Player): number
	local since = joinedAt[player]
	return if since then os.clock() - since else 0
end

local function chestPower(player: Player, chest: SessionConfig.PlaytimeChest): number
	local info = PowerService.GetInfo(player)
	local perClick = if info then info.PerClick else 0
	return math.max(perClick * chest.ClicksWorth, SessionConfig.MinChestPower)
end

local function payChests(player: Player)
	local minutes = SessionService.SessionSeconds(player) / 60
	local taken = claimed[player]
	if not taken then
		return
	end
	for index, chest in SessionConfig.Chests do
		if minutes >= chest.Minutes and not taken[index] then
			taken[index] = true
			local power = CurrencyService.Add(player, "Power", chestPower(player, chest), "PlaytimeChest")
			if #chest.Rewards > 0 then
				RewardService.Grant(player, chest.Rewards, "PlaytimeChest")
			end
			NetService.FireClient("Notify", player, "PlaytimeChest", {
				Minutes = chest.Minutes,
				Power = power,
			})
			SessionService.ChestClaimed:Fire(player, chest.Minutes, power)
			log:Info(string.format("user=%d playtime chest %d min", player.UserId, chest.Minutes))
		end
	end
end

local function publishEvent(force: boolean)
	local window, secondsLeft = ScheduleRules.Active(os.time())
	local id = if window then window.Id else nil
	local multiplier = if window then window.Multiplier else 1
	if not force and id == currentEventId and multiplier == currentMultiplier then
		-- Same window: refresh the countdown only.
		NetService.FireAllClients("EventState", { EventId = id, Multiplier = multiplier, SecondsLeft = secondsLeft })
		return
	end
	currentEventId = id
	currentMultiplier = multiplier
	for _, player in Players:GetPlayers() do
		PowerService.Invalidate(player)
	end
	NetService.FireAllClients("EventState", { EventId = id, Multiplier = multiplier, SecondsLeft = secondsLeft })
	log:Info("happy hour:", id or "none", "x" .. tostring(multiplier))
end

function SessionService.Init()
	PowerService.RegisterProvider("Event", function(): number
		return currentMultiplier
	end)

	local function track(player: Player)
		joinedAt[player] = os.clock()
		claimed[player] = {}
	end
	for _, player in Players:GetPlayers() do
		track(player)
	end
	Players.PlayerAdded:Connect(track)
	Players.PlayerRemoving:Connect(function(player)
		joinedAt[player] = nil
		claimed[player] = nil
	end)
end

function SessionService.Start()
	publishEvent(true)
	task.spawn(function()
		while true do
			task.wait(SessionConfig.TickSeconds)
			publishEvent(false)
			for _, player in Players:GetPlayers() do
				payChests(player)
			end
		end
	end)
end

return SessionService
