--!strict
--[[
	CorridorThemes
	A AMBIENTAÇÃO do Caminho do Poder, por estágio. É a única fonte de verdade
	de como cada região se veste; o resto vem de onde já vinha:

		WallConfig      → ids, ordem, cores da barreira (Color/Accent), fileiras
		CorridorLayout  → onde cada área começa/termina (mesma conta do builder)
		CorridorThemes  → piso, faixa central, paredes, acabamento, silhueta,
		                  transição, slots de landmark e LOD (este arquivo)
		World/PowerPath → constrói a fundação a partir dos três

	As CORES vêm do WallConfig por padrão (cada tema só ajusta o que precisa);
	o que cada tema define aqui é MATERIAL e SILHUETA — a Fase A já não
	diferencia estágio só por cor.

	Fases (B: 1–3, C: 4–6, D: 7–9 e E: Colosso + final) preenchem `Props`,
	`Ambient` e os landmarks de cada tema; a estrutura não muda.
]]

local Shared = script.Parent.Parent
local WallConfig = require(Shared.Config.WallConfig)

export type Surface = { Material: Enum.Material, Color: Color3? }
--[[
	Uma peça de cenário do tema (Fase B em diante). O PowerPathDecor tem o
	builder de cada `Kind`; aqui fica SÓ onde e quanto:
	  At    fração da área (0 = começo, 1 = face da barreira); acima de 1 é
	        a zona de decisão depois da barreira (1 = fim das fileiras,
	        2 = fim do trecho). "Barrier" = moldura da barreira.
	  Side  -1 / 1 (lado do corredor); 0 = os dois.
	  Z     distância do centro (studs) — fora da safe lane.
	  Scale tamanho relativo (1 = padrão do builder).
	  Yaw   giro em graus (peças soltas).
	  Landmark  a peça é o marco do estágio (o check exige ao menos um).
	  Fx    VFX ambiental (preset do PowerPathDecor) nesta peça; poucos, com LOD.
]]
export type Decor = { Kind: string, At: number | string, Side: number?, Z: number?, Scale: number?, Yaw: number?, Landmark: boolean?, Fx: string? }
export type Theme = {
	Floor: Surface, -- piso das laterais (fora da faixa central)
	Lane: Surface, -- a faixa central: o "Caminho" em si
	Wall: Surface, -- paredes laterais
	Trim: Surface, -- bordas da faixa, capitéis, soleiras
	-- Altura da parede em cada terço da área (início, meio, fim) e na zona
	-- de decisão depois da barreira. O ritmo baixo → médio → alto varia por
	-- estágio para a silhueta não ser | | | | do começo ao fim.
	Profile: { number },
	Props: { string }, -- (Fases B–E) peças temáticas
	Ambient: string?, -- (Fases B–E) VFX ambiental permitido
	Decor: { Decor }, -- cenário: landmark + secundários + transição
	PlateShade: number, -- contraste entre placas vizinhas da faixa (1 = liso)
	PlateLength: number?, -- placas da faixa deste tema (padrão: Rules.PlateLength)
}

local CorridorThemes = {}

--[[
	Regras estruturais (valem para todos os estágios).
]]
CorridorThemes.Rules = {
	-- SAFE PLAY LANE: faixa central em que NADA decorativo sólido ou alto
	-- entra (avatar + pets + golpe + Corte + multiplayer). Meia largura.
	SafeLaneHalf = 18,
	-- A faixa central pavimentada (o "Caminho"): meia largura.
	LaneHalf = 9,
	-- Placas da faixa central (comprimento aproximado de cada uma).
	PlateLength = 14,
	-- Pilares nas paredes: quanto entram no corredor e quantos por terço.
	PillarDepth = 3,
	PillarWidth = 4,
	-- Transição: quanto do PRÓXIMO tema entra em cada trecho do estágio.
	-- [terço 1, terço 2, terço 3 (anúncio), zona de decisão (revelação)]
	Blend = { 0, 0, 0.35, 0.7 },
	-- Material do trecho troca para o do próximo tema a partir deste blend.
	MaterialSwitch = 0.5,
	-- LOD para o que for dinâmico (VFX ambiental das Fases B–E): só roda até
	-- esta distância da câmera. Nada estático depende disto.
	AmbientDistance = 180,
	-- Slots de landmark por estágio (um de cada lado, no meio da área).
	LandmarkSlots = 2,
}

