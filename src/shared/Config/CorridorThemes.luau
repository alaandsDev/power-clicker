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

	Fases futuras (B: 1–3, C: 4–6, D: 7–9, E: Colosso) preenchem `Props`,
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
]]
export type Decor = { Kind: string, At: number | string, Side: number?, Z: number?, Scale: number?, Yaw: number?, Landmark: boolean? }
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
	Crystal = {
		Floor = { Material = M.Slate },
		Lane = { Material = M.Glass },
		Wall = { Material = M.Rock },
		Trim = { Material = M.Glass },
		Profile = { 38, 46, 42, 40 },
	},
	Gold = {
		Floor = { Material = M.Sandstone },
		Lane = { Material = M.Marble },
		Wall = { Material = M.Sandstone },
		Trim = { Material = M.Metal },
		Profile = { 40, 36, 46, 42 },
	},
	Ancient = {
		Floor = { Material = M.Sandstone },
		Lane = { Material = M.Cobblestone },
		Wall = { Material = M.Sandstone },
		Trim = { Material = M.Slate },
		Profile = { 42, 48, 44, 42 },
	},
	Volcanic = {
		Floor = { Material = M.Basalt },
		Lane = { Material = M.Basalt },
		Wall = { Material = M.Basalt },
		Trim = { Material = M.CrackedLava },
		Profile = { 44, 38, 50, 46 },
	},
	Magma = {
		Floor = { Material = M.CrackedLava },
		Lane = { Material = M.Basalt },
		Wall = { Material = M.Basalt },
		Trim = { Material = M.CrackedLava },
		Profile = { 46, 52, 48, 46 },
	},
	Tech = {
		Floor = { Material = M.DiamondPlate },
		Lane = { Material = M.Metal },
		Wall = { Material = M.Metal },
		Trim = { Material = M.Neon },
		Profile = { 48, 44, 52, 50 },
	},
	-- Colosso: paredes altas e piso de mármore; a Fase E monta o monumento
	-- nos slots (a área é 1,6x mais larga e mais longa).
	Colossus = {
		Floor = { Material = M.Marble },
		Lane = { Material = M.Marble },
		Wall = { Material = M.Marble },
		Trim = { Material = M.Metal },
		Profile = { 54, 60, 64, 58 },
	},
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
