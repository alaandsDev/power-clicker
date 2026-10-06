--[[
	check_power_path.luau — Caminho do Poder: fundação (Fase A), temas 1–3 (Fase B) e 4–6 (Fase C).

		lune run tools/lune/check_power_path.luau [raiz]

	Não mede beleza: mede a estrutura que as Fases B–E vão vestir.
	  1. 10 trechos (Model PowerPath_<Id>) na ordem, batendo com o
	     CorridorLayout, mais a praça final; entrada colada no portão;
	  2. corredor horizontal: piso todo com o topo em y = 0;
	  3. SAFE PLAY LANE: nada sólido nem alto na faixa do meio (fora as
	     fileiras); caminho livre do portão ao portal para avatar + pets;
	  4. limites: nada da fundação fora do trecho nem além das paredes;
	  5. transições: terço 1 no tema puro, terço 3 anunciando o próximo
	     (cor misturada + placas do próximo tema), zona de decisão já com o
	     material do próximo; silhueta das paredes variando;
	  6. barreiras e pads intocados (posição, tamanho, quantidade); moldura
	     da zona de decisão em volta dos pads; nada sólido em cima deles;
	  7. portal preservado e inerte; estágio 10 pronto para o Colosso
	     (largura 1,6x, slots de landmark);
	  8. nenhuma decoração global (ilhas do céu, árvores, pedras) dentro do
	     corredor;
	  9. orçamento: peças, PointLights e emissores do corredor;
	 10. Fases B e C (estágios 1–6): landmark, molduras das barreiras,
	     transições físicas (1→2 … 6→calor do 7), cenário fora da safe lane /
	     da frente da barreira / das fileiras / dos pads / da câmera, Neon só
	     como acento, orçamento por estágio, emissores locais com um único
	     controlador.

	REQUER VALIDAÇÃO NO ROBLOX STUDIO: escala, materiais, luz e leitura em
	3ª pessoa; pets de verdade seguindo o jogador.
]]
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local E = require("./env")(process.args[1])
local V3 = roblox.Vector3
local CF = roblox.CFrame
local Enum = roblox.Enum

local problems = {}
local function check(condition: any, message: string)
	if condition then
		print("OK   " .. message)
	else
		table.insert(problems, message)
		print("FALHA " .. message)
	end
end

local WallConfig = E.require(E.Shared.Config.WallConfig)
local WorldConfig = E.require(E.Shared.Config.WorldConfig)
local CorridorLayout = E.require(E.Shared.Formulas.CorridorLayout)
local CorridorThemes = E.require(E.Shared.Config.CorridorThemes)
local world = E.require(E.Server.World.WorldBuilder).Build(WorldConfig.Worlds[WallConfig.WorldId], V3.new(0, 0, 0), E.Instance.new("Folder"), E.Instance.new("Folder"), true)
local path = world:FindFirstChild("PowerPath")
check(path ~= nil, "1. corredor agrupado no Model PowerPath")
if not path then
	process.exit(1)
end
local layout = WallConfig.Layout
local rules = CorridorThemes.Rules
local segments = CorridorLayout.Segments()
local finalStart = CorridorLayout.FinalStart()
local finalEnd = finalStart + CorridorLayout.FINAL_PLAZA

local function corners(part)
	local list = {}
	local h = part.Size / 2
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				table.insert(list, (part.CFrame * CF.new(sx * h.X, sy * h.Y, sz * h.Z)).Position)
			end
		end
	end
	return list
end
local function box(part)
	local minP, maxP = V3.new(math.huge, math.huge, math.huge), V3.new(-math.huge, -math.huge, -math.huge)
	for _, c in corners(part) do
		minP = V3.new(math.min(minP.X, c.X), math.min(minP.Y, c.Y), math.min(minP.Z, c.Z))
		maxP = V3.new(math.max(maxP.X, c.X), math.max(maxP.Y, c.Y), math.max(maxP.Z, c.Z))
	end
	return minP, maxP
end

-- ── 1. Trechos ──────────────────────────────────────────────────────────────
local stageModels = {}
local orderOk = #segments == 10
for index, segment in segments do
	local model = path:FindFirstChild("PowerPath_" .. segment.Id)
	stageModels[segment.Id] = model
	if not model or model:GetAttribute("Order") ~= index or model:GetAttribute("AreaStart") ~= segment.AreaStart or model:GetAttribute("Barrier") ~= segment.Barrier or model:GetAttribute("End") ~= segment.End or not model:HasTag("PowerPathStage") then
		orderOk = false
		print("      trecho " .. segment.Id .. " ausente ou fora do layout")
	end
	if index > 1 and math.abs(segment.AreaStart - segments[index - 1].End) > 1e-6 then
		orderOk = false
	end
end
check(orderOk, "1. 10 trechos PowerPath_<Id> na ordem, contíguos e batendo com o CorridorLayout (tag PowerPathStage)")
local final = path:FindFirstChild("PowerPath_Final")
check(final and final:GetAttribute("AreaStart") == finalStart and final:GetAttribute("End") == finalEnd, "1. praça final do portal na mesma fundação")
local threshold1 = stageModels.Wood and stageModels.Wood:FindFirstChild("PathThreshold")
check(segments[1].AreaStart == layout.StartX and threshold1 and math.abs(threshold1.CFrame.Position.X - layout.StartX - 0.8) < 0.01, "1. a faixa do Caminho começa colada no portão (soleira em x = StartX)")

-- ── 2. Horizontal ───────────────────────────────────────────────────────────
local floorOk, floors = true, 0
for _, d in path:GetDescendants() do
	if d:IsA("BasePart") and (d.Name == "PathFloor" or d.Name == "PathLane" or d.Name == "PathLanding") then
		floors += 1
		local top = d.CFrame.Position.Y + d.Size.Y / 2
		if math.abs(top) > 0.01 or not d.CanCollide then
			floorOk = false
		end
	end
