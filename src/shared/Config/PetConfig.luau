--!strict
--[[
	PetConfig
	Pet power bonus is additive: PetMultiplier = 1 + Σ(equipped Bonus * VariantScale).
	All Icon / ModelName values are placeholders (TODO_ASSET) until art exists.
	Icon: UI image. Set it per pet in the ICONS table below
	("rbxassetid://<id>"); pets without one show text only.

	To add a pet: add an entry to Pets with a unique Id, then reference it from an
	egg in EggConfig (or leave EggId = nil for exclusive/product pets).
	Pet ids are persisted in player data — NEVER rename or delete an id that
	has shipped; set it unobtainable instead.
]]

local Types = require(script.Parent.Parent.Types)

type RarityData = Types.RarityData
type VariantData = Types.VariantData
type PetData = Types.PetData

local Rarities: { [string]: RarityData } = {
	Common = { Id = "Common", DisplayName = "Common", Order = 1, Color = Color3.fromRGB(180, 180, 180), AffectedByLuck = false, Announce = false },
	Uncommon = { Id = "Uncommon", DisplayName = "Uncommon", Order = 2, Color = Color3.fromRGB(90, 200, 90), AffectedByLuck = false, Announce = false },
	Rare = { Id = "Rare", DisplayName = "Rare", Order = 3, Color = Color3.fromRGB(70, 140, 255), AffectedByLuck = true, Announce = false },
	Epic = { Id = "Epic", DisplayName = "Epic", Order = 4, Color = Color3.fromRGB(170, 80, 255), AffectedByLuck = true, Announce = false },
	Legendary = { Id = "Legendary", DisplayName = "Legendary", Order = 5, Color = Color3.fromRGB(255, 190, 40), AffectedByLuck = true, Announce = true },
	Mythic = { Id = "Mythic", DisplayName = "Mythic", Order = 6, Color = Color3.fromRGB(255, 60, 120), AffectedByLuck = true, Announce = true },
}

local Variants: { [string]: VariantData } = {
	Normal = { Id = "Normal", DisplayName = "Normal", MultiplierScale = 1, Enabled = true },
	Golden = { Id = "Golden", DisplayName = "Golden", MultiplierScale = 2, Enabled = false },
	Shiny = { Id = "Shiny", DisplayName = "Shiny", MultiplierScale = 3.5, Enabled = false },
	Rainbow = { Id = "Rainbow", DisplayName = "Rainbow", MultiplierScale = 5, Enabled = false },
}

-- Uploaded portraits live in AssetIds as pet_<Id> (see tools/upload_assets.py).
local AssetIds = require(script.Parent.AssetIds)

local function pet(id: string, name: string, rarity: Types.RarityId, bonus: number, eggId: string?): PetData
	return {
		Id = id,
		DisplayName = name,
		Rarity = rarity,
		Bonus = bonus,
		WorldId = "Training",
		EggId = eggId,
		Icon = AssetIds["pet_" .. id] or "TODO_ASSET",
		ModelName = "TODO_ASSET_" .. id,
		Tradeable = false,
	}
end

local Pets: { [string]: PetData } = {
	-- Basic Egg (Power)
	Dog = pet("Dog", "Dog", "Common", 0.10, "BasicEgg"),
	Cat = pet("Cat", "Cat", "Common", 0.12, "BasicEgg"),
	Bunny = pet("Bunny", "Bunny", "Uncommon", 0.20, "BasicEgg"),
	Fox = pet("Fox", "Fox", "Rare", 0.35, "BasicEgg"),
	Wolf = pet("Wolf", "Wolf", "Epic", 0.60, "BasicEgg"),

	-- Forest Egg (Gems)
	Deer = pet("Deer", "Deer", "Uncommon", 0.30, "ForestEgg"),
	Owl = pet("Owl", "Owl", "Rare", 0.50, "ForestEgg"),
	Bear = pet("Bear", "Bear", "Rare", 0.70, "ForestEgg"),
	Panther = pet("Panther", "Panther", "Epic", 1.20, "ForestEgg"),
	Unicorn = pet("Unicorn", "Unicorn", "Legendary", 3.00, "ForestEgg"),

	-- Mystic Egg (Gems)
	SpiritFox = pet("SpiritFox", "Spirit Fox", "Rare", 1.00, "MysticEgg"),
	Golem = pet("Golem", "Golem", "Epic", 2.00, "MysticEgg"),
	Phoenix = pet("Phoenix", "Phoenix", "Legendary", 5.00, "MysticEgg"),
	Dragon = pet("Dragon", "Dragon", "Legendary", 7.00, "MysticEgg"),
	CelestialDragon = pet("CelestialDragon", "Celestial Dragon", "Mythic", 20.00, "MysticEgg"),

	-- Tower Egg (gemas das primeiras conquistas, estágio 5)
	Gargoyle = pet("Gargoyle", "Gárgula", "Rare", 2.50, "TowerEgg"),
	Knight = pet("Knight", "Cavaleiro de Pedra", "Epic", 4.00, "TowerEgg"),
	Griffin = pet("Griffin", "Grifo", "Epic", 6.00, "TowerEgg"),
	Titan = pet("Titan", "Titã de Ouro", "Legendary", 12.00, "TowerEgg"),
	Eclipse = pet("Eclipse", "Dragão Eclipse", "Mythic", 35.00, "TowerEgg"),

	-- Colossus Egg (estágio 10: o fim da primeira jornada)
	Guardian = pet("Guardian", "Guardião do Colosso", "Epic", 15.00, "ColossusEgg"),
	Seraph = pet("Seraph", "Serafim", "Legendary", 30.00, "ColossusEgg"),
	Nova = pet("Nova", "Nova", "Legendary", 45.00, "ColossusEgg"),
	Colossus = pet("Colossus", "Colosso Menor", "Mythic", 90.00, "ColossusEgg"),

	-- Exclusive (not hatchable)
	StarterDragonling = pet("StarterDragonling", "Starter Dragonling", "Epic", 1.50, nil),
	VipCrownCat = pet("VipCrownCat", "VIP Crown Cat", "Legendary", 2.50, nil),
}

return {
	Rarities = Rarities,
	Variants = Variants,
	Pets = Pets,

	BaseEquipSlots = 3,
	BaseInventorySlots = 50,
	-- Absolute safety cap regardless of upgrades/passes.
	MaxEquipSlots = 12,
	MaxInventorySlots = 500,
}
