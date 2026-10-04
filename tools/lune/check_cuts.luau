--[[
	check_cuts.luau — a vitrine dos Cortes (CutShowcaseController) e a camada
	de corte do golpe (SlashController), de verdade, sobre o mapa gerado pelo
	WorldBuilder.

		lune run tools/lune/check_cuts.luau [raiz]

	Verifica:
	  1. ESTAÇÕES  — cada corte do CutConfig tem pad, pedestal, âncora do orbe e
	                 placa; nada disso colide (o adro é a avenida); o prompt de
	                 compra continua o mesmo (CutId, distância 12).
	  2. LEITURA   — vistas da avenida (várias posições de câmera), as placas e
	                 os nomes das estações não se sobrepõem na tela.
	  3. ESTADOS   — ATIVO / COMPRADO / DISPONÍVEL / BLOQUEADO conforme os
	                 dados do jogador; "Comprar" some só de quem já tem.
	  4. MESMA CONFIG — a vitrine toca exatamente CutVisuals.For(corte) (ou a
	                 versão apagada, se bloqueado) e o golpe do jogador toca
	                 CutVisuals.For(BestCut): a mesma receita.
	  5. LAÇO      — 1,5–3 s de pausa entre demonstrações; nada perto = nada
	                 toca; longe = peças apagadas; "efeitos reduzidos" = nada.
	  6. LIMPEZA   — peças da vitrine não acumulam (contagem estável em 3 min
	                 simulados), Destroy apaga tudo, nenhuma conexão nova por
	                 passo do laço, faíscas limitadas.
	  7. SEM EFEITO COLATERAL — a vitrine e o golpe não mandam nada ao servidor,
	                 não mexem nos dados, não concedem corte; o requisito
	                 continua no CutService (CanBuy).

	REQUER VALIDAÇÃO NO STUDIO: cor, partículas, trail, tamanho, brilho, leitura
	real de SurfaceGui/BillboardGui. Aqui só se mede geometria e lógica.

	Sai com código 1 se algum problema for encontrado.
]]
local process = require("@lune/process")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local E = require("./env")(process.args[1])
local V3 = roblox.Vector3
local Instance = roblox.Instance

local problems = {}
local function fail(message: string)
	table.insert(problems, message)
end
local function check(condition: any, message: string)
	if not condition then
		fail(message)
	end
end

-- ── Ambiente do cliente ─────────────────────────────────────────────────────
local connects = 0
local Sig = {
	Connect = function()
		connects += 1
		return { Disconnect = function() end }
	end,
	Once = function()
		return { Disconnect = function() end }
	end,
	Wait = function() end,
}
for _, pair in {
	{ "Instance", { "Changed", "ChildAdded", "ChildRemoved", "Destroying", "AncestryChanged", "AttributeChanged", "DescendantAdded" } },
	{ "ProximityPrompt", { "Triggered", "PromptShown", "PromptHidden" } },
} do
	for _, name in pair[2] do
		roblox.implementProperty(pair[1], name, function()
			return Sig
		end)
	end
end
roblox.implementMethod("Instance", "GetAttributeChangedSignal", function()
	return Sig
end)
local emits = {}
roblox.implementMethod("ParticleEmitter", "Emit", function(_, count)
	table.insert(emits, count)
end)

-- Relógio controlado: o laço e os limites de intervalo usam os.clock.
local now = 1000
E.extraGlobals.os = setmetatable({ clock = function()
	return now
end }, { __index = os })
E.extraGlobals.TweenInfo = { new = function(...)
	return { ... }
end }
local tweens = 0
E.stubs.TweenService = { Create = function(_, instance, _, goal)
	return { Play = function()
		tweens += 1
		-- Simula o fim do tween: aplica o objetivo (o próximo uso parte dele).
		for key, value in goal do
			instance[key] = value
		end
	end, Cancel = function() end }
end }

local playerGui = Instance.new("Folder")
playerGui.Name = "PlayerGui"
local attributes = { BestCut = "Cut1" }
local character = Instance.new("Model")
local rootPart = Instance.new("Part")
rootPart.Name = "HumanoidRootPart"
rootPart.Parent = character
local localPlayer = {
	Name = "Tester",
	UserId = 1,
	LocaleId = "pt-br",
	Character = character,
	WaitForChild = function(_, n)
		return if n == "PlayerGui" then playerGui else nil
	end,
	FindFirstChild = function(_, n)
		return if n == "PlayerGui" then playerGui else nil
	end,
	GetAttribute = function(_, key)
		return attributes[key]
	end,
	SetAttribute = function(_, key, value)
		attributes[key] = value
	end,
	GetAttributeChangedSignal = function()
		return Sig
	end,
	CharacterAdded = Sig,
}
E.stubs.Players = { LocalPlayer = localPlayer, GetPlayers = function()
	return { localPlayer }
end, PlayerAdded = Sig, PlayerRemoving = Sig }

-- Rede: tudo o que o cliente mandaria ao servidor é contado (tem de ser 0).
local sent = 0
local handlers = {}
E.stubModules["StarterPlayer.Client.Net.ClientNet"] = setmetatable({
	On = function(name, fn)
		handlers[name] = fn
	end,
	Fire = function()
		sent += 1
	end,
	Invoke = function()
		sent += 1
		return { Ok = false }
	end,
}, { __index = function()
	return function()
		sent += 1
	end
end })

