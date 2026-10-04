--[[
	check_corridor.luau — o CAMINHO DO PODER fora do Studio: o WallService REAL
	sobre o mapa gerado de verdade pelo WorldBuilder, com vários jogadores no
	mesmo servidor, e, para cada jogador, um CLIENTE separado (ambiente Lune
	próprio, com o próprio mapa e o WallController real) recebendo só o
	WallState daquele jogador.

		lune run tools/lune/check_corridor.luau [raiz]

	Barreiras são INDIVIDUAIS: HP, abertura, janela, prêmio e passagem são por
	jogador; as peças do Workspace ficam inteiras e sólidas no servidor.

	Loop (o que já valia):
	  1. ordem das 10 barreiras; 2. golpe de frente quebra, de trás não;
	  3. fileira quebrada some e não colide PARA QUEM QUEBROU (detalhes juntos);
	  4. 3 pads: normal, x2 = 2x o normal, Voltar sem prêmio; prêmio encerra a
	     corrida (volta à praça); um prêmio por abertura;
	  5. gemas da primeira vez uma vez só; 6. a barreira não se refaz em cima
	  do jogador; 7. respawn não perde progresso; 8. efeitos não mexem no HP;
	  9. não dá para contornar/pular; 10. distância/tempo de volta do spawn.
	Multiplayer: M1–M9 (os 9 testes pedidos), nos blocos marcados abaixo.

	Adaptações SÓ AQUI (o arquivo do jogo não muda): `.Position` vira
	`.CFrame.Position` (o Lune não expõe BasePart.Position), a janela aberta
	cai de 14 s para 0,5 s e o PivotTo do "levar de volta" move a peça raiz
	(o Lune não tem PivotTo de verdade).

	REQUER VALIDAÇÃO NO ROBLOX STUDIO (com 2 jogadores): a física de verdade
	(personagem atravessando a fileira local, o outro batendo nela), toque nos
	pads, câmera, efeitos, som e o streaming de peças.
]]
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")
local E = require("./env")(process.args[1])
local V3 = roblox.Vector3
local CFrame = roblox.CFrame

-- ── Eventos que o Lune não tem ──────────────────────────────────────────────
local Sig = {
	Connect = function()
		return { Disconnect = function() end }
	end,
	Once = function()
		return { Disconnect = function() end }
	end,
	Wait = function() end,
}
for _, pair in {
	{ "Instance", { "Changed", "ChildAdded", "ChildRemoved", "Destroying", "AncestryChanged", "AttributeChanged", "DescendantAdded" } },
	{ "GuiObject", { "InputBegan", "InputEnded", "InputChanged", "MouseEnter", "MouseLeave" } },
	{ "GuiButton", { "Activated", "MouseButton1Click" } },
} do
	for _, name in pair[2] do
		roblox.implementProperty(pair[1], name, function()
			return Sig
		end)
	end
end
roblox.implementMethod("Instance", "GetPropertyChangedSignal", function()
	return Sig
end)
roblox.implementMethod("Instance", "GetAttributeChangedSignal", function()
	return Sig
end)
-- Toque dos pads: guardamos o handler por nome do pad para simular o toque.
local touchHandlers = {}
roblox.implementProperty("BasePart", "Touched", function(self)
	local name = self.Name
	return {
		Connect = function(_, handler)
			touchHandlers[name] = handler
			return { Disconnect = function() end }
		end,
	}
end)

local Signal = E.require(E.Shared.Utils.Signal)
local WallConfig = E.require(E.Shared.Config.WallConfig)
local LobbyConfig = E.require(E.Shared.Config.LobbyConfig)

local function buildMap(env)
	local map = roblox.Instance.new("Folder")
	map.Name = "Map"
	local worldsFolder = roblox.Instance.new("Folder")
	worldsFolder.Name = "Worlds"
	worldsFolder.Parent = map
	local spawns = roblox.Instance.new("Folder")
	spawns.Name = "Spawns"
	spawns.Parent = map
	map.Parent = env.Workspace
	local builder = env.require(env.Server.World.WorldBuilder)
	local worldConfig = env.require(env.Shared.Config.WorldConfig)
	builder.Build(worldConfig.Worlds[WallConfig.WorldId], V3.new(0, 0, 0), worldsFolder, spawns, true)
	return worldsFolder
end

-- ── Servidor ────────────────────────────────────────────────────────────────
local worlds = buildMap(E)

