--!strict
--[[
	NetService
	The ONLY place that creates remotes and connects to OnServerEvent /
	OnServerInvoke. Every client request goes through this pipeline:

		1. Remote direction check   (ServerToClient remotes fired by a client → report + drop)
		2. Per-player rate limit     (token bucket from RemoteDefinitions → report + drop)
		3. Data-ready check          (RequiresData remotes before data loads → drop)
		4. Argument validation       (Guard validators, extra args rejected → report + drop)
		5. Handler                   (xpcall; errors logged, never sent to the client)

	Handlers receive already-validated arguments. Handlers must still validate
	STATE (ownership, funds, cooldowns) — that is the owning service's job.

	Usage (from a service's Init):
		NetService.On("OpenEgg", Guard.Args(Guard.KeyOf(Eggs)), function(player, eggId) ... end)
		NetService.OnInvoke("BuyUpgrade", validator, function(player, id) return { Ok = true } end)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Logger = require(Shared.Utils.Logger)
local RateLimiter = require(Shared.Utils.RateLimiter)
local Try = require(Shared.Utils.Try)
local RemoteDefinitions = require(Shared.Net.RemoteDefinitions)
local AntiExploitService = require(script.Parent.AntiExploitService)

type RemoteSpec = Types.RemoteSpec
type RemoteResponse = Types.RemoteResponse
type Validator = (...any) -> boolean

local log = Logger.new("Net")

local NetService = {}

local folder: Folder? = nil
local events: { [string]: RemoteEvent } = {}
local functions: { [string]: RemoteFunction } = {}
local limiters: { [string]: RateLimiter.RateLimiter } = {}
local handled: { [string]: boolean } = {}

-- Injected by DataService to avoid a circular require.
local isPlayerReady: (Player) -> boolean = function()
	return false
end

local function getSpec(name: string): RemoteSpec
	local spec = RemoteDefinitions.Remotes[name]
	assert(spec, "Unknown remote: " .. name)
	return spec
end

-- Shared gatekeeping for both events and functions. Returns an error code or nil.
local function gate(name: string, spec: RemoteSpec, validator: Validator, player: Player, ...: any): string?
	local limiter = limiters[name]
	if limiter and not limiter:Consume(player) then
		AntiExploitService.Report(player, "RateLimited", name)
		return "RateLimited"
	end
	if spec.RequiresData ~= false and not isPlayerReady(player) then
		return "NotReady"
	end
	if not validator(...) then
		AntiExploitService.Report(player, "InvalidArguments", name)
		return "InvalidRequest"
	end
	return nil
end

function NetService.SetReadyPredicate(predicate: (Player) -> boolean)
	isPlayerReady = predicate
end

-- Register a handler for a ClientToServer RemoteEvent.
function NetService.On(name: string, validator: Validator, handler: (Player, ...any) -> ())
	local spec = getSpec(name)
	assert(spec.Kind == "Event" and spec.Direction == "ClientToServer", name .. " is not a ClientToServer event")
	assert(not handled[name], name .. " already has a handler")
	handled[name] = true

	events[name].OnServerEvent:Connect(function(player: Player, ...: any)
		if gate(name, spec, validator, player, ...) then
			return
		end
		local ok, err = Try.Call(handler, player, ...)
		if not ok then
			log:Error("Handler error in", name, "user=" .. player.UserId, err)
		end
	end)
end

-- Register a handler for a ClientToServer RemoteFunction.
function NetService.OnInvoke(name: string, validator: Validator, handler: (Player, ...any) -> RemoteResponse)
	local spec = getSpec(name)
	assert(spec.Kind == "Function" and spec.Direction == "ClientToServer", name .. " is not a ClientToServer function")
	assert(not handled[name], name .. " already has a handler")
	handled[name] = true

	functions[name].OnServerInvoke = function(player: Player, ...: any): RemoteResponse
		local code = gate(name, spec, validator, player, ...)
		if code then
			return { Ok = false, Code = code }
		end
		local args = table.pack(...)
		local response: RemoteResponse? = nil
		local ok, err = Try.Call(function()
			response = handler(player, table.unpack(args, 1, args.n))
		end)
		if not ok or response == nil then
			log:Error("Handler error in", name, "user=" .. player.UserId, err or "handler returned nil")
			return { Ok = false, Code = "ServerError" }
		end
		return response
	end
end

function NetService.FireClient(name: string, player: Player, ...: any)
	local spec = getSpec(name)
	assert(spec.Direction == "ServerToClient", name .. " is not ServerToClient")
	if player.Parent == Players then
		events[name]:FireClient(player, ...)
	end
end

function NetService.FireAllClients(name: string, ...: any)
	local spec = getSpec(name)
	assert(spec.Direction == "ServerToClient", name .. " is not ServerToClient")
	events[name]:FireAllClients(...)
end

function NetService.Init()
	-- Remotes must only ever be created by this service. Anything already
	-- present (e.g. inserted into the place by a plugin/free model) is removed.
	local existing = ReplicatedStorage:FindFirstChild(RemoteDefinitions.FolderName)
	if existing then
		log:Warn("Removing pre-existing", RemoteDefinitions.FolderName, "folder; remotes are created at runtime only")
		existing:Destroy()
	end

	local newFolder = Instance.new("Folder")
	newFolder.Name = RemoteDefinitions.FolderName

	for name, spec in RemoteDefinitions.Remotes do
		if spec.Kind == "Function" and spec.Direction == "ServerToClient" then
			-- Server→client invokes can hang the server thread forever. Not allowed.
			error("RemoteFunction " .. name .. " cannot be ServerToClient")
		end

		if spec.Kind == "Event" then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = newFolder
			events[name] = remote
		else
			local remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = newFolder
			functions[name] = remote
		end

		if spec.Direction == "ClientToServer" then
			local limit = spec.RateLimit
			assert(limit, "ClientToServer remote " .. name .. " has no RateLimit")
			limiters[name] = RateLimiter.new(limit.Capacity, limit.RefillPerSecond)
		elseif spec.Kind == "Event" then
			-- A client firing a ServerToClient event is never legitimate.
			events[name].OnServerEvent:Connect(function(player: Player)
				AntiExploitService.Report(player, "WrongDirection", name)
			end)
		end
	end

	newFolder.Parent = ReplicatedStorage
	folder = newFolder

	Players.PlayerRemoving:Connect(function(player)
		for _, limiter in limiters do
			limiter:Remove(player)
		end
	end)
end

function NetService.Start()
	for name, spec in RemoteDefinitions.Remotes do
		if spec.Direction == "ClientToServer" and not handled[name] then
			log:Warn("ClientToServer remote has no handler (requests are ignored):", name)
			if spec.Kind == "Event" then
				events[name].OnServerEvent:Connect(function() end) -- drain queue
			else
				functions[name].OnServerInvoke = function(): RemoteResponse
					return { Ok = false, Code = "NotImplemented" }
				end
			end
		end
	end
	log:Info("Remotes ready in", if folder then folder:GetFullName() else "?")
end

return NetService
