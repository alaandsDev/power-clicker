--!strict
--[[
	WallConfig
	O CORREDOR: dez estágios em linha reta a leste da praça, todos no mesmo
	nível do chão. Cada estágio é uma área temática que termina numa barreira de
	várias fileiras do mesmo material; o jogador quebra fileira por fileira com
	os cliques, passa, pega a recompensa e segue em frente para a área seguinte.

		área N -> fileira 1..R (cada uma com HP) -> pads de vitória -> área N+1

	Qualquer um pode bater em qualquer estágio: quem tem dano de menos
	simplesmente não passa — e é esse o recado da barreira, "vá ficar mais
	forte e volte". Não existe exigência de vitórias para golpear.

	Pegar um pad manda o jogador de volta à praça, então a corrida é sempre
	"quebra, pega, sai", e nunca termina parado numa sala que se fecha.

	Cada estágio tem identidade visual própria (cor, material, acento) e o tema
	cresce junto com a dificuldade, com transição GRADUAL entre vizinhos: o piso
	e as paredes vão virando o tema seguinte ao longo da área, em vez de trocar
	de uma vez. O estágio 10 é o fim da primeira jornada: área maior, barreira
	colossal e o portal do próximo mundo (que ainda não existe — o portal fica
	visivelmente "em breve", nunca fingindo conteúdo).

	Recompensas:
	- Pads de vitória, pagos a cada vez que a barreira cai.
	- FirstClearGems, pago UMA vez por estágio (PlayerData.Tower.Cleared), que é
	  a torneira de gemas que o jogo não tinha (problema P6 do ECONOMY.md).

	Ids são persistidos em PlayerData.Tower e aparecem nas strings
	(`wall.<Id>.name`) — nunca renomear depois do lançamento. Os valores de
	HP/pads/gemas são provisórios e serão recalibrados na Fase H; o que está
	definido aqui é a ESTRUTURA e a forma da curva.

	A geometria também mora aqui, então a torre pode ser reajustada sem tocar
	em código.
]]

local Shared = script.Parent.Parent
local Types = require(Shared.Types)

export type WallStage = {
	Id: string,
	Order: number,
	DisplayName: string,
	Hp: number, -- per ROW; the bar shows the row you are breaking
	Rows: number, -- rows of the same material to get through
	Pads: { number }, -- wins each pad in the room behind it pays
	FirstClearGems: number, -- paid once, the first time this stage falls for you
	Color: Color3, -- the barrier
	Material: Enum.Material,
	Accent: Color3, -- floor trim, pads and lights of the room
	Neon: boolean, -- the barrier glows (the energy stages)
}

local function stage(
	id: string,
	order: number,
	name: string,
	hp: number,
	rows: number,
	pads: { number },
	gems: number,
	color: Color3,
	material: Enum.Material,
	accent: Color3,
	neon: boolean
): WallStage
	return {
		Id = id,
		Order = order,
		DisplayName = name,
		Hp = hp,
		Rows = rows,
		Pads = pads,
		FirstClearGems = gems,
		Color = color,
		Material = material,
		Accent = accent,
		Neon = neon,
	}
end

--[[
	The ten stages. The HP curve is deliberately smooth (about ×6 to ×8 per
	stage) — the six-stage version jumped ×33 between the fourth and the fifth,
	which the simulation showed as a wall nobody passed in six hours.
]]
local Stages: { WallStage } = {
	stage("Wood", 1, "Madeira", 60, 3, { 1, 2 }, 0, Color3.fromRGB(150, 106, 62), Enum.Material.Wood, Color3.fromRGB(104, 168, 86), false),
	stage("Ruins", 2, "Pedra Reforçada", 450, 4, { 3, 6 }, 5, Color3.fromRGB(135, 138, 148), Enum.Material.Slate, Color3.fromRGB(168, 160, 130), false),
	stage("Ice", 3, "Gelo Eterno", 3_500, 4, { 8, 15 }, 10, Color3.fromRGB(150, 215, 245), Enum.Material.Ice, Color3.fromRGB(120, 180, 230), false),
	stage("Crystal", 4, "Cristal Energizado", 28_000, 4, { 20, 40 }, 20, Color3.fromRGB(120, 220, 255), Enum.Material.Glass, Color3.fromRGB(80, 200, 255), true),
	stage("Gold", 5, "Estrutura Dourada", 220_000, 5, { 50, 100 }, 35, Color3.fromRGB(240, 196, 70), Enum.Material.Metal, Color3.fromRGB(255, 220, 120), false),
	stage("Ancient", 6, "Pedra Antiga", 1_800_000, 5, { 120, 240 }, 60, Color3.fromRGB(126, 118, 96), Enum.Material.Sandstone, Color3.fromRGB(190, 160, 90), true),
	stage("Volcanic", 7, "Rocha Vulcânica", 15_000_000, 5, { 300, 600 }, 100, Color3.fromRGB(74, 48, 44), Enum.Material.Basalt, Color3.fromRGB(255, 120, 40), false),
	stage("Magma", 8, "Magma Cristalizado", 120_000_000, 6, { 800, 1_600 }, 170, Color3.fromRGB(200, 50, 30), Enum.Material.CrackedLava, Color3.fromRGB(255, 90, 40), true),
	stage("Tech", 9, "Barreira Energética", 1_000_000_000, 6, { 2_000, 4_000 }, 280, Color3.fromRGB(90, 120, 200), Enum.Material.DiamondPlate, Color3.fromRGB(120, 230, 255), true),
	stage("Colossus", 10, "Colosso", 9_000_000_000, 8, { 6_000, 12_000 }, 500, Color3.fromRGB(230, 230, 255), Enum.Material.Neon, Color3.fromRGB(255, 120, 230), true),
}

