local Shared = game:GetService("ReplicatedStorage").Shared
local EconomyFormulas = require(Shared.Formulas.EconomyFormulas)
local RebirthConfig = require(Shared.Config.RebirthConfig)
local ComboConfig = require(Shared.Config.ComboConfig)
local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local GameConfig = require(Shared.Config.GameConfig)

return function(T)
	T.describe("EconomyFormulas", function()
		local upgrade = UpgradeConfig.Temporary.ClickStrength

		T.it("UpgradeCost level 0 equals BaseCost", function()
			T.expect(EconomyFormulas.UpgradeCost(upgrade, 0)).toBe(math.ceil(upgrade.BaseCost))
		end)

		T.it("UpgradeCost grows monotonically", function()
			local previous = 0
			for level = 0, 50 do
				local cost = EconomyFormulas.UpgradeCost(upgrade, level)
				T.expect(cost >= previous).toBe(true)
				previous = cost
			end
		end)

		T.it("UpgradeCost is infinite when maxed, negative or fractional", function()
			T.expect(EconomyFormulas.UpgradeCost(upgrade, upgrade.MaxLevel)).toBe(math.huge)
			T.expect(EconomyFormulas.UpgradeCost(upgrade, -1)).toBe(math.huge)
			T.expect(EconomyFormulas.UpgradeCost(upgrade, 1.5)).toBe(math.huge)
		end)

		T.it("UpgradeCost stays finite and capped at huge levels", function()
			local fake = table.clone(upgrade)
			fake.MaxLevel = 1e9
			local cost = EconomyFormulas.UpgradeCost(fake, 100000)
			T.expect(cost <= GameConfig.Numbers.MaxValue).toBe(true)
		end)

		T.it("RebirthCost follows BaseCost * Growth^r", function()
			T.expect(EconomyFormulas.RebirthCost(0)).toBe(RebirthConfig.BaseCost)
			T.expect(EconomyFormulas.RebirthCost(2)).toBe(math.ceil(RebirthConfig.BaseCost * RebirthConfig.CostGrowth ^ 2))
			T.expect(EconomyFormulas.RebirthCost(-1)).toBe(math.huge)
			T.expect(EconomyFormulas.RebirthCost(RebirthConfig.MaxRebirths)).toBe(math.huge)
		end)

		T.it("RebirthGems and RebirthMultiplier", function()
			T.expect(EconomyFormulas.RebirthGems(0)).toBe(RebirthConfig.BaseGems)
			T.expect(EconomyFormulas.RebirthGems(-3)).toBe(0)
			T.expect(EconomyFormulas.RebirthMultiplier(0)).toBe(1)
			T.expect(EconomyFormulas.RebirthMultiplier(-5)).toBe(1)
			T.expect(EconomyFormulas.RebirthMultiplier(2)).toBeNear(1 + 2 * RebirthConfig.MultiplierPerRebirth)
		end)

		T.it("ComboMultiplier is clamped to [1, MaxMultiplier]", function()
			T.expect(EconomyFormulas.ComboMultiplier(0)).toBe(1)
			T.expect(EconomyFormulas.ComboMultiplier(-10)).toBe(1)
			T.expect(EconomyFormulas.ComboMultiplier(1e9)).toBe(ComboConfig.MaxMultiplier)
		end)

		T.it("Sanitize handles NaN, negatives and huge values", function()
			T.expect(EconomyFormulas.Sanitize(0 / 0)).toBe(0)
			T.expect(EconomyFormulas.Sanitize(-5)).toBe(0)
			T.expect(EconomyFormulas.Sanitize(math.huge)).toBe(GameConfig.Numbers.MaxValue)
			T.expect(EconomyFormulas.Sanitize(42)).toBe(42)
		end)
	end)
end
