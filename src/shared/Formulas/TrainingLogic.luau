--!strict
--[[
	TrainingLogic
	Regras puras do Campo de Treinamento (sem Instance, sem serviço), usadas
	pelo TrainingService (servidor, quem decide) e pelo cliente (só para
	mostrar cadeado/energia de cada alvo).

	- StationAt: em qual estação a posição está (raio no plano + altura),
	  independentemente de o jogador poder treinar nela.
	- CanTrain: o requisito de Renascimentos.
]]

local Shared = script.Parent.Parent
local TrainingConfig = require(Shared.Config.TrainingConfig)

type Station = TrainingConfig.Station

local TrainingLogic = {}

-- Diferença de altura aceita entre o personagem e o chão da estação.
TrainingLogic.HEIGHT_TOLERANCE = 14

function TrainingLogic.Required(station: Station): number
	return math.max(math.floor(tonumber(station.RequiredRebirths) or 0), 0)
end

function TrainingLogic.CanTrain(station: Station, rebirths: number?): boolean
	return (tonumber(rebirths) or 0) >= TrainingLogic.Required(station)
end

-- `areaCentre` = centro da área de treino no mundo.
function TrainingLogic.StationAt(areaCentre: Vector3, position: Vector3): Station?
	for _, station in TrainingConfig.Stations do
		local centre = areaCentre + station.Local
		local flat = (position - centre) * Vector3.new(1, 0, 1)
		if flat.Magnitude <= station.Radius and math.abs(position.Y - centre.Y) <= TrainingLogic.HEIGHT_TOLERANCE then
			return station
		end
	end
	return nil
end

function TrainingLogic.ById(id: string): Station?
	for _, station in TrainingConfig.Stations do
		if station.Id == id then
			return station
		end
	end
	return nil
end

return TrainingLogic