local datas = {}
local currency = {} -- [player][currency] = total
local notices = {} -- { {target, kind, payload} }
local wallStates = {} -- [userId] = { payload, ... } ainda não entregues ao cliente
local wallStateCount = {} -- [userId] = quantos WallState o servidor mandou
local sentBy = {} -- [player] = vezes que voltou para a praça
local players = {}
local spawnPosition = LobbyConfig.SpawnPoint + V3.new(0, 3, 0)
local playerReady = Signal.new()
local playerRemoving = Signal.new()

E.stubs.Players = {
	GetPlayers = function()
		return players
	end,
	PlayerRemoving = playerRemoving,
	PlayerAdded = Signal.new(),
	GetPlayerFromCharacter = function(_, character)
		for _, player in players do
			if player.Character == character then
				return player
			end
		end
		return nil
	end,
}
E.stubModules["ServerScriptService.Server.Services.DataService"] = {
	GetData = function(player)
		return datas[player]
	end,
	MarkChanged = function() end,
	PlayerReady = playerReady,
}
E.stubModules["ServerScriptService.Server.Services.NetService"] = {
	FireClient = function(name, player, kind, payload)
		if name == "WallState" then
			wallStates[player.UserId] = wallStates[player.UserId] or {}
			table.insert(wallStates[player.UserId], kind)
			wallStateCount[player.UserId] = (wallStateCount[player.UserId] or 0) + 1
			return
		end
		table.insert(notices, { player, kind, payload })
	end,
	FireAllClients = function(_, kind, payload)
		table.insert(notices, { "all", kind, payload })
	end,
}
E.stubModules["ServerScriptService.Server.Services.CurrencyService"] = {
	Add = function(player, id, amount)
		currency[player] = currency[player] or {}
		currency[player][id] = (currency[player][id] or 0) + amount
		return amount
	end,
}
E.stubModules["ServerScriptService.Server.Services.WorldService"] = {
	-- Como o real: leva o personagem para o spawn (aqui, só a posição).
	SendToSpawn = function(player)
		sentBy[player] = (sentBy[player] or 0) + 1
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			root.CFrame = CFrame.new(spawnPosition)
		end
	end,
}
E.patches["ServerScriptService.Server.Services.WallService"] = {
	{ ".Position", ".CFrame.Position", "all" },
	{ "WallConfig.OpenSeconds", "0.5", "all" },
	{ "character:PivotTo(CFrame.lookAt(target, target + Vector3.new(1, 0, 0)))", "root.CFrame = CFrame.new(target)" },
}
local WallService = E.require(E.Server.Services.WallService)
WallService.Init()
WallService.Start()

local function newPlayer(id: number, data: any?)
	local player = { UserId = id, DisplayName = "P" .. id, Name = "P" .. id, Character = nil }
	table.insert(players, player)
	datas[player] = data or { Worlds = { Current = WallConfig.WorldId }, Tower = { Cleared = {}, Highest = 0 } }
	playerReady:Fire(player, datas[player])
	return player
end
local function removePlayer(player)
	for index, other in players do
		if other == player then
			table.remove(players, index)
			break
		end
	end
	playerRemoving:Fire(player)
end
local function respawn(player, position: Vector3)
	if player.Character then
		player.Character:Destroy()
	end
	local character = roblox.Instance.new("Model")
	character.Name = player.Name
	local root = roblox.Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.CFrame = CFrame.new(position)
	root.Parent = character
	character.Parent = E.Workspace
	player.Character = character
	return character
end
local function moveTo(player, position: Vector3)
	player.Character.HumanoidRootPart.CFrame = CFrame.new(position)
end
local function positionOf(player): Vector3
	return player.Character.HumanoidRootPart.CFrame.Position
end

-- Fileiras e detalhes, por estágio (as peças do SERVIDOR).
local rows = {}
for _, d in worlds:GetDescendants() do
	if d:IsA("BasePart") and d:GetAttribute("Wall") == true then
		local id = d:GetAttribute("StageId")
		rows[id] = rows[id] or {}
		table.insert(rows[id], d)
	end
end
for _, list in rows do
	table.sort(list, function(a, b)
		return a:GetAttribute("Row") < b:GetAttribute("Row")
	end)
end

