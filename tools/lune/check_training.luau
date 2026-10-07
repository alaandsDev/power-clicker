--[[
	check_training.luau — CAMPO DE TREINAMENTO (TrainingConfig +
	StationMachines.BuildTrainingField + TrainingService +
	TrainingFieldController).

		lune run tools/lune/check_training.luau [raiz]

	  1. config: 4 alvos com identidades distintas, rates 0,35 / 0,70 / 1,20 /
	     1,80 intactos, requisito em RENASCIMENTOS crescente (o primeiro
	     livre), raios sem sobreposição, dentro do piso da área;
	  2. mundo: os 4 alvos (pedestal, placa, boneco), progressão visível
	     (mais peças por tier, pedestal mais alto), cadeado só onde há
	     requisito, nada de HP/loot/IA (sem Humanoid, prompt, script,
	     BillboardGui ou luz), espaço livre para treinar, circulação entre os
	     pedestais e da entrada até cada placa, academia antiga removida;
	  3. servidor: 0 renascimento treina no I e não nos outros; aviso
	     "Você precisa de X Renascimentos" uma vez por entrada (pular não
	     repete); exato e acima liberam; abaixo não; pagamento =
	     poderPorClique × Rate × tempo; o serviço não ouve remote nenhum (o
	     cliente não tem como pedir treino); nada novo no save;
	  4. cliente: cadeado/energia/placa por jogador; reações (I balança, II
	     placas + faíscas, III energia, IV núcleo); longe nada mexe; parou de
	     treinar, volta ao lugar; "Efeitos reduzidos" tira as faíscas.

	REQUER VALIDAÇÃO NO ROBLOX STUDIO: leitura das placas, tamanho dos
	bonecos ao lado do avatar, ritmo das reações, aviso em jogo.
]]
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
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

local TrainingConfig = E.require(E.Shared.Config.TrainingConfig)
local LobbyConfig = E.require(E.Shared.Config.LobbyConfig)
local WorldConfig = E.require(E.Shared.Config.WorldConfig)
local Text = E.require(E.Shared.Localization)