-- O laço de fundo da vitrine (task.wait de 0,25 s) fica desligado: o teste
-- chama CutShowcaseController.Tick com relógio e posição simulados.
E.patches["StarterPlayer.Client.Controllers.CutShowcaseController"] = {
	{ "		while true do\n			task.wait(TICK_SECONDS)", "		while false do\n			task.wait(TICK_SECONDS)" },
}

-- ── Mundo ───────────────────────────────────────────────────────────────────
local WorldBuilder = E.require(E.Server.World.WorldBuilder)
local WorldConfig = E.require(E.Shared.Config.WorldConfig)
local CutConfig = E.require(E.Shared.Config.CutConfig)
local CutLogic = E.require(E.Shared.Formulas.CutLogic)
local CutVisuals = E.require(E.Shared.Formulas.CutVisuals)
local SwordConfig = E.require(E.Shared.Config.SwordConfig)
local LobbyConfig = E.require(E.Shared.Config.LobbyConfig)
local WallConfig = E.require(E.Shared.Config.WallConfig)

local map = Instance.new("Folder")
map.Name = "Map"
map.Parent = E.Workspace
local spawnsFolder = Instance.new("Folder")
local model = WorldBuilder.Build(WorldConfig.Worlds[WorldConfig.DefaultWorld], V3.new(0, 0, 0), Instance.new("Folder"), spawnsFolder, true)
model.Parent = map

local layout = CutConfig.Layout
local ordered = CutLogic.Ordered()
-- Índice por nome (FindFirstChild recursivo no mapa inteiro é lento no Lune).
local byName = {}
for _, d in model:GetDescendants() do
	if string.find(d.Name, "^Cut") and not byName[d.Name] then
		byName[d.Name] = d
	end
end
local function find(name)
	return byName[name]
end

-- 1. Estações
for _, cut in ordered do
	local pad = find("CutPad_" .. cut.Id)
	local anchor = find("CutShowcase_" .. cut.Id)
	local card = find("CutCard_" .. cut.Id)
	local pedestal = find("CutPedestal_" .. cut.Id)
	check(pad, cut.Id .. ": sem pad")
	check(anchor and anchor:GetAttribute("CutShowcase") == true and anchor:GetAttribute("CutId") == cut.Id, cut.Id .. ": sem âncora da vitrine")
	check(card and card:GetAttribute("CutId") == cut.Id, cut.Id .. ": sem placa")
	check(pedestal, cut.Id .. ": sem pedestal")
	for _, part in { pad, anchor, card, pedestal } do
		if part then
			check(not part.CanCollide, cut.Id .. ": " .. part.Name .. " colide (fica na avenida)")
		end
	end
	for _, part in { anchor, card } do
		if part then
			check(not part.CanQuery and not part.CanTouch, cut.Id .. ": " .. part.Name .. " recebe toque/raycast")
		end
	end
	if pad then
		local prompt = pad:FindFirstChildOfClass("ProximityPrompt")
		if cut.Price > 0 then
			check(prompt and prompt:GetAttribute("CutId") == cut.Id and prompt.MaxActivationDistance == 12, cut.Id .. ": prompt de compra mudou")
		else
			check(prompt == nil, cut.Id .. ": corte inicial não deveria ter prompt")
		end
	end
	if anchor and pad then
		-- A estação olha para a avenida (eixo do adro) e um pouco para quem chega.
		local look = anchor.CFrame.LookVector
		local towardAxis = -math.sign(pad.CFrame.Position.Z)
		check(look.X < 0 and look.Z * towardAxis > 0.5, string.format("%s: estação não olha para a avenida (look %.2f, %.2f)", cut.Id, look.X, look.Z))
		check(anchor.CFrame.Position.Y - pad.CFrame.Position.Y > layout.PedestalHeight, cut.Id .. ": orbe abaixo do topo do pedestal")
	end
	if card and pad then
		-- A placa girada não sai do pad para a faixa do meio da avenida.
		local h = card.Size / 2
		local padHalf = pad.Size.X / 2
		for _, corner in { V3.new(-h.X, -h.Y, 0), V3.new(h.X, -h.Y, 0), V3.new(-h.X, h.Y, 0), V3.new(h.X, h.Y, 0) } do
			local p = card.CFrame:PointToWorldSpace(corner)
			check(math.abs(p.Z - pad.CFrame.Position.Z) <= padHalf + 0.05 and math.abs(p.X - pad.CFrame.Position.X) <= padHalf + 0.05, string.format("%s: placa sai do pad (quina dx %.2f dz %.2f)", cut.Id, p.X - pad.CFrame.Position.X, p.Z - pad.CFrame.Position.Z))
		end
	end
	if card and anchor then
		local cardTop = card.CFrame:PointToWorldSpace(V3.new(0, card.Size.Y / 2, 0)).Y
		check(cardTop < anchor.CFrame.Position.Y - 1.2, cut.Id .. ": placa tapa o orbe")
	end
end

