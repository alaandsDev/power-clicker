local Shared = game:GetService("ReplicatedStorage").Shared
local CutLogic = require(Shared.Formulas.CutLogic)
local CutConfig = require(Shared.Config.CutConfig)

local function secondCut()
	local ordered = CutLogic.Ordered()
	return ordered[2]
end

return function(T)
	T.describe("CutLogic", function()
		T.it("starts with the starter cut and its damage", function()
			local cuts = CutLogic.Fresh()
			T.expect(CutLogic.Best(cuts).Id).toBe(CutConfig.StarterCut)
			T.expect(CutLogic.FlatBonus(cuts)).toBe(CutConfig.Cuts[CutConfig.StarterCut].Flat)
		end)

		T.it("asks for the wins before selling a cut", function()
			local cuts = CutLogic.Fresh()
			local cut = secondCut()
			local allowed, reason = CutLogic.CanBuy(cuts, cut.Id, cut.RequiredWins - 1)
			T.expect(allowed).toBe(false)
			T.expect(reason).toBe("NeedsWins")
			T.expect(CutLogic.CanBuy(cuts, cut.Id, cut.RequiredWins)).toBe(true)
		end)

		T.it("refuses to sell the same cut twice", function()
			local cuts = CutLogic.Fresh()
			local cut = secondCut()
			cuts.Owned[cut.Id] = true
			local allowed, reason = CutLogic.CanBuy(cuts, cut.Id, cut.RequiredWins)
			T.expect(allowed).toBe(false)
			T.expect(reason).toBe("AlreadyOwned")
		end)

		T.it("uses the best cut owned, whatever order they were bought in", function()
			local cuts = CutLogic.Fresh()
			local ordered = CutLogic.Ordered()
			local last = ordered[#ordered]
			cuts.Owned[last.Id] = true
			cuts.Owned[ordered[2].Id] = true
			T.expect(CutLogic.Best(cuts).Id).toBe(last.Id)
			T.expect(CutLogic.FlatBonus(cuts)).toBe(last.Flat)
		end)

		T.it("every cut is stronger and dearer than the one before", function()
			local ordered = CutLogic.Ordered()
			for index = 2, #ordered do
				T.expect(ordered[index].Flat > ordered[index - 1].Flat).toBe(true)
				T.expect(ordered[index].Price > ordered[index - 1].Price).toBe(true)
				T.expect(ordered[index].RequiredWins >= ordered[index - 1].RequiredWins).toBe(true)
			end
		end)

		T.it("repairs a record with a cut that no longer exists", function()
			local cuts = { Owned = { Ghost = true } }
			T.expect(CutLogic.Sanitize(cuts :: any) > 0).toBe(true)
			T.expect(cuts.Owned.Ghost).toBe(nil)
			T.expect(cuts.Owned[CutConfig.StarterCut]).toBe(true)
		end)
	end)
end