-- ── 1. Config ───────────────────────────────────────────────────────────────
local stations = TrainingConfig.Stations
check(#stations == 4, "1. quatro alvos de treino")
local expected = {
	{ "Dummy", 0.35, 0 },
	{ "Scarecrow", 0.7, 1 },
	{ "Warrior", 1.2, 3 },
	{ "Guardian", 1.8, 6 },
}
local same = true
local kinds = {}
for index, station in stations do
	local e = expected[index]
	if not e or station.Id ~= e[1] or math.abs(station.Rate - e[2]) > 1e-9 or station.RequiredRebirths ~= e[3] or station.Order ~= index then
		same = false
		print(string.format("      %s rate %s req %s", tostring(station.Id), tostring(station.Rate), tostring(station.RequiredRebirths)))
	end
	kinds[station.Kind] = true
	if station.RequiredWins ~= nil then
		same = false
		print("      " .. station.Id .. " ainda tem RequiredWins")
	end
end
local kindCount = 0
for _ in kinds do
	kindCount += 1
end
check(same, "1. rates 0,35 / 0,70 / 1,20 / 1,80 (iguais à academia) e requisito 0 / 1 / 3 / 6 Renascimentos (sem vitórias)")
check(kindCount == 4, "1. quatro identidades distintas (Boneco, Espantalho, Guerreiro, Guardião)")
local increasing = stations[1].RequiredRebirths == 0
for index = 2, #stations do
	if stations[index].RequiredRebirths <= stations[index - 1].RequiredRebirths or stations[index].Rate <= stations[index - 1].Rate then
		increasing = false
	end
end
check(increasing, "1. o primeiro é livre e requisito e rate crescem a cada tier")
local apart = true
for i = 1, #stations do
	for j = i + 1, #stations do
		local a, b = stations[i], stations[j]
		local d = (V3.new(a.Local.X, 0, a.Local.Z) - V3.new(b.Local.X, 0, b.Local.Z)).Magnitude
		-- Pedestal quadrado de lado 2·Radius: a diagonal também não pode encostar.
		if math.abs(a.Local.X - b.Local.X) < a.Radius + b.Radius + 1.5 and math.abs(a.Local.Z - b.Local.Z) < a.Radius + b.Radius + 1.5 then
			apart = false
			print(string.format("      %s e %s a %.1f studs", a.Id, b.Id, d))
		end
	end
end
check(apart, "1. pedestais não se encostam (≥ 1,5 stud de vão): o serviço nunca confunde dois alvos")
local area = LobbyConfig.Areas[TrainingConfig.Area]
local halfX, halfZ = area.FloorSize.X / 2, area.FloorSize.Y / 2
local inside = true
for _, station in stations do
	if math.abs(station.Local.X) + station.Radius > halfX - 1 or math.abs(station.Local.Z) + station.Radius > halfZ - 1 then
		inside = false
	end
end
check(inside, "1. todos os pedestais dentro do piso da área de treino")

-- ── 2. Mundo ────────────────────────────────────────────────────────────────
local WorldBuilder = E.require(E.Server.World.WorldBuilder)
local world = WorldBuilder.Build(WorldConfig.Worlds[WorldConfig.DefaultWorld], V3.new(0, 0, 0), E.Instance.new("Folder"), E.Instance.new("Folder"), true)
local field = world:FindFirstChild("Station_Training_Machine", true)
check(field ~= nil, "2. Campo de Treinamento construído")
if not field then
	process.exit(1)
end
local models = {}
for _, d in field:GetChildren() do
	if d:IsA("Model") and d:HasTag("TrainingStation") then
		models[d:GetAttribute("Station")] = d
	end
end
local allModels = true
for _, station in stations do
	if not models[station.Id] then
		allModels = false
	end
end
check(allModels, "2. um Model por alvo, com a tag TrainingStation (o cliente acha por ela)")

-- Peças por alvo, prefixos do boneco e alturas.
local partsBy, heightBy, prefixes = {}, {}, {}
for index, station in stations do
	local model = models[station.Id]
	local n, top = 0, 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
			top = math.max(top, d.CFrame.Position.Y + d.Size.Y / 2)
		end
	end
	partsBy[index], heightBy[index] = n, top
	local dummy = model:FindFirstChild("Dummy")
	local names = {}
	for _, d in dummy:GetDescendants() do
		if d:IsA("BasePart") then
			local prefix = string.match(d.Name, "^%u%l+")
			names[prefix or d.Name] = true
		end
	end
	prefixes[index] = names
end
check(partsBy[1] < partsBy[2] and partsBy[2] < partsBy[3] and partsBy[3] < partsBy[4], string.format("2. progressão visível: peças por alvo I %d < II %d < III %d < IV %d", partsBy[1], partsBy[2], partsBy[3], partsBy[4]))
check(heightBy[1] < heightBy[4] and heightBy[4] >= 11, string.format("2. o Guardião é o mais alto (%.1f studs; o boneco I %.1f)", heightBy[4], heightBy[1]))
local wanted = { "Dummy", "Scarecrow", "Warrior", "Guardian" }
local distinct = true
for index, prefix in wanted do
	if not prefixes[index][prefix] then
		distinct = false
	end
	for other, otherPrefix in wanted do
		if other ~= index and prefixes[index][otherPrefix] then
			distinct = false
		end
	end
end
check(distinct, "2. cada boneco é feito das próprias peças (madeira/palha, espantalho, guerreiro, guardião)")
-- Material dá a identidade: I madeira/palha, II metal + madeira, III/IV energia.
local function materials(model)
	local set = {}
	for _, d in model:FindFirstChild("Dummy"):GetDescendants() do
		if d:IsA("BasePart") then
			set[d.Material.Name] = (set[d.Material.Name] or 0) + 1
		end
	end
	return set
end
local m1, m2, m3, m4 = materials(models.Dummy), materials(models.Scarecrow), materials(models.Warrior), materials(models.Guardian)
check(not m1.Neon and not m1.Metal and (m1.Fabric or 0) >= 2, "2. I Boneco: madeira e palha, sem energia")
check((m2.DiamondPlate or 0) >= 3 and (m2.Metal or 0) >= 4 and not m2.Neon, "2. II Espantalho: placas de metal e correntes, sem energia")
check((m3.Neon or 0) >= 3 and (m3.Glass or 0) >= 1 and (m3.Metal or 0) >= 6, "2. III Guerreiro: metal + filetes de energia + cristal no peito")
check((m4.Slate or 0) >= 4 and (m4.Neon or 0) >= 4 and models.Guardian:FindFirstChild("GuardianCore", true), "2. IV Guardião: pedra e metal, runas e núcleo")

-- Pedestal = área que conta, com piso diferente por tier.
local pedestalOk = true
local floorMaterial = {}
for index, station in stations do
	local pedestal = models[station.Id]:FindFirstChild("Pedestal")
	if not pedestal or math.abs(pedestal.Size.X - station.Radius * 2) > 0.01 then
		pedestalOk = false
	end
	floorMaterial[index] = pedestal and pedestal.Material.Name
	local centre = area.Offset + station.Local
	if pedestal and (V3.new(pedestal.CFrame.Position.X, 0, pedestal.CFrame.Position.Z) - V3.new(centre.X, 0, centre.Z)).Magnitude > 0.01 then
		pedestalOk = false
	end
end
check(pedestalOk and floorMaterial[1] == "WoodPlanks" and floorMaterial[2] == "Slate", "2. pedestal de cada alvo do tamanho do raio que conta, centrado na config; piso I madeira, II+ pedra")
local symbols = true
for _, station in stations do
	if not models[station.Id]:FindFirstChild("PedestalSymbol") then
		symbols = false
	end
end
check(symbols and models.Guardian:FindFirstChild("GuardianRunes") and #models.Guardian:FindFirstChild("GuardianRunes"):GetChildren() == 8, "2. símbolo no piso de cada alvo; o IV tem círculo de runas")

-- Placas e cadeados.
local roman = { "I", "II", "III", "IV" }
local plaquesOk = true
for index, station in stations do
	local board = models[station.Id]:FindFirstChild("TrainingPlaque_" .. station.Id)
	local gui = board and board:FindFirstChild("Text")
	local tier = gui and gui:FindFirstChild("Tier")
	local name = gui and gui:FindFirstChild("Name")
	local req = gui and gui:FindFirstChild("Requirement")
	local want = if station.RequiredRebirths == 0 then "LIVRE" elseif station.RequiredRebirths == 1 then "🔒 REQUER ♻ 1 RENASCIMENTO" else "🔒 REQUER ♻ " .. station.RequiredRebirths .. " RENASCIMENTOS"
	if not (tier and tier.Text == roman[index] and name and req and req.Text == want) then
		plaquesOk = false
		print("      placa " .. station.Id .. ": " .. tostring(req and req.Text))
	end
	-- De frente para a entrada (olha para -Z, um pouco de lado no arco).
	if board and board.CFrame.LookVector.Z > -0.6 then
		plaquesOk = false
		print("      placa " .. station.Id .. " virada para " .. tostring(board.CFrame.LookVector))
	end
	-- Baixa: não esconde o boneco.
	if board and board.CFrame.Position.Y + board.Size.Y / 2 > 3.0 then
		plaquesOk = false
	end
	local lock = models[station.Id]:FindFirstChild("Padlock")
	if (station.RequiredRebirths > 0) ~= (lock ~= nil) then
		plaquesOk = false
		print("      cadeado " .. station.Id .. ": " .. tostring(lock ~= nil))
	end
end
check(plaquesOk, "2. placa I–IV baixa com nome e \"🔒 REQUER ♻ X RENASCIMENTOS\" (I: LIVRE), cadeado só onde há requisito")
check(Text.GetFor(nil, "training.locked", { count = "3" }) == "Você precisa de 3 Renascimentos para treinar aqui." and Text.GetFor(nil, "training.lockedOne") == "Você precisa de 1 Renascimento para treinar aqui.", "2. mensagem curta em PT-BR (singular e plural)")
check(Text.GetFor(nil, "station.training.name") == "Treino" and Text.GetFor(nil, "station.training.subtitle") == "FIQUE MAIS FORTE" and field:FindFirstChild("FieldGateBeam"), "2. cabeçalho TREINO / FIQUE MAIS FORTE na entrada")

-- Nada de combate: sem Humanoid, HP, prompt, script, billboard ou luz.
local forbidden = {}
local emitters, rate = 0, 0
for _, d in field:GetDescendants() do
	if d:IsA("Humanoid") or d:IsA("ProximityPrompt") or d:IsA("BaseScript") or d:IsA("BillboardGui") or d:IsA("Light") or d:IsA("ClickDetector") then
		table.insert(forbidden, d.ClassName .. " " .. d.Name)
	end
	if d:GetAttribute("Health") ~= nil or d:GetAttribute("HP") ~= nil or d:GetAttribute("Loot") ~= nil then
		table.insert(forbidden, "atributo de combate em " .. d.Name)
	end
	if d:IsA("ParticleEmitter") then
		emitters += 1
		rate += d.Rate
	end
end
check(#forbidden == 0, "2. sem HP, loot, IA ou ataque: nenhum Humanoid/prompt/script/billboard/luz nos alvos " .. table.concat(forbidden, ", "))
check(emitters <= 2 and rate == 0, string.format("2. partículas só no golpe (%d emissor, Rate %d parado)", emitters, rate))
local fieldParts = field:GetAttribute("PartCount")
check(fieldParts <= 175, string.format("2. orçamento: %d peças (%d instâncias)", fieldParts, #field:GetDescendants()))

-- Academia antiga removida (na área de treino).
local old = {}
for _, d in world:GetDescendants() do
	if d:IsA("BasePart") and (math.abs(d.CFrame.Position.X - area.Offset.X) > halfX + 2 or math.abs(d.CFrame.Position.Z - area.Offset.Z) > halfZ + 2) then
		continue
	end
	local n = d.Name
	if n == "GymLandmark" or n == "GymPlate" or string.sub(n, 1, 12) == "TrainingPad_" or string.sub(n, 1, 13) == "TrainingSign_" or n == "Bag" or n == "Belt" or n == "Stack" or n == "GymGateBeam" then
		table.insert(old, n)
	end
end
check(#old == 0, "2. academia antiga (saco, halteres, esteira, máquina, pórtico de vigas, haltere gigante) removida " .. table.concat(old, ","))

-- Espaço para treinar e circulação (sólidos na altura do corpo).
local solids = {}
for _, d in world:GetDescendants() do
	if d:IsA("BasePart") and d.CanCollide then
		local p = d.CFrame.Position
		if math.abs(p.X - area.Offset.X) < halfX + 6 and math.abs(p.Z - area.Offset.Z) < halfZ + 6 then
			table.insert(solids, d)
		end
	end
end
local function blocked(p)
	for _, part in solids do
		local lp = part.CFrame:PointToObjectSpace(p)
		local h = part.Size / 2
		if math.abs(lp.X) <= h.X and math.abs(lp.Y) <= h.Y and math.abs(lp.Z) <= h.Z then
			return true
		end
	end
	return false
end
local roomOk = true
for _, station in stations do
	local centre = area.Offset + station.Local
	local pedestal = models[station.Id]:FindFirstChild("Pedestal")
	local stand = pedestal.CFrame.Position.Y + pedestal.Size.Y / 2 + 2.5
	local free, total = 0, 0
	for dx = -station.Radius + 0.5, station.Radius - 0.5, 1 do
		for dz = -station.Radius + 0.5, station.Radius - 0.5, 1 do
			if dx * dx + dz * dz <= (station.Radius - 0.5) ^ 2 then
				total += 1
				if not blocked(V3.new(centre.X + dx, stand + 2, centre.Z + dz)) then
					free += 1
				end
			end
		end
	end
	if free / total < 0.5 then
		roomOk = false
	end
	print(string.format("      %s: %.0f%% do raio livre na altura do corpo", station.Id, free / total * 100))
end
check(roomOk, "2. cada alvo deixa ≥ 50% do raio livre para o jogador ficar e treinar")
-- Da entrada até a frente de cada placa, sem bater em nada (na altura do corpo).
local gate = field:FindFirstChild("FieldGateBeam")
local start = V3.new(gate.CFrame.Position.X, 3.5, gate.CFrame.Position.Z + 1.5)
local pathOk = true
for _, station in stations do
	local board = models[station.Id]:FindFirstChild("TrainingPlaque_" .. station.Id)
	local goal = board.CFrame.Position + board.CFrame.LookVector * 2.5
	goal = V3.new(goal.X, 3.5, goal.Z)
	for step = 0, 40 do
		local p = start:Lerp(goal, step / 40)
		if blocked(p) then
			pathOk = false
			print("      caminho até " .. station.Id .. " bloqueado em " .. tostring(p))
			break
		end
	end
end
check(pathOk, "2. da entrada até a frente de cada placa, caminho livre")
-- Vão entre pedestais vizinhos (para passar entre eles): nenhum canto de
-- um pedestal chega a 1,5 stud do outro (pedestais girados no arco).
local worstGap = math.huge
for i = 1, #stations do
	for j = 1, #stations do
		if i ~= j then
			local a, b = models[stations[i].Id]:FindFirstChild("Pedestal"), models[stations[j].Id]:FindFirstChild("Pedestal")
			for _, sx in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local corner = (a.CFrame * CF.new(sx * a.Size.X / 2, 0, sz * a.Size.Z / 2)).Position
					local lp = b.CFrame:PointToObjectSpace(corner)
					local dx = math.max(math.abs(lp.X) - b.Size.X / 2, 0)
					local dz = math.max(math.abs(lp.Z) - b.Size.Z / 2, 0)
					worstGap = math.min(worstGap, math.sqrt(dx * dx + dz * dz))
				end
			end
		end
	end
end
check(worstGap >= 1.5, string.format("2. pedestais vizinhos com vão para passar (menor vão %.1f studs)", worstGap))
-- Nada do campo fora do piso da área nem na avenida.
local bounds = true
for _, d in field:GetDescendants() do
	if d:IsA("BasePart") then
		local p = d.CFrame.Position
		if math.abs(p.X - area.Offset.X) > halfX + 0.5 or math.abs(p.Z - area.Offset.Z) > halfZ + 0.5 then
			bounds = false
			print("      fora do piso: " .. d.Name .. " " .. tostring(p))
		end
	end
end
check(bounds, "2. todas as peças dentro do piso da área (não invadem calçada nem avenida)")

-- ── 3. Servidor ─────────────────────────────────────────────────────────────
local granted, notices = {}, {}
local perClick = 100
local Sig = { Connect = function()
	return { Disconnect = function() end }
end }
E.stubModules["ServerScriptService.Server.Services.DataService"] = { GetData = function(player)
	return player.Data
end }
E.stubModules["ServerScriptService.Server.Services.CurrencyService"] = { Add = function(player, currency, amount, reason)
	table.insert(granted, { Player = player, Currency = currency, Amount = amount, Reason = reason })
	return amount
end }
E.stubModules["ServerScriptService.Server.Services.PowerService"] = { GetInfo = function()
	return { PerClick = perClick }
end }
E.stubModules["ServerScriptService.Server.Services.WorldService"] = { OriginOf = function()
	return V3.new(0, 0, 0)
end }
E.stubModules["ServerScriptService.Server.Services.NetService"] = { FireClient = function(name, player, kind, payload)
	table.insert(notices, { Name = name, Player = player, Kind = kind, Payload = payload })
end }
local players = {}
E.stubs.Players = { GetPlayers = function()
	return players
end, PlayerAdded = Sig, PlayerRemoving = Sig }
E.patches["ServerScriptService.Server.Services.TrainingService"] = {
	{ "return root.Position, grounded", "return root.CFrame.Position, grounded" },
	{ "function TrainingService.Init()", "TrainingService._Tick = tick\nfunction TrainingService.Init()" },
}
local TrainingService = E.require(E.Server.Services.TrainingService)

local function fakePlayer(rebirths)
	local root = E.Instance.new("Part")
	root.Name = "HumanoidRootPart"
	local state = Enum.HumanoidStateType.Running
	local humanoid = { IsA = function(_, c)
		return c == "Humanoid"
	end, GetState = function()
		return state
	end }
	local attributes = {}
	local player = {
		Name = "Tester",
		UserId = 1,
		Data = { Stats = { Rebirths = rebirths }, Currencies = { Wins = 999999 } },
		GetAttribute = function(_, k)
			return attributes[k]
		end,
		SetAttribute = function(_, k, v)
			attributes[k] = v
		end,
	}
	player.Character = {
		FindFirstChild = function(_, n)
			return if n == "HumanoidRootPart" then root else nil
		end,
		FindFirstChildOfClass = function(_, c)
			return if c == "Humanoid" then humanoid else nil
		end,
	}
	player.MoveTo = function(id)
		local s
		for _, station in stations do
			if station.Id == id then
				s = station
			end
		end
		local p = if s then area.Offset + s.Local + V3.new(0.5, 3, -1) else area.Offset + V3.new(0, 3, -halfZ + 2)
		root.CFrame = CF.new(p)
	end
	player.Jump = function(on)
		state = if on then Enum.HumanoidStateType.Freefall else Enum.HumanoidStateType.Running
	end
	return player
end
local function tick(dt)
	table.clear(granted)
	TrainingService._Tick(dt or 0.5)
end
local function noticesFor(player)
	local n = 0
	for _, notice in notices do
		if notice.Player == player and notice.Name == "Notify" and notice.Kind == "TrainingLocked" then
			n += 1
		end
	end
	return n
end

local fresh = fakePlayer(0)
players = { fresh }
fresh.MoveTo("Dummy")
tick(0.5)
check(#granted == 1 and math.abs(granted[1].Amount - perClick * 0.35 * 0.5) < 1e-6 and granted[1].Reason == "Training:Dummy" and fresh:GetAttribute("Training") == "Dummy", "3. 0 Renascimento: treina no Boneco (poderPorClique × 0,35 × tempo)")
fresh.MoveTo("Scarecrow")
tick()
check(#granted == 0 and fresh:GetAttribute("Training") == nil and fresh:GetAttribute("TrainingRate") == nil, "3. 0 Renascimento no Espantalho: não ganha nada e o HUD apaga")
check(noticesFor(fresh) == 1 and notices[#notices].Payload.Rebirths == 1 and notices[#notices].Payload.Station == "Scarecrow", "3. aviso TrainingLocked (precisa de 1) uma vez")
tick()
tick()
fresh.Jump(true)
tick()
fresh.Jump(false)
tick()
check(noticesFor(fresh) == 1 and #granted == 0, "3. parado ou pulando no alvo bloqueado: sem repetir o aviso, sem pagar")
fresh.MoveTo(nil)
tick()
fresh.MoveTo("Scarecrow")
tick()
check(noticesFor(fresh) == 2, "3. saiu e voltou: avisa de novo")
fresh.MoveTo("Guardian")
tick()
check(noticesFor(fresh) == 3 and notices[#notices].Payload.Rebirths == 6, "3. trocou de alvo bloqueado: novo aviso com o requisito daquele alvo")

local exact = fakePlayer(3)
local below = fakePlayer(5)
local above = fakePlayer(20)
players = { exact, below, above }
exact.MoveTo("Warrior")
below.MoveTo("Guardian")
above.MoveTo("Guardian")
tick(1)
local byPlayer = {}
for _, g in granted do
	byPlayer[g.Player] = g
end
check(byPlayer[exact] and math.abs(byPlayer[exact].Amount - perClick * 1.2) < 1e-6, "3. exatamente 3 Renascimentos: treina no Guerreiro (1,20)")
check(byPlayer[below] == nil and below:GetAttribute("Training") == nil, "3. 5 Renascimentos no Guardião (precisa 6): bloqueado")
check(byPlayer[above] and math.abs(byPlayer[above].Amount - perClick * 1.8) < 1e-6 and above:GetAttribute("TrainingRate") == perClick * 1.8, "3. acima do requisito (20): Guardião paga 1,80")
players = { above }
above.MoveTo("Dummy")
tick(1)
check(#granted == 1 and math.abs(granted[1].Amount - perClick * 0.35) < 1e-6 and above:GetAttribute("Training") == "Dummy", "3. trocar de alvo troca o rendimento na hora")
above.Jump(true)
tick(1)
check(#granted == 0, "3. pulando não treina (RequireGrounded)")
above.Jump(false)
-- Renasceu no meio do treino: o próximo tick já libera (lê Stats.Rebirths).
below.Data.Stats.Rebirths = 6
players = { below }
tick(1)
check(#granted == 1 and math.abs(granted[1].Amount - perClick * 1.8) < 1e-6, "3. renasceu (5 → 6) parado no Guardião: libera no tick seguinte, sem relogar")
-- O cliente não tem como pedir treino nem mudar requisito.
local source = fs.readFile(E.Root .. "/src/server/Services/TrainingService.luau")
local listens = string.find(source, "OnServerEvent", 1, true) or string.find(source, "OnServerInvoke", 1, true) or string.find(source, "NetService.On", 1, true) or string.find(source, "NetService.Handle", 1, true)
check(not listens, "3. o serviço não ouve remote: posição (personagem) e Renascimentos (save) vêm do servidor")
check(string.find(source, "data.Stats.Rebirths", 1, true) and not string.find(source, "Wins", 1, true), "3. requisito lido de Stats.Rebirths (vitórias não contam mais)")
-- Save intacto.
local template = fs.readFile(E.Root .. "/src/server/Services/DataService/DataTemplate.luau")
local dataConfig = E.require(E.Server.ServerConfig.DataConfig)
-- DataVersion 9 veio do C2-E (Stats.RebirthAnchor), não do treino.
check(dataConfig.DataVersion == 9 and not string.find(template, "Training", 1, true), "3. save: DataVersion 9 (C2-E), nada de treino no DataTemplate (o requisito é só config)")

-- ── 4. Cliente ──────────────────────────────────────────────────────────────
local tagged = {}
for _, d in field:GetDescendants() do
	if d:HasTag("TrainingStation") then
		table.insert(tagged, d)
	end
end
E.stubs.CollectionService = {
	GetTagged = function(_, tag)
		return if tag == "TrainingStation" then tagged else {}
	end,
	GetInstanceAddedSignal = function()
		return Sig
	end,
	GetInstanceRemovedSignal = function()
		return Sig
	end,
}
local camera = { CFrame = CF.new(area.Offset + V3.new(0, 8, -halfZ)) }
E.stubs.Workspace = setmetatable({ CurrentCamera = camera }, { __index = E.Workspace })
local trainer = { Attrs = {} }
function trainer:GetAttribute(k)
	return self.Attrs[k]
end
E.stubs.Players = { GetPlayers = function()
	return { trainer }
end, LocalPlayer = trainer }
local settings = { ReducedEffects = false }
local stats = { Rebirths = 0 }
E.stubModules["StarterPlayer.Client.Controllers.DataController"] = {
	Get = function(key)
		return if key == "Settings" then settings elseif key == "Stats" then stats else nil
	end,
	Changed = Sig,
}
local emitted = 0
roblox.implementMethod("ParticleEmitter", "Emit", function(_, count)
	emitted += count or 1
end)
local Fx = E.require(E.Client.Controllers.TrainingFieldController)
Fx.Init()
check(Fx.Count() == 4, "4. cliente registra os 4 alvos pela tag")
local function lockState(id)
	local entry = Fx.Entry(id)
	local lock = entry.Lock[1]
	return entry.Unlocked, lock and lock.Part.Transparency, entry.Label and entry.Label.Text
end
local u1 = lockState("Dummy")
local u2, l2, t2 = lockState("Scarecrow")
local energyLocked = Fx.Entry("Warrior").Energy[1].Part.Transparency
check(u1 and not u2 and l2 < 1 and t2 == "🔒 REQUER ♻ 1 RENASCIMENTO" and energyLocked >= 0.85, "4. 0 Renascimento: I liberado; II–IV com cadeado, placa \"🔒 REQUER\" e energia apagada")
Fx.OnStats({ Rebirths = 3 })
local v2, k2, s2 = lockState("Scarecrow")
local v3 = lockState("Warrior")
local v4, k4 = lockState("Guardian")
local energyOpen = Fx.Entry("Warrior").Energy[1].Part.Transparency
check(v2 and v3 and k2 == 1 and s2 == "♻ 1 RENASCIMENTO" and energyOpen < 0.85 and not v4 and k4 < 1, "4. com 3 Renascimentos: II e III liberados (cadeado some, energia acende), IV continua bloqueado")
Fx.OnStats({ Rebirths = 10 })

local function snapshot(id)
	local list = {}
	for _, moving in Fx.Entry(id).Moving do
		table.insert(list, { moving.Part.CFrame, moving.Part.Size, moving.Part.Transparency })
	end
	return list
end
local function changed(id, before)
	local n = 0
	for index, moving in Fx.Entry(id).Moving do
		local b = before[index]
		if (moving.Part.CFrame.Position - b[1].Position).Magnitude > 1e-3 or (moving.Part.Size - b[2]).Magnitude > 1e-3 or math.abs(moving.Part.Transparency - b[3]) > 1e-3 or moving.Part.CFrame.LookVector:Dot(b[1].LookVector) < 0.9999 then
			n += 1
		end
	end
	return n
end
local base = {}
for _, id in wanted do
	base[id] = snapshot(id)
end
Fx.Step(100.1)
local idle = 0
for _, id in wanted do
	idle += changed(id, base[id])
end
check(idle == 0 and emitted == 0, "4. ninguém treinando: nada mexe")
for _, id in wanted do
	trainer.Attrs.Training = id
	emitted = 0
	-- Começo de um golpe (o ciclo é de 0,7 s): 200,305 s = fase 0,15.
	Fx.Step(200.05)
	Fx.Step(200.305)
	local moved = changed(id, base[id])
	if id == "Dummy" then
		local entry = Fx.Entry(id)
		check(moved >= #entry.Moving - 1, string.format("4. I Boneco balança enquanto alguém treina (%d peças)", moved))
	elseif id == "Scarecrow" then
		local plates = 0
		for index, moving in Fx.Entry(id).Moving do
			if moving.Plate and (moving.Part.CFrame.Position - base[id][index][1].Position).Magnitude > 1e-3 then
				plates += 1
			end
		end
		check(plates == 3 and emitted > 0, string.format("4. II Espantalho: as 3 placas vibram e solta faíscas (%d)", emitted))
	elseif id == "Warrior" then
		local brighter = 0
		for _, glow in Fx.Entry(id).Energy do
			if glow.InDummy and glow.Part.Transparency < glow.Base - 1e-3 then
				brighter += 1
			end
		end
		check(brighter >= 4, string.format("4. III Guerreiro: a energia responde ao golpe (%d peças acendem)", brighter))
	else
		local core = Fx.Entry(id).Core
		check(core and core.Part.Size.X > core.Size.X * 1.05, "4. IV Guardião: o núcleo pulsa")
	end
	trainer.Attrs.Training = nil
	Fx.Step(201)
	check(changed(id, base[id]) == 0, "4. " .. id .. ": parou o treino, volta exatamente ao lugar")
end
-- Longe: nada roda.
camera.CFrame = CF.new(area.Offset + V3.new(0, 8, -400))
trainer.Attrs.Training = "Dummy"
Fx.Step(300.1)
check(changed("Dummy", base.Dummy) == 0, "4. longe da câmera (> 140 studs): nada mexe")
camera.CFrame = CF.new(area.Offset + V3.new(0, 8, -halfZ))
-- Efeitos reduzidos: sem faíscas.
settings.ReducedEffects = true
trainer.Attrs.Training = "Scarecrow"
emitted = 0
Fx.Step(400.05)
Fx.Step(401.5)
check(emitted == 0, "4. \"Efeitos reduzidos\": sem faíscas (o movimento continua)")
local clientSource = fs.readFile(E.Root .. "/src/client/Controllers/TrainingFieldController.luau")
check(not string.find(clientSource, "FireServer", 1, true) and not string.find(clientSource, "InvokeServer", 1, true) and not string.find(clientSource, "Instance.new", 1, true), "4. o cliente não pede nada ao servidor e não cria instância")

if #problems > 0 then
	print(#problems .. " problema(s).")
	process.exit(1)
end
print("OK: Campo de Treinamento — 4 alvos, requisito em Renascimentos no servidor, reações só visuais, save intacto.")
print("REQUER VALIDAÇÃO NO ROBLOX STUDIO: leitura das placas, escala dos bonecos, ritmo das reações, aviso em jogo.")
process.exit(0)
