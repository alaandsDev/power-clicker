--!strict
--[[
	ZoneConfig
	Training zones: floating islands, linked by bridges, going north from each
	world's plaza. Standing in a zone multiplies Power per click (layer "Zone")
	and unlocks that zone's targets (punching bags / crystals you break for a
	Power reward).

	Entry is gated by Requirement (TotalPowerEarned and/or Rebirths, both
	checked on the SERVER by ZoneService, which sends trespassers back).

	Positions are OFFSETS from the world origin, in studs, so every world uses
	the same layout. The plaza itself is the implicit zone 0 (multiplier 1);
	it is not listed here.

	Training has four zones (the early game); every other world has two, whose
	requirements are sized for the stage that world belongs to. A target always
	pays LESS than the Power needed to break it (checked by ConfigValidator and
	by the ZoneRules tests), so a zone speeds you up without printing Power.
]]

local Types = require(script.Parent.Parent.Types)

type ZoneData = Types.ZoneData

-- Zones sit in a line going north (-Z) from the island, one island each.
-- Spacing must clear the two radii it sits between (they grow with the zone
-- order), or the last islands end up touching: tools/check_world_layout.py.
local FIRST_Z = -300
local SPACING_Z = -250

local function offset(index: number): Vector3
	return Vector3.new(0, 0, FIRST_Z + SPACING_Z * (index - 1))
end