-- 1b. Zona livre da avenida (teste no Studio: as fileiras faziam um funil).
local stationsCfg = LobbyConfig.CutStations
local CLEAR = stationsCfg.ClearHalfWidth
-- Largura mínima da zona livre, independente da config: 2x o vão de 4 studs
-- entre os pads que travou a avenida no teste do Studio.
local MIN_CLEAR_WIDTH = 8
check(CLEAR * 2 >= MIN_CLEAR_WIDTH, string.format("zona livre: %.1f studs (mínimo %d)", CLEAR * 2, MIN_CLEAR_WIDTH))
local axisZ = 0
for _, area in LobbyConfig.Areas do
	if area.Id == layout.Area then
		axisZ = area.Offset.Z
	end
end
-- Tudo o que fica em cima de cada pad é da estação (pad, inserto, pedestal,
-- tampa, placa, suporte, âncora).
local stationParts = {}
local stationSet = {}
-- No Lune cada leitura devolve um objeto novo: a chave é a geometria.
local function keyOf(part)
	local p, z = part.CFrame.Position, part.Size
	return string.format("%s|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f", part.Name, p.X, p.Y, p.Z, z.X, z.Y, z.Z)
end
local function corners(part)
	local h = part.Size / 2
	local list = {}
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				table.insert(list, part.CFrame:PointToWorldSpace(V3.new(sx * h.X, sy * h.Y, sz * h.Z)))
			end
		end
	end
	return list
end
for _, cut in ordered do
	local pad = find("CutPad_" .. cut.Id)
	local list = {}
	local half = pad.Size.X / 2
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local offset = d.CFrame.Position - pad.CFrame.Position
			if math.abs(offset.X) <= half and math.abs(offset.Z) <= half and offset.Y >= -0.01 and offset.Y < 12 then
				table.insert(list, d)
				stationSet[keyOf(d)] = true
			end
		end
	end
	stationParts[cut.Id] = list
end

local innerObjects, innerPads = math.huge, math.huge
for _, cut in ordered do
	for _, part in stationParts[cut.Id] do
		for _, corner in corners(part) do
			local fromAxis = math.abs(corner.Z - axisZ)
			if fromAxis < CLEAR - 0.01 then
				fail(string.format("zona livre: %s (%s) entra %.2f studs na zona central", part.Name, cut.Id, CLEAR - fromAxis))
				break
			end
			if part.Name == "CutPad_" .. cut.Id then
				innerPads = math.min(innerPads, fromAxis)
			elseif corner.Y > part.CFrame.Position.Y - 10 and part.Size.Y > 0.3 or part.Name == "CutCard_" .. cut.Id then
				innerObjects = math.min(innerObjects, fromAxis)
			end
		end
	end
end

-- Orbe (cliente), prompt e efeito da demonstração.
local showcaseSrc = fs.readFile(E.Root .. "/src/client/Controllers/CutShowcaseController.luau")
local fxSrc = fs.readFile(E.Root .. "/src/client/Effects/CutFx.luau")
local ORB_SIZE = tonumber(string.match(showcaseSrc, "local ORB_SIZE = ([%d%.]+)"))
local SHOWCASE_SCALE = tonumber(string.match(showcaseSrc, "local SHOWCASE_SCALE = ([%d%.]+)"))
local _, maxLife = string.match(fxSrc, "Lifetime = NumberRange%.new%(([%d%.]+), ([%d%.]+)%)")
local _, maxSpeed = string.match(fxSrc, "Speed = NumberRange%.new%(([%d%.]+), ([%d%.]+)%)")
local drag = tonumber(string.match(fxSrc, "emitter%.Drag = ([%d%.]+)"))
-- Distância máxima de uma faísca: v/arrasto · (1 − e^(−arrasto·vida)).
local SPARK_REACH = tonumber(maxSpeed) / drag * (1 - math.exp(-drag * tonumber(maxLife)))
local VFX_MARGIN = 1 -- os riscos param pelo menos 1 stud antes da zona livre
local innerVfx, innerSparks = math.huge, math.huge
for _, cut in ordered do
	local anchor = find("CutShowcase_" .. cut.Id)
	local pad = find("CutPad_" .. cut.Id)
	local orbInner = math.abs(anchor.CFrame.Position.Z - axisZ) - ORB_SIZE / 2
	check(orbInner >= CLEAR + VFX_MARGIN, string.format("zona livre: orbe de %s a %.2f do eixo", cut.Id, orbInner))
	innerObjects = math.min(innerObjects, orbInner)
	-- Prompt: no pad (fora da zona) e alcançável da borda da avenida.
	local prompt = pad:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		local edge = V3.new(pad.CFrame.Position.X, pad.CFrame.Position.Y, axisZ + math.sign(pad.CFrame.Position.Z - axisZ) * CLEAR)
		check((edge - pad.CFrame.Position).Magnitude <= prompt.MaxActivationDistance, cut.Id .. ": prompt não alcança da borda da avenida")
		check(math.abs(pad.CFrame.Position.Z - axisZ) >= CLEAR, cut.Id .. ": prompt dentro da zona livre")
	end
	-- Efeito: os riscos (tamanho inicial e final, nos dois extremos da
	-- varredura) do corte com a receita mais longa e as faíscas.
	local origin = anchor.CFrame * E.roblox.CFrame.new(0, 0, -(ORB_SIZE / 2 + 0.3))
	for _, other in ordered do
		local recipe = CutVisuals.For(other.Id)
		local length, width = recipe.Length * SHOWCASE_SCALE, recipe.Width * SHOWCASE_SCALE
		for _, angle in CutVisuals.Angles(recipe.Slashes) do
			for _, sweep in { -recipe.Sweep / 2, recipe.Sweep / 2 } do
				for _, size in { V3.new(recipe.Thickness, length * 0.45, width), V3.new(recipe.Thickness, length, width * 0.4) } do
					local cf = origin * E.roblox.CFrame.Angles(0, 0, math.rad(angle + sweep))
					local h = size / 2
					for _, sx in { -1, 1 } do
						for _, sy in { -1, 1 } do
							for _, sz in { -1, 1 } do
								local p = cf:PointToWorldSpace(V3.new(sx * h.X, sy * h.Y, sz * h.Z))
								innerVfx = math.min(innerVfx, math.abs(p.Z - axisZ))
							end
						end
					end
				end
			end
		end
	end
	innerSparks = math.min(innerSparks, math.abs(origin.Position.Z - axisZ) - SPARK_REACH)
