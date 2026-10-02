--!strict
--[[
	Signal
	Minimal typed event object for in-process (same VM) communication between
	services/controllers. Handlers run in their own thread (task.spawn) so a
	yielding or erroring handler never blocks or breaks the emitter.
]]

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	Wait: (self: Signal<T...>) -> T...,
	DisconnectAll: (self: Signal<T...>) -> (),
}

type Handler = { Callback: (...any) -> (), Connection: Connection }

type Self = { _handlers: { Handler } }

local Signal = {}
Signal.__index = Signal

function Signal.new<T...>(): Signal<T...>
	local self: Self = { _handlers = {} }
	return setmetatable(self, Signal) :: any
end

function Signal.Connect(self: Self, callback: (...any) -> ()): Connection
	local handlers = self._handlers
	local connection = { Connected = true } :: any
	local entry: Handler = { Callback = callback, Connection = connection }

	function connection.Disconnect(conn: Connection)
		if not conn.Connected then
			return
		end
		conn.Connected = false
		local index = table.find(handlers, entry)
		if index then
			table.remove(handlers, index)
		end
	end

	table.insert(handlers, entry)
	return connection
end

function Signal.Once(self: Self, callback: (...any) -> ()): Connection
	local connection: Connection
	connection = Signal.Connect(self, function(...)
		connection:Disconnect()
		callback(...)
	end)
	return connection
end

function Signal.Fire(self: Self, ...: any)
	-- Snapshot so handlers may disconnect while iterating.
	local snapshot = table.clone(self._handlers)
	for _, entry in snapshot do
		if entry.Connection.Connected then
			task.spawn(entry.Callback, ...)
		end
	end
end

function Signal.Wait(self: Self): ...any
	local thread = coroutine.running()
	Signal.Once(self, function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal.DisconnectAll(self: Self)
	for _, entry in self._handlers do
		entry.Connection.Connected = false
	end
	table.clear(self._handlers)
end

return Signal
