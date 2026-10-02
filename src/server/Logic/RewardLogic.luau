--!strict
--[[
	RewardLogic
	Grants a list of RewardData atomically: CanGrant is checked first (pet
	rewards need free inventory slots, every entry must be valid); if it
	fails, NOTHING is granted. Used by daily rewards, quests, achievements,
	codes and (Phase 6) developer products.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local PetConfig = require(Shared.Config.PetConfig)
local BoostConfig = require(Shared.Config.BoostConfig)
local CurrencyLogic = require(script.Parent.CurrencyLogic)
local BoostLogic = require(script.Parent.BoostLogic)
local PetLogic = require(script.Parent.PetLogic)

type PlayerData = Types.PlayerData
type RewardData = Types.RewardData

-- What was granted, for replication and UI.
export type GrantSummary = {
	Currencies: { [string]: number },
	Boosts: { [string]: number },
	Pets: { { Uid: string, PetId: string } },
}

local RewardLogic = {}

export type GrantOptions = {
	-- Paid purchases only: pets are granted even over inventory capacity.
	IgnoreCapacity: boolean?,
}

-- Codes: "InvalidReward" | "InventoryFull"
function RewardLogic.CanGrant(data: PlayerData, rewards: { RewardData }, options: GrantOptions?): (boolean, string?)
	local petsNeeded = 0
	for _, reward in rewards do
		if reward.Type == "Currency" then
			if not CurrencyLogic.IsCurrency(reward.Currency) or not CurrencyLogic.IsValidAmount(reward.Amount) then
				return false, "InvalidReward"
			end
		elseif reward.Type == "Boost" then
			if not reward.BoostId or not BoostConfig.Boosts[reward.BoostId] then
				return false, "InvalidReward"
			end
		elseif reward.Type == "Pet" then
			if not reward.PetId or not PetConfig.Pets[reward.PetId] then
				return false, "InvalidReward"
			end
			petsNeeded += 1
		else
			return false, "InvalidReward"
		end
	end
	local ignoreCapacity = options ~= nil and options.IgnoreCapacity == true
	if petsNeeded > 0 and not ignoreCapacity and PetLogic.Count(data) + petsNeeded > PetLogic.GetInventoryCapacity(data) then
		return false, "InventoryFull"
	end
	return true, nil
end

-- Mutates `data`. Returns (true, nil, summary) or (false, code) with no changes.
function RewardLogic.Grant(data: PlayerData, rewards: { RewardData }, now: number, options: GrantOptions?): (boolean, string?, GrantSummary?)
	local ok, code = RewardLogic.CanGrant(data, rewards, options)
	local ignoreCapacity = options ~= nil and options.IgnoreCapacity == true
	if not ok then
		return false, code
	end
	local summary: GrantSummary = { Currencies = {}, Boosts = {}, Pets = {} }
	for _, reward in rewards do
		if reward.Type == "Currency" and reward.Currency and reward.Amount then
			local added = CurrencyLogic.Add(data, reward.Currency, reward.Amount)
			summary.Currencies[reward.Currency] = (summary.Currencies[reward.Currency] or 0) + added
		elseif reward.Type == "Boost" and reward.BoostId then
			local stacks = reward.Amount or 1
			BoostLogic.Add(data, reward.BoostId, stacks)
			summary.Boosts[reward.BoostId] = (summary.Boosts[reward.BoostId] or 0) + stacks
		elseif reward.Type == "Pet" and reward.PetId then
			local added, _, uid = PetLogic.Add(data, reward.PetId, reward.Variant or "Normal", now, ignoreCapacity)
			if added and uid then
				table.insert(summary.Pets, { Uid = uid, PetId = reward.PetId })
			end
		end
	end
	return true, nil, summary
end

return RewardLogic