local M = Enum.Material
-- Só o que difere do padrão. Padrão: Floor/Wall/Lane/Trim no material da
-- barreira e nas cores derivadas do WallConfig.
local THEMES: { [string]: { [string]: any } } = {
	--[[
		1 FLORESTA — o começo: terra, rocha com musgo, trilha de pedra. Duas
		árvores antigas formam a entrada natural para a barreira de madeira;
		raízes e galhos emolduram a barreira. No fim, pedras talhadas e um
		tambor de coluna anunciam as ruínas.
	]]
	Wood = {
		Floor = { Material = M.Ground, Color = Color3.fromRGB(98, 80, 56) },
		Lane = { Material = M.Cobblestone, Color = Color3.fromRGB(132, 118, 98) },
		Wall = { Material = M.Rock, Color = Color3.fromRGB(92, 74, 56) },
		Trim = { Material = M.Grass, Color = Color3.fromRGB(86, 136, 60) },
		Profile = { 26, 32, 38, 34 },
		PlateShade = 0.9,
		Decor = {
			{ Kind = "FoliageClump", At = 0.1, Side = -1, Z = 38 },
			{ Kind = "Boulder", At = 0.2, Side = 1, Z = 35, Yaw = 20 },
			{ Kind = "FloorRoot", At = 0.26, Side = -1, Z = 26, Yaw = 30 },
			{ Kind = "FallenLog", At = 0.34, Side = -1, Z = 30 },
			{ Kind = "Stump", At = 0.34, Side = 1, Z = 28 },
			-- As duas árvores antigas: a entrada natural (no meio da área, longe
			-- o bastante da barreira para a copa não tapar a câmera).
			{ Kind = "AncientTree", At = 0.46, Side = -1, Z = 33, Scale = 1, Landmark = true },
			{ Kind = "AncientTree", At = 0.54, Side = 1, Z = 33, Scale = 0.86, Landmark = true },
			{ Kind = "FloorRoot", At = 0.6, Side = -1, Z = 24, Yaw = -25 },
			{ Kind = "FoliageClump", At = 0.64, Side = 1, Z = 39 },
			-- Anúncio das ruínas: pedra trabalhada aparecendo no fim da floresta.
			{ Kind = "WorkedStone", At = 0.8, Side = -1, Z = 34, Yaw = 12 },
			{ Kind = "ColumnDrum", At = 0.84, Side = 1, Z = 30 },
			{ Kind = "BarrierRoots", At = "Barrier" },
			{ Kind = "WorkedStone", At = 1.05, Side = 1, Z = 38, Yaw = -8 },
			{ Kind = "ColumnDrum", At = 1.9, Side = -1, Z = 34 },
		},
	},
	--[[
		2 RUÍNAS — uma construção antiga no caminho: placas de pedra, colunas
		(algumas quebradas), o ARCO quebrado e assimétrico, blocos caídos. No
		último terço a pedra esfria: frost nas colunas e nas bordas; depois da
		barreira, crosta de gelo na base das paredes e as primeiras lascas.
	]]
	Ruins = {
		Floor = { Material = M.Slate, Color = Color3.fromRGB(116, 110, 96) },
		Lane = { Material = M.Cobblestone, Color = Color3.fromRGB(150, 146, 136) },
		Wall = { Material = M.Slate, Color = Color3.fromRGB(104, 104, 110) },
		Trim = { Material = M.Concrete, Color = Color3.fromRGB(168, 162, 146) },
		Profile = { 34, 30, 40, 36 },
		PlateShade = 0.82,
		Decor = {
			{ Kind = "RuinColumn", At = 0.12, Side = 1, Z = 36, Scale = 0.7 },
			{ Kind = "Rubble", At = 0.2, Side = -1, Z = 31, Yaw = 25 },
			{ Kind = "BrokenSlab", At = 0.26, Side = 1, Z = 26, Yaw = 8 },
			{ Kind = "RuinColumn", At = 0.32, Side = 1, Z = 36, Scale = 1 },
			{ Kind = "BrokenArch", At = 0.52, Landmark = true },
			{ Kind = "BrokenSlab", At = 0.66, Side = -1, Z = 27, Yaw = -6 },
			-- Pedra → frost.
			{ Kind = "RuinColumn", At = 0.76, Side = -1, Z = 36, Scale = 0.8 },
			{ Kind = "Rubble", At = 0.82, Side = 1, Z = 33, Yaw = 40, Scale = 1.1 },
			{ Kind = "FrostCap", At = 0.82, Side = 1, Z = 33 },
			{ Kind = "FrostPatch", At = 0.88, Side = 1 },
			{ Kind = "FrostPatch", At = 0.94, Side = -1 },
			{ Kind = "RuinGate", At = "Barrier" },
			-- Frost → gelo (zona de decisão, fora da moldura dos pads).
			{ Kind = "IceCrust", At = 1.12, Side = -1 },
			{ Kind = "IceCrust", At = 1.16, Side = 1 },
			{ Kind = "IceShard", At = 1.92, Side = -1, Z = 37 },
			{ Kind = "IceShard", At = 1.96, Side = 1, Z = 36, Scale = 0.8 },
		},
	},
	--[[
		3 GELO ETERNO — o primeiro "uau": portal de gelo na entrada, grandes
		formações de cristais de gelo nas laterais (com cintilação local e
		leve), paredes de pedra sob gelo com neve no topo e pingentes, frost na
		faixa. A barreira fica selada por placas de gelo. Depois dela, um
		indício discreto de cristal energizado (estágio 4).
	]]
	Ice = {
		Floor = { Material = M.Snow, Color = Color3.fromRGB(206, 222, 236) },
		Lane = { Material = M.Ice, Color = Color3.fromRGB(150, 192, 214) },
		Wall = { Material = M.Slate, Color = Color3.fromRGB(96, 110, 126) },
		Trim = { Material = M.Snow, Color = Color3.fromRGB(236, 244, 250) },
		Profile = { 36, 44, 40, 38 },
		PlateShade = 0.94,
		Ambient = "FrostSparkle",
		Decor = {
			{ Kind = "IceGate", At = 0.07, Landmark = true },
			{ Kind = "FrostPatch", At = 0.16, Side = -1 },
			{ Kind = "FrozenPuddle", At = 0.2, Side = -1, Z = 30 },
			{ Kind = "Icicles", At = 0.22, Side = 1 },
			{ Kind = "IceSpire", At = 0.3, Side = 1, Z = 36, Scale = 0.5 },
			{ Kind = "FrozenPuddle", At = 0.36, Side = 1, Z = 27 },
			{ Kind = "FrostPatch", At = 0.4, Side = 1 },
			{ Kind = "IceCrust", At = 0.42, Side = -1 },
			{ Kind = "IceFormation", At = 0.5, Side = -1, Z = 32, Landmark = true },
			{ Kind = "IceFormation", At = 0.6, Side = 1, Z = 32, Scale = 0.85, Landmark = true },
			{ Kind = "Icicles", At = 0.64, Side = -1 },
			{ Kind = "IceSpire", At = 0.74, Side = -1, Z = 36, Scale = 0.6 },
			{ Kind = "IceSpire", At = 0.8, Side = 1, Z = 37, Scale = 0.45, Yaw = 15 },
			{ Kind = "Icicles", At = 0.84, Side = 1 },
			{ Kind = "IceSeal", At = "Barrier" },
			-- Indício do estágio 4 (cristal energizado), discreto.
			{ Kind = "CrystalHint", At = 1.08, Side = -1, Z = 37 },
			{ Kind = "CrystalHint", At = 1.94, Side = 1, Z = 38 },
		},
	},
	--[[
		4 CRISTAL ENERGIZADO — o primeiro estágio com ENERGIA do Caminho. O
		gelo vira mineral: formações de gelo com ponta de cristal na entrada,
		depois prismas angulares (corpo sólido + veio de energia) crescendo da
		rocha escura e das paredes — um "vale de cristais" assimétrico que
		aponta para a barreira, alimentada por dois pilares de cristal. No fim,
		pedestais e cintas de ouro: alguém construiu em volta dessa energia.
	]]
	Crystal = {
		Floor = { Material = M.Slate, Color = Color3.fromRGB(68, 64, 86) },
		Lane = { Material = M.Glass, Color = Color3.fromRGB(116, 110, 146) },
		Wall = { Material = M.Rock, Color = Color3.fromRGB(56, 52, 72) },
		Trim = { Material = M.Glass, Color = Color3.fromRGB(110, 196, 232) },
		Profile = { 38, 46, 42, 40 },
		PlateShade = 0.88,
		Ambient = "CrystalMotes",
		Decor = {
			-- Gelo → cristal.
			{ Kind = "FrostCrystal", At = 0.06, Side = 1, Z = 34 },
			{ Kind = "FrostCrystal", At = 0.14, Side = -1, Z = 36, Scale = 0.8, Yaw = 20 },
			{ Kind = "CrystalVein", At = 0.22, Side = 1, Z = 30, Yaw = 15 },
			{ Kind = "WallCrystal", At = 0.3, Side = -1 },
			-- O vale de cristais (assimétrico: o maior à esquerda).
			{ Kind = "CrystalFormation", At = 0.48, Side = -1, Z = 33, Landmark = true, Fx = "CrystalMotes" },
			{ Kind = "CrystalFormation", At = 0.6, Side = 1, Z = 34, Scale = 0.72, Yaw = 10, Landmark = true },
			{ Kind = "CrystalVein", At = 0.74, Side = -1, Z = 28, Yaw = -10 },
			-- Cristal → arquitetura dourada.
			{ Kind = "GoldBracket", At = 0.8, Side = -1, Z = 35 },
			{ Kind = "GoldBracket", At = 0.86, Side = 1, Z = 37, Scale = 0.8 },
			{ Kind = "CrystalConduit", At = "Barrier" },
			{ Kind = "TempleBlock", At = 1.08, Side = 1, Z = 40 },
		},
	},
	--[[
		5 TEMPLO DOURADO — civilização antiga e PRESERVADA (as Ruínas do 2
		são quebradas; aqui tudo está inteiro e organizado): pedra quente,
		pilastras e nichos na parede, medalhão no piso da faixa, os dois
		PÓRTICOS simétricos com símbolo de ouro e o portão selado do templo.
		O ouro é acabamento (capitéis, frisos, símbolos), nunca a superfície.
		No fim, blocos ancestrais com runas: algo mais antigo vem depois.
	]]
	Gold = {
		Floor = { Material = M.Sandstone, Color = Color3.fromRGB(138, 116, 88) },
		Lane = { Material = M.Marble, Color = Color3.fromRGB(176, 166, 146) },
		Wall = { Material = M.Sandstone, Color = Color3.fromRGB(112, 90, 66) },
		Trim = { Material = M.Metal, Color = Color3.fromRGB(186, 146, 64) },
		Profile = { 40, 36, 46, 42 },
		PlateShade = 0.9,
		PlateLength = 10,
		Decor = {
			{ Kind = "GoldRemnant", At = 0.06, Side = 1, Z = 38 },
			{ Kind = "TemplePilaster", At = 0.26, Side = -1 },
			{ Kind = "TemplePilaster", At = 0.26, Side = 1 },
			{ Kind = "TempleNiche", At = 0.4, Side = -1 },
			{ Kind = "TempleNiche", At = 0.4, Side = 1 },
			{ Kind = "GoldenPortico", At = 0.6, Landmark = true },
			{ Kind = "FloorMedallion", At = 0.6 },
			{ Kind = "TemplePilaster", At = 0.74, Side = -1 },
			{ Kind = "TemplePilaster", At = 0.74, Side = 1 },
			-- Ouro → ancestral: o ouro some, a pedra pesa, surge a runa.
			{ Kind = "AncientBlock", At = 0.82, Side = -1, Z = 38 },
			{ Kind = "AncientBlock", At = 0.92, Side = 1, Z = 41, Scale = 0.8, Yaw = 8 },
			{ Kind = "TempleGate", At = "Barrier" },
			{ Kind = "AncientBlock", At = 1.06, Side = -1, Z = 40, Scale = 0.7, Yaw = -10 },
		},
	},
	--[[
		6 PEDRA ANCESTRAL ENERGIZADA — menos brilho, mais presença: granito
		escuro, placas enormes na faixa, blocos gigantes embutidos nas paredes,
		poucos sulcos rúnicos e três MONÓLITOS irregulares com UMA runa cada.
		A barreira é um selo de pedras com energia vazando. No fim, o primeiro
		calor (fissuras com brasa, pedra escurecida, brasas raras) — sem lava.
	]]
	Ancient = {
		Floor = { Material = M.Slate, Color = Color3.fromRGB(70, 70, 66) },
		Lane = { Material = M.Slate, Color = Color3.fromRGB(104, 102, 94) },
		Wall = { Material = M.Granite, Color = Color3.fromRGB(84, 84, 78) },
		Trim = { Material = M.Slate, Color = Color3.fromRGB(58, 58, 56) },
		Profile = { 42, 48, 44, 42 },
		PlateShade = 0.86,
		PlateLength = 18,
		Decor = {
			{ Kind = "MassiveBlock", At = 0.1, Side = -1 },
			{ Kind = "RuneGroove", At = 0.18, Side = 1, Z = 28, Yaw = 12 },
			{ Kind = "MassiveBlock", At = 0.26, Side = 1, Scale = 1.2 },
			{ Kind = "RunicMonolith", At = 0.4, Side = -1, Z = 34, Yaw = 8, Landmark = true },
			{ Kind = "RunicMonolith", At = 0.54, Side = 1, Z = 35, Scale = 0.8, Yaw = -12, Landmark = true },
			{ Kind = "RunicMonolith", At = 0.64, Side = -1, Z = 37, Scale = 0.6, Yaw = 20 },
			{ Kind = "RuneGroove", At = 0.7, Side = -1, Z = 26, Yaw = -8 },
			{ Kind = "MassiveBlock", At = 0.76, Side = 1, Scale = 0.9 },
			-- Primeiro calor (indício do 7).
			{ Kind = "HeatFissure", At = 0.86, Side = 1, Z = 30, Yaw = 10 },
			{ Kind = "AncientSeal", At = "Barrier" },
			{ Kind = "HeatFissure", At = 1.08, Side = -1, Z = 30, Yaw = -14 },
			{ Kind = "EmberVent", At = 1.9, Side = 1, Z = 42, Fx = "Embers" },
			{ Kind = "HeatFissure", At = 1.92, Side = -1, Z = 32, Yaw = 6 },
		},
	},
	--[[
		7 ROCHA VULCÂNICA — "entrei no endgame": basalto, rocha rachada em
		camadas, fissuras quentes (algumas cruzam a faixa rente ao chão), um
		respiro com fumaça controlada e brasas. Landmark: dois PAREDÕES de
		basalto quebrados e inclinados, com pontas — o jogador fica pequeno.
		A barreira é uma massa de rocha vulcânica. No fim, o primeiro cristal
		vermelho rompendo o basalto. Ainda não é lava: é ROCHA.
	]]
	Volcanic = {
		Floor = { Material = M.Basalt, Color = Color3.fromRGB(48, 40, 38) },
		Lane = { Material = M.Basalt, Color = Color3.fromRGB(78, 68, 64) },
		Wall = { Material = M.Rock, Color = Color3.fromRGB(56, 46, 42) },
		Trim = { Material = M.CrackedLava, Color = Color3.fromRGB(120, 48, 26) },
		Profile = { 44, 38, 50, 46 },
		PlateShade = 0.84,
		PlateLength = 16,
		Decor = {
			-- Ancestral → vulcânico: o calor do fim do 6 continua e cresce.
			{ Kind = "HeatFissure", At = 0.05, Side = -1, Z = 28, Yaw = 12 },
			{ Kind = "LavaCrack", At = 0.14, Side = 1, Z = 14, Yaw = 20 },
			{ Kind = "BasaltColumns", At = 0.3, Side = -1 },
			{ Kind = "VolcanicVent", At = 0.36, Side = 1, Z = 38, Fx = "Smoke" },
			{ Kind = "VolcanicCliff", At = 0.5, Side = -1, Z = 32, Yaw = 6, Landmark = true },
			{ Kind = "VolcanicCliff", At = 0.62, Side = 1, Z = 33, Scale = 0.8, Yaw = -8, Landmark = true },
			{ Kind = "LavaCrack", At = 0.72, Side = -1, Z = 22, Yaw = -10 },
			{ Kind = "EmberVent", At = 0.78, Side = -1, Z = 42, Fx = "Embers" },
			-- Vulcânico → magma: as fissuras crescem e cruzam a faixa.
			{ Kind = "LavaCrack", At = 0.86, Side = 1, Z = 10, Scale = 1.2, Yaw = -18 },
			{ Kind = "VolcanicGate", At = "Barrier" },
			{ Kind = "MagmaShard", At = 1.08, Side = 1, Z = 38 },
		},
	},
	--[[
		8 MAGMA CRISTALIZADO — a energia térmica saiu do controle: rocha NEGRA,
		CRISTAIS VERMELHOS com núcleo laranja rompendo o chão, magma correndo
		entre eles e vazando das paredes, faíscas. Não é "vulcânico 2": o 7 é
		rocha, o 8 é magma + cristal. No fim, os cristais escurecem e o veio
		vira outra energia (fria) — o calor virando energia pura.
	]]
	Magma = {
		Floor = { Material = M.Basalt, Color = Color3.fromRGB(32, 28, 28) },
		Lane = { Material = M.Slate, Color = Color3.fromRGB(70, 58, 56) },
		Wall = { Material = M.Basalt, Color = Color3.fromRGB(38, 32, 32) },
		Trim = { Material = M.CrackedLava, Color = Color3.fromRGB(190, 70, 30) },
		Profile = { 46, 52, 48, 46 },
		PlateShade = 0.82,
		Decor = {
			{ Kind = "LavaCrack", At = 0.1, Side = -1, Z = 20, Scale = 1.2, Yaw = 18 },
			{ Kind = "MagmaShard", At = 0.14, Side = 1, Z = 36, Scale = 1.2 },
			{ Kind = "WallMagma", At = 0.28, Side = -1 },
			{ Kind = "MagmaFormation", At = 0.46, Side = 1, Z = 32, Landmark = true, Fx = "MagmaSparks" },
			{ Kind = "MagmaFlow", At = 0.54, Side = 1, Z = 26, Yaw = 30 },
			{ Kind = "MagmaFormation", At = 0.6, Side = -1, Z = 33, Scale = 0.8, Yaw = 12, Landmark = true },
			{ Kind = "WallMagma", At = 0.74, Side = 1, Scale = 0.8 },
			-- Magma → energia: o cristal escurece, a linha fria substitui a fissura.
			{ Kind = "DarkCrystal", At = 0.84, Side = -1, Z = 35 },
			{ Kind = "EnergyLine", At = 0.9, Side = 1, Z = 28, Yaw = -12 },
			{ Kind = "MagmaSeal", At = "Barrier" },
			{ Kind = "DarkCrystal", At = 1.08, Side = 1, Z = 40, Scale = 0.7 },
		},
	},
	--[[
		9 ENERGIA / CÓSMICO — fora do normal: a energia acumulada está
		DISTORCENDO o próprio Caminho. Grafite, azul profundo, violeta; energia
		violeta-branca só nas linhas. Piso escuro com circuitos que "cortam" a
		faixa (só visual), painéis e uma parede cujo topo se soltou, e o
		landmark: ARCOS FLUTUANTES — pedaços de estrutura suspensos por
		energia. A barreira é uma contenção. Depois dela, pilones mais altos
		que as paredes abrindo para fora e energia convergindo para frente:
		tem algo ENORME depois (o 10 não é construído aqui).
	]]
	Tech = {
		Floor = { Material = M.Slate, Color = Color3.fromRGB(32, 32, 42) },
		Lane = { Material = M.DiamondPlate, Color = Color3.fromRGB(58, 60, 80) },
		Wall = { Material = M.Metal, Color = Color3.fromRGB(40, 42, 60) },
		Trim = { Material = M.Metal, Color = Color3.fromRGB(120, 110, 170) },
		Profile = { 48, 44, 52, 50 },
		PlateShade = 0.86,
		Decor = {
			{ Kind = "DarkCrystal", At = 0.05, Side = 1, Z = 36, Scale = 0.8 },
			{ Kind = "EnergyCircuit", At = 0.12 },
			{ Kind = "EnergyPanel", At = 0.24, Side = -1 },
			{ Kind = "EnergyPanel", At = 0.24, Side = 1 },
			{ Kind = "FloatingArch", At = 0.44, Side = -1, Z = 34, Landmark = true, Fx = "EnergyMotes" },
			{ Kind = "FloatingArch", At = 0.56, Side = 1, Z = 35, Scale = 0.8, Yaw = 10, Landmark = true },
			{ Kind = "FloatingShards", At = 0.64, Side = -1, Z = 38 },
			{ Kind = "EnergyCircuit", At = 0.7 },
			{ Kind = "BrokenWall", At = 0.78, Side = 1 },
			{ Kind = "EnergyContainment", At = "Barrier" },
			-- Pré-10 (só preparação; o Colosso é a Fase E).
			{ Kind = "OpeningPylon", At = 1.9, Side = -1 },
			{ Kind = "OpeningPylon", At = 1.9, Side = 1 },
			{ Kind = "ConvergenceLines", At = 1.94 },
		},
	},
	--[[
		10 COLOSSO — o DESTINO, não "o 9 + um tema". Depois da instabilidade
		do 9, poder absoluto: pedra monumental escura, marfim mineral pesado,
		ouro antigo só em faixas finas e energia branco-dourada. A faixa chega
		ao ápice (placas longas de marfim). O corredor abre (soleira
		escalonada), a escala cresce (contrafortes → massas escalonadas →
		obeliscos → paredes que sobem) e tudo conduz ao PORTÃO DO COLOSSO,
		com o selo do Caminho do Poder. Espaço negativo de propósito.
	]]
	Colossus = {
		Floor = { Material = M.Slate, Color = Color3.fromRGB(66, 66, 74) },
		Lane = { Material = M.Marble, Color = Color3.fromRGB(206, 198, 178) },
		Wall = { Material = M.Slate, Color = Color3.fromRGB(72, 72, 80) },
		Trim = { Material = M.Marble, Color = Color3.fromRGB(222, 214, 194) },
		Profile = { 54, 60, 64, 58 },
		PlateShade = 0.9,
		PlateLength = 22,
		Decor = {
			{ Kind = "ColossusThreshold", At = 0.03 },
			{ Kind = "GoldInlay", At = 0.12, Side = -1, Z = 28, Yaw = 22 },
			{ Kind = "GoldInlay", At = 0.12, Side = 1, Z = 28, Yaw = 22 },
			{ Kind = "Buttress", At = 0.26, Side = -1, Scale = 0.8 },
			{ Kind = "Buttress", At = 0.26, Side = 1, Scale = 0.8 },
			{ Kind = "StepMass", At = 0.46, Side = -1 },
			{ Kind = "StepMass", At = 0.46, Side = 1 },
			{ Kind = "ColossusSigil", At = 0.6 },
			{ Kind = "WallRise", At = 0.62, Side = -1, Scale = 0.5 },
			{ Kind = "WallRise", At = 0.62, Side = 1, Scale = 0.5 },
			{ Kind = "Obelisk", At = 0.7, Side = -1, Z = 52 },
			{ Kind = "Obelisk", At = 0.7, Side = 1, Z = 52 },
			{ Kind = "SealLines", At = 0.84 },
			{ Kind = "Buttress", At = 0.86, Side = -1 },
			{ Kind = "Buttress", At = 0.86, Side = 1 },
			{ Kind = "WallRise", At = 0.88, Side = -1 },
			{ Kind = "WallRise", At = 0.88, Side = 1 },
			{ Kind = "ColossusGate", At = "Barrier", Landmark = true, Fx = "SealMotes" },
			-- Atravessar o Colosso: o outro lado do portão e a zona de decisão final.
			{ Kind = "ColossusRear", At = 1.12 },
			{ Kind = "DecisionGold", At = 1.5 },
		},
	},
}

