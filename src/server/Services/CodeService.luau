--!strict
--[[
	CodeService
	"RedeemCode"(text) — codes are defined ONLY in server-side CodeConfig.

	Flow (one redemption in flight per player):
		normalize → well-formed → CodeLogic.Validate (exists, enabled, not
		expired, not redeemed by this player) → RewardService.CanGrant →
		[global cap: atomic DataStore counter, only if MaxRedemptions set]
		→ grant → mark redeemed.
	The remote is tightly rate limited (brute-force protection). Wrong codes
	are normal player behavior and are NOT reported as exploits.

	Studio with the Mock data backend: the global counter is kept in memory
	(clearly logged) — never a fake success in live servers.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Guard = require(Shared.Utils.Guard)
local Logger = require(Shared.Utils.Logger)
local Signal = require(Shared.Utils.Signal)

local CodeConfig = require(script.Parent.Parent.ServerConfig.CodeConfig)
local NetService = require(script.Parent.NetService)
local DataService = require(script.Parent.DataService)
local RewardService = require(script.Parent.RewardService)
local CodeLogic = require(script.Parent.Parent.Logic.CodeLogic)

type RemoteResponse = Types.RemoteResponse

local COUNTER_STORE = "CodeRedemptions_v1"
local RAW_MAX_LENGTH = 64

local log = Logger.new("Codes")

local CodeService = {
	-- (player, code)
	Redeemed = Signal.new() :: Signal.Signal<Player, string>,
}

local inFlight: { [Player]: boolean } = {}
local memoryCounters: { [string]: number } = {} -- Studio Mock only

-- Atomically increments the global counter if below max. Returns (allowed, errorCode?).
local function reserveGlobal(code: string, maxRedemptions: number): (boolean, string?)
	if DataService.IsUsingMockBackend() then
		local count = memoryCounters[code] or 0
		if count >= maxRedemptions then
			return false, "CodeExhausted"
		end
		memoryCounters[code] = count + 1
		log:Warn("Global code counter kept in memory (Studio Mock backend)")
		return true, nil
	end
	local exhausted = false
	local ok, err = pcall(function()
		local store = DataStoreService:GetDataStore(COUNTER_STORE)
		store:UpdateAsync(code, function(current: any): any
			local count = if type(current) == "number" then current else 0
			if count >= maxRedemptions then
				exhausted = true
				return nil -- don't write
			end
			exhausted = false
			return count + 1
		end)
	end)
	if not ok then
		log:Warn("Global counter unavailable:", err)
		return false, "TryAgain"
	end
	return not exhausted, if exhausted then "CodeExhausted" else nil
end

local function redeem(player: Player, raw: string): RemoteResponse
	if inFlight[player] then
		return { Ok = false, Code = "RateLimited" }
	end
	local data = DataService.GetData(player)
	if not data then
		return { Ok = false, Code = "NotReady" }
	end
	local code = CodeLogic.Normalize(raw)
	if not CodeLogic.IsWellFormed(code, CodeConfig.MaxCodeLength) then
		return { Ok = false, Code = "InvalidCode" }
	end
	local valid, validCode, entry = CodeLogic.Validate(data, code, CodeConfig.Codes :: any, os.time())
	if not valid or not entry then
		return { Ok = false, Code = validCode }
	end
	local canGrant, grantCode = RewardService.CanGrant(player, entry.Rewards)
	if not canGrant then
		return { Ok = false, Code = grantCode }
	end

	inFlight[player] = true
	if entry.MaxRedemptions then
		local allowed, capCode = reserveGlobal(code, entry.MaxRedemptions)
		if not allowed then
			inFlight[player] = nil
			return { Ok = false, Code = capCode }
		end
		-- We yielded: re-read state (player may have left).
		data = DataService.GetData(player)
		if not data then
			inFlight[player] = nil
			return { Ok = false, Code = "NotReady" }
		end
	end

	local ok, code2, summary = RewardService.Grant(player, entry.Rewards, "Code:" .. code)
	if ok then
		CodeLogic.MarkRedeemed(data, code, os.time())
		DataService.MarkChanged(player, "Codes")
		log:Info(string.format("user=%d redeemed %s", player.UserId, code))
		CodeService.Redeemed:Fire(player, code)
	end
	inFlight[player] = nil
	if not ok then
		return { Ok = false, Code = code2 }
	end
	return { Ok = true, Data = { Summary = summary } }
end

function CodeService.Init()
	NetService.OnInvoke("RedeemCode", Guard.Args(Guard.String(RAW_MAX_LENGTH)), redeem)
	Players.PlayerRemoving:Connect(function(player)
		inFlight[player] = nil
	end)
end

return CodeService
