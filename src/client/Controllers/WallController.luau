--!strict
--[[
	WallController
	As barreiras do Caminho do Poder COMO ELAS SÃO PARA ESTE JOGADOR. Cada
	jogador tem o próprio caminho: o servidor (WallService) guarda o HP de cada
	fileira por jogador e manda a este cliente só o estado dele (WallState).

	As peças das fileiras no Workspace são compartilhadas e ficam sempre
	inteiras e sólidas no servidor. Aqui, e só neste cliente, a fileira que
	ESTE jogador quebrou some e deixa de colidir (propriedades locais, que não
	replicam): a física do personagem roda no cliente dono dele, então ele
	atravessa e os outros continuam batendo na fileira inteira. Se a peça sair
	e voltar pelo streaming, o estado é aplicado de novo.

	Também desenha a placa de cada estágio (número, material e barra de HP da
	fileira da frente), o flash/rachadura dos golpes, os estilhaços e o aviso
	"BARREIRA N DESTRUÍDA!".

	Nada aqui decide nada: HP, abertura, janela e vitórias são do WallService,
	que também confere a posição de quem tenta atravessar sem ter quebrado.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local NumberFormat = require(Shared:WaitForChild("Utils"):WaitForChild("NumberFormat"))
local Signal = require(Shared:WaitForChild("Utils"):WaitForChild("Signal"))
local WallConfig = require(Shared:WaitForChild("Config"):WaitForChild("WallConfig"))
local WinPadRules = require(Shared:WaitForChild("Formulas"):WaitForChild("WinPadRules"))
local Text = require(Shared:WaitForChild("Localization"))

local SwordConfig = require(Shared:WaitForChild("Config"):WaitForChild("SwordConfig"))

local Theme = require(script.Parent.Parent.UI.Theme)
local Build = require(script.Parent.Parent.UI.Build)
local Anim = require(script.Parent.Parent.UI.Anim)
local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local SoundController = require(script.Parent.SoundController)
local NotificationController = require(script.Parent.NotificationController)
local HudController = require(script.Parent.HudController)
local DataController = require(script.Parent.DataController)

type Sign = {
	Gui: BillboardGui,
	Title: TextLabel,
	Name: TextLabel,
	BarFill: Frame,
	BarText: TextLabel,
}

-- Studs: the sign shrinks with distance like every other world sign.
local SIGN_WIDTH = 30
local SIGN_HEIGHT = 12
-- Clear of the block: the part's centre is half its height off the floor, so
-- anything less than that keeps the sign INSIDE the stone.
local SIGN_OFFSET = WallConfig.Layout.WallHeight / 2 + SIGN_HEIGHT / 2 + 2
local SCAN_RETRY_SECONDS = 1
-- A superfície da fileira pisca quando toma dano (com teto de frequência). O
-- resto do impacto, as rachaduras e a quebra são do CombatFxController, que
-- escuta os sinais abaixo.
local HIT_FLASH_SECONDS = 0.08
local HIT_MIN_INTERVAL = 0.09
-- Anúncio "BARREIRA N DESTRUÍDA!": curto, no topo, não bloqueia nada.
local BANNER_SECONDS = 2.6

local WallController = {
	-- Eventos das fileiras DESTE jogador (vindos do WallState próprio):
	-- (row, stageId, hpAntes, hpDepois) quando toma dano e continua de pé.
	RowDamaged = Signal.new() :: Signal.Signal<BasePart, string, number, number>,
	-- (row, stageId, final) quando cai; final = era a última fileira de pé.
	RowBroken = Signal.new() :: Signal.Signal<BasePart, string, boolean>,
	-- (row, stageId) quando volta inteira (a barreira se refez).
	RowRestored = Signal.new() :: Signal.Signal<BasePart, string>,
}

export type StageView = { Hp: { number }, Open: boolean }

-- rowsByStage[stageId][row] = peça (substituída se o streaming trocar a peça).
local rowsByStage: { [string]: { [number]: BasePart } } = {}
-- O estado deste jogador (WallState). Estágio sem entrada = inteiro.
local views: { [string]: StageView } = {}
local signs: { [string]: Sign } = {}
local scanned = false
local lastHitAt: { [BasePart]: number } = {}
local banner: TextLabel
local bannerStamp = 0
local objectiveChip: TextLabel
-- Pads de vitória (placa reescrita com o valor deste jogador) e, por estágio,
-- até quando vale a "primeira conquista" que acabou de acontecer.
local winPads: { BasePart } = {}
local firstClearUntil: { [string]: number } = {}

local function stageOrder(stageId: string): number
	for _, stage in WallConfig.Stages do
		if stage.Id == stageId then
			return stage.Order
		end
	end
	return 0
end

local function stageName(stageId: string): string
	local key = "wall." .. stageId .. ".name"
	local value = Text.Get(key)
	if value ~= key then
		return value
	end
	for _, stage in WallConfig.Stages do
		if stage.Id == stageId then
			return stage.DisplayName
		end
	end
	return stageId
end

local function swordColor(): Color3
	local swordId = Players.LocalPlayer:GetAttribute("EquippedSword")
	local sword = if type(swordId) == "string" then SwordConfig.Swords[swordId] else nil
	return if sword then sword.ArcColor else Color3.new(1, 1, 1)
end

local function stageOfId(stageId: any): WallConfig.WallStage?
	for _, stage in WallConfig.Stages do
		if stage.Id == stageId then
			return stage
		end
	end
	return nil
end

--[[
	(hp, maxHp, quebrada) da fileira PARA ESTE JOGADOR. Sem estado recebido,
	a fileira está inteira.
]]
function WallController.RowState(row: BasePart): (number, number, boolean)
	local stageId = row:GetAttribute("StageId")
	local index = row:GetAttribute("Row")
	local stage = stageOfId(stageId)
	local maxHp = if stage then stage.Hp else (tonumber(row:GetAttribute("MaxHp")) or 0)
	local view = if type(stageId) == "string" then views[stageId] else nil
	local hp = if view and type(index) == "number" then view.Hp[index] else nil
	if type(hp) ~= "number" then
		hp = maxHp
	end
	return hp :: number, maxHp, (hp :: number) <= 0
end

-- As fileiras do corredor, por estágio e número (para a faixa do corredor).
function WallController.Rows(): { [string]: { [number]: BasePart } }
	return rowsByStage
end

--[[
	Aparência e colisão LOCAIS da fileira: quebrada para este jogador = some,
	sem colisão, sem luz, detalhes escondidos. Só mexe quando difere, então
	pode rodar a cada quadro (e reaplica se o streaming trouxer a peça de novo).
]]
local function applyRow(row: BasePart, broken: boolean)
	local wantCollide = not broken
	local wantTransparency = if broken then 1 else 0
	if row.CanCollide == wantCollide and row.Transparency == wantTransparency then
		return
	end
	row.CanCollide = wantCollide
	row.Transparency = wantTransparency
	if not broken then
		row.LocalTransparencyModifier = 0
	end
	for _, child in row:GetChildren() do
		if child:IsA("BasePart") and child:GetAttribute("WallDetail") == true then
			local base = child:GetAttribute("BaseTransparency")
			child.Transparency = if broken then 1 else (if type(base) == "number" then base else 0)
		elseif child:IsA("Light") then
			child.Enabled = not broken
		end
	end
end

--[[
	O ponto da face da fileira em que um golpe de quem está em `position` bate
	(a face voltada para a praça, na altura do peito, alinhado ao jogador).
]]
function WallController.ContactPoint(row: BasePart, position: Vector3): Vector3
	local half = row.Size / 2
	return Vector3.new(
		row.Position.X - half.X - 0.3,
		math.clamp(position.Y + 1, row.Position.Y - half.Y + 1, row.Position.Y + half.Y - 1),
		math.clamp(position.Z, row.Position.Z - half.Z + 1, row.Position.Z + half.Z - 1)
	)
end

--[[
	A fileira que um golpe de quem está em `position` acerta AGORA, pela mesma
	regra do servidor: de pé para este jogador, À FRENTE dele e a até
	WallConfig.HitRange. Só para o efeito do impacto sair junto com o golpe; o
	dano de verdade continua sendo decidido no servidor.
]]
function WallController.TargetRow(position: Vector3): BasePart?
	local best: BasePart? = nil
	local bestDistance = WallConfig.HitRange
	for _, rows in rowsByStage do
		for _, row in rows do
			if row.Parent and position.X < row.Position.X then
				local _, _, broken = WallController.RowState(row)
				local distance = (row.Position - position).Magnitude
				if not broken and distance <= bestDistance then
					best, bestDistance = row, distance
				end
			end
		end
	end
	return best
end

-- A superfície reage ao dano: um flash curto na cor da espada (cosmético).
local function flashSurface(row: BasePart)
	local now = os.clock()
	if now - (lastHitAt[row] or 0) < HIT_MIN_INTERVAL then
		return
	end
	lastHitAt[row] = now
	local flash = swordColor()
	local original = row.Color
	row.Color = original:Lerp(flash, 0.5)
	task.delay(HIT_FLASH_SECONDS, function()
		if row.Parent then
			row.Color = original
		end
	end)
end

local function createSign(stageId: string, row: BasePart): Sign
	local gui = Instance.new("BillboardGui")
	gui.Name = "WallSign"
	gui.Size = UDim2.fromScale(SIGN_WIDTH, SIGN_HEIGHT)
	gui.StudsOffset = Vector3.new(0, SIGN_OFFSET, 0)
	gui.MaxDistance = 320
	-- The rows behind it would swallow the sign otherwise.
	gui.AlwaysOnTop = true
	gui.Adornee = row
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Font = Theme.FontDisplay
	title.TextScaled = true
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextStrokeTransparency = 0.2
	title.Size = UDim2.fromScale(1, 0.3)
	title.Parent = gui

	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Font = Theme.FontDisplay
	name.TextScaled = true
	name.TextColor3 = Color3.new(1, 1, 1)
	name.TextStrokeTransparency = 0.2
	name.Position = UDim2.fromScale(0, 0.32)
	name.Size = UDim2.fromScale(1, 0.3)
	name.Parent = gui

	local bar = Instance.new("Frame")
	bar.BackgroundColor3 = Color3.fromRGB(28, 30, 44)
	bar.BorderSizePixel = 0
	bar.Position = UDim2.fromScale(0.1, 0.68)
	bar.Size = UDim2.fromScale(0.8, 0.26)
	bar.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.4, 0)
	corner.Parent = bar

	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = Theme.Colors.Good
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(1, 1)
	fill.Parent = bar
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.4, 0)
	fillCorner.Parent = fill

	local barText = Instance.new("TextLabel")
	barText.BackgroundTransparency = 1
	barText.Font = Theme.FontDisplay
	barText.TextScaled = true
	barText.TextColor3 = Color3.new(1, 1, 1)
	barText.TextStrokeTransparency = 0.3
	barText.Size = UDim2.fromScale(1, 1)
	barText.ZIndex = 2
	barText.Parent = bar

	return { Gui = gui, Title = title, Name = name, BarFill = fill, BarText = barText }
