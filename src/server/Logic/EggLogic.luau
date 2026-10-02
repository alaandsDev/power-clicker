--!strict
--[[
	EggLogic
	Pure, atomic egg hatching. Order matters for integrity:
		1. egg exists and is enabled
		2. egg's world is unlocked
		3. egg's tower stage has been cleared once (RequiredStage)
		4. inventory has space        (checked BEFORE charging)
		5. player can afford it
		5. charge → roll (server RNG) → add pet → stats
	Nothing yields; either everything happens or nothing does.
	The RNG is injected: production passes a server-side Random; tests pass
	deterministic sequences. The client never chooses or sees the roll.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local EggConfig = require(Shared.Config.EggConfig)
local PetConfig = require(Shared.Config.PetConfig)
local EggOdds = require(Shared.Formulas.EggOdds)
local CurrencyLogic = require(script.Parent.CurrencyLogic)
local PetLogic = require(script.Parent.PetLogic)

type PlayerData = Types.PlayerData

export type HatchResult = {
	Uid: string,
	PetId: string,
	Variant: string,
	Rarity: string,
	EggId: string,
	Price: number,
	Currency: string,
}

local RARITY_STAT: { [string]: string } = {
	Legendary = "LegendaryHatched",
	Mythic = "MythicHatched",
}

local EggLogic = {}

-- Codes: "UnknownEgg" | "WorldLocked" | "WrongWorld" | "StageLocked" | "InventoryFull" | "NotEnoughCurrency" | "NoDrops"
function EggLogic.Hatch(data: PlayerData, eggId: string, luck: number, roll: () -> number, now: number): (boolean, string?, HatchResult?)
	local egg = EggConfig.Eggs[eggId]
	if not egg or not egg.Enabled then
		return false, "UnknownEgg"
	end
	if not data.Worlds.Unlocked[egg.WorldId] then
		return false, "WorldLocked"
	end
	if data.Worlds.Current ~= egg.WorldId then
		return false, "WrongWorld" -- eggs are opened in their own world
	end
	--[[
		Ovos ligados à torre: só abrem depois de o estágio cair uma vez. É o que
		faz o ovo acompanhar a progressão, e não só o saldo de gemas.
	]]
	local stage = egg.RequiredStage
	if stage and data.Tower.Cleared[stage] ~= true then
		return false, "StageLocked"
	end
	if PetLogic.Count(data) >= PetLogic.GetInventoryCapacity(data) then
		return false, "InventoryFull"
	end
	local weights = EggOdds.Weights(egg, luck)
	local petId = EggOdds.Pick(weights, roll())
	if not petId then
		return false, "NoDrops"
	end
	if not CurrencyLogic.Remove(data, egg.Currency, egg.Price) then
		return false, "NotEnoughCurrency"
	end

	local added, code, uid = PetLogic.Add(data, petId, "Normal", now)
	if not added or not uid then
		-- Cannot happen after the capacity check above; refund to stay atomic.
		CurrencyLogic.Add(data, egg.Currency, egg.Price)
		return false, code or "InventoryFull"
	end

	local rarity = PetConfig.Pets[petId].Rarity
	data.Stats.EggsOpened += 1
	local stat = RARITY_STAT[rarity]
	if stat then
		local stats = data.Stats :: any
		stats[stat] = (stats[stat] or 0) + 1
	end
	local result: HatchResult = {
		Uid = uid,
		PetId = petId,
		Variant = "Normal",
		Rarity = rarity,
		EggId = eggId,
		Price = egg.Price,
		Currency = egg.Currency,
	}
	return true, nil, result
end

return EggLogic
