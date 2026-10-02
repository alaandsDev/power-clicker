local Shared = game:GetService("ReplicatedStorage").Shared
local LevelFormula = require(Shared.Formulas.LevelFormula)
local LevelConfig = require(Shared.Config.LevelConfig)

return function(T)
	T.describe("LevelFormula", function()
		T.it("starts at level 0 and asks for BaseStep", function()
			local level, into, cost = LevelFormula.LevelOf(0)
			T.expect(level).toBe(0)
			T.expect(into).toBe(0)
			T.expect(cost).toBe(LevelConfig.BaseStep)
		end)

		T.it("levels up exactly on the step cost", function()
			local step = LevelConfig.BaseStep
			T.expect((LevelFormula.LevelOf(step - 1))).toBe(0)
			T.expect((LevelFormula.LevelOf(step))).toBe(1)
			-- Second level asks for BaseStep + StepIncrease on top.
			local second = step + LevelFormula.StepCost(1)
			T.expect((LevelFormula.LevelOf(second - 1))).toBe(1)
			T.expect((LevelFormula.LevelOf(second))).toBe(2)
		end)

		T.it("reports the progress inside the current level", function()
			local target = LevelFormula.TotalFor(3) + 7
			local level, into, cost = LevelFormula.LevelOf(target)
			T.expect(level).toBe(3)
			-- Geometric costs are not whole numbers, so this is a float compare.
			T.expect(math.abs(into - 7) < 1e-6).toBe(true)
			T.expect(cost).toBe(LevelFormula.StepCost(3))
		end)

		T.it("TotalFor matches the sum of every step before it", function()
			local sum = 0
			for level = 0, 9 do
				T.expect(math.abs(LevelFormula.TotalFor(level) - sum) < 1e-6).toBe(true)
				sum += LevelFormula.StepCost(level)
			end
		end)

		T.it("stays a readable number at absurd Power", function()
			-- A linear ladder would read ~300 here; this is what the bug looked like.
			T.expect((LevelFormula.LevelOf(2_240_000)) < 60).toBe(true)
			T.expect((LevelFormula.LevelOf(1e15)) < 150).toBe(true)
		end)

		T.it("survives junk and huge numbers without looping", function()
			T.expect((LevelFormula.LevelOf(0 / 0))).toBe(0)
			T.expect((LevelFormula.LevelOf(-10))).toBe(0)
			local level, into, cost = LevelFormula.LevelOf(1e30)
			T.expect(level > 0 and level <= LevelConfig.MaxLevel).toBe(true)
			T.expect(into <= cost).toBe(true)
		end)
	end)
end
