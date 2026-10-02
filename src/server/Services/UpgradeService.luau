--!strict
--[[
	UpgradeService
	"BuyUpgrade"(upgradeId) → server validates everything via UpgradeLogic:
	upgrade exists, not maxed, player can afford the SERVER-computed cost.
	The client never sends a price or a level.

	Responses: { Ok = true, Data = { Level, Cost } }
	           { Ok = false, Code = "UnknownUpgrade" | "MaxLevel" | "NotEnoughCurrency" }
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Guard = require(Shared.Utils.Guard)
local Signal = require(Shared.Utils.Signal)
local UpgradeConfig = require(Shared.Config.UpgradeConfig)

local NetService = require(script.Parent.NetService)
local DataService = require(script.Parent.DataService)
local CurrencyService = require(script.Parent.CurrencyService)
local PowerService = require(script.Parent.PowerService)
local PetService = require(script.Parent.PetService)
local UpgradeLogic = require(script.Parent.Parent.Logic.UpgradeLogic)

type RemoteResponse = Types.RemoteResponse

local UpgradeService = {
	-- (player, upgradeId, newLevel)
	Purchased = Signal.new() :: Signal.Signal<Player, string, number>,
}

-- All ids across both groups, for argument validation.
local allUpgrades: { [string]: boolean } = {}
for id in UpgradeConfig.Temporary do
	allUpgrades[id] = true
end
for id in UpgradeConfig.Permanent do
	allUpgrades[id] = true
end

-- Total effect of a permanent upgrade type (used by later phases: slots, luck...).
function UpgradeService.GetPermanentEffect(player: Player, effectType: Types.UpgradeEffectType): number
	local data = DataService.GetData(player)
	return if data then UpgradeLogic.GetEffect(data, "Permanent", effectType) else 0
end

-- `amount` is how many levels to buy; 0 means "as many as affordable".
function UpgradeService.Purchase(player: Player, upgradeId: string, amount: number?): RemoteResponse
	local data = DataService.GetData(player)
	if not data then
		return { Ok = false, Code = "NotReady" }
	end
	local upgrade, group = UpgradeLogic.Find(upgradeId)
	local ok, code, level, cost, bought = UpgradeLogic.Purchase(data, upgradeId, amount)
	if not ok or not upgrade or not group or not level or not cost then
		return { Ok = false, Code = code or "UnknownUpgrade" }
	end

	DataService.MarkChanged(player, if group == "Temporary" then "Upgrades" else "PermanentUpgrades")
	CurrencyService.NotifyChanged(player, upgrade.Currency, -cost, "Upgrade:" .. upgradeId)
	PowerService.Invalidate(player)
	if upgrade.EffectType == "EquipSlots" or upgrade.EffectType == "InventorySlots" then
		DataService.MarkChanged(player, "Pets")
		PetService.NotifyChanged(player)
	end
	UpgradeService.Purchased:Fire(player, upgradeId, level)
	return { Ok = true, Data = { Level = level, Cost = cost, Bought = bought } }
end

function UpgradeService.Init()
	-- amount: 1..MaxBulk levels, or 0 for "as many as the player can afford".
	NetService.OnInvoke(
		"BuyUpgrade",
		Guard.Args(Guard.KeyOf(allUpgrades), Guard.Integer(0, UpgradeConfig.MaxBulk)),
		function(player: Player, upgradeId: string, amount: number): RemoteResponse
			return UpgradeService.Purchase(player, upgradeId, amount)
		end
	)
end

return UpgradeService
