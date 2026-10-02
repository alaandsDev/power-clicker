--!strict
--[[
	RuneConfig
	Runes drop from world bosses and are the only reward that keeps its value
	across rebirths: they are equipped in a few slots and multiply Power (the
	"Rune" layer of PowerFormula).

	One rune per world per rarity (Comum / Incomum / Lendária / Mítica), so the
	rune you get tells you where you beat the boss. Later worlds give stronger
	runes of the same rarity (WorldScale), which is what makes travelling worth
	it after the multiplier itself stopped impressing.

		RuneId = <WorldId> .. <Rarity>   e.g. "VolcanoLegendary"

	Ids are persisted in PlayerData.Runes — never rename one after launch.

	Drops are rolled SERVER SIDE only (RuneService, from BossService.Defeated),
	weighted by the rarity weights below; a player who did more damage to the
	boss gets a better roll (ShareBonus), never a guaranteed one.
]]

local Shared = script.Parent.Parent
local Types = require(Shared.Types)
local WorldConfig = require(Shared.Config.WorldConfig)

type RuneData = Types.RuneData

-- Rarity ladder used by runes (a subset of the pet rarities, same ids).
local Tiers: { { Rarity: Types.RarityId, Bonus: number, Weight: number } } = {
	{ Rarity = "Common", Bonus = 0.03, Weight = 62 },
	{ Rarity = "Uncommon", Bonus = 0.08, Weight = 28 },
	{ Rarity = "Legendary", Bonus = 0.25, Weight = 8 },
	{ Rarity = "Mythic", Bonus = 0.6, Weight = 2 },
}

-- How strong a rune of a given world is, relative to the ladder above.
local WorldScale: { [string]: number } = {
	Training = 1,
	City = 1.15,
	Volcano = 1.35,
	Space = 1.6,
	Galaxy = 2,
}

local Runes: { [string]: RuneData } = {}

for _, world in WorldConfig.Worlds do
	local scale = WorldScale[world.Id] or 1
	for order, tier in Tiers do
		local id = world.Id .. tier.Rarity
		Runes[id] = {
			Id = id,
			DisplayName = world.DisplayName .. " " .. tier.Rarity,
			WorldId = world.Id,
			Rarity = tier.Rarity,
			Order = world.Order * 10 + order,
			-- The bonus scales with the world; the rarity sets its size.
			PowerMultiplier = 1 + tier.Bonus * scale,
			Weight = tier.Weight,
		}
	end
end

return {
	Runes = Runes,
	Tiers = Tiers,
	WorldScale = WorldScale,

	-- Equipped runes multiply together. More slots would make the last worlds
	-- trivial; three is enough for a real choice.
	Slots = 3,
	-- The same rune can fill more than one slot, but only as many times as the
	-- player actually owns it.
	MaxOwnedPerRune = 999,

	Drop = {
		-- Damage share needed to be in the draw at all (5% of the boss).
		MinShare = 0.05,
		-- Chance of a rune at MinShare; a full-share player gets MaxChance.
		MinChance = 0.35,
		MaxChance = 1,
		-- Rare tiers get their weight multiplied by (1 + share × ShareBonus).
		ShareBonus = 1.5,
	},
}
