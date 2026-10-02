--[[
	check_world.luau — roda o WorldBuilder de verdade fora do Studio e valida a
	geometria gerada do mundo inicial (o que o servidor publicado constrói).

		lune run tools/lune/check_world.luau [raiz]

	O que verifica (todas as medidas vêm dos configs, não de números soltos):
	  1. CHÃO       — chão sólido em toda a ilha (grade de 5 studs) e na boca
	                  do corredor; nenhum buraco.
	  2. BORDAS     — anel em volta da ilha (360°, 3 raios) é sólido em altura
	                  de personagem, exceto a boca do corredor: sem FRESTAS.
	  3. ESCALADA   — a borda mais baixa é muito mais alta que um pulo.
	  4. CAMINHO    — nada sólido na altura do peito no caminho da praça até o
	                  corredor.
	  5. SPAWN      — o marcador de spawn olha para a entrada do Caminho.
	  6. CORREDOR   — piso contínuo do lobby até o portal final; as 10
	                  barreiras existem, em linha reta (z = 0), em ordem.
	  7. PRAÇA FINAL— depois do portal há contenção sólida e alta em toda a
	                  largura; o portal fica de frente para o corredor, sem
	                  nada sólido na frente; moldura tangente ao anel.
	  8. MUNDOS     — todos os mundos do WorldConfig constroem sem erro (como
	                  no Studio com EnableAllWorldsInStudio = true).
	  + contagem de instâncias por classe (mundo inicial).

	Sai com código 1 se algum problema for encontrado.
]]
local process = require("@lune/process")
local fs = require("@lune/fs")
local E = require("./env")(process.args[1])
local V3 = E.roblox.Vector3

local WorldBuilder = E.require(E.Server.World.WorldBuilder)
local WorldConfig = E.require(E.Shared.Config.WorldConfig)
local WallConfig = E.require(E.Shared.Config.WallConfig)
local LobbyConfig = E.require(E.Shared.Config.LobbyConfig)

-- Raio da ilha: constante local do WorldBuilder, lida do próprio fonte.
local builderSource = fs.readFile(E.Root .. "/src/server/World/WorldBuilder.luau")
local ISLAND = tonumber(string.match(builderSource, "local GROUND_RADIUS = (%d+)")) or 150
local JUMP = 7.2 -- altura de um pulo do personagem padrão do Roblox

local problems = {}
local function fail(message: string)
	table.insert(problems, message)
end

-- ── Mundo inicial ───────────────────────────────────────────────────────────
local spawnsFolder = E.Instance.new("Folder")
local model = WorldBuilder.Build(WorldConfig.Worlds[WorldConfig.DefaultWorld], V3.new(0, 0, 0), E.Instance.new("Folder"), spawnsFolder, true)

local solids = {}
local named = {}
local byClass, total = {}, 0
for _, d in model:GetDescendants() do
	total += 1
	byClass[d.ClassName] = (byClass[d.ClassName] or 0) + 1
	if d:IsA("BasePart") then
		named[d.Name] = d
		if d.CanCollide then
			table.insert(solids, d)
		end
	end
end

local function inside(part, p)
	local lp = part.CFrame:PointToObjectSpace(p)
	local s = part.Size / 2
	return math.abs(lp.X) <= s.X + 1e-3 and math.abs(lp.Y) <= s.Y + 1e-3 and math.abs(lp.Z) <= s.Z + 1e-3
end
local function solidAt(p)
	for _, part in solids do
		if inside(part, p) then
			return part
		end
	end
	return nil
end

local L = WallConfig.Layout
local mouthHalf = L.Width / 2

-- 1. Chão
for x = -ISLAND, ISLAND, 5 do
	for z = -ISLAND, ISLAND, 5 do
		if x * x + z * z <= (ISLAND - 1) ^ 2 and not solidAt(V3.new(x, -0.5, z)) then
			fail(string.format("chão: buraco em (%d, %d)", x, z))
		end
	end
end
for x = ISLAND - 50, L.StartX + 50, 2 do
	if not solidAt(V3.new(x, -1, 0)) then
		fail("chão: buraco na boca do corredor x=" .. x)
		break
	end
end

-- 2. Bordas sem frestas
local rimPoints = 0
for degree = 0, 359 do
	local a = math.rad(degree)
	local direction = V3.new(math.cos(a), 0, math.sin(a))
	for _, radius in { ISLAND + 2, ISLAND + 10, ISLAND + 18 } do
		local p = direction * radius + V3.new(0, 4, 0)
		if not (p.X > 0 and math.abs(p.Z) <= mouthHalf) then
			rimPoints += 1
			if not solidAt(p) then
				fail(string.format("borda: fresta em %d°, r=%d", degree, radius))
				break
			end
		end
	end
end

-- 3. Escalada
local lowest = math.huge
for degree = 0, 359, 2 do
	local a = math.rad(degree)
	local p = V3.new(math.cos(a), 0, math.sin(a)) * (ISLAND + 6)
	if not (p.X > 0 and math.abs(p.Z) <= mouthHalf + 2) then
		local top = 0
		for y = 0, 160, 2 do
			if solidAt(p + V3.new(0, y, 0)) then
				top = y
			end
		end
		lowest = math.min(lowest, top)
	end