return {
	Stages = Stages,
	-- The tower stands in the starting world: wins are one track for the whole
	-- game, not one per world.
	WorldId = "Training",

	--[[
		CORREDOR RETO (Tower Layout → Linear Progression Corridor).

		Tudo acontece no mesmo nível do chão, numa linha só, indo para +X:

			lobby → [área 1] → barreira 1 → [área 2] → barreira 2 → ... → portal

		Sem escadas, sem andares, sem subir. A área vem primeiro e a barreira
		fecha o fim dela, então o jogador atravessa o ambiente novo e encontra o
		obstáculo daquele tema.

		RoomLength é curto de propósito: o espaço entre barreiras existe para
		mostrar a mudança de ambiente e preparar a próxima, não para caminhada
		vazia.
	]]
	Layout = {
		--[[
			Onde o corredor começa. Tem de ser a borda da ilha (GROUND_RADIUS no
			WorldBuilder): com 170, sobrava um vão de 20 studs entre o fim do
			chão e o começo do corredor — ou seja, um buraco para cair.
		]]
		StartX = 150,
		RoomLength = 110, -- comprimento de cada área, ao longo do corredor
		Width = 86,
		WallHeight = 30, -- a barreira
		RowThickness = 8,
		RowGap = 2,
		FloorThickness = 6,
		SideThickness = 8,
		SideHeight = 42,
		-- Arco que emoldura cada barreira: é o "portão" que marca o checkpoint.
		ArchThickness = 4,
		ArchExtra = 8, -- quanto o arco passa da altura da barreira
		-- Postes de luz na cor do PRÓXIMO tema, para o jogador ver de longe que
		-- há algo diferente adiante.
		LampSpacing = 36,
		LampHeight = 18,
		PadSize = 14,
		PadSpacing = 26,
		ReturnPadInset = 24,
		-- A área final é mais larga e mais longa: tem que parecer um fim.
		FinalScale = 1.6,
	},

	--[[
		Rendimento decrescente (correção de P1 no ECONOMY.md).

		Antes, o pad pagava o mesmo valor toda vez e a barreira mais baixa era
		farmável para sempre: o jogador ativo juntava 6.492 vitórias em 2 h e
		35.000 em 6 h, enquanto o Corte 8 — meta de fim de jogo — pede 6.000.

		Agora:
		- a PRIMEIRA vez que você passa um estágio paga o valor cheio (e as
		  gemas da conquista);
		- repetir o seu melhor estágio paga `Share`;
		- repetir um estágio abaixo do seu melhor cai `FalloffPerStage` por
		  degrau de distância, com piso em `MinShare`.

		Ou seja: farmar a barreira que você está quebrando AGORA continua
		valendo; voltar para a de madeira com o Colosso liberado, não.
	]]
	Repeat = {
		Share = 0.2,
		FalloffPerStage = 0.45,
		MinShare = 0.02,
	},

	-- How long the room stays open after the LAST row of a stage falls. When it
	-- ends every row of that stage is back at full HP. Short on purpose: the
	-- run back is part of the game.
	OpenSeconds = 14,
	HitRange = 26, -- how close you must be for your clicks to reach a row

	Currency = "Wins" :: Types.CurrencyId,
	GemCurrency = "Gems" :: Types.CurrencyId,
}
