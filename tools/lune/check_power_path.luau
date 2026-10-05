--[[
	check_power_path.luau — FUNDAÇÃO do Caminho do Poder (Fase A).

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
	  9. orçamento: peças, PointLights e emissores do corredor.

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
-- centro, ±4, ±12, ±30 e ±34 (jogador colado na parede com pets ao lado).
local function blockedAt(p)
	return solidAt(p, true)
end
local routeHits = {}
for _, z in { 0, -4, 4, -12, 12, -30, 30, -34, 34 } do
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
check(#routeHits == 0, "3. avatar + 1/3/12 pets (linhas a 0, ±4, ±12, ±30 e ±34 studs do centro) atravessam do portão ao portal sem bater em nada além das fileiras " .. table.concat(routeHits, "; "))
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
local lightKinds = {}
for _, d in path:GetDescendants() do
	if d:IsA("BasePart") then
		parts += 1
	elseif d:IsA("Light") then
		lights += 1
		local owner = d.Parent and d.Parent.Name or "?"
		owner = string.match(owner, "^Arch_") and "arco" or owner
		lightKinds[owner] = (lightKinds[owner] or 0) + 1
	elseif d:IsA("ParticleEmitter") then
		emitters += 1
	end
end
local kinds = {}
for name, n in lightKinds do
	table.insert(kinds, name .. " " .. n)
end
check(parts <= 1250, string.format("9. orçamento da fundação: %d peças (%d instâncias) — meta da Fase A 1.100–1.250, final ≤ 1.600", parts, instances))
check(lights <= 20, string.format("9. PointLights no corredor: %d (eram 103; meta final ≤ 40) — %s", lights, table.concat(kinds, ", ")))
check(emitters == 0, "9. nenhum ParticleEmitter fixo (VFX ambiental fica para os temas, com LOD)")

if #problems > 0 then
	print(#problems .. " problema(s).")
	process.exit(1)
end
print("OK: fundação do Caminho do Poder — 10 trechos, faixa central, transições, safe lane, barreiras/pads/portal intocados, sem decoração invasora.")
print("REQUER VALIDAÇÃO NO ROBLOX STUDIO: escala, materiais, luz e leitura em 3ª pessoa; pets reais seguindo o jogador.")
process.exit(0)