end
if lowest < JUMP * 6 then
	fail(string.format("escalada: borda com só %d studs", lowest))
end

-- 4. Caminho livre
local pathHalf = LobbyConfig.Path.Width / 2 - 2
for x = 46, L.StartX + 10, 2 do
	for _, z in { -pathHalf, -pathHalf / 2, 0, pathHalf / 2, pathHalf } do
		local blocker = solidAt(V3.new(x, 3, z))
		if blocker then
			fail(string.format("caminho: obstáculo em (%d, %.0f): %s", x, z, blocker.Name))
			break
		end
	end
end

-- 5. Spawn olhando para a entrada do Caminho
local spawnPart = spawnsFolder:GetChildren()[1]
local spawnDot = 0
if not spawnPart then
	fail("spawn: marcador não foi criado")
else
	local position = spawnPart.CFrame.Position
	local toGate = (V3.new(L.StartX, position.Y, 0) - position).Unit
	spawnDot = spawnPart.CFrame.LookVector:Dot(toGate)
	if spawnDot < 0.98 then
		fail(string.format("spawn: não olha para a entrada (dot %.2f)", spawnDot))
	end
end

-- 6. Corredor
local portal = named.NextWorldPortal
if not portal then
	fail("corredor: NextWorldPortal não existe")
else
	local endX = portal.CFrame.Position.X
	for x = 0, endX, 2 do
		for _, z in { -mouthHalf + 13, 0, mouthHalf - 13 } do
			if not solidAt(V3.new(x, -1, z)) then
				fail(string.format("corredor: sem piso em x=%d z=%d", x, z))
				break
			end
		end
	end
end
local lastX = -math.huge
for _, stage in WallConfig.Stages do
	local row = named["Wall_" .. stage.Id .. "_1"]
	if not row then
		fail("corredor: barreira ausente " .. stage.Id)
	else
		local p = row.CFrame.Position
		if p.X <= lastX then
			fail("corredor: fora de ordem " .. stage.Id)
		end
		if math.abs(p.Z) > 1e-6 or math.abs(p.Y - row.Size.Y / 2) > 1e-6 then
			fail("corredor: barreira fora da linha " .. stage.Id)
		end
		lastX = p.X
	end
end

-- 7. Praça final
if portal then
	local endX = portal.CFrame.Position.X
	local half = L.Width * L.FinalScale / 2
	for z = -half, half, 4 do
		local wall = nil
		for x = endX + 1, endX + 12 do
			wall = solidAt(V3.new(x, 12, z))
			if wall then
				break
			end
		end
		if not wall then
			fail(string.format("praça final: fim aberto em z=%.0f", z))
			break
		end
		if wall.CFrame.Position.Y + wall.Size.Y / 2 < 20 then
			fail(string.format("praça final: contenção baixa em z=%.0f", z))
		end
	end
	if math.abs(portal.CFrame.RightVector.X) < 0.99 then
		fail("praça final: portal não está de frente para o corredor")
	end
	for dx = 2, 20, 2 do
		if solidAt(portal.CFrame.Position - V3.new(dx, 0, 0)) then
			fail("praça final: algo sólido na frente do portal")
			break
		end
	end
	local worst = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Size == V3.new(4, 5, 15) then
			local radial = d.CFrame.Position - portal.CFrame.Position
			radial = V3.new(0, radial.Y, radial.Z).Unit
			worst = math.max(worst, math.abs(d.CFrame.LookVector:Dot(radial)))
		end
	end
	if worst > 0.05 then
		fail("praça final: moldura do portal fora do anel")
	end
end

-- 8. Todos os mundos constroem
local worldsOk = 0
for id, world in WorldConfig.Worlds do
	local ok, err = pcall(WorldBuilder.Build, world, V3.new((world.Order - 1) * 8000, 0, 0), E.Instance.new("Folder"), E.Instance.new("Folder"), false)
	if ok then
		worldsOk += 1
	else
		fail("mundos: " .. id .. " não constrói: " .. tostring(err))
	end
end

-- ── Relatório ───────────────────────────────────────────────────────────────
local classes = {}
for name in byClass do
	table.insert(classes, name)
end
table.sort(classes, function(a, b)
	return byClass[a] > byClass[b]
end)
local line = {}
for _, name in classes do
	table.insert(line, name .. "=" .. byClass[name])
end
print(string.format("Instâncias do mundo inicial: %d", total))
print("  " .. table.concat(line, " "))
print(string.format("Borda mais baixa: %d studs · %d pontos de borda · spawn·entrada = %.3f · %d mundos constroem", lowest, rimPoints, spawnDot, worldsOk))
if #problems == 0 then
	print("OK: chão, bordas, caminho, spawn, corredor e praça final.")
	process.exit(0)
end
print(#problems .. " problema(s):")
for _, message in problems do
	print("  " .. message)
end
process.exit(1)
