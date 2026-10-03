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
	Color: Color3, -- cor de DETALHE (estandarte, friso, cristal), não do piso
	SignHeight: number,
	--[[
		Redesign do lobby: as áreas deixaram de ser discos saturados com placa
		gigante. A identidade vem de detalhe, material e arquitetura:
		- Label: "Name" (estandarte pequeno com ícone + nome), "Icon" (só o
		  ícone: a estrutura já diz o que é — Treino, Loja) ou "None".
		- Floor: "Stone" (disco de pedra clara), "Square" (praça retangular de
		  cantos arredondados), "Deck" (deck de madeira), "MatSquare" (piso
		  de academia retangular), "Mat" (disco de academia), "Forecourt"
		  (adro escuro diante do portão) ou "None". Só Ovos e Renascer ficam
		  em disco: a mistura evita o "monte de círculos na grama".
		- FloorSize: largura x profundidade dos pisos retangulares.
	]]
	Label: string,
	Floor: string,
	FloorSize: Vector2?,
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
		Label = "None",
		Floor = "Square",
		FloorSize = Vector2.new(76, 26),
	},
	Eggs = {
		Id = "Eggs",
		NameKey = "area.eggs",
		Icon = "🥚",
		Offset = Vector3.new(0, 0, -96),
		Radius = 44,
		Color = Color3.fromRGB(255, 196, 45),
		SignHeight = 26,
		Label = "Name",
		Floor = "Stone",
	},
	Pets = {
		Id = "Pets",
		NameKey = "area.pets",
		Icon = "🐾",
		Offset = Vector3.new(-80, 0, -46),
		Radius = 26,
		Color = Color3.fromRGB(80, 220, 255),
		SignHeight = 22,
		Label = "Name",
		Floor = "Deck",
		FloorSize = Vector2.new(44, 34),
	},
	Shop = {
		Id = "Shop",
		NameKey = "area.shop",
		Icon = "🛒",
		Offset = Vector3.new(80, 0, -46),
		Radius = 30,
		Color = Color3.fromRGB(255, 150, 80),
		SignHeight = 22,
		Label = "Icon",
		Floor = "Square",
		FloorSize = Vector2.new(50, 38),
	},
	Rebirth = {
		Id = "Rebirth",
		NameKey = "area.rebirth",
		Icon = "🔁",
		Offset = Vector3.new(-80, 0, 46),
		Radius = 26,
		Color = Color3.fromRGB(170, 120, 255),
		SignHeight = 22,
		Label = "Name",
		Floor = "Stone",
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
		Label = "Icon",
		Floor = "MatSquare",
		FloorSize = Vector2.new(54, 46),
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
		Label = "None",
		Floor = "Forecourt",
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

	--[[
		Onde o jogador nasce: NO EIXO da avenida (z = 0), olhando para +X.
		Assim a câmera padrão, que fica atrás do personagem, enquadra a avenida,
		o portão CAMINHO DO PODER e a barreira 1 ao fundo. (Antes o spawn ficava
		na área "Spawn", em diagonal ao portão.) A área "Spawn" continua sendo a
		praça das Missões e Prêmios.
	]]
	SpawnPoint = Vector3.new(-30, 0, 0),

	-- Caminho de pedra da praça até a boca do Caminho do Poder.
	Path = {
		Width = 24,
		TileLength = 20,
		-- Pequenos pilares com cristal dos dois lados do caminho, conduzindo o
		-- olhar até o portão (distância da praça, em X).
		Pylons = { 60, 86 },
		PylonOffsetZ = 15,
	},

	--[[
		PORTÃO DO CAMINHO DO PODER — o marco principal do lobby. Fica na boca do
		corredor (WallConfig.Layout.StartX), com dois pilares que também fecham
		o vão entre o corredor e o paredão da ilha, uma verga com a placa e uma
		espada gigante de energia em cima. NÃO é uma torre nem um portal para
		outro mapa: é a entrada do corredor reto.
	]]
	Gate = {
		PillarWidth = 22, -- pilar quadrado
		PillarHeight = 52,
		PlinthHeight = 6,
		LintelHeight = 14, -- verga mais alta: a placa precisa ser lida da praça
		LintelDepth = 24,
		SwordHeight = 40, -- da empunhadura à ponta, acima da verga
		Energy = Color3.fromRGB(110, 210, 255), -- cor da identidade do Caminho
		Trim = Color3.fromRGB(255, 200, 90),
		Stone = Color3.fromRGB(150, 146, 160),
	},

	--[[
		PAREDÕES. A ilha é fechada por paredões de rocha (não por degraus de
		bloco): segmentos em volta da borda, com altura e profundidade variadas,
		todos mais altos que qualquer pulo. Muito mais barato que os ~800
		blocos da muralha em degraus.
	]]
	Cliffs = {
		Segments = 26,
		MinHeight = 58, -- nenhum trecho fica abaixo disso (pulo do Roblox: ~7,2)
		MaxHeight = 86,
		Depth = 26,
		BackDepth = 30,
	},

	--[[
		Quadro de recordes: na borda OESTE da praça, virado para ela. Antes
		ficava em (44, 74), exatamente na linha de visão de quem nasce olhando
		para o portão do Caminho do Poder.
		ScoreboardYaw gira o quadro inteiro (graus): o cliente desenha na face
		Left da peça, então 180° faz essa face olhar para +X (a praça).
	]]
	Scoreboard = Vector3.new(-62, 0, 0),
	ScoreboardYaw = 180,

	-- Enfeite: ilhotas flutuando em volta, nuvens e a cachoeira na borda.
	Decoration = {
		FloatingIslands = 5,
		IslandMinRadius = 190,
		IslandMaxRadius = 290,
		IslandHeight = 70, -- altura média acima do chão
		Clouds = 14,
		CloudHeight = 150,
		-- Lago com pedras (antes ficava em cima da área de Pets).
		Pond = Vector3.new(-122, 0, 0),
		PondRadius = 16,
	},
}
