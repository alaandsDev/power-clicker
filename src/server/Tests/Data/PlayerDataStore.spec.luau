--[[
	PlayerDataStore tests. Uses MockDataStoreBackend (explicit test backend,
	in-memory, JSON round-trip) — never the real DataStore.
]]

local DataService = script.Parent.Parent.Parent.Services.DataService
local PlayerDataStore = require(DataService.PlayerDataStore)
local MockDataStoreBackend = require(DataService.MockDataStoreBackend)
local DataTemplate = require(DataService.DataTemplate)
local DataConfig = require(script.Parent.Parent.Parent.ServerConfig.DataConfig)

local KEY = "Player_1"
local USER = 1

return function(T)
	local now = 1_000_000
	local waits = 0

	local function makeStore(backend)
		return PlayerDataStore.new(backend, {
			DataVersion = DataConfig.DataVersion,
			CreateTemplate = DataTemplate.Create,
			StaleLockSeconds = 300,
			LockRetryAttempts = 2,
			LockRetryDelaySeconds = 5,
			LoadMaxAttempts = 3,
			LoadRetryBaseDelaySeconds = 1,
			SaveMaxAttempts = 3,
			SaveRetryBaseDelaySeconds = 1,
			PlaceId = 0,
			JobId = "test",
			Now = function()
				return now
			end,
			Wait = function()
				waits += 1
			end,
		})
	end

	T.describe("PlayerDataStore.Load", function()
		T.it("creates template data for a brand-new player and takes the lock", function()
			local backend = MockDataStoreBackend.new()
			local result = makeStore(backend):Load(KEY, USER, "s1")
			T.expect(result.Status).toBe("New")
			T.expect(result.Data.Currencies.Power).toBe(0)
			T.expect(backend:GetRaw(KEY).Meta.Session.Id).toBe("s1")
		end)

		T.it("returns saved data for an existing player", function()
			local backend = MockDataStoreBackend.new()
			local store = makeStore(backend)
			local first = store:Load(KEY, USER, "s1")
			first.Data.Currencies.Gems = 42
			T.expect(store:Save(KEY, USER, "s1", first.Data, true)).toBe("Saved")

			local second = store:Load(KEY, USER, "s2")
			T.expect(second.Status).toBe("Loaded")
			T.expect(second.Data.Currencies.Gems).toBe(42)
		end)

		T.it("retries transient failures", function()
			local backend = MockDataStoreBackend.new()
			backend:FailNext(2)
			local result = makeStore(backend):Load(KEY, USER, "s1")
			T.expect(result.Status).toBe("New")
			T.expect(backend.CallCount).toBe(3)
		end)

		T.it("FAILURE IS NOT A NEW PLAYER: persistent failure returns Failed and writes nothing", function()
			local backend = MockDataStoreBackend.new()
			backend:SetAlwaysFail(true)
			local result = makeStore(backend):Load(KEY, USER, "s1")
			T.expect(result.Status).toBe("Failed")
			T.expect(result.Data).toBeNil()
			backend:SetAlwaysFail(false)
			T.expect(backend:GetRaw(KEY)).toBeNil()
		end)

		T.it("failure with existing data leaves the data untouched", function()
			local backend = MockDataStoreBackend.new()
			local store = makeStore(backend)
			local loaded = store:Load(KEY, USER, "s1")
			loaded.Data.Currencies.Gems = 7
			store:Save(KEY, USER, "s1", loaded.Data, true)

			backend:SetAlwaysFail(true)
			T.expect(store:Load(KEY, USER, "s2").Status).toBe("Failed")
			backend:SetAlwaysFail(false)
			T.expect(backend:GetRaw(KEY).Data.Currencies.Gems).toBe(7)
		end)

		T.it("does not steal a live lock from another server", function()
			local backend = MockDataStoreBackend.new()
			local store = makeStore(backend)
			store:Load(KEY, USER, "serverA")
			local result = store:Load(KEY, USER, "serverB")
			T.expect(result.Status).toBe("Locked")
			T.expect(backend:GetRaw(KEY).Meta.Session.Id).toBe("serverA")
		end)

		T.it("acquires the lock once the other server releases it", function()
			local backend = MockDataStoreBackend.new()
			local store = makeStore(backend)
			local a = store:Load(KEY, USER, "serverA")
			a.Data.Currencies.Gems = 3
			-- Release happens "during" B's first retry wait.
			local b = PlayerDataStore.new(backend, {
				DataVersion = DataConfig.DataVersion,
				CreateTemplate = DataTemplate.Create,
				StaleLockSeconds = 300,
				LockRetryAttempts = 3,
				LockRetryDelaySeconds = 5,
				LoadMaxAttempts = 3,
				LoadRetryBaseDelaySeconds = 1,
				SaveMaxAttempts = 3,
				SaveRetryBaseDelaySeconds = 1,
				PlaceId = 0,
				JobId = "b",
				Now = function()
					return now
				end,
				Wait = function()
					store:Save(KEY, USER, "serverA", a.Data, true)
				end,
			})
			local result = b:Load(KEY, USER, "serverB")
			T.expect(result.Status).toBe("Loaded")
			T.expect(result.Data.Currencies.Gems).toBe(3)
		end)

		T.it("takes over a stale lock (crashed server)", function()
			local backend = MockDataStoreBackend.new()
			local store = makeStore(backend)
			store:Load(KEY, USER, "crashed")
			now += 301
			local result = store:Load(KEY, USER, "fresh")
			T.expect(result.Status).toBe("Loaded")
			T.expect(result.StoleLock).toBe(true)
		end)

		T.it("refuses data from a newer schema and does not touch it", function()
			local backend = MockDataStoreBackend.new()
			backend:SetRaw(KEY, { Data = { DataVersion = 999, Marker = "keep" }, Meta = {} })
			local result = makeStore(backend):Load(KEY, USER, "s1")
			T.expect(result.Status).toBe("FutureVersion")
			T.expect(backend:GetRaw(KEY).Data.Marker).toBe("keep")
			T.expect(backend.WriteCount).toBe(0)
		end)

		T.it("refuses corrupt records and does not overwrite them", function()
			local backend = MockDataStoreBackend.new()
			backend:SetRaw(KEY, "garbage")
			local result = makeStore(backend):Load(KEY, USER, "s1")
			T.expect(result.Status).toBe("Corrupt")
			T.expect(backend:GetRaw(KEY)).toBe("garbage")
		end)

		T.it("stops when cancelled (player left) without writing", function()
			local backend = MockDataStoreBackend.new()
			local result = makeStore(backend):Load(KEY, USER, "s1", function()
				return true
			end)
			T.expect(result.Status).toBe("Cancelled")
			T.expect(backend.WriteCount).toBe(0)
		end)

		T.it("isolates players (different keys)", function()
			local backend = MockDataStoreBackend.new()
			local store = makeStore(backend)
			local p1 = store:Load("Player_1", 1, "s1")
			local p2 = store:Load("Player_2", 2, "s2")
			p1.Data.Currencies.Gems = 10
			store:Save("Player_1", 1, "s1", p1.Data, false)
			T.expect(backend:GetRaw("Player_2").Data.Currencies.Gems).toBe(0)
			T.expect(p2.Status).toBe("New")
		end)
	end)

	T.describe("PlayerDataStore.Save", function()
		T.it("refreshes the lock time on autosave", function()
			local backend = MockDataStoreBackend.new()
			local store = makeStore(backend)
			local loaded = store:Load(KEY, USER, "s1")
			now += 60
			T.expect(store:Save(KEY, USER, "s1", loaded.Data, false)).toBe("Saved")
			T.expect(backend:GetRaw(KEY).Meta.Session.Time).toBe(now)
		end)

		T.it("does not overwrite data after the lock was lost", function()
			local backend = MockDataStoreBackend.new()
			local store = makeStore(backend)
			local old = store:Load(KEY, USER, "old")
			now += 301
			local new = store:Load(KEY, USER, "new")
			new.Data.Currencies.Gems = 100
			store:Save(KEY, USER, "new", new.Data, false)

			old.Data.Currencies.Gems = 1
			T.expect(store:Save(KEY, USER, "old", old.Data, false)).toBe("LockLost")
			T.expect(backend:GetRaw(KEY).Data.Currencies.Gems).toBe(100)
		end)

		T.it("release is idempotent (retry after committed release)", function()
			local backend = MockDataStoreBackend.new()
			local store = makeStore(backend)
			local loaded = store:Load(KEY, USER, "s1")
			T.expect(store:Save(KEY, USER, "s1", loaded.Data, true)).toBe("Saved")
			T.expect(store:Save(KEY, USER, "s1", loaded.Data, true)).toBe("Saved")
			T.expect(store:Save(KEY, USER, "s1", loaded.Data, false)).toBe("LockLost")
		end)

		T.it("retries transient save failures", function()
			local backend = MockDataStoreBackend.new()
			local store = makeStore(backend)
			local loaded = store:Load(KEY, USER, "s1")
			loaded.Data.Currencies.Gems = 5
			backend:FailNext(2)
			T.expect(store:Save(KEY, USER, "s1", loaded.Data, false)).toBe("Saved")
			T.expect(backend:GetRaw(KEY).Data.Currencies.Gems).toBe(5)
		end)

		T.it("reports Failed after exhausting retries", function()
			local backend = MockDataStoreBackend.new()
			local store = makeStore(backend)
			local loaded = store:Load(KEY, USER, "s1")
			backend:SetAlwaysFail(true)
			T.expect(store:Save(KEY, USER, "s1", loaded.Data, false)).toBe("Failed")
		end)

		T.it("reports Missing when the record disappeared", function()
			local backend = MockDataStoreBackend.new()
			T.expect(makeStore(backend):Save(KEY, USER, "s1", {}, false)).toBe("Missing")
		end)
	end)
end
