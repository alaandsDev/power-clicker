--[[
	Pads de vitória: o pad "x2" tem de pagar o dobro do normal em TODA situação
	(regressão: repetindo a barreira de madeira, os dois pagavam 1).
]]
local Shared = game:GetService("ReplicatedStorage").Shared
local WallConfig = require(Shared.Config.WallConfig)
local WinPadRules = require(Shared.Formulas.WinPadRules)

local wood = WallConfig.Stages[1]

return function(T)
	T.describe("WinPadRules", function()
		T.it("first clear pays the full pad values (1 and 2 on wood)", function()
			local share = WinPadRules.Share(wood, { Cleared = {}, Highest = 0 }, true)
			T.expect(share).toBe(1)
			T.expect(WinPadRules.Payout(wood, 1, share)).toBe(wood.Pads[1])
			T.expect(WinPadRules.Payout(wood, 2, share)).toBe(wood.Pads[2])
		end)

		T.it("first clear is full even though Tower already marks the stage", function()
			-- O servidor registra a conquista antes do toque no pad.
			local tower = { Cleared = { [wood.Id] = true }, Highest = 1 }
			T.expect(WinPadRules.Share(wood, tower, true)).toBe(1)
		end)

		T.it("x2 pays exactly twice the normal pad on repeats (no more 1 and 1)", function()
			local tower = { Cleared = { [wood.Id] = true }, Highest = 1 }
			local share = WinPadRules.Share(wood, tower, false)
			T.expect(share < 1).toBe(true)
			local normal = WinPadRules.Payout(wood, 1, share)
			local double = WinPadRules.Payout(wood, 2, share)
			T.expect(normal >= 1).toBe(true)
			T.expect(double).toBe(normal * 2)
		end)

		T.it("x2 = 2 x normal for every stage at every distance from the best stage", function()
			for _, stage in WallConfig.Stages do
				local ratio = stage.Pads[2] / stage.Pads[1]
				for highest = stage.Order, #WallConfig.Stages do
					for _, first in { true, false } do
						local tower = { Cleared = { [stage.Id] = true }, Highest = highest }
						local share = WinPadRules.Share(stage, tower, first)
						local normal = WinPadRules.Payout(stage, 1, share)
						T.expect(WinPadRules.Payout(stage, 2, share)).toBe(math.floor(normal * ratio + 0.5))
					end
				end
			end
		end)

		T.it("a player who never cleared the stage gets the full value", function()
			T.expect(WinPadRules.Share(wood, { Cleared = {}, Highest = 0 }, false)).toBe(1)
			T.expect(WinPadRules.Share(wood, nil, false)).toBe(1)
		end)

		T.it("only an exact double is labelled x2", function()
			for _, stage in WallConfig.Stages do
				T.expect(WinPadRules.IsDouble(stage, 2)).toBe(stage.Pads[2] == stage.Pads[1] * 2)
				T.expect(WinPadRules.IsDouble(stage, 1)).toBe(false)
			end
		end)

		T.it("an unknown pad pays nothing", function()
			T.expect(WinPadRules.Payout(wood, 3, 1)).toBe(0)
			T.expect(WinPadRules.IndexOf(wood, wood.Pads[2])).toBe(2)
		end)
	end)
end
