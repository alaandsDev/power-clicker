--!strict
--[[
	PetService
	Owns pet inventory changes (via PetLogic) and the "Pet" power layer.

	"PetAction"(action, uid?) — every action re-validates on the server that
	the uid exists in THIS player's inventory; the client can't invent pets,
	duplicate them, or exceed equip/inventory limits.

	Other systems add pets through PetService.Grant (eggs, rewards, products).
	Extra equip slots from game passes (Phase 6) are fed via
	PetService.SetExtraEquipSlots.

	Equipped pet ids are mirrored to a player attribute ("EquippedPets") so
	every client can render other players' pets without extra remotes.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Guard = require(Shared.Utils.Guard)
local Logger = require(Shared.Utils.Logger)
local Signal = require(Shared.Utils.Signal)

local NetService = require(script.Parent.NetService)
local DataService = require(script.Parent.DataService)
local PowerService = require(script.Parent.PowerService)
local PetLogic = require(script.Parent.Parent.Logic.PetLogic)

type RemoteResponse = Types.RemoteResponse
type PlayerData = Types.PlayerData

local ACTIONS = { "Equip", "Unequip", "EquipBest", "Delete", "Lock", "Unlock" }
local UID_MAX_LENGTH = 12
local ATTRIBUTE = "EquippedPets"

local log = Logger.new("Pets")

local PetService = {
	-- (player, uid, petId, source)
	PetGranted = Signal.new() :: Signal.Signal<Player, string, string, string>,
}

local extraSlots: { [Player]: number } = {}

function PetService.GetEquipCapacity(player: Player): number
	local data = DataService.GetData(player)
	return if data then PetLogic.GetEquipCapacity(data, extraSlots[player]) else 0
end

local function publishEquipped(player: Player, data: PlayerData)
	local ids = {}
	for _, uid in data.Pets.Equipped do
		local pet = data.Pets.Inventory[uid]
		if pet then
			table.insert(ids, pet.PetId)
		end
	end
	player:SetAttribute(ATTRIBUTE, table.concat(ids, ","))
	-- Display-only mirrors of server-computed limits (the server enforces them).
	player:SetAttribute("EquipCapacity", PetLogic.GetEquipCapacity(data, extraSlots[player]))
	player:SetAttribute("InventoryCapacity", PetLogic.GetInventoryCapacity(data))
end

local function changed(player: Player, data: PlayerData)
	DataService.MarkChanged(player, "Pets")
	PowerService.Invalidate(player)
	publishEquipped(player, data)
end

-- Adds a pet from a trusted server source (egg, reward, product).
-- Returns (true, nil, uid) or (false, code).
function PetService.Grant(player: Player, petId: string, variant: string?, source: string): (boolean, string?, string?)
	local data = DataService.GetData(player)
	if not data then
		return false, "NotReady"
	end
	local ok, code, uid = PetLogic.Add(data, petId, variant, os.time())
	if not ok or not uid then
		return false, code
	end
	changed(player, data)
	PetService.PetGranted:Fire(player, uid, petId, source)
	return true, nil, uid
end

-- For services that already mutated data via PetLogic (e.g. EggLogic).
function PetService.NotifyChanged(player: Player)
	local data = DataService.GetData(player)
	if data then
		changed(player, data)
	end
end

function PetService.SetExtraEquipSlots(player: Player, slots: number)
	extraSlots[player] = math.max(0, math.floor(slots))
	PetService.NotifyChanged(player)
end

local function handleAction(player: Player, action: string, uid: string?): RemoteResponse
	local data = DataService.GetData(player)
	if not data then
		return { Ok = false, Code = "NotReady" }
	end
	local capacity = PetLogic.GetEquipCapacity(data, extraSlots[player])

	local ok: boolean, code: string? = false, nil
	if action == "EquipBest" then
		PetLogic.EquipBest(data, capacity)
		ok = true
	elseif not uid then
		return { Ok = false, Code = "InvalidRequest" }
	elseif action == "Equip" then
		ok, code = PetLogic.Equip(data, uid, capacity)
	elseif action == "Unequip" then
		ok, code = PetLogic.Unequip(data, uid)
	elseif action == "Delete" then
		ok, code = PetLogic.Delete(data, uid)
	elseif action == "Lock" or action == "Unlock" then
		ok, code = PetLogic.SetLocked(data, uid, action == "Lock")
	else
		return { Ok = false, Code = "InvalidRequest" }
	end

	if not ok then
		return { Ok = false, Code = code }
	end
	changed(player, data)
	return { Ok = true }
end

function PetService.Init()
	PowerService.RegisterProvider("Pet", function(_player, data)
		return PetLogic.GetMultiplier(data)
	end)

	NetService.OnInvoke(
		"PetAction",
		Guard.Args(Guard.OneOf(ACTIONS), Guard.Optional(Guard.String(UID_MAX_LENGTH))),
		handleAction
	)

	DataService.PlayerLoaded:Connect(function(player, data)
		local fixes = PetLogic.Sanitize(data, PetLogic.GetEquipCapacity(data, extraSlots[player]))
		if fixes > 0 then
			log:Warn(string.format("user=%d repaired %d pet inventory issue(s)", player.UserId, fixes))
		end
		publishEquipped(player, data)
	end)
	DataService.DataReset:Connect(function(player, data)
		publishEquipped(player, data)
	end)
	Players.PlayerRemoving:Connect(function(player)
		extraSlots[player] = nil
	end)
end

return PetService
