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

local map = Instance.new("Folder")
map.Name = "Map"
map.Parent = E.Workspace
local model = WorldBuilder.Build(WorldConfig.Worlds[WorldConfig.DefaultWorld], V3.new(0, 0, 0), Instance.new("Folder"), Instance.new("Folder"), true)
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
