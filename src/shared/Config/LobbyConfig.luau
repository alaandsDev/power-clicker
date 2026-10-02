--!strict
--[[
	LobbyConfig
	Onde cada coisa fica na ilha inicial. Antes disso, as posições viviam
	espalhadas como constantes dentro do WorldBuilder (EGG_Z, ALTAR_X,
	SCOREBOARD_X, offsets de quiosque...), o que deixava o lobby parecer um
	monte de objetos soltos — exatamente a reclamação do pedido.

	Agora o lobby é um conjunto de ÁREAS. Cada área tem um piso redondo, um
	letreiro alto com ícone e nome, e as coisas dela ficam dentro do seu raio.
	O jogador nasce na praça e consegue ler o mapa de onde está.

	Tudo é relativo à origem do mundo; +Z é o lado do nascimento, +X é o lado
	da torre.
]]

local Shared = script.Parent.Parent

export type Area = {
	Id: string,
	NameKey: string, -- chave de localização do letreiro
	Icon: string,
	Offset: Vector3, -- centro da área, relativo à origem
	Radius: number,
	Color: Color3,
	SignHeight: number,
}

export type Station = {
	Panel: string, -- painel que o prompt abre (UIController.RegisterPanel)
	TextKey: string,
	NameKey: string,
	Icon: string,
	Area: string, -- em qual área o quiosque fica
	Local: Vector3, -- deslocamento dentro da área
	Color: Color3,
}

local Areas: { [string]: Area } = {
	Spawn = {
		Id = "Spawn",
		NameKey = "area.spawn",
		Icon = "🏠",
		Offset = Vector3.new(0, 0, 92),
		Radius = 26,
		Color = Color3.fromRGB(255, 226, 120),
		SignHeight = 18,
	},
	Eggs = {
		Id = "Eggs",
		NameKey = "area.eggs",
		Icon = "🥚",
		Offset = Vector3.new(0, 0, -96),
		Radius = 44,
		Color = Color3.fromRGB(255, 196, 45),
		SignHeight = 26,
	},
	Pets = {
		Id = "Pets",
		NameKey = "area.pets",
		Icon = "🐾",
		Offset = Vector3.new(-80, 0, -46),
		Radius = 26,
		Color = Color3.fromRGB(80, 220, 255),
		SignHeight = 22,
	},
	Shop = {
		Id = "Shop",
		NameKey = "area.shop",
		Icon = "🛒",
		Offset = Vector3.new(80, 0, -46),
		Radius = 30,
		Color = Color3.fromRGB(255, 150, 80),
		SignHeight = 22,
	},
	Rebirth = {
		Id = "Rebirth",
		NameKey = "area.rebirth",
		Icon = "🔁",
		Offset = Vector3.new(-80, 0, 46),
		Radius = 26,
		Color = Color3.fromRGB(170, 120, 255),
		SignHeight = 22,
	},
	Training = {
		Id = "Training",
		NameKey = "area.training",
		Icon = "💪",
		-- Fica no caminho entre a praça e a torre, de frente para as duas: o
		-- jogador passa por ela indo bater na barreira. A Fase D põe os
		-- equipamentos dentro.
		Offset = Vector3.new(80, 0, 46),
		Radius = 30,
		Color = Color3.fromRGB(104, 230, 140),
		SignHeight = 24,
	},
	Tower = {
		Id = "Tower",
		NameKey = "area.tower",
		Icon = "⚔️",
		-- Boca da torre: o caminho de pedra sai da praça e termina aqui.
		Offset = Vector3.new(130, 0, 0),
		Radius = 34,
		Color = Color3.fromRGB(255, 120, 230),
		SignHeight = 30,
	},
}

-- Quiosques: cada um pertence a uma área e abre um painel.
local Stations: { Station } = {
	{ Panel = "Upgrades", TextKey = "world.prompt.upgrades", NameKey = "menu.upgrades", Icon = "⬆️", Area = "Shop", Local = Vector3.new(-18, 0, -8), Color = Color3.fromRGB(70, 210, 110) },
	{ Panel = "Shop", TextKey = "world.prompt.shop", NameKey = "menu.shop", Icon = "🛒", Area = "Shop", Local = Vector3.new(18, 0, 8), Color = Color3.fromRGB(255, 196, 45) },
	{ Panel = "Pets", TextKey = "world.prompt.pets", NameKey = "menu.pets", Icon = "🐾", Area = "Pets", Local = Vector3.new(0, 0, 0), Color = Color3.fromRGB(80, 220, 255) },
	{ Panel = "Quests", TextKey = "world.prompt.quests", NameKey = "menu.quests", Icon = "📜", Area = "Spawn", Local = Vector3.new(-34, 0, 10), Color = Color3.fromRGB(140, 90, 255) },
	{ Panel = "Rewards", TextKey = "world.prompt.rewards", NameKey = "menu.rewards", Icon = "🎁", Area = "Spawn", Local = Vector3.new(34, 0, 10), Color = Color3.fromRGB(255, 150, 80) },
}

return {
	Areas = Areas,
	Stations = Stations,

	-- Caminho de pedra da praça até a boca da torre.
	Path = {
		Width = 24,
		TileLength = 20,
	},

	-- Quadro de recordes, de frente para a praça.
	Scoreboard = Vector3.new(44, 0, 74),

	-- Enfeite: ilhotas flutuando em volta, nuvens e a cachoeira na borda.
	Decoration = {
		FloatingIslands = 5,
		IslandMinRadius = 190,
		IslandMaxRadius = 290,
		IslandHeight = 70, -- altura média acima do chão
		Clouds = 14,
		CloudHeight = 150,
		Waterfall = {
			-- Borda sul da ilha: a água cai e desaparece no vazio.
			Offset = Vector3.new(-40, 0, 128),
			Width = 34,
			Drop = 140,
		},
	},
}