--[[
	O FINAL ATUAL (praça depois do Colosso, até o portal). Mesma estrutura de
	Decor; `At` = fração da praça (CorridorLayout.FINAL_PLAZA). A tensão cai:
	pouca coisa, calma, o olho vai para o portal "em breve" (inerte).
]]
CorridorThemes.Final = {
	Decor = {
		{ Kind = "CalmStele", At = 0.4, Side = -1, Z = 40 },
		{ Kind = "CalmStele", At = 0.4, Side = 1, Z = 40 },
		{ Kind = "PortalGlyph", At = 0.86 },
		{ Kind = "FuturePortal", At = 0.967, Landmark = true, Fx = "PortalMotes" },
	} :: { Decor },
}

local function shade(color: Color3, factor: number): Color3
	return Color3.new(math.clamp(color.R * factor, 0, 1), math.clamp(color.G * factor, 0, 1), math.clamp(color.B * factor, 0, 1))
end

local cache: { [string]: Theme } = {}

-- O tema completo de um estágio (padrões do WallConfig + ajustes daqui).
function CorridorThemes.For(stageId: string): Theme
	local cached = cache[stageId]
	if cached then
		return cached
	end
	local stage: WallConfig.WallStage? = nil
	for _, candidate in WallConfig.Stages do
		if candidate.Id == stageId then
			stage = candidate
		end
	end
	assert(stage, "CorridorThemes: estágio desconhecido " .. tostring(stageId))
	local custom = THEMES[stageId] or {}
	local function surface(key: string, color: Color3): Surface
		local value = custom[key] or {}
		return { Material = value.Material or stage.Material, Color = value.Color or color }
	end
	local theme: Theme = {
		Floor = surface("Floor", shade(stage.Accent, 0.62)),
		Lane = surface("Lane", shade(stage.Color, 0.82):Lerp(Color3.fromRGB(150, 146, 140), 0.25)),
		Wall = surface("Wall", shade(stage.Color, 0.55)),
		Trim = surface("Trim", shade(stage.Accent, 0.9)),
		Profile = custom.Profile or { 32, 38, 42, 38 },
		Props = custom.Props or {},
		Ambient = custom.Ambient,
		Decor = custom.Decor or {},
		PlateShade = custom.PlateShade or 0.93,
		PlateLength = custom.PlateLength,
	}
	cache[stageId] = theme
	return theme
end

-- O tema seguinte (o último aponta para si mesmo).
function CorridorThemes.Next(stageId: string): string
	for index, stage in WallConfig.Stages do
		if stage.Id == stageId then
			local nextStage = WallConfig.Stages[math.min(index + 1, #WallConfig.Stages)]
			return nextStage.Id
		end
	end
	return stageId
end

--[[
	A superfície de um trecho com `blend` do próximo tema: cor misturada e
	material do próximo a partir de Rules.MaterialSwitch.
]]
function CorridorThemes.Mix(from: Surface, to: Surface, blend: number): (Color3, Enum.Material)
	local color = (from.Color :: Color3):Lerp(to.Color :: Color3, blend)
	local material = if blend >= CorridorThemes.Rules.MaterialSwitch then to.Material else from.Material
	return color, material
end

return CorridorThemes
