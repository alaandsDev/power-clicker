--!strict
--[[
	UpgradeLogic
	Pure upgrade rules. Upgrade ids are unique across the Temporary and
	Permanent groups (enforced by ConfigValidator).

	Temporary levels live in data.Upgrades (reset on rebirth), permanent ones
	in data.PermanentUpgrades.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local EconomyFormulas = require(Shared.Formulas.EconomyFormulas)
local CurrencyLogic = require(script.Parent.CurrencyLogic)

type PlayerData = Types.PlayerData
type UpgradeData = Types.UpgradeData
type UpgradeEffectType = Types.UpgradeEffectType

export type Group = "Temporary" | "Permanent"
-- Failure codes: "UnknownUpgrade" | "MaxLevel" | "NotEnoughCurrency"

local UpgradeLogic = {}

-- `group` is a Group value; typed as string because callers get it from Find().
local function levelsFor(data: PlayerData, group: string): { [string]: number }
	return if group == "Temporary" then data.Upgrades else data.PermanentUpgrades
end

function UpgradeLogic.Find(upgradeId: string): (UpgradeData?, Group?)
	local temporary = UpgradeConfig.Temporary[upgradeId]
	if temporary then
		return temporary, "Temporary"
	end
	local permanent = UpgradeConfig.Permanent[upgradeId]
	if permanent then
		return permanent, "Permanent"
	end
	return nil, nil
end

function UpgradeLogic.GetLevel(data: PlayerData, upgradeId: string): number
	local _, group = UpgradeLogic.Find(upgradeId)
	if not group then
		return 0
	end
	local level = levelsFor(data, group)[upgradeId]
	if type(level) ~= "number" or level ~= level or level < 0 then
		return 0
	end
	return math.floor(level)
end

function UpgradeLogic.GetCost(data: PlayerData, upgradeId: string): number
	local upgrade = UpgradeLogic.Find(upgradeId)
	if not upgrade then
		return math.huge
	end
	return EconomyFormulas.UpgradeCost(upgrade, UpgradeLogic.GetLevel(data, upgradeId))
end

-- Sum of an effect over every upgrade of a group.
function UpgradeLogic.GetEffect(data: PlayerData, group: string, effectType: UpgradeEffectType): number
	local configs: { [string]: UpgradeData } = if group == "Temporary" then UpgradeConfig.Temporary else UpgradeConfig.Permanent
	local total = 0
	for id, upgrade in configs do
		if upgrade.EffectType == effectType then
			total += EconomyFormulas.UpgradeEffect(upgrade, UpgradeLogic.GetLevel(data, id))
		end
	end
	return total
end

--[[
	Cost of buying `amount` levels from the current one, and how many of those
	are actually affordable. Each level costs more than the last, so the sum is
	walked level by level (there is no shortcut that stays exact).
	`amount` <= 0 means "as many as the player can afford".
	Returns (levels, totalCost).
]]
function UpgradeLogic.PlanPurchase(data: PlayerData, upgradeId: string, amount: number): (number, number)
	local upgrade = UpgradeLogic.Find(upgradeId)
	if not upgrade then
		return 0, 0
	end
	local level = UpgradeLogic.GetLevel(data, upgradeId)
	local room = upgrade.MaxLevel - level
	if room <= 0 then
		return 0, 0
	end
	local wanted = if amount <= 0 then room else math.min(math.floor(amount), room)
	local balance = CurrencyLogic.Get(data, upgrade.Currency)
	local bought, total = 0, 0
	while bought < wanted do
		local cost = EconomyFormulas.UpgradeCost(upgrade, level + bought)
		if cost == math.huge or total + cost > balance then
			break
		end
		total += cost
		bought += 1
	end
	return bought, total
end

--[[
	Mutates `data`: buys up to `amount` levels (<= 0 means as many as possible).
	Returns (true, nil, newLevel, totalCost, levelsBought) or (false, code).
	Buying ten at once must cost exactly the same as buying one ten times, so
	the price of every single level is summed — never the first level times ten.
]]
function UpgradeLogic.Purchase(data: PlayerData, upgradeId: string, amount: number?): (boolean, string?, number?, number?, number?)
	local upgrade, group = UpgradeLogic.Find(upgradeId)
	if not upgrade or not group then
		return false, "UnknownUpgrade"
	end
	local level = UpgradeLogic.GetLevel(data, upgradeId)
	if level >= upgrade.MaxLevel then
		return false, "MaxLevel"
	end
	local bought, total = UpgradeLogic.PlanPurchase(data, upgradeId, amount or 1)
	if bought <= 0 then
		return false, "NotEnoughCurrency"
	end
	if not CurrencyLogic.Remove(data, upgrade.Currency, total) then
		return false, "NotEnoughCurrency"
	end
	levelsFor(data, group)[upgradeId] = level + bought
	return true, nil, level + bought, total, bought
end

-- Clears all temporary upgrades (rebirth).
function UpgradeLogic.ResetTemporary(data: PlayerData)
	table.clear(data.Upgrades)
end

return UpgradeLogic
