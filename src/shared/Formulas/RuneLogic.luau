--!strict
--[[
	RuneLogic
	Pure rune rules: the inventory, the equipped slots, what they multiply, and
	the drop roll.

	The roll takes its random numbers as an argument so the server can use a
	real Random and the tests can feed a fixed sequence — the odds are the
	config's, never the caller's.
]]

local Shared = script.Parent.Parent
local Types = require(Shared.Types)
local RuneConfig = require(Shared.Config.RuneConfig)

type RunesData = Types.RunesData
type RuneData = Types.RuneData

local RuneLogic = {}

function RuneLogic.Fresh(): RunesData
	return { Owned = {}, Equipped = {} }
end

function RuneLogic.Get(runeId: string): RuneData?
	return RuneConfig.Runes[runeId]
end

-- Every rune of a world, weakest first (the UI lists them by world).
function RuneLogic.OfWorld(worldId: string): { RuneData }
	local list: { RuneData } = {}
	for _, rune in RuneConfig.Runes do
		if rune.WorldId == worldId then
			table.insert(list, rune)
		end
	end
	table.sort(list, function(a, b)
		return a.Order < b.Order
	end)
	return list
end

function RuneLogic.Count(runes: RunesData, runeId: string): number
	local count = runes.Owned[runeId]
	return if type(count) == "number" and count > 0 then math.floor(count) else 0
end

-- How many copies of `runeId` are sitting in slots right now.
function RuneLogic.EquippedCount(runes: RunesData, runeId: string): number
	local count = 0
	for _, id in runes.Equipped do
		if id == runeId then
			count += 1
		end
	end
	return count
end

-- Adds copies from a trusted source (a boss drop). Returns the new count.
function RuneLogic.Add(runes: RunesData, runeId: string, count: number?): number
	if not RuneConfig.Runes[runeId] then
		return 0
	end
	local amount = math.max(math.floor(count or 1), 1)
	local total = math.min(RuneLogic.Count(runes, runeId) + amount, RuneConfig.MaxOwnedPerRune)
	runes.Owned[runeId] = total
	return total
end

--[[
	Puts a rune in a free slot. A rune may fill more than one slot, but never
	more often than the player owns it. Returns (false, code) when it cannot.
]]
function RuneLogic.Equip(runes: RunesData, runeId: string): (boolean, string?)
	if not RuneConfig.Runes[runeId] then
		return false, "InvalidRequest"
	end
	if #runes.Equipped >= RuneConfig.Slots then
		return false, "NoSlots"
	end
	if RuneLogic.EquippedCount(runes, runeId) >= RuneLogic.Count(runes, runeId) then
		return false, "NotOwned"
	end
	table.insert(runes.Equipped, runeId)
	return true, nil
end

-- Frees slot `index` (1-based). Returns (false, code) for an empty slot.
function RuneLogic.UnequipSlot(runes: RunesData, index: number): (boolean, string?)
	if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > #runes.Equipped then
		return false, "InvalidRequest"
	end
	table.remove(runes.Equipped, index)
	return true, nil
end

function RuneLogic.UnequipAll(runes: RunesData)
	table.clear(runes.Equipped)
end

-- "Rune" layer of PowerFormula: the equipped runes multiplied together.
function RuneLogic.Multiplier(runes: RunesData): number
	local total = 1
	for _, runeId in runes.Equipped do
		local rune = RuneConfig.Runes[runeId]
		if rune then
			total *= rune.PowerMultiplier
		end
	end
	return total
end

--[[
	Rolls a boss drop for a player who did `share` (0..1) of the damage in
	`worldId`. `roll` returns a number in [0, 1) — one call decides whether
	anything drops, the next picks the rarity.
	Returns the rune id, or nil when nothing dropped.
]]
function RuneLogic.Roll(worldId: string, share: number, roll: () -> number): string?
	local drop = RuneConfig.Drop
	local clamped = math.clamp(if share == share then share else 0, 0, 1)
	if clamped < drop.MinShare then
		return nil
	end
	-- Between MinChance (just qualified) and MaxChance (did it alone).
	local progress = (clamped - drop.MinShare) / math.max(1 - drop.MinShare, 1e-6)
	local chance = drop.MinChance + (drop.MaxChance - drop.MinChance) * progress
	if roll() >= chance then
		return nil
	end

	local candidates = RuneLogic.OfWorld(worldId)
	if #candidates == 0 then
		return nil
	end
	-- A bigger share tilts the draw towards the rare tiers; it never removes
	-- the common ones.
	local weights: { number } = {}
	local total = 0
	for index, rune in candidates do
		local bonus = if rune.Weight < RuneConfig.Tiers[1].Weight then 1 + clamped * drop.ShareBonus else 1
		local weight = rune.Weight * bonus
		weights[index] = weight
		total += weight
	end
	local pick = roll() * total
	for index, rune in candidates do
		pick -= weights[index]
		if pick <= 0 then
			return rune.Id
		end
	end
	return candidates[#candidates].Id
end

--[[
	Repairs a loaded record: drops unknown ids, floors the counts and removes
	equipped runes the player does not own (or that overflow the slots).
	Returns how many problems were fixed.
]]
function RuneLogic.Sanitize(runes: RunesData): number
	local fixes = 0
	if type(runes.Owned) ~= "table" then
		runes.Owned = {}
		fixes += 1
	end
	if type(runes.Equipped) ~= "table" then
		runes.Equipped = {}
		fixes += 1
	end
	for runeId, count in runes.Owned do
		if not RuneConfig.Runes[runeId] or type(count) ~= "number" or count < 1 then
			runes.Owned[runeId] = nil
			fixes += 1
		elseif count % 1 ~= 0 or count > RuneConfig.MaxOwnedPerRune then
			runes.Owned[runeId] = math.clamp(math.floor(count), 1, RuneConfig.MaxOwnedPerRune)
			fixes += 1
		end
	end
	local kept: { string } = {}
	local used: { [string]: number } = {}
	for _, runeId in runes.Equipped do
		local owned = RuneLogic.Count(runes, runeId)
		local already = used[runeId] or 0
		if RuneConfig.Runes[runeId] and already < owned and #kept < RuneConfig.Slots then
			table.insert(kept, runeId)
			used[runeId] = already + 1
		else
			fixes += 1
		end
	end
	runes.Equipped = kept
	return fixes
end

return RuneLogic
