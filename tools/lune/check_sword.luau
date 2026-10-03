--[[
	check_sword.luau — roda o SwordService REAL com DataService, NetService e
	Players simulados, e confere que a espada equipada vai para o personagem
	em todos os caminhos:

	  1. jogador novo: personagem nasce ANTES dos dados, e a mão (RightHand)
	     só aparece depois — a espada inicial tem de aparecer;
	  2. respawn: a espada equipada reaparece no personagem novo;
	  3. trocar de espada (remote SwordAction): troca a espada da mão;
	  4. reentrar com espada salva: a última equipada reaparece;
	  5. dados migrados (v6 -> v7): espada inicial;
	  6. equipada inválida / não possuída: cai para a inicial;
	  7. corrida: dados + CharacterAdded + duas trocas rápidas -> UMA espada só,
	     nada sobrando na mochila.

		lune run tools/lune/check_sword.luau [raiz]

	O que NÃO dá para provar aqui (REQUER STUDIO): solda do cabo na mão
	(RightGrip), animação, a espada visível/seguindo o braço e a replicação
	para o cliente. Este script só garante que a Tool certa é criada, uma
	vez, no personagem certo, na hora certa.
]]
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")
local E = require("./env")(process.args[1])

local Signal = E.require(E.Shared.Utils.Signal)
local SwordConfig = E.require(E.Shared.Config.SwordConfig)
local SwordLogic = E.require(E.Shared.Formulas.SwordLogic)
local Migrations = E.require(E.Server.Services.DataService.Migrations)

