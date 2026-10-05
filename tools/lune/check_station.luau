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
	  P. POLIMENTO: núcleo maior e em camadas (anel frontal → núcleo → halo
	     traseiro), anéis livres em toda a volta (não entram em coluna,
	     bacia, tampa nem halo), colunas com painel embutido, console-terminal
	     inclinado para o jogador com tela, doca no piso com rampa e seta
	     gravada, placa com hierarquia (título >> subtítulo), emblema com
	     suporte, gema da Loja menor (Loja intacta);
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
local StationMachines = E.require(E.Server.World.StationMachines)
local function StationMachinesTheme()
	return StationMachines.Themes.Cuts
end
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
check(parts <= 120, string.format("2. orçamento: %d peças (%d instâncias no total; meta ≤ 120 peças)", parts, total))
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

-- P. Polimento.
local fwd = toPlaza
local side = V3.new(fwd.Z, 0, -fwd.X)
local origin3 = V3.new(base.X, 0, base.Z)
-- Coordenadas da máquina: lateral, altura e "profundidade" (+ = para a praça).
local function machineLocal(p)
	local d = p - origin3
	return d:Dot(side), p.Y, d:Dot(fwd)
end
local function find(name)
	return machine:FindFirstChild(name, true)
end
local crystalPart, corePart = find("CoreCrystal"), find("PowerCore")
check(crystalPart and crystalPart.Size.Y >= 3.1 * 1.15 and crystalPart.Size.Y <= 3.1 * 1.3, string.format("P. núcleo maior (cristal %.1f studs de altura; antes 3,1)", crystalPart and crystalPart.Size.Y or 0))
local energyRing, goldRing, halo = find("CoreRingEnergy"), find("CoreRingGold"), find("CoreHalo")
local _, _, dEnergy = machineLocal(energyRing:GetAttribute("Centre"))
local _, _, dCore = machineLocal(corePart.CFrame.Position)
local _, _, dHalo = machineLocal(halo.CFrame.Position)
check(dEnergy > dCore and dCore > dHalo + 1, string.format("P. profundidade: anel frontal (%.2f) → núcleo (%.2f) → halo traseiro (%.2f)", dEnergy, dCore, dHalo))
check(#machine:GetDescendants() > 0 and find("CoreArm") and find("CoreHaloRim"), "P. armação: halo com aro dourado preso às colunas por braços")
local panelCount, pilasters = 0, 0
for _, d in machine:GetDescendants() do
	if d.Name == "PanelRecess" then
		panelCount += 1
	elseif d.Name == "PanelPilaster" then
		pilasters += 1
	end
end
check(panelCount == 2 and pilasters == 4, "P. colunas com painel embutido (moldura de pilastras + rebaixo + canal) atrás das setas")
local screen = find("ConsoleScreen")
local screenGui = screen and screen:FindFirstChildOfClass("SurfaceGui")
check(screenGui and screenGui:FindFirstChild("Bar3") and screenGui:FindFirstChild("Arrow") and screenGui.Face == roblox.Enum.NormalId.Top, "P. console com tela embutida (↑ + barras subindo)")
local _, consoleY = machineLocal(console.CFrame.Position)
check(console.CFrame.UpVector:Dot(fwd) > 0.3 and consoleY >= 3.5 and consoleY <= 5, string.format("P. console inclinado para o jogador, na altura do peito (%.1f studs)", consoleY))
check(find("ConsoleCable") and find("ConsoleBezel") and find("ConsoleCheek"), "P. console ligado à máquina (cabo) com moldura e laterais")
local ramp, plinth = find("Ramp"), find("Plinth")
local padTop = pad.CFrame.Position.Y + pad.Size.Y / 2
local rampLow = ramp.CFrame.Position.Y - ramp.Size.Y / 2
local plinthTop = plinth.CFrame.Position.Y + plinth.Size.Y / 2
check(math.abs(rampLow - padTop) < 0.05 and math.abs(ramp.CFrame.Position.Y + ramp.Size.Y / 2 - plinthTop) < 0.05, string.format("P. doca: piso → plataforma (topo %.2f) → rampa → base (topo %.2f), sem degrau solto", padTop, plinthTop))
check(padTop - 0.59 <= 0.2, "P. plataforma rente ao piso (encaixada num aro), não um bloco em cima dele")
local arrowPart = find("PadArrow")
check(arrowPart and arrowPart.CFrame.Position.Y + 0.05 - padTop < 0.08, "P. seta do chão gravada na plataforma")
local titleArea = title.Size.X * title.Size.Y
local subArea = subtitle.Size.X * subtitle.Size.Y
check(titleArea >= 4 * subArea and find("SignFrame"), string.format("P. hierarquia da placa: MELHORIAS %.0fx maior que o subtítulo, com moldura dourada", titleArea / subArea))
local braces = 0
for _, d in machine:GetDescendants() do
	if d.Name == "CrestBrace" then
		braces += 1
	end
end
check(braces == 2 and find("CrestPedestal"), "P. emblema ⬆ assentado num pedestal com braços ligando à verga")
check(gem.Size.X <= 4.6 * 0.75 and gem.Size.X >= 4.6 * 0.6, string.format("P. gema da Loja %.0f%% menor (%.1f studs; antes 4,6)", (1 - gem.Size.X / 4.6) * 100, gem.Size.X))
local shopPrompt = nil
for _, d in world:GetDescendants() do
	if d:IsA("ProximityPrompt") and d:GetAttribute("OpenPanel") == "Shop" then
		shopPrompt = d
	end
end
check(shopPrompt ~= nil, "P. Loja continua com o prompt dela (acessível)")
local npcModel = find("Technician")
if npcModel then
	local nx, _, nd = machineLocal(npcModel.PrimaryPart.CFrame.Position)
	local px, _, pd = machineLocal(pad.CFrame.Position)
	check((V3.new(nx, 0, nd) - V3.new(px, 0, pd)).Magnitude > 6, "P. técnico fora da plataforma e do caminho até o console")
end

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
-- Todas as estações do mundo (o controlador é um só para todas).
local tagged = {}
for _, d in world:GetDescendants() do
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
local playerAttributes = { BestCut = "Cut1" }
local bestCutChanged = nil
local localPlayer = {
	Character = character,
	GetAttribute = function(_, key)
		return playerAttributes[key]
	end,
	GetAttributeChangedSignal = function(_, key)
		return { Connect = function(_, fn)
			if key == "BestCut" then
				bestCutChanged = fn
			end
			return { Disconnect = function() end }
		end }
	end,
}
E.stubs.Players = { GetPlayers = function()
	return { { Character = character } }
end, LocalPlayer = localPlayer }
local settings = { ReducedEffects = false }
local statsChanged = nil
E.stubModules["StarterPlayer.Client.Controllers.DataController"] = {
	Get = function(key)
		return if key == "Settings" then settings else nil
	end,
	Changed = { Connect = function(_, fn)
		statsChanged = fn
		return { Disconnect = function() end }
	end },
}
local emitted = {}
roblox.implementMethod("ParticleEmitter", "Emit", function(emitter, count)
	emitted[emitter.Name] = (emitted[emitter.Name] or 0) + (count or 1)
end)
E.stubs.Workspace = setmetatable({ CurrentCamera = camera }, { __index = E.Workspace })
-- O Lune não expõe BasePart.Position (só CFrame).
E.patches["StarterPlayer.Client.Controllers.StationFxController"] = {
	{ "root.Position", "root.CFrame.Position", "all" },
	{ "core.Part.Position", "core.Part.CFrame.Position", "all" },
	{ "pulse.Part.Position", "pulse.Part.CFrame.Position", "all" },
	{ "localRoot.Position", "localRoot.CFrame.Position", "all" },
	{ "screen.Part.Position", "screen.Part.CFrame.Position", "all" },
	{ "flash.Part.Position", "flash.Part.CFrame.Position", "all" },
	{ "holo.Part.Position", "holo.Part.CFrame.Position", "all" },
	{ "(mine - part.Position)", "(mine - part.CFrame.Position)", "all" },
}
local Fx = E.require(E.Client.Controllers.StationFxController)
Fx.Init()
local counts = Fx.Counts()
local function tagCount(tag)
	return if tagged[tag] then #tagged[tag] else 0
end
local registeredAll = counts.Spin == tagCount("StationSpin") and counts.Ring == tagCount("StationRing") and counts.Core == tagCount("StationCore")
	and counts.Pulse == tagCount("StationPulse") and counts.Npc == tagCount("StationNpc") and counts.Screen == tagCount("StationScreen")
	and counts.Tint == tagCount("StationCutTint") and counts.Flash == tagCount("StationFlash") and counts.Particles == tagCount("StationParticles")
	and counts.Holo == tagCount("StationHolo")
check(registeredAll and counts.Npc == (if npc then 1 else 0) and counts.Screen >= 1, string.format("8. um controlador para todas as estações: tudo registrado (giro %d, anéis %d, núcleo %d, pulsos %d, técnico %d, telas %d, tint %d, clarão %d, partículas %d, hologramas %d)", counts.Spin, counts.Ring, counts.Core, counts.Pulse, counts.Npc, counts.Screen, counts.Tint, counts.Flash, counts.Particles, counts.Holo))

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
check(core.Transparency >= 0.03 and core.Transparency <= 0.25, string.format("8. núcleo pulsa sutil, nunca some nem estoura (transparência %.2f)", core.Transparency))
check(brightest[1] and brightest[2] and brightest[3] and brightest[1] < brightest[2] and brightest[2] < brightest[3], "8. setas de energia acendem de BAIXO para CIMA (↑↑↑)")
if npcRoot then
	local toPlayer = (playerRoot.CFrame.Position - npcRoot.CFrame.Position)
	local flat = V3.new(toPlayer.X, 0, toPlayer.Z).Unit
	local before0 = npcStart.LookVector:Dot(flat)
	local after = npcRoot.CFrame.LookVector:Dot(flat)
	check(after > before0 + 0.05, string.format("8. técnico vira para o jogador que chega (alinhamento %.2f → %.2f)", before0, after))
end
check(#machine:GetDescendants() == before, "8. nada criado por quadro")

-- Anéis livres em TODA a volta (não entram em coluna, bacia, tampa, halo).
local haloFront = dHalo + halo.Size.X / 2
local worstSide, worstLow, worstHigh, worstBack = 0, math.huge, -math.huge, math.huge
local function sampleRings()
	for _, ringModel in { energyRing, goldRing } do
		for _, seg in ringModel:GetChildren() do
			for _, sign in { -1, 1 } do
				local p = (seg.CFrame * CF.new(sign * seg.Size.X / 2, 0, 0)).Position
				local lx, ly, ld = machineLocal(p)
				worstSide = math.max(worstSide, math.abs(lx))
				worstLow = math.min(worstLow, ly)
				worstHigh = math.max(worstHigh, ly)
				worstBack = math.min(worstBack, ld)
			end
		end
	end
end

-- Estado de interação: jogador no ponto de uso → a máquina "acorda" de leve.
local function coreRate(seconds)
	local total = 0
	local last = core.CFrame.LookVector
	for _ = 1, math.floor(seconds * 60) do
		t += 1 / 60
		Fx.Step(t)
		sampleRings()
		local now = core.CFrame.LookVector
		total += math.deg(math.acos(math.clamp(now:Dot(last), -1, 1)))
		last = now
	end
	return total / seconds
end
local bar = screen:FindFirstChildOfClass("SurfaceGui"):FindFirstChild("Bar2")
playerRoot.CFrame = CF.new(origin3 + fwd * 60 + V3.new(0, 3, 0))
coreRate(2)
local idleRate = coreRate(1)
local idleBar = bar.BackgroundTransparency
check(Fx.Engagement(screen) < 0.05, "8. longe do console: estação em repouso")
playerRoot.CFrame = CF.new(pad.CFrame.Position + V3.new(0, 3, 0))
coreRate(1.5)
local engagedRate = coreRate(1)
check(Fx.Engagement(screen) > 0.9, string.format("8. jogador na plataforma: a estação acorda (%.2f)", Fx.Engagement(screen)))
check(engagedRate > idleRate * 1.25 and engagedRate < idleRate * 1.6, string.format("8. núcleo um pouco mais rápido no ponto de uso (%.0f°/s → %.0f°/s)", idleRate, engagedRate))
check(bar.BackgroundTransparency < idleBar - 0.1, "8. a tela do console responde (barras mais vivas)")
playerRoot.CFrame = CF.new(origin3 + fwd * 60 + V3.new(0, 3, 0))
coreRate(2)
check(Fx.Engagement(screen) < 0.05, "8. saindo, volta ao repouso")
check(worstSide <= 3.85 and worstLow >= 4.7 and worstHigh <= 10.95 and worstBack >= haloFront + 0.05, string.format("8. anéis girando nunca entram em coluna/bacia/tampa/halo (lateral %.2f ≤ 3,85; altura %.2f–%.2f; atrás %.2f ≥ %.2f)", worstSide, worstLow, worstHigh, worstBack, haloFront + 0.05))
check(#machine:GetDescendants() == before, "8. nada criado no estado de interação")
-- Longe: nada roda.
camera.CFrame = CF.new(0, 50, 400)
local frozen = core.CFrame
for _ = 1, 30 do
	t += 1 / 60
	Fx.Step(t)
end
check(core.CFrame == frozen, "8. câmera longe (>140 studs): nada é animado")

-- ── B. ESTAÇÃO DE COMPANHEIROS (PETS) ──────────────────────────────────────
do
	local lab = world:FindFirstChild("Station_Pets_Machine", true)
	check(lab ~= nil, "B. estação de Pets construída")
	if lab then
		local petPrompts = {}
		for _, d in world:GetDescendants() do
			if d:IsA("ProximityPrompt") and d:GetAttribute("OpenPanel") == "Pets" then
				table.insert(petPrompts, d)
			end
		end
		local terminal = petPrompts[1] and petPrompts[1].Parent
		check(#petPrompts == 1 and terminal and terminal.Name == "Station_Pets" and terminal:IsDescendantOf(lab), "B. um só prompt de Pets, no terminal da estação")
		check(petPrompts[1] and petPrompts[1]:GetAttribute("TextKey") == "world.prompt.pets", "B. é o prompt de sempre (abre o painel Pets atual)")
		local parts, lights, holograms, fakePets = 0, 0, 0, 0
		local minX, maxX, minZ, maxZ, top = math.huge, -math.huge, math.huge, -math.huge, 0
		for _, d in lab:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
				for _, c in corners(d) do
					minX, maxX = math.min(minX, c.X), math.max(maxX, c.X)
					minZ, maxZ = math.min(minZ, c.Z), math.max(maxZ, c.Z)
					top = math.max(top, c.Y)
				end
			elseif d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
				lights += 1
			end
			if d.Name == "PetHologram" then
				holograms += 1
			end
			if d:GetAttribute("PetId") or d:GetAttribute("EquippedPets") or d:IsA("Humanoid") then
				fakePets += 1
			end
		end
		check(parts >= 45 and parts <= 100, string.format("B. orçamento: %d peças (%d instâncias)", parts, #lab:GetDescendants()))
		check(lights == 0, "B. sem luz")
		check(holograms == 3 and fakePets == 0, "B. 3 previews são só imagem (sem PetId, sem Humanoid, nada salvável)")
		local fsB = require("@lune/fs")
		local machinesSource = fsB.readFile(E.Root .. "/src/server/World/StationMachines.luau")
		local cleanPets = true
		for _, word in { "PetService", "EquippedPets", "PetConfig", "PetLogic", "FireServer" } do
			if string.find(machinesSource, word, 1, true) then
				cleanPets = false
				print("      StationMachines usa " .. word)
			end
		end
		check(cleanPets, "B. a estação não conhece o sistema de pets (inventário, equipar, multiplicador)")
		local deck = LobbyConfig.Areas.Pets
		local floorMin = deck.Offset - V3.new(deck.FloorSize.X / 2, 0, deck.FloorSize.Y / 2)
		local floorMax = deck.Offset + V3.new(deck.FloorSize.X / 2, 0, deck.FloorSize.Y / 2)
		check(minX >= floorMin.X and maxX <= floorMax.X and minZ >= floorMin.Z and maxZ <= floorMax.Z, string.format("B. tudo dentro do deck da área (x %.0f a %.0f, z %.0f a %.0f)", minX, maxX, minZ, maxZ))
		check(top <= 14 and (maxX - minX) > top * 1.4, string.format("B. silhueta horizontal (%.0f de largura, %.0f de altura)", maxX - minX, top))
		local worstWalkB = math.huge
		for _, d in lab:GetDescendants() do
			if d:IsA("BasePart") then
				for _, c in corners(d) do
					local flat = V3.new(c.X, 0, c.Z)
					for _, a in LobbyConfig.Areas do
						if a.Id ~= "Tower" and a.Id ~= "Pets" then
							worstWalkB = math.min(worstWalkB, segmentDistance(flat, V3.zero, V3.new(a.Offset.X, 0, a.Offset.Z)))
						end
					end
				end
			end
		end
		check(worstWalkB >= 5, string.format("B. fora das calçadas das outras áreas (%.1f studs)", worstWalkB))
		local pawPad = lab:FindFirstChild("PawPad")
		local toOrigin = (V3.zero - V3.new(deck.Offset.X, 0, deck.Offset.Z)).Unit
		check(pawPad and (pawPad.CFrame.Position - terminal.CFrame.Position):Dot(toOrigin) > 3 and (pawPad.CFrame.Position - terminal.CFrame.Position).Magnitude <= petPrompts[1].MaxActivationDistance - 3, "B. pegada no chão na frente do terminal, ao alcance do prompt")
		-- Reverter.
		local petStation = nil
		for _, st in LobbyConfig.Stations do
			if st.Panel == "Pets" then
				petStation = st
			end
		end
		local styleB = petStation.Style
		petStation.Style = nil
		local oldB = build()
		local oldPrompt = nil
		for _, d in oldB:GetDescendants() do
			if d:IsA("ProximityPrompt") and d:GetAttribute("OpenPanel") == "Pets" then
				oldPrompt = d
			end
		end
		check(oldB:FindFirstChild("Station_Pets_Machine", true) == nil and oldPrompt and oldPrompt.Parent.Name == "Station_Pets", "B. sem Style no LobbyConfig volta o quiosque antigo, com o mesmo prompt")
		petStation.Style = styleB
		-- Cliente: hologramas flutuam (sem mover peças), nítidos perto do terminal.
		local holo = lab:FindFirstChild("PetHologram")
		local gui = holo:FindFirstChildOfClass("BillboardGui")
		camera.CFrame = CF.new(holo.CFrame.Position + toOrigin * 15 + V3.new(0, 4, 0))
		playerRoot.CFrame = CF.new(holo.CFrame.Position + toOrigin * 40)
		local anchorBefore = holo.CFrame
		local lowest, highest = math.huge, -math.huge
		for _ = 1, 60 * 3 do
			t += 1 / 60
			Fx.Step(t)
			lowest = math.min(lowest, gui.StudsOffset.Y)
			highest = math.max(highest, gui.StudsOffset.Y)
		end
		check(highest - lowest > 0.2 and highest - lowest < 0.5 and holo.CFrame == anchorBefore, string.format("B. hologramas flutuam de leve (%.2f studs) sem mover peça", highest - lowest))
		local art = gui:FindFirstChildOfClass("ImageLabel")
		local farArt = art and art.ImageTransparency
		playerRoot.CFrame = CF.new(pawPad.CFrame.Position + V3.new(0, 3, 0))
		for _ = 1, 90 do
			t += 1 / 60
			Fx.Step(t)
		end
		check(art and Fx.Engagement(terminal:FindFirstChild("TerminalScreen") or lab:FindFirstChild("TerminalScreen")) > 0.8 and art.ImageTransparency < farArt, "B. jogador na pegada: a estação acorda (hologramas mais nítidos)")
	end
end

-- ── R. ALTAR DO RENASCIMENTO ───────────────────────────────────────────────
do
	local altar = world:FindFirstChild("Station_Rebirth_Machine", true)
	check(altar ~= nil, "R. altar do Renascimento construído")
	if altar then
		local rebirthPrompts = {}
		for _, d in world:GetDescendants() do
			if d:IsA("ProximityPrompt") and d:GetAttribute("OpenPanel") == "Rebirth" then
				table.insert(rebirthPrompts, d)
			end
		end
		local core = rebirthPrompts[1] and rebirthPrompts[1].Parent
		check(#rebirthPrompts == 1 and core and core.Name == "RebirthCore" and core:IsDescendantOf(altar) and rebirthPrompts[1]:GetAttribute("TextKey") == "world.prompt.rebirth", "R. um só prompt de Renascer (o de sempre), no núcleo do altar")
		local parts, lights, bills = 0, 0, 0
		local centre = LobbyConfig.Areas.Rebirth.Offset
		local reach, top = 0, 0
		for _, d in altar:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
				for _, c in corners(d) do
					reach = math.max(reach, (V3.new(c.X, 0, c.Z) - V3.new(centre.X, 0, centre.Z)).Magnitude)
					top = math.max(top, c.Y)
				end
			elseif d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
				lights += 1
			elseif d:IsA("BillboardGui") then
				bills += 1
			end
		end
		check(parts >= 50 and parts <= 110, string.format("R. orçamento: %d peças (%d instâncias)", parts, #altar:GetDescendants()))
		check(lights == 0 and bills == 0, "R. sem luz (o orbe antigo tinha PointLight 18/2) e sem BillboardGui")
		check(reach <= LobbyConfig.Areas.Rebirth.Radius - 4 and top <= 19, string.format("R. círculo de %.1f studs de raio dentro da área (%d), %.1f de altura", reach, LobbyConfig.Areas.Rebirth.Radius, top))
		local toPlazaR = (V3.zero - V3.new(centre.X, 0, centre.Z)).Unit
		local ramp = altar:FindFirstChild("AltarRamp")
		check(ramp and (ramp.CFrame.Position - V3.new(centre.X, ramp.CFrame.Position.Y, centre.Z)):Dot(toPlazaR) > 5, "R. rampa de acesso virada para a praça (frente aberta)")
		local pillar = altar:FindFirstChild("CorePillar")
		local crystalR = altar:FindFirstChild("RebirthCrystal")
		local half = crystalR.Size.X / 2 * math.sqrt(2)
		check(pillar and pillar.CanCollide and half <= pillar.Size.Y / 2 + 0.6, "R. núcleo sobre um pilar sólido: quem sobe no altar não fica dentro do cristal")
		local worstWalkR = math.huge
		for _, d in altar:GetDescendants() do
			if d:IsA("BasePart") then
				for _, c in corners(d) do
					local flat = V3.new(c.X, 0, c.Z)
					for _, a in LobbyConfig.Areas do
						if a.Id ~= "Tower" and a.Id ~= "Rebirth" then
							worstWalkR = math.min(worstWalkR, segmentDistance(flat, V3.zero, V3.new(a.Offset.X, 0, a.Offset.Z)))
						end
					end
				end
			end
		end
		check(worstWalkR >= 5, string.format("R. fora das calçadas das outras áreas (%.1f studs)", worstWalkR))
		-- Cálculo intacto: o visual não conhece o renascimento.
		local fsR = require("@lune/fs")
		local cleanR = true
		for _, path in { "src/server/World/StationMachines.luau", "src/client/Controllers/StationFxController.luau" } do
			local source = fsR.readFile(E.Root .. "/" .. path)
			for _, word in { "RebirthLogic", "RebirthService", "RebirthConfig", "Invoke(" } do
				if string.find(source, word, 1, true) then
					cleanR = false
					print("      " .. path .. " usa " .. word)
				end
			end
		end
		check(cleanR, "R. nenhum cálculo de renascimento no visual (só lê Stats.Rebirths para a rajada)")
		-- Reverter.
		local style = LobbyConfig.RebirthStation
		LobbyConfig.RebirthStation = nil
		local oldR = build()
		local orb = oldR:FindFirstChild("RebirthOrb", true)
		check(oldR:FindFirstChild("Station_Rebirth_Machine", true) == nil and orb and orb:FindFirstChildOfClass("ProximityPrompt"), "R. RebirthStation = nil volta o altar antigo, com o mesmo prompt")
		LobbyConfig.RebirthStation = style
		-- Cliente: partículas sobem mais com o jogador perto; rajada só ao renascer.
		local rise = altar:FindFirstChild("RebirthRise", true)
		while rise and not rise:IsA("ParticleEmitter") do
			rise = rise:FindFirstChildWhichIsA("ParticleEmitter")
		end
		camera.CFrame = CF.new(core.CFrame.Position + toPlazaR * 20 + V3.new(0, 4, 0))
		playerRoot.CFrame = CF.new(core.CFrame.Position + toPlazaR * 40)
		for _ = 1, 90 do
			t += 1 / 60
			Fx.Step(t)
		end
		local idleRate = rise.Rate
		playerRoot.CFrame = CF.new(ramp.CFrame.Position + V3.new(0, 3, 0))
		for _ = 1, 90 do
			t += 1 / 60
			Fx.Step(t)
		end
		check(idleRate <= 1.5 and rise.Rate >= 5, string.format("R. jogador chega: fragmentos começam a subir (%.1f → %.1f por segundo)", idleRate, rise.Rate))
		check(statsChanged ~= nil, "R. escuta Stats do DataController (nenhum remote novo)")
		emitted = {}
		statsChanged("Stats", { Rebirths = 3 })
		statsChanged("Stats", { Rebirths = 3 })
		check((emitted.RebirthBurst or 0) == 0, "R. sem renascer: nada de rajada")
		statsChanged("Stats", { Rebirths = 4 })
		check((emitted.RebirthBurst or 0) > 0, "R. renasceu (Stats.Rebirths subiu): rajada local no altar")
		settings.ReducedEffects = true
		t += 1.1
		Fx.Step(t)
		emitted = {}
		statsChanged("Stats", { Rebirths = 5 })
		check((emitted.RebirthBurst or 0) == 0, "R. \"Efeitos reduzidos\": sem rajada")
		settings.ReducedEffects = false
		t += 1.1
		Fx.Step(t)
	end
end

-- ── T. CENTRO DE TREINAMENTO ───────────────────────────────────────────────
do
	local TrainingConfig = E.require(E.Shared.Config.TrainingConfig)
	local gym = world:FindFirstChild("Station_Training_Machine", true)
	check(gym ~= nil, "T. centro de treinamento construído")
	-- Os valores de jogo, exatamente como estão.
	local expected = { Bag = { 0.35, 0 }, Weights = { 0.7, 10 }, Treadmill = { 1.2, 60 }, Rack = { 1.8, 300 } }
	local sameValues = #TrainingConfig.Stations == 4
	for _, station in TrainingConfig.Stations do
		local e = expected[station.Id]
		if not e or math.abs(station.Rate - e[1]) > 1e-9 or station.RequiredWins ~= e[2] then
			sameValues = false
		end
	end
	check(sameValues, "T. rendimentos 0,35 / 0,70 / 1,20 / 1,80 e requisitos 0 / 10 / 60 / 300 intactos")
	if gym then
		local area = LobbyConfig.Areas.Training
		local areaMin = area.Offset - V3.new(area.FloorSize.X / 2, 0, area.FloorSize.Y / 2)
		local areaMax = area.Offset + V3.new(area.FloorSize.X / 2, 0, area.FloorSize.Y / 2)
		local function inArea(p)
			return p.X >= areaMin.X - 1 and p.X <= areaMax.X + 1 and p.Z >= areaMin.Z - 1 and p.Z <= areaMax.Z + 1
		end
		-- Placas de tier com nome e requisito, na ordem de requisito.
		local order = {}
		for _, station in TrainingConfig.Stations do
			table.insert(order, station)
		end
		table.sort(order, function(a, b)
			return a.RequiredWins < b.RequiredWins
		end)
		local roman = { "I", "II", "III", "IV" }
		local plaquesOk = true
		for index, station in order do
			local plaque = gym:FindFirstChild("TierPlaque_" .. station.Id)
			local gui = plaque and plaque:FindFirstChildOfClass("SurfaceGui")
			local tier = gui and gui:FindFirstChild("Tier")
			local req = gui and gui:FindFirstChild("Requirement")
			local wantReq = if station.RequiredWins > 0 then "🏆 " .. tostring(station.RequiredWins) else "LIVRE"
			if not (tier and tier.Text == roman[index] and req and req.Text == wantReq) then
				plaquesOk = false
				print("      placa de " .. station.Id .. ": " .. (tier and tier.Text or "?") .. " / " .. (req and req.Text or "?"))
			end
			-- A placa fica na borda do pad, de frente para a avenida (-Z).
			if plaque and plaque.CFrame.LookVector.Z > -0.9 then
				plaquesOk = false
			end
		end
		check(plaquesOk, "T. placa I–IV por equipamento: nome + requisito (LIVRE, 🏆 10, 🏆 60, 🏆 300), de frente para quem chega")
		-- Sem letreiro flutuante e sem luz constante na academia.
		local bills, lightsT = 0, 0
		for _, d in world:GetDescendants() do
			if d:IsA("BasePart") and inArea(d.CFrame.Position) then
				if d:FindFirstChildOfClass("BillboardGui") and string.sub(d.Name, 1, 13) == "TrainingSign_" then
					bills += 1
				end
				if d:FindFirstChildOfClass("PointLight") then
					lightsT += 1
				end
			end
		end
		check(bills == 0 and lightsT == 0, "T. sem letreiros flutuantes e sem luz constante na academia (a esteira e a máquina de força tinham PointLight)")
		-- Dá para ficar em cima de cada pad: amostra o pad na altura do corpo.
		local solidsT = {}
		for _, d in world:GetDescendants() do
			if d:IsA("BasePart") and d.CanCollide and inArea(d.CFrame.Position) then
				table.insert(solidsT, d)
			end
		end
		local function blocked(p)
			for _, part in solidsT do
				local lp = part.CFrame:PointToObjectSpace(p)
				local h = part.Size / 2
				if math.abs(lp.X) <= h.X and math.abs(lp.Y) <= h.Y and math.abs(lp.Z) <= h.Z then
					return true
				end
			end
			return false
		end
		local padsOk = true
		for _, station in TrainingConfig.Stations do
			local centre = area.Offset + station.Local
			local free, total = 0, 0
			for dx = -station.Radius + 1, station.Radius - 1, 1.5 do
				for dz = -station.Radius + 1, station.Radius - 1, 1.5 do
					if dx * dx + dz * dz <= (station.Radius - 1) ^ 2 then
						total += 1
						if not blocked(centre + V3.new(dx, 3, dz)) then
							free += 1
						end
					end
				end
			end
			if free / total < 0.6 then
				padsOk = false
				print(string.format("      pad %s: %.0f%% livre", station.Id, free / total * 100))
			end
		end
		check(padsOk, "T. os quatro pads continuam com espaço para treinar (> 60% livre na altura do corpo)")
		-- Pórtico fora da avenida, com vão para passar.
		local pillars = {}
		local gymParts = 0
		for _, d in gym:GetDescendants() do
			if d:IsA("BasePart") then
				gymParts += 1
			end
			if d.Name == "GymGatePillar" then
				table.insert(pillars, d)
			end
		end
		local gap = math.abs(pillars[1].CFrame.Position.X - pillars[2].CFrame.Position.X) - pillars[1].Size.X
		check(#pillars == 2 and gap >= 10 and pillars[1].CFrame.Position.Z > LobbyConfig.Path.Width / 2 + 8, string.format("T. pórtico fora da avenida, com %.1f studs de vão", gap))
		check(gymParts <= 90, string.format("T. orçamento do que foi acrescentado: %d peças (%d instâncias)", gymParts, #gym:GetDescendants()))
		-- Progressão: o IV é a máquina mais elaborada.
		local function near(station)
			local centre = area.Offset + station.Local
			local n = 0
			for _, d in world:GetDescendants() do
				if d:IsA("BasePart") and (V3.new(d.CFrame.Position.X, 0, d.CFrame.Position.Z) - V3.new(centre.X, 0, centre.Z)).Magnitude <= station.Radius + 1 then
					n += 1
				end
			end
			return n
		end
		local counts = {}
		for index, station in order do
			counts[index] = near(station)
		end
		check(counts[1] <= counts[2] and counts[2] <= counts[3] and counts[3] < counts[4], string.format("T. progressão visível: peças por equipamento I %d, II %d, III %d, IV %d", counts[1], counts[2], counts[3], counts[4]))
		local gauges = 0
		for _, d in gym:GetDescendants() do
			if d.Name == "ForceGauge" and d:HasTag("StationPulse") then
				gauges += 1
			end
		end
		check(gauges == 5, "T. medidor de força da máquina IV sobe (5 segmentos animados)")
		-- Reverter.
		LobbyConfig.TrainingCenter = false
		local oldT = build()
		local oldSign = oldT:FindFirstChild("TrainingSign_Rack", true)
		check(oldT:FindFirstChild("Station_Training_Machine", true) == nil and oldSign and oldSign:FindFirstChildOfClass("BillboardGui") and oldT:FindFirstChild("AreaSign_Training", true), "T. TrainingCenter = false volta a academia de antes (letreiros e estandarte)")
		check(world:FindFirstChild("AreaSign_Training", true) == nil, "T. com o pórtico, o estandarte da área (cristal + luz) sai: placa repetida")
		LobbyConfig.TrainingCenter = true
	end
end

-- ── E. ÁREA DE INCUBAÇÃO (OVOS) ────────────────────────────────────────────
do
	local EggConfig = E.require(E.Shared.Config.EggConfig)
	local area = world:FindFirstChild("Station_Eggs_Machine", true)
	check(area ~= nil, "E. área de incubação construída")
	-- Preços, moedas, estágios e chances: exatamente os mesmos.
	local want = {
		BasicEgg = { "Power", 2000, nil, 100 },
		ForestEgg = { "Gems", 25, nil, 100 },
		MysticEgg = { "Gems", 150, nil, 100 },
		TowerEgg = { "Gems", 400, "Gold", 100 },
		ColossusEgg = { "Gems", 2500, "Colossus", 100 },
	}
	local sameEggs = true
	for id, w in want do
		local egg = EggConfig.Eggs[id]
		local total = 0
		for _, drop in egg and egg.Drops or {} do
			total += drop.Weight
		end
		if not egg or egg.Currency ~= w[1] or egg.Price ~= w[2] or egg.RequiredStage ~= w[3] or math.abs(total - w[4]) > 1e-6 then
			sameEggs = false
			print("      " .. id .. " mudou")
		end
	end
	check(sameEggs, "E. ovos intactos: Básico ⚡2.000, Floresta 💎25, Místico 💎150, Caminho 💎400 (estágio 5), Colosso 💎2.500 (estágio 10), chances somando 100")
	if area then
		-- Os mesmos prompts, nos próprios ovos.
		local eggPrompts, okPrompts = 0, true
		for _, d in world:GetDescendants() do
			if d:IsA("ProximityPrompt") and d:GetAttribute("OpenPanel") == "Eggs" then
				eggPrompts += 1
				local id = string.sub(d.Parent.Name, 5)
				if string.sub(d.Parent.Name, 1, 4) ~= "Egg_" or d:GetAttribute("TextKey") ~= "world.prompt.hatch" or d:GetAttribute("ObjectKey") ~= "egg." .. id .. ".name" then
					okPrompts = false
				end
			end
		end
		check(eggPrompts == 5 and okPrompts, "E. os 5 prompts de sempre, um em cada ovo (abrem o painel de Ovos; a validação antes da cobrança fica no servidor)")
		-- Placas: nome, preço e estágio exigido.
		local function plaque(id)
			local board = area:FindFirstChild("EggPlaque_" .. id)
			local gui = board and board:FindFirstChildOfClass("SurfaceGui")
			local nameLabel = gui and gui:FindFirstChild("Name")
			local priceLabel = gui and gui:FindFirstChild("Price")
			return nameLabel and nameLabel.Text, priceLabel and priceLabel.Text
		end
		local _, towerPrice = plaque("TowerEgg")
		local colossusName, colossusPrice = plaque("ColossusEgg")
		local basicName, basicPrice = plaque("BasicEgg")
		check(basicName == "OVO BÁSICO" and basicPrice == "⚡ 2K" and colossusName == "OVO DO COLOSSO" and string.find(colossusPrice or "", "💎 2.5K", 1, true) and string.find(colossusPrice or "", "Estágio 10", 1, true) and string.find(towerPrice or "", "Estágio 5", 1, true), string.format("E. placas físicas: nome, preço e estágio (\"%s\" / \"%s\")", tostring(colossusName), tostring(colossusPrice)))
		-- Incubadoras abertas: braços longe do ovo, menores que ele, até 4.
		local eggs = {}
		for _, d in world:GetDescendants() do
			if d:IsA("BasePart") and string.sub(d.Name, 1, 4) == "Egg_" then
				table.insert(eggs, d)
			end
		end
		local open, armsByTier = true, {}
		for _, d in area:GetDescendants() do
			if d.Name == "IncubatorArm" then
				local tier = d:GetAttribute("Tier")
				armsByTier[tier] = (armsByTier[tier] or 0) + 1
				local tip = (d.CFrame * CF.new(0, d.Size.Y / 2, 0)).Position
				for _, egg in eggs do
					local centre = egg.CFrame.Position
					local flat = V3.new(tip.X - centre.X, 0, tip.Z - centre.Z).Magnitude
					if flat < 5 and flat < egg.Size.X / 2 + 0.5 then
						open = false
					end
					if d.Size.Y >= egg.Size.Y * 1.3 then
						open = false
					end
				end
			end
		end
		check(open and (armsByTier[1] or 0) <= (armsByTier[3] or 0) and (armsByTier[5] or 0) <= 4, string.format("E. incubadoras ABERTAS e menores que o ovo; mais elaboradas por nível (braços: %d, %d, %d, %d, %d)", armsByTier[1] or 0, armsByTier[2] or 0, armsByTier[3] or 0, armsByTier[4] or 0, armsByTier[5] or 0))
		-- Nada sólido novo perto dos ovos (o caminho até eles fica livre).
		local blocking = 0
		for _, d in area:GetDescendants() do
			if d:IsA("BasePart") and d.CanCollide then
				for _, egg in eggs do
					local a = V3.new(d.CFrame.Position.X, 0, d.CFrame.Position.Z)
					local b = V3.new(egg.CFrame.Position.X, 0, egg.CFrame.Position.Z)
					if (a - b).Magnitude < 16 then
						blocking += 1
					end
				end
			end
		end
		check(blocking == 0, "E. nenhuma peça sólida nova a menos de 16 studs dos ovos: as bancadas continuam acessíveis")
		local partsE, lightsE = 0, 0
		for _, d in area:GetDescendants() do
			if d:IsA("BasePart") then
				partsE += 1
			end
		end
		local landmark = world:FindFirstChild("EggLandmark", true)
		for _, d in world:GetDescendants() do
			if d:IsA("PointLight") and d.Parent and d.Parent:IsA("BasePart") and (V3.new(d.Parent.CFrame.Position.X, 0, d.Parent.CFrame.Position.Z) - V3.new(LobbyConfig.Areas.Eggs.Offset.X, 0, LobbyConfig.Areas.Eggs.Offset.Z)).Magnitude < LobbyConfig.Areas.Eggs.Radius then
				lightsE += 1
			end
		end
		check(partsE <= 90 and lightsE == 0 and landmark and world:FindFirstChild("AreaSign_Eggs", true) == nil, string.format("E. %d peças (%d instâncias), sem luz constante (o ovo gigante tinha PointLight 18) e sem estandarte repetido", partsE, #area:GetDescendants()))
		-- Reverter.
		LobbyConfig.IncubationArea = false
		local oldE = build()
		local oldEgg = oldE:FindFirstChild("Egg_BasicEgg", true)
		check(oldE:FindFirstChild("Station_Eggs_Machine", true) == nil and oldEgg and oldEgg:FindFirstChildOfClass("BillboardGui") and oldE:FindFirstChild("AreaSign_Eggs", true), "E. IncubationArea = false volta as bancadas de antes")
		LobbyConfig.IncubationArea = true
	end
end

-- ── C. FORJA DE CORTES ─────────────────────────────────────────────────────
do
	local forge = world:FindFirstChild("Station_Cuts_Machine", true)
	check(forge ~= nil, "C. forja de Cortes construída")
	if forge then
		local parts, lights, bills, emittersN, forgePrompts = 0, 0, 0, 0, 0
		local minX, maxX, minZ, maxZ, top = math.huge, -math.huge, math.huge, -math.huge, 0
		local railMinX, railMaxX = math.huge, -math.huge
		for _, d in forge:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
				local isRail = d.Name == "ForgeRail" or d.Name == "RailTap"
				for _, c in corners(d) do
					if isRail then
						railMinX, railMaxX = math.min(railMinX, c.X), math.max(railMaxX, c.X)
					else
						minX, maxX = math.min(minX, c.X), math.max(maxX, c.X)
					end
					minZ, maxZ = math.min(minZ, c.Z), math.max(maxZ, c.Z)
					top = math.max(top, c.Y)
				end
			elseif d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
				lights += 1
			elseif d:IsA("BillboardGui") then
				bills += 1
			elseif d:IsA("ParticleEmitter") then
				emittersN += 1
			elseif d:IsA("ProximityPrompt") then
				forgePrompts += 1
			end
		end
		check(parts >= 50 and parts <= 115, string.format("C. orçamento: %d peças (%d instâncias)", parts, #forge:GetDescendants()))
		check(lights == 0 and bills == 0 and emittersN <= 2, "C. sem luz, sem BillboardGui, no máximo 2 emissores")
		check(forgePrompts == 0, "C. a forja não tem prompt: a compra continua nos pads da galeria")
		-- Os pads de compra continuam os mesmos (um prompt por Corte pago).
		local CutLogic = E.require(E.Shared.Formulas.CutLogic)
		local paid, padPrompts = 0, 0
		for _, cut in CutLogic.Ordered() do
			if cut.Price > 0 then
				paid += 1
			end
		end
		for _, d in world:GetDescendants() do
			if d:IsA("ProximityPrompt") and d:GetAttribute("CutId") then
				if d.Parent and string.sub(d.Parent.Name, 1, 7) == "CutPad_" and d.Parent.Name == "CutPad_" .. d:GetAttribute("CutId") then
					padPrompts += 1
				end
			end
		end
		check(padPrompts == paid, string.format("C. %d prompts de compra, um em cada pad de Corte pago (como antes)", padPrompts))
		-- Fora da avenida e da galeria: atrás da fileira norte, dentro do adro, antes do portão.
		local stations = LobbyConfig.CutStations
		local CutConfig = E.require(E.Shared.Config.CutConfig)
		local rowOuter = stations.ClearHalfWidth + CutConfig.Layout.PadSize
		local tower = LobbyConfig.Areas.Tower
		check(maxZ <= -rowOuter and minZ >= -tower.Radius - 0.05, string.format("C. fora da avenida e da galeria: z de %.1f a %.1f (pads até %.1f; adro até %.1f)", minZ, maxZ, -rowOuter, -tower.Radius))
		check(minX >= tower.Offset.X - tower.Radius and maxX <= WallConfig.Layout.StartX, string.format("C. estrutura dentro do adro, antes do portão (x %.1f a %.1f)", minX, maxX))
		local padXs = {}
		for _, d in world:GetDescendants() do
			if d:IsA("BasePart") and string.sub(d.Name, 1, 7) == "CutPad_" then
				table.insert(padXs, d.CFrame.Position.X)
			end
		end
		local galleryMin, galleryMax = math.min(table.unpack(padXs)) - CutConfig.Layout.PadSize / 2, math.max(table.unpack(padXs)) + CutConfig.Layout.PadSize / 2
		check(railMinX >= galleryMin and railMaxX <= galleryMax, string.format("C. trilho no chão só ao longo da galeria (x %.1f a %.1f; pads de %.1f a %.1f)", railMinX, railMaxX, galleryMin, galleryMax))
		local shopFloor = LobbyConfig.Areas.Shop
		check(minX > shopFloor.Offset.X + shopFloor.FloorSize.X / 2 + 3, "C. não invade a área da Loja/Melhorias")
		check(top <= 17 and top < LobbyConfig.Gate.PillarHeight * 0.4, string.format("C. %.1f studs de altura: não compete com o portão (pilares de %d)", top, LobbyConfig.Gate.PillarHeight))
		-- Canais de energia: a onda vai dos braços para o centro.
		local outerOrder, innerOrder = 0, 0
		for _, d in forge:GetDescendants() do
			if d.Name == "ForgeConduit" then
				local lateral = math.abs((d.CFrame.Position - forge:FindFirstChild("ForgeBack").CFrame.Position):Dot(V3.new(1, 0, 0)))
				if d:GetAttribute("Order") == 1 then
					outerOrder = math.max(outerOrder, lateral)
				elseif d:GetAttribute("Order") == 3 then
					innerOrder = math.max(innerOrder, lateral)
				end
			end
		end
		check(outerOrder > innerOrder, "C. energia viaja pelos condutores de fora para o centro (1 → 3)")
		-- Cliente: o slash na cor do Corte do jogador; troca quando ele troca.
		local CutVisuals = E.require(E.Shared.Formulas.CutVisuals)
		local slash = forge:FindFirstChild("CutSlash")
		local sparks = forge:FindFirstChildWhichIsA("ParticleEmitter", true)
		local function near(a, b)
			return math.abs(a.R - b.R) < 0.01 and math.abs(a.G - b.G) < 0.01 and math.abs(a.B - b.B) < 0.01
		end
		check(slash and near(slash.Color, CutVisuals.ForBest("Cut1").Color), "C. slash na cor do Corte do jogador (Cut1)")
		playerAttributes.BestCut = "Cut6"
		if bestCutChanged then
			bestCutChanged()
		end
		check(slash and near(slash.Color, CutVisuals.ForBest("Cut6").Color) and sparks and near(sparks.Color.Keypoints[1].Value, CutVisuals.ForBest("Cut6").Color), "C. trocou de Corte: slash e faíscas mudam de cor (cliente, sem reconstruir nada)")
		check(near(forge:FindFirstChild("ConductorArm").Color, StationMachinesTheme().Stone), "C. a estrutura mantém a cor própria")
		-- Clarão ocasional e "Efeitos reduzidos".
		local veil = forge:FindFirstChild("CutSlashVeil")
		camera.CFrame = CF.new(veil.CFrame.Position + V3.new(0, 4, 20))
		local flashed, baseVeil = false, veil.Transparency
		for _ = 1, 60 * 6 do
			t += 1 / 60
			Fx.Step(t)
			if veil.Transparency < baseVeil - 0.2 then
				flashed = true
			end
		end
		check(flashed and veil.Transparency >= 0.7, "C. clarão curto de tempos em tempos (mini-impacto), voltando ao normal")
		settings.ReducedEffects = true
		t += 1.1
		Fx.Step(t)
		local anyOn = false
		for _, d in world:GetDescendants() do
			if d:IsA("ParticleEmitter") and d:HasTag("StationParticles") and d.Enabled then
				anyOn = true
			end
		end
		check(not anyOn, "C. \"Efeitos reduzidos\": partículas das estações desligadas")
		settings.ReducedEffects = false
		t += 1.1
		Fx.Step(t)
		check(sparks.Enabled, "C. e voltam quando desliga")
		-- O visual não mexe em Corte de verdade.
		local fsMod = require("@lune/fs")
		local clean = true
		for _, path in { "src/server/World/StationMachines.luau", "src/client/Controllers/StationFxController.luau" } do
			local source = fsMod.readFile(E.Root .. "/" .. path)
			for _, word in { "CutConfig", "CutLogic", "FireServer", "InvokeServer", "Damage", "cut.Price", "PerClick" } do
				if string.find(source, word, 1, true) then
					clean = false
					print("      " .. path .. " usa " .. word)
				end
			end
		end
		check(clean, "C. VFX da forja não toca em Corte de verdade (sem CutConfig/CutLogic, preço, dano ou remote)")
	end
end

if #problems > 0 then
	print(#problems .. " problema(s).")
	process.exit(1)
end
print("OK: estação de Melhorias como máquina (protótipo) — mesma interação, dentro do orçamento, reversível pelo LobbyConfig.")
print("REQUER VALIDAÇÃO NO ROBLOX STUDIO: materiais, Neon, partículas, leitura das placas e se o técnico ajuda ou polui.")
process.exit(0)
