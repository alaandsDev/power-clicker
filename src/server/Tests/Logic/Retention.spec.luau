--[[
	Retention systems: boosts, rewards, daily rewards, quests, achievements, codes.
]]

local Server = script.Parent.Parent.Parent
local Shared = game:GetService("ReplicatedStorage").Shared
local BoostLogic = require(Server.Logic.BoostLogic)
local RewardLogic = require(Server.Logic.RewardLogic)
local QuestLogic = require(Server.Logic.QuestLogic)
local AchievementLogic = require(Server.Logic.AchievementLogic)
local CodeLogic = require(Server.Logic.CodeLogic)
local CurrencyLogic = require(Server.Logic.CurrencyLogic)
local PetLogic = require(Server.Logic.PetLogic)
local DataTemplate = require(Server.Services.DataService.DataTemplate)
local DailyRewardLogic = require(Shared.Formulas.DailyRewardLogic)
local BoostConfig = require(Shared.Config.BoostConfig)
local DailyRewardConfig = require(Shared.Config.DailyRewardConfig)
local QuestConfig = require(Shared.Config.QuestConfig)

local HOUR = 3600
local DAY = 24 * HOUR

local function fresh()
	return DataTemplate.Create(0)
end

return function(T)
	T.describe("BoostLogic", function()
		T.it("adds duration per stack, capped at MaxStoredSeconds", function()
			local data = fresh()
			local boost = BoostConfig.Boosts.Power2x
			BoostLogic.Add(data, "Power2x", 2)
			T.expect(data.Boosts.Remaining.Power2x).toBe(boost.DurationSeconds * 2)
			BoostLogic.Add(data, "Power2x", 1000)
			T.expect(data.Boosts.Remaining.Power2x).toBe(boost.MaxStoredSeconds)
		end)
		T.it("rejects unknown boosts and invalid stacks", function()
			local data = fresh()
			T.expect((select(2, BoostLogic.Add(data, "Power100x", 1)))).toBe("UnknownBoost")
			T.expect((select(2, BoostLogic.Add(data, "Power2x", 0)))).toBe("InvalidAmount")
			T.expect((select(2, BoostLogic.Add(data, "Power2x", 1.5)))).toBe("InvalidAmount")
			T.expect((select(2, BoostLogic.Add(data, "Power2x", 0 / 0)))).toBe("InvalidAmount")
		end)
		T.it("same category: highest applies, never multiplied", function()
			local data = fresh()
			BoostLogic.Add(data, "Power2x", 1)
			BoostLogic.Add(data, "Power5x", 1)
			T.expect(BoostLogic.GetMultiplier(data, "Power")).toBe(5)
			T.expect(BoostLogic.GetMultiplier(data, "Luck")).toBe(1)
		end)
		T.it("tick consumes time and expires", function()
			local data = fresh()
			BoostLogic.Add(data, "Luck2x", 1)
			local duration = BoostConfig.Boosts.Luck2x.DurationSeconds
			T.expect(#BoostLogic.Tick(data, duration - 1)).toBe(0)
			T.expect(BoostLogic.GetMultiplier(data, "Luck")).toBe(2)
			local expired = BoostLogic.Tick(data, 2)
			T.expect(expired).toEqual({ "Luck2x" })
			T.expect(BoostLogic.HasActive(data)).toBe(false)
			T.expect(#BoostLogic.Tick(data, -5)).toBe(0) -- negative elapsed ignored
		end)
	end)

	T.describe("RewardLogic", function()
		T.it("grants currencies, boosts and pets together", function()
			local data = fresh()
			local ok, _, summary = RewardLogic.Grant(data, {
				{ Type = "Currency", Currency = "Gems", Amount = 10 },
				{ Type = "Boost", BoostId = "Power2x", Amount = 1 },
				{ Type = "Pet", PetId = "Dog" },
			}, 0)
			T.expect(ok).toBe(true)
			T.expect(CurrencyLogic.Get(data, "Gems")).toBe(10)
			T.expect(data.Boosts.Remaining.Power2x ~= nil).toBe(true)
			T.expect(#summary.Pets).toBe(1)
		end)
		T.it("is atomic: full inventory means NOTHING is granted", function()
			local data = fresh()
			for _ = 1, PetLogic.GetInventoryCapacity(data) do
				PetLogic.Add(data, "Dog", nil, 0)
			end
			local ok, code = RewardLogic.Grant(data, {
				{ Type = "Currency", Currency = "Gems", Amount = 10 },
				{ Type = "Pet", PetId = "Cat" },
			}, 0)
			T.expect(ok).toBe(false)
			T.expect(code).toBe("InventoryFull")
			T.expect(CurrencyLogic.Get(data, "Gems")).toBe(0)
		end)
		T.it("rejects invalid entries without partial grants", function()
			local data = fresh()
			local ok, code = RewardLogic.Grant(data, {
				{ Type = "Currency", Currency = "Gems", Amount = 10 },
				{ Type = "Currency", Currency = "Gems", Amount = -1 },
			}, 0)
			T.expect(ok).toBe(false)
			T.expect(code).toBe("InvalidReward")
			T.expect(CurrencyLogic.Get(data, "Gems")).toBe(0)
		end)
	end)

	T.describe("DailyRewardLogic", function()
		local start = 1_700_000_000

		T.it("first claim is day 1", function()
			local preview = DailyRewardLogic.Preview(fresh(), start)
			T.expect(preview.CanClaim).toBe(true)
			T.expect(preview.Day).toBe(1)
		end)
		T.it("cannot claim twice within the interval", function()
			local data = fresh()
			DailyRewardLogic.Commit(data, start, 1)
			local preview = DailyRewardLogic.Preview(data, start + HOUR)
			T.expect(preview.CanClaim).toBe(false)
			T.expect(preview.SecondsUntilClaim).toBe(DailyRewardConfig.ClaimIntervalSeconds - HOUR)
		end)
		T.it("consecutive days advance the streak and loop the cycle", function()
			local data = fresh()
			local now = start
			for expectedDay = 1, DailyRewardConfig.CycleLength + 2 do
				local preview = DailyRewardLogic.Preview(data, now)
				T.expect(preview.CanClaim).toBe(true)
				T.expect(preview.Day).toBe(((expectedDay - 1) % DailyRewardConfig.CycleLength) + 1)
				DailyRewardLogic.Commit(data, now, preview.NewStreak)
				now += DAY
			end
		end)
		T.it("a long absence restarts the streak", function()
			local data = fresh()
			DailyRewardLogic.Commit(data, start, 4)
			local preview = DailyRewardLogic.Preview(data, start + DailyRewardConfig.StreakResetSeconds + 1)
			T.expect(preview.StreakBroken).toBe(true)
			T.expect(preview.Day).toBe(1)
		end)
		T.it("server clock going backwards never allows a claim", function()
			local data = fresh()
			DailyRewardLogic.Commit(data, start, 2)
			T.expect(DailyRewardLogic.Preview(data, start - 10 * DAY).CanClaim).toBe(false)
		end)
		T.it("every configured day has valid rewards", function()
			for day = 1, DailyRewardConfig.CycleLength do
				T.expect((RewardLogic.CanGrant(fresh(), DailyRewardLogic.RewardsFor(day)))).toBe(true)
			end
		end)
	end)

	T.describe("QuestLogic", function()
		T.it("progress caps at target and reports completion once", function()
			local data = fresh()
			local target = QuestConfig.Quests.Click100.Target
			T.expect(#QuestLogic.AddProgress(data, "Clicks", target - 1)).toBe(0)
			local completed = QuestLogic.AddProgress(data, "Clicks", 50)
			T.expect(table.find(completed, "Click100") ~= nil).toBe(true)
			T.expect(data.Quests.Progress.Click100.Progress).toBe(target)
			T.expect(table.find(QuestLogic.AddProgress(data, "Clicks", 1), "Click100")).toBeNil()
		end)
		T.it("claim requires completion and only once", function()
			local data = fresh()
			T.expect((select(2, QuestLogic.CanClaim(data, "Click100")))).toBe("NotComplete")
			QuestLogic.AddProgress(data, "Clicks", 1e6)
			T.expect((QuestLogic.CanClaim(data, "Click100"))).toBe(true)
			QuestLogic.MarkClaimed(data, "Click100")
			T.expect((select(2, QuestLogic.CanClaim(data, "Click100")))).toBe("AlreadyClaimed")
			T.expect((select(2, QuestLogic.CanClaim(data, "Nope")))).toBe("UnknownQuest")
		end)
		T.it("daily quests reset on a new day; once quests don't", function()
			local data = fresh()
			local day1 = 1_700_000_000
			QuestLogic.ApplyDailyReset(data, day1)
			QuestLogic.AddProgress(data, "Clicks", 1e6)
			QuestLogic.MarkClaimed(data, "DailyClicks")
			QuestLogic.MarkClaimed(data, "Click100")
			T.expect(QuestLogic.ApplyDailyReset(data, day1 + 60)).toBe(false) -- same day
			T.expect(QuestLogic.ApplyDailyReset(data, day1 + DAY)).toBe(true)
			T.expect(data.Quests.Progress.DailyClicks.Claimed).toBe(false)
			T.expect(data.Quests.Progress.DailyClicks.Progress).toBe(0)
			T.expect(data.Quests.Progress.Click100.Claimed).toBe(true)
		end)
		T.it("absolute progress (worlds unlocked)", function()
			local data = fresh()
			T.expect(#QuestLogic.SetProgressAtLeast(data, "WorldsUnlocked", 2)).toBe(0) -- no such quest configured
		end)
	end)

	T.describe("AchievementLogic", function()
		T.it("stat thresholds and world unlocks", function()
			local data = fresh()
			T.expect(#AchievementLogic.Pending(data)).toBe(0)
			data.Stats.TotalClicks = 1000
			data.Worlds.Unlocked.City = true
			local pending = AchievementLogic.Pending(data)
			T.expect(table.find(pending, "FirstClick") ~= nil).toBe(true)
			T.expect(table.find(pending, "Clicks1K") ~= nil).toBe(true)
			T.expect(table.find(pending, "UnlockCity") ~= nil).toBe(true)
			T.expect(table.find(pending, "Clicks10K")).toBeNil()
		end)
		T.it("unlock is idempotent", function()
			local data = fresh()
			data.Stats.TotalClicks = 1
			AchievementLogic.MarkUnlocked(data, "FirstClick", 5)
			AchievementLogic.MarkUnlocked(data, "FirstClick", 99)
			T.expect(data.Achievements.Unlocked.FirstClick).toBe(5)
			T.expect(table.find(AchievementLogic.Pending(data), "FirstClick")).toBeNil()
		end)
	end)

	T.describe("CodeLogic", function()
		local codes = {
			RELEASE = { Rewards = {}, Enabled = true },
			OLD = { Rewards = {}, Enabled = true, ExpiresAt = 100 },
			OFF = { Rewards = {}, Enabled = false },
		}
		T.it("normalizes and checks format", function()
			T.expect(CodeLogic.Normalize("  release ")).toBe("RELEASE")
			T.expect(CodeLogic.IsWellFormed("RELEASE", 32)).toBe(true)
			T.expect(CodeLogic.IsWellFormed("REL EASE", 32)).toBe(false)
			T.expect(CodeLogic.IsWellFormed("", 32)).toBe(false)
			T.expect(CodeLogic.IsWellFormed(string.rep("A", 40), 32)).toBe(false)
			T.expect(CodeLogic.IsWellFormed("DROP;TABLE", 32)).toBe(false)
		end)
		T.it("validates existence, enabled, expiry and single use", function()
			local data = fresh()
			T.expect((select(2, CodeLogic.Validate(data, "NOPE", codes, 0)))).toBe("InvalidCode")
			T.expect((select(2, CodeLogic.Validate(data, "OFF", codes, 0)))).toBe("InvalidCode")
			T.expect((select(2, CodeLogic.Validate(data, "OLD", codes, 100)))).toBe("CodeExpired")
			T.expect((CodeLogic.Validate(data, "RELEASE", codes, 0))).toBe(true)
			CodeLogic.MarkRedeemed(data, "RELEASE", 0)
			T.expect((select(2, CodeLogic.Validate(data, "RELEASE", codes, 0)))).toBe("AlreadyRedeemed")
		end)
	end)
end
