--!strict
--[[
	UpgradeConfig
	Cost(level) = BaseCost * CostGrowth ^ level   (level = current level, 0-based)

	Temporary upgrades are bought with Power and reset on Rebirth.
	Permanent upgrades are bought with Gems and are never reset.
]]

local Types = require(script.Parent.Parent.Types)

type UpgradeData = Types.UpgradeData

local Temporary: { [string]: UpgradeData } = {
	ClickStrength = {
		Id = "ClickStrength",
		DisplayName = "Click Strength",
		Description = "+1 base Power per click.",
		Currency = "Power",
		BaseCost = 20,
		CostGrowth = 1.2,
		MaxLevel = 250,
		EffectType = "ClickPowerFlat",
		EffectPerLevel = 1,
		Order = 1,
	},
	PowerBoost = {
		Id = "PowerBoost",
		DisplayName = "Power Boost",
		Description = "+25% Power per click.",
		Currency = "Power",
		BaseCost = 1500,
		CostGrowth = 1.9,
		MaxLevel = 50,
		EffectType = "PowerMultiplier",
		EffectPerLevel = 0.25,
		Order = 2,
	},
}

local Permanent: { [string]: UpgradeData } = {
	GemPower = {
		Id = "GemPower",
		DisplayName = "Eternal Power",
		Description = "+10% Power permanently.",
		Currency = "Gems",
		BaseCost = 15,
		CostGrowth = 1.35,
		MaxLevel = 50,
		EffectType = "PowerMultiplier",
		EffectPerLevel = 0.1,
		Order = 1,
	},
	PetSlots = {
		Id = "PetSlots",
		DisplayName = "Pet Slots",
		Description = "+1 equipped pet.",
		Currency = "Gems",
		BaseCost = 100,
		CostGrowth = 3,
		MaxLevel = 3,
		EffectType = "EquipSlots",
		EffectPerLevel = 1,
		Order = 2,
	},
	Luck = {
		Id = "Luck",
		DisplayName = "Lucky Charm",
		Description = "+5% egg luck.",
		Currency = "Gems",
		BaseCost = 40,
		CostGrowth = 1.4,
		MaxLevel = 20,
		EffectType = "LuckMultiplier",
		EffectPerLevel = 0.05,
		Order = 3,
	},
	Storage = {
		Id = "Storage",
		DisplayName = "Pet Storage",
		Description = "+25 pet inventory slots.",
		Currency = "Gems",
		BaseCost = 50,
		CostGrowth = 2,
		MaxLevel = 8,
		EffectType = "InventorySlots",
		EffectPerLevel = 25,
		Order = 4,
	},
}

return {
	Temporary = Temporary,
	Permanent = Permanent,

	-- Buy buttons: how many levels at once. 0 means "as many as affordable",
	-- and MaxBulk caps what a client may ask for in one request.
	BulkOptions = { 1, 10, 0 },
	MaxBulk = 100,
}
