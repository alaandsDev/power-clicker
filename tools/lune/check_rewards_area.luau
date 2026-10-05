--[[
	check_rewards_area.luau — CENTRAL DO AVENTUREIRO (Missões + Prêmios),
	a área "Spawn" do LobbyConfig.

		lune run tools/lune/check_rewards_area.luau [raiz]

	Nasceu de um bug visto no Studio: piso branco vazio, quiosques nas pontas
	com toldo para fora do piso e uma árvore na frente do letreiro "Prêmios"
	(o clearOfLayout só protegia um CÍRCULO de raio 26, e o piso era um
	retângulo 76x26). Verifica:
	  1. piso: dentro do retângulo da config e a calçada da praça chega nele;
	  2. Missões (quadro) à esquerda de quem chega, Prêmios (baú) à direita,
	     cada uma inteira dentro do piso, mais baixa que o portão do Caminho;
	  3. um prompt de cada, o MESMO de antes (OpenPanel Quests / Rewards,
	     mesmas chaves), na peça da estrutura;
	  4. textos: só SurfaceGui (sem BillboardGui flutuando), presos na
	     própria estrutura, com distância limitada; nada na frente deles;
	  5. nenhuma árvore/pedra/objeto alheio sobre o piso (até a copa);
	  6. circulação: entrar → Missões → centro → Prêmios → sair, com folga
	     de avatar (e de pet atrás); centro livre;
	  7. orçamento: peças, nenhuma luz, quiosques antigos removidos.

	REQUER VALIDAÇÃO NO ROBLOX STUDIO: leitura real das placas, ângulo dos
	prompts, pets seguindo o jogador.
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

local LobbyConfig = E.require(E.Shared.Config.LobbyConfig)
local WorldConfig = E.require(E.Shared.Config.WorldConfig)
local WorldBuilder = E.require(E.Server.World.WorldBuilder)
local world = WorldBuilder.Build(WorldConfig.Worlds[WorldConfig.DefaultWorld], V3.new(0, 0, 0), E.Instance.new("Folder"), E.Instance.new("Folder"), true)

local area = LobbyConfig.Areas.Spawn
local centre = area.Offset
local halfX, halfZ = area.FloorSize.X / 2, area.FloorSize.Y / 2
local function inFloor(p: any, margin: number): boolean
	return math.abs(p.X - centre.X) <= halfX + margin and math.abs(p.Z - centre.Z) <= halfZ + margin
end
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

-- ── 1. Piso ─────────────────────────────────────────────────────────────────
check(area.Floor == "Adventure" and area.FloorSize.X <= 70, string.format("1. piso da Central (%dx%d), não a praça branca 76x26 do antigo spawn", area.FloorSize.X, area.FloorSize.Y))
-- A calçada da praça termina em (raio da área - 2) do centro: tem de tocar o piso.
local walkwayEnd = centre.Magnitude - area.Radius + 2
local floorFront = centre.Magnitude - halfZ
check(walkwayEnd >= floorFront, string.format("1. a calçada da praça chega no piso (termina a %.0f; piso começa a %.0f)", walkwayEnd, floorFront))
local plaza = world:FindFirstChild("AdventurePlaza", true)
check(plaza and plaza:FindFirstChild("PlazaMedallion") and #plaza:GetChildren() > 0, "1. centro com medalhão, caminhos e placa de direção")

-- ── 2. Estações ─────────────────────────────────────────────────────────────
local quests = world:FindFirstChild("Station_Quests_Machine", true)
local rewards = world:FindFirstChild("Station_Rewards_Machine", true)
check(quests ~= nil and rewards ~= nil, "2. quadro de Missões e totem de Prêmios construídos")
if not (quests and rewards and plaza) then
	process.exit(1)
end
local function bounds(model)
	local minP, maxP = V3.new(math.huge, math.huge, math.huge), V3.new(-math.huge, -math.huge, -math.huge)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			for _, c in corners(d) do
				minP = V3.new(math.min(minP.X, c.X), math.min(minP.Y, c.Y), math.min(minP.Z, c.Z))
				maxP = V3.new(math.max(maxP.X, c.X), math.max(maxP.Y, c.Y), math.max(maxP.Z, c.Z))
			end
		end
	end
	return minP, maxP
end
local qMin, qMax = bounds(quests)
local rMin, rMax = bounds(rewards)
local pMin, pMax = bounds(plaza)
-- Quem chega pela calçada olha para +Z: a esquerda é +X.
check(qMin.X > centre.X + 4 and rMax.X < centre.X - 4, "2. Missões à ESQUERDA de quem chega (+X), Prêmios à direita (-X), sem invadir o centro")
local inside = true
for _, pair in { { "Missões", qMin, qMax }, { "Prêmios", rMin, rMax }, { "centro", pMin, pMax } } do
	if not (inFloor(pair[2], -0.5) and inFloor(pair[3], -0.5)) then
		inside = false
		print(string.format("      %s passa do piso: %s .. %s", pair[1], tostring(pair[2]), tostring(pair[3])))
	end
end
check(inside, "2. nada fora da plataforma (estruturas, placas, telhado e toldo dentro do piso, com folga)")
-- O portão do Caminho do Poder tem ~20 studs até a placa: a Central fica
-- bem abaixo (sistema secundário).
local tallest = math.max(qMax.Y, rMax.Y, pMax.Y)
check(tallest < 14, string.format("2. secundárias: até %.1f studs de altura (portão do Caminho ~20)", tallest))

-- ── 3. Prompts ──────────────────────────────────────────────────────────────
local prompts = {}
for _, d in world:GetDescendants() do
	if d:IsA("ProximityPrompt") then
		local panel = d:GetAttribute("OpenPanel")
		if panel == "Quests" or panel == "Rewards" then
			prompts[panel] = prompts[panel] or {}
			table.insert(prompts[panel], d)
		end
	end
end
local q, r = prompts.Quests and prompts.Quests[1], prompts.Rewards and prompts.Rewards[1]
check(prompts.Quests and #prompts.Quests == 1 and prompts.Rewards and #prompts.Rewards == 1, "3. um prompt de Missões e um de Prêmios no mundo (nenhum sistema duplicado)")
check(q and q.Parent.Name == "Station_Quests" and q.Parent:IsDescendantOf(quests) and q:GetAttribute("TextKey") == "world.prompt.quests" and q:GetAttribute("ObjectKey") == "menu.quests", "3. Missões: prompt de sempre (abre o painel Quests), no próprio quadro")
check(r and r.Parent.Name == "Station_Rewards" and r.Parent:IsDescendantOf(rewards) and r:GetAttribute("TextKey") == "world.prompt.rewards" and r:GetAttribute("ObjectKey") == "menu.rewards", "3. Prêmios: prompt de sempre (abre o painel Rewards), no próprio baú")

-- Sólidos sobre o piso (para circulação e para achar intrusos).
local solids = {}
for _, d in world:GetDescendants() do
	if d:IsA("BasePart") and d.CanCollide and inFloor(d.CFrame.Position, 12) and d.CFrame.Position.Y + d.Size.Y / 2 > 1.2 and d.CFrame.Position.Y < 60 then
		table.insert(solids, d)
	end
end
local AVATAR = 1.4 -- meia largura do avatar (R15 ~2,8 de ombro a ombro)
local function blocked(p)
	for _, part in solids do
		for _, offset in { V3.new(0, 0, 0), V3.new(AVATAR, 0, 0), V3.new(-AVATAR, 0, 0), V3.new(0, 0, AVATAR), V3.new(0, 0, -AVATAR) } do
			local lp = part.CFrame:PointToObjectSpace(p + offset)
			local h = part.Size / 2
			if math.abs(lp.X) <= h.X and math.abs(lp.Y) <= h.Y and math.abs(lp.Z) <= h.Z then
				return part
			end
		end
	end
	return nil
end
-- Ponto de uso: na frente da peça do prompt, ao alcance dele e livre.
local function usePoint(prompt)
	local part = prompt.Parent
	local look = part.CFrame.LookVector
	local flat = V3.new(look.X, 0, look.Z).Unit
	for distance = 2.5, 8, 0.5 do
		local p = V3.new(part.CFrame.Position.X, 3, part.CFrame.Position.Z) + flat * (part.Size.Z / 2 + distance)
		if not blocked(p) and (p - part.CFrame.Position).Magnitude <= prompt.MaxActivationDistance - 2 then
			return p
		end
	end
	return nil
end
local qUse, rUse = q and usePoint(q), r and usePoint(r)
check(qUse and rUse and inFloor(qUse, 0) and inFloor(rUse, 0), "3. cada prompt tem um lugar livre na frente, no piso e dentro do alcance (14 studs)")

-- ── 4. Textos ───────────────────────────────────────────────────────────────
local textsOk, guiCount = true, 0
for _, model in { quests, rewards, plaza } do
	local minP, maxP = bounds(model)
	for _, d in model:GetDescendants() do
		if d:IsA("BillboardGui") then
			textsOk = false
			print("      BillboardGui em " .. d:GetFullName())
		elseif d:IsA("SurfaceGui") then
			guiCount += 1
			local part = d.Parent
			local p = part.CFrame.Position
			local front = part.CFrame.LookVector
			if not (part:IsA("BasePart") and d.Face == Enum.NormalId.Front and d.MaxDistance > 0 and d.MaxDistance <= 120) then
				textsOk = false
				print("      SurfaceGui sem face/distância: " .. part.Name)
			end
			if p.X < minP.X or p.X > maxP.X or p.Z < minP.Z or p.Z > maxP.Z then
				textsOk = false
			end
			-- A placa olha para quem chega (-Z, para a praça).
			if front.Z > -0.7 then
				textsOk = false
				print("      placa virada para " .. tostring(front) .. ": " .. part.Name)
			end
			-- Nada sólido ou de folhagem entre a placa e quem olha de frente.
			for step = 1, 12 do
				local probe = p + front * (0.6 + step)
				for _, other in world:GetDescendants() do
					if other:IsA("BasePart") and other ~= part and not other:IsDescendantOf(model) and other.Transparency < 0.9 and other.CFrame.Position.Y > 1.2 then
						local lp = other.CFrame:PointToObjectSpace(probe)
						local h = other.Size / 2
						if math.abs(lp.X) <= h.X and math.abs(lp.Y) <= h.Y and math.abs(lp.Z) <= h.Z then
							textsOk = false
							print(string.format("      %s cobre a placa %s", other.Name, part.Name))
						end
					end
				end
			end
		elseif d:IsA("Light") then
			textsOk = false
			print("      luz em " .. d:GetFullName())
		end
	end
end
check(textsOk and guiCount >= 6, string.format("4. %d textos físicos (SurfaceGui), presos na estrutura, de frente para quem chega, sem nada na frente; nenhum BillboardGui nem luz", guiCount))
local function guiText(model, name)
	local part = model:FindFirstChild(name, true)
	local gui = part and part:FindFirstChildOfClass("SurfaceGui")
	local label = gui and gui:FindFirstChildOfClass("TextLabel")
	return label and label.Text
end
check(guiText(quests, "SignTitle") == "📋 MISSÕES" and guiText(quests, "SignSubtitle") == "COMPLETE DESAFIOS", "4. placa \"📋 MISSÕES / COMPLETE DESAFIOS\"")
check(guiText(rewards, "SignTitle") == "🎁 PRÊMIOS" and guiText(rewards, "SignSubtitle") == "COLETE SUAS RECOMPENSAS", "4. placa \"🎁 PRÊMIOS / COLETE SUAS RECOMPENSAS\" (nome do sistema: Prêmios)")

-- ── 5. Intrusos sobre o piso ────────────────────────────────────────────────
local intruders = {}
for _, d in world:GetDescendants() do
	if d:IsA("BasePart") and not d:IsDescendantOf(quests) and not d:IsDescendantOf(rewards) and not d:IsDescendantOf(plaza) then
		local list = corners(d)
		local top, bottom = -math.huge, math.huge
		for _, c in list do
			top, bottom = math.max(top, c.Y), math.min(bottom, c.Y)
		end
		if top > 1.2 and bottom < 40 then
			for _, c in list do
				if inFloor(c, 0) then
					table.insert(intruders, string.format("%s (%.0f, %.0f, %.0f)", d.Name, d.CFrame.Position.X, d.CFrame.Position.Y, d.CFrame.Position.Z))
					break
				end
			end
		end
	end
end
check(#intruders == 0, "5. nenhuma árvore, pedra ou objeto antigo sobre o piso (nem a copa) " .. table.concat(intruders, ", "))

-- ── 6. Circulação ───────────────────────────────────────────────────────────
local entrance = V3.new(centre.X, 3, centre.Z - halfZ - 1)
local middle = V3.new(centre.X, 3, centre.Z - 2)
local exit = V3.new(centre.X, 3, centre.Z - halfZ - 1)
local function walk(a, b)
	for step = 0, 60 do
		local p = a:Lerp(b, step / 60)
		local hit = blocked(p)
		if hit then
			return hit.Name
		end
	end
	return nil
end
local route = { { "entrada", entrance }, { "Missões", qUse }, { "centro", middle }, { "Prêmios", rUse }, { "saída", exit } }
local routeOk = true
for index = 1, #route - 1 do
	local a, b = route[index], route[index + 1]
	if not (a[2] and b[2]) then
		routeOk = false
	else
		local hit = walk(a[2], b[2])
		if hit then
			routeOk = false
			print(string.format("      %s → %s bate em %s", a[1], b[1], hit))
		end
	end
end
check(routeOk, "6. avatar real: entrar → Missões → centro → Prêmios → sair sem bater em nada")
-- Pet: segue o rastro do jogador, ~3 studs atrás e até 1,5 stud de lado.
local petOk = true
for index = 1, #route - 1 do
	local a, b = route[index][2], route[index + 1][2]
	if a and b then
		local dir = (b - a)
		if dir.Magnitude > 0.1 then
			for _, sign in { -1, 1 } do
				local side = V3.new(dir.Unit.Z, 0, -dir.Unit.X) * 1.5 * sign
				-- O pet fica ~3 studs atrás: não encosta no ponto de uso.
				local trim = dir.Unit * math.min(3, dir.Magnitude / 3)
				local hit = walk(a + trim + side, b - trim + side)
				if hit then
					petOk = false
					print(string.format("      pet %s → %s bate em %s", route[index][1], route[index + 1][1], hit))
				end
			end
		end
	end
end
check(petOk, "6. pet seguindo o rastro ao lado do jogador (±1,5 stud) também passa")
-- Centro livre: faixa de 16 studs no meio, da frente até o medalhão.
local freeOk = true
for x = -8, 8, 2 do
	for z = -halfZ + 1, 6, 2 do
		if blocked(V3.new(centre.X + x, 3, centre.Z + z)) then
			freeOk = false
		end
	end
end
check(freeOk, "6. corredor central livre (16 studs de largura, da borda até depois do medalhão)")

-- ── 7. Orçamento e restos ───────────────────────────────────────────────────
local parts = 0
local instances = 0
for _, model in { quests, rewards, plaza } do
	instances += #model:GetDescendants()
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
end
check(parts <= 110, string.format("7. orçamento: %d peças (%d instâncias) — Missões %d, Prêmios %d, centro %d", parts, instances, quests:GetAttribute("PartCount"), rewards:GetAttribute("PartCount"), plaza:GetAttribute("PartCount")))
local leftovers = {}
for _, d in world:GetDescendants() do
	if d:IsA("BasePart") and inFloor(d.CFrame.Position, 6) and (d.Name == "Canopy" or (d.Name == "Station_Quests" and d.Parent == world) or (d.Name == "Station_Rewards" and d.Parent == world)) then
		table.insert(leftovers, d.Name)
	end
end
check(#leftovers == 0, "7. quiosques antigos (balcão, toldo, billboard) removidos " .. table.concat(leftovers, ","))

if #problems > 0 then
	print(#problems .. " problema(s).")
	process.exit(1)
end
print("OK: Central do Aventureiro — Missões e Prêmios dentro do piso, prompts de sempre, textos livres, circulação limpa.")
print("REQUER VALIDAÇÃO NO ROBLOX STUDIO: leitura das placas, alcance dos prompts, pets seguindo o jogador.")
process.exit(0)
