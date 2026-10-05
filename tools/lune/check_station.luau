--[[
	check_station.luau — PROTÓTIPO VISUAL da estação de MELHORIAS como máquina
	(server/World/StationMachines + client/Controllers/StationFxController).

		lune run tools/lune/check_station.luau [raiz]

	Verifica, sobre o WorldBuilder real (mundo inicial):
	  1. a máquina existe no lugar da antiga (área Shop) e o prompt é o MESMO
	     de antes (OpenPanel = "Upgrades", mesmas chaves) — um só no mundo;
	  2. orçamento: peças, nenhuma luz (PointLight/SpotLight/SurfaceLight),
	     nenhum BillboardGui, partículas poucas e lentas;
	  3. escala: estrutura principal 2–3x a altura do avatar; total < 20 studs;
	  4. placas físicas "⬆️ MELHORIAS" / "AUMENTE SEU PODER" viradas para a
	     praça, com distância de leitura limitada;
	  5. pegada dentro do piso da área, fora das calçadas, do caminho do
	     Caminho do Poder, do spawn, e longe do quiosque da Loja, da gema e do
	     estandarte da área;
	  6. plataforma de interação na frente, ao alcance do prompt;
	  7. reverter = tirar Style do LobbyConfig: volta o quiosque antigo, com o
	     mesmo prompt;
	  8. cliente: núcleo e anéis giram (sem sair do raio), setas acendem de
	     baixo para cima, técnico vira para quem chega; longe nada roda; nada
	     é criado.

	REQUER VALIDAÇÃO NO ROBLOX STUDIO: aparência real (materiais, Neon,
	partículas), leitura das placas, se o técnico ajuda ou polui.
]]
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local E = require("./env")(process.args[1])
local V3 = roblox.Vector3
local CF = roblox.CFrame

local problems = {}
local function check(condition: any, message: string)
	if condition then
		print("OK   " .. message)
	else
		table.insert(problems, message)
		print("FALHA " .. message)
	end
end

local WorldBuilder = E.require(E.Server.World.WorldBuilder)
local WorldConfig = E.require(E.Shared.Config.WorldConfig)
local LobbyConfig = E.require(E.Shared.Config.LobbyConfig)
local WallConfig = E.require(E.Shared.Config.WallConfig)

local function build()
	return WorldBuilder.Build(WorldConfig.Worlds[WorldConfig.DefaultWorld], V3.new(0, 0, 0), E.Instance.new("Folder"), E.Instance.new("Folder"), true)
end
local world = build()
local machine = world:FindFirstChild("Station_Upgrades_Machine")
check(machine ~= nil, "1. estação-máquina de Melhorias construída")
if not machine then
	process.exit(1)
end

-- 1. Prompt.
local prompts = {}
for _, d in world:GetDescendants() do
	if d:IsA("ProximityPrompt") and d:GetAttribute("OpenPanel") == "Upgrades" then
		table.insert(prompts, d)
	end