-- ── Clientes (um ambiente por jogador) ──────────────────────────────────────
local function makeClient(userId: number)
	local C = require("./env")(process.args[1])
	local playerGui = roblox.Instance.new("Folder")
	playerGui.Name = "PlayerGui"
	local localPlayer = {
		Name = "P" .. userId,
		UserId = userId,
		LocaleId = "pt-br",
		Character = nil,
		WaitForChild = function(_, n)
			return if n == "PlayerGui" then playerGui else nil
		end,
		FindFirstChild = function(_, n)
			return if n == "PlayerGui" then playerGui else nil
		end,
		GetAttribute = function()
			return nil
		end,
		GetAttributeChangedSignal = function()
			return Sig
		end,
	}
	C.stubs.Players = { LocalPlayer = localPlayer, GetPlayers = function()
		return { localPlayer }
	end, PlayerAdded = Sig, PlayerRemoving = Sig }
	C.stubs.TweenService = { Create = function()
		return { Play = function() end, Cancel = function() end, Completed = Sig }
	end }
	local heartbeat = function() end
	C.stubs.RunService.Heartbeat = { Connect = function(_, fn)
		heartbeat = fn
		return { Disconnect = function() end }
	end }
	C.extraGlobals.TweenInfo = { new = function(...)
		return { ... }
	end }
	local handlers = {}
	local client = "StarterPlayer.Client."
	C.stubModules[client .. "Net.ClientNet"] = { On = function(name, fn)
		handlers[name] = fn
		return { Disconnect = function() end }
	end, Fire = function() end, Invoke = function()
		return { Ok = false }
	end }
	C.stubModules[client .. "Controllers.SoundController"] = { Play = function() end }
	C.stubModules[client .. "Controllers.NotificationController"] = { Show = function() end }
	C.stubModules[client .. "Controllers.HudController"] = { GetTopStack = function()
		return roblox.Instance.new("Frame")
	end }
	C.stubModules[client .. "Controllers.DataController"] = { Get = function()
		return nil
	end, IsLoaded = function()
		return false
	end }
	C.patches[client .. "Controllers.WallController"] = {
		{ "row.Position", "row.CFrame.Position", "all" },
		{ "root.Position", "root.CFrame.Position", "all" },
	}
	local clientWorlds = buildMap(C)
	local controller = C.require(C.Client.Controllers.WallController)
	controller.Init()
	controller.Start()
	local clientRows = {}
	for _, d in clientWorlds:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("Wall") == true then
			local id = d:GetAttribute("StageId")
			clientRows[id] = clientRows[id] or {}
			clientRows[id][d:GetAttribute("Row")] = d
		end
	end
	return {
		Controller = controller,
		Heartbeat = function()
			heartbeat()
		end,
		Handlers = handlers,
		Rows = clientRows,
		UserId = userId,
	}
end
-- Entrega ao cliente o que o servidor mandou para ESTE jogador e roda um quadro.
local function sync(client)
	for _, payload in wallStates[client.UserId] or {} do
		client.Handlers.WallState(payload)
	end
	wallStates[client.UserId] = {}
	client.Heartbeat()
end

local problems = {}
local function check(condition: any, message: string)
	if condition then
		print("OK   " .. message)
	else
		table.insert(problems, message)
		print("FALHA " .. message)
	end
end
local function frontOf(part, back: number?): Vector3
	return V3.new(part.CFrame.Position.X - part.Size.X / 2 - (back or 6), 3, 0)