end

local function refresh()
	for stageId, rows in rowsByStage do
		-- Colisão/aparência locais de cada fileira, conforme o estado DESTE jogador.
		local front: BasePart? = nil
		local stage = stageOfId(stageId)
		local count = if stage then stage.Rows else #rows
		for index = 1, count do
			local row = rows[index]
			if row and row.Parent then
				local _, _, broken = WallController.RowState(row)
				applyRow(row, broken)
				if not broken and front == nil then
					front = row
				end
			end
		end
		local sign = signs[stageId]
		if not sign then
			continue
		end
		if not front then
			sign.Gui.Enabled = false
			continue
		end
		sign.Gui.Enabled = true
		sign.Gui.Adornee = front

		sign.Title.Text = Text.Get("wall.stage", { order = stageOrder(stageId) })
		sign.Name.Text = stageName(stageId)
		local hp, maxHp = WallController.RowState(front :: BasePart)
		if maxHp > 0 then
			local fraction = math.clamp(hp / maxHp, 0, 1)
			sign.BarFill.Size = UDim2.fromScale(fraction, 1)
			sign.BarFill.BackgroundColor3 = Theme.Colors.Good
			sign.BarText.Text = NumberFormat.Short(hp) .. " / " .. NumberFormat.Short(maxHp)
		end
	end
