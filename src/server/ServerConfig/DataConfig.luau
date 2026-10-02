--!strict
--[[
	DataConfig (server-only)
	Persistence settings for DataService.

	DataVersion: bump when the PlayerData shape changes AND add a migration in
	Services/DataService/Migrations (from DataVersion - 1 to DataVersion).
	Never lower it; servers refuse to load data newer than their DataVersion.

	StoreName: changing it effectively wipes everyone's data. Do not change it
	after launch.
]]

return {
	DataVersion = 8,

	StoreName = "PlayerData_Production",
	KeyPrefix = "Player_",

	AutosaveIntervalSeconds = 60,

	Session = {
		-- A lock not refreshed for this long is considered abandoned (crashed
		-- server) and may be taken over. Autosave refreshes it every interval.
		StaleLockSeconds = 300,
		-- When another live server still holds the lock (e.g. player hopped
		-- servers and the old one is still saving), wait and retry.
		LockRetryAttempts = 6,
		LockRetryDelaySeconds = 5,
	},

	Load = {
		MaxAttempts = 5,
		RetryBaseDelaySeconds = 1, -- exponential backoff: 1, 2, 4, 8...
	},

	Save = {
		MaxAttempts = 5,
		RetryBaseDelaySeconds = 1,
	},

	-- Roblox gives BindToClose 30s in total; leave margin.
	BindToCloseTimeoutSeconds = 25,

	-- DataStore value limit is 4,194,304 characters.
	MaxRecordCharacters = 4_000_000,
	WarnRecordCharacters = 3_000_000,

	--[[
		Backend used when running in Studio:
		- "Real": real DataStores. Requires the place to be published and
		  Game Settings > Security > "Enable Studio Access to API Services".
		  If unavailable, players are kicked with an explanation (no silent
		  fallback — we never pretend data is persisted).
		- "Mock": MockDataStoreBackend, in-memory, NOTHING IS SAVED. Loudly
		  logged. Never used in live servers regardless of this value.
	]]
	StudioBackend = "Real",
}
