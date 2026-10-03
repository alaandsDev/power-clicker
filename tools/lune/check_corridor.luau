--[[
	check_corridor.luau — o loop do CAMINHO DO PODER fora do Studio: roda o
	WallService REAL sobre o mapa gerado de verdade pelo WorldBuilder, com
	dados, rede, moedas e jogadores simulados.

		lune run tools/lune/check_corridor.luau [raiz]

	Verifica:
	  1. ordem: Barreira 1 antes da 2 (e assim por diante), na mesma linha;
	  2. golpe de FRENTE quebra fileira por fileira; de TRÁS não faz nada;
	  3. detalhes visuais acompanham a fileira (somem e voltam com ela) e
	     nunca colidem; fileira quebrada não colide, as de pé colidem;
	  4. a última fileira abre a passagem; pads pagam UMA vez por abertura e
	     por jogador; pegar o pad NÃO teleporta (o pad de voltar teleporta);
	  5. gemas da primeira vez saem UMA vez, mesmo quebrando de novo;
	  6. a barreira não se refaz em cima de um personagem que está dentro dela;
	     refaz quando ele sai;
	  7. respawn (personagem novo) não perde o progresso e continua batendo;
	  8. efeitos não mexem no HP: cada golpe tira exatamente o dano;
	  9. não dá para contornar nem pular: a seção da barreira é sólida em
	     toda a largura e muito mais alta que um pulo;
	 10. relatório de distância/tempo de caminhada do spawn até cada barreira
	     (o retorno depois de morrer).

	O WallService é carregado com duas adaptações SÓ AQUI (o arquivo do jogo
	não muda): `.Position` vira `.CFrame.Position` (o Lune não expõe
	BasePart.Position) e a janela aberta cai de 14 s para 0,5 s.

	REQUER VALIDAÇÃO NO ROBLOX STUDIO: toque real nos pads (física), colisão do
	personagem nas fileiras, sensação do golpe, partículas, som e câmera.
]]
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")
local E = require("./env")(process.args[1])
local V3 = roblox.Vector3
local CFrame = roblox.CFrame

local Signal = E.require(E.Shared.Utils.Signal)
local WallConfig = E.require(E.Shared.Config.WallConfig)
local WorldConfig = E.require(E.Shared.Config.WorldConfig)
local LobbyConfig = E.require(E.Shared.Config.LobbyConfig)
local WorldBuilder = E.require(E.Server.World.WorldBuilder)

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

-- ── Mapa real ───────────────────────────────────────────────────────────────
local map = roblox.Instance.new("Folder")
map.Name = "Map"
local worlds = roblox.Instance.new("Folder")
worlds.Name = "Worlds"
worlds.Parent = map
local spawns = roblox.Instance.new("Folder")
spawns.Name = "Spawns"
spawns.Parent = map
map.Parent = E.Workspace
WorldBuilder.Build(WorldConfig.Worlds[WallConfig.WorldId], V3.new(0, 0, 0), worlds, spawns, true)

-- ── Stubs ───────────────────────────────────────────────────────────────────
local datas = {}
local currency = {} -- [player][currency] = total
local notices = {} -- { {target, kind, payload} }
local sentToSpawn = 0
local players = {}

E.stubs.Players = {
	GetPlayers = function()
		return players
	end,
	PlayerRemoving = Signal.new(),
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
}
E.stubModules["ServerScriptService.Server.Services.NetService"] = {
	FireClient = function(kind, player, name, payload)
		table.insert(notices, { player, name == nil and kind or name, payload })
	end,
	FireAllClients = function(kind, name, payload)
		table.insert(notices, { "all", name, payload })
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
	SendToSpawn = function()
		sentToSpawn += 1
	end,
}
E.patches["ServerScriptService.Server.Services.WallService"] = {
	{ ".Position", ".CFrame.Position", "all" },
	{ "WallConfig.OpenSeconds", "0.5", "all" },
}
local WallService = E.require(E.Server.Services.WallService)
WallService.Init()
WallService.Start()

local function newPlayer(id: number)
	local player = { UserId = id, DisplayName = "P" .. id, Name = "P" .. id, Character = nil }
	table.insert(players, player)
	datas[player] = { Worlds = { Current = WallConfig.WorldId }, Tower = { Cleared = {}, Highest = 0 } }
	return player
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

-- Fileiras e detalhes, por estágio.
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

local problems = {}
local function check(condition: boolean, message: string)
	if condition then
		print("OK   " .. message)
	else
		table.insert(problems, message)
		print("FALHA " .. message)
	end
end
local function frontOf(part: BasePart, back: number?): Vector3
	return V3.new(part.CFrame.Position.X - part.Size.X / 2 - (back or 6), 3, 0)
end
local function detailsVisible(row: BasePart, visible: boolean): boolean
	for _, child in row:GetChildren() do
		if child:GetAttribute("WallDetail") == true then
			if (child.Transparency < 0.5) ~= visible or child.CanCollide then
				return false
			end
		end
	end
	return true
end
local function noticesOf(kind: string)
	local list = {}
	for _, n in notices do
		if n[2] == kind then
			table.insert(list, n)
		end
	end
	return list
end

local first, second = WallConfig.Stages[1], WallConfig.Stages[2]
local b1, b2 = rows[first.Id], rows[second.Id]

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