end

--[[
	Novo estado DESTE jogador vindo do servidor: golpe na fileira (flash e
	rachadura), fileira caindo (estilhaços) e barreira se refazendo.
]]
local function onWallState(payload: any)
	if type(payload) ~= "table" then
		return
	end
	for stageId, incoming in payload do
		if type(stageId) ~= "string" or type(incoming) ~= "table" or type(incoming.Hp) ~= "table" then
			continue
		end
		local stage = stageOfId(stageId)
		local previous = views[stageId]
		local rows = rowsByStage[stageId] or {}
		for index, hp in incoming.Hp do
			local before = if previous then previous.Hp[index] else (if stage then stage.Hp else hp)
			local row = rows[index]
			if row and type(hp) == "number" and type(before) == "number" then
				if hp <= 0 and before > 0 then
					row.LocalTransparencyModifier = 0
					SoundController.Play("WallBreak")
					local standing = 0
					for _, other in incoming.Hp do
						if type(other) == "number" and other > 0 then
							standing += 1
						end
					end
					WallController.RowBroken:Fire(row, stageId, standing == 0)
				elseif hp > 0 and hp < before and stage then
					flashSurface(row)
					WallController.RowDamaged:Fire(row, stageId, before, hp)
				elseif hp > before then
					row.LocalTransparencyModifier = 0
					WallController.RowRestored:Fire(row, stageId)
				end
			end
		end
		views[stageId] = { Hp = table.clone(incoming.Hp), Open = incoming.Open == true }
	end
	refresh()
