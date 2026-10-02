--!strict
--[[
	PickupService
	Power orbs that appear around each populated world and pay the first player
	who walks into them.

	Authority: the orb part lives on the server and its value is computed here
	from the toucher's own Power per click (EventConfig.Pickup.ClicksWorth), so
	a client can neither pick a value nor claim an orb it did not touch.
	Each orb is claimed once (Claimed flag) and then removed.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Logger = require(Shared.Utils.Logger)
local EventConfig = require(Shared.Config.EventConfig)
local WorldConfig = require(Shared.Config.WorldConfig)
local WorldRules = require(Shared.Formulas.WorldRules)

local NetService = require(script.Parent.NetService)
local DataService = require(script.Parent.DataService)
local CurrencyService = require(script.Parent.CurrencyService)
local PowerService = require(script.Parent.PowerService)
local WorldService = require(script.Parent.WorldService)

local ORB_SIZE = 4.5
local ORB_HEIGHT = 4

local log = Logger.new("Pickups")

local PickupService = {}

local folder: Folder
local alive = 0
local random = Random.new()

local function playersIn(worldId: string): { Player }
	local list: { Player } = {}
	for _, player in Players:GetPlayers() do
		local data = DataService.GetData(player)
		if data and data.Worlds.Current == worldId then
			table.insert(list, player)
		end
	end
	return list
end

local function valueFor(player: Player): number
	local info = PowerService.GetInfo(player)
	local perClick = if info then info.PerClick else 0
	return math.max(perClick * EventConfig.Pickup.ClicksWorth, EventConfig.Pickup.MinValue)
end

local function claim(orb: BasePart, player: Player)
	if orb:GetAttribute("Claimed") == true then
		return
	end
	orb:SetAttribute("Claimed", true)
	local amount = CurrencyService.Add(player, "Power", valueFor(player), "Pickup")
	NetService.FireClient("Notify", player, "PickupClaimed", { Amount = amount, Position = orb.Position })
	orb:Destroy()
	alive -= 1
end

local function spawnOrb(worldId: string)
	local origin = WorldService.OriginOf(worldId)
	if not origin then
		return
	end
	local config = EventConfig.Pickup
	local angle = random:NextNumber(0, math.pi * 2)
	local radius = random:NextNumber(20, config.SpawnRadius)
	local position = origin + Vector3.new(math.cos(angle) * radius, ORB_HEIGHT, math.sin(angle) * radius)

	local orb = Instance.new("Part")
	orb.Name = "PowerOrb"
	orb.Shape = Enum.PartType.Ball
	orb.Size = Vector3.new(ORB_SIZE, ORB_SIZE, ORB_SIZE)
	orb.Position = position
	orb.Anchored = true
	orb.CanCollide = false
	orb.Material = Enum.Material.Neon
	orb.Color = Color3.fromRGB(255, 196, 45)
	orb:SetAttribute("Pickup", true)
	orb:SetAttribute("TODO_ASSET", true)

	local glow = Instance.new("PointLight")
	glow.Color = orb.Color
	glow.Range = 14
	glow.Brightness = 2
	glow.Parent = orb

	local lastTouch = 0
	orb.Touched:Connect(function(hit: BasePart)
		local now = os.clock()
		if now - lastTouch < config.TouchCooldownSeconds then
			return
		end
		lastTouch = now
		local character = hit.Parent
		local player = if character then Players:GetPlayerFromCharacter(character) else nil
		if player then
			claim(orb, player)
		end
	end)

	orb.Parent = folder
	alive += 1
	task.delay(config.LifetimeSeconds, function()
		if orb.Parent then
			orb:Destroy()
			alive -= 1
		end
	end)
end

-- Debug only (AdminConfig-gated): drops one orb in the player's world.
function PickupService.SpawnNow(player: Player): boolean
	local data = DataService.GetData(player)
	if not data then
		return false
	end
	spawnOrb(data.Worlds.Current)
	return true
end

function PickupService.Init()
	folder = Instance.new("Folder")
	folder.Name = "Pickups"
	folder.Parent = Workspace
end

function PickupService.Start()
	task.spawn(function()
		while true do
			task.wait(EventConfig.Pickup.IntervalSeconds)
			if alive < EventConfig.Pickup.MaxAlive then
				for worldId, world in WorldConfig.Worlds do
					if WorldRules.IsEnabled(world) and #playersIn(worldId) > 0 then
						spawnOrb(worldId)
					end
				end
			end
		end
	end)
	log:Info("Power orbs every", EventConfig.Pickup.IntervalSeconds, "s")
end

return PickupService
