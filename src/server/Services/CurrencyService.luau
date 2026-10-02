--!strict
--[[
	CurrencyService
	The ONLY way currencies change. Wraps CurrencyLogic (pure rules) with
	replication and a change signal. No function here yields, so a service can
	safely do  if CurrencyService.Remove(...) then <grant> end  atomically.

	Never call this directly from a remote handler with client-provided
	amounts: the amount must always come from config/formulas on the server.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Logger = require(Shared.Utils.Logger)
local Signal = require(Shared.Utils.Signal)

local DataService = require(script.Parent.DataService)
local CurrencyLogic = require(script.Parent.Parent.Logic.CurrencyLogic)

type CurrencyId = Types.CurrencyId

local log = Logger.new("Currency")

local CurrencyService = {
	-- (player, currency, newBalance, delta, reason)
	Changed = Signal.new() :: Signal.Signal<Player, CurrencyId, number, number, string>,
}

local function changed(player: Player, currency: CurrencyId, delta: number, reason: string, balance: number)
	DataService.MarkChanged(player, "Currencies")
	DataService.MarkChanged(player, "Stats")
	CurrencyService.Changed:Fire(player, currency, balance, delta, reason)
end

function CurrencyService.Get(player: Player, currency: CurrencyId): number
	local data = DataService.GetData(player)
	return if data then CurrencyLogic.Get(data, currency) else 0
end

function CurrencyService.CanAfford(player: Player, currency: CurrencyId, amount: number): boolean
	local data = DataService.GetData(player)
	return data ~= nil and CurrencyLogic.CanAfford(data, currency, amount)
end

-- Returns the amount actually added (0 if the data isn't loaded or the amount is invalid).
function CurrencyService.Add(player: Player, currency: CurrencyId, amount: number, reason: string): number
	local data = DataService.GetData(player)
	if not data then
		return 0
	end
	local added = CurrencyLogic.Add(data, currency, amount)
	if added > 0 then
		changed(player, currency, added, reason, CurrencyLogic.Get(data, currency))
	elseif not CurrencyLogic.IsValidAmount(amount) then
		log:Error("Rejected invalid add", currency, tostring(amount), reason)
	end
	return added
end

-- Removes the full amount or nothing. Returns true on success.
function CurrencyService.Remove(player: Player, currency: CurrencyId, amount: number, reason: string): boolean
	local data = DataService.GetData(player)
	if not data or not CurrencyLogic.Remove(data, currency, amount) then
		return false
	end
	changed(player, currency, -amount, reason, CurrencyLogic.Get(data, currency))
	return true
end

function CurrencyService.Reset(player: Player, currency: CurrencyId, reason: string)
	local data = DataService.GetData(player)
	if not data then
		return
	end
	local before = CurrencyLogic.Get(data, currency)
	CurrencyLogic.Reset(data, currency)
	changed(player, currency, -before, reason, 0)
end

-- For services that mutate data through a Logic module (e.g. RebirthLogic)
-- and only need replication + the signal afterwards.
function CurrencyService.NotifyChanged(player: Player, currency: CurrencyId, delta: number, reason: string)
	changed(player, currency, delta, reason, CurrencyService.Get(player, currency))
end

return CurrencyService
