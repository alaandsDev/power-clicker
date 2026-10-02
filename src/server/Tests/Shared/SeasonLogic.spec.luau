local Shared = game:GetService("ReplicatedStorage").Shared
local SeasonLogic = require(Shared.Formulas.SeasonLogic)
local SeasonConfig = require(Shared.Config.SeasonConfig)

local function fresh()
	return SeasonLogic.Fresh()
end

return function(T)
	T.describe("SeasonLogic", function()
		T.it("levels up every XpPerLevel points", function()
			T.expect(SeasonLogic.LevelOf(0)).toBe(0)
			T.expect(SeasonLogic.LevelOf(SeasonConfig.XpPerLevel - 1)).toBe(0)
			T.expect(SeasonLogic.LevelOf(SeasonConfig.XpPerLevel)).toBe(1)
			T.expect(SeasonLogic.LevelOf(SeasonConfig.XpPerLevel * 3.5)).toBe(3)
		end)

		T.it("never goes past the last level, and survives junk XP", function()
			T.expect(SeasonLogic.LevelOf(SeasonConfig.XpPerLevel * 10_000)).toBe(SeasonConfig.LevelCount)
			T.expect(SeasonLogic.LevelOf(0 / 0)).toBe(0)
			T.expect(SeasonLogic.LevelOf(-500)).toBe(0)
		end)

		T.it("reports progress inside the current level", function()
			local inLevel, needed = SeasonLogic.Progress(SeasonConfig.XpPerLevel + 30)
			T.expect(inLevel).toBe(30)
			T.expect(needed).toBe(SeasonConfig.XpPerLevel)
		end)

		T.it("a new season resets progress", function()
			local data = { Season = { SeasonId = "OldSeason", Xp = 900, ClaimedFree = { ["1"] = true }, ClaimedVip = {} } }
			T.expect(SeasonLogic.EnsureCurrent(data)).toBe(true)
			T.expect(data.Season.Xp).toBe(0)
			T.expect(data.Season.SeasonId).toBe(SeasonConfig.Id)
			-- Running it again changes nothing.
			T.expect(SeasonLogic.EnsureCurrent(data)).toBe(false)
		end)

		T.it("refuses levels that were not reached", function()
			local season = fresh()
			season.Xp = SeasonConfig.XpPerLevel * 2
			T.expect(SeasonLogic.CanClaim(season, 2, "Free", false)).toBe(true)
			local allowed, reason = SeasonLogic.CanClaim(season, 3, "Free", false)
			T.expect(allowed).toBe(false)
			T.expect(reason).toBe("LevelLocked")
		end)

		T.it("the VIP track needs the pass", function()
			local season = fresh()
			season.Xp = SeasonConfig.XpPerLevel
			local allowed, reason = SeasonLogic.CanClaim(season, 1, "Vip", false)
			T.expect(allowed).toBe(false)
			T.expect(reason).toBe("VipOnly")
			T.expect(SeasonLogic.CanClaim(season, 1, "Vip", true)).toBe(true)
		end)

		T.it("never pays the same level twice", function()
			local season = fresh()
			season.Xp = SeasonConfig.XpPerLevel
			SeasonLogic.MarkClaimed(season, 1, "Free")
			local allowed, reason = SeasonLogic.CanClaim(season, 1, "Free", false)
			T.expect(allowed).toBe(false)
			T.expect(reason).toBe("AlreadyClaimed")
			-- The VIP side of the same level is independent.
			T.expect(SeasonLogic.CanClaim(season, 1, "Vip", true)).toBe(true)
		end)

		T.it("rejects junk levels and tracks", function()
			local season = fresh()
			season.Xp = SeasonConfig.XpPerLevel * SeasonConfig.LevelCount
			T.expect(SeasonLogic.CanClaim(season, 0, "Free", true)).toBe(false)
			T.expect(SeasonLogic.CanClaim(season, SeasonConfig.LevelCount + 1, "Free", true)).toBe(false)
			T.expect(SeasonLogic.CanClaim(season, 1.5, "Free", true)).toBe(false)
			T.expect(SeasonLogic.CanClaim(season, 1, "Gold", true)).toBe(false)
		end)

		T.it("every level pays something on both tracks", function()
			for level = 1, SeasonConfig.LevelCount do
				T.expect(#SeasonLogic.RewardsOf(level, "Free") > 0).toBe(true)
				T.expect(#SeasonLogic.RewardsOf(level, "Vip") > 0).toBe(true)
			end
			T.expect(#SeasonLogic.RewardsOf(SeasonConfig.LevelCount + 1, "Free")).toBe(0)
		end)
	end)
end
