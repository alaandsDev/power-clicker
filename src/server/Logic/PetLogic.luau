--!strict
--[[
	PetLogic
	Pure pet inventory rules over PlayerData.Pets. The inventory is keyed by a
	server-generated uid (string of an ever-increasing counter), so a pet can
	never be duplicated by the client: clients only ever reference uids that
	already exist in THEIR server-side inventory.

	Invariants kept by every function here (and restored by Sanitize):
	- Equipped contains only uids present in Inventory, no duplicates,
	  at most `capacity` entries.
	- NextUid is greater than every numeric uid in Inventory.
	Pets whose PetId no longer exists in config are KEPT (never delete player
	items) but contribute nothing and cannot be equipped.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local PetConfig = require(Shared.Config.PetConfig)
local UpgradeLogic = require(script.Parent.UpgradeLogic)

type PlayerData = Types.PlayerData
type PetInstance = Types.PetInstance

local PetLogic = {}

function PetLogic.GetEquipCapacity(data: PlayerData, extraSlots: number?): number
	local slots = PetConfig.BaseEquipSlots + UpgradeLogic.GetEffect(data, "Permanent", "EquipSlots") + (extraSlots or 0)
	return math.clamp(math.floor(slots), 1, PetConfig.MaxEquipSlots)
end

function PetLogic.GetInventoryCapacity(data: PlayerData): number
	local slots = PetConfig.BaseInventorySlots + UpgradeLogic.GetEffect(data, "Permanent", "InventorySlots")
	return math.clamp(math.floor(slots), 1, PetConfig.MaxInventorySlots)
end

function PetLogic.Count(data: PlayerData): number
	local count = 0
	for _ in data.Pets.Inventory do
		count += 1
	end
	return count
end

function PetLogic.IsEquipped(data: PlayerData, uid: string): boolean
	return table.find(data.Pets.Equipped, uid) ~= nil
end

-- Bonus of one owned pet (0 for unknown pets/variants).
function PetLogic.GetBonus(pet: PetInstance): number
	local config = PetConfig.Pets[pet.PetId]
	local variant = PetConfig.Variants[pet.Variant]
	if not config or not variant then
		return 0
	end
	return config.Bonus * variant.MultiplierScale
end

-- Power multiplier from equipped pets: 1 + Σ bonus.
function PetLogic.GetMultiplier(data: PlayerData): number
	local total = 1
	for _, uid in data.Pets.Equipped do
		local pet = data.Pets.Inventory[uid]
		if pet then
			total += PetLogic.GetBonus(pet)
		end
	end
	return total
end

-- Adds a new pet. Returns (true, nil, uid) or (false, code).
-- Codes: "UnknownPet" | "UnknownVariant" | "InventoryFull"
-- ignoreCapacity: ONLY for paid purchases (a player who paid always receives
-- the item even with a full inventory).
function PetLogic.Add(data: PlayerData, petId: string, variant: string?, now: number, ignoreCapacity: boolean?): (boolean, string?, string?)
	if not PetConfig.Pets[petId] then
		return false, "UnknownPet"
	end
	local variantId = variant or "Normal"
	local variantConfig = PetConfig.Variants[variantId]
	if not variantConfig or not variantConfig.Enabled then
		return false, "UnknownVariant"
	end
	if not ignoreCapacity and PetLogic.Count(data) >= PetLogic.GetInventoryCapacity(data) then
		return false, "InventoryFull"
	end

	local pets = data.Pets
	local nextUid = math.max(1, math.floor(tonumber(pets.NextUid) or 1))
	while pets.Inventory[tostring(nextUid)] ~= nil do
		nextUid += 1 -- never overwrite an existing pet
	end
	local uid = tostring(nextUid)
	pets.Inventory[uid] = {
		PetId = petId,
		Variant = variantId :: any,
		Locked = false,
		ObtainedAt = now,
	}
	pets.NextUid = nextUid + 1
	return true, nil, uid
end

-- Codes: "NotOwned" | "AlreadyEquipped" | "UnknownPet" | "EquipFull"
function PetLogic.Equip(data: PlayerData, uid: string, capacity: number): (boolean, string?)
	local pet = data.Pets.Inventory[uid]
	if not pet then
		return false, "NotOwned"
	end
	if PetLogic.IsEquipped(data, uid) then
		return false, "AlreadyEquipped"
	end
	if not PetConfig.Pets[pet.PetId] then
		return false, "UnknownPet"
	end
	if #data.Pets.Equipped >= capacity then
		return false, "EquipFull"
	end
	table.insert(data.Pets.Equipped, uid)
	return true, nil
end

-- Codes: "NotEquipped"
function PetLogic.Unequip(data: PlayerData, uid: string): (boolean, string?)
	local index = table.find(data.Pets.Equipped, uid)
	if not index then
		return false, "NotEquipped"
	end
	table.remove(data.Pets.Equipped, index)
	return true, nil
end

-- Equips the strongest pets up to capacity. Returns the new equipped count.
function PetLogic.EquipBest(data: PlayerData, capacity: number): number
	local candidates: { { Uid: string, Bonus: number } } = {}
	for uid, pet in data.Pets.Inventory do
		if PetConfig.Pets[pet.PetId] then
			table.insert(candidates, { Uid = uid, Bonus = PetLogic.GetBonus(pet) })
		end
	end
	table.sort(candidates, function(a, b)
		if a.Bonus == b.Bonus then
			return a.Uid < b.Uid -- deterministic
		end
		return a.Bonus > b.Bonus
	end)
	local equipped = {}
	for i = 1, math.min(capacity, #candidates) do
		equipped[i] = candidates[i].Uid
	end
	data.Pets.Equipped = equipped
	return #equipped
end

-- Codes: "NotOwned" | "Locked"
function PetLogic.Delete(data: PlayerData, uid: string): (boolean, string?)
	local pet = data.Pets.Inventory[uid]
	if not pet then
		return false, "NotOwned"
	end
	if pet.Locked then
		return false, "Locked"
	end
	PetLogic.Unequip(data, uid)
	data.Pets.Inventory[uid] = nil
	return true, nil
end

-- Codes: "NotOwned"
function PetLogic.SetLocked(data: PlayerData, uid: string, locked: boolean): (boolean, string?)
	local pet = data.Pets.Inventory[uid]
	if not pet then
		return false, "NotOwned"
	end
	pet.Locked = locked
	return true, nil
end

-- Repairs invariants (run on load). Returns the number of fixes made.
function PetLogic.Sanitize(data: PlayerData, capacity: number): number
	local pets = data.Pets
	local fixes = 0
	local seen: { [string]: boolean } = {}
	local cleaned: { string } = {}
	for _, uid in pets.Equipped do
		local pet = pets.Inventory[uid]
		if type(uid) == "string" and pet and not seen[uid] and PetConfig.Pets[pet.PetId] and #cleaned < capacity then
			seen[uid] = true
			table.insert(cleaned, uid)
		else
			fixes += 1
		end
	end
	pets.Equipped = cleaned

	local highest = 0
	for uid in pets.Inventory do
		local number = tonumber(uid)
		if number and number > highest then
			highest = number
		end
	end
	if (tonumber(pets.NextUid) or 0) <= highest then
		pets.NextUid = highest + 1
		fixes += 1
	end
	return fixes
end

return PetLogic
