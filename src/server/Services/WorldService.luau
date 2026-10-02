--!strict
--[[
	WorldService
	"UnlockWorld"(worldId) / "TravelWorld"(worldId) via WorldLogic. Teleports
	are done by the SERVER (character:PivotTo) to the world's spawn part:
		Workspace.Map.Spawns.<WorldConfig.SpawnName>
	The client never sends a position.

	Maps: for every enabled world without a model in Workspace.Map.Worlds.<Id>,
	WorldBuilder generates a themed low-poly map (ground, spawn, egg stands,
	rebirth altar, portal, decoration). A hand-made model with that name always
	takes precedence and is never touched.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Guard = require(Shared.Utils.Guard)
local Logger = require(Shared.Utils.Logger)
local Signal = require(Shared.Utils.Signal)
local WorldConfig = require(Shared.Config.WorldConfig)
local WorldRules = require(Shared.Formulas.WorldRules)

local NetService = require(script.Parent.NetService)
local DataService = require(script.Parent.DataService)
local CurrencyService = require(script.Parent.CurrencyService)
local PowerService = require(script.Parent.PowerService)
local WorldLogic = require(script.Parent.Parent.Logic.WorldLogic)
local WorldBuilder = require(script.Parent.Parent.World.WorldBuilder)

type RemoteResponse = Types.RemoteResponse
type WorldData = Types.WorldData

--[[
	Worlds are laid out far apart on the X axis (each has its own lighting/fog
	on the client). The gap has to beat two things: the fog of every ambient
	preset (so a neighbour world is never a silhouette on your horizon) and the
	win corridor, which grows east out of the starting island.
]]
local WORLD_SPACING = 8000

local log = Logger.new("Worlds")

local WorldService = {
	-- (player, worldId)
	Unlocked = Signal.new() :: Signal.Signal<Player, string>,
	Traveled = Signal.new() :: Signal.Signal<Player, string>,
}

local function getMapFolder(name: string): Folder
	local map = workspace:FindFirstChild("Map")
	if not map then
		local created = Instance.new("Folder")
		created.Name = "Map"
		created.Parent = workspace
		map = created
	end
	local folder = (map :: Instance):FindFirstChild(name)
	if not folder then
		local created = Instance.new("Folder")
		created.Name = name
		created.Parent = map
		folder = created
	end
	return folder :: Folder
end

-- Builds the world map with WorldBuilder unless a hand-made model already
-- exists in Workspace.Map.Worlds.<Id> (hand-made maps always win).
local function ensureMap(world: WorldData)
	local worlds = getMapFolder("Worlds")
	local spawns = getMapFolder("Spawns")
	if worlds:FindFirstChild(world.Id) then
		return
	end
	local staleSpawn = spawns:FindFirstChild(world.SpawnName)
	if staleSpawn then
		log:Warn("Spawn exists without a map for", world.Id, "- rebuilding both")
		staleSpawn:Destroy()
	end
	local origin = WorldService.OriginOf(world.Id) or Vector3.zero
	WorldBuilder.Build(world, origin, worlds, spawns, world.Id == WorldConfig.DefaultWorld)
end

-- Worlds sit side by side on +X; zones and targets are placed from here.
function WorldService.OriginOf(worldId: string): Vector3?
	local world = WorldConfig.Worlds[worldId]
	return if world then Vector3.new((world.Order - 1) * WORLD_SPACING, 0, 0) else nil
end

local function spawnCFrame(worldId: string): CFrame?
	local world = WorldConfig.Worlds[worldId]
	if not world then
		return nil
	end
	local spawn = getMapFolder("Spawns"):FindFirstChild(world.SpawnName)
	if spawn and spawn:IsA("BasePart") then
		return spawn.CFrame + Vector3.new(0, 3, 0)
	end
	return nil
end

-- Puts the player back on their world's spawn pad (locked zone, stuck, ...).
function WorldService.SendToSpawn(player: Player)
	local data = DataService.GetData(player)
	local character = player.Character
	local target = if data then spawnCFrame(data.Worlds.Current) else nil
	if character and target then
		character:PivotTo(target)
	end
end

local function moveToCurrentWorld(player: Player)
	local data = DataService.GetData(player)
	local character = player.Character
	if not data or not character then
		return
	end
	local target = spawnCFrame(data.Worlds.Current)
	if target then
		character:PivotTo(target)
	end
end

local function unlock(player: Player, worldId: string): RemoteResponse
	local data = DataService.GetData(player)
	if not data then
		return { Ok = false, Code = "NotReady" }
	end
	local world = WorldConfig.Worlds[worldId]
	local ok, code = WorldLogic.Unlock(data, worldId)
	if not ok or not world then
		return { Ok = false, Code = code }
	end
	DataService.MarkChanged(player, "Worlds")
	if world.Requirement.Cost > 0 then
		CurrencyService.NotifyChanged(player, world.Requirement.Currency, -world.Requirement.Cost, "World:" .. worldId)
	end
	log:Info(string.format("user=%d unlocked %s", player.UserId, worldId))
	WorldService.Unlocked:Fire(player, worldId)
	return { Ok = true }
end

local function travel(player: Player, worldId: string): RemoteResponse
	local data = DataService.GetData(player)
	if not data then
		return { Ok = false, Code = "NotReady" }
	end
	local ok, code = WorldLogic.Travel(data, worldId)
	if not ok then
		return { Ok = false, Code = code }
	end
	DataService.MarkChanged(player, "Worlds")
	PowerService.Invalidate(player) -- world multiplier changed
	moveToCurrentWorld(player)
	WorldService.Traveled:Fire(player, worldId)
	return { Ok = true }
end

function WorldService.Init()
	local worldIds: { [string]: boolean } = {}
	for id in WorldConfig.Worlds do
		worldIds[id] = true
	end
	NetService.OnInvoke("UnlockWorld", Guard.Args(Guard.KeyOf(worldIds)), unlock)
	NetService.OnInvoke("TravelWorld", Guard.Args(Guard.KeyOf(worldIds)), travel)

	DataService.PlayerLoaded:Connect(function(player, data)
		if WorldLogic.Sanitize(data) then
			log:Info(string.format("user=%d world state repaired (current=%s)", player.UserId, data.Worlds.Current))
		end
	end)
	--[[
		Mundo dormente no save: quem parou de jogar dentro da Cidade (antes de a
		torre virar a progressão) voltaria para um mapa que não é mais
		construído — ou seja, cairia no vazio. O save é corrigido na carga.
	]]
	DataService.PlayerLoaded:Connect(function(player: Player, data)
		local current = WorldConfig.Worlds[data.Worlds.Current]
		if not current or not WorldRules.IsEnabled(current) then
			log:Warn(string.format("user=%d was in dormant world %s; moved home", player.UserId, tostring(data.Worlds.Current)))
			data.Worlds.Current = WorldConfig.DefaultWorld
			data.Worlds.Unlocked[WorldConfig.DefaultWorld] = true
			DataService.MarkChanged(player, "Worlds")
		end
	end)

	-- Place the character in its saved world once data is ready, and on every respawn.
	DataService.PlayerReady:Connect(moveToCurrentWorld)
	DataService.DataReset:Connect(moveToCurrentWorld)
end

function WorldService.Start()
	for _, world in WorldRules.Ordered() do
		if WorldRules.IsEnabled(world) then
			ensureMap(world)
		end
	end

	local function hookCharacter(player: Player)
		player.CharacterAdded:Connect(function()
			task.defer(moveToCurrentWorld, player)
		end)
	end
	Players.PlayerAdded:Connect(hookCharacter)
	for _, player in Players:GetPlayers() do
		hookCharacter(player)
	end
end

return WorldService