end

local function addRow(descendant: Instance)
	if not descendant:IsA("BasePart") or descendant:GetAttribute("Wall") ~= true then
		return
	end
	local stageId = descendant:GetAttribute("StageId")
	local index = descendant:GetAttribute("Row")
	if type(stageId) ~= "string" or type(index) ~= "number" then
		return
	end
	local list = rowsByStage[stageId]
	if not list then
		list = {}
		rowsByStage[stageId] = list
	end
	list[index] = descendant
end

local function scan()
	local map = Workspace:FindFirstChild("Map")
	local worlds = if map then map:FindFirstChild("Worlds") else nil
	local world = if worlds then worlds:FindFirstChild(WallConfig.WorldId) else nil
	if not world then
		return
	end
	table.clear(rowsByStage)
	table.clear(winPads)
	for _, descendant in world:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:GetAttribute("WinPad") == true and descendant:GetAttribute("Return") ~= true then
			table.insert(winPads, descendant)
		end
		addRow(descendant)
	end
	for stageId, rows in rowsByStage do
		if not signs[stageId] and rows[1] then
			signs[stageId] = createSign(stageId, rows[1])
		end
	end
	scanned = next(rowsByStage) ~= nil
	if scanned then
		-- Streaming: uma fileira que volta é uma peça nova; ela entra no lugar
		-- da antiga e o próximo quadro aplica o estado deste jogador nela.
		world.DescendantAdded:Connect(addRow)
	end
end

