--!strict
--[[
	BossService
	A boss lands on the default world's plaza every EventConfig.Boss.Interval
	seconds. Everyone hits it by clicking near it (ClickService routes the
	click here, exactly like the zone targets).

	Payout: each player is paid for their SHARE of the damage
		reward = (damage / maxHp) × maxHp × RewardRatio
	so the pool is fixed no matter how many people join, and nobody can be
	paid for damage they did not do (damage is summed here, per player).
	When it dies everyone online also gets a Power boost.

	Authority: HP, damage bookkeeping and rewards are server-only. The client
	just draws the bar from "BossState".
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Logger = require(Shared.Utils.Logger)
local AssetIds = require(Shared.Config.AssetIds)
local EventConfig = require(Shared.Config.EventConfig)
local WorldConfig = require(Shared.Config.WorldConfig)
local WorldRules = require(Shared.Formulas.WorldRules)

local Signal = require(Shared.Utils.Signal)
local NetService = require(script.Parent.NetService)
local DataService = require(script.Parent.DataService)
local CurrencyService = require(script.Parent.CurrencyService)
local PowerService = require(script.Parent.PowerService)
local BoostService = require(script.Parent.BoostService)
local WorldService = require(script.Parent.WorldService)

local BOSS_SIZE = Vector3.new(16, 16, 16)
local BOSS_STANDEE = 34 -- studs tall when the artwork exists
local HIT_RANGE = 26

local log = Logger.new("Boss")

local BossService = {
	-- (player, reward, damageShare) for everyone who helped
	Defeated = Signal.new() :: Signal.Signal<Player, number, number>,
}

local model: BasePart? = nil
local worldId = WorldConfig.DefaultWorld
local maxHp = 0
local hp = 0
local endsAt = 0
local damageBy: { [Player]: number } = {}

local function broadcast()
	NetService.FireAllClients("BossState", {
		Active = model ~= nil,
		Hp = hp,
		MaxHp = maxHp,
		WorldId = worldId,
		SecondsLeft = if model then math.max(endsAt - os.clock(), 0) else 0,
	})
end

-- Everyone standing in `world` right now (the only ones who can fight there).
local function playersIn(world: string): { Player }
	local list: { Player } = {}
	for _, player in Players:GetPlayers() do
		local data = DataService.GetData(player)
		if data and data.Worlds.Current == world then
			table.insert(list, player)
		end
	end
	return list
end

--[[
	The world the next boss lands in: round-robin over the worlds that have
	someone in them, so a boss never spawns where nobody can reach it and every
	world takes its turn (which is what makes its runes obtainable).
]]
local function nextWorld(): string?
	local candidates: { Types.WorldData } = {}
	for _, world in WorldConfig.Worlds do
		if WorldRules.IsEnabled(world) and #playersIn(world.Id) > 0 then
			table.insert(candidates, world)
		end
	end
	if #candidates == 0 then
		return nil
	end
	table.sort(candidates, function(a, b)
		return a.Order < b.Order
	end)
	local previous = WorldConfig.Worlds[worldId]
	local after = if previous then previous.Order else 0
	for _, world in candidates do
		if world.Order > after then
			return world.Id
		end
	end
	return candidates[1].Id
end

local function scaledHp(world: string): number
	local total = 0
	for _, player in playersIn(world) do
		local info = PowerService.GetInfo(player)
		total += if info then info.PerClick else 0
	end
	return math.max(total * EventConfig.Boss.ClicksToKill, EventConfig.Boss.MinHp)
end

local function despawn()
	if model then
		model:Destroy()
		model = nil
	end
	table.clear(damageBy)
	hp, maxHp, endsAt = 0, 0, 0
	broadcast()
end

-- Pays every participant their share and boosts the whole server.
local function payout()
	local pool = maxHp * EventConfig.Boss.RewardRatio
	local winners = 0
	for player, damage in damageBy do
		if player.Parent and damage > 0 then
			local share = math.clamp(damage / maxHp, 0, 1)
			local reward = CurrencyService.Add(player, "Power", pool * share, "Boss")
			NetService.FireClient("Notify", player, "BossReward", { Amount = reward, Share = share })
			BossService.Defeated:Fire(player, reward, share)
			winners += 1
		end
	end
	for _, player in playersIn(worldId) do
		BoostService.Add(player, EventConfig.Boss.VictoryBoostId, EventConfig.Boss.VictoryBoostStacks, "BossVictory")
	end
	NetService.FireAllClients("Notify", "BossDefeated", { Players = winners })
	log:Info(string.format("boss defeated by %d player(s), pool=%.0f", winners, pool))
end

local function spawnBoss()
	if model or #Players:GetPlayers() == 0 then
		return
	end
	local chosen = nextWorld()
	if not chosen then
		return
	end
	worldId = chosen
	local origin = WorldService.OriginOf(worldId)
	if not origin then
		return
	end
	maxHp = scaledHp(worldId)
	hp = maxHp
	endsAt = os.clock() + EventConfig.Boss.FightSeconds
	table.clear(damageBy)

	local part = Instance.new("Part")
	part.Name = "Boss"
	part.Shape = Enum.PartType.Ball
	part.Size = BOSS_SIZE
	part.Position = origin + Vector3.new(0, EventConfig.Boss.Height, 0)
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(255, 70, 90)
	part:SetAttribute("Boss", true)
	local glow = Instance.new("PointLight")
	glow.Color = part.Color
	glow.Range = 40
	glow.Brightness = 3
	glow.Parent = part

	-- With artwork the ball becomes an invisible anchor and the boss is drawn
	-- as a standee (same approach as the zone monsters).
	local artwork = AssetIds["boss_" .. worldId]
	if artwork and artwork ~= "" then
		part.Transparency = 1
		glow.Brightness = 1.5
		local gui = Instance.new("BillboardGui")
		gui.Name = "Monster"
		gui.Size = UDim2.fromScale(BOSS_STANDEE, BOSS_STANDEE) -- studs
		gui.MaxDistance = 400
		gui.Parent = part
		local art = Instance.new("ImageLabel")
		art.BackgroundTransparency = 1
		art.Image = artwork
		art.ScaleType = Enum.ScaleType.Fit
		art.Size = UDim2.fromScale(1, 1)
		art.Parent = gui
	else
		part:SetAttribute("TODO_ASSET", true)
	end
	part.Parent = Workspace

	model = part
	broadcast()
	NetService.FireAllClients("Notify", "BossSpawned", { WorldId = worldId })
	log:Info(string.format("boss spawned in %s with %.0f hp", worldId, maxHp))
end

--[[
	Damage from one click. Returns the Power paid out right now (always 0:
	the boss pays when it dies). Called by ClickService.
]]
function BossService.OnClick(player: Player, damage: number): number
	local part = model
	if not part or damage <= 0 then
		return 0
	end
	local data = DataService.GetData(player)
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not data or data.Worlds.Current ~= worldId or not root or not root:IsA("BasePart") then
		return 0
	end
	if (root.Position - part.Position).Magnitude > HIT_RANGE then
		return 0
	end
	local applied = math.min(damage, hp)
	hp -= applied
	damageBy[player] = (damageBy[player] or 0) + applied
	if hp <= 0 then
		payout()
		despawn()
	else
		broadcast()
	end
	return 0
end

-- Debug only (AdminConfig-gated): brings the boss in right now.
function BossService.SpawnNow(): boolean
	if model then
		return false
	end
	spawnBoss()
	return model ~= nil
end

function BossService.Init()
	Players.PlayerRemoving:Connect(function(player)
		damageBy[player] = nil
	end)
end

function BossService.Start()
	task.spawn(function()
		while true do
			task.wait(EventConfig.Boss.IntervalSeconds)
			spawnBoss()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			if model then
				if os.clock() >= endsAt then
					NetService.FireAllClients("Notify", "BossEscaped", {})
					despawn()
				else
					broadcast()
				end
			end
		end
	end)
end

return BossService