--[[
	EquipTool: o Lune não tem. Imita o que o Studio mostrou: equipar num
	personagem que ainda não tem a mão direita não solda o cabo, e a espada
	(solta, sem colisão) cai para fora do mapa — aqui, vai para o Workspace e
	some do personagem. Com a mão presente, a Tool fica no personagem.
]]
roblox.implementMethod("Humanoid", "EquipTool", function(self, tool)
	local character = self.Parent
	if character and (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")) then
		tool.Parent = character
	else
		tool.Parent = E.Workspace
	end
end)

-- ── Stubs ───────────────────────────────────────────────────────────────────
local datas = {}
local DataService = {
	PlayerLoaded = Signal.new(),
	DataReset = Signal.new(),
	GetData = function(player)
		return datas[player]
	end,
	MarkChanged = function() end,
}
local invokeHandlers = {}
local NetService = {
	OnInvoke = function(name, _guard, handler)
		invokeHandlers[name] = handler
	end,
	FireClient = function() end,
}
local PlayersStub = { PlayerAdded = Signal.new(), PlayerRemoving = Signal.new(), list = {} }
function PlayersStub.GetPlayers()
	return PlayersStub.list
end
E.stubs.Players = PlayersStub
E.stubModules["ServerScriptService.Server.Services.DataService"] = DataService
E.stubModules["ServerScriptService.Server.Services.NetService"] = NetService

local SwordService = E.require(E.Server.Services.SwordService)
SwordService.Init()
SwordService.Start()

local nextUserId = 0
local function newPlayer()
	nextUserId += 1
	local backpack = roblox.Instance.new("Backpack")
	local attributes = {}
	local player
	player = {
		UserId = nextUserId,
		Character = nil,
		CharacterAdded = Signal.new(),
		SetAttribute = function(_, k, v)
			attributes[k] = v
		end,
		GetAttribute = function(_, k)
			return attributes[k]
		end,
		FindFirstChildOfClass = function(_, className)
			return if className == "Backpack" then backpack else nil
		end,
		Backpack = backpack,
	}
	table.insert(PlayersStub.list, player)
	PlayersStub.PlayerAdded:Fire(player)
	return player
end

-- Personagem: Model no Workspace com Humanoid e raiz; a mão pode vir depois.
local function spawnCharacter(player, handDelay: number?)
	local old = player.Character
	if old then
		old:Destroy()
	end
	local character = roblox.Instance.new("Model")
	character.Name = "Character" .. player.UserId
	roblox.Instance.new("Humanoid").Parent = character
	local root = roblox.Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Parent = character
	local function addHand()
		local hand = roblox.Instance.new("Part")
		hand.Name = "RightHand"
		hand.Parent = character
	end
	if handDelay then
		task.delay(handDelay, addHand)
	else
		addHand()
	end
	character.Parent = E.Workspace
	player.Character = character
	player.CharacterAdded:Fire(character)
	return character
end

local function blades(player)
	local inCharacter, inBackpack, id = 0, 0, nil
	if player.Character then
		for _, child in player.Character:GetChildren() do
			if child.Name == "CutBlade" then
				inCharacter += 1
				local blade = child:FindFirstChild("Blade")
				id = blade and blade.Color
			end
		end
	end
	for _, child in player.Backpack:GetChildren() do
		if child.Name == "CutBlade" then
			inBackpack += 1
		end
	end
	return inCharacter, inBackpack, id
end

local problems = {}
local function expectBlade(player, swordId: string, label: string)
	local inCharacter, inBackpack, color = blades(player)
	local sword = SwordConfig.Swords[swordId]
	if inCharacter ~= 1 or inBackpack ~= 0 then
		table.insert(problems, string.format("%s: %d espada(s) no personagem, %d na mochila (esperado 1 e 0)", label, inCharacter, inBackpack))
	elseif color ~= sword.Color then
		table.insert(problems, label .. ": a espada na mão não é " .. swordId)
	elseif player:GetAttribute("EquippedSword") ~= swordId then
		table.insert(problems, label .. ": atributo EquippedSword ≠ " .. swordId)
	else
		print("OK   " .. label)
	end
end

local function otherSword(): string
	for _, sword in SwordLogic.Ordered() do
		if sword.Id ~= SwordConfig.DefaultSword then
			return sword.Id
		end
	end
	error("só existe uma espada")
end
local second = otherSword()
local function settle()
	task.wait(1.2)
end

-- 1. Jogador novo: personagem antes dos dados; mão chega depois.
local p1 = newPlayer()
spawnCharacter(p1, 0.5)
task.wait(0.1)
datas[p1] = { Swords = SwordLogic.Fresh(), Stats = { Rebirths = 0 }, Currencies = { Wins = 0 }, Tower = { Cleared = {}, Highest = 0 } }
DataService.PlayerLoaded:Fire(p1, datas[p1])
settle()
expectBlade(p1, SwordConfig.DefaultSword, "1. jogador novo (mão chega depois dos dados)")

-- 2. Respawn.
spawnCharacter(p1, 0.3)
settle()
expectBlade(p1, SwordConfig.DefaultSword, "2. respawn")

-- 3. Trocar de espada pelo remote.
datas[p1].Swords.Owned[second] = true
local response = invokeHandlers.SwordAction(p1, second)
settle()
if not response.Ok then
	table.insert(problems, "3. troca recusada: " .. tostring(response.Code))
end
expectBlade(p1, second, "3. trocar de espada")

-- 4. Reentrar com a espada salva.
local p2 = newPlayer()
datas[p2] = { Swords = { Owned = { [SwordConfig.DefaultSword] = true, [second] = true }, Equipped = second }, Stats = { Rebirths = 0 }, Currencies = { Wins = 0 }, Tower = { Cleared = {}, Highest = 0 } }
DataService.PlayerLoaded:Fire(p2, datas[p2])
spawnCharacter(p2)
settle()
expectBlade(p2, second, "4. reentrar com espada salva")

-- 5. Dados migrados (v6 -> v7).
local p3 = newPlayer()
local migrated = { DataVersion = 6, Stats = { Rebirths = 0 }, Currencies = { Wins = 0 }, Tower = { Cleared = {}, Highest = 0 } }
Migrations.Steps[6](migrated)
datas[p3] = migrated
spawnCharacter(p3)
DataService.PlayerLoaded:Fire(p3, migrated)
settle()
expectBlade(p3, SwordConfig.DefaultSword, "5. dados migrados")

-- 6. Equipada inválida / não possuída.
local p4 = newPlayer()
datas[p4] = { Swords = { Owned = { [SwordConfig.DefaultSword] = true }, Equipped = second }, Stats = { Rebirths = 0 }, Currencies = { Wins = 0 }, Tower = { Cleared = {}, Highest = 0 } }
spawnCharacter(p4)
DataService.PlayerLoaded:Fire(p4, datas[p4])
settle()
expectBlade(p4, SwordConfig.DefaultSword, "6a. equipada não possuída -> inicial")
local p5 = newPlayer()
datas[p5] = { Swords = { Owned = { [SwordConfig.DefaultSword] = true }, Equipped = "NoSuchBlade" }, Stats = { Rebirths = 0 }, Currencies = { Wins = 0 }, Tower = { Cleared = {}, Highest = 0 } }
spawnCharacter(p5)
DataService.PlayerLoaded:Fire(p5, datas[p5])
settle()
expectBlade(p5, SwordConfig.DefaultSword, "6b. equipada inexistente -> inicial")

-- 7. Corrida: dados + CharacterAdded + duas trocas rápidas, mão atrasada.
local p6 = newPlayer()
datas[p6] = { Swords = { Owned = { [SwordConfig.DefaultSword] = true, [second] = true }, Equipped = SwordConfig.DefaultSword }, Stats = { Rebirths = 0 }, Currencies = { Wins = 0 }, Tower = { Cleared = {}, Highest = 0 } }
spawnCharacter(p6, 0.4)
DataService.PlayerLoaded:Fire(p6, datas[p6])
invokeHandlers.SwordAction(p6, second)
invokeHandlers.SwordAction(p6, SwordConfig.DefaultSword)
invokeHandlers.SwordAction(p6, second)
settle()
expectBlade(p6, second, "7a. corrida na entrada (uma espada só)")
spawnCharacter(p6)
invokeHandlers.SwordAction(p6, SwordConfig.DefaultSword)
settle()
expectBlade(p6, SwordConfig.DefaultSword, "7b. respawn + troca imediata (uma espada só)")

print("Requer validação no Studio: espada soldada na mão (RightGrip), visível e seguindo o braço; replicação ao cliente.")
if #problems > 0 then
	print(#problems .. " problema(s):")
	for _, message in problems do
		print("  " .. message)
	end
	process.exit(1)
end
print("OK: espada equipada aplicada em todos os caminhos.")
process.exit(0)