local Zones: { [string]: ZoneData } = {
	Meadow = {
		Id = "Meadow",
		WorldId = "Training",
		Order = 1,
		DisplayName = "Campo de Treino",
		Offset = offset(1),
		Radius = 78,
		Multiplier = 3,
		Requirement = { Power = 5_000, Rebirths = 0 },
		Color = Color3.fromRGB(120, 200, 110),
		Target = { Kind = "Dummy", Count = 6, Hp = 400, Reward = 350, RespawnSeconds = 6 },
	},
	Quarry = {
		Id = "Quarry",
		WorldId = "Training",
		Order = 2,
		DisplayName = "Pedreira",
		Offset = offset(2),
		Radius = 84,
		Multiplier = 8,
		Requirement = { Power = 1_500_000, Rebirths = 0 },
		Color = Color3.fromRGB(170, 150, 120),
		Target = { Kind = "Rock", Count = 7, Hp = 12_000, Reward = 9_000, RespawnSeconds = 8 },
	},
	Storm = {
		Id = "Storm",
		WorldId = "Training",
		Order = 3,
		DisplayName = "Pico da Tempestade",
		Offset = offset(3),
		Radius = 90,
		Multiplier = 20,
		Requirement = { Power = 400_000_000, Rebirths = 3 },
		Color = Color3.fromRGB(110, 190, 255),
		Target = { Kind = "Crystal", Count = 8, Hp = 900_000, Reward = 600_000, RespawnSeconds = 10 },
	},
	Void = {
		Id = "Void",
		WorldId = "Training",
		Order = 4,
		DisplayName = "Fenda do Vazio",
		Offset = offset(4),
		Radius = 96,
		Multiplier = 50,
		Requirement = { Power = 120_000_000_000, Rebirths = 8 },
		Color = Color3.fromRGB(190, 120, 255),
		Target = { Kind = "Orb", Count = 8, Hp = 120_000_000, Reward = 70_000_000, RespawnSeconds = 12 },
	},

	-- ── City (world x10) ────────────────────────────────────────────────────
	Rooftops = {
		Id = "Rooftops",
		WorldId = "City",
		Order = 1,
		DisplayName = "Telhados",
		Offset = offset(1),
		Radius = 82,
		Multiplier = 4,
		Requirement = { Power = 2_000_000_000, Rebirths = 5 },
		Color = Color3.fromRGB(120, 170, 220),
		Target = { Kind = "Rock", Count = 7, Hp = 2_000_000, Reward = 1_400_000, RespawnSeconds = 8 },
	},
	Downtown = {
		Id = "Downtown",
		WorldId = "City",
		Order = 2,
		DisplayName = "Centro",
		Offset = offset(2),
		Radius = 88,
		Multiplier = 12,
		Requirement = { Power = 50_000_000_000, Rebirths = 7 },
		Color = Color3.fromRGB(80, 220, 255),
		Target = { Kind = "Crystal", Count = 8, Hp = 50_000_000, Reward = 35_000_000, RespawnSeconds = 9 },
	},

	-- ── Volcano (world x100) ────────────────────────────────────────────────
	Crater = {
		Id = "Crater",
		WorldId = "Volcano",
		Order = 1,
		DisplayName = "Cratera",
		Offset = offset(1),
		Radius = 86,
		Multiplier = 6,
		Requirement = { Power = 2_000_000_000_000, Rebirths = 12 },
		Color = Color3.fromRGB(230, 120, 60),
		Target = { Kind = "Rock", Count = 7, Hp = 2_000_000_000, Reward = 1_400_000_000, RespawnSeconds = 9 },
	},
	LavaCore = {
		Id = "LavaCore",
		WorldId = "Volcano",
		Order = 2,
		DisplayName = "Núcleo de Lava",
		Offset = offset(2),
		Radius = 92,
		Multiplier = 18,
		Requirement = { Power = 60_000_000_000_000, Rebirths = 15 },
		Color = Color3.fromRGB(255, 80, 40),
		Target = { Kind = "Orb", Count = 8, Hp = 60_000_000_000, Reward = 42_000_000_000, RespawnSeconds = 10 },
	},

	-- ── Space (world x1000) ─────────────────────────────────────────────────
	Orbit = {
		Id = "Orbit",
		WorldId = "Space",
		Order = 1,
		DisplayName = "Órbita",
		Offset = offset(1),
		Radius = 88,
		Multiplier = 8,
		Requirement = { Power = 1e15, Rebirths = 20 },
		Color = Color3.fromRGB(140, 200, 255),
		Target = { Kind = "Crystal", Count = 8, Hp = 1e12, Reward = 7e11, RespawnSeconds = 10 },
	},
	Nebula = {
		Id = "Nebula",
		WorldId = "Space",
		Order = 2,
		DisplayName = "Nebulosa",
		Offset = offset(2),
		Radius = 94,
		Multiplier = 25,
		Requirement = { Power = 4e16, Rebirths = 24 },
		Color = Color3.fromRGB(180, 140, 255),
		Target = { Kind = "Orb", Count = 8, Hp = 4e13, Reward = 2.8e13, RespawnSeconds = 11 },
	},

	-- ── Galaxy (world x10000) ───────────────────────────────────────────────
	StarForge = {
		Id = "StarForge",
		WorldId = "Galaxy",
		Order = 1,
		DisplayName = "Forja Estelar",
		Offset = offset(1),
		Radius = 92,
		Multiplier = 10,
		Requirement = { Power = 2e18, Rebirths = 30 },
		Color = Color3.fromRGB(255, 190, 120),
		Target = { Kind = "Crystal", Count = 8, Hp = 2e15, Reward = 1.4e15, RespawnSeconds = 11 },
	},
	EventHorizon = {
		Id = "EventHorizon",
		WorldId = "Galaxy",
		Order = 2,
		DisplayName = "Horizonte de Eventos",
		Offset = offset(2),
		Radius = 98,
		Multiplier = 30,
		Requirement = { Power = 8e19, Rebirths = 33 },
		Color = Color3.fromRGB(230, 120, 255),
		Target = { Kind = "Orb", Count = 8, Hp = 8e16, Reward = 5.6e16, RespawnSeconds = 12 },
	},
}

return {
	--[[
		The training islands (ramp, bridges, floating platforms, monsters) are
		NOT built any more: the win corridor took over as the thing you walk to
		and hit. The zones stay here, dormant and complete, because turning them
		back on is one flag — deleting them would throw away the monsters, the
		layout and the balance work.
		With this false, ZoneService never assigns a zone and TargetService
		finds no targets, so both simply idle.
	]]
	Build = false,


	Zones = Zones,

	-- How close (studs) a player must be to a target for a click to hit it.
	HitRange = 18,
	-- How often the server re-checks which zone each player stands in.
	CheckIntervalSeconds = 0.4,
	-- Vertical tolerance: zones are floating, so a player below the platform
	-- (falling past it) does not count as inside.
	HeightTolerance = 40,
	-- Height of each zone platform above the world origin.
	PlatformHeight = 26,
}
