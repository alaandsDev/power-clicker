--!strict
--[[
	GameStateController
	Client mirror of NON-persisted server state (display only):
	- PowerInfo (power per click and multiplier breakdown)
	- Overdrive (active / remaining / cooldown)
	- Combo (server stacks + local prediction between server updates)
	Nothing here affects gameplay; the server recomputes everything.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Signal = require(Shared:WaitForChild("Utils"):WaitForChild("Signal"))
local Formulas = Shared:WaitForChild("Formulas")
local ComboLogic = require(Formulas:WaitForChild("ComboLogic"))

local ClientNet = require(script.Parent.Parent.Net.ClientNet)

export type PowerInfo = { PerClick: number, Base: number, Total: number, Layers: { [string]: number } }

-- How long local prediction wins over (slightly stale) server combo values.
local PREDICTION_WINDOW = 0.4

local GameStateController = {
	PowerInfoChanged = Signal.new() :: Signal.Signal<PowerInfo>,
	OverdriveChanged = Signal.new() :: Signal.Signal<boolean>,
	-- (manualGain, manualClicks, autoGain)
	Feedback = Signal.new() :: Signal.Signal<number, number, number>,
}

local powerInfo: PowerInfo = { PerClick = 1, Base = 1, Total = 1, Layers = {} }
local overdriveActive = false
local overdriveEndsAt = 0
local cooldownEndsAt = 0

local comboStacks = 0
local comboAt = 0 -- time the stacks value refers to (last click)
local lastLocalClick = -math.huge

function GameStateController.GetPowerInfo(): PowerInfo
	return powerInfo
end

function GameStateController.IsOverdriveActive(): boolean
	return overdriveActive and os.clock() < overdriveEndsAt
end

function GameStateController.GetOverdriveRemaining(): number
	return math.max(0, overdriveEndsAt - os.clock())
end

function GameStateController.GetCooldownRemaining(): number
	return math.max(0, cooldownEndsAt - os.clock())
end

function GameStateController.GetCombo(): number
	return ComboLogic.Current(comboStacks, comboAt, os.clock())
end

-- Local prediction for a click the client just sent. Returns predicted stacks.
function GameStateController.RegisterLocalClick(): number
	local now = os.clock()
	comboStacks = ComboLogic.Register(comboStacks, comboAt, now)
	comboAt = now
	lastLocalClick = now
	return comboStacks
end

function GameStateController.Init()
	ClientNet.On("PowerInfo", function(info: any)
		if type(info) == "table" and type(info.PerClick) == "number" then
			powerInfo = info
			GameStateController.PowerInfoChanged:Fire(info)
		end
	end)

	ClientNet.On("OverdriveState", function(active: any, remaining: any, cooldown: any)
		local now = os.clock()
		overdriveActive = active == true
		overdriveEndsAt = now + (if type(remaining) == "number" then remaining else 0)
		cooldownEndsAt = now + (if type(cooldown) == "number" then cooldown else 0)
		GameStateController.OverdriveChanged:Fire(overdriveActive)
	end)

	ClientNet.On("ClickFeedback", function(manualGain: any, manualClicks: any, serverCombo: any, autoGain: any)
		local now = os.clock()
		if type(serverCombo) == "number" and now - lastLocalClick > PREDICTION_WINDOW then
			comboStacks = serverCombo
			comboAt = now
		end
		GameStateController.Feedback:Fire(
			if type(manualGain) == "number" then manualGain else 0,
			if type(manualClicks) == "number" then manualClicks else 0,
			if type(autoGain) == "number" then autoGain else 0
		)
	end)
end

return GameStateController
