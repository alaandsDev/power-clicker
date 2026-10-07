--!strict
--[[
	BoostService
	Temporary boosts (BoostLogic). Registers:
	- PowerService provider "TemporaryBoost" (highest Power boost)
	- EggService luck provider "Boosts" (highest Luck boost)
	Time is consumed only while online, ticked once per second for all
	players by a single loop. The client counts down locally; "Boosts" is
	replicated on add/expire and resynced periodically.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Logger = require(Shared.Utils.Logger)
local Signal = require(Shared.Utils.Signal)

local DataService = require(script.Parent.DataService)
local PowerService = require(script.Parent.PowerService)
local EggService = require(script.Parent.EggService)
local BoostLogic = require(script.Parent.Parent.Logic.BoostLogic)

local TICK_SECONDS = 1
local MAX_TICK_SECONDS = 5 -- clamp after server hitches
local RESYNC_SECONDS = 15

local log = Logger.new("Boosts")

local BoostService = {
	-- (player, boostId, stacks, source)
	Added = Signal.new() :: Signal.Signal<Player, string, number, string>,
}

-- Adds a boost from a trusted server source (reward, product, debug).
function BoostService.Add(player: Player, boostId: string, stacks: number, source: string): (boolean, string?)
	local data = DataService.GetData(player)
	if not data then
		return false, "NotReady"
	end
	local ok, code = BoostLogic.Add(data, boostId, stacks)
	if not ok then
		return false, code
	end
	BoostService.NotifyChanged(player)
	log:Debug(string.format("user=%d +%dx %s (%s)", player.UserId, stacks, boostId, source))
	BoostService.Added:Fire(player, boostId, stacks, source)
	return true, nil
end

-- Same as Add, but grants an exact duration instead of stacks.
function BoostService.AddSeconds(player: Player, boostId: string, seconds: number, source: string): (boolean, string?)
	local data = DataService.GetData(player)
	if not data then
		return false, "NotReady"
	end
	local ok, code = BoostLogic.AddSeconds(data, boostId, seconds)
	if not ok then
		return false, code
	end
	BoostService.NotifyChanged(player)
	log:Debug(string.format("user=%d +%ds %s (%s)", player.UserId, seconds, boostId, source))
	BoostService.Added:Fire(player, boostId, 1, source)
	return true, nil
end

-- For callers that mutated boosts via a Logic module (RewardLogic).
function BoostService.NotifyChanged(player: Player)
	DataService.MarkChanged(player, "Boosts")
	PowerService.Invalidate(player)
end

function BoostService.Init()
	PowerService.RegisterProvider("TemporaryBoost", function(_player, data)
		return BoostLogic.GetMultiplier(data, "Power")
	end)
	EggService.RegisterLuckProvider("Boosts", function(player)
		local data = DataService.GetData(player)
		return if data then BoostLogic.GetMultiplier(data, "Luck") else 1
	end)
end

function BoostService.Start()
	task.spawn(function()
		local last = os.clock()
		local sinceResync = 0
		while true do
			task.wait(TICK_SECONDS)
			local now = os.clock()
			local elapsed = math.min(now - last, MAX_TICK_SECONDS)
			last = now
			sinceResync += elapsed
			local resync = sinceResync >= RESYNC_SECONDS
			if resync then
				sinceResync = 0
			end
			for _, player in game:GetService("Players"):GetPlayers() do
				local data = DataService.GetData(player)
				if data and BoostLogic.HasActive(data) then
					local expired = BoostLogic.Tick(data, elapsed)
					if #expired > 0 then
						BoostService.NotifyChanged(player)
					elseif resync then
						DataService.MarkChanged(player, "Boosts")
					end
				end
			end
		end
	end)
end

return BoostService