end
check(floorOk and floors > 100, string.format("2. corredor plano: %d peças de piso, todas com o topo em y = 0 (sem degrau, sem rampa)", floors))
-- Piso contínuo na faixa e nas laterais do portão ao portal.
local solids = {}
for _, d in world:GetDescendants() do
	if d:IsA("BasePart") and d.CanCollide then
		local p = d.CFrame.Position
		if p.X > layout.StartX - 40 and p.X < finalEnd + 60 and math.abs(p.Z) < 120 then
			table.insert(solids, d)
		end
	end
end
local function solidAt(p, ignoreRows)
	for _, part in solids do
		if not (ignoreRows and part:GetAttribute("Wall") == true) then
			local lp = part.CFrame:PointToObjectSpace(p)
			local h = part.Size / 2
			if math.abs(lp.X) <= h.X and math.abs(lp.Y) <= h.Y and math.abs(lp.Z) <= h.Z then
				return part
			end
		end
	end
	return nil
end
local holes = 0
for x = layout.StartX, finalEnd - 6, 1.5 do
	for _, z in { 0, -rules.LaneHalf - 0.5, rules.LaneHalf + 0.5, -40, 40 } do
		if not solidAt(V3.new(x, -0.5, z), false) then
			holes += 1
		end
	end
end
check(holes == 0, string.format("2. piso sem buraco do portão ao portal (faixa, bordas e laterais; %d furos)", holes))

-- ── 3. Safe play lane ───────────────────────────────────────────────────────
local laneProblems = {}
for _, d in path:GetDescendants() do
	if d:IsA("BasePart") and d:GetAttribute("Wall") ~= true and d:GetAttribute("WallDetail") ~= true then
		local minP, maxP = box(d)
		local intoLane = minP.Z < rules.SafeLaneHalf and maxP.Z > -rules.SafeLaneHalf
		local tall = maxP.Y > 0.3 and minP.Y < 14
		-- (O portal e a moldura dele são o DESTINO: ficam no fim da praça final.)
		local destination = minP.X > finalEnd - 12
		if intoLane and tall and d:GetAttribute("WinPad") ~= true and not destination then
			table.insert(laneProblems, string.format("%s (%.0f, %.0f, %.0f)", d.Name, d.CFrame.Position.X, d.CFrame.Position.Y, d.CFrame.Position.Z))
		end
	end