end
local function behind(list): Vector3
	local last = list[#list]
	return V3.new(last.CFrame.Position.X + last.Size.X / 2 + 30, 3, 0)
end
local function detailsVisible(row, visible: boolean): boolean
	for _, child in row:GetChildren() do
		if child:GetAttribute("WallDetail") == true then
			if (child.Transparency < 0.5) ~= visible or child.CanCollide then
				return false
			end
		end
	end
	return true
end
-- Fileira como o CLIENTE a mostra: (some e não colide) ou (inteira e sólida).
local function clientRowOpen(client, stageId: string, index: number): boolean
	local row = client.Rows[stageId][index]
	return row.Transparency == 1 and not row.CanCollide and detailsVisible(row, false)
end
local function clientRowWhole(client, stageId: string, index: number): boolean
	local row = client.Rows[stageId][index]
	return row.Transparency == 0 and row.CanCollide and detailsVisible(row, true)
end
local function clientStageWhole(client, stageId: string): boolean
	for index in client.Rows[stageId] do
		if not clientRowWhole(client, stageId, index) then
			return false
		end
	end
	return true
end
local function clientStageOpen(client, stageId: string): boolean
	for index in client.Rows[stageId] do
		if not clientRowOpen(client, stageId, index) then
			return false
		end
	end
	return true
end
local function serverPartsUntouched(): boolean
	for _, list in rows do
		for _, row in list do
			if not row.CanCollide or row.Transparency ~= 0 or not detailsVisible(row, true) then
				return false
			end
		end
	end
	return true
end
local function noticesOf(kind: string, target: any?)
	local list = {}
	for _, n in notices do
		if n[2] == kind and (target == nil or n[1] == target) then
			table.insert(list, n)
		end
	end
	return list
end
local function wins(player)
	return (currency[player] or {}).Wins or 0
end
local function gems(player)
	return (currency[player] or {}).Gems or 0
end
local function touch(padName, player)
	touchHandlers[padName](player.Character.HumanoidRootPart)
end
local function breakStage(player, list, hp)
	for _, row in list do
		moveTo(player, frontOf(row, 2))
		WallService.OnClick(player, hp)
	end
end

local first, second = WallConfig.Stages[1], WallConfig.Stages[2]
local b1, b2 = rows[first.Id], rows[second.Id]
local padNormal, padDouble, padBack = "WinPad_" .. first.Id .. "_1", "WinPad_" .. first.Id .. "_2", "ReturnPad_" .. first.Id

-- 1. Ordem
local orderOk = true
local lastX = -math.huge
for _, stage in WallConfig.Stages do
	local list = rows[stage.Id]
	if not list or #list ~= stage.Rows then
		orderOk = false
	else
		local x = list[1].CFrame.Position.X
		orderOk = orderOk and x > lastX and math.abs(list[1].CFrame.Position.Z) < 1e-6
		lastX = x
	end
end
check(orderOk, "1. 10 barreiras em ordem (1 -> 10), na mesma linha, com todas as fileiras")

-- ── Dois jogadores no mesmo servidor ────────────────────────────────────────
local A = newPlayer(1)
local B = newPlayer(2)
local clientA, clientB = makeClient(1), makeClient(2)
sync(clientA)
sync(clientB)
check((wallStateCount[1] or 0) >= 1 and (wallStateCount[2] or 0) >= 1, "M6. cada jogador recebe o próprio estado ao entrar (WallState)")
check(clientStageWhole(clientA, first.Id) and clientStageWhole(clientB, first.Id), "M6. ao entrar, os dois veem a Barreira 1 inteira")
respawn(A, frontOf(b1[1]))
respawn(B, frontOf(b1[1]))

-- M1/M8. Golpe de A não muda o HP de B (mesma fileira, ao mesmo tempo).
local damage = 7
WallService.OnClick(A, damage)
check(WallService.RowHp(A, first.Id, 1) == first.Hp - damage, "8. um golpe tira exatamente o dano (efeitos não mexem no HP)")
check(WallService.RowHp(B, first.Id, 1) == first.Hp, "M1. A bate na Barreira 1: o HP de B continua 100%")
for _ = 1, 3 do
	WallService.OnClick(A, damage)
	WallService.OnClick(B, 2)
end
check(WallService.RowHp(A, first.Id, 1) == first.Hp - damage * 4 and WallService.RowHp(B, first.Id, 1) == first.Hp - 6,
	string.format("M8. A e B batem na mesma fileira ao mesmo tempo: cada um só tira HP da PRÓPRIA (A %d, B %d)", WallService.RowHp(A, first.Id, 1), WallService.RowHp(B, first.Id, 1)))
sync(clientA)
sync(clientB)
check(clientA.Controller.RowState(clientA.Rows[first.Id][1]) == first.Hp - damage * 4 and clientB.Controller.RowState(clientB.Rows[first.Id][1]) == first.Hp - 6,
	"M8. a barra de cada cliente mostra o próprio HP")

-- 2. Golpe por trás não faz nada.
moveTo(A, V3.new(b1[1].CFrame.Position.X + 3, 3, 0))
local before = WallService.RowHp(A, first.Id, 1)
WallService.OnClick(A, damage)
check(WallService.RowHp(A, first.Id, 1) == before, "2. golpe por TRÁS da fileira não faz nada")

-- 3. A quebra a fileira 1: some e não colide SÓ para A.
moveTo(A, frontOf(b1[1]))
WallService.OnClick(A, first.Hp)
sync(clientA)
sync(clientB)
check(WallService.RowHp(A, first.Id, 1) == 0 and clientRowOpen(clientA, first.Id, 1), "3. fileira quebrada some e não colide para quem quebrou (detalhes juntos)")
check(clientRowWhole(clientA, first.Id, 2), "3. fileira seguinte continua de pé, sólida e com detalhes")
check(clientRowWhole(clientB, first.Id, 1), "M2. B continua vendo a fileira 1 inteira e sólida")
check(#noticesOf("WallRow", A) >= 1 and #noticesOf("WallRow", B) == 0, "3. aviso de fileiras restantes só para quem quebrou")

-- M2. A destrói a Barreira 1: só A vê a passagem.
breakStage(A, b1, first.Hp)
sync(clientA)
sync(clientB)
check(WallService.IsOpen(A, first.Id) and not WallService.IsOpen(B, first.Id), "M2. A destruiu a Barreira 1: aberta para A, fechada para B")
check(clientStageOpen(clientA, first.Id), "M2. A vê a passagem aberta (fileiras somem e não colidem no cliente de A)")
check(clientStageWhole(clientB, first.Id), "M2. B continua vendo a Barreira 1 inteira (e ela colide para B)")
check(WallService.RowHp(B, first.Id, 1) == first.Hp - 6, "M2. o HP de B não mudou com a quebra de A")
check(serverPartsUntouched(), "M2. o servidor não mexe nas peças compartilhadas (inteiras e sólidas no Workspace)")
local broken = noticesOf("WallBroken")
check(#broken >= 1 and broken[#broken][1] == A and broken[#broken][3].ById == A.UserId and broken[#broken][3].FirstClear == true and #noticesOf("WallBroken", "all") == 0,
	"4. quebra anunciada só para quem quebrou (estágio e primeira conquista)")

-- M3. A atravessa; B tenta atravessar sem quebrar.
moveTo(A, behind(b1))
check(WallService.Validate(A), "M3. A atravessa a própria barreira aberta (posição válida)")
moveTo(B, behind(b1))
local okB = WallService.Validate(B)
check(not okB and positionOf(B).X < b1[1].CFrame.Position.X - b1[1].Size.X / 2, "M3. B além da barreira sem quebrar: o servidor o leva de volta para a frente dela")
check(clientRowWhole(clientB, first.Id, 1), "M3. no cliente de B a fileira continua sólida (B fica bloqueado pela física local)")

-- M5. A pega o prêmio: só A recebe e volta à praça.
local a0, b0 = wins(A), wins(B)
moveTo(A, behind(b1))
touch(padDouble, A)
check(wins(A) - a0 == first.Pads[2] and first.Pads[2] == first.Pads[1] * 2, "B. pad x2 paga exatamente 2x o normal (+" .. first.Pads[2] .. ")")
check(wins(B) == b0 and (sentBy[B] or 0) == 0 and sentBy[A] == 1, "M5. só A recebe as vitórias e só A volta para a praça")
moveTo(A, behind(b1))
touch(padNormal, A)
touch(padDouble, A)
check(wins(A) - a0 == first.Pads[2], "A. não recebe de novo na mesma abertura (nem no outro pad)")
check(datas[A].Tower.Cleared[first.Id] == true and datas[A].Tower.Highest == first.Order and datas[B].Tower.Cleared[first.Id] == nil, "E. Barreira 1 registrada como conquistada só para A")

-- M9. B sem ter quebrado: atravessar/remover localmente não dá nada.
clientB.Rows[first.Id][1].CanCollide = false -- "exploit": apaga a fileira no próprio cliente
clientB.Rows[first.Id][1].Transparency = 1
moveTo(B, behind(b1))
touch(padNormal, B)
touch(padDouble, B)
check(wins(B) == b0, "M9. B tira a fileira no próprio cliente e pisa nos pads: nenhuma vitória")
moveTo(B, frontOf(b2[1]))
local b2Before = WallService.RowHp(B, second.Id, 1)
WallService.OnClick(B, 1e6)
check(WallService.RowHp(B, second.Id, 1) == b2Before and not WallService.IsOpen(B, second.Id), "M9. B não consegue bater na Barreira 2 pulando a 1")
check(positionOf(B).X < b1[1].CFrame.Position.X, "M9. B é levado de volta para a frente da própria Barreira 1")
check(datas[B].Tower.Cleared[first.Id] == nil and datas[B].Tower.Highest == 0 and gems(B) == 0, "M9. nenhum progresso salvo nem gema para B")
clientB.Heartbeat()
check(clientRowWhole(clientB, first.Id, 1), "M9. o cliente de B reaplica o estado verdadeiro (a fileira volta sólida)")

-- C) Voltar.
local r = newPlayer(3)
respawn(r, frontOf(b1[1]))
breakStage(r, b1, first.Hp)
moveTo(r, behind(b1))
touch(padBack, r)
check(wins(r) == 0 and sentBy[r] == 1, "C. Voltar leva para a praça sem dar vitória")
removePlayer(r)

-- 6. Não refaz em cima de quem está dentro (só o dono conta).
respawn(A, frontOf(b1[1]))
task.wait(1.2) -- a janela antiga de A acaba
breakStage(A, b1, first.Hp)
moveTo(A, V3.new(b1[2].CFrame.Position.X, 3, 0)) -- no meio do bloco
moveTo(B, frontOf(b1[1]))
task.wait(1.2)
check(WallService.IsOpen(A, first.Id), "6. barreira de A não se refaz com A dentro dela")
moveTo(A, behind(b1))
task.wait(1.6)
sync(clientA)
check(not WallService.IsOpen(A, first.Id) and clientStageWhole(clientA, first.Id), "6. com A fora, a barreira de A volta inteira (com detalhes)")
check(WallService.Validate(A), "6. A atravessou com a passagem aberta: continua válido do outro lado depois de ela se refazer")

-- M4. A na Barreira 2, B na Barreira 1, ao mesmo tempo.
moveTo(A, frontOf(b2[1]))
local bHp = WallService.RowHp(B, first.Id, 1)
WallService.OnClick(A, damage)
WallService.OnClick(B, damage)
check(WallService.RowHp(A, second.Id, 1) == second.Hp - damage and WallService.RowHp(B, first.Id, 1) == bHp - damage and WallService.RowHp(B, second.Id, 1) == second.Hp,
	"M4. A ataca a Barreira 2 e B a Barreira 1: nenhum estado interfere no outro")
local gemsA = gems(A)
breakStage(A, b2, second.Hp)
check(gems(A) - gemsA == second.FirstClearGems and gems(B) == 0, "5. gemas da primeira vez do estágio 2 pagas só para A")
moveTo(A, behind(b2))
task.wait(1.6)
breakStage(A, b2, second.Hp)
check(gems(A) - gemsA == second.FirstClearGems, "5. quebrar de novo NÃO paga as gemas outra vez")
sync(clientA)
sync(clientB)
check(clientStageWhole(clientB, second.Id), "M4. B continua vendo a Barreira 2 inteira")

-- B) Repetindo: x2 continua valendo o dobro do normal.
local function openAgain(player, list, hp)
	moveTo(player, spawnPosition)
	WallService.Validate(player) -- na praça: nova tentativa
	task.wait(1.6)
	breakStage(player, list, hp)
	moveTo(player, behind(list))
