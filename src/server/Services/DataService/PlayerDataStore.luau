--!strict
--[[
	PlayerDataStore
	Session-locked load/save of one record per player on top of a Backend
	(real DataStoreBackend or MockDataStoreBackend). No Players/Instance
	dependencies: time and waiting are injectable, so it is fully unit tested.

	Stored record:
		{
			Data = PlayerData,
			Meta = {
				Session = { Id, Time, PlaceId, JobId } | nil,  -- lock owner
				LastReleasedSession = string?,                -- makes release idempotent
				CreatedAt, LastSaveTime, SaveCount, LoadCount,
			},
		}

	Data-loss guarantees:
	- "No record" (New) is only reported when the backend call SUCCEEDED and
	  returned nil. A failed call is never treated as a new player.
	- Unreadable/unknown records (Corrupt) and records from a newer schema
	  (FutureVersion) are NEVER written to.
	- A live lock owned by another session is never overwritten; only locks
	  older than StaleLockSeconds (crashed server) may be taken over.
	- Saves only write while this session still owns the lock (LockLost otherwise).
]]

local DataStoreBackend = require(script.Parent.DataStoreBackend)

type Backend = DataStoreBackend.Backend

export type LoadStatus = "Loaded" | "New" | "Locked" | "Failed" | "FutureVersion" | "Corrupt" | "Cancelled"
export type SaveStatus = "Saved" | "LockLost" | "Missing" | "Failed"

export type LoadResult = {
	Status: LoadStatus,
	Data: any?,
	StoleLock: boolean,
	Error: string?,
}

export type Options = {
	DataVersion: number,
	CreateTemplate: (now: number) -> any,
	StaleLockSeconds: number,
	LockRetryAttempts: number,
	LockRetryDelaySeconds: number,
	LoadMaxAttempts: number,
	LoadRetryBaseDelaySeconds: number,
	SaveMaxAttempts: number,
	SaveRetryBaseDelaySeconds: number,
	PlaceId: number,
	JobId: string,
	Now: (() -> number)?, -- defaults to os.time
	Wait: ((seconds: number) -> ())?, -- defaults to task.wait
}

export type PlayerDataStore = {
	Load: (self: PlayerDataStore, key: string, userId: number, sessionId: string, isCancelled: (() -> boolean)?) -> LoadResult,
	Save: (self: PlayerDataStore, key: string, userId: number, sessionId: string, data: any, release: boolean) -> (SaveStatus, string?),
}

type Self = {
	_backend: Backend,
	_options: Options,
	_now: () -> number,
	_wait: (seconds: number) -> (),
}

local PlayerDataStore = {}
PlayerDataStore.__index = PlayerDataStore

function PlayerDataStore.new(backend: Backend, options: Options): PlayerDataStore
	local self: Self = {
		_backend = backend,
		_options = options,
		_now = options.Now or os.time,
		_wait = options.Wait or function(seconds: number)
			task.wait(seconds)
		end,
	}
	return setmetatable(self, PlayerDataStore) :: any
end

local function newLock(self: Self, sessionId: string, now: number): { [string]: any }
	return {
		Id = sessionId,
		Time = now,
		PlaceId = self._options.PlaceId,
		JobId = self._options.JobId,
	}
end

function PlayerDataStore.Load(self: Self, key: string, userId: number, sessionId: string, isCancelled: (() -> boolean)?): LoadResult
	local options: Options = self._options
	local cancelled = isCancelled or function()
		return false
	end

	local failures = 0
	local lockWaits = 0
	local lastError: string? = nil

	while true do
		if cancelled() then
			return { Status = "Cancelled", StoleLock = false }
		end

		-- Outcome of the latest transform invocation (UpdateAsync may call it more than once).
		local outcome: LoadStatus? = nil
		local loadedData: any = nil
		local stole = false

		local ok, err = self._backend:Update(key, function(old: any): any
			outcome, loadedData, stole = nil, nil, false
			local now = self._now()

			if old == nil then
				local record = {
					Data = options.CreateTemplate(now),
					Meta = {
						Session = newLock(self, sessionId, now),
						CreatedAt = now,
						LastSaveTime = 0,
						SaveCount = 0,
						LoadCount = 1,
					},
				}
				outcome, loadedData = "New", record.Data
				return record
			end

			if type(old) ~= "table" or type(old.Data) ~= "table" or type(old.Meta) ~= "table" then
				outcome = "Corrupt"
				return nil
			end
			local version = old.Data.DataVersion
			if type(version) ~= "number" then
				outcome = "Corrupt"
				return nil
			end
			if version > options.DataVersion then
				outcome = "FutureVersion"
				return nil
			end

			local lock = old.Meta.Session
			if type(lock) == "table" and lock.Id ~= sessionId then
				local age = now - (tonumber(lock.Time) or 0)
				if age < options.StaleLockSeconds then
					outcome = "Locked"
					return nil
				end
				stole = true
			end

			old.Meta.Session = newLock(self, sessionId, now)
			old.Meta.LoadCount = (tonumber(old.Meta.LoadCount) or 0) + 1
			outcome, loadedData = "Loaded", old.Data
			return old
		end, userId)

		if not ok or outcome == nil then
			failures += 1
			lastError = err or "transform not invoked"
			if failures >= options.LoadMaxAttempts then
				return { Status = "Failed", StoleLock = false, Error = lastError }
			end
			self._wait(options.LoadRetryBaseDelaySeconds * 2 ^ (failures - 1))
		elseif outcome == "Locked" then
			lockWaits += 1
			if lockWaits > options.LockRetryAttempts then
				return { Status = "Locked", StoleLock = false }
			end
			self._wait(options.LockRetryDelaySeconds)
		elseif outcome == "Loaded" or outcome == "New" then
			return { Status = outcome, Data = loadedData, StoleLock = stole }
		else
			return { Status = outcome, StoleLock = false }
		end
	end
end

--[[
	Writes `data` if this session still owns the lock. `release = true` also
	frees the lock (player leaving / server closing). `data` must be a
	snapshot (deep copy) that is not mutated while the save is in flight.
]]
function PlayerDataStore.Save(self: Self, key: string, userId: number, sessionId: string, data: any, release: boolean): (SaveStatus, string?)
	local options: Options = self._options
	local failures = 0

	while true do
		local outcome: SaveStatus? = nil

		local ok, err = self._backend:Update(key, function(old: any): any
			outcome = nil
			if type(old) ~= "table" or type(old.Meta) ~= "table" then
				outcome = "Missing"
				return nil
			end
			local meta = old.Meta
			local lock = meta.Session
			if type(lock) ~= "table" or lock.Id ~= sessionId then
				-- A previous attempt may have committed the release before erroring.
				if release and lock == nil and meta.LastReleasedSession == sessionId then
					outcome = "Saved"
				else
					outcome = "LockLost"
				end
				return nil
			end

			local now = self._now()
			old.Data = data
			meta.LastSaveTime = now
			meta.SaveCount = (tonumber(meta.SaveCount) or 0) + 1
			if release then
				meta.Session = nil
				meta.LastReleasedSession = sessionId
			else
				lock.Time = now
			end
			outcome = "Saved"
			return old
		end, userId)

		if ok and outcome ~= nil then
			return outcome, nil
		end

		failures += 1
		if failures >= options.SaveMaxAttempts then
			return "Failed", err or "transform not invoked"
		end
		self._wait(options.SaveRetryBaseDelaySeconds * 2 ^ (failures - 1))
	end
end

return PlayerDataStore
