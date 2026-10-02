--!strict
--[[
	EggConfig
	Drops use relative Weights (they do not need to sum to 100). The chance of a
	drop is Weight / Σ Weights, after luck is applied server-side.

	Luck: for rarities with AffectedByLuck = true, Weight is multiplied by the
	player's luck multiplier, capped at MaxLuckMultiplier. RNG runs ONLY on the
	server (EggService, Phase 3).
]]

local Types = require(script.Parent.Parent.Types)
-- Uploaded egg images live in AssetIds as egg_<Id> (see tools/upload_assets.py).
local AssetIds = require(script.Parent.AssetIds)

type EggData = Types.EggData

local Eggs: { [string]: EggData } = {
	BasicEgg = {
		Id = "BasicEgg",
		DisplayName = "Basic Egg",
		WorldId = "Training",
		Currency = "Power",
		Price = 2_000,
		Drops = {
			{ PetId = "Dog", Weight = 50 },
			{ PetId = "Cat", Weight = 30 },
			{ PetId = "Bunny", Weight = 14 },
			{ PetId = "Fox", Weight = 5 },
			{ PetId = "Wolf", Weight = 1 },
		},
		Icon = AssetIds.egg_BasicEgg or "TODO_ASSET",
		ModelName = "TODO_ASSET_BasicEgg",
		Enabled = true,
	},
	ForestEgg = {
		Id = "ForestEgg",
		DisplayName = "Forest Egg",
		WorldId = "Training",
		Currency = "Gems",
		Price = 25,
		Drops = {
			{ PetId = "Deer", Weight = 45 },
			{ PetId = "Owl", Weight = 30 },
			{ PetId = "Bear", Weight = 18 },
			{ PetId = "Panther", Weight = 6.5 },
			{ PetId = "Unicorn", Weight = 0.5 },
		},
		Icon = AssetIds.egg_ForestEgg or "TODO_ASSET",
		ModelName = "TODO_ASSET_ForestEgg",
		Enabled = true,
	},
	MysticEgg = {
		Id = "MysticEgg",
		DisplayName = "Mystic Egg",
		WorldId = "Training",
		Currency = "Gems",
		Price = 150,
		Drops = {
			{ PetId = "SpiritFox", Weight = 50 },
			{ PetId = "Golem", Weight = 35 },
			{ PetId = "Phoenix", Weight = 12 },
			{ PetId = "Dragon", Weight = 2.9 },
			{ PetId = "CelestialDragon", Weight = 0.1 },
		},
		Icon = AssetIds.egg_MysticEgg or "TODO_ASSET",
		ModelName = "TODO_ASSET_MysticEgg",
		Enabled = true,
	},
	TowerEgg = {
		Id = "TowerEgg",
		DisplayName = "Ovo do Caminho", -- reserva; o nome real vem de egg.TowerEgg.name
		WorldId = "Training",
		-- Abre depois da Estrutura Dourada: as gemas das primeiras conquistas
		-- são exatamente o que paga este ovo.
		RequiredStage = "Gold",
		Currency = "Gems",
		Price = 400,
		Drops = {
			{ PetId = "Gargoyle", Weight = 46 },
			{ PetId = "Knight", Weight = 30 },
			{ PetId = "Griffin", Weight = 17 },
			{ PetId = "Titan", Weight = 6.5 },
			{ PetId = "Eclipse", Weight = 0.5 },
		},
		Icon = AssetIds.egg_TowerEgg or "TODO_ASSET",
		ModelName = "TODO_ASSET_TowerEgg",
		Enabled = true,
	},

	ColossusEgg = {
		Id = "ColossusEgg",
		DisplayName = "Ovo do Colosso",
		WorldId = "Training",
		RequiredStage = "Colossus",
		Currency = "Gems",
		Price = 2_500,
		Drops = {
			{ PetId = "Guardian", Weight = 55 },
			{ PetId = "Seraph", Weight = 29 },
			{ PetId = "Nova", Weight = 15 },
			{ PetId = "Colossus", Weight = 1 },
		},
		Icon = AssetIds.egg_ColossusEgg or "TODO_ASSET",
		ModelName = "TODO_ASSET_ColossusEgg",
		Enabled = true,
	},

}

return {
	Eggs = Eggs,
	MaxLuckMultiplier = 5,
	-- Minimum seconds between hatches per player (server-enforced).
	HatchCooldownSeconds = 0.75,
}