end
openAgain(A, b1, first.Hp)
local before1 = wins(A)
touch(padNormal, A)
local normalRepeat = wins(A) - before1
openAgain(A, b1, first.Hp)
local before2 = wins(A)
touch(padDouble, A)
local doubleRepeat = wins(A) - before2
check(normalRepeat >= 1 and doubleRepeat == normalRepeat * 2, string.format("B. repetindo, x2 paga o dobro do normal (+%d e +%d)", normalRepeat, doubleRepeat))

-- 7. Respawn: progresso salvo fica, golpe volta a funcionar.
respawn(A, spawnPosition)
check(datas[A].Tower.Cleared[first.Id] and datas[A].Tower.Cleared[second.Id] and datas[A].Tower.Highest == second.Order, "7. respawn não perde o progresso do Caminho")
task.wait(1.6)
moveTo(A, frontOf(b1[1]))
local hpBefore = WallService.RowHp(A, first.Id, 1)
WallService.OnClick(A, damage)
check(WallService.RowHp(A, first.Id, 1) == hpBefore - damage, "7. depois do respawn o golpe volta a funcionar")

-- M6. D entra depois: recebe o PRÓPRIO estado, não o de A.
breakStage(A, b1, first.Hp)
local D = newPlayer(4)
local clientD = makeClient(4)
sync(clientA)
sync(clientD)
check(clientStageOpen(clientA, first.Id) and clientStageWhole(clientD, first.Id) and WallService.RowHp(D, first.Id, 1) == first.Hp,
	"M6. quem entra depois de A quebrar a Barreira 1 a vê inteira (estado dele, não o de A)")

