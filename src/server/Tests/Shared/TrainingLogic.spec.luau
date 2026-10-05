local Shared = game:GetService("ReplicatedStorage").Shared
local TrainingLogic = require(Shared.Formulas.TrainingLogic)
local TrainingConfig = require(Shared.Config.TrainingConfig)

local ORIGIN = Vector3.new(0, 0, 0)

return function(T)
	T.describe("TrainingLogic", function()
		T.it("lets everyone train on the first station", function()
			T.expect(TrainingLogic.CanTrain(TrainingConfig.Stations[1], 0)).toBe(true)
		end)

		T.it("asks for the rebirths, exactly", function()
			for _, station in TrainingConfig.Stations do
				local required = TrainingLogic.Required(station)
				if required > 0 then
					T.expect(TrainingLogic.CanTrain(station, required - 1)).toBe(false)
				end
				T.expect(TrainingLogic.CanTrain(station, required)).toBe(true)
				T.expect(TrainingLogic.CanTrain(station, required + 10)).toBe(true)
			end
		end)

		T.it("treats missing data as zero rebirths", function()
			T.expect(TrainingLogic.CanTrain(TrainingConfig.Stations[2], nil)).toBe(false)
		end)

		T.it("finds the station under the player, and nothing outside", function()
			for _, station in TrainingConfig.Stations do
				T.expect(TrainingLogic.StationAt(ORIGIN, station.Local + Vector3.new(0, 3, 0))).toBe(station)
				T.expect(TrainingLogic.StationAt(ORIGIN, station.Local + Vector3.new(station.Radius + 0.5, 3, 0))).toBe(nil)
				T.expect(TrainingLogic.StationAt(ORIGIN, station.Local + Vector3.new(0, TrainingLogic.HEIGHT_TOLERANCE + 1, 0))).toBe(nil)
			end
		end)
	end)
end