end
check(#laneProblems == 0, "3. SAFE PLAY LANE (±" .. rules.SafeLaneHalf .. " studs, até 14 de altura): só piso e acabamento rente ao chão " .. table.concat(laneProblems, ", "))
-- Caminho do avatar + pets do portão ao portal; as fileiras contam como
-- abertas (o jogador as quebrou). Pets (PetFollowController): 1, 3 ou até
-- 12 equipados, em 2 colunas a ±2,6 studs do rastro (+1,4 da arte) e até
-- ~19 studs atrás — ocupam ±4 em volta da linha do jogador. Linhas testadas:
-- centro, ±4, ±8, ±12 e ±16: a SAFE LANE inteira (Fase B: o cenário mora
-- fora dela, nas laterais, e as laterais deixam de ser rota garantida).
local function blockedAt(p)
	return solidAt(p, true)
end
local routeHits = {}
for _, z in { 0, -4, 4, -8, 8, -12, 12, -16, 16 } do
	for x = layout.StartX + 2, finalEnd - 30, 1 do
		for _, y in { 1, 3, 5 } do
			local hit = blockedAt(V3.new(x, y, z))
			if hit then
				table.insert(routeHits, string.format("%s em x=%d z=%d", hit.Name, x, z))
				break
			end
		end
		if #routeHits > 0 and routeHits[#routeHits]:find("z=" .. z, 1, true) then
			break
		end
	end
end
check(#routeHits == 0, "3. avatar + 1/3/12 pets (linhas a 0, ±4, ±8, ±12 e ±16 studs do centro) atravessam do portão ao portal sem bater em nada além das fileiras " .. table.concat(routeHits, "; "))
local pillarGap = math.huge
for _, d in path:GetDescendants() do
	if d:IsA("BasePart") and d.Name == "PathPillar" then
		local minP, maxP = box(d)
		local inner = if d.CFrame.Position.Z > 0 then minP.Z else -maxP.Z
		pillarGap = math.min(pillarGap, inner)
	end
end
check(pillarGap >= 86 / 2 - rules.PillarDepth - 0.01, string.format("3. pilares não estreitam a avenida: entram no máximo %d studs (avenida livre de %.0f studs)", rules.PillarDepth, pillarGap * 2))

-- ── 4. Limites ──────────────────────────────────────────────────────────────
local outside = {}
for _, segment in segments do
	local model = stageModels[segment.Id]
	local half = segment.Width / 2
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local minP, maxP = box(d)
			if minP.X < segment.AreaStart - 0.2 or maxP.X > segment.End + 0.2 or math.max(math.abs(minP.Z), math.abs(maxP.Z)) > half + layout.SideThickness + 1.01 then
				table.insert(outside, segment.Id .. ":" .. d.Name)
			end
		end
	end
end
check(#outside == 0, "4. nada da fundação sai do próprio trecho nem passa das paredes " .. table.concat(outside, ", "))

-- ── 5. Transições e silhueta ────────────────────────────────────────────────
local function sectionParts(model, name, fromX, toX)
	local list = {}
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") and d.Name == name and d.CFrame.Position.X > fromX and d.CFrame.Position.X < toX then
			table.insert(list, d)
		end
	end
	return list
end
local function close(a: Color3, b: Color3): boolean
	return math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B) < 0.02
end
local transitionOk = true
for index = 1, #segments - 1 do
	local segment = segments[index]
	local model = stageModels[segment.Id]
	local theme = CorridorThemes.For(segment.Id)
	local nextTheme = CorridorThemes.For(segments[index + 1].Id)
	local third = (segment.Barrier - segment.AreaStart) / 3
	local first = sectionParts(model, "PathFloor", segment.AreaStart, segment.AreaStart + third)
	local last = sectionParts(model, "PathFloor", segment.AreaStart + 2 * third, segment.Barrier)
	local tail = sectionParts(model, "PathLanding", segment.Barrier, segment.End)
	local lanesFirst = sectionParts(model, "PathLane", segment.AreaStart, segment.AreaStart + third)
	local lanesLast = sectionParts(model, "PathLane", segment.AreaStart + 2 * third, segment.Barrier)
	local nextFirst, nextLast = 0, 0
	for _, p in lanesFirst do
		nextFirst += if p:GetAttribute("NextTheme") then 1 else 0
	end
	for _, p in lanesLast do
		nextLast += if p:GetAttribute("NextTheme") then 1 else 0
	end
	local expectedLast = (theme.Floor.Color :: Color3):Lerp(nextTheme.Floor.Color :: Color3, rules.Blend[3])
	local ok = #first == 2 and close(first[1].Color, theme.Floor.Color) and first[1].Material == theme.Floor.Material
		and #last == 2 and close(last[1].Color, expectedLast) and last[1].Material == theme.Floor.Material
		and #tail == 1 and tail[1].Material == nextTheme.Lane.Material
		and nextFirst == 0 and nextLast >= 1 and nextLast < #lanesLast
	if not ok then
		transitionOk = false
		print(string.format("      %s: piso1 %d, piso3 %d, pouso %d, placas do próximo no terço 1=%d terço 3=%d/%d", segment.Id, #first, #last, #tail, nextFirst, nextLast, #lanesLast))
	end
end
check(transitionOk, "5. transição em degraus: terço 1 no tema puro; terço 3 com 35% do próximo (cor) e parte das placas da faixa já no próximo; zona de decisão no material do próximo")
local heights = {}
local distinct = {}
local silhouetteOk = true
for _, segment in segments do
	local walls = {}
	for _, d in stageModels[segment.Id]:GetChildren() do
		if d.Name == "PathWall" and d.CFrame.Position.Z > 0 then
			table.insert(walls, d)
		end
	end
	table.sort(walls, function(a, b)
		return a.CFrame.Position.X < b.CFrame.Position.X
	end)
	local profile = CorridorThemes.For(segment.Id).Profile
	if #walls ~= 4 then
		silhouetteOk = false
	end
	local changes = 0
	for k, wall in walls do
		distinct[wall.Size.Y] = true
		if math.abs(wall.Size.Y - profile[k]) > 0.01 then
			silhouetteOk = false
		end
		if k > 1 and wall.Size.Y ~= walls[k - 1].Size.Y then
			changes += 1
		end
	end
	if changes < 2 then
		silhouetteOk = false
	end
	heights[segment.Id] = walls
end
local distinctCount = 0
for _ in distinct do
	distinctCount += 1
end
check(silhouetteOk and distinctCount >= 8, string.format("5. silhueta: 4 alturas de parede por trecho (perfil do tema), muda ao menos 2 vezes por trecho; %d alturas diferentes no corredor", distinctCount))
local pillarsOk = true
for _, d in path:GetDescendants() do
	if d.Name == "PathPillar" then
		local wallTop = 0
		for _, wall in path:GetDescendants() do
			if wall.Name == "PathWall" and math.abs(wall.CFrame.Position.X - d.CFrame.Position.X) < wall.Size.X / 2 and math.sign(wall.CFrame.Position.Z) == math.sign(d.CFrame.Position.Z) then
				wallTop = wall.Size.Y
			end
		end
		if d.Size.Y <= wallTop then
			pillarsOk = false
		end
	end
end
check(pillarsOk, "5. pilares mais altos que a parede (quebram a linha reta | | | |)")
local materialsOk = true
local seen = {}
for _, segment in segments do
	local key = tostring(CorridorThemes.For(segment.Id).Wall.Material) .. tostring(CorridorThemes.For(segment.Id).Lane.Material)
	seen[key] = (seen[key] or 0) + 1
end
local combos = 0
for _ in seen do
	combos += 1
end
materialsOk = combos >= 8
check(materialsOk, string.format("5. estágios não diferem só por cor: %d combinações parede/faixa de MATERIAL em 10 estágios", combos))

-- ── 6. Barreiras e pads intocados ───────────────────────────────────────────
local barriersOk = true
local padsOk = true
for index, segment in segments do
	local stage = WallConfig.Stages[index]
	local count = 0
	for _, d in path:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("Wall") == true and d:GetAttribute("StageId") == stage.Id then
			count += 1
			local row = d:GetAttribute("Row")
			local expectedX = segment.Barrier + (row - 0.5) * layout.RowThickness + (row - 1) * layout.RowGap
			if math.abs(d.CFrame.Position.X - expectedX) > 1e-6 or d.Size ~= V3.new(layout.RowThickness, segment.Height, segment.Width) or math.abs(d.CFrame.Position.Z) > 1e-6 or not d.CanCollide then
				barriersOk = false
			end
		end
	end
	if count ~= stage.Rows then
		barriersOk = false
	end
	local half = segment.Width / 2
	for padIndex in stage.Pads do
		local pad = path:FindFirstChild("WinPad_" .. stage.Id .. "_" .. padIndex, true)
		local z = (padIndex - (#stage.Pads + 1) / 2) * layout.PadSpacing
		if not pad or (pad.CFrame.Position - V3.new(segment.PadsX, 0.5, z)).Magnitude > 1e-3 or pad.CanCollide then
			padsOk = false
			print("      pad " .. stage.Id .. "_" .. padIndex .. " fora do lugar")
		end
		if pad then
			for _, y in { 1.5, 4, 8 } do
				local hit = solidAt(pad.CFrame.Position + V3.new(0, y, 0), true)
				if hit then
					padsOk = false
					print("      " .. hit.Name .. " em cima do pad " .. stage.Id)
				end
			end
		end
	end
	local back = path:FindFirstChild("ReturnPad_" .. stage.Id, true)
	if not back or (back.CFrame.Position - V3.new(segment.ReturnX, 0.5, half - layout.PadSize)).Magnitude > 1e-3 then
		padsOk = false
		print("      voltar " .. stage.Id .. " fora do lugar")
	end
	-- Moldura da zona de decisão em volta de todos os pads.
	local frames = sectionParts(stageModels[stage.Id], "PathDecisionFrame", segment.Barrier, segment.End)
	if #frames ~= 4 then
		padsOk = false
		print("      moldura " .. stage.Id .. ": " .. #frames)
	end
end
check(barriersOk, "6. barreiras intocadas: mesmas fileiras, posição, tamanho, colisão (WallService/WallController inalterados)")
check(padsOk, "6. pads de vitória, x2 e Voltar nos mesmos lugares, sem nada sólido em cima, dentro da moldura da zona de decisão")

-- ── 7. Portal e estágio 10 ──────────────────────────────────────────────────
local portal = path:FindFirstChild("NextWorldPortal", true)
local prompts = 0
for _, d in path:GetDescendants() do
	if d:IsA("ProximityPrompt") or d:IsA("ClickDetector") or d:IsA("BaseScript") then
		prompts += 1
	end
end
check(portal and math.abs(portal.CFrame.Position.X - (finalEnd - 4)) < 1e-6 and prompts == 0 and portal:GetAttribute("Teleport") == nil, "7. portal futuro preservado no fim da faixa, inerte (sem prompt, script ou teleporte)")
local slotsOk = true
for _, segment in segments do
	local slots = {}
	for _, d in stageModels[segment.Id]:GetDescendants() do
		if d:IsA("Attachment") and d.Name == "LandmarkSlot" then
			table.insert(slots, d)
		end
	end
	if #slots ~= rules.LandmarkSlots then
		slotsOk = false
	end
	for _, slot in slots do
		local world = (slot.Parent.CFrame * CF.new(slot.Position)).Position
		if math.abs(world.Z) < rules.SafeLaneHalf + 4 or math.abs(world.Z) > segment.Width / 2 then
			slotsOk = false
		end
	end
end
check(slotsOk, "7. dois slots de landmark por estágio (Attachment), fora da safe lane e dentro das paredes — Fases B–E")
local colossus = segments[10]
check(colossus.Width > segments[9].Width * 1.5 and colossus.Barrier - colossus.AreaStart >= 170 and CorridorThemes.For("Colossus").Profile[3] >= 60, string.format("7. estágio 10 com espaço para o Colosso: %.0f de largura, área de %.0f, paredes até %d", colossus.Width, colossus.Barrier - colossus.AreaStart, CorridorThemes.For("Colossus").Profile[3]))

-- ── 8. Decoração global fora do corredor ────────────────────────────────────
local intruders = {}
-- Meia largura do corredor (com a parede) em cada X; a boca (portão e
-- paredões do lobby) fica antes de StartX + 20.
local function halfAt(x)
	for _, segment in segments do
		if x >= segment.AreaStart and x < segment.End then
			return segment.Width / 2 + layout.SideThickness
		end
	end
	return colossus.Width / 2 + layout.SideThickness
end
for _, d in world:GetDescendants() do
	if d:IsA("BasePart") and not d:IsDescendantOf(path) then
		local minP, maxP = box(d)
		local x = math.clamp(d.CFrame.Position.X, layout.StartX + 20, finalEnd)
		local widest = halfAt(x)
		local inX = maxP.X > layout.StartX + 20 and minP.X < finalEnd
		local inZ = maxP.Z > -widest and minP.Z < widest
		local inY = maxP.Y > 0.5 and minP.Y < 90
		if inX and inZ and inY then
			table.insert(intruders, string.format("%s (%.0f, %.0f, %.0f)", d.Name, d.CFrame.Position.X, d.CFrame.Position.Y, d.CFrame.Position.Z))
		end
	end
end
check(#intruders == 0, "8. nenhuma decoração global (ilha do céu, árvore, pedra, nuvem baixa) dentro do corredor " .. table.concat(intruders, ", "))

-- ── 9. Orçamento ────────────────────────────────────────────────────────────
local parts, instances, lights, emitters = 0, #path:GetDescendants(), 0, 0
local decorParts = 0
local lightKinds = {}
local emitterList = {}
for _, d in path:GetDescendants() do
	if d:IsA("BasePart") then
		parts += 1
		if d:GetAttribute("Decor") ~= nil then
			decorParts += 1
		end
	elseif d:IsA("Light") then
		lights += 1
		local owner = d.Parent and d.Parent.Name or "?"
		owner = string.match(owner, "^Arch_") and "arco" or owner
		lightKinds[owner] = (lightKinds[owner] or 0) + 1
	elseif d:IsA("ParticleEmitter") then
		emitters += 1
		table.insert(emitterList, d)
	end
end
local kinds = {}
for name, n in lightKinds do
	table.insert(kinds, name .. " " .. n)
end
check(parts - decorParts <= 1250, string.format("9. orçamento da fundação (Fase A): %d peças fora do cenário — meta 1.100–1.250", parts - decorParts))
-- Peças de cenário por fase (Fase B: 1–3; Fase C: 4–6).
local phaseOf = { Wood = "B", Ruins = "B", Ice = "B", Crystal = "C", Gold = "C", Ancient = "C", Volcanic = "D", Magma = "D", Tech = "D" }
local decorPhase = { B = 0, C = 0, D = 0 }
for _, d in path:GetDescendants() do
	if d:IsA("BasePart") and d:GetAttribute("Decor") ~= nil then
		local stage = d:FindFirstAncestorWhichIsA("Model")
		stage = stage and stage.Parent
		local id = stage and stage:GetAttribute("StageId")
		local phase = id and phaseOf[id] or "?"
		decorPhase[phase] = (decorPhase[phase] or 0) + 1
	end
end
check(decorPhase.B >= 80 and decorPhase.B <= 130, string.format("9. orçamento da Fase B (1–3): +%d peças de cenário (meta 80–110, teto 130)", decorPhase.B))
check(decorPhase.C >= 90 and decorPhase.C <= 130, string.format("9. orçamento da Fase C (4–6): +%d peças de cenário (meta 90–115, teto 130)", decorPhase.C))
check(decorPhase.D >= 105 and decorPhase.D <= 150 and parts <= 1500 and decorParts == decorPhase.B + decorPhase.C + decorPhase.D, string.format("9. orçamento da Fase D (7–9): +%d peças de cenário (meta 105–135, teto 150); corredor com %d peças (%d instâncias) — abaixo de 1.500, reserva para o Colosso (final ≈ 1.600, teto 1.700)", decorPhase.D, parts, instances))
check(lights <= 16, string.format("9. PointLights no corredor: %d (eram 103; Fases B, C e D não adicionam; meta final ≤ 40) — %s", lights, table.concat(kinds, ", ")))
-- Emissores: poucos, só onde o tema pede, desligados no servidor, com tag
-- (o PowerPathEnvironmentController liga perto da câmera).
local emitterStages = { Ice = 2, Crystal = 1, Ancient = 1, Volcanic = 2, Magma = 1, Tech = 1 }
local emitterCount = {}
local emittersOk = emitters <= 9
for _, emitter in emitterList do
	local owner = emitter.Parent
	local stage = owner and owner:FindFirstAncestorWhichIsA("Model")
	stage = stage and stage.Parent
	local id = stage and stage:GetAttribute("StageId")
	emitterCount[id or "?"] = (emitterCount[id or "?"] or 0) + 1
	if emitter.Enabled or not emitter:HasTag("PowerPathAmbient") or not owner or owner:GetAttribute("Decor") == nil or not id or not emitterStages[id] or emitter.Rate > 10 then
		emittersOk = false
		print("      emissor fora da regra: " .. emitter:GetFullName())
	end
end
for id, max in emitterStages do
	if (emitterCount[id] or 0) > max then
		emittersOk = false
	end
end
check(emittersOk, string.format("9. ParticleEmitters fixos: %d (≤ 9: gelo 2, cristal 1, brasas do 6 1, fumaça+brasas do 7 2, faíscas do 8 1, motes do 9 1; desligados no servidor, tag PowerPathAmbient, taxa baixa)", emitters))

-- ── 10. Fases B e C: cenário dos estágios 1–6 ───────────────────────────────
local themed = { Wood = true, Ruins = true, Ice = true, Crystal = true, Gold = true, Ancient = true, Volcanic = true, Magma = true, Tech = true }
local decorBy = {}
for _, segment in segments do
	local decor = stageModels[segment.Id]:FindFirstChild("Decor")
	local list = {}
	if decor then
		for _, d in decor:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(list, d)
			end
		end
	end
	decorBy[segment.Id] = list
end
local function overlaps(minP, maxP, lo, hi)
	return maxP.X > lo.X and minP.X < hi.X and maxP.Y > lo.Y and minP.Y < hi.Y and maxP.Z > lo.Z and minP.Z < hi.Z
end
local function kindsIn(list, fromX, toX)
	local found = {}
	for _, d in list do
		local x = d.CFrame.Position.X
		if x >= fromX and x <= toX then
			found[d:GetAttribute("Decor")] = true
		end
	end
	return found
end
local landmarkOk, onlyThemed = true, true
local counts = {}
for _, segment in segments do
	local list = decorBy[segment.Id]
	counts[segment.Id] = #list
	if themed[segment.Id] then
		local landmarks, tall = 0, 0
		for _, d in list do
			if d:GetAttribute("Landmark") == true then
				landmarks += 1
				local _, maxP = box(d)
				tall = math.max(tall, maxP.Y)
			end
			if not d.Name:find("^PathDecor_") or type(d:GetAttribute("Decor")) ~= "string" then
				landmarkOk = false
			end
		end
		if landmarks < 3 or tall < 24 then
			landmarkOk = false
			print(string.format("      %s: %d peças de landmark, a mais alta até y %.0f", segment.Id, landmarks, tall))
		end
	elseif #list > 0 or stageModels[segment.Id]:FindFirstChild("Decor") then
		onlyThemed = false
	end
end
check(landmarkOk, string.format("10. landmark nos estágios 1–3 (peças marcadas Landmark, acima de y 24): floresta %d, ruínas %d, gelo %d peças de cenário", counts.Wood, counts.Ruins, counts.Ice))
check(landmarkOk, string.format("10. landmark nos estágios 4–6 (peças marcadas Landmark, acima de y 24): cristal %d, ouro %d, ancestral %d peças de cenário", counts.Crystal, counts.Gold, counts.Ancient))
check(landmarkOk, string.format("10. landmark nos estágios 7–9 (peças marcadas Landmark, acima de y 24): vulcânico %d, magma %d, energia %d peças de cenário", counts.Volcanic, counts.Magma, counts.Tech))
check(onlyThemed, "10. estágio 10 (Colosso) ainda sem cenário (Fase E); o 9 só PREPARA a chegada")
check(counts.Wood >= 20 and counts.Wood <= 40 and counts.Ruins >= 25 and counts.Ruins <= 45 and counts.Ice >= 30 and counts.Ice <= 50 and counts.Wood < counts.Ice and counts.Ruins <= counts.Ice, string.format("10. orçamento por estágio (guia 25–35 / 30–40 / 35–45) e intensidade subindo até o gelo: %d / %d / %d", counts.Wood, counts.Ruins, counts.Ice))
check(counts.Crystal >= 25 and counts.Crystal <= 45 and counts.Gold >= 25 and counts.Gold <= 45 and counts.Ancient >= 22 and counts.Ancient <= 45, string.format("10. orçamento por estágio da Fase C (guia 30–40 cada, sem landmark de 80 peças): %d / %d / %d", counts.Crystal, counts.Gold, counts.Ancient))
-- Nenhum landmark gasta o orçamento sozinho.
check(counts.Volcanic >= 25 and counts.Volcanic <= 50 and counts.Magma >= 30 and counts.Magma <= 50 and counts.Tech >= 35 and counts.Tech <= 55 and counts.Volcanic <= counts.Magma and counts.Magma <= counts.Tech, string.format("10. orçamento por estágio da Fase D (guia 30–40 / 35–45 / 40–50) e intensidade subindo 7 ≤ 8 ≤ 9: %d / %d / %d", counts.Volcanic, counts.Magma, counts.Tech))
local heavy = {}
for _, segment in segments do
	local perKind = {}
	for _, d in decorBy[segment.Id] do
		if d:GetAttribute("Landmark") == true then
			local key = d:GetAttribute("Decor")
			perKind[key] = (perKind[key] or 0) + 1
		end
	end
	for key, n in perKind do
		if n > 20 then
			table.insert(heavy, segment.Id .. ":" .. key .. " " .. n)
		end
	end
end
check(#heavy == 0, "10. landmarks eficientes (≤ 20 peças por tipo de landmark no estágio) " .. table.concat(heavy, ", "))
-- Neon é ACENTO: peças finas (veio, runa, fissura) com pouca área visível.
local neonOk, neonInfo = true, {}
local function face(d)
	local a, b, c = d.Size.X, d.Size.Y, d.Size.Z
	return a * b + b * c + a * c
end
for _, segment in segments do
	local neonArea, totalArea = 0, 0
	for _, d in decorBy[segment.Id] do
		totalArea += face(d)
		if d.Material == Enum.Material.Neon then
			-- A área de uma linha fina é o comprimento × a espessura visível.
			local smallest = math.min(d.Size.X, d.Size.Y, d.Size.Z)
			local longest = math.max(d.Size.X, d.Size.Y, d.Size.Z)
			neonArea += longest * math.max(smallest, 0.5) * 2
			if smallest > 0.6 then
				neonOk = false
				print("      Neon largo demais: " .. d.Name)
			end
		end
	end
	if totalArea > 0 then
		local share = neonArea / totalArea
		table.insert(neonInfo, string.format("%s %.1f%%", segment.Id, share * 100))
		if share > 0.05 then
			neonOk = false
		end
	end
end
check(neonOk, "10. Neon só como acento (linhas finas ≤ 0,6 stud, ≤ 5% da área do cenário de cada estágio): " .. table.concat(neonInfo, ", "))

-- Regras de posição do cenário.
local laneHits, frontHits, rowHits, padHits, cameraHits = {}, {}, {}, {}, {}
for _, segment in segments do
	local half = segment.Width / 2
	local stage = WallConfig.Stages[segment.Index]
	for _, d in decorBy[segment.Id] do
		local minP, maxP = box(d)
		local label = string.format("%s (%.0f, %.0f, %.0f)", d.Name, d.CFrame.Position.X, d.CFrame.Position.Y, d.CFrame.Position.Z)
		-- Safe lane (só peças rentes ao chão, topo < 0,3).
		if overlaps(minP, maxP, V3.new(-math.huge, 0.3, -rules.SafeLaneHalf), V3.new(math.huge, 14, rules.SafeLaneHalf)) then
			table.insert(laneHits, label)
		end
		-- Frente da barreira: placa de HP (x = face - 1,5; |z| ≤ 33 + 5) e o golpe.
		if overlaps(minP, maxP, V3.new(segment.Barrier - 12, 0.3, -38), V3.new(segment.Barrier, 14, 38)) then
			table.insert(frontHits, label)
		end
		-- Dentro das fileiras (a moldura fica nas bordas ou acima de y 30,5).
		if overlaps(minP, maxP, V3.new(segment.Barrier, -0.5, -half), V3.new(segment.Barrier + segment.Depth, segment.Height + 0.5, half)) then
			table.insert(rowHits, label)
		end
		-- Pads (pegada + 1 stud, até 10 de altura).
		local pads = {}
		for padIndex in stage.Pads do
			table.insert(pads, V3.new(segment.PadsX, 0, (padIndex - (#stage.Pads + 1) / 2) * layout.PadSpacing))
		end
		table.insert(pads, V3.new(segment.ReturnX, 0, half - layout.PadSize))
		for _, c in pads do
			local r = layout.PadSize / 2 + 1
			if overlaps(minP, maxP, c + V3.new(-r, 0.3, -r), c + V3.new(r, 10, r)) then
				table.insert(padHits, label)
			end
		end
		-- Câmera de 3ª pessoa chegando na barreira: nada sobre a faixa entre
		-- y 14 e 24 nos 40 studs antes dela (placa de HP, espada e Corte à vista).
		if overlaps(minP, maxP, V3.new(segment.Barrier - 40, 14, -rules.SafeLaneHalf), V3.new(segment.Barrier, 24, rules.SafeLaneHalf)) then
			table.insert(cameraHits, label)
		end
	end
end
check(#laneHits == 0, "10. cenário fora da safe lane (±18 até y 14) " .. table.concat(laneHits, ", "))
check(#frontHits == 0, "10. frente da barreira livre (placa de HP, espada, CutFx: x ∈ [B-12, B], |z| < 38) " .. table.concat(frontHits, ", "))
check(#rowHits == 0, "10. nada do cenário dentro das fileiras (molduras nas bordas ou acima da barreira) " .. table.concat(rowHits, ", "))
check(#padHits == 0, "10. nada do cenário sobre os pads de vitória / Voltar " .. table.concat(padHits, ", "))
check(#cameraHits == 0, "10. câmera chegando na barreira sem nada sobre a faixa (y 14–24, 40 studs antes) " .. table.concat(cameraHits, ", "))

-- Molduras das barreiras e transições físicas.
local frames = { Wood = "BarrierRoots", Ruins = "RuinGate", Ice = "IceSeal", Crystal = "CrystalConduit", Gold = "TempleGate", Ancient = "AncientSeal", Volcanic = "VolcanicGate", Magma = "MagmaSeal", Tech = "EnergyContainment" }
local segmentById = {}
for _, segment in segments do
	segmentById[segment.Id] = segment
end
local framesOk = true
for id, kind in frames do
	local segment = segmentById[id]
	if not kindsIn(decorBy[id], segment.Barrier - 6, segment.Barrier + segment.Depth)[kind] then
		framesOk = false
		print("      sem moldura: " .. id)
	end
end
check(framesOk, "10. barreiras 1–9 emolduradas pelo tema (raízes, umbral, selo de gelo, pilares de cristal, portão do templo, selo ancestral, massa vulcânica, magma cristalizado, contenção de energia)")
local w, r, i = segments[1], segments[2], segments[3]
local thirdW, thirdR = (w.Barrier - w.AreaStart) / 3, (r.Barrier - r.AreaStart) / 3
local t12 = kindsIn(decorBy.Wood, w.AreaStart + 2 * thirdW, w.End)
local t12a = kindsIn(decorBy.Wood, w.AreaStart, w.AreaStart + 2 * thirdW)
local t23 = kindsIn(decorBy.Ruins, r.AreaStart + 2 * thirdR, r.Barrier)
local t23b = kindsIn(decorBy.Ruins, r.Barrier, r.End)
local t23a = kindsIn(decorBy.Ruins, r.AreaStart, r.AreaStart + 2 * thirdR)
local t34 = kindsIn(decorBy.Ice, i.Barrier, i.End)
check((t12.WorkedStone or t12.ColumnDrum) and not t12a.WorkedStone and not t12a.ColumnDrum, "10. transição 1→2 física: pedra trabalhada e tambor de coluna só no fim da floresta")
check(t23.RuinColumn and (t23.FrostPatch or t23.FrostCap) and (t23b.IceCrust or t23b.IceShard) and not t23a.FrostPatch and not t23a.IceCrust, "10. transição 2→3 física: pedra → frost (terço 3) → gelo (depois da barreira 2)")
check(t34.CrystalHint and not kindsIn(decorBy.Ice, i.AreaStart, i.Barrier).CrystalHint, "10. indício do estágio 4 só depois da barreira 3 (discreto)")
-- Fase C: transições físicas 3→4, 4→5, 5→6 e o primeiro calor do 7.
local function parts3(id)
	local seg = segmentById[id]
	local third = (seg.Barrier - seg.AreaStart) / 3
	return kindsIn(decorBy[id], seg.AreaStart, seg.AreaStart + third), kindsIn(decorBy[id], seg.AreaStart, seg.AreaStart + 2 * third), kindsIn(decorBy[id], seg.AreaStart + 2 * third, seg.End)
end
local c1, c12, c3 = parts3("Crystal")
local g1, g12, g3 = parts3("Gold")
local _, a12, a3 = parts3("Ancient")
check(c1.FrostCrystal and not c3.FrostCrystal, "10. transição 3→4 física: gelo com ponta de cristal só no começo do cristal (o gelo vira mineral)")
check((c3.GoldBracket or c3.TempleBlock) and not c12.GoldBracket and not c12.TempleBlock and g1.GoldRemnant, "10. transição 4→5: pedestais/cintas de ouro só no fim do cristal; resto de cristal num berço de ouro no começo do templo")
check(g3.AncientBlock and not g12.AncientBlock and g12.GoldenPortico, "10. transição 5→6: blocos ancestrais com runa só no fim do templo (o ouro diminui)")
local lava = false
for _, d in decorBy.Ancient do
	if d.Material == Enum.Material.CrackedLava then
		lava = true
	end
end
check((a3.HeatFissure or a3.EmberVent) and not a12.HeatFissure and not a12.EmberVent and not lava, "10. primeiro calor do 7 só no fim do 6 (fissuras e brasas, sem lava)")
-- Fase D: 6→7, 7→8, 8→9 e 9→área do 10.
local v1, v12, v3 = parts3("Volcanic")
local m1, m12, m3 = parts3("Magma")
local t1, t12, t3 = parts3("Tech")
check(v1.HeatFissure and v12.VolcanicCliff and not v12.MagmaShard and not v12.MagmaFormation, "10. transição 6→7: o calor do 6 continua no começo do 7 e vira rocha vulcânica (paredões no meio, sem cristal vermelho)")
check(v3.MagmaShard and m1.LavaCrack and m1.MagmaShard and not m3.MagmaShard and m12.MagmaFormation, "10. transição 7→8: fissuras crescem, o primeiro cristal vermelho rompe o basalto no fim do 7 e o magma domina o 8")
check(m3.DarkCrystal and m3.EnergyLine and not m12.DarkCrystal and not m12.EnergyLine and t1.DarkCrystal and t1.EnergyCircuit, "10. transição 8→9: o cristal escurece e a linha de energia fria substitui a fissura térmica")
local tTail = kindsIn(decorBy.Tech, segmentById.Tech.Barrier + segmentById.Tech.Depth, segmentById.Tech.End)
local pylonsTall = true
for _, d in decorBy.Tech do
	if d:GetAttribute("Decor") == "OpeningPylon" and d.Material ~= Enum.Material.Neon then
		local _, maxP = box(d)
		if maxP.Y <= CorridorThemes.For("Tech").Profile[4] + 8 then
			pylonsTall = false
		end
	end
end
check(tTail.OpeningPylon and tTail.ConvergenceLines and pylonsTall and #decorBy.Colossus == 0, "10. pré-10: depois da Barreira 9, pilones MAIS ALTOS que as paredes e energia convergindo para frente — e nada construído no 10")

-- Cenário estático: sem script, sem prompt, sem luz.
local staticOk = true
for _, list in decorBy do
	for _, d in list do
		if not d.Anchored or d.CanTouch or d:FindFirstChildWhichIsA("Light") or d:FindFirstChildWhichIsA("BaseScript") or d:FindFirstChildWhichIsA("ProximityPrompt") then
			staticOk = false
		end
	end
end
check(staticOk, "10. cenário estático: ancorado, sem toque, sem luz, sem script (nenhum loop novo)")

-- O controlador dos emissores: liga só perto da câmera e sem "Efeitos reduzidos".
do
	local Sig = { Connect = function()
		return { Disconnect = function() end }
	end }
	E.stubs.CollectionService = {
		GetTagged = function(_, tag)
			return if tag == "PowerPathAmbient" then emitterList else {}
		end,
		GetInstanceAddedSignal = function()
			return Sig
		end,
		GetInstanceRemovedSignal = function()
			return Sig
		end,
	}
	local settings = { ReducedEffects = false }
	E.stubModules["StarterPlayer.Client.Controllers.DataController"] = { Get = function(k)
		return if k == "Settings" then settings else nil
	end, Changed = Sig }
	local camera = { CFrame = CF.new(i.AreaStart + 40, 8, 0) }
	E.stubs.Workspace = setmetatable({ CurrentCamera = camera }, { __index = E.Workspace })
	local Env = E.require(E.Client.Controllers.PowerPathEnvironmentController)
	Env.Init()
	-- Cada emissor liga com a câmera perto dele, e só os perto ligam.
	local eachOk, maxOn = true, 0
	for _, emitter in emitterList do
		camera.CFrame = CF.new(emitter.Parent.CFrame.Position + V3.new(0, 6, 0))
		local on = Env.Step()
		maxOn = math.max(maxOn, on)
		if not emitter.Enabled or on >= emitters then
			eachOk = false
			print("      não ligou sozinho: " .. emitter:GetFullName())
		end
	end
	settings.ReducedEffects = true
	local reducedOn = Env.Step()
	settings.ReducedEffects = false
	camera.CFrame = CF.new(w.AreaStart, 8, 0)
	local far = Env.Step()
	local source = require("@lune/fs").readFile(E.Root .. "/src/client/Controllers/PowerPathEnvironmentController.luau")
	local _, loops = string.gsub(source, "while true do", "")
	check(Env.Count() == emitters and emitters > 0 and eachOk and reducedOn == 0 and far == 0 and loops == 1 and not string.find(source, "RenderStepped", 1, true) and not string.find(source, "Heartbeat", 1, true) and not string.find(source, "Lighting", 1, true),
		string.format("10. VFX ambiental LOCAL (gelo, cristal, brasas, fumaça, faíscas, motes): cada um liga só perto (no máx. %d juntos), apaga com Efeitos reduzidos (%d) e longe (%d); 1 loop só, sem quadro a quadro, sem Lighting", maxOn, reducedOn, far))
	-- Um sistema só: nenhum controlador de ambiente por estágio.
	local fs = require("@lune/fs")
	local envControllers = {}
	for _, name in fs.readDir(E.Root .. "/src/client/Controllers") do
		if string.find(name, "^PowerPath") or string.find(name, "^Crystal") or string.find(name, "^Gold") or string.find(name, "^Ancient") then
			table.insert(envControllers, name)
		end
	end
	check(#envControllers == 1 and envControllers[1] == "PowerPathEnvironmentController.luau", "10. um único controlador de ambiente do Caminho (sem CrystalController/GoldController/AncientController): " .. table.concat(envControllers, ", "))
end

if #problems > 0 then
	print(#problems .. " problema(s).")
	process.exit(1)
end
print("OK: fundação do Caminho do Poder — 10 trechos, faixa central, transições, safe lane, barreiras/pads/portal intocados, sem decoração invasora.")
print("REQUER VALIDAÇÃO NO ROBLOX STUDIO: escala, materiais, luz e leitura em 3ª pessoa; pets reais seguindo o jogador.")
process.exit(0)