end
local prompt = prompts[1]
local console = prompt and prompt.Parent
check(#prompts == 1 and console and console.Name == "Station_Upgrades" and console:IsDescendantOf(machine), "1. um só prompt de Melhorias, no console da máquina (peça Station_Upgrades)")
check(prompt and prompt:GetAttribute("TextKey") == "world.prompt.upgrades" and prompt:GetAttribute("ObjectKey") == "menu.upgrades", "1. o prompt é o mesmo de antes (abre o painel Upgrades atual; nenhum sistema novo)")

-- 2. Orçamento.
local parts, lights, billboards, emitters, rate = 0, 0, 0, 0, 0
for _, d in machine:GetDescendants() do
	if d:IsA("BasePart") then
		parts += 1
	elseif d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
		lights += 1
	elseif d:IsA("BillboardGui") then
		billboards += 1
	elseif d:IsA("ParticleEmitter") then
		emitters += 1
		rate += d.Rate
	end
end
local total = #machine:GetDescendants()
check(parts <= 130, string.format("2. orçamento: %d peças (%d instâncias no total; limite 130 peças)", parts, total))
check(lights == 0, "2. nenhuma luz (o brilho vem de material, partícula e movimento)")
check(billboards == 0, "2. nenhum BillboardGui (a placa é física)")
check(emitters <= 3 and rate <= 15, string.format("2. partículas controladas (%d emissores, %d/s no total)", emitters, rate))
check(machine:GetAttribute("PartCount") == parts, "2. PartCount do protótipo bate com as peças")

-- Medidas no espaço da máquina (frente = -Z, na direção da praça).
local station = nil
for _, s in LobbyConfig.Stations do
	if s.Panel == "Upgrades" then
		station = s
	end
end
local area = LobbyConfig.Areas[station.Area]
local base = area.Offset + station.Local
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
local top, structure = 0, 0
for _, d in machine:GetDescendants() do
	if d:IsA("BasePart") then
		for _, c in corners(d) do
			top = math.max(top, c.Y)
			if d.Name == "Lintel" then
				structure = math.max(structure, c.Y)
			end
		end
	end
end
local AVATAR = 5.5
check(structure >= 2 * AVATAR and structure <= 3 * AVATAR, string.format("3. estrutura principal %.1f studs = %.1fx o avatar (2–3x)", structure, structure / AVATAR))
check(top <= 20, string.format("3. com o emblema ⬆ chega a %.1f studs (não vira prédio)", top))

-- 4. Placas.
local title, subtitle = machine:FindFirstChild("SignTitle", true), machine:FindFirstChild("SignSubtitle", true)
local function textOf(part)
	local gui = part and part:FindFirstChildOfClass("SurfaceGui")
	local label = gui and gui:FindFirstChildOfClass("TextLabel")
	return label and label.Text or "", gui
end
local titleText, titleGui = textOf(title)
local subText, subGui = textOf(subtitle)
check(string.find(titleText, "MELHORIAS", 1, true) and string.find(titleText, "⬆", 1, true), "4. placa \"" .. titleText .. "\"")
check(subText == "AUMENTE SEU PODER", "4. subtítulo \"" .. subText .. "\"")
local toPlaza = (V3.new(0, 0, 0) - V3.new(base.X, 0, base.Z)).Unit
check(title and title.CFrame.LookVector:Dot(toPlaza) > 0.99 and titleGui.Face == roblox.Enum.NormalId.Front, "4. placas viradas para a praça (de onde o jogador vem)")
check(titleGui and titleGui.MaxDistance <= 120 and subGui.MaxDistance <= 60, "4. leitura com distância limitada (título 110, subtítulo 55): não é letreiro do mapa inteiro")

-- 5. Pegada.
local floor = area.FloorSize
local floorMin = V3.new(area.Offset.X - floor.X / 2, 0, area.Offset.Z - floor.Y / 2)
local floorMax = V3.new(area.Offset.X + floor.X / 2, 0, area.Offset.Z + floor.Y / 2)
local outside, worstWalk, worstPath = 0, math.huge, math.huge
local function segmentDistance(p, a, b)
	local ab = b - a
	local t = math.clamp((p - a):Dot(ab) / ab:Dot(ab), 0, 1)
	return (p - (a + ab * t)).Magnitude
end
local ground = {}
for _, d in machine:GetDescendants() do
	if d:IsA("BasePart") then
		for _, c in corners(d) do
			local flat = V3.new(c.X, 0, c.Z)
			table.insert(ground, flat)
			if flat.X < floorMin.X or flat.X > floorMax.X or flat.Z < floorMin.Z or flat.Z > floorMax.Z then
				outside += 1
			end
			for _, a in LobbyConfig.Areas do
				if a.Id ~= "Tower" then
					worstWalk = math.min(worstWalk, segmentDistance(flat, V3.zero, V3.new(a.Offset.X, 0, a.Offset.Z)))
				end
			end
			if flat.X > 0 then
				worstPath = math.min(worstPath, math.abs(flat.Z) - LobbyConfig.Path.Width / 2)
			end
		end
	end
end
check(outside == 0, "5. toda a máquina fica dentro do piso da área de Melhorias/Loja")
-- Calçada: 7 de largura (WorldBuilder.WALKWAY_WIDTH); a da própria área chega no centro dela.
check(worstWalk >= 3.5 + 1.5, string.format("5. fora das calçadas da praça (mais perto: %.1f studs do eixo; calçada tem 3,5 de meia largura)", worstWalk))
check(worstPath >= 20, string.format("5. longe do caminho do Caminho do Poder (%.1f studs da borda)", worstPath))
local spawnPoint = LobbyConfig.SpawnPoint
local nearestSpawn = math.huge
for _, p in ground do
	nearestSpawn = math.min(nearestSpawn, (p - V3.new(spawnPoint.X, 0, spawnPoint.Z)).Magnitude)
end
check(nearestSpawn >= 60, string.format("5. não invade o spawn (%.0f studs)", nearestSpawn))
local function nearestTo(part)
	local best = math.huge
	local centre = V3.new(part.CFrame.Position.X, 0, part.CFrame.Position.Z)
	for _, p in ground do
		best = math.min(best, (p - centre).Magnitude)
	end
	return best
end
local shopKiosk, gem, sign = world:FindFirstChild("Station_Shop", true), world:FindFirstChild("ShopGem", true), world:FindFirstChild("AreaSign_Shop", true)
check(shopKiosk and nearestTo(shopKiosk) >= 15, string.format("5. não cobre o quiosque da Loja (%.0f studs)", shopKiosk and nearestTo(shopKiosk) or -1))
check(gem and nearestTo(gem) >= 6, string.format("5. não encosta na vitrine da gema (%.1f studs)", gem and nearestTo(gem) or -1))
check(sign and nearestTo(sign) >= 15, "5. não cobre o estandarte da área")
local gateX = WallConfig.Layout.StartX
check(base.X < gateX - 40, "5. longe do portão do Caminho do Poder")

-- 6. Plataforma.
local pad = machine:FindFirstChild("InteractPad", true)
local ahead = (pad.CFrame.Position - console.CFrame.Position):Dot(toPlaza)
check(ahead > 3, string.format("6. plataforma de interação NA FRENTE da máquina (%.1f studs à frente do console, do lado da praça)", ahead))
check((pad.CFrame.Position - console.CFrame.Position).Magnitude <= prompt.MaxActivationDistance - 3, string.format("6. de cima da plataforma o prompt alcança (%.1f studs; alcance %d)", (pad.CFrame.Position - console.CFrame.Position).Magnitude, prompt.MaxActivationDistance))
check(pad.Size.X <= 7 and pad.Size.Z <= 6, "6. marca discreta (não é um círculo neon gigante)")

-- 7. Reverter pelo config.
local style, npc = station.Style, station.Npc
station.Style, station.Npc = nil, nil
local old = build()
local oldPrompt = nil
for _, d in old:GetDescendants() do
	if d:IsA("ProximityPrompt") and d:GetAttribute("OpenPanel") == "Upgrades" then
		oldPrompt = d
	end
end
check(old:FindFirstChild("Station_Upgrades_Machine") == nil and oldPrompt and oldPrompt.Parent.Name == "Station_Upgrades", "7. sem Style no LobbyConfig volta o quiosque antigo, com o mesmo prompt")
station.Style, station.Npc = style, npc

-- 8. Cliente.
local tagged = {}
for _, d in machine:GetDescendants() do
	for _, tag in d:GetTags() do
		tagged[tag] = tagged[tag] or {}
		table.insert(tagged[tag], d)
	end
end
local Sig = { Connect = function()
	return { Disconnect = function() end }
end }
E.stubs.CollectionService = {
	GetTagged = function(_, tag)
		return tagged[tag] or {}
	end,
	GetInstanceAddedSignal = function()
		return Sig
	end,
	GetInstanceRemovedSignal = function()
		return Sig
	end,
}
local camera = { CFrame = CF.new(pad.CFrame.Position + V3.new(0, 6, 0)) }
local playerRoot = E.Instance.new("Part")
playerRoot.Name = "HumanoidRootPart"
local character = E.Instance.new("Model")
playerRoot.Parent = character
E.stubs.Players = { GetPlayers = function()
	return { { Character = character } }
end, LocalPlayer = { Character = character } }
E.stubs.Workspace = setmetatable({ CurrentCamera = camera }, { __index = E.Workspace })
-- O Lune não expõe BasePart.Position (só CFrame).
E.patches["StarterPlayer.Client.Controllers.StationFxController"] = {
	{ "root.Position", "root.CFrame.Position", "all" },
	{ "core.Part.Position", "core.Part.CFrame.Position", "all" },
	{ "pulse.Part.Position", "pulse.Part.CFrame.Position", "all" },
}
local Fx = E.require(E.Client.Controllers.StationFxController)
Fx.Init()
local counts = Fx.Counts()
check(counts.Spin == 2 and counts.Ring == 2 and counts.Core == 1 and counts.Npc == (if npc then 1 else 0) and counts.Pulse >= 12, string.format("8. peças animadas registradas (giro %d, anéis %d, núcleo %d, setas %d, técnico %d)", counts.Spin, counts.Ring, counts.Core, counts.Pulse, counts.Npc))

local core = machine:FindFirstChild("PowerCore", true)
local ringModel = machine:FindFirstChild("CoreRingGold", true)
local ringCentre = ringModel:GetAttribute("Centre")
local segment = ringModel:FindFirstChildWhichIsA("BasePart")
local radius0 = (segment.CFrame.Position - ringCentre).Magnitude
local before = #machine:GetDescendants()
local coreStart, segStart = core.CFrame, segment.CFrame.Position
local arrows = {}
for _, d in tagged.StationPulse do
	if d.Name == "EnergyArrow" then
		arrows[d:GetAttribute("Order")] = arrows[d:GetAttribute("Order")] or d
	end
end
-- Jogador chega pela direita de quem olha (lado do técnico).
local technician = machine:FindFirstChild("Technician", true)
local npcRoot = technician and technician.PrimaryPart
local npcStart = npcRoot and npcRoot.CFrame
if npcRoot then
	playerRoot.CFrame = npcRoot.CFrame * CF.new(-8, 0, -8)
end
-- Bordas de subida (seta acendendo) de cada seta, quadro a quadro.
local edges = { {}, {}, {} }
local lit = {}
local t = 1000
for frameIndex = 1, 180 do
	t += 1 / 60
	Fx.Step(t)
	for order = 1, 3 do
		local on = arrows[order] ~= nil and arrows[order].Transparency < 0.3
		if on and not lit[order] then
			table.insert(edges[order], frameIndex)
		end
		lit[order] = on
	end
end
local function after(list, frameIndex)
	for _, value in list do
		if value > frameIndex then
			return value
		end
	end
	return nil
end
-- Um ciclo: a 1 acende, depois a 2, depois a 3 (antes da 1 acender de novo).
local e1 = after(edges[1], 0)
local e2 = e1 and after(edges[2], e1)
local e3 = e2 and after(edges[3], e2)
local next1 = e1 and after(edges[1], e1)
local brightest = { e1, e2, e3 }
if next1 and e3 and e3 > next1 then
	brightest[3] = nil
end
local spun = math.deg(math.acos(math.clamp(core.CFrame.LookVector:Dot(coreStart.LookVector), -1, 1)))
check(spun > 10 and (core.CFrame.Position - coreStart.Position).Magnitude < 1e-3, string.format("8. núcleo gira no lugar (%.0f° em 3 s)", spun))
check((segment.CFrame.Position - segStart).Magnitude > 0.2 and math.abs((segment.CFrame.Position - ringCentre).Magnitude - radius0) < 1e-3, "8. anéis giram em volta do núcleo, sem sair do raio")
check(core.Transparency >= 0.08 and core.Transparency <= 0.25, string.format("8. núcleo pulsa sutil (transparência %.2f)", core.Transparency))
check(brightest[1] and brightest[2] and brightest[3] and brightest[1] < brightest[2] and brightest[2] < brightest[3], "8. setas de energia acendem de BAIXO para CIMA (↑↑↑)")
if npcRoot then
	local toPlayer = (playerRoot.CFrame.Position - npcRoot.CFrame.Position)
	local flat = V3.new(toPlayer.X, 0, toPlayer.Z).Unit
	local before0 = npcStart.LookVector:Dot(flat)
	local after = npcRoot.CFrame.LookVector:Dot(flat)
	check(after > before0 + 0.05, string.format("8. técnico vira para o jogador que chega (alinhamento %.2f → %.2f)", before0, after))
end
check(#machine:GetDescendants() == before, "8. nada criado por quadro")
-- Longe: nada roda.
camera.CFrame = CF.new(0, 50, 400)
local frozen = core.CFrame
for _ = 1, 30 do
	t += 1 / 60
	Fx.Step(t)
end
check(core.CFrame == frozen, "8. câmera longe (>140 studs): nada é animado")

if #problems > 0 then
	print(#problems .. " problema(s).")
	process.exit(1)
end
print("OK: estação de Melhorias como máquina (protótipo) — mesma interação, dentro do orçamento, reversível pelo LobbyConfig.")
print("REQUER VALIDAÇÃO NO ROBLOX STUDIO: materiais, Neon, partículas, leitura das placas e se o técnico ajuda ou polui.")
process.exit(0)
