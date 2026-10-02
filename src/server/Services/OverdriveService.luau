--!strict
--[[
	OverdriveService
	Charge (persisted in data.Overdrive.Charge) fills from valid MANUAL clicks.
	When full: Overdrive is active for DurationSeconds and the "Overdrive"
	power layer becomes OverdriveConfig.Multiplier. Then a cooldown.

	State that must not be persisted (active/ends/cooldown) lives in memory;
	a player who leaves during Overdrive loses the rest of it (charge was
	already spent).

	Server → client: OverdriveState(active, remainingSeconds, cooldownSeconds).
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Logger = require(Shared.Utils.Logger)
local Signal = require(Shared.Utils.Signal)
local OverdriveConfig = require(Shared.Config.OverdriveConfig)

local NetService = require(script.Parent.NetService)
local DataService = require(script.Parent.DataService)
local PowerService = require(script.Parent.PowerService)

type State = {
	Active: boolean,
	EndsAt: number, -- os.clock()
	CooldownEndsAt: number,
	Token: number, -- invalidates stale end timers
}

local log = Logger.new("Overdrive")

local OverdriveService = {
	-- (player, source: "Charge" | "Product" | "Debug")
	Activated = Signal.new() :: Signal.Signal<Player, string>,
	Ended = Signal.new() :: Signal.Signal<Player>,
}

local states: { [Player]: State } = {}

local function getState(player: Player): State
	local state = states[player]
	if not state then
		state = { Active = false, EndsAt = 0, CooldownEndsAt = 0, Token = 0 }
		states[player] = state
	end
	return state
end

local function push(player: Player)
	local state = getState(player)
	local now = os.clock()
	NetService.FireClient(
		"OverdriveState",
		player,
		state.Active,
		if state.Active then math.max(0, state.EndsAt - now) else 0,
		math.max(0, state.CooldownEndsAt - now)
	)
end

function OverdriveService.IsActive(player: Player): boolean
	local state = states[player]
	return state ~= nil and state.Active
end

local function finish(player: Player, token: number)
	local state = states[player]
	if not state or state.Token ~= token or not state.Active then
		return
	end
	state.Active = false
	state.CooldownEndsAt = os.clock() + OverdriveConfig.CooldownSeconds
	PowerService.Invalidate(player)
	push(player)
	OverdriveService.Ended:Fire(player)
end

-- Starts Overdrive regardless of charge (charge is consumed). Returns false if already active.
function OverdriveService.Activate(player: Player, source: string): boolean
	local data = DataService.GetData(player)
	if not data then
		return false
	end
	local state = getState(player)
	if state.Active then
		return false
	end

	state.Active = true
	state.EndsAt = os.clock() + OverdriveConfig.DurationSeconds
	state.Token += 1
	local token = state.Token

	data.Overdrive.Charge = 0
	data.Stats.OverdrivesActivated += 1
	DataService.MarkChanged(player, "Overdrive")
	DataService.MarkChanged(player, "Stats")
	PowerService.Invalidate(player)
	push(player)

	task.delay(OverdriveConfig.DurationSeconds, finish, player, token)
	log:Debug(string.format("user=%d activated (%s)", player.UserId, source))
	OverdriveService.Activated:Fire(player, source)
	return true
end

-- Starts Overdrive, or extends it by one full duration if already active
-- (so a paid Instant Overdrive is never wasted).
function OverdriveService.ActivateOrExtend(player: Player, source: string): boolean
	local state = states[player]
	if not state or not state.Active then
		return OverdriveService.Activate(player, source)
	end
	state.EndsAt += OverdriveConfig.DurationSeconds
	state.Token += 1
	local token = state.Token
	task.delay(state.EndsAt - os.clock(), finish, player, token)
	push(player)
	OverdriveService.Activated:Fire(player, source)
	return true
end

-- Called by ClickService for every valid MANUAL click.
function OverdriveService.OnManualClick(player: Player)
	local data = DataService.GetData(player)
	if not data then
		return
	end
	local state = getState(player)
	if state.Active or os.clock() < state.CooldownEndsAt then
		return
	end
	local charge = math.min((data.Overdrive.Charge or 0) + OverdriveConfig.ChargePerClick, OverdriveConfig.ChargeMax)
	data.Overdrive.Charge = charge
	DataService.MarkChanged(player, "Overdrive")
	if charge >= OverdriveConfig.ChargeMax then
		OverdriveService.Activate(player, "Charge")
	end
end

local function resetPlayer(player: Player)
	local state = states[player]
	if state then
		state.Token += 1 -- cancels pending end timer
	end
	states[player] = nil
end

function OverdriveService.Init()
	PowerService.RegisterProvider("Overdrive", function(player)
		return if OverdriveService.IsActive(player) then OverdriveConfig.Multiplier else 1
	end)

	DataService.PlayerLoaded:Connect(function(_player, data)
		if not OverdriveConfig.PersistCharge then
			data.Overdrive.Charge = 0
		end
		data.Overdrive.Charge = math.clamp(data.Overdrive.Charge, 0, OverdriveConfig.ChargeMax)
	end)
	DataService.PlayerReady:Connect(push)
	DataService.DataReset:Connect(function(player)
		resetPlayer(player)
		push(player)
	end)
	Players.PlayerRemoving:Connect(resetPlayer)
end

return OverdriveService
