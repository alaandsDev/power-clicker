--!strict
--[[
	MockDataStoreBackend — TEST/STUDIO ONLY. NOTHING IS PERSISTED.

	In-memory stand-in for DataStoreBackend used by:
	- unit tests (PlayerDataStore.spec) with failure injection;
	- Studio sessions when DataConfig.StudioBackend = "Mock" (DataService logs
	  a loud warning). DataService never selects it in live servers.

	Values are round-tripped through JSON like the real service, so
	non-serializable data (NaN, Instances, mixed tables) fails here too.
]]

local HttpService = game:GetService("HttpService")

local Try = require(game:GetService("ReplicatedStorage").Shared.Utils.Try)
local DataStoreBackend = require(script.Parent.DataStoreBackend)

type Transform = DataStoreBackend.Transform

export type MockBackend = DataStoreBackend.Backend & {
	FailNext: (self: MockBackend, count: number, message: string?) -> (),
	SetAlwaysFail: (self: MockBackend, enabled: boolean) -> (),
	GetRaw: (self: MockBackend, key: string) -> any,
	SetRaw: (self: MockBackend, key: string, value: any) -> (),
	WriteCount: number,
	CallCount: number,
}

type Self = {
	Name: string,
	WriteCount: number,
	CallCount: number,
	_data: { [string]: string },
	_failNext: number,
	_failMessage: string,
	_alwaysFail: boolean,
}

local MockDataStoreBackend = {}
MockDataStoreBackend.__index = MockDataStoreBackend

function MockDataStoreBackend.new(): MockBackend
	local self: Self = {
		Name = "MockDataStore (NOT PERSISTED)",
		WriteCount = 0,
		CallCount = 0,
		_data = {},
		_failNext = 0,
		_failMessage = "MockDataStoreBackend: injected failure",
		_alwaysFail = false,
	}
	return setmetatable(self, MockDataStoreBackend) :: any
end

function MockDataStoreBackend.FailNext(self: Self, count: number, message: string?)
	self._failNext = count
	if message then
		self._failMessage = message
	end
end

function MockDataStoreBackend.SetAlwaysFail(self: Self, enabled: boolean)
	self._alwaysFail = enabled
end

function MockDataStoreBackend.GetRaw(self: Self, key: string): any
	local encoded = self._data[key]
	return if encoded then HttpService:JSONDecode(encoded) else nil
end

function MockDataStoreBackend.SetRaw(self: Self, key: string, value: any)
	if value == nil then
		self._data[key] = nil
	else
		self._data[key] = HttpService:JSONEncode(value)
	end
end

function MockDataStoreBackend.Update(self: Self, key: string, transform: Transform, _userId: number?): (boolean, string?)
	self.CallCount += 1
	if self._alwaysFail then
		return false, self._failMessage
	end
	if self._failNext > 0 then
		self._failNext -= 1
		return false, self._failMessage
	end

	return Try.Call(function()
		local new = transform(MockDataStoreBackend.GetRaw(self, key))
		if new ~= nil then
			self._data[key] = HttpService:JSONEncode(new)
			self.WriteCount += 1
		end
	end)
end

return MockDataStoreBackend
