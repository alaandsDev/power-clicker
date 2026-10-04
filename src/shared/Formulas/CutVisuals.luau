--!strict
--[[
	CutVisuals
	Transforma a identidade visual de um corte (campos do CutConfig) na
	"receita" do efeito que é desenhado. É a ponte única:

		CutConfig (cor, trail, luz, neon, riscos, faíscas, tamanho)
		        │
		    CutVisuals.For
		   ┌────┴─────┐
		golpe        vitrine
		(SlashController)  (CutShowcaseController)

	Os dois desenham com o mesmo CutFx; a vitrine só muda a escala (o efeito
	cabe no pedestal) e, para corte bloqueado, usa CutVisuals.Locked.

	Puro: não lê jogador, não mexe em dado nenhum.
]]

local Shared = script.Parent.Parent
local CutConfig = require(Shared.Config.CutConfig)

export type Recipe = {
	CutId: string,
	Color: Color3,
	Slashes: number,
	Length: number,
	Width: number,
	Thickness: number,
	FadeSeconds: number,
	Sweep: number, -- graus que o risco varre enquanto some (o "trail")
	Sparks: number,
	LightRange: number,
	Glow: boolean,
}

local CutVisuals = {}

-- Medidas do risco no tamanho 1 (as mesmas do arco do golpe).
CutVisuals.BASE_LENGTH = 6.5
CutVisuals.BASE_WIDTH = 1.1
CutVisuals.THICKNESS = 0.25
CutVisuals.FLASH_SECONDS = 0.16
-- Limites do desenho: o CutFx guarda peças para isso e nada além.
CutVisuals.MAX_SLASHES = 3
CutVisuals.MAX_SPARKS = 24
-- Bloqueado: quanto a cor vai para o cinza.
CutVisuals.LOCKED_GREY = Color3.fromRGB(120, 124, 136)
CutVisuals.LOCKED_MIX = 0.65

-- Inclinação (graus, em torno do eixo do olhar) de cada risco: 1 diagonal,
-- 2 em X, 3 em leque.
local ANGLES: { [number]: { number } } = {
	[1] = { 45 },
	[2] = { 45, -45 },
	[3] = { 60, 0, -60 },
}

function CutVisuals.Angles(slashes: number): { number }
	return ANGLES[math.clamp(slashes, 1, CutVisuals.MAX_SLASHES)]
end

-- Receita do efeito real do corte `cutId` (nil para id desconhecido).
function CutVisuals.For(cutId: string): Recipe?
	local cut = CutConfig.Cuts[cutId]
	if not cut then
		return nil
	end
	return {
		CutId = cut.Id,
		Color = cut.Color,
		Slashes = math.clamp(cut.Slashes, 1, CutVisuals.MAX_SLASHES),
		Length = CutVisuals.BASE_LENGTH * cut.SlashScale,
		Width = CutVisuals.BASE_WIDTH * cut.SlashScale,
		Thickness = CutVisuals.THICKNESS,
		FadeSeconds = CutVisuals.FLASH_SECONDS + cut.TrailSeconds,
		-- Sem trail o risco é seco; com trail ele varre um pouco ao sumir.
		Sweep = cut.TrailSeconds * 60,
		Sparks = math.clamp(cut.Sparks, 0, CutVisuals.MAX_SPARKS),
		LightRange = cut.LightRange,
		Glow = cut.Neon,
	}
end

-- A receita do corte que o jogador usa de verdade (o melhor que possui).
function CutVisuals.ForBest(bestCutId: any): Recipe
	local recipe = if type(bestCutId) == "string" then CutVisuals.For(bestCutId) else nil
	return recipe or (CutVisuals.For(CutConfig.StarterCut) :: Recipe)
end

-- Versão apagada para a vitrine de um corte bloqueado: mesma forma (o
-- jogador ainda vê o que vai ganhar), cor puxada para o cinza, sem brilho e
-- com poucas faíscas.
function CutVisuals.Locked(recipe: Recipe): Recipe
	local copy = table.clone(recipe)
	copy.Color = recipe.Color:Lerp(CutVisuals.LOCKED_GREY, CutVisuals.LOCKED_MIX)
	copy.Sparks = math.floor(recipe.Sparks / 3)
	copy.LightRange = 0
	copy.Glow = false
	return copy
end

-- Problemas na configuração visual (lista vazia = tudo certo). Os testes usam.
function CutVisuals.Problems(): { string }
	local problems = {}
	for cutId, cut in CutConfig.Cuts do
		local function bad(message: string)
			table.insert(problems, cutId .. ": " .. message)
		end
		if typeof(cut.Color) ~= "Color3" then
			bad("sem cor")
		end
		if type(cut.Slashes) ~= "number" or cut.Slashes < 1 or cut.Slashes > CutVisuals.MAX_SLASHES or cut.Slashes % 1 ~= 0 then
			bad("Slashes fora de 1.." .. CutVisuals.MAX_SLASHES)
		end
		if type(cut.Sparks) ~= "number" or cut.Sparks < 0 or cut.Sparks > CutVisuals.MAX_SPARKS or cut.Sparks % 1 ~= 0 then
			bad("Sparks fora de 0.." .. CutVisuals.MAX_SPARKS)
		end
		if type(cut.SlashScale) ~= "number" or cut.SlashScale <= 0 or cut.SlashScale > 3 then
			bad("SlashScale fora de (0, 3]")
		end
		if type(cut.TrailSeconds) ~= "number" or cut.TrailSeconds < 0 or cut.TrailSeconds > 1 then
			bad("TrailSeconds fora de [0, 1]")
		end
		if type(cut.LightRange) ~= "number" or cut.LightRange < 0 or cut.LightRange > 60 then
			bad("LightRange fora de [0, 60]")
		end
		if type(cut.Neon) ~= "boolean" then
			bad("Neon não é booleano")
		end
	end
	return problems
end

return CutVisuals
