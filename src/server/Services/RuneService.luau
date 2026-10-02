--!strict
--[[
	RuneService
	Owns the rune inventory, the equipped slots and the "Rune" power layer.

	Runes come from ONE place: beating a world boss. BossService.Defeated
	carries each player's damage share, and the roll happens here with a
	server-side Random — the client is only told what it got.

	"RuneAction"(action, value) — "Equip" takes a rune id, "Unequip" a slot
	number (1..Slots), "UnequipAll" ignores it. Every action re-checks the
	inventory, so a client can never equip a rune it does not own or fill more
	slots than the config allows.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Guard = require(Shared.Utils.Guard)
local Logger = require(Shared.Utils.Logger)
local RuneConfig = require(Shared.Config.RuneConfig)
local RuneLogic = require(Shared.Formulas.RuneLogic)

local NetService = require(script.Parent.NetService)
local DataService = require(script.Parent.DataService)
local PowerService = require(script.Parent.PowerService)
local BossService = require(script.Parent.BossService)

type RemoteResponse = Types.RemoteResponse
type PlayerData = Types.PlayerData

local ACTIONS = { "Equip", "Unequip", "UnequipAll" }
local RUNE_ID_MAX_LENGTH = 32

local log = Logger.new("Rune")

local RuneService = {}

local random = Random.new()

local function changed(player: Player, _data: PlayerData)
	DataService.MarkChanged(player, "Runes")
	PowerService.Invalidate(player)
end

-- Adds a rune from a trusted server source (boss drop, reward, admin).
function RuneService.Grant(player: Player, runeId: string, source: string): boolean
	local data = DataService.GetData(player)
	if not data or not RuneConfig.Runes[runeId] then
		return false
	end
	local total = RuneLogic.Add(data.Runes, runeId)
	changed(player, data)
	NetService.FireClient("Notify", player, "RuneDropped", { RuneId = runeId, Total = total })
	log:Info(string.format("user=%d got rune %s (%d) from %s", player.UserId, runeId, total, source))
	return true
end

-- Rolls the boss drop for one participant. Returns the rune id, or nil.
local function rollDrop(player: Player, share: number): string?
	local data = DataService.GetData(player)
	if not data then
		return nil
	end
	local runeId = RuneLogic.Roll(data.Worlds.Current, share, function()
		return random:NextNumber()
	end)
	if runeId then
		RuneService.Grant(player, runeId, "Boss")
	end
	return runeId
end

local function handleAction(player: Player, action: string, value: (string | number)?): RemoteResponse
	local data = DataService.GetData(player)
	if not data then
		return { Ok = false, Code = "NotReady" }
	end
	local ok: boolean, code: string? = false, nil
	if action == "UnequipAll" then
		RuneLogic.UnequipAll(data.Runes)
		ok = true
	elseif action == "Equip" then
		ok, code = RuneLogic.Equip(data.Runes, if type(value) == "string" then value else "")
	elseif action == "Unequip" then
		ok, code = RuneLogic.UnequipSlot(data.Runes, if type(value) == "number" then value else 0)
	else
		return { Ok = false, Code = "InvalidRequest" }
	end
	if not ok then
		return { Ok = false, Code = code }
	end
	changed(player, data)
	return { Ok = true, Data = { Equipped = data.Runes.Equipped } }
end

function RuneService.Init()
	PowerService.RegisterProvider("Rune", function(_player, data)
		return RuneLogic.Multiplier(data.Runes)
	end)

	-- "Equip" sends a rune id (string), "Unequip" a slot number: one optional
	-- argument that may be either, each branch re-checked above.
	local isRuneId = Guard.String(RUNE_ID_MAX_LENGTH)
	local isSlot = Guard.Integer(1, RuneConfig.Slots)
	local function isValue(value: any): boolean
		return isRuneId(value) or isSlot(value)
	end
	NetService.OnInvoke("RuneAction", Guard.Args(Guard.OneOf(ACTIONS), Guard.Optional(isValue)), handleAction)

	BossService.Defeated:Connect(function(player: Player, _reward: number, share: number)
		rollDrop(player, share)
	end)

	DataService.PlayerLoaded:Connect(function(player: Player, data: PlayerData)
		local fixes = RuneLogic.Sanitize(data.Runes)
		if fixes > 0 then
			log:Warn(string.format("user=%d repaired %d rune issue(s)", player.UserId, fixes))
			DataService.MarkChanged(player, "Runes")
		end
	end)
end

function RuneService.Start()
	-- Players who joined before this service started still get their layer.
	for _, player in Players:GetPlayers() do
		PowerService.Invalidate(player)
	end
end

return RuneService
