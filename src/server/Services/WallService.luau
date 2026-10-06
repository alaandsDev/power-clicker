--!strict
--[[
	WallService
	O CAMINHO DO PODER: as barreiras de cada estágio e os pads de vitória atrás
	delas. Cada jogador faz o SEU caminho: HP, abertura, janela dos pads e
	passagem são por jogador, mesmo com todos no mesmo servidor.

	A stage is several rows of the same material. Every click a player makes
	also hits the row in front of them (ClickService routes it here); each row
	has its own HP — for that player — and is broken on its own. When the
	player breaks the LAST row of a stage, the stage is open FOR THAT PLAYER:
	for WallConfig.OpenSeconds a win pad pays them once, and they may walk
	through. Then that player's rows come back at full HP (never on top of
	them: it waits for them to step out of the block).

	First clear: the first time a player opens a stage, it is written to
	PlayerData.Tower and pays the stage's gems. Every clear after that pays only
	the win pads, at the repeat share (WinPadRules / WallConfig.Repeat).

	SERVIDOR x CLIENTE
	- As peças das fileiras no Workspace são COMPARTILHADAS e ficam sempre
	  inteiras e sólidas no servidor. Esconder ou tirar a colisão de uma delas
	  aqui liberaria todo mundo; por isso o servidor nunca mexe nelas.
	- O servidor é dono do estado: HP de cada fileira por jogador, abertura,
	  janela, prêmio, ordem e progresso salvo. Cada cliente recebe SÓ o próprio
	  estado pelo remote WallState.
	- O cliente (WallController) desenha esse estado: barra, rachadura, flash,
	  estilhaços, e esconde/tira a colisão LOCALMENTE das fileiras que aquele
	  jogador quebrou. A física do personagem roda no cliente dono dele, então
	  só ele atravessa; os outros continuam batendo na fileira inteira.
	- Anti-exploit: um cliente pode apagar a fileira localmente e atravessar
	  (noclip). O servidor não confia nisso: a posição de cada jogador é
	  conferida contra as barreiras DELE (Validate); quem está além de uma
	  barreira que não abriu volta para a frente dela, e golpe e pad exigem
	  posição válida. Nada de progresso, prêmio ou acesso sem ter quebrado.

	Parts come from WorldBuilder with attributes:
		Wall = true, StageId, Row = <n>, Rows = <total>
		WinPad = true, StageId, Wins = <amount> | Return = true
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Logger = require(Shared.Utils.Logger)
local Signal = require(Shared.Utils.Signal)
local WallConfig = require(Shared.Config.WallConfig)
local WinPadRules = require(Shared.Formulas.WinPadRules)

local NetService = require(script.Parent.NetService)
local DataService = require(script.Parent.DataService)
local CurrencyService = require(script.Parent.CurrencyService)
local WorldService = require(script.Parent.WorldService)

type Stage = WallConfig.WallStage

-- Geometria de um estágio (igual para todos; vem do mapa).
type StageGeo = {
	Stage: Stage,
	Rows: { BasePart }, -- por Row
	RowFront: { number }, -- x da face de entrada de cada fileira
	Front: number, -- x da face de entrada da primeira fileira
	Back: number, -- x da face de saída da última fileira
	HalfZ: number,
	Top: number,
}

-- O estado de UM estágio para UM jogador.
type PlayerStage = {
	Hp: { number }, -- por fileira; 0 = quebrada para este jogador
	Open: boolean, -- todas as fileiras quebradas: a passagem dele está aberta
	Opening: number, -- sobe a cada abertura; o prêmio é um por abertura
	OpenUntil: number, -- os.clock() até quando os pads pagam
	FirstOpening: number, -- a abertura em que o estágio caiu pela 1a vez (0 = nenhuma)
	Claimed: number, -- a abertura cujo prêmio já foi pego
}

type Run = {
	Stages: { [string]: PlayerStage },
	-- Barreiras que o jogador atravessou com a passagem aberta, desde que saiu
	-- da praça. Quem está além delas está num lugar legítimo mesmo depois que
	-- a barreira se refaz atrás dele.
	Passed: { [string]: boolean },
	LastPush: number,
	LastPadNotice: number,
}

-- Quanto além da face da barreira o centro do personagem pode estar (atraso
-- de replicação de posição). Além disso, é atravessar sem ter quebrado.
local PASS_TOLERANCE = 2
-- Onde quem atravessou sem direito é colocado de volta: à frente da barreira.
local PUSH_BACK = 6
local VALIDATE_SECONDS = 0.25
-- Intervalo mínimo entre dois avisos de "este pad não paga agora" (o Touched
-- dispara várias vezes por passo).
local PAD_NOTICE_SECONDS = 3

local log = Logger.new("Walls")

local WallService = {
	-- (player, stageId, wins)
	Claimed = Signal.new() :: Signal.Signal<Player, string, number>,
	-- (player, stageId)
	Opened = Signal.new() :: Signal.Signal<Player, string>,
}

local geos: { [string]: StageGeo } = {}
local ordered: { StageGeo } = {}
local pads: { BasePart } = {}
local runs: { [Player]: Run } = {}
local scanned = false

local function stageById(id: any): Stage?
	if type(id) ~= "string" then
		return nil
	end
	for _, stage in WallConfig.Stages do
		if stage.Id == id then
			return stage
		end
	end
	return nil
end

local function runOf(player: Player): Run
	local run = runs[player]
	if not run then
		run = { Stages = {}, Passed = {}, LastPush = 0, LastPadNotice = 0 }
		runs[player] = run
	end
	return run
end

local function stateOf(run: Run, stage: Stage): PlayerStage
	local state = run.Stages[stage.Id]
	if not state then
		local hp = table.create(stage.Rows, stage.Hp)
		state = { Hp = hp, Open = false, Opening = 0, OpenUntil = 0, FirstOpening = 0, Claimed = 0 }
		run.Stages[stage.Id] = state
	end
	return state
end

-- Manda ao cliente do jogador o estado dos estágios indicados (só dele).
local function sendState(player: Player, stageIds: { string })
	local run = runs[player]
	if not run then
		return
	end
	local payload = {}
	for _, stageId in stageIds do
		local state = run.Stages[stageId]
		if state then
			payload[stageId] = { Hp = table.clone(state.Hp), Open = state.Open }
		end
	end
	NetService.FireClient("WallState", player, payload)
end

-- Estado completo (estágios sem entrada = inteiros). Vai na entrada do jogador.
local function sendAll(player: Player)
	local ids = {}
	for stageId in runOf(player).Stages do
		table.insert(ids, stageId)
	end
	sendState(player, ids)
end

local function characterRoot(player: Player): BasePart?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

local function characterPosition(player: Player): Vector3?
	local root = characterRoot(player)
	return if root then root.Position else nil
end

local function insideBlock(geo: StageGeo, position: Vector3): boolean
	return position.X > geo.Front - 3 and position.X < geo.Back + 3 and math.abs(position.Z) <= geo.HalfZ + 1 and position.Y < geo.Top + 4
end

local function inCorridorWorld(player: Player): boolean
	local data = DataService.GetData(player)
	return data ~= nil and data.Worlds.Current == WallConfig.WorldId
end

--[[
	A posição do jogador é válida para o caminho DELE? Percorre as barreiras
	em ordem: as já atravessadas ficam para trás; numa barreira aberta para ele
	vale estar antes, dentro ou depois (e depois dela conta como atravessada);
	na primeira barreira fechada, o limite é a face da primeira fileira ainda
	de pé PARA ESTE JOGADOR (quem quebrou a fileira 1 entra no bloco para bater
	na 2). Devolve (válida, barreira-limite, x-limite).
]]
local function legality(run: Run, position: Vector3): (boolean, StageGeo?, number?)
	if position.X < WallConfig.Layout.StartX then
		-- Na praça: nova tentativa; nada atravessado vale mais.
		table.clear(run.Passed)
		return true, nil
	end
	for _, geo in ordered do
		local id = geo.Stage.Id
		if run.Passed[id] then
			continue
		end
		local state = run.Stages[id]
		if state and state.Open then
			if position.X > geo.Back then
				run.Passed[id] = true
				continue
			end
			return true, nil
		end
		local limit = geo.Front
		for index = 1, geo.Stage.Rows do
			local hp = if state then state.Hp[index] else geo.Stage.Hp
			if hp > 0 and geo.RowFront[index] then
				limit = geo.RowFront[index]
				break
			end
		end
		return position.X <= limit + PASS_TOLERANCE, geo, limit
	end
	return true, nil
end

-- Leva de volta para a frente da barreira quem está além dela sem direito.
local function pushBack(player: Player, run: Run, geo: StageGeo, limit: number)
	local root = characterRoot(player)
	local character = player.Character
	if not root or not character then
		return
	end
	local position = root.Position
	local target = Vector3.new(limit - PUSH_BACK, math.max(position.Y, 3), math.clamp(position.Z, -geo.HalfZ + 3, geo.HalfZ - 3))
	character:PivotTo(CFrame.lookAt(target, target + Vector3.new(1, 0, 0)))
	-- Sempre leva de volta; só o log é limitado (um exploit insistente não
	-- enche o console).
	local now = os.clock()
	if now - run.LastPush >= 2 then
		run.LastPush = now
		log:Warn(string.format("user=%d beyond %s without opening it: pushed back", player.UserId, geo.Stage.Id))
	end
end

--[[
	Confere a posição de um jogador (o laço chama para todos a cada
	VALIDATE_SECONDS; golpe e pad chamam antes de agir). Devolve se está num
	lugar válido; se não estiver, já o leva de volta.
]]
function WallService.Validate(player: Player): boolean
	if not scanned or not inCorridorWorld(player) then
		return true
	end
	local position = characterPosition(player)
	if not position then
		return true
	end
	local run = runOf(player)
	local ok, geo, limit = legality(run, position)
	if not ok and geo and limit then
		pushBack(player, run, geo, limit)
	end
	return ok
end

--[[
	Fecha a barreira DESTE jogador quando a janela dele acaba — nunca em cima
	dele: se o personagem estiver dentro do bloco de fileiras, espera ele sair.
	Os outros jogadores não contam: a barreira deles é outra.
]]
local function restoreWhenClear(player: Player, stageId: string, opening: number)
	local run = runs[player]
	local geo = geos[stageId]
	local state = if run then run.Stages[stageId] else nil
	if not run or not geo or not state or state.Opening ~= opening or not state.Open then
		return
	end
	local position = characterPosition(player)
	if position and insideBlock(geo, position) then
		task.delay(1, restoreWhenClear, player, stageId, opening)
		return
	end
	if position and position.X > geo.Back then
		-- Atravessou com a passagem aberta: continua legítimo do outro lado.
		run.Passed[stageId] = true
	end
	state.Open = false
	state.OpenUntil = 0
	for index in state.Hp do
		state.Hp[index] = geo.Stage.Hp
	end
	sendState(player, { stageId })
end

--[[
	The row closest to the player that is still standing FOR THIS PLAYER, if any
	is in reach — and only rows IN FRONT of the player (the corridor runs to +X).
]]
local function nearestRow(run: Run, position: Vector3): (StageGeo?, number?)
	local bestGeo: StageGeo? = nil
	local bestIndex: number? = nil
	local bestDistance = WallConfig.HitRange
	for _, geo in ordered do
		local state = run.Stages[geo.Stage.Id]
		for index, part in geo.Rows do
			local standing = if state then state.Hp[index] > 0 else true
			if standing and position.X < part.Position.X then
				local distance = (part.Position - position).Magnitude
				if distance <= bestDistance then
					bestGeo, bestIndex, bestDistance = geo, index, distance
				end
			end
		end
	end
	return bestGeo, bestIndex
end

local function playerOf(part: BasePart): Player?
	local character = part.Parent
	return if character then Players:GetPlayerFromCharacter(character) else nil
end

local function onPadTouched(pad: BasePart, hit: BasePart)
	local player = playerOf(hit)
	if not player then
		return
	end
	local stageId = pad:GetAttribute("StageId")
	local geo = if type(stageId) == "string" then geos[stageId] else nil
	if not geo then
		return
	end

	if pad:GetAttribute("Return") == true then
		WorldService.SendToSpawn(player)
		return
	end
	-- Só paga quem está num lugar legítimo do PRÓPRIO caminho...
	if not WallService.Validate(player) then
		return
	end
	-- ...e com a barreira DELE aberta, dentro da janela, uma vez por abertura.
	local run = runOf(player)
	local state = run.Stages[geo.Stage.Id]
	if not state or not state.Open or os.clock() >= state.OpenUntil then
		--[[
			O pad só paga logo depois de ESTE jogador quebrar ESTA barreira. Antes
			isto voltava calado e parecia defeito ("pisei e não ganhei"): agora
			o jogador fica sabendo o porquê.
		]]
		local now = os.clock()
		if now - run.LastPadNotice >= PAD_NOTICE_SECONDS then
			run.LastPadNotice = now
			NetService.FireClient("Notify", player, "WinPadClosed", { StageId = geo.Stage.Id, Order = geo.Stage.Order })
		end
		return
	end
	if state.Claimed == state.Opening then
		return -- already took a pad in this opening
	end
	local amount = pad:GetAttribute("Wins")
	if type(amount) ~= "number" or amount <= 0 then
		return
	end
	local data = DataService.GetData(player)
	if not data then
		return
	end
	state.Claimed = state.Opening

	--[[
		Quanto este pad paga agora (WinPadRules, a mesma regra da placa):
		- abertura da primeira conquista deste jogador: valor cheio;
		- repetindo: fração de repetição, e o pad x2 vale sempre o dobro do
		  normal.
	]]
	local isFirstClear = state.FirstOpening == state.Opening
	local share = WinPadRules.Share(geo.Stage, data.Tower, isFirstClear)
	local padIndex = pad:GetAttribute("PadIndex")
	if type(padIndex) ~= "number" then
		padIndex = WinPadRules.IndexOf(geo.Stage, amount) or 1
	end
	local payout = WinPadRules.Payout(geo.Stage, padIndex :: number, share)
	if payout <= 0 then
		return
	end
	local granted = CurrencyService.Add(player, WallConfig.Currency, payout, "WinPad:" .. geo.Stage.Id)
	NetService.FireClient("Notify", player, "WinPad", { StageId = geo.Stage.Id, Wins = granted, Share = share })
	WallService.Claimed:Fire(player, geo.Stage.Id, granted)
	-- Pegar o prêmio ENCERRA a corrida: o jogador volta para a praça. Quem quer
	-- a barreira seguinte passa direto pelos pads, sem pegar nenhum.
	WorldService.SendToSpawn(player)
end

-- Finds the corridor once the world exists.
local function scan()
	local map = Workspace:FindFirstChild("Map")
	local worlds = if map then map:FindFirstChild("Worlds") else nil
	local world = if worlds then worlds:FindFirstChild(WallConfig.WorldId) else nil
	if not world then
		return
	end
	table.clear(geos)
	table.clear(ordered)
	table.clear(pads)
	for _, descendant in world:GetDescendants() do
		if not descendant:IsA("BasePart") then
			continue
		end
		if descendant:GetAttribute("Wall") == true then
			local stage = stageById(descendant:GetAttribute("StageId"))
			local index = descendant:GetAttribute("Row")
			if stage and type(index) == "number" then
				local geo = geos[stage.Id]
				if not geo then
					geo = { Stage = stage, Rows = {}, RowFront = {}, Front = math.huge, Back = -math.huge, HalfZ = 0, Top = 0 }
					geos[stage.Id] = geo
				end
				local g = geo :: StageGeo
				g.Rows[index] = descendant
				g.RowFront[index] = descendant.Position.X - descendant.Size.X / 2
				g.Front = math.min(g.Front, descendant.Position.X - descendant.Size.X / 2)
				g.Back = math.max(g.Back, descendant.Position.X + descendant.Size.X / 2)
				g.HalfZ = math.max(g.HalfZ, descendant.Size.Z / 2)
				g.Top = math.max(g.Top, descendant.Position.Y + descendant.Size.Y / 2)
				-- A peça é de todos: inteira e sólida no servidor, sempre.
				descendant:SetAttribute("MaxHp", stage.Hp)
			end
		elseif descendant:GetAttribute("WinPad") == true then
			table.insert(pads, descendant)
			descendant.Touched:Connect(function(hit: BasePart)
				onPadTouched(descendant, hit)
			end)
		end
	end
	for _, stage in WallConfig.Stages do
		local geo = geos[stage.Id]
		if geo then
			table.insert(ordered, geo)
		end
	end
	scanned = #ordered > 0
	if scanned then
		log:Info(string.format("win corridor: %d stage(s), %d pad(s), per-player barriers", #ordered, #pads))
	end
end

--[[
	One click's worth of damage against the row in front of the player — the
	row as it is FOR THIS PLAYER. Always returns 0: the corridor pays in wins,
	on the pads, never in Power. Called by ClickService.
]]
function WallService.OnClick(player: Player, damage: number): number
	if not scanned or damage <= 0 then
		return 0
	end
	local data = DataService.GetData(player)
	local position = characterPosition(player)
	if not data or not position or data.Worlds.Current ~= WallConfig.WorldId then
		return 0
	end
	if not WallService.Validate(player) then
		return 0
	end
	local run = runOf(player)
	local geo, index = nearestRow(run, position)
	if not geo or not index then
		return 0
	end
	local stage = geo.Stage
	local state = stateOf(run, stage)
	state.Hp[index] = math.max(state.Hp[index] - damage, 0)
	if state.Hp[index] > 0 then
		sendState(player, { stage.Id })
		return 0
	end

	local remaining = 0
	for _, hp in state.Hp do
		if hp > 0 then
			remaining += 1
		end
	end
	if remaining > 0 then
		sendState(player, { stage.Id })
		NetService.FireClient("Notify", player, "WallRow", {
			StageId = stage.Id,
			Remaining = remaining,
		})
		return 0
	end

	-- Last row down: THIS player's passage is open for a while.
	state.Open = true
	state.Opening += 1
	state.OpenUntil = os.clock() + WallConfig.OpenSeconds
	local opening = state.Opening
	task.delay(WallConfig.OpenSeconds, restoreWhenClear, player, stage.Id, opening)
	sendState(player, { stage.Id })
	--[[
		First time this player gets through this stage: record it and pay the
		gems. Marked BEFORE granting, so a failure in the grant cannot pay it
		twice on a retry.
	]]
	local tower = data.Tower
	local firstClear = 0
	local isFirstClear = not tower.Cleared[stage.Id]
	if isFirstClear then
		state.FirstOpening = opening
		tower.Cleared[stage.Id] = true
		tower.Highest = math.max(tower.Highest, stage.Order)
		DataService.MarkChanged(player, "Tower")
		if stage.FirstClearGems > 0 then
			local gems = CurrencyService.Add(player, WallConfig.GemCurrency, stage.FirstClearGems, "TowerClear:" .. stage.Id)
			NetService.FireClient("Notify", player, "TowerCleared", {
				StageId = stage.Id,
				Order = stage.Order,
				Gems = gems,
			})
			firstClear = gems
		end
	end

	-- Só quem quebrou fica sabendo: a barreira dos outros continua inteira.
	NetService.FireClient("Notify", player, "WallBroken", {
		StageId = stage.Id,
		Order = stage.Order,
		Seconds = WallConfig.OpenSeconds,
		ById = player.UserId,
		FirstClear = isFirstClear,
		FirstClearGems = firstClear,
	})
	WallService.Opened:Fire(player, stage.Id)
	log:Info(string.format("user=%d opened stage %s", player.UserId, stage.Id))
	return 0
end

-- Leitura para testes e ferramentas: HP da fileira `row` para este jogador.
function WallService.RowHp(player: Player, stageId: string, row: number): number?
	local run = runs[player]
	local state = if run then run.Stages[stageId] else nil
	if state then
		return state.Hp[row]
	end
	local geo = geos[stageId]
	return if geo then geo.Stage.Hp else nil
end

function WallService.IsOpen(player: Player, stageId: string): boolean
	local run = runs[player]
	local state = if run then run.Stages[stageId] else nil
	return state ~= nil and state.Open
end

function WallService.Init()
	Players.PlayerRemoving:Connect(function(player)
		runs[player] = nil
	end)
	-- Estado inicial (ou o atual, se já houver) assim que o cliente escuta.
	DataService.PlayerReady:Connect(function(player: Player)
		sendAll(player)
	end)
end

function WallService.Start()
	scan()
	task.spawn(function()
		while not scanned do
			task.wait(1)
			scan()
		end
		while true do
			task.wait(VALIDATE_SECONDS)
			for _, player in Players:GetPlayers() do
				WallService.Validate(player)
			end
		end
	end)
end

return WallService