end
check(innerVfx >= CLEAR + VFX_MARGIN, string.format("efeito: riscos da vitrine chegam a %.2f do eixo (mínimo %.2f)", innerVfx, CLEAR + VFX_MARGIN))
check(innerSparks >= CLEAR, string.format("efeito: faíscas chegam a %.2f do eixo (zona livre %.2f)", innerSparks, CLEAR))

-- Simetria das fileiras.
local columns = layout.Columns
for index = 1, columns do
	local a, b = ordered[index], ordered[index + columns]
	if a and b then
		for _, prefix in { "CutPad_", "CutCard_", "CutShowcase_" } do
			local pa, pb = find(prefix .. a.Id).CFrame.Position, find(prefix .. b.Id).CFrame.Position
			check(math.abs(pa.X - pb.X) < 0.01 and math.abs((pa.Z - axisZ) + (pb.Z - axisZ)) < 0.01 and math.abs(pa.Y - pb.Y) < 0.01,
				string.format("simetria: %s%s e %s%s não se espelham no eixo", prefix, a.Id, prefix, b.Id))
		end
	end
end

-- Dentro do adro (longe do paredão) e sem invadir outra coisa do lobby.
local towerArea = LobbyConfig.Areas[layout.Area]
local others = {}
for _, d in model:GetDescendants() do
	if d:IsA("BasePart") and not stationSet[keyOf(d)] and d.Transparency < 1 then
		-- Caixa alinhada pelas 8 quinas (vale para peças giradas e discos).
		local x0, x1, y0, y1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge
		for _, c in corners(d) do
			x0, x1, y0, y1, z0, z1 = math.min(x0, c.X), math.max(x1, c.X), math.min(y0, c.Y), math.max(y1, c.Y), math.min(z0, c.Z), math.max(z1, c.Z)
		end
		-- Só o que fica de pé acima do piso e na altura de uma estação.
		if y1 > 0.8 and y0 < 12 then
			table.insert(others, { part = d, box = { x0, x1, z0, z1 } })
		end
	end
end
for _, cut in ordered do
	local pad = find("CutPad_" .. cut.Id)
	local p, half = pad.CFrame.Position, pad.Size.X / 2
	check(math.abs(p.Z - towerArea.Offset.Z) + half <= towerArea.Radius - 1, cut.Id .. ": estação sai do adro do portão")
	for _, other in others do
		local box = other.box
		if box[1] < p.X + half and box[2] > p.X - half and box[3] < p.Z + half and box[4] > p.Z - half then
			local o = other.part.CFrame.Position
			fail(string.format("%s: estação encosta em %s (%.0f, %.0f, %.0f)", cut.Id, other.part.Name, o.X, o.Y, o.Z))
		end
	end
end

-- Vista do spawn: nada da estação na janela avenida → barreira 1.
local spawnPart = spawnsFolder:GetChildren()[1]
local barrier = byName["Wall_" .. WallConfig.Stages[1].Id .. "_1"] or model:FindFirstChild("Wall_" .. WallConfig.Stages[1].Id .. "_1", true)
local spawnGap = 0
if spawnPart and barrier then
	local look = spawnPart.CFrame.LookVector
	local flat = V3.new(look.X, 0, look.Z).Unit
	local eye = spawnPart.CFrame.Position + V3.new(0, 8, 0) - flat * 14 -- câmera do SpawnCameraController
	local cam = E.CFrame.lookAt(eye, eye + flat)
	local function screen(point)
		local q = cam:PointToObjectSpace(point)
		return q.X / -q.Z, q.Y / -q.Z, -q.Z
	end
	local front = barrier.CFrame.Position.X - barrier.Size.X / 2
	local wallTop = barrier.CFrame.Position.Y + barrier.Size.Y / 2
	local wx0 = screen(V3.new(front, 0, axisZ - CLEAR))
	local wx1 = screen(V3.new(front, 0, axisZ + CLEAR))
	local _, wy1 = screen(V3.new(front, wallTop, axisZ))
	local _, wy0 = screen(V3.new(front, 0, axisZ))
	local left, right = -math.huge, math.huge
	for _, cut in ordered do
		for _, part in stationParts[cut.Id] do
			if part.Transparency < 1 then
				local x0, x1, y0, y1 = math.huge, -math.huge, math.huge, -math.huge
				for _, corner in corners(part) do
					local x, y = screen(corner)
					x0, x1, y0, y1 = math.min(x0, x), math.max(x1, x), math.min(y0, y), math.max(y1, y)
				end
				if x1 > math.min(wx0, wx1) and x0 < math.max(wx0, wx1) and y1 > wy0 and y0 < wy1 then
					fail(string.format("vista do spawn: %s (%s) cobre a janela avenida → barreira 1", part.Name, cut.Id))
				end
				if (part.CFrame.Position.Z - axisZ) < 0 then
					left = math.max(left, x1)
				else
					right = math.min(right, x0)
				end
			end
		end
	end
	-- Abertura entre as duas fileiras, em graus, vista da câmera do spawn.
	spawnGap = math.deg(math.atan(right) - math.atan(left))
