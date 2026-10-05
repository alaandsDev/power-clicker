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
	Wood = {
		Floor = { Material = M.Ground },
		Lane = { Material = M.Cobblestone },
		Wall = { Material = M.Rock },
		Trim = { Material = M.Wood },
		Profile = { 26, 32, 38, 34 },
	},
	Ruins = {
		Floor = { Material = M.Slate },
		Lane = { Material = M.Cobblestone },
		Wall = { Material = M.Slate },
		Trim = { Material = M.Concrete },
		Profile = { 34, 30, 40, 36 },
	},
	Ice = {
		Floor = { Material = M.Glacier },
		Lane = { Material = M.Ice },
		Wall = { Material = M.Glacier },
		Trim = { Material = M.Ice },
		Profile = { 36, 44, 40, 38 },
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
