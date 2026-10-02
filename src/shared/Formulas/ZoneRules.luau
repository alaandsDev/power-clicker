--!strict
--[[
	ZoneRules
	Pure rules for training zones. No Roblox services, no player instances —
	ZoneService (server) and ZoneController (client display) both use these,
	so "can I stand here" is answered by the same code on both sides.
]]

local Shared = script.Parent.Parent
local Types = require(Shared.Types)
local ZoneConfig = require(Shared.Config.ZoneConfig)

type ZoneData = Types.ZoneData

local ZoneRules = {}

-- Zones of a world, weakest first.
function ZoneRules.ForWorld(worldId: string): { ZoneData }
	local zones: { ZoneData } = {}
	for _, zone in ZoneConfig.Zones do
		if zone.WorldId == worldId then
			table.insert(zones, zone)
		end
	end
	table.sort(zones, function(a: ZoneData, b: ZoneData): boolean
		return a.Order < b.Order
	end)
	return zones
end

--[[
	True when the player meets a zone's requirement.
	`totalPowerEarned` is Stats.TotalPowerEarned (never decreases, so a zone
	stays unlocked after a rebirth spends the Power).
]]
function ZoneRules.IsUnlocked(zone: ZoneData, totalPowerEarned: number, rebirths: number): boolean
	return totalPowerEarned >= zone.Requirement.Power and rebirths >= zone.Requirement.Rebirths
end

-- What the player still needs, or nil when the zone is already unlocked.
function ZoneRules.Missing(zone: ZoneData, totalPowerEarned: number, rebirths: number): { Power: number, Rebirths: number }?
	if ZoneRules.IsUnlocked(zone, totalPowerEarned, rebirths) then
		return nil
	end
	return {
		Power = math.max(zone.Requirement.Power - totalPowerEarned, 0),
		Rebirths = math.max(zone.Requirement.Rebirths - rebirths, 0),
	}
end

--[[
	Zone whose platform contains `position` (world-space), or nil for the plaza.
	`origin` is the world's origin. Vertical distance is limited so a player
	falling past a floating island does not count as inside it.
]]
function ZoneRules.ZoneAt(worldId: string, origin: Vector3, position: Vector3): ZoneData?
	for _, zone in ZoneRules.ForWorld(worldId) do
		local center = origin + zone.Offset + Vector3.new(0, ZoneConfig.PlatformHeight, 0)
		local flat = Vector2.new(position.X - center.X, position.Z - center.Z)
		if flat.Magnitude <= zone.Radius and math.abs(position.Y - center.Y) <= ZoneConfig.HeightTolerance then
			return zone
		end
	end
	return nil
end

-- Power multiplier of a zone id (the plaza, or an unknown id, is 1).
function ZoneRules.Multiplier(zoneId: string?): number
	local zone = if zoneId then ZoneConfig.Zones[zoneId] else nil
	return if zone then zone.Multiplier else 1
end

return ZoneRules