else
	fail("vista do spawn: marcador ou barreira 1 não encontrados")
end

-- 2. Leitura: projeções vistas da avenida.
local FOV_TAN = math.tan(math.rad(35))
local ASPECT = 16 / 9
local CARD_MAX = layout.CardReadDistance
local NAME_MAX = layout.NameReadDistance
-- Medidas do nome e do orbe: constantes do próprio controller.
local showcaseText = fs.readFile(E.Root .. "/src/client/Controllers/CutShowcaseController.luau")
local nameW, nameH = string.match(showcaseText, "local NAME_SIZE = Vector2%.new%(([%d%.]+), ([%d%.]+)%)")
local NAME_SIZE = { tonumber(nameW), tonumber(nameH) }
local ORB = tonumber(string.match(showcaseText, "local ORB_SIZE = ([%d%.]+)"))
local function project(cam, point)
	local p = cam:PointToObjectSpace(point)
	if p.Z > -0.5 then
		return nil
	end
	return p.X / -p.Z, p.Y / -p.Z
end
local function rect(cam, corners)
	local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
	for _, corner in corners do
		local x, y = project(cam, corner)
		if not x then
			return nil
		end
		x0, y0, x1, y1 = math.min(x0, x), math.min(y0, y), math.max(x1, x), math.max(y1, y)
	end
	if x1 < -FOV_TAN * ASPECT or x0 > FOV_TAN * ASPECT or y1 < -FOV_TAN or y0 > FOV_TAN then
		return nil
	end
	return { x0, y0, x1, y1 }
end
local function overlap(a, b)
	local w = math.min(a[3], b[3]) - math.max(a[1], b[1])
	local h = math.min(a[4], b[4]) - math.max(a[2], b[2])
	if w <= 0 or h <= 0 then
		return 0
	end
	local area = math.min((a[3] - a[1]) * (a[4] - a[2]), (b[3] - b[1]) * (b[4] - b[2]))
	return (w * h) / area
end

local views = {}
for x = 70, 150, 10 do
	for _, z in { -1.5, 0, 1.5 } do
		-- Câmera de terceira pessoa: atrás e acima do personagem, olhando a avenida.
		table.insert(views, { eye = V3.new(x - 10, 8, z), target = V3.new(x + 20, 4, z) })
	end
end
for _, cut in ordered do
	local anchor = find("CutShowcase_" .. cut.Id)
	local pos = anchor.CFrame.Position
	-- Olhando para a estação, da avenida, a caminho dela.
	table.insert(views, { eye = V3.new(pos.X - 14, 8, 0), target = pos })
	table.insert(views, { eye = V3.new(pos.X - 4, 8, 0), target = pos })
end

local worstOverlap, worstWhere = 0, ""
for _, view in views do
	local cam = E.CFrame.lookAt(view.eye, view.target)
	local boxes = {}
	for _, cut in ordered do
		local card = find("CutCard_" .. cut.Id)
		local anchor = find("CutShowcase_" .. cut.Id)
		local cardCentre = card.CFrame.Position
		local toEye = (view.eye - cardCentre)
		if toEye.Magnitude <= CARD_MAX and card.CFrame.LookVector:Dot(toEye.Unit) > 0.15 then
			local h = card.Size / 2
			local box = rect(cam, {
				card.CFrame:PointToWorldSpace(V3.new(-h.X, -h.Y, 0)),
				card.CFrame:PointToWorldSpace(V3.new(h.X, -h.Y, 0)),
				card.CFrame:PointToWorldSpace(V3.new(-h.X, h.Y, 0)),
				card.CFrame:PointToWorldSpace(V3.new(h.X, h.Y, 0)),
			})
			if box then
				table.insert(boxes, { id = cut.Id .. " placa", box = box, depth = toEye.Magnitude })
			end
		end
		local namePos = anchor.CFrame.Position + V3.new(0, ORB / 2 + NAME_SIZE[2] / 2 + 0.4, 0)
		local toName = view.eye - namePos
		if toName.Magnitude <= NAME_MAX then
			-- Billboard: sempre de frente para a câmera.
			local right = cam.RightVector * (NAME_SIZE[1] / 2)
			local up = cam.UpVector * (NAME_SIZE[2] / 2)
			local box = rect(cam, { namePos - right - up, namePos + right - up, namePos - right + up, namePos + right + up })
			if box then
				table.insert(boxes, { id = cut.Id .. " nome", box = box, depth = toName.Magnitude })
			end
		end
	end
	for i = 1, #boxes do
		for j = i + 1, #boxes do
			local a, b = boxes[i], boxes[j]
			if string.sub(a.id, 1, 4) ~= string.sub(b.id, 1, 4) then
				local amount = overlap(a.box, b.box)
				if amount > worstOverlap then
					worstOverlap = amount
					worstWhere = string.format("%s x %s (câmera em %.0f, %.0f, %.0f)", a.id, b.id, view.eye.X, view.eye.Y, view.eye.Z)
				end
			end
		end
	end
