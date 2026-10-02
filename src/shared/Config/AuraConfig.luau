--!strict
--[[
	AuraConfig
	Auras you BUY with Gems and equip (one at a time). Unlike the rebirth ring
	in CosmeticConfig (pure status), an aura changes play:

		WalkSpeedBonus  — added to the character's base walk speed (server side)
		PowerMultiplier — the "Aura" layer of PowerFormula

	Gems are the rebirth currency, so auras are a long-term sink that never
	competes with the click economy. Prices grow much faster than the bonuses
	on purpose: the last aura is a goal, not a step.

	Ids are persisted in PlayerData.Auras — never rename one after launch.
]]

local Shared = script.Parent.Parent
local Types = require(Shared.Types)

type AuraData = Types.AuraData

local Auras: { [string]: AuraData } = {
	None = {
		Id = "None",
		DisplayName = "Sem aura",
		Order = 1,
		Rarity = "Common",
		Price = 0,
		RequiredWins = 0,
		WalkSpeedBonus = 0,
		PowerMultiplier = 1,
		Color = Color3.fromRGB(200, 205, 225),
		RingSize = 0,
		LightRange = 0,
		Outline = false,
	},
	Spark = {
		Id = "Spark",
		DisplayName = "Faísca",
		Order = 2,
		Rarity = "Common",
		Price = 40,
		RequiredWins = 0,
		WalkSpeedBonus = 2,
		PowerMultiplier = 1.05,
		Color = Color3.fromRGB(120, 220, 255),
		RingSize = 6,
		LightRange = 10,
		Outline = false,
	},
	Ember = {
		Id = "Ember",
		DisplayName = "Brasa",
		Order = 3,
		Rarity = "Uncommon",
		Price = 250,
		RequiredWins = 5,
		WalkSpeedBonus = 4,
		PowerMultiplier = 1.15,
		Color = Color3.fromRGB(255, 130, 50),
		RingSize = 7,
		LightRange = 12,
		Outline = false,
	},
	Storm = {
		Id = "Storm",
		DisplayName = "Tempestade",
		Order = 4,
		Rarity = "Rare",
		Price = 1_200,
		RequiredWins = 25,
		WalkSpeedBonus = 6,
		PowerMultiplier = 1.4,
		Color = Color3.fromRGB(140, 90, 255),
		RingSize = 8,
		LightRange = 14,
		Outline = true,
	},
	Stellar = {
		Id = "Stellar",
		DisplayName = "Estelar",
		Order = 5,
		Rarity = "Epic",
		Price = 6_000,
		RequiredWins = 150,
		WalkSpeedBonus = 8,
		PowerMultiplier = 1.9,
		Color = Color3.fromRGB(255, 196, 45),
		RingSize = 9,
		LightRange = 18,
		Outline = true,
	},
	Singularity = {
		Id = "Singularity",
		DisplayName = "Singularidade",
		Order = 6,
		Rarity = "Legendary",
		Price = 30_000,
		RequiredWins = 800,
		WalkSpeedBonus = 12,
		PowerMultiplier = 3,
		Color = Color3.fromRGB(255, 80, 160),
		RingSize = 10,
		LightRange = 22,
		Outline = true,
	},
}

return {
	Auras = Auras,
	Currency = "Gems" :: Types.CurrencyId,
	-- Everyone starts with (and can always go back to) this one.
	DefaultAura = "None",
	-- Roblox default is 16; the cap keeps a fast aura from breaking the
	-- islands' jump distances.
	BaseWalkSpeed = 16,
	MaxWalkSpeed = 34,
}
