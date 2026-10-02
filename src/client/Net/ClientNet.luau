--!strict
--[[
	ClientNet
	Client-side access to the remotes created by the server's NetService.
	The client can only *request*; every request is validated server-side.
	Never send computed values (power, prices, rewards) — send intent + ids.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local RemoteDefinitions = require(Shared:WaitForChild("Net"):WaitForChild("RemoteDefinitions"))
local Logger = require(Shared:WaitForChild("Utils"):WaitForChild("Logger"))

type RemoteResponse = Types.RemoteResponse

local log = Logger.new("ClientNet")

local REMOTE_WAIT_TIMEOUT = 30

local ClientNet = {}

local folder: Instance? = nil

local function getRemote(name: string): Instance
	local spec = RemoteDefinitions.Remotes[name]
	assert(spec, "Unknown remote: " .. name)
	if not folder then
		folder = ReplicatedStorage:WaitForChild(RemoteDefinitions.FolderName, REMOTE_WAIT_TIMEOUT)
		assert(folder, "Remotes folder not found (server failed to boot?)")
	end
	local remote = (folder :: Instance):WaitForChild(name, REMOTE_WAIT_TIMEOUT)
	assert(remote, "Remote not found: " .. name)
	return remote
end

function ClientNet.Fire(name: string, ...: any)
	assert(RemoteDefinitions.Remotes[name].Direction == "ClientToServer", name .. " is not ClientToServer")
	local remote = getRemote(name) :: RemoteEvent
	remote:FireServer(...)
end

-- Yields. Returns a RemoteResponse; network errors become { Ok = false, Code = "NetworkError" }.
function ClientNet.Invoke(name: string, ...: any): RemoteResponse
	assert(RemoteDefinitions.Remotes[name].Kind == "Function", name .. " is not a RemoteFunction")
	local remote = getRemote(name) :: RemoteFunction
	local args = table.pack(...)
	local ok, result = pcall(function()
		return remote:InvokeServer(table.unpack(args, 1, args.n))
	end)
	if not ok or type(result) ~= "table" then
		log:Warn("Invoke failed:", name, if ok then "bad response" else result)
		return { Ok = false, Code = "NetworkError" }
	end
	return result
end

function ClientNet.On(name: string, handler: (...any) -> ()): RBXScriptConnection
	assert(RemoteDefinitions.Remotes[name].Direction == "ServerToClient", name .. " is not ServerToClient")
	return (getRemote(name) :: RemoteEvent).OnClientEvent:Connect(handler)
end

return ClientNet
