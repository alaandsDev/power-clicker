--!strict
--[[
	CutConfig
	"Cortes": the pads lined up in front of the spawn that sell raw damage per
	click. Each one is bought once, with Power, and the BEST one you own is the
	one that counts — there is nothing to equip and nothing to manage.

	They add to the BASE of PowerFormula (before every multiplier), which is
	what makes them matter early: at the start +5 per click is five times your
	damage, and by the time the multipliers are big they are a rounding error.
	That is on purpose — the cut pads are the first hour of the game.

	Wins gate them, so the win corridor and the click damage pull each other
	forward: break walls to afford the next cut, buy the cut to break the next
	wall.

	Ids are persisted in PlayerData.Cuts — never rename one after launch.
]]

local Shared = script.Parent.Parent
local Types = require(Shared.Types)

type CutData = Types.CutData

local Cuts: { [string]: CutData } = {
	Cut1 = { Id = "Cut1", Order = 1, DisplayName = "Corte 1", Flat = 1, Price = 0, RequiredWins = 0, Color = Color3.fromRGB(198, 203, 219), TrailSeconds = 0, LightRange = 0, Neon = false },
	Cut2 = { Id = "Cut2", Order = 2, DisplayName = "Corte 2", Flat = 2, Price = 250, RequiredWins = 1, Color = Color3.fromRGB(120, 220, 255), TrailSeconds = 0.18, LightRange = 0, Neon = false },
	Cut3 = { Id = "Cut3", Order = 3, DisplayName = "Corte 3", Flat = 5, Price = 5_000, RequiredWins = 5, Color = Color3.fromRGB(70, 210, 110), TrailSeconds = 0.22, LightRange = 8, Neon = false },
	Cut4 = { Id = "Cut4", Order = 4, DisplayName = "Corte 4", Flat = 10, Price = 120_000, RequiredWins = 25, Color = Color3.fromRGB(140, 90, 255), TrailSeconds = 0.26, LightRange = 10, Neon = false },
	Cut5 = { Id = "Cut5", Order = 5, DisplayName = "Corte 5", Flat = 25, Price = 3_000_000, RequiredWins = 100, Color = Color3.fromRGB(255, 130, 50), TrailSeconds = 0.3, LightRange = 12, Neon = true },
	Cut6 = { Id = "Cut6", Order = 6, DisplayName = "Corte 6", Flat = 60, Price = 90_000_000, RequiredWins = 400, Color = Color3.fromRGB(255, 60, 120), TrailSeconds = 0.34, LightRange = 14, Neon = true },
	Cut7 = { Id = "Cut7", Order = 7, DisplayName = "Corte 7", Flat = 150, Price = 4_000_000_000, RequiredWins = 1_500, Color = Color3.fromRGB(255, 220, 60), TrailSeconds = 0.4, LightRange = 18, Neon = true },
	Cut8 = { Id = "Cut8", Order = 8, DisplayName = "Corte 8", Flat = 400, Price = 200_000_000_000, RequiredWins = 6_000, Color = Color3.fromRGB(255, 255, 255), TrailSeconds = 0.5, LightRange = 24, Neon = true },
}

return {
	Cuts = Cuts,
	-- Everyone starts with the first cut: it is the base swing, not a purchase.
	StarterCut = "Cut1",
	Currency = "Power" :: Types.CurrencyId,

	--[[
		The blade every player carries. Its colour, trail and glow come from the
		best cut owned, so what you bought is visible to the whole server
		without a single extra remote.
	]]
	Sword = {
		BladeSize = Vector3.new(0.22, 4.2, 0.9),
		GuardSize = Vector3.new(0.3, 0.3, 1.8),
		GripSize = Vector3.new(0.3, 1.2, 0.3),
		-- Tool.Grip: where the hand holds the handle, and how far the blade is
		-- tipped forward (0 = straight up out of the fist).
		GripOffset = Vector3.new(0, -0.2, 0),
		GripPitch = -20,
		TrailWidth = 0.9,
	},

	--[[
		Os pads ficam no pé da torre (área Tower do LobbyConfig), em grade: é
		onde o jogador compra dano antes de subir. Na fileira longa que eles
		ocupavam antes, atravessavam as áreas de Renascimento e Treino.
	]]
	Layout = {
		Area = "Tower",
		Columns = 4,
		Spacing = Vector2.new(15, 17), -- entre centros: x, z
		PadSize = 13,
		SignHeight = 6,
	},
}
