--!strict
--[[
	DataController
	Read-only client mirror of the player's data, fed by the server
	(DataSnapshot + batched DataChanged). UI reads from here.

	This is a VIEW. Modifying it changes nothing on the server; all actions
	go through ClientNet requests that the server validates.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Logger = require(Shared:WaitForChild("Utils"):WaitForChild("Logger"))
local Signal = require(Shared:WaitForChild("Utils"):WaitForChild("Signal"))
local ClientNet = require(script.Parent.Parent.Net.ClientNet)

local log = Logger.new("DataController")

local READY_RETRY_SECONDS = 10
local READY_MAX_RETRIES = 3

local DataController = {
	-- Fired once when the first snapshot arrives.
	Loaded = Signal.new() :: Signal.Signal<{ [string]: any }>,
	-- (key, newValue) for every top-level key that changed (also fired for every key on snapshot).
	Changed = Signal.new() :: Signal.Signal<string, any>,
}

local state: { [string]: any }? = nil

function DataController.IsLoaded(): boolean
	return state ~= nil
end

function DataController.Get(key: string): any
	return if state then state[key] else nil
end

-- Yields until the first snapshot arrives.
function DataController.WaitUntilLoaded(): { [string]: any }
	if state then
		return state
	end
	return DataController.Loaded:Wait()
end

function DataController.Init()
	ClientNet.On("DataSnapshot", function(snapshot: any)
		if type(snapshot) ~= "table" then
			return
		end
		local first = state == nil
		state = snapshot
		for key, value in snapshot do
			DataController.Changed:Fire(key, value)
		end
		if first then
			log:Info("Data loaded")
			-- Local-only flag read by the ReplicatedFirst loading screen.
			Players.LocalPlayer:SetAttribute("ClientDataLoaded", true)
			DataController.Loaded:Fire(snapshot)
		end
	end)

	ClientNet.On("DataChanged", function(key: any, value: any)
		local current = state
		if type(key) ~= "string" or not current then
			return
		end
		current[key] = value
		DataController.Changed:Fire(key, value)
	end)
end

function DataController.Start()
	-- Listeners are connected in Init, so it is now safe to ask for the snapshot.
	-- Retry a few times in case the first request was dropped (e.g. very early join).
	task.spawn(function()
		for _ = 1, READY_MAX_RETRIES do
			if state then
				return
			end
			ClientNet.Fire("ClientReady")
			task.wait(READY_RETRY_SECONDS)
		end
		if not state then
			log:Warn("No data snapshot received from server")
		end
	end)
end

return DataController
