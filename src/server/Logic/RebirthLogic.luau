--!strict
--[[
	RebirthLogic
	Pure rebirth rules (RebirthConfig). Atomic: either everything below
	happens or nothing does.

	1. Require Power >= RebirthCost(rebirths, anchor) and rebirths < MaxRebirths.
	2. Reset what RebirthConfig.Resets says (Power, temporary upgrades, ...).
	3. rebirths += 1 and grant RebirthGems(previous rebirths).

	The cost is NOT removed separately: Power is reset to 0 as the price.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local RebirthConfig = require(Shared.Config.RebirthConfig)
local EconomyFormulas = require(Shared.Formulas.EconomyFormulas)
local CurrencyLogic = require(script.Parent.CurrencyLogic)
local UpgradeLogic = require(script.Parent.UpgradeLogic)

type PlayerData = Types.PlayerData

-- Failure codes: "MaxRebirths" | "NotEnoughCurrency"
export type RebirthResult = { Rebirths: number, Gems: number }

local RebirthLogic = {}

-- Leitura saneada do Stats: a mesma função que o cliente usa (EconomyFormulas).
function RebirthLogic.GetRebirths(data: PlayerData): number
	return EconomyFormulas.RebirthsOf(data.Stats)
end

-- Âncora do C2-E (Stats.RebirthAnchor); 0 para saves novos ou inválidos.
function RebirthLogic.GetAnchor(data: PlayerData): number
	return EconomyFormulas.RebirthAnchorOf(data.Stats)
end

function RebirthLogic.GetCost(data: PlayerData): number
	return EconomyFormulas.RebirthCostFor(data.Stats)
end

function RebirthLogic.CanRebirth(data: PlayerData): (boolean, string?)
	local rebirths = RebirthLogic.GetRebirths(data)
	if rebirths >= RebirthConfig.MaxRebirths then
		return false, "MaxRebirths"
	end
	if CurrencyLogic.Get(data, RebirthConfig.Currency) < RebirthLogic.GetCost(data) then
		return false, "NotEnoughCurrency"
	end
	return true, nil
end

-- Mutates `data`. Returns (true, nil, result) or (false, code).
function RebirthLogic.Perform(data: PlayerData): (boolean, string?, RebirthResult?)
	local allowed, code = RebirthLogic.CanRebirth(data)
	if not allowed then
		return false, code
	end
	local previous = RebirthLogic.GetRebirths(data)
	local gems = EconomyFormulas.RebirthGems(previous)

	if RebirthConfig.Resets.Power then
		CurrencyLogic.Reset(data, "Power")
	end
	if RebirthConfig.Resets.TemporaryUpgrades then
		UpgradeLogic.ResetTemporary(data)
	end
	if RebirthConfig.Resets.OverdriveCharge then
		data.Overdrive.Charge = 0
	end

	data.Stats.Rebirths = previous + 1
	local granted = if gems > 0 then CurrencyLogic.Add(data, "Gems", gems) else 0
	return true, nil, { Rebirths = previous + 1, Gems = granted }
end

return RebirthLogic
