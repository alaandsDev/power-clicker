--!strict
--[[
	WorldConfig
	All five worlds are live. Each has its own Power multiplier, map theme and
	training zones (ZoneConfig); eggs and pets are still Training-only, so a
	player travels back to hatch. A world can still be taken off the menu with
	Enabled = false; the server then refuses to unlock or teleport to it.
]]

local Types = require(script.Parent.Parent.Types)

type WorldData = Types.WorldData

local Worlds: { [string]: WorldData } = {
	Training = {
		Id = "Training",
		DisplayName = "Training",
		Order = 1,
		Multiplier = 1,
		Requirement = { Rebirths = 0, Cost = 0, Currency = "Power" },
		SpawnName = "Training",
		Ambient = "Training", -- AmbientConfig preset
		Eggs = { "BasicEgg", "ForestEgg", "MysticEgg", "TowerEgg", "ColossusEgg" },
		Enabled = true,
	},
	City = {
		Id = "City",
		DisplayName = "City",
		Order = 2,
		Multiplier = 10,
		Requirement = { Rebirths = 5, Cost = 100, Currency = "Gems" },
		SpawnName = "City",
		Ambient = "City", -- AmbientConfig preset
		Eggs = {},
		-- Dormente: a TORRE é a progressão agora (ver docs/PLANO_TORRE.md §C3).
		-- Nada foi apagado — voltar a ligar é trocar este false por true.
		Enabled = false,
	},
	Volcano = {
		Id = "Volcano",
		DisplayName = "Volcano",
		Order = 3,
		Multiplier = 100,
		Requirement = { Rebirths = 12, Cost = 500, Currency = "Gems" },
		SpawnName = "Volcano",
		Ambient = "Volcano", -- AmbientConfig preset
		Eggs = {},
		-- Dormente: a TORRE é a progressão agora (ver docs/PLANO_TORRE.md §C3).
		-- Nada foi apagado — voltar a ligar é trocar este false por true.
		Enabled = false,
	},
	Space = {
		Id = "Space",
		DisplayName = "Space",
		Order = 4,
		Multiplier = 1_000,
		Requirement = { Rebirths = 20, Cost = 2_000, Currency = "Gems" },
		SpawnName = "Space",
		Ambient = "Space", -- AmbientConfig preset
		Eggs = {},
		-- Dormente: a TORRE é a progressão agora (ver docs/PLANO_TORRE.md §C3).
		-- Nada foi apagado — voltar a ligar é trocar este false por true.
		Enabled = false,
	},
	Galaxy = {
		Id = "Galaxy",
		DisplayName = "Galaxy",
		Order = 5,
		Multiplier = 10_000,
		Requirement = { Rebirths = 30, Cost = 6_000, Currency = "Gems" },
		SpawnName = "Galaxy",
		Ambient = "Galaxy", -- AmbientConfig preset
		Eggs = {},
		-- Dormente: a TORRE é a progressão agora (ver docs/PLANO_TORRE.md §C3).
		-- Nada foi apagado — voltar a ligar é trocar este false por true.
		Enabled = false,
	},
}

return {
	DefaultWorld = "Training",
	Worlds = Worlds,
}
