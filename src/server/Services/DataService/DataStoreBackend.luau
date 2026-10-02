--!strict
--[[
	DataStoreBackend
	Thin wrapper over the REAL Roblox DataStoreService. All persistence goes
	through UpdateAsync (atomic read-modify-write), never SetAsync, so session
	locks cannot be overwritten by a racing server.

	Interface (shared with MockDataStoreBackend):
		backend:Update(key, transform, userId) -> (success: boolean, err: string?)
	`transform(old) -> new?` must not yield; returning nil cancels the write.
]]

local DataStoreService = game:GetService("DataStoreService")

local Try = require(game:GetService("ReplicatedStorage").Shared.Utils.Try)

export type Transform = (old: any) -> any
export type Backend = {
	Name: string,
	Update: (self: Backend, key: string, transform: Transform, userId: number?) -> (boolean, string?),
}

type Self = {
	Name: string,
	_storeName: string,
	_store: DataStore?,
}

local BUDGET_WAIT_STEP = 0.5
local BUDGET_MAX_WAIT = 10

local DataStoreBackend = {}
DataStoreBackend.__index = DataStoreBackend

function DataStoreBackend.new(storeName: string): Backend
	local self: Self = {
		Name = "DataStore:" .. storeName,
		_storeName = storeName,
		_store = nil,
	}
	return setmetatable(self, DataStoreBackend) :: any
end

-- GetDataStore can throw (unpublished place / Studio API access off). Resolve
-- lazily so the failure surfaces as a normal, retryable load/save error.
local function getStore(self: Self): DataStore
	local store = self._store
	if not store then
		store = DataStoreService:GetDataStore(self._storeName)
		self._store = store
	end
	return store :: DataStore
end

local function waitForBudget()
	local waited = 0
	while DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync) < 1 and waited < BUDGET_MAX_WAIT do
		task.wait(BUDGET_WAIT_STEP)
		waited += BUDGET_WAIT_STEP
	end
end

function DataStoreBackend.Update(self: Self, key: string, transform: Transform, userId: number?): (boolean, string?)
	return Try.Call(function()
		local store = getStore(self)
		waitForBudget()
		store:UpdateAsync(key, function(old: any): (any, { number }?)
			local new = transform(old)
			if new == nil then
				return nil, nil
			end
			-- Tag the key with the UserId for GDPR/right-to-erasure tooling.
			return new, if userId then { userId } else nil
		end)
	end)
end

return DataStoreBackend