-- 2/3/8. Golpes
local p = newPlayer(1)
respawn(p, frontOf(b1[1]))
local damage = 7
WallService.OnClick(p, damage)
check(b1[1]:GetAttribute("Hp") == first.Hp - damage, "8. um golpe tira exatamente o dano (efeitos não mexem no HP)")
moveTo(p, V3.new(b1[1].CFrame.Position.X + 3, 3, 0)) -- dentro/atrás da fileira 1
local before = b1[1]:GetAttribute("Hp")
WallService.OnClick(p, damage)
check(b1[1]:GetAttribute("Hp") == before, "2. golpe por TRÁS da fileira não faz nada")
moveTo(p, frontOf(b1[1]))
WallService.OnClick(p, first.Hp) -- quebra a fileira 1
check(b1[1]:GetAttribute("Broken") == true and not b1[1].CanCollide and b1[1].Transparency == 1, "3. fileira quebrada some e não colide")
check(detailsVisible(b1[1], false), "3. detalhes da fileira quebrada somem junto (e não colidem)")
check(b1[2].CanCollide and b1[2]:GetAttribute("Broken") ~= true and detailsVisible(b1[2], true), "3. fileira seguinte continua de pé, sólida e com detalhes")
check(#noticesOf("WallRow") >= 1, "3. aviso de fileiras restantes enviado")

-- 4. Abertura, pads, sem teleporte
moveTo(p, frontOf(b1[2], 2))
for index = 2, #b1 do
	moveTo(p, frontOf(b1[index], 2))
	WallService.OnClick(p, first.Hp)
end
local broken = noticesOf("WallBroken")
local announced = broken[#broken]
check(announced ~= nil and announced[3].ById == p.UserId and announced[3].Order == first.Order, "4. quebra anunciada com quem quebrou (ById) e o estágio")
local wins0 = (currency[p] or {}).Wins or 0
touchHandlers["WinPad_" .. first.Id .. "_1"](p.Character.HumanoidRootPart)
local wins1 = (currency[p] or {}).Wins or 0
touchHandlers["WinPad_" .. first.Id .. "_1"](p.Character.HumanoidRootPart)
touchHandlers["WinPad_" .. first.Id .. "_2"](p.Character.HumanoidRootPart)
local wins2 = (currency[p] or {}).Wins or 0
check(wins1 > wins0 and wins2 == wins1, "4. pad paga uma vez por abertura (segundo toque e outro pad: nada)")
check(sentToSpawn == 0, "4. pegar o prêmio NÃO teleporta para a praça")
touchHandlers["ReturnPad_" .. first.Id](p.Character.HumanoidRootPart)
check(sentToSpawn == 1, "4. pad de voltar continua levando para a praça")
check(datas[p].Tower.Cleared[first.Id] == true and datas[p].Tower.Highest == first.Order, "4. estágio 1 registrado como conquistado")

-- 6. Não refaz em cima de quem está dentro
moveTo(p, V3.new(b1[2].CFrame.Position.X, 3, 0)) -- no meio do bloco
task.wait(1.2)
check(b1[1]:GetAttribute("Broken") == true, "6. barreira não se refaz com o personagem dentro dela")
moveTo(p, V3.new(b1[#b1].CFrame.Position.X + 40, 3, 0)) -- saiu pela frente (área 2)
task.wait(1.6)
check(b1[1]:GetAttribute("Broken") ~= true and b1[1].CanCollide and detailsVisible(b1[1], true), "6. sem ninguém dentro, a barreira volta inteira (com detalhes)")

-- 5. Barreira 2 e gemas da primeira vez
local function breakStage(player, list, hp)
	for _, row in list do
		moveTo(player, frontOf(row, 2))
		WallService.OnClick(player, hp)
	end
end
moveTo(p, frontOf(b2[1]))
check(rows[second.Id][1].CFrame.Position.X > b1[#b1].CFrame.Position.X, "1. Barreira 2 fica depois da 1, na mesma avenida")
local gems0 = (currency[p] or {}).Gems or 0
breakStage(p, b2, second.Hp)
local gems1 = (currency[p] or {}).Gems or 0
check(gems1 - gems0 == second.FirstClearGems, "5. gemas da primeira vez do estágio 2 pagas")
moveTo(p, V3.new(b2[#b2].CFrame.Position.X + 40, 3, 0))
task.wait(1.6)
breakStage(p, b2, second.Hp)
local gems2 = (currency[p] or {}).Gems or 0
check(gems2 == gems1, "5. quebrar de novo NÃO paga as gemas outra vez")

-- 7. Respawn
local spawnPoint = LobbyConfig.SpawnPoint + V3.new(0, 3, 0)
respawn(p, spawnPoint)
check(datas[p].Tower.Cleared[first.Id] and datas[p].Tower.Cleared[second.Id] and datas[p].Tower.Highest == second.Order, "7. respawn não perde o progresso do Caminho")
task.wait(1.6)
moveTo(p, frontOf(b1[1]))
local hpBefore = b1[1]:GetAttribute("Hp")
WallService.OnClick(p, damage)
check(b1[1]:GetAttribute("Hp") == hpBefore - damage, "7. depois do respawn o golpe volta a funcionar")

-- 9. Contornar / pular: a fileira cobre a largura do corredor inteira (sem vão
-- até as paredes laterais), e fileira e paredes laterais ficam muito acima de
-- um pulo (as paredes não precisam ser mais altas que a barreira, só que pulo).
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
				-- Parede que encosta na borda do corredor, na altura da barreira.
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
print("REQUER VALIDAÇÃO NO ROBLOX STUDIO: toque real nos pads, colisão do personagem, golpe/faísca/estilhaços, som, anúncio e câmera.")
if #problems > 0 then
	print(#problems .. " problema(s).")
	process.exit(1)
end
print("OK: loop do Caminho (quebrar, abrir, prêmio, avançar, respawn) sem regressão.")
process.exit(0)
