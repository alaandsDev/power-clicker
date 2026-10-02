--!strict
--[[
	RewardText
	Localized, compact description of RewardData lists ("💎 25, 2x Power x1").
	Used by daily rewards, quests, achievements and the shop.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local NumberFormat = require(Shared:WaitForChild("Utils"):WaitForChild("NumberFormat"))
local Config = Shared:WaitForChild("Config")
local PetConfig = require(Config:WaitForChild("PetConfig"))
local BoostConfig = require(Config:WaitForChild("BoostConfig"))
local AssetIds = require(Config:WaitForChild("AssetIds"))
local Text = require(Shared:WaitForChild("Localization"))

local Theme = require(script.Parent.Theme)

type RewardData = Types.RewardData

local RewardText = {}

function RewardText.Describe(reward: RewardData): string
	if reward.Type == "Currency" then
		local icon = if reward.Currency == "Gems" then Theme.Icons.Gems else Theme.Icons.Power
		return icon .. " " .. NumberFormat.Short(reward.Amount or 0)
	elseif reward.Type == "Boost" and reward.BoostId then
		return Text.Get("reward.boost", { name = Text.Get("boost." .. reward.BoostId .. ".name"), count = reward.Amount or 1 })
	elseif reward.Type == "Pet" and reward.PetId then
		local pet = PetConfig.Pets[reward.PetId]
		return Text.Get("reward.pet", { icon = Theme.Icons.Pets, name = if pet then Text.Name("pet", pet) else reward.PetId })
	end
	return "?"
end

--[[
	Visual form of a reward for tiles that show it big (season pass, shop):
		Image  — uploaded picture, "" when there is none
		Emoji  — fallback glyph for Image == ""
		Amount — short tag under the icon ("8", "x2"), "" when it means nothing
		Label  — one short line naming the reward
]]
export type RewardVisual = { Image: string, Emoji: string, Amount: string, Label: string }

function RewardText.Visual(reward: RewardData): RewardVisual
	if reward.Type == "Currency" then
		local isGems = reward.Currency == "Gems"
		return {
			Image = if isGems then AssetIds.icon_gems or "" else AssetIds.icon_power or "",
			Emoji = if isGems then Theme.Icons.Gems else Theme.Icons.Power,
			Amount = NumberFormat.Short(reward.Amount or 0),
			Label = Text.Get(if isGems then "currency.Gems" else "currency.Power"),
		}
	elseif reward.Type == "Boost" and reward.BoostId then
		local boost = BoostConfig.Boosts[reward.BoostId]
		-- Power boosts borrow the bolt; luck boosts borrow the egg (that is what luck is for).
		local isLuck = boost ~= nil and boost.Category == "Luck"
		-- "15 min" says more than "x1": a stack is a chunk of boost time.
		local minutes = if boost then math.max(math.floor(boost.DurationSeconds * (reward.Amount or 1) / 60), 1) else 0
		return {
			Image = if isLuck then AssetIds.icon_eggs or "" else AssetIds.icon_power or "",
			Emoji = if isLuck then Theme.Icons.Eggs else Theme.Icons.Power,
			Amount = if minutes > 0 then Text.Get("reward.minutes", { minutes = minutes }) else "",
			Label = Text.Get("boost." .. reward.BoostId .. ".name"),
		}
	elseif reward.Type == "Pet" and reward.PetId then
		local pet = PetConfig.Pets[reward.PetId]
		return {
			Image = AssetIds["pet_" .. reward.PetId] or "",
			Emoji = Theme.Icons.Pets,
			Amount = "",
			Label = if pet then Text.Name("pet", pet) else reward.PetId,
		}
	end
	return { Image = "", Emoji = "?", Amount = "", Label = "?" }
end

function RewardText.List(rewards: { RewardData }): string
	local parts = {}
	for _, reward in rewards do
		table.insert(parts, RewardText.Describe(reward))
	end
	return table.concat(parts, ", ")
end

return RewardText