end
local OVERLAP_LIMIT = 0.15
if worstOverlap > OVERLAP_LIMIT then
	fail(string.format("leitura: textos de estações diferentes se sobrepõem %.0f%% — %s", worstOverlap * 100, worstWhere))
end

-- ── Controllers do cliente ──────────────────────────────────────────────────
local DataController = E.require(E.Client.Controllers.DataController)
local CutShowcase = E.require(E.Client.Controllers.CutShowcaseController)
local Slash = E.require(E.Client.Controllers.SlashController)
local CutFx = E.require(E.Client.Effects.CutFx)

-- Espião no desenho compartilhado: quem tocou qual receita.
local played = {}
local originalPlay = CutFx.Play
CutFx.Play = function(rig, recipe, origin, scale, roll)
	table.insert(played, { rig = rig, recipe = recipe })
	return originalPlay(rig, recipe, origin, scale, roll)
end

DataController.Init()
local snapshot = {
	Cuts = { Owned = { Cut1 = true } },
	Currencies = { Power = 0, Wins = 1, Gems = 0 },
	Settings = { ReducedEffects = false },
}
handlers.DataSnapshot(snapshot)
CutShowcase.Init()
Slash.Init()
CutShowcase.Start()

local stations = CutShowcase.Stations()
check(#stations == #ordered, string.format("vitrine: %d estações de %d cortes", #stations, #ordered))
local byId = {}
for _, station in stations do
	byId[station.CutId] = station
end

-- 3. Estados
local function expectState(cutId, state, label)
	local station = byId[cutId]
	if not station then
		return fail("estado: estação " .. cutId .. " não existe")
	end
	check(station.State == state, string.format("estado (%s): %s é %s, esperado %s", label, cutId, tostring(station.State), state))
	local Text = E.require(E.Shared.Localization)
	check(station.Status and station.Status.Text == Text.Get("cut.state." .. state), string.format("estado (%s): placa de %s não diz %s", label, cutId, state))
	local owned = state == "Active" or state == "Owned"
	if station.Prompt then
		check(station.Prompt.Enabled == not owned, string.format("estado (%s): prompt de %s deveria estar %s", label, cutId, if owned then "escondido" else "visível"))
	end
	check((station.Stroke.Transparency == 0) == (state == "Available"), string.format("estado (%s): destaque de %s errado", label, cutId))
	if state == "Locked" then
		check(station.Orb.Material ~= roblox.Enum.Material.Neon, string.format("estado (%s): orbe de %s bloqueado ainda brilha", label, cutId))
	end
end
expectState("Cut1", "Active", "jogador novo")
expectState("Cut2", "Available", "jogador novo")
expectState("Cut3", "Locked", "jogador novo")
expectState("Cut8", "Locked", "jogador novo")

handlers.DataChanged("Cuts", { Owned = { Cut1 = true, Cut2 = true, Cut3 = true } })
handlers.DataChanged("Currencies", { Power = 0, Wins = 30, Gems = 0 })
expectState("Cut1", "Owned", "comprou até o 3")
expectState("Cut2", "Owned", "comprou até o 3")
expectState("Cut3", "Active", "comprou até o 3")
expectState("Cut4", "Available", "comprou até o 3")
expectState("Cut5", "Locked", "comprou até o 3")
for _, station in stations do
	local text = station.Need and station.Need.Text or ""
	check(#text > 0 and station.Bonus and #station.Bonus.Text > 0, station.CutId .. ": placa sem bônus/requisito")
end

-- 4/5/6. Laço da vitrine.
local folder = (E.Workspace :: any):FindFirstChild("CutShowcase", true)
check(folder, "vitrine: pasta de efeitos não existe")
local function countParts()
	local n = 0
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end
local baseline = countParts()
check(baseline == #ordered, string.format("vitrine: %d peças fixas, esperado %d orbes", baseline, #ordered))

local spawnPos = V3.new(-30, 3, 0)
local nearPos = V3.new(130, 3, 0)
local playsBefore = #played
for _ = 1, 40 do
	now += 0.25
	CutShowcase.Tick(now, spawnPos, false)
end
check(#played == playsBefore, "vitrine: tocou com o jogador no spawn (longe)")
check(countParts() == baseline, "vitrine: criou peças com o jogador longe")
for _ = 1, 40 do
	now += 0.25
	CutShowcase.Tick(now, nil, false)
end
check(#played == playsBefore, "vitrine: tocou sem personagem")

local lastAt, gaps, perStation = {}, {}, {}
local connectsBefore = connects
local maxParts = 0
local partsAfter60 = nil
local t0 = now
local showcaseRecipesOk = true
while now - t0 < 180 do
	now += 0.25
	local before = #played
	CutShowcase.Tick(now, nearPos, false)
	for index = before + 1, #played do
		local entry = played[index]
		local cutId = entry.recipe.CutId
		local station = byId[cutId]
		local expected = CutShowcase.RecipeFor(cutId, station.State)
		local base = CutVisuals.For(cutId)
		local same = true
		for key, value in expected do
			if entry.recipe[key] ~= value then
				same = false
			end
		end
		if station.State ~= "Locked" then
			for key, value in base do
				if entry.recipe[key] ~= value then
					same = false
				end
			end
		end
		if not same then
			showcaseRecipesOk = false
		end
		if lastAt[cutId] then
			table.insert(gaps, { cutId = cutId, gap = now - lastAt[cutId], fade = entry.recipe.FadeSeconds })
		end
		lastAt[cutId] = now
		perStation[cutId] = (perStation[cutId] or 0) + 1
	end
	maxParts = math.max(maxParts, countParts())
	if now - t0 >= 60 and not partsAfter60 then
		partsAfter60 = countParts()
	end
end
check(showcaseRecipesOk, "mesma config: a vitrine tocou uma receita diferente de CutVisuals.For (ou Locked)")
for _, cut in ordered do
	check((perStation[cut.Id] or 0) > 0, "vitrine: " .. cut.Id .. " nunca tocou com o jogador perto")
end
local minGap, maxGap = math.huge, 0
for _, g in gaps do
	local pause = g.gap - g.fade
	minGap = math.min(minGap, pause)
	maxGap = math.max(maxGap, pause)
end
check(minGap >= 1.5 - 1e-6, string.format("laço: pausa mínima %.2f s (< 1,5 s: pisca)", minGap))
check(maxGap <= 3 + 0.25 + 1e-6, string.format("laço: pausa máxima %.2f s (> 3 s + passo)", maxGap))
local rigParts = #ordered * (CutVisuals.MAX_SLASHES + 1)
check(maxParts <= baseline + rigParts, string.format("limpeza: %d peças (limite %d)", maxParts, baseline + rigParts))
check(countParts() == partsAfter60, string.format("limpeza: peças mudaram entre 1 min (%s) e 3 min (%d) — acumulando", tostring(partsAfter60), countParts()))
check(connects == connectsBefore, string.format("conexões: %d novas durante o laço", connects - connectsBefore))
for _, count in emits do
	check(count <= CutVisuals.MAX_SPARKS, "faíscas: Emit de " .. count)
end

-- Distância: perto de uma estação só (Cut1 a ~12 studs, Cut4 a ~53, Cut8 > 60).
local nearOnePos = V3.new(95, 3, -5)
local countsNear = {}
local mark = #played
for _ = 1, 40 do
	now += 0.25
	CutShowcase.Tick(now, nearOnePos, false)
end
for index = mark + 1, #played do
	local cutId = played[index].recipe.CutId
	countsNear[cutId] = (countsNear[cutId] or 0) + 1
end
for _, station in stations do
	local distance = (station.Anchor.CFrame.Position - nearOnePos).Magnitude
	if distance > layout.ShowcaseDistance then
		check(countsNear[station.CutId] == nil, string.format("distância: %s tocou a %.0f studs", station.CutId, distance))
	end
end
check(countsNear.Cut1 ~= nil, "distância: Cut1 (perto) não tocou")

-- Longe: efeitos apagados; volta: recriados sem acumular.
now += 0.25
CutShowcase.Tick(now, spawnPos, false)
check(countParts() == baseline, string.format("limpeza: %d peças depois de ir para longe (esperado %d)", countParts(), baseline))
for _, station in stations do
	check(station.Rig == nil, "limpeza: rig de " .. station.CutId .. " ficou vivo longe")
end
for _ = 1, 20 do
	now += 0.25
	CutShowcase.Tick(now, nearPos, false)
end
check(countParts() <= baseline + rigParts, "limpeza: peças acumularam ao voltar")
-- Efeitos reduzidos: nada toca e tudo é apagado.
mark = #played
for _ = 1, 20 do
	now += 0.25
	CutShowcase.Tick(now, nearPos, true)
end
check(#played == mark, "efeitos reduzidos: a vitrine tocou")
check(countParts() == baseline, "efeitos reduzidos: peças de efeito ficaram")

-- Rig destruído não toca e não deixa nada.
local rig = CutFx.NewRig("Teste", folder, 2)
local rigFolder = rig.Folder
CutFx.Destroy(rig)
CutFx.Destroy(rig)
-- No Lune, ler uma instância destruída lança erro; no Roblox, Parent vira nil.
local okRead, parentAfter = pcall(function()
	return rigFolder.Parent
end)
check(not okRead or parentAfter == nil, "limpeza: Destroy não removeu o rig")
originalPlay(rig, CutVisuals.For("Cut8"), roblox.CFrame.new(), 1, 0)
check(countParts() == baseline, "limpeza: rig destruído voltou a criar peças")

-- 4. Golpe real: mesma receita do melhor corte.
rootPart.CFrame = roblox.CFrame.new(130, 3, 0)
attributes.BestCut = "Cut5"
mark = #played
local emitsBefore = #emits
for _ = 1, 20 do
	now += 0.11
	Slash.Play()
end
local gameplay = 0
for index = mark + 1, #played do
	local recipe = played[index].recipe
	gameplay += 1
	for key, value in CutVisuals.For("Cut5") do
		if recipe[key] ~= value then
			fail("mesma config: o golpe tocou " .. key .. " diferente de CutVisuals.For(BestCut)")
			break
		end
	end
end
check(gameplay == 20, string.format("golpe: camada do corte tocou %d de 20 cliques", gameplay))
local gameplaySparks = #emits - emitsBefore
check(gameplaySparks > 0 and gameplaySparks <= 8, string.format("golpe: faíscas %d vezes em 2,2 s (limite ~3/s)", gameplaySparks))
-- O arco da espada continua com a cor da skin (cosmético separado).
local slashFolder = (E.Workspace :: any):FindFirstChild("SlashEffects", true)
local arcColorOk = false
for _, child in slashFolder:GetChildren() do
	if child.Name == "Slash" and child.Color == SwordConfig.Swords[SwordConfig.DefaultSword].ArcColor then
		arcColorOk = true
	end
end
check(arcColorOk, "golpe: o arco deixou de usar a cor da espada")
attributes.BestCut = "NaoExiste"
mark = #played
now += 0.2
Slash.Play()
check(played[#played] and played[#played].recipe.CutId == CutConfig.StarterCut, "golpe: BestCut inválido não caiu no corte inicial")
-- Efeitos reduzidos desligam o golpe inteiro (como antes).
handlers.DataChanged("Settings", { ReducedEffects = true })
mark = #played
now += 0.2
Slash.Play()
check(#played == mark, "golpe: tocou com efeitos reduzidos")

-- 7. Sem efeito colateral.
check(sent == 0, string.format("colateral: vitrine/golpe mandaram %d mensagens ao servidor", sent))
local cuts = DataController.Get("Cuts")
check(cuts.Owned.Cut4 == nil and cuts.Owned.Cut5 == nil, "colateral: a vitrine concedeu um corte")
check(attributes.BestCut == "NaoExiste", "colateral: atributo BestCut alterado pelo cliente")
local showcaseSource = fs.readFile(E.Root .. "/src/client/Controllers/CutShowcaseController.luau")
local fxSource = fs.readFile(E.Root .. "/src/client/Effects/CutFx.luau")
for _, pair in { { "CutShowcaseController", showcaseSource }, { "CutFx", fxSource } } do
	for _, forbidden in { "ClientNet", "RemoteEvent", "RemoteFunction", "FireServer", "InvokeServer", "InputHoldBegin", "SetAttribute" } do
		check(not string.find(pair[2], forbidden, 1, true), pair[1] .. ": usa " .. forbidden .. " (vitrine é só visual)")
	end
end
local serviceSource = fs.readFile(E.Root .. "/src/server/Services/CutService.luau")
check(string.find(serviceSource, "CutLogic.CanBuy(data.Cuts, cutId, data.Currencies.Wins)", 1, true), "servidor: CutService deixou de checar o requisito (CanBuy)")
check(string.find(serviceSource, "PromptTriggered", 1, true), "servidor: compra deixou de ser pelo PromptTriggered")

-- ── Resultado ───────────────────────────────────────────────────────────────
print(string.format("[cuts] %d estações; %d vistas da avenida, maior sobreposição entre estações %.0f%% (limite %.0f%%)", #stations, #views, worstOverlap * 100, OVERLAP_LIMIT * 100))
if worstWhere ~= "" then
	print("[cuts]   pior caso: " .. worstWhere)
end
print(string.format("[cuts] zona livre: %.1f studs (pads a %.2f do eixo, objetos a %.2f, riscos a %.2f, faíscas a %.2f)", CLEAR * 2, innerPads, innerObjects, innerVfx, innerSparks))
print(string.format("[cuts] vão entre fileiras: pads %.1f studs, objetos (pedestal/placa/orbe) %.1f studs; da câmera do spawn %.1f°", innerPads * 2, innerObjects * 2, spawnGap))
print(string.format("[cuts] pausa entre demonstrações: %.2f–%.2f s; peças de efeito no pico: %d (orbes %d)", minGap, maxGap, maxParts, baseline))
for _, cut in ordered do
	local r = CutVisuals.For(cut.Id)
	print(string.format("[cuts]   %s  cor %3d,%3d,%3d  riscos %d  tamanho %.2f  some em %.2fs  faíscas %2d  luz %2d  neon %s",
		cut.Id, math.floor(r.Color.R * 255 + 0.5), math.floor(r.Color.G * 255 + 0.5), math.floor(r.Color.B * 255 + 0.5),
		r.Slashes, cut.SlashScale, r.FadeSeconds, r.Sparks, r.LightRange, tostring(r.Glow)))
end
if #problems > 0 then
	for _, message in problems do
		print("[cuts] FALHA: " .. message)
	end
	print(string.format("[cuts] %d problema(s)", #problems))
	process.exit(1)
end
print("[cuts] OK — REQUER VALIDAÇÃO NO ROBLOX STUDIO: cor, partículas, trail, brilho e leitura real das placas")
process.exit(0)
