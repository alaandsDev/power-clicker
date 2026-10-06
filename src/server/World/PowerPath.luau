--!strict
--[[
	PowerPath
	A FUNDAÇÃO do Caminho do Poder (Fase A): piso, faixa central, paredes,
	silhueta, transições e zona de decisão, estágio por estágio. As barreiras,
	os pads, os arcos e o portal continuam no WorldBuilder.buildCorridor —
	nada aqui tem lógica (sem prompt, sem toque, sem atributo de jogo).

	Fontes de verdade (nenhuma conta repetida aqui):
	  CorridorLayout → onde cada trecho começa/termina, pads, largura
	  CorridorThemes → materiais, cores, silhueta, transição, regras
	  WallConfig     → espessuras (piso, parede)

	Cada trecho de estágio vira um Model "PowerPath_<Id>" (tag
	PowerPathStage, atributos StageId/AreaStart/Barrier/End) com:

	  │ terço 1 │ terço 2 │ terço 3 (anúncio) │ barreira + zona de decisão │
	   blend 0    blend 0    blend 0,35          blend 0,7 (revelação)

	  cenário: Model "Decor" (Fase B em diante, PowerPathDecor);
	  piso: faixa central de placas (o "Caminho") + laterais; bordas da faixa;
	  paredes: altura por terço (CorridorThemes Profile) com capitel e um
	           pilar por terço de cada lado — a silhueta sobe e desce;
	  soleira no começo de cada área; moldura da zona de decisão em volta
	  dos pads; dois slots de landmark (Attachments) para as Fases B–E.

	Transição: cada trecho mistura a cor do próximo tema pelo blend; a partir
	de 0,5 troca o material; no terço 3 as placas da faixa mais perto da
	barreira já são do próximo tema (degradê). Nada troca de uma vez.

	SAFE PLAY LANE (CorridorThemes.Rules.SafeLaneHalf): nada sólido nem alto
	entra na faixa do meio — só piso e acabamento rente ao chão.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local WallConfig = require(Shared.Config.WallConfig)
local CorridorThemes = require(Shared.Config.CorridorThemes)
local CorridorLayout = require(Shared.Formulas.CorridorLayout)
local PowerPathDecor = require(script.Parent.PowerPathDecor)

local PowerPath = {}

PowerPath.TAG_STAGE = "PowerPathStage"

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, collide: boolean): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.CanCollide = collide
	p.CanTouch = false
	p.CanQuery = collide
	p.CastShadow = collide and material ~= Enum.Material.Neon
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function shade(color: Color3, factor: number): Color3
	return Color3.new(math.clamp(color.R * factor, 0, 1), math.clamp(color.G * factor, 0, 1), math.clamp(color.B * factor, 0, 1))
end

-- Degradê da faixa: no trecho com `blend` do próximo tema, as últimas placas
-- (as mais perto da barreira) já são do próximo — nunca uma linha seca.
local function plateIsNext(k: number, count: number, blend: number): boolean
	return blend > 0 and (k - 0.5) / count > 1 - blend
end

type Section = { From: number, To: number, Blend: number, Profile: number, Area: boolean }

local function sections(segment: CorridorLayout.Segment): { Section }
	local blend = CorridorThemes.Rules.Blend
	local profile = CorridorThemes.For(segment.Id).Profile
	local length = segment.Barrier - segment.AreaStart
	local a = segment.AreaStart
	return {
		{ From = a, To = a + length / 3, Blend = blend[1], Profile = profile[1], Area = true },
		{ From = a + length / 3, To = a + length * 2 / 3, Blend = blend[2], Profile = profile[2], Area = true },
		{ From = a + length * 2 / 3, To = segment.Barrier, Blend = blend[3], Profile = profile[3], Area = true },
		{ From = segment.Barrier, To = segment.End, Blend = blend[4], Profile = profile[4], Area = false },
	}
end

--[[
	Piso + paredes de um trecho [from, to) do corredor, com `blend` do tema
	`toTheme` sobre `fromTheme`. Devolve as laterais (para os slots).
]]
local function buildSection(model: Model, origin: Vector3, half: number, section: Section, fromTheme: CorridorThemes.Theme, toTheme: CorridorThemes.Theme): { BasePart }
	local rules = CorridorThemes.Rules
	local layout = WallConfig.Layout
	local thickness = layout.FloorThickness
	local length = section.To - section.From
	local centreX = (section.From + section.To) / 2
	local blend = section.Blend
	local laneHalf = rules.LaneHalf

	-- Laterais do piso (fora da faixa central).
	local floorColor, floorMaterial = CorridorThemes.Mix(fromTheme.Floor, toTheme.Floor, blend)
	local shoulders = {}
	local shoulderWidth = half - laneHalf
	for _, side in { -1, 1 } do
		local shoulder = part(model, "PathFloor", Vector3.new(length + 0.2, thickness, shoulderWidth), CFrame.new(origin + Vector3.new(centreX, -thickness / 2, side * (laneHalf + shoulderWidth / 2))), floorColor, floorMaterial, true)
		shoulder:SetAttribute("Side", side)
		table.insert(shoulders, shoulder)
	end

	-- Faixa central: placas na área (o "Caminho"); na zona de decisão, uma
	-- laje só (o pouso depois da barreira).
	if section.Area then
		local count = math.max(math.round(length / (fromTheme.PlateLength or rules.PlateLength)), 1)
		local plate = length / count
		for k = 1, count do
			local useNext = plateIsNext(k, count, blend)
			local surface = if useNext then toTheme.Lane else fromTheme.Lane
			local color = shade(surface.Color :: Color3, if k % 2 == 0 then (if useNext then toTheme else fromTheme).PlateShade else 1)
			local x = section.From + (k - 0.5) * plate
			local slab = part(model, "PathLane", Vector3.new(plate + 0.1, thickness, laneHalf * 2), CFrame.new(origin + Vector3.new(x, -thickness / 2, 0)), color, surface.Material, true)
			slab:SetAttribute("NextTheme", useNext)
		end
		-- Bordas da faixa, rentes ao chão (sem colisão: ninguém tropeça).
		local trimColor, trimMaterial = CorridorThemes.Mix(fromTheme.Trim, toTheme.Trim, blend)
		for _, side in { -1, 1 } do
			part(model, "PathLaneEdge", Vector3.new(length, 0.12, 0.7), CFrame.new(origin + Vector3.new(centreX, 0.06, side * laneHalf)), trimColor, trimMaterial, false)
		end
	else
		local laneColor, laneMaterial = CorridorThemes.Mix(fromTheme.Lane, toTheme.Lane, blend)
		part(model, "PathLanding", Vector3.new(length + 0.2, thickness, laneHalf * 2), CFrame.new(origin + Vector3.new(centreX, -thickness / 2, 0)), laneColor, laneMaterial, true)
	end

	-- Paredes: altura do perfil, capitel no topo e um pilar por terço.
	local wallColor, wallMaterial = CorridorThemes.Mix(fromTheme.Wall, toTheme.Wall, blend)
	local capColor, capMaterial = CorridorThemes.Mix(fromTheme.Trim, toTheme.Trim, blend)
	local height = section.Profile
	local side = layout.SideThickness
	for _, s in { -1, 1 } do
		local z = s * (half + side / 2)
		part(model, "PathWall", Vector3.new(length + 0.2, height, side), CFrame.new(origin + Vector3.new(centreX, height / 2, z)), wallColor, wallMaterial, true)
		part(model, "PathWallCap", Vector3.new(length + 0.2, 1, side + 1), CFrame.new(origin + Vector3.new(centreX, height + 0.5, z)), capColor, capMaterial, false)
		if section.Area then
			local depth, width = rules.PillarDepth, rules.PillarWidth
			local pillarHeight = height + 4
			local pz = s * (half + (side - depth) / 2)
			part(model, "PathPillar", Vector3.new(width, pillarHeight, depth + side), CFrame.new(origin + Vector3.new(centreX, pillarHeight / 2, pz)), shade(wallColor, 0.82), wallMaterial, true)
			part(model, "PathPillarCap", Vector3.new(width + 1, 1, depth + side + 1), CFrame.new(origin + Vector3.new(centreX, pillarHeight + 0.5, pz)), capColor, capMaterial, false)
		end
	end
	return shoulders
end

-- Um trecho de estágio inteiro (área + barreira + zona de decisão).
function PowerPath.BuildStage(parent: Instance, origin: Vector3, segment: CorridorLayout.Segment): Model
	local model = Instance.new("Model")
	model.Name = "PowerPath_" .. segment.Id
	local theme = CorridorThemes.For(segment.Id)
	local nextTheme = CorridorThemes.For(CorridorThemes.Next(segment.Id))
	local half = segment.Width / 2
	local rules = CorridorThemes.Rules
	local layout = WallConfig.Layout

	for index, section in sections(segment) do
		local shoulders = buildSection(model, origin, half, section, theme, nextTheme)
		-- Slots de landmark (Fases B–E): no meio da área, um de cada lado,
		-- fora da safe lane, rente à parede.
		if index == 2 then
			for _, shoulder in shoulders do
				local slot = Instance.new("Attachment")
				slot.Name = "LandmarkSlot"
				local sideSign = shoulder:GetAttribute("Side") :: number
				local offsetZ = sideSign * ((half - rules.LaneHalf) / 2 - rules.PillarDepth - 2)
				slot.Position = Vector3.new(0, layout.FloorThickness / 2, offsetZ)
				slot:SetAttribute("Side", sideSign)
				slot:SetAttribute("StageId", segment.Id)
				slot.Parent = shoulder
			end
		end
	end

	-- Soleira no começo da área: o "você entrou numa região nova" no chão.
	part(model, "PathThreshold", Vector3.new(1.6, 0.14, rules.LaneHalf * 2 + 2), CFrame.new(origin + Vector3.new(segment.AreaStart + 0.8, 0.07, 0)), theme.Trim.Color :: Color3, theme.Trim.Material, false)

	--[[
		Zona de decisão (depois da barreira): uma moldura rente ao chão em
		volta dos pads de vitória e do pad de voltar — "pegue um prêmio ou
		siga". O ambiente se encaixa nos pads; os pads não mudam.
	]]
	local pad = layout.PadSize
	local x0 = segment.PadsX - pad / 2 - 4
	local x1 = segment.ReturnX + pad / 2 + 4
	local z1 = half - 3
	local frameColor = (theme.Trim.Color :: Color3):Lerp(nextTheme.Trim.Color :: Color3, rules.Blend[4])
	local frameMaterial = if rules.Blend[4] >= rules.MaterialSwitch then nextTheme.Trim.Material else theme.Trim.Material
	for _, s in { -1, 1 } do
		part(model, "PathDecisionFrame", Vector3.new(x1 - x0, 0.12, 0.8), CFrame.new(origin + Vector3.new((x0 + x1) / 2, 0.08, s * z1)), frameColor, frameMaterial, false)
		part(model, "PathDecisionFrame", Vector3.new(0.8, 0.12, z1 * 2), CFrame.new(origin + Vector3.new(if s < 0 then x0 else x1, 0.08, 0)), frameColor, frameMaterial, false)
	end

	-- Cenário do tema (Fase B em diante): landmark, peças, molduras das
	-- barreiras e transição — Model "Decor" (PowerPathDecor + CorridorThemes).
	PowerPathDecor.Build(model, origin, segment)

	model:SetAttribute("StageId", segment.Id)
	model:SetAttribute("Order", segment.Order)
	model:SetAttribute("AreaStart", segment.AreaStart)
	model:SetAttribute("Barrier", segment.Barrier)
	model:SetAttribute("End", segment.End)
	model:AddTag(PowerPath.TAG_STAGE)
	model.Parent = parent
	return model
end

-- A praça final até o portal: a faixa central termina diante dele.
function PowerPath.BuildFinal(parent: Instance, origin: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "PowerPath_Final"
	local segments = CorridorLayout.Segments()
	local last = segments[#segments]
	local theme = CorridorThemes.For(last.Id)
	local start = CorridorLayout.FinalStart()
	local length = CorridorLayout.FINAL_PLAZA
	buildSection(model, origin, last.Width / 2, {
		From = start,
		To = start + length,
		Blend = 0,
		Profile = theme.Profile[4],
		Area = true,
	}, theme, theme)
	part(model, "PathThreshold", Vector3.new(1.6, 0.14, CorridorThemes.Rules.LaneHalf * 2 + 2), CFrame.new(origin + Vector3.new(start + 0.8, 0.07, 0)), theme.Trim.Color :: Color3, theme.Trim.Material, false)
	-- Área de conclusão e moldura do portal (Fase E).
	PowerPathDecor.BuildFinal(model, origin)
	model:SetAttribute("StageId", "Final")
	model:SetAttribute("AreaStart", start)
	model:SetAttribute("End", start + length)
	model.Parent = parent
	return model
end

return PowerPath
