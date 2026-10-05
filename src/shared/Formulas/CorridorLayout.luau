--!strict
--[[
	CorridorLayout
	Onde cada estágio do Caminho do Poder fica ao longo do corredor (eixo X,
	a partir da origem do mundo), pela MESMA conta do
	WorldBuilder.buildCorridor:

		[AreaStart ........ Barrier][fileiras][pads ... End]

	Puro (sem Instance). O cliente usa para saber em que área o jogador
	entrou (título temporário do estágio); o WorldBuilder/PowerPath constrói
	o corredor a partir daqui; check_power_hud e check_power_path conferem.
]]

local Shared = script.Parent.Parent
local WallConfig = require(Shared.Config.WallConfig)

export type Segment = {
	Id: string,
	Order: number,
	Index: number,
	AreaStart: number, -- começo da área temática
	Barrier: number, -- face da primeira fileira
	Depth: number, -- fileiras + vãos (a barreira ocupa [Barrier, Barrier + Depth])
	PadsX: number, -- centro dos pads de vitória (zona de decisão)
	ReturnX: number, -- centro do pad de voltar
	End: number, -- fim do trecho (depois dos pads)
	Height: number,
	Width: number,
	Final: boolean,
}

local CorridorLayout = {}

local cache: { Segment }? = nil

function CorridorLayout.Segments(): { Segment }
	if cache then
		return cache
	end
	local layout = WallConfig.Layout
	local list: { Segment } = {}
	local cursor = layout.StartX
	for index, stage in WallConfig.Stages do
		local scale = if index == #WallConfig.Stages then layout.FinalScale else 1
		local length = layout.RoomLength * scale
		local depth = stage.Rows * layout.RowThickness + (stage.Rows - 1) * layout.RowGap
		local barrier = cursor + length
		table.insert(list, {
			Id = stage.Id,
			Order = stage.Order,
			Index = index,
			AreaStart = cursor,
			Barrier = barrier,
			Depth = depth,
			PadsX = barrier + depth + 24,
			ReturnX = barrier + depth + 24 + layout.ReturnPadInset,
			End = barrier + depth + 72,
			Height = layout.WallHeight * scale,
			Width = layout.Width * scale,
			Final = index == #WallConfig.Stages,
		})
		cursor += length + depth + 72
	end
	cache = list
	return list
end

-- Praça final (depois do Colosso) até o portal: [FinalStart, FinalStart + FINAL_PLAZA].
CorridorLayout.FINAL_PLAZA = 120

function CorridorLayout.FinalStart(): number
	local list = CorridorLayout.Segments()
	return list[#list].End
end

-- O estágio cuja ÁREA (antes da barreira) contém `x` (relativo à origem).
function CorridorLayout.AreaAt(x: number): Segment?
	for _, segment in CorridorLayout.Segments() do
		if x >= segment.AreaStart and x < segment.Barrier then
			return segment
		end
	end
	return nil
end

return CorridorLayout
