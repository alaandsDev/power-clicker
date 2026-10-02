--!strict
--[[
	WallController
	The sign on the win corridor: stage number, material name and the HP bar of
	the row you are breaking — exactly the information the server already writes
	on each row part ("Hp", "MaxHp", "Broken").

	One sign per stage: it follows the front-most row still standing, so the
	player always reads the row in front of them. When the stage is open the
	sign shows the seconds left to grab a pad.

	Nothing here decides anything: HP, the open window and the wins are
	WallService's.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local NumberFormat = require(Shared:WaitForChild("Utils"):WaitForChild("NumberFormat"))
local WallConfig = require(Shared:WaitForChild("Config"):WaitForChild("WallConfig"))
local Text = require(Shared:WaitForChild("Localization"))

local SwordConfig = require(Shared:WaitForChild("Config"):WaitForChild("SwordConfig"))

local Theme = require(script.Parent.Parent.UI.Theme)
local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local SoundController = require(script.Parent.SoundController)
local NotificationController = require(script.Parent.NotificationController)

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
-- Impacto: a fileira pisca na cor da espada quando toma dano, e racha mais
-- conforme o HP cai. Tudo local e com teto de frequência — a 9 cliques por
-- segundo, um efeito por golpe derrubaria o FPS de um celular.
local HIT_FLASH_SECONDS = 0.08
local HIT_MIN_INTERVAL = 0.09
local BREAK_PIECES = 8
local BREAK_SECONDS = 0.5

local WallController = {}

local rowsByStage: { [string]: { BasePart } } = {}
local signs: { [string]: Sign } = {}
local scanned = false
local lastHitAt: { [BasePart]: number } = {}
local lastHp: { [BasePart]: number } = {}
local debris: { BasePart } = {}
local debrisIndex = 0
local debrisFolder: Folder

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

--[[
	Rachadura progressiva: quanto menos HP, mais a fileira escurece e fica
	transparente. Não é textura de rachadura (seria um asset por material);
	é a leitura mais honesta que dá para fazer só com propriedades da peça.
]]
local function showDamage(row: BasePart, fraction: number)
	local now = os.clock()
	if now - (lastHitAt[row] or 0) < HIT_MIN_INTERVAL then
		return
	end
	lastHitAt[row] = now
	row.LocalTransparencyModifier = (1 - fraction) * 0.35
	local flash = swordColor()
	local original = row.Color
	row.Color = original:Lerp(flash, 0.5)
	task.delay(HIT_FLASH_SECONDS, function()
		if row.Parent then
			row.Color = original
		end
	end)
end

-- Estilhaços quando a fileira cai: peças locais, recicladas de um pool.
local function burst(row: BasePart)
	local colour = row.Color
	for _ = 1, BREAK_PIECES do
		debrisIndex = (debrisIndex % #debris) + 1
		local piece = debris[debrisIndex]
		piece.Color = colour
		piece.Transparency = 0.1
		piece.CFrame = row.CFrame
			* CFrame.new(
				math.random(-30, 30) / 10,
				math.random(-120, 120) / 10,
				math.random(-30, 30) / 10
			)
		local target = piece.CFrame * CFrame.new(math.random(-60, 60) / 10, math.random(-40, 20) / 10, math.random(10, 40) / 10)
		TweenService:Create(piece, TweenInfo.new(BREAK_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = target,
			Transparency = 1,
			Size = piece.Size * 0.4,
		}):Play()
	end
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
		local sign = signs[stageId]
		if not sign then
			continue
		end
		-- The row in front: the first one still standing.
		local front: BasePart? = nil
		for _, row in rows do
			local broken = row:GetAttribute("Broken") == true
			if broken then
				-- Fell since the last sweep: one burst, then forget it until
				-- the stage rebuilds.
				if lastHp[row] ~= nil then
					lastHp[row] = nil
					row.LocalTransparencyModifier = 0
					burst(row)
				end
			else
				if front == nil then
					front = row
				end
			end
		end
		if not front then
			sign.Gui.Enabled = false
			continue
		end
		sign.Gui.Enabled = true
		sign.Gui.Adornee = front

		sign.Title.Text = Text.Get("wall.stage", { order = stageOrder(stageId) })
		sign.Name.Text = stageName(stageId)
		local hp = front:GetAttribute("Hp")
		local maxHp = front:GetAttribute("MaxHp")
		if type(hp) == "number" and type(maxHp) == "number" and maxHp > 0 then
			local fraction = math.clamp(hp / maxHp, 0, 1)
			sign.BarFill.Size = UDim2.fromScale(fraction, 1)
			sign.BarFill.BackgroundColor3 = Theme.Colors.Good
			sign.BarText.Text = NumberFormat.Short(hp) .. " / " .. NumberFormat.Short(maxHp)
			-- Took damage since the last sweep: flash and crack.
			local previous = lastHp[front]
			if previous and hp < previous then
				showDamage(front, fraction)
			end
			lastHp[front] = hp
		end
	end
end

local function scan()
	if not debrisFolder then
		debrisFolder = Instance.new("Folder")
		debrisFolder.Name = "WallDebris"
		debrisFolder.Parent = Workspace.CurrentCamera or Workspace
		for index = 1, BREAK_PIECES * 2 do
			local piece = Instance.new("Part")
			piece.Name = "Debris" .. index
			piece.Size = Vector3.new(2.2, 2.2, 2.2)
			piece.Anchored = true
			piece.CanCollide = false
			piece.CanQuery = false
			piece.CanTouch = false
			piece.CastShadow = false
			piece.Transparency = 1
			piece.Parent = debrisFolder
			debris[index] = piece
		end
	end
	local map = Workspace:FindFirstChild("Map")
	local worlds = if map then map:FindFirstChild("Worlds") else nil
	local world = if worlds then worlds:FindFirstChild(WallConfig.WorldId) else nil
	if not world then
		return
	end
	table.clear(rowsByStage)
	for _, descendant in world:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:GetAttribute("Wall") == true then
			local stageId = descendant:GetAttribute("StageId")
			if type(stageId) == "string" then
				local list = rowsByStage[stageId]
				if not list then
					list = {}
					rowsByStage[stageId] = list
				end
				table.insert(list, descendant)
			end
		end
	end
	for stageId, rows in rowsByStage do
		table.sort(rows, function(a, b)
			return (a:GetAttribute("Row") or 0) < (b:GetAttribute("Row") or 0)
		end)
		if not signs[stageId] then
			signs[stageId] = createSign(stageId, rows[1])
		end
	end
	scanned = next(rowsByStage) ~= nil
end

function WallController.Init()
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
			SoundController.Play("Rebirth")
			NotificationController.Show(Text.Get("wall.opened", {
				seconds = tostring(payload.Seconds or 0),
			}), "Good")
		elseif kind == "TowerCleared" then
			SoundController.Play("Rebirth")
			NotificationController.Show(Text.Get("wall.firstClear", {
				order = tostring(payload.Order or 0),
				gems = NumberFormat.Short(tonumber(payload.Gems) or 0),
			}), "Good")
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
