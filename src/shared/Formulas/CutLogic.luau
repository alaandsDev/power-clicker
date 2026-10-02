--!strict
--[[
	CutLogic
	Pure rules for the cut pads: what a player owns, what they may buy, and how
	much raw damage the best cut they own adds to a click.

	The server decides with these (CutService); the UI and the world signs read
	the same answers, so a price exists in exactly one place.
]]

local Shared = script.Parent.Parent
local Types = require(Shared.Types)
local CutConfig = require(Shared.Config.CutConfig)

type CutsData = Types.CutsData
type CutData = Types.CutData

local CutLogic = {}

function CutLogic.Fresh(): CutsData
	return { Owned = { [CutConfig.StarterCut] = true } }
end

function CutLogic.Get(cutId: string): CutData?
	return CutConfig.Cuts[cutId]
end

-- Cheapest first (the order the pads stand in).
function CutLogic.Ordered(): { CutData }
	local list: { CutData } = {}
	for _, cut in CutConfig.Cuts do
		table.insert(list, cut)
	end
	table.sort(list, function(a, b)
		return a.Order < b.Order
	end)
	return list
end

function CutLogic.Owns(cuts: CutsData, cutId: string): boolean
	return cuts.Owned[cutId] == true
end

--[[
	Can this cut be bought right now? Returns (false, code) when not.
	The caller still has to charge the price.
]]
function CutLogic.CanBuy(cuts: CutsData, cutId: string, wins: number): (boolean, string?)
	local cut = CutConfig.Cuts[cutId]
	if not cut then
		return false, "InvalidRequest"
	end
	if CutLogic.Owns(cuts, cutId) then
		return false, "AlreadyOwned"
	end
	if wins < cut.RequiredWins then
		return false, "NeedsWins"
	end
	return true, nil
end

-- The best cut owned (there is nothing to equip: owning is using).
function CutLogic.Best(cuts: CutsData): CutData
	local best = CutConfig.Cuts[CutConfig.StarterCut]
	for cutId in cuts.Owned do
		local cut = CutConfig.Cuts[cutId]
		if cut and cut.Flat > best.Flat then
			best = cut
		end
	end
	return best
end

-- Flat damage the cut adds to the base of PowerFormula.
function CutLogic.FlatBonus(cuts: CutsData): number
	return CutLogic.Best(cuts).Flat
end

--[[
	Repairs a loaded record: drops unknown ids and puts the starter cut back.
	Returns how many problems were fixed (0 = the record was fine).
]]
function CutLogic.Sanitize(cuts: CutsData): number
	local fixes = 0
	if type(cuts.Owned) ~= "table" then
		cuts.Owned = {}
		fixes += 1
	end
	for cutId in cuts.Owned do
		if not CutConfig.Cuts[cutId] then
			cuts.Owned[cutId] = nil
			fixes += 1
		end
	end
	if not cuts.Owned[CutConfig.StarterCut] then
		cuts.Owned[CutConfig.StarterCut] = true
		fixes += 1
	end
	return fixes
end

return CutLogic
