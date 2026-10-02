--!strict
--[[
	ClickService
	Handles the "Click" remote (no arguments — the client only says "I clicked").

	Per valid manual click (already rate limited by NetService at
	EconomyConfig.Click.MaxClicksPerSecond):
		combo += 1 (with timeout/decay, ComboLogic)
		gain = PowerService.ComputeClick(player, ComboMultiplier)
		CurrencyService.Add(Power, gain)
		TotalClicks += 1, HighestCombo
		OverdriveService.OnManualClick
		ClickPatternDetector → AntiExploit signal only (never blocks)

	Auto Click: the SERVER generates ticks at AutoClick.TicksPerSecond for
	players with auto click enabled (gamepass in Phase 6, debug in Studio).
	Auto ticks use combo multiplier 1 and don't charge Overdrive.

	Feedback to the client is batched (ClickFeedback, every flush interval).
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Guard = require(Shared.Utils.Guard)
local Signal = require(Shared.Utils.Signal)
local GameConfig = require(Shared.Config.GameConfig)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local EconomyFormulas = require(Shared.Formulas.EconomyFormulas)
local ComboLogic = require(Shared.Formulas.ComboLogic)

local ServerConfig = script.Parent.Parent.ServerConfig
local AntiExploitConfig = require(ServerConfig.AntiExploitConfig)

local NetService = require(script.Parent.NetService)
local DataService = require(script.Parent.DataService)
local CurrencyService = require(script.Parent.CurrencyService)
local PowerService = require(script.Parent.PowerService)
local OverdriveService = require(script.Parent.OverdriveService)
local ZoneService = require(script.Parent.ZoneService)
local TargetService = require(script.Parent.TargetService)
local BossService = require(script.Parent.BossService)
local WallService = require(script.Parent.WallService)
local AntiExploitService = require(script.Parent.AntiExploitService)
local ClickPatternDetector = require(script.Parent.Parent.Logic.ClickPatternDetector)

type ClickState = {
	Combo: number,
	LastClickAt: number,
	Detector: ClickPatternDetector.Detector,
	PendingManualGain: number,
	PendingManualClicks: number,
	PendingAutoGain: number,
	Dirty: boolean,
	AutoClick: boolean,
}

local ClickService = {
	-- (player, gain, isAuto) after every processed click. For quests/achievements.
	Clicked = Signal.new() :: Signal.Signal<Player, number, boolean>,
}

local states: { [Player]: ClickState } = {}

local function getState(player: Player): ClickState
	local state = states[player]
	if not state then
		local pattern = AntiExploitConfig.ClickPattern
		state = {
			Combo = 0,
			LastClickAt = 0,
			Detector = ClickPatternDetector.new(pattern.SampleSize, pattern.MinStdDevSeconds, pattern.MaxMeanSeconds),
			PendingManualGain = 0,
			PendingManualClicks = 0,
			PendingAutoGain = 0,
			Dirty = false,
			AutoClick = false,
		}
		states[player] = state
	end
	return state
end

-- Core click processing. Returns the Power gained.
local function processClick(player: Player, isAuto: boolean): number
	local data = DataService.GetData(player)
	if not data then
		return 0
	end
	local state = getState(player)
	local now = os.clock()

	local comboMultiplier = 1
	if not isAuto then
		state.Combo = ComboLogic.Register(state.Combo, state.LastClickAt, now)
		state.LastClickAt = now
		comboMultiplier = EconomyFormulas.ComboMultiplier(state.Combo)
		if state.Combo > data.Stats.HighestCombo then
			data.Stats.HighestCombo = state.Combo
		end
		if state.Detector:Record(now) then
			AntiExploitService.Report(player, "SuspiciousPattern", "click timing too regular")
		end
	elseif EconomyConfig.AutoClick.BuildsCombo then
		comboMultiplier = EconomyFormulas.ComboMultiplier(ComboLogic.Current(state.Combo, state.LastClickAt, now))
	end

	local gain = CurrencyService.Add(player, "Power", PowerService.ComputeClick(player, comboMultiplier), if isAuto then "AutoClick" else "Click")
	data.Stats.TotalClicks += 1
	-- The same click also damages the nearest target in the player's zone;
	-- breaking one pays its reward, shown with the click's own feedback.
	local total = gain
		+ TargetService.OnClick(player, ZoneService.GetZone(player), gain)
		+ BossService.OnClick(player, gain)
		+ WallService.OnClick(player, gain) -- the win corridor pays in wins, not Power

	if isAuto then
		state.PendingAutoGain += total
		if EconomyConfig.AutoClick.BuildsOverdrive then
			OverdriveService.OnManualClick(player)
		end
	else
		state.PendingManualGain += total
		state.PendingManualClicks += 1
		OverdriveService.OnManualClick(player)
	end
	state.Dirty = true

	ClickService.Clicked:Fire(player, total, isAuto)
	return total
end

function ClickService.SetAutoClick(player: Player, enabled: boolean)
	getState(player).AutoClick = enabled
end

function ClickService.IsAutoClickEnabled(player: Player): boolean
	local state = states[player]
	return state ~= nil and state.AutoClick
end

function ClickService.Init()
	NetService.On("Click", Guard.Args(), function(player: Player)
		processClick(player, false)
	end)

	DataService.DataReset:Connect(function(player)
		local state = states[player]
		if state then
			state.Combo = 0
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
end

function ClickService.Start()
	-- Batched feedback.
	task.spawn(function()
		while true do
			task.wait(GameConfig.Replication.FlushIntervalSeconds)
			local now = os.clock()
			for player, state in states do
				if state.Dirty then
					state.Dirty = false
					NetService.FireClient(
						"ClickFeedback",
						player,
						state.PendingManualGain,
						state.PendingManualClicks,
						ComboLogic.Current(state.Combo, state.LastClickAt, now),
						state.PendingAutoGain
					)
					state.PendingManualGain = 0
					state.PendingManualClicks = 0
					state.PendingAutoGain = 0
				end
			end
		end
	end)

	-- Server-generated auto click ticks.
	task.spawn(function()
		local interval = 1 / EconomyConfig.AutoClick.TicksPerSecond
		while true do
			task.wait(interval)
			for player, state in states do
				if state.AutoClick then
					processClick(player, true)
				end
			end
		end
	end)
end

return ClickService
