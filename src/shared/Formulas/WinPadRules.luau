--!strict
--[[
	WinPadRules
	Quanto cada pad de vitória paga. Uma regra só, usada pelo servidor
	(WallService paga) e pelo cliente (a placa do pad mostra o valor que o
	jogador vai receber de verdade).

	Cada estágio tem pads em WallConfig.Stages[n].Pads, ex. { 1, 2 }: o pad 1
	é o prêmio normal e o pad 2 é o "x2" (sempre o dobro do primeiro). O
	jogador escolhe UM pad por abertura; pegar o pad encerra a corrida
	(volta para a praça).

	- Primeira conquista do estágio (a abertura em que ele cai pela primeira
	  vez para o jogador): valor cheio.
	- Repetindo: WallConfig.Repeat — `Share` no melhor estágio do jogador,
	  caindo `FalloffPerStage` por degrau abaixo dele (piso `MinShare`).

	O pad x2 vale sempre (pad normal) × (razão entre os pads). Antes, cada pad
	era arredondado sozinho com piso 1: repetindo a barreira de madeira, 1 ×
	0,2 e 2 × 0,2 viravam ambos 1 — o "x2 paga igual ao normal".
]]

local Shared = script.Parent.Parent
local WallConfig = require(Shared.Config.WallConfig)

type Stage = WallConfig.WallStage
export type TowerData = { Cleared: { [string]: boolean }, Highest: number }

local WinPadRules = {}

-- Fração do valor cheio que este jogador recebe agora neste estágio.
function WinPadRules.Share(stage: Stage, tower: TowerData?, firstClear: boolean): number
	if firstClear or type(tower) ~= "table" or tower.Cleared[stage.Id] ~= true then
		return 1
	end
	local rule = WallConfig.Repeat
	local behind = math.max((tonumber(tower.Highest) or 0) - stage.Order, 0)
	return math.max(rule.Share * rule.FalloffPerStage ^ behind, rule.MinShare)
end

-- Vitórias do pad `padIndex` com a fração `share`. 0 para pad inexistente.
function WinPadRules.Payout(stage: Stage, padIndex: number, share: number): number
	local base = stage.Pads[1]
	local amount = stage.Pads[padIndex]
	if type(base) ~= "number" or type(amount) ~= "number" or base <= 0 or amount <= 0 then
		return 0
	end
	local normal = math.max(math.floor(base * share), 1)
	return math.max(math.floor(normal * (amount / base) + 0.5), 1)
end

-- O pad é um "x2" de verdade? Só quando vale exatamente o dobro do normal
-- (no Gelo os pads são 8 e 15: a placa mostra o valor, sem dizer "x2").
function WinPadRules.IsDouble(stage: Stage, padIndex: number): boolean
	return padIndex >= 2 and stage.Pads[padIndex] == (stage.Pads[1] or 0) * 2
end

-- Índice do pad que paga `amount` no valor cheio (para pads sem PadIndex).
function WinPadRules.IndexOf(stage: Stage, amount: number): number?
	for index, value in stage.Pads do
		if value == amount then
			return index
		end
	end
	return nil
end

return WinPadRules
