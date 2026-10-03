--!strict
--[[
	WallService
	A TORRE: as barreiras de cada estágio e os pads de vitória atrás delas.

	A stage is several rows of the same material. Every click a player makes
	also hits the row in front of them (ClickService routes it here, like the
	zone targets); each row has its own HP and is broken on its own. When the
	LAST row of a stage falls, the room behind it is open for
	WallConfig.OpenSeconds, and whoever steps on a win pad in that window gets
	its wins — once per opening per player. Then every row of that stage comes
	back at full HP.

	First clear: the first time a player opens a stage, it is written to
	PlayerData.Tower and pays the stage's gems (the gem tap the economy was
	missing). Every clear after that pays only the win pads — and less of them:
	WallConfig.Repeat makes a repeat pay a share, falling off the further the
	stage is below the player's best. Farming the barrier you are breaking now
	is the game; farming the wooden one with the Colossus unlocked is not.

	Authority: HP, the open window, the claims and the payout are server-side.
	The client only reads the "Hp" attribute to draw the bar, and a pad touch is
	re-checked here (the stage must really be open, and this must really be that
	player's first claim of the opening).

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

local NetService = require(script.Parent.NetService)
local DataService = require(script.Parent.DataService)
local CurrencyService = require(script.Parent.CurrencyService)
local WorldService = require(script.Parent.WorldService)

type Stage = WallConfig.WallStage

type RowState = {
	Part: BasePart,
	Index: number,
	Hp: number,
	Standing: boolean,
}

type StageState = {
	Stage: Stage,
	Rows: { RowState },
	Opening: number, -- bumped every time the stage opens; claims are keyed by it
	OpenUntil: number, -- os.clock(); 0 = the block is whole
}

local log = Logger.new("Walls")

local WallService = {
	-- (player, stageId, wins)
	Claimed = Signal.new() :: Signal.Signal<Player, string, number>,
	-- (player, stageId)
	Opened = Signal.new() :: Signal.Signal<Player, string>,
}

local stages: { [string]: StageState } = {}
local pads: { BasePart } = {}
-- claims[stageId][player] = the opening number already claimed
local claims: { [string]: { [Player]: number } } = {}
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

local function setRow(row: RowState, hp: number, standing: boolean)
	row.Hp = math.max(hp, 0)
	row.Standing = standing
	row.Part:SetAttribute("Hp", row.Hp)
	row.Part:SetAttribute("Broken", not standing)
	row.Part.Transparency = if standing then 0 else 1
	row.Part.CanCollide = standing
	-- Detalhes visuais da fileira (tábuas, juntas, rachaduras: WorldBuilder)
	-- somem e voltam junto com ela. Só aparência; não têm colisão.
	for _, child in row.Part:GetChildren() do
		if child:IsA("BasePart") and child:GetAttribute("WallDetail") == true then
			local base = child:GetAttribute("BaseTransparency")
			child.Transparency = if standing then (if type(base) == "number" then base else 0) else 1
		end
	end
end

-- Rebuilds every row of the stage and closes the room again.
local function restore(state: StageState)
	state.OpenUntil = 0
	for _, row in state.Rows do
		setRow(row, state.Stage.Hp, true)
	end
end

-- Is any character standing inside the stage's block of rows right now?
local function someoneInside(state: StageState): boolean
	local minX, maxX = math.huge, -math.huge
	local halfZ, top = 0, 0
	for _, row in state.Rows do
		local part = row.Part
		minX = math.min(minX, part.Position.X - part.Size.X / 2)
		maxX = math.max(maxX, part.Position.X + part.Size.X / 2)
		halfZ = math.max(halfZ, part.Size.Z / 2)
		top = math.max(top, part.Position.Y + part.Size.Y / 2)
	end
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if root and root:IsA("BasePart") then
			local p = root.Position
			if p.X > minX - 3 and p.X < maxX + 3 and math.abs(p.Z) <= halfZ + 1 and p.Y < top + 4 then
				return true
			end
		end
	end
	return false
end

--[[
	Fecha a sala quando a janela acaba — mas nunca em cima de alguém: se um
	personagem ainda estiver dentro do bloco de fileiras, espera ele sair
	(fileiras sólidas surgindo em volta de um personagem o prendiam ou o
	arremessavam). A janela dos pads acaba no horário de qualquer jeito.
]]
local function restoreWhenClear(state: StageState, opening: number)
	if state.Opening ~= opening then
		return
	end
	if someoneInside(state) then
		task.delay(1, restoreWhenClear, state, opening)
		return
	end
	restore(state)
end

local function characterPosition(player: Player): Vector3?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root.Position else nil
end

--[[
	The standing row closest to the player, if any is in reach — and only rows
	IN FRONT of the player (the corridor runs to +X, so the row's centre must
	be ahead of the player). Without this a player who walked through could
	keep hitting the barrier from behind; now that a win pad no longer sends
	the player back to the plaza, that would turn the room into a farm.
]]
local function nearestRow(position: Vector3): (StageState?, RowState?, number)
	local bestStage: StageState? = nil
	local bestRow: RowState? = nil
	local bestDistance = WallConfig.HitRange
	for _, state in stages do
		for _, row in state.Rows do
			if row.Standing and position.X < row.Part.Position.X then
				local distance = (row.Part.Position - position).Magnitude
				if distance <= bestDistance then
					bestStage, bestRow, bestDistance = state, row, distance
				end
			end
		end
	end
	return bestStage, bestRow, bestDistance
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
	local state = if type(stageId) == "string" then stages[stageId] else nil
	if not state then
		return
	end

	if pad:GetAttribute("Return") == true then
		WorldService.SendToSpawn(player)
		return
	end
	-- A pad only pays while its stage is open.
	if state.OpenUntil == 0 or os.clock() >= state.OpenUntil then
		return
	end
	local byStage = claims[state.Stage.Id]
	if not byStage then
		byStage = {}
		claims[state.Stage.Id] = byStage
	end
	if byStage[player] == state.Opening then
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
	byStage[player] = state.Opening

	--[[
		Quanto este pad paga agora:
		- primeira vez neste estágio: valor cheio;
		- repetindo: `Share`, caindo `FalloffPerStage` por degrau de distância
		  entre este estágio e o melhor que o jogador já passou.
	]]
	local repeatRule = WallConfig.Repeat
	local share = 1
	if data.Tower.Cleared[state.Stage.Id] then
		local behind = math.max(data.Tower.Highest - state.Stage.Order, 0)
		share = math.max(repeatRule.Share * repeatRule.FalloffPerStage ^ behind, repeatRule.MinShare)
	end
	local payout = math.max(math.floor(amount * share), 1)
	local granted = CurrencyService.Add(player, WallConfig.Currency, payout, "WinPad:" .. state.Stage.Id)
	NetService.FireClient("Notify", player, "WinPad", { StageId = state.Stage.Id, Wins = granted, Share = share })
	WallService.Claimed:Fire(player, state.Stage.Id, granted)
	--[[
		O prêmio NÃO manda mais o jogador para a praça: quem quebrou a barreira
		segue andando para a próxima área ("quebrei e agora passo"). Voltar é
		pelo pad vermelho de voltar, que continua em cada estágio.
	]]
end

-- Finds the corridor once the world exists.
local function scan()
	local map = Workspace:FindFirstChild("Map")
	local worlds = if map then map:FindFirstChild("Worlds") else nil
	local world = if worlds then worlds:FindFirstChild(WallConfig.WorldId) else nil
	if not world then
		return
	end
	table.clear(stages)
	table.clear(pads)
	for _, descendant in world:GetDescendants() do
		if not descendant:IsA("BasePart") then
			continue
		end
		if descendant:GetAttribute("Wall") == true then
			local stage = stageById(descendant:GetAttribute("StageId"))
			local index = descendant:GetAttribute("Row")
			if stage and type(index) == "number" then
				local state = stages[stage.Id]
				if not state then
					state = { Stage = stage, Rows = {}, Opening = 0, OpenUntil = 0 }
					stages[stage.Id] = state
				end
				local row: RowState = { Part = descendant, Index = index, Hp = stage.Hp, Standing = true }
				descendant:SetAttribute("MaxHp", stage.Hp)
				setRow(row, stage.Hp, true)
				table.insert((state :: StageState).Rows, row)
			end
		elseif descendant:GetAttribute("WinPad") == true then
			table.insert(pads, descendant)
			descendant.Touched:Connect(function(hit: BasePart)
				onPadTouched(descendant, hit)
			end)
		end
	end
	for _, state in stages do
		table.sort(state.Rows, function(a, b)
			return a.Index < b.Index
		end)
	end
	scanned = next(stages) ~= nil
	if scanned then
		log:Info(string.format("win corridor: %d stage(s), %d pad(s)", #WallConfig.Stages, #pads))
	end
end

--[[
	One click's worth of damage against the row in front of the player.
	Always returns 0: the corridor pays in wins, on the pads, never in Power.
	Called by ClickService.
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
	local state, row = nearestRow(position)
	if not state or not row then
		return 0
	end
	setRow(row, row.Hp - damage, row.Hp - damage > 0)
	if row.Standing then
		return 0
	end

	local remaining = 0
	for _, other in state.Rows do
		if other.Standing then
			remaining += 1
		end
	end
	if remaining > 0 then
		NetService.FireClient("Notify", player, "WallRow", {
			StageId = state.Stage.Id,
			Remaining = remaining,
		})
		return 0
	end

	-- Last row down: the room is open for a while, then everything is back.
	state.Opening += 1
	state.OpenUntil = os.clock() + WallConfig.OpenSeconds
	local opening = state.Opening
	task.delay(WallConfig.OpenSeconds, restoreWhenClear, state, opening)
	--[[
		First time this player gets through this stage: record it and pay the
		gems. Marked BEFORE granting, so a failure in the grant cannot pay it
		twice on a retry.
	]]
	local tower = data.Tower
	local firstClear = 0
	if not tower.Cleared[state.Stage.Id] then
		tower.Cleared[state.Stage.Id] = true
		tower.Highest = math.max(tower.Highest, state.Stage.Order)
		DataService.MarkChanged(player, "Tower")
		if state.Stage.FirstClearGems > 0 then
			local gems = CurrencyService.Add(player, WallConfig.GemCurrency, state.Stage.FirstClearGems, "TowerClear:" .. state.Stage.Id)
			NetService.FireClient("Notify", player, "TowerCleared", {
				StageId = state.Stage.Id,
				Order = state.Stage.Order,
				Gems = gems,
			})
			firstClear = gems
		end
	end

	-- Todos recebem (a barreira some para todos), mas cada cliente decide: quem
	-- quebrou vê o anúncio grande; quem está perto, um aviso curto; o resto,
	-- nada (antes era um aviso para o servidor inteiro a cada quebra).
	NetService.FireAllClients("Notify", "WallBroken", {
		StageId = state.Stage.Id,
		Order = state.Stage.Order,
		Seconds = WallConfig.OpenSeconds,
		By = player.DisplayName,
		ById = player.UserId,
		FirstClearGems = firstClear,
	})
	WallService.Opened:Fire(player, state.Stage.Id)
	log:Info(string.format("user=%d opened stage %s", player.UserId, state.Stage.Id))
	return 0
end

function WallService.Init()
	Players.PlayerRemoving:Connect(function(player)
		for _, byStage in claims do
			byStage[player] = nil
		end
	end)
end

function WallService.Start()
	scan()
	task.spawn(function()
		while not scanned do
			task.wait(1)
			scan()
		end
	end)
end

return WallService
