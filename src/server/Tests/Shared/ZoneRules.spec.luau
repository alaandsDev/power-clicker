local Shared = game:GetService("ReplicatedStorage").Shared
local ZoneRules = require(Shared.Formulas.ZoneRules)
local ZoneConfig = require(Shared.Config.ZoneConfig)

local ORIGIN = Vector3.new(1000, 0, -500) -- any origin: zones are offsets from it

local function centerOf(zoneId: string): Vector3
	local zone = ZoneConfig.Zones[zoneId]
	return ORIGIN + zone.Offset + Vector3.new(0, ZoneConfig.PlatformHeight, 0)
end

return function(T)
	T.describe("ZoneRules", function()
		T.it("lists a world's zones weakest first", function()
			local zones = ZoneRules.ForWorld("Training")
			T.expect(#zones > 0).toBe(true)
			for index = 2, #zones do
				T.expect(zones[index - 1].Order < zones[index].Order).toBe(true)
			end
			T.expect(#ZoneRules.ForWorld("NotAWorld")).toBe(0)
		end)

		T.it("zones get stronger and pricier in order", function()
			local zones = ZoneRules.ForWorld("Training")
			for index = 2, #zones do
				T.expect(zones[index].Multiplier > zones[index - 1].Multiplier).toBe(true)
				T.expect(zones[index].Requirement.Power > zones[index - 1].Requirement.Power).toBe(true)
			end
		end)

		T.it("unlocks on total power earned and rebirths", function()
			local zone = ZoneConfig.Zones.Storm
			T.expect(ZoneRules.IsUnlocked(zone, zone.Requirement.Power, zone.Requirement.Rebirths)).toBe(true)
			T.expect(ZoneRules.IsUnlocked(zone, zone.Requirement.Power - 1, zone.Requirement.Rebirths)).toBe(false)
			T.expect(ZoneRules.IsUnlocked(zone, zone.Requirement.Power, zone.Requirement.Rebirths - 1)).toBe(false)
		end)

		T.it("reports what is still missing", function()
			local zone = ZoneConfig.Zones.Meadow
			T.expect(ZoneRules.Missing(zone, zone.Requirement.Power, 99)).toBe(nil)
			local missing = ZoneRules.Missing(zone, zone.Requirement.Power - 250, 0)
			T.expect(missing ~= nil).toBe(true)
			T.expect((missing :: any).Power).toBe(250)
		end)

		T.it("locates the zone a position stands in", function()
			local center = centerOf("Meadow")
			local inside = ZoneRules.ZoneAt("Training", ORIGIN, center)
			T.expect(inside ~= nil and (inside :: any).Id).toBe("Meadow")
			-- just outside the rim
			local radius = ZoneConfig.Zones.Meadow.Radius
			T.expect(ZoneRules.ZoneAt("Training", ORIGIN, center + Vector3.new(radius + 5, 0, 0))).toBe(nil)
			-- falling far below the platform
			T.expect(ZoneRules.ZoneAt("Training", ORIGIN, center - Vector3.new(0, ZoneConfig.HeightTolerance + 10, 0))).toBe(nil)
			-- the plaza itself is not a zone
			T.expect(ZoneRules.ZoneAt("Training", ORIGIN, ORIGIN)).toBe(nil)
		end)

		T.it("multiplier falls back to 1 outside zones", function()
			T.expect(ZoneRules.Multiplier(nil)).toBe(1)
			T.expect(ZoneRules.Multiplier("NotAZone")).toBe(1)
			T.expect(ZoneRules.Multiplier("Quarry")).toBe(ZoneConfig.Zones.Quarry.Multiplier)
		end)

		T.it("targets are worth less than the power they cost to break", function()
			-- A target must not be a free lunch: reward < hp keeps zones honest.
			for _, zone in ZoneConfig.Zones do
				T.expect(zone.Target.Reward < zone.Target.Hp).toBe(true)
				T.expect(zone.Target.Count > 0).toBe(true)
				T.expect(zone.Target.RespawnSeconds > 0).toBe(true)
			end
		end)
	end)
end
