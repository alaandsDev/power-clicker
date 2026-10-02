--!strict
--[[
	DataService
	Owns every player's PlayerData for the lifetime of their session.

	Lifecycle per player:
		PlayerAdded   → Load (session lock) → migrate (on a copy) → reconcile
		              → sanitize → State = "Loaded" → PlayerLoaded:Fire
		every N sec   → autosave (refreshes the lock)
		PlayerRemoving→ PlayerReleasing:Fire → final save + release lock
		BindToClose   → release every session in parallel, wait (bounded)

	If loading fails for ANY reason the player is kicked with an explanation.
	They are never given default data on failure, and nothing is ever saved
	for a session that did not load successfully.

	Other services:
		DataService.GetData(player)       → PlayerData? (nil until loaded)
		DataService.MarkChanged(player, "Currencies")  → replicate that key
		DataService.SaveNow(player)       → force save (e.g. after a purchase)
		DataService.PlayerReady           → data loaded AND client listening:
		                                    push initial non-data state here
	Services mutate the returned table directly (server-side only) and then
	call MarkChanged for keys the client should see.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local GameConfig = require(Shared.Config.GameConfig)
local Logger = require(Shared.Utils.Logger)
local Signal = require(Shared.Utils.Signal)
local TableUtil = require(Shared.Utils.TableUtil)
local Guard = require(Shared.Utils.Guard)
local Text = require(Shared.Localization)

local DataConfig = require(script.Parent.Parent.ServerConfig.DataConfig)
local NetService = require(script.Parent.NetService)

local DataTemplate = require(script.DataTemplate)
local Migrations = require(script.Migrations)
local DataSanitizer = require(script.DataSanitizer)
local PlayerDataStore = require(script.PlayerDataStore)
local DataStoreBackend = require(script.DataStoreBackend)
local MockDataStoreBackend = require(script.MockDataStoreBackend)

type PlayerData = Types.PlayerData

type SessionState = "Loading" | "Loaded" | "Releasing" | "Released"

type Session = {
	Player: Player,
	UserId: number,
	Key: string,
	SessionId: string,
	State: SessionState,
	Data: PlayerData?,
	Saving: boolean,
	LockLost: boolean,
	LastSaveAt: number,
	ClientReady: boolean,
	Announced: boolean, -- PlayerLoaded was fired for this session
	ReadyAnnounced: boolean, -- PlayerReady was fired for this session
	JoinedAt: number, -- os.clock() when the session was created (diagnostics)
	DirtyKeys: { [string]: boolean },
}

local log = Logger.new("DataService")

-- Kick reasons; texts live in Shared/Localization under "kick.<Reason>".
local KICK_REASONS = {
	Failed = true,
	Locked = true,
	FutureVersion = true,
	Corrupt = true,
	Migration = true,
	LockLost = true,
}

local AUTOSAVE_CHECK_SECONDS = 5
local RELEASE_WAIT_STEP = 0.25
local PENDING_RELEASE_MAX_WAIT = 30

local DataService = {
	PlayerLoaded = Signal.new() :: Signal.Signal<Player, PlayerData>,
	-- Fired right before the final save. Handlers MUST NOT yield; write any
	-- final session state (e.g. playtime) into the data synchronously.
	PlayerReleasing = Signal.new() :: Signal.Signal<Player, PlayerData>,
	-- Fired once per session when data is loaded AND the client has signalled
	-- ClientReady (its listeners are connected). Use it to push initial
	-- non-persisted state (power info, overdrive state...).
	PlayerReady = Signal.new() :: Signal.Signal<Player, PlayerData>,
	-- Studio-only: fired after ResetForTesting replaced a player's data.
	DataReset = Signal.new() :: Signal.Signal<Player, PlayerData>,
}

local sessions: { [Player]: Session } = {}
local dirtySessions: { [Session]: boolean } = {}
-- ClientReady can arrive before PlayerAdded is processed; remember it.
local readyBeforeSession: { [Player]: boolean } = {}
local pendingReleaseByUserId: { [number]: number } = {}
local activeLoads = 0
local activeReleases = 0
local shuttingDown = false
local usingMock = false

local store: PlayerDataStore.PlayerDataStore

-- ─── Helpers ────────────────────────────────────────────────────────────────

local function keyFor(userId: number): string
	return DataConfig.KeyPrefix .. tostring(userId)
end

local function kick(player: Player, reason: string)
	local message = Text.GetFor(player.LocaleId, "kick." .. (if KICK_REASONS[reason] then reason else "Failed"))
	if RunService:IsStudio() and not usingMock then
		message ..= Text.GetFor(player.LocaleId, "kick.StudioHint")
	end
	if player.Parent == Players then
		player:Kick(message)
	end
end

local function buildClientView(data: PlayerData): { [string]: any }
	local view = {}
	for key, value in data :: any do
		if not DataTemplate.ServerOnlyKeys[key] then
			view[key] = value
		end
	end
	return view
end

local function sendSnapshot(session: Session)
	local data = session.Data
	if not data then
		return
	end
	NetService.FireClient("DataSnapshot", session.Player, buildClientView(data))
	-- A full snapshot supersedes any queued deltas.
	table.clear(session.DirtyKeys)
	dirtySessions[session] = nil
	log:Debug(string.format("user=%d snapshot sent (%.2fs after join)", session.UserId, os.clock() - session.JoinedAt))

	if not session.ReadyAnnounced then
		session.ReadyAnnounced = true
		DataService.PlayerReady:Fire(session.Player, data)
	end
end

-- Serialized per session: a save never overlaps another save of the same player.
local function saveSession(session: Session, release: boolean): boolean
	while session.Saving do
		task.wait(RELEASE_WAIT_STEP)
	end
	if session.LockLost or not session.Data then
		return false
	end

	session.Saving = true
	local snapshot = TableUtil.DeepCopy(session.Data) :: any
	local issues = DataSanitizer.Sanitize(snapshot, GameConfig.Numbers.MaxValue)
	if #issues > 0 then
		log:Error(string.format("user=%d sanitized %d issue(s) before save: %s", session.UserId, #issues, table.concat(issues, "; ", 1, math.min(#issues, 5))))
	end

	local okEncode, encoded = pcall(HttpService.JSONEncode, HttpService, snapshot)
	if okEncode then
		local size = #encoded
		if size > DataConfig.MaxRecordCharacters then
			log:Error(string.format("user=%d data too large (%d chars); save will likely fail", session.UserId, size))
		elseif size > DataConfig.WarnRecordCharacters then
			log:Warn(string.format("user=%d data is large (%d chars)", session.UserId, size))
		end
	else
		log:Error(string.format("user=%d data not JSON-encodable: %s", session.UserId, tostring(encoded)))
	end

	local status, err = store:Save(session.Key, session.UserId, session.SessionId, snapshot, release)
	session.Saving = false

	if status == "Saved" then
		session.LastSaveAt = os.clock()
		log:Debug(string.format("user=%d saved%s", session.UserId, if release then " + released" else ""))
		return true
	elseif status == "LockLost" or status == "Missing" then
		session.LockLost = true
		log:Error(string.format("user=%d lost session lock (%s); further saves disabled", session.UserId, status))
		if not release then
			kick(session.Player, "LockLost")
		end
		return false
	else
		log:Error(string.format("user=%d save failed after retries: %s", session.UserId, tostring(err)))
		return false
	end
end

local function releaseSession(session: Session)
	if session.State ~= "Loaded" then
		return
	end
	session.State = "Releasing"
	activeReleases += 1
	pendingReleaseByUserId[session.UserId] = (pendingReleaseByUserId[session.UserId] or 0) + 1

	if session.Announced and session.Data then
		DataService.PlayerReleasing:Fire(session.Player, session.Data)
	end
	saveSession(session, true)

	session.State = "Released"
	dirtySessions[session] = nil
	local pending = (pendingReleaseByUserId[session.UserId] or 1) - 1
	if pending > 0 then
		pendingReleaseByUserId[session.UserId] = pending
	else
		pendingReleaseByUserId[session.UserId] = nil
	end
	activeReleases -= 1
end

-- ─── Player lifecycle ───────────────────────────────────────────────────────

local function onPlayerAdded(player: Player)
	if sessions[player] or shuttingDown then
		return
	end

	local session: Session = {
		Player = player,
		UserId = player.UserId,
		Key = keyFor(player.UserId),
		SessionId = HttpService:GenerateGUID(false),
		State = "Loading",
		Data = nil,
		Saving = false,
		LockLost = false,
		LastSaveAt = os.clock(),
		ClientReady = readyBeforeSession[player] == true,
		Announced = false,
		ReadyAnnounced = false,
		JoinedAt = os.clock(),
		DirtyKeys = {},
	}
	readyBeforeSession[player] = nil
	sessions[player] = session
	activeLoads += 1

	-- Fast rejoin to the SAME server: wait for our own release to finish
	-- instead of bouncing off our own lock.
	local waited = 0
	while pendingReleaseByUserId[session.UserId] and waited < PENDING_RELEASE_MAX_WAIT do
		task.wait(RELEASE_WAIT_STEP)
		waited += RELEASE_WAIT_STEP
	end

	local function isGone(): boolean
		return player.Parent ~= Players or sessions[player] ~= session
	end

	local result = store:Load(session.Key, session.UserId, session.SessionId, isGone)
	activeLoads -= 1

	if result.Status ~= "Loaded" and result.Status ~= "New" then
		if sessions[player] == session then
			sessions[player] = nil
		end
		if result.Status == "Cancelled" then
			return
		end
		log:Warn(string.format("user=%d load %s %s", session.UserId, result.Status, result.Error or ""))
		kick(player, result.Status)
		return
	end

	local loaded = result.Data :: any
	if result.StoleLock then
		log:Warn(string.format("user=%d took over a stale session lock", session.UserId))
	end

	-- Migrate on a copy: on failure the stored data is left untouched.
	local data = TableUtil.DeepCopy(loaded)
	local migrated, migrationError = Migrations.Run(data, DataConfig.DataVersion)
	if not migrated then
		log:Error(string.format("user=%d migration failed: %s", session.UserId, tostring(migrationError)))
		-- Release the lock with the ORIGINAL data, then kick.
		session.Data = loaded
		session.State = "Loaded"
		releaseSession(session)
		sessions[player] = nil
		kick(player, "Migration")
		return
	end

	local now = os.time()
	TableUtil.Reconcile(data, DataTemplate.Create(now) :: any)
	local issues = DataSanitizer.Sanitize(data, GameConfig.Numbers.MaxValue)
	if #issues > 0 then
		log:Warn(string.format("user=%d sanitized %d issue(s) on load", session.UserId, #issues))
	end

	local playerData = data :: PlayerData
	playerData.Stats.SessionCount += 1
	playerData.Stats.LastJoinTime = now
	session.Data = playerData
	session.State = "Loaded"

	-- Player left while we were loading: release immediately.
	if isGone() then
		releaseSession(session)
		if sessions[player] == session then
			sessions[player] = nil
		end
		return
	end

	log:Info(string.format("user=%d %s (sessions=%d, %.2fs after join)", session.UserId, if result.Status == "New" then "created new data" else "loaded data", playerData.Stats.SessionCount, os.clock() - session.JoinedAt))
	session.Announced = true
	DataService.PlayerLoaded:Fire(player, playerData)
	if session.ClientReady then
		sendSnapshot(session)
	end
end

local function onPlayerRemoving(player: Player)
	readyBeforeSession[player] = nil
	local session = sessions[player]
	if not session then
		return
	end
	-- Loading sessions notice via isGone() and release themselves.
	if session.State == "Loaded" then
		releaseSession(session)
	end
	if sessions[player] == session then
		sessions[player] = nil
	end
end

local function onClose()
	shuttingDown = true
	for _, session in sessions do
		task.spawn(releaseSession, session)
	end
	local deadline = os.clock() + DataConfig.BindToCloseTimeoutSeconds
	while (activeReleases > 0 or activeLoads > 0) and os.clock() < deadline do
		task.wait(RELEASE_WAIT_STEP)
	end
	if activeReleases > 0 or activeLoads > 0 then
		log:Error(string.format("BindToClose timed out (releases=%d loads=%d)", activeReleases, activeLoads))
	end
end

-- ─── Public API ─────────────────────────────────────────────────────────────

function DataService.GetData(player: Player): PlayerData?
	local session = sessions[player]
	if session and session.State == "Loaded" then
		return session.Data
	end
	return nil
end

function DataService.IsLoaded(player: Player): boolean
	return DataService.GetData(player) ~= nil
end

-- Yields until the player's data is loaded, they leave, or the timeout passes.
function DataService.WaitForData(player: Player, timeoutSeconds: number?): PlayerData?
	local deadline = os.clock() + (timeoutSeconds or 60)
	while player.Parent == Players and os.clock() < deadline do
		local data = DataService.GetData(player)
		if data then
			return data
		end
		local session = sessions[player]
		if not session then
			return nil
		end
		task.wait(0.1)
	end
	return DataService.GetData(player)
end

-- Queue replication of a top-level data key (batched, see GameConfig.Replication).
function DataService.MarkChanged(player: Player, key: string)
	local session = sessions[player]
	if not session or session.State ~= "Loaded" or DataTemplate.ServerOnlyKeys[key] then
		return
	end
	session.DirtyKeys[key] = true
	dirtySessions[session] = true
end

-- Forces an immediate save (e.g. right after granting a purchase). Yields.
function DataService.SaveNow(player: Player): boolean
	local session = sessions[player]
	if not session or session.State ~= "Loaded" then
		return false
	end
	return saveSession(session, false)
end

--[[
	STUDIO ONLY (DebugService "ResetData"). Replaces the player's data with a
	fresh template in memory; the next save persists it (Mock backend: never).
	Refuses to run in live servers.
]]
function DataService.ResetForTesting(player: Player): boolean
	if not RunService:IsStudio() then
		log:Error("ResetForTesting refused outside Studio")
		return false
	end
	local session = sessions[player]
	if not session or session.State ~= "Loaded" then
		return false
	end
	local fresh = DataTemplate.Create(os.time())
	session.Data = fresh
	sendSnapshot(session)
	DataService.DataReset:Fire(player, fresh)
	log:Warn(string.format("user=%d data reset for testing", session.UserId))
	return true
end

function DataService.IsUsingMockBackend(): boolean
	return usingMock
end

-- ─── Lifecycle ──────────────────────────────────────────────────────────────

function DataService.Init()
	local backend: DataStoreBackend.Backend
	if RunService:IsStudio() and DataConfig.StudioBackend == "Mock" then
		usingMock = true
		backend = MockDataStoreBackend.new()
		log:Warn("USING MockDataStoreBackend — NOTHING WILL BE SAVED (Studio only; DataConfig.StudioBackend)")
	else
		backend = DataStoreBackend.new(DataConfig.StoreName)
	end

	store = PlayerDataStore.new(backend, {
		DataVersion = DataConfig.DataVersion,
		CreateTemplate = DataTemplate.Create,
		StaleLockSeconds = DataConfig.Session.StaleLockSeconds,
		LockRetryAttempts = DataConfig.Session.LockRetryAttempts,
		LockRetryDelaySeconds = DataConfig.Session.LockRetryDelaySeconds,
		LoadMaxAttempts = DataConfig.Load.MaxAttempts,
		LoadRetryBaseDelaySeconds = DataConfig.Load.RetryBaseDelaySeconds,
		SaveMaxAttempts = DataConfig.Save.MaxAttempts,
		SaveRetryBaseDelaySeconds = DataConfig.Save.RetryBaseDelaySeconds,
		PlaceId = game.PlaceId,
		JobId = game.JobId,
	})

	NetService.SetReadyPredicate(DataService.IsLoaded)

	NetService.On("ClientReady", Guard.Args(), function(player: Player)
		local session = sessions[player]
		if not session then
			log:Debug(string.format("user=%d ClientReady before session exists", player.UserId))
			readyBeforeSession[player] = true
			return
		end
		if session.ClientReady then
			return
		end
		log:Debug(string.format("user=%d ClientReady received (state=%s, %.2fs after join)", player.UserId, session.State, os.clock() - session.JoinedAt))
		session.ClientReady = true
		if session.State == "Loaded" then
			sendSnapshot(session)
		end
	end)
end

function DataService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	game:BindToClose(onClose)

	-- Autosave: each session saves once per interval, naturally staggered by join time.
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_CHECK_SECONDS)
			if shuttingDown then
				break
			end
			local now = os.clock()
			for _, session in sessions do
				if session.State == "Loaded" and not session.Saving and now - session.LastSaveAt >= DataConfig.AutosaveIntervalSeconds then
					task.spawn(saveSession, session, false)
				end
			end
		end
	end)

	-- Batched replication of changed keys.
	task.spawn(function()
		while true do
			task.wait(GameConfig.Replication.FlushIntervalSeconds)
			for session in dirtySessions do
				dirtySessions[session] = nil
				local data = session.Data
				if session.State == "Loaded" and session.ClientReady and data then
					for key in session.DirtyKeys do
						NetService.FireClient("DataChanged", session.Player, key, (data :: any)[key])
					end
				end
				table.clear(session.DirtyKeys)
			end
		end
	end)
end

return DataService
