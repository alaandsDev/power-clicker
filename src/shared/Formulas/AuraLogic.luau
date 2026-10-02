--!strict
--[[
	AuraLogic
	Pure aura rules: what a player owns, what they may buy, and what the
	equipped aura is worth (Power multiplier and walk speed).

	The server decides with these (AuraService); the UI shows the same answers
	from the replicated data, so a price or a bonus is never written twice.
]]

local Shared = script.Parent.Parent
local Types = require(Shared.Types)
local AuraConfig = require(Shared.Config.AuraConfig)

type AurasData = Types.AurasData
type AuraData = Types.AuraData

local AuraLogic = {}

-- A brand-new record: only the default (empty) aura, equipped.
function AuraLogic.Fresh(): AurasData
	return { Owned = { [AuraConfig.DefaultAura] = true }, Equipped = AuraConfig.DefaultAura }
end

function AuraLogic.Get(auraId: string): AuraData?
	return AuraConfig.Auras[auraId]
end

-- Ordered list (cheapest first) for the UI.
function AuraLogic.Ordered(): { AuraData }
	local list: { AuraData } = {}
	for _, aura in AuraConfig.Auras do
		table.insert(list, aura)
	end
	table.sort(list, function(a, b)
		return a.Order < b.Order
	end)
	return list
end

function AuraLogic.Owns(auras: AurasData, auraId: string): boolean
	return auras.Owned[auraId] == true
end

--[[
	Can this aura be bought right now? Returns (false, code) when not.
	The caller still has to check (and spend) the price.
]]
function AuraLogic.CanBuy(auras: AurasData, auraId: string, wins: number): (boolean, string?)
	local aura = AuraConfig.Auras[auraId]
	if not aura then
		return false, "InvalidRequest"
	end
	if AuraLogic.Owns(auras, auraId) then
		return false, "AlreadyOwned"
	end
	if wins < aura.RequiredWins then
		return false, "NeedsWins"
	end
	return true, nil
end

-- Equips an owned aura. Returns (false, code) when it is not owned.
function AuraLogic.Equip(auras: AurasData, auraId: string): (boolean, string?)
	if not AuraConfig.Auras[auraId] then
		return false, "InvalidRequest"
	end
	if not AuraLogic.Owns(auras, auraId) then
		return false, "NotOwned"
	end
	auras.Equipped = auraId
	return true, nil
end

-- The equipped aura, or the default one when the record is broken.
function AuraLogic.Equipped(auras: AurasData): AuraData
	local aura = AuraConfig.Auras[auras.Equipped]
	return aura or AuraConfig.Auras[AuraConfig.DefaultAura]
end

-- "Aura" layer of PowerFormula.
function AuraLogic.Multiplier(auras: AurasData): number
	return AuraLogic.Equipped(auras).PowerMultiplier
end

-- Walk speed the character should run at (always within the config cap).
function AuraLogic.WalkSpeed(auras: AurasData): number
	local speed = AuraConfig.BaseWalkSpeed + AuraLogic.Equipped(auras).WalkSpeedBonus
	return math.clamp(speed, AuraConfig.BaseWalkSpeed, AuraConfig.MaxWalkSpeed)
end

--[[
	Repairs a loaded record: drops unknown ids, re-adds the default aura and
	falls back to it when the equipped one is not owned. Returns how many
	problems were fixed (0 = the record was fine).
]]
function AuraLogic.Sanitize(auras: AurasData): number
	local fixes = 0
	if type(auras.Owned) ~= "table" then
		auras.Owned = {}
		fixes += 1
	end
	for auraId in auras.Owned do
		if not AuraConfig.Auras[auraId] then
			auras.Owned[auraId] = nil
			fixes += 1
		end
	end
	if not auras.Owned[AuraConfig.DefaultAura] then
		auras.Owned[AuraConfig.DefaultAura] = true
		fixes += 1
	end
	if type(auras.Equipped) ~= "string" or not AuraLogic.Owns(auras, auras.Equipped) then
		auras.Equipped = AuraConfig.DefaultAura
		fixes += 1
	end
	return fixes
end

return AuraLogic