--[[
	"BARREIRA N DESTRUÍDA!" para quem quebrou: estágio, gemas da primeira vez
	e para onde ir agora. Some sozinho em poucos segundos.
]]
local function showDestroyed(payload: any)
	local order = tonumber(payload.Order) or stageOrder(tostring(payload.StageId))
	local lines = { Text.Get("wall.destroyed", { order = tostring(order) }) }
	local gems = tonumber(payload.FirstClearGems) or 0
	if gems > 0 then
		table.insert(lines, Text.Get("wall.destroyedGems", { gems = NumberFormat.Short(gems), icon = Theme.Icons.Gems }))
	end
	local nextStage = WallConfig.Stages[order + 1]
	if nextStage then
		table.insert(lines, Text.Get("wall.destroyedNext", { next = tostring(nextStage.Order), name = stageName(nextStage.Id) }))
	else
		table.insert(lines, Text.Get("wall.destroyedLast"))
	end
	banner.Text = table.concat(lines, "\n")
	banner.Size = UDim2.fromOffset(470, 30 + 22 * (#lines - 1))
	banner.Visible = true
	Anim.PopIn(banner, 0.6, 0.3)
	SoundController.Play("Reward")
	bannerStamp += 1
	local stamp = bannerStamp
	task.delay(BANNER_SECONDS, function()
		if bannerStamp == stamp then
			banner.Visible = false
		end
	end)
end

local function stageOf(stageId: any): WallConfig.WallStage?
	for _, stage in WallConfig.Stages do
		if stage.Id == stageId then
			return stage
		end
	end
	return nil
end

--[[
	A placa de cada pad mostra o que ESTE jogador recebe se pisar nele agora
	(WinPadRules — a mesma conta do servidor): valor cheio na abertura da
	primeira conquista, fração de repetição depois. O pad x2 é sempre o dobro.
]]
local function refreshPads()
	local tower = DataController.Get("Tower")
	for _, pad in winPads do
		local stage = stageOf(pad:GetAttribute("StageId"))
		local gui = pad:FindFirstChildOfClass("BillboardGui")
		local label = if gui then gui:FindFirstChildOfClass("TextLabel") else nil
		if stage and label then
			local index = tonumber(pad:GetAttribute("PadIndex")) or WinPadRules.IndexOf(stage, tonumber(pad:GetAttribute("Wins")) or 0) or 1
			local firstClear = (firstClearUntil[stage.Id] or 0) > os.clock()
			local amount = WinPadRules.Payout(stage, index, WinPadRules.Share(stage, tower, firstClear))
			label.Text = Text.Get(if WinPadRules.IsDouble(stage, index) then "wall.padWinsDouble" else "wall.padWins", { amount = NumberFormat.Short(amount) })
		end
	end
end

-- Objetivo até a primeira barreira cair: só no lobby (perto da barreira, a
-- faixa do corredor assume) e some de vez depois do primeiro estágio.
local function refreshObjective()
	local tower = DataController.Get("Tower")
	local highest = if type(tower) == "table" then tonumber(tower.Highest) or 0 else 0
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local inLobby = root ~= nil and root:IsA("BasePart") and root.Position.X < WallConfig.Layout.StartX + 40
	objectiveChip.Visible = DataController.IsLoaded() and highest < 1 and inLobby
end

function WallController.Init()
	banner = Build.label({
		Name = "WallBanner",
		Text = "",
		Font = Theme.FontDisplay,
		TextSize = 20,
		TextWrapped = true,
		TextColor3 = Theme.Colors.Power,
		BackgroundColor3 = Theme.Hud.Surface,
		BackgroundTransparency = 0.15,
		Size = UDim2.fromOffset(470, 30),
		Visible = false,
		ZIndex = 25,
		LayoutOrder = 1,
		Parent = HudController.GetTopStack(),
	})
	Build.corner(banner, UDim.new(0, 12))
	Build.textStroke(banner, 2)
	objectiveChip = Build.label({
		Name = "ObjectiveChip",
		Text = Text.Get("objective.firstBarrier"),
		TextSize = 16,
		BackgroundColor3 = Theme.Hud.Surface,
		BackgroundTransparency = 0.25,
		Size = UDim2.fromOffset(0, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		Visible = false,
		LayoutOrder = 6,
		Parent = HudController.GetTopStack(),
	})
	Build.corner(objectiveChip, UDim.new(1, 0))
	Build.new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), Parent = objectiveChip })
	task.spawn(function()
		while true do
			refreshObjective()
			refreshPads()
			task.wait(0.5)
		end
	end)

	ClientNet.On("WallState", onWallState)
	ClientNet.On("Notify", function(kind: any, payload: any)
		if type(payload) ~= "table" then
			return
		end
		if kind == "WinPad" then
			SoundController.Play("Reward")
			NotificationController.Show(Text.Get("wall.gotWins", {
				amount = NumberFormat.Short(tonumber(payload.Wins) or 0),
				icon = Theme.Icons.Wins,
			}), "Good")
		elseif kind == "WallBroken" then
			-- Só chega para quem quebrou: a barreira dos outros continua inteira.
			if payload.ById == Players.LocalPlayer.UserId then
				if payload.FirstClear == true and type(payload.StageId) == "string" then
					firstClearUntil[payload.StageId] = os.clock() + (tonumber(payload.Seconds) or WallConfig.OpenSeconds)
				end
				refreshPads()
				showDestroyed(payload)
			end
		elseif kind == "TowerCleared" then
			-- As gemas da primeira vez entram no anúncio grande (WallBroken traz
			-- FirstClearGems); aqui só o som.
			SoundController.Play("Rebirth")
		elseif kind == "WallRow" then
			NotificationController.Show(Text.Get("wall.rowsLeft", {
				count = tostring(payload.Remaining or 0),
			}), "Info")
		end
	end)
end

function WallController.Start()
	task.spawn(function()
		while not scanned do
			scan()
			if not scanned then
				task.wait(SCAN_RETRY_SECONDS)
			end
		end
		-- Attributes change often while a wall is being broken; one cheap sweep
		-- per heartbeat is simpler (and lighter) than a listener per row.
		RunService.Heartbeat:Connect(refresh)
	end)
end

return WallController
