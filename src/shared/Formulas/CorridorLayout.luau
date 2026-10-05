--!strict
--[[
	CorridorLayout
	Onde cada estágio do Caminho do Poder fica ao longo do corredor (eixo X,
	a partir da origem do mundo), pela MESMA conta do
	WorldBuilder.buildCorridor:

		[AreaStart ........ Barrier][fileiras][pads ... End]

	Puro (sem Instance). O cliente usa para saber em que área o jogador
	entrou (título temporário do estágio); o check_power_hud confere que
	bate com as fileiras construídas.
]]

local Shared = script.Parent.Parent
local WallConfig = require(Shared.Config.WallConfig)

export type Segment = {
	Id: string,
	Order: number,
	AreaStart: number, -- começo da área temática
	Barrier: number, -- face da primeira fileira
	End: number, -- fim do trecho (depois dos pads)
	Height: number,
	Width: number,
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
		table.insert(list, {
			Id = stage.Id,
			Order = stage.Order,
			AreaStart = cursor,
			Barrier = cursor + length,
			End = cursor + length + depth + 72,
			Height = layout.WallHeight * scale,
			Width = layout.Width * scale,
		})
		cursor += length + depth + 72
	end
	cache = list
	return list
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
