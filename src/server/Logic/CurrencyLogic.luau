--!strict
--[[
	CurrencyLogic
	Pure currency rules operating on a PlayerData table. CurrencyService is the
	only caller in production (it adds replication + signals on top).

	Invariants:
	- Balances are always finite, >= 0 and <= GameConfig.Numbers.MaxValue.
	- Amounts must be finite and > 0; anything else is rejected (returns 0/false).
	- Remove never goes negative: it either removes the full amount or nothing.
	- No function here yields, so check-then-mutate is atomic.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local EconomyFormulas = require(Shared.Formulas.EconomyFormulas)
local GameConfig = require(Shared.Config.GameConfig)

type PlayerData = Types.PlayerData

local MAX_VALUE = GameConfig.Numbers.MaxValue

local EARNED_STAT: { [string]: string } = {
	Power = "TotalPowerEarned",
	Gems = "TotalGemsEarned",
	Wins = "TotalWinsEarned",
}

local CurrencyLogic = {}

function CurrencyLogic.IsCurrency(currency: any): boolean
	return type(currency) == "string" and (EconomyConfig.Currencies :: any)[currency] ~= nil
end

function CurrencyLogic.IsValidAmount(amount: any): boolean
	return type(amount) == "number" and amount == amount and amount > 0 and amount < math.huge
end

function CurrencyLogic.Get(data: PlayerData, currency: string): number
	return EconomyFormulas.Sanitize((data.Currencies :: any)[currency] or 0)
end

function CurrencyLogic.CanAfford(data: PlayerData, currency: string, amount: number): boolean
	if not CurrencyLogic.IsCurrency(currency) or not CurrencyLogic.IsValidAmount(amount) then
		return false
	end
	return CurrencyLogic.Get(data, currency) >= amount
end

-- Returns the amount actually added (0 when rejected; less when capped).
function CurrencyLogic.Add(data: PlayerData, currency: string, amount: number): number
	if not CurrencyLogic.IsCurrency(currency) or not CurrencyLogic.IsValidAmount(amount) then
		return 0
	end
	local current = CurrencyLogic.Get(data, currency)
	local new = math.min(current + amount, MAX_VALUE)
	local added = new - current
	;(data.Currencies :: any)[currency] = new

	local stat = EARNED_STAT[currency]
	if stat and added > 0 then
		local stats = data.Stats :: any
		stats[stat] = math.min((stats[stat] or 0) + added, MAX_VALUE)
	end
	return added
end

-- Removes exactly `amount` or nothing. Returns true on success.
function CurrencyLogic.Remove(data: PlayerData, currency: string, amount: number): boolean
	if not CurrencyLogic.CanAfford(data, currency, amount) then
		return false
	end
	local current = CurrencyLogic.Get(data, currency)
	;(data.Currencies :: any)[currency] = math.max(0, current - amount)
	return true
end

function CurrencyLogic.Reset(data: PlayerData, currency: string)
	if CurrencyLogic.IsCurrency(currency) then
		(data.Currencies :: any)[currency] = 0
	end
end

return CurrencyLogic
