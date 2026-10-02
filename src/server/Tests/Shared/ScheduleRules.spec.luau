local Shared = game:GetService("ReplicatedStorage").Shared
local ScheduleRules = require(Shared.Formulas.ScheduleRules)
local SessionConfig = require(Shared.Config.SessionConfig)

-- Fixed UTC timestamps (2026-09, checked against a calendar).
local SATURDAY_03H = 1790391600
local SUNDAY_12H = 1790510400
local WEDNESDAY_19H30 = 1790191800
local WEDNESDAY_05H = 1790139600

return function(T)
	T.describe("ScheduleRules", function()
		T.it("weekends run at double power all day", function()
			T.expect(ScheduleRules.Multiplier(SATURDAY_03H)).toBe(2)
			T.expect(ScheduleRules.Multiplier(SUNDAY_12H)).toBe(2)
		end)

		T.it("the daily window runs on a weekday evening", function()
			T.expect(ScheduleRules.Multiplier(WEDNESDAY_19H30)).toBe(1.5)
		end)

		T.it("quiet hours have no multiplier", function()
			T.expect(ScheduleRules.Multiplier(WEDNESDAY_05H)).toBe(1)
			local window = ScheduleRules.Active(WEDNESDAY_05H)
			T.expect(window).toBe(nil)
		end)

		T.it("reports the time left in the running window", function()
			local window, left = ScheduleRules.Active(WEDNESDAY_19H30)
			T.expect(window ~= nil and (window :: any).Id).toBe("AfterSchool")
			T.expect(left).toBe(30 * 60) -- 19:30 → 20:00
		end)

		T.it("the strongest window wins when they overlap", function()
			-- Saturday 18:30 is inside both the weekend (x2) and the daily (x1.5).
			local saturdayEvening = SATURDAY_03H + 15.5 * 3600
			T.expect(ScheduleRules.Multiplier(saturdayEvening)).toBe(2)
		end)

		T.it("playtime chests grow and never pay nothing", function()
			for index = 2, #SessionConfig.Chests do
				local previous = SessionConfig.Chests[index - 1]
				local chest = SessionConfig.Chests[index]
				T.expect(chest.Minutes > previous.Minutes).toBe(true)
				T.expect(chest.ClicksWorth > previous.ClicksWorth).toBe(true)
			end
			T.expect(SessionConfig.MinChestPower > 0).toBe(true)
		end)
	end)
end