-- M7. A sai e entra de novo: progresso salvo restaurado.
local savedA = datas[A]
local gemsBefore = gems(A)
removePlayer(A)
check(WallService.RowHp(A, first.Id, 1) == first.Hp and not WallService.IsOpen(A, first.Id), "M7. ao sair, o estado em memória do jogador é descartado")
local A2 = newPlayer(1, savedA) -- mesmo UserId, mesmos dados salvos
currency[A2] = currency[A]
respawn(A2, frontOf(b1[1]))
check(datas[A2].Tower.Cleared[first.Id] and datas[A2].Tower.Cleared[second.Id] and datas[A2].Tower.Highest == second.Order, "M7. ao voltar, o progresso salvo (Tower) está lá")
breakStage(A2, b1, first.Hp)
moveTo(A2, behind(b1))
local w2 = wins(A2)
touch(padNormal, A2)
check(gems(A2) == gemsBefore and wins(A2) - w2 == normalRepeat, "M7. de volta: a Barreira 1 conta como repetição (sem gemas de novo, prêmio de repetição)")

check(serverPartsUntouched(), "M2. no fim de tudo, as peças do servidor continuam inteiras e sólidas")

-- 9. Contornar / pular: a fileira cobre a largura do corredor inteira e
-- fileira e paredes laterais ficam muito acima de um pulo.
local jump = 7.2
local bypassProblems = {}
for _, stage in WallConfig.Stages do
	local row = rows[stage.Id][1]
	local size = row.Size
	local x = row.CFrame.Position.X
	local corridorHalf = WallConfig.Layout.Width * (if stage.Order == #WallConfig.Stages then WallConfig.Layout.FinalScale else 1) / 2
	if size.Y < jump * 4 then
		table.insert(bypassProblems, stage.Id .. ": barreira baixa")
	end
	if size.Z < corridorHalf * 2 - 0.01 then
		table.insert(bypassProblems, stage.Id .. ": vão entre a barreira e a parede lateral")
	end
	for _, side in { -1, 1 } do
		local found = false
		for _, d in worlds:GetDescendants() do
			if d:IsA("BasePart") and d.CanCollide and d:GetAttribute("Wall") ~= true then
				local p = d.CFrame.Position
				local half = d.Size / 2
				if math.abs(p.X - x) <= half.X + 0.5 and side * (p.Z - side * half.Z) <= corridorHalf + 0.6 and side * p.Z > corridorHalf and p.Y + half.Y >= jump * 4 then
					found = true
					break
				end
			end
		end
		if not found then
			table.insert(bypassProblems, stage.Id .. ": sem parede lateral alta colada no corredor (lado " .. side .. ")")
		end
	end
end
for _, message in bypassProblems do
	print("      " .. message)
end
check(#bypassProblems == 0, "9. não dá para contornar nem pular as barreiras (largura toda, paredes laterais coladas e altas)")

-- 10. Distância do spawn até cada barreira
print("")
print("Retorno depois de morrer (do spawn até a frente de cada barreira, andando a 16 studs/s):")
local accumulatedHp = 0
for _, stage in WallConfig.Stages do
	local front = rows[stage.Id][1]
	local distance = (front.CFrame.Position.X - front.Size.X / 2) - LobbyConfig.SpawnPoint.X
	print(string.format("  Barreira %2d  %-20s %5.0f studs  %4.0f s andando  (antes dela: %s de HP em barreiras para quebrar de novo)", stage.Order, stage.DisplayName, distance, distance / 16, if accumulatedHp > 0 then string.format("%.3g", accumulatedHp) else "0"))
	accumulatedHp += stage.Hp * stage.Rows
end

print("")
print("REQUER VALIDAÇÃO NO ROBLOX STUDIO (2 jogadores): física real da passagem local, toque nos pads, câmera, efeitos, som e streaming.")
if #problems > 0 then
	print(#problems .. " problema(s).")
	process.exit(1)
end
print("OK: Caminho do Poder individual por jogador (quebrar, abrir, prêmio, avançar, respawn, multiplayer) sem regressão.")
process.exit(0)
