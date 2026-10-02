--[[
	World unlock/travel rule tests. `isEnabled` is injected so results don't
	depend on WorldConfig.Enabled or the Studio override.
]]

local Server = script.Parent.Parent.Parent
local Shared = game:GetService("ReplicatedStorage").Shared
local WorldLogic = require(Server.Logic.WorldLogic)
local CurrencyLogic = require(Server.Logic.CurrencyLogic)
local EggLogic = require(Server.Logic.EggLogic)
local DataTemplate = require(Server.Services.DataService.DataTemplate)
local WorldConfig = require(Shared.Config.WorldConfig)

local function allEnabled()
	return true
end
local function noneEnabled()
	return false
end

local function fresh()
	return DataTemplate.Create(0)
end

return function(T)
	local city = WorldConfig.Worlds.City

	T.describe("WorldLogic.Unlock", function()
		T.it("requires rebirths", function()
			local data = fresh()
			CurrencyLogic.Add(data, city.Requirement.Currency, city.Requirement.Cost)
			T.expect((select(2, WorldLogic.Unlock(data, "City", allEnabled)))).toBe("NotEnoughRebirths")
			T.expect(data.Worlds.Unlocked.City).toBeNil()
		end)

		T.it("requires the cost and charges exactly it", function()
			local data = fresh()
			data.Stats.Rebirths = city.Requirement.Rebirths
			T.expect((select(2, WorldLogic.Unlock(data, "City", allEnabled)))).toBe("NotEnoughCurrency")
			CurrencyLogic.Add(data, city.Requirement.Currency, city.Requirement.Cost + 7)
			T.expect((WorldLogic.Unlock(data, "City", allEnabled))).toBe(true)
			T.expect(data.Worlds.Unlocked.City).toBe(true)
			T.expect(CurrencyLogic.Get(data, city.Requirement.Currency)).toBe(7)
		end)

		T.it("is sequential: previous world must be unlocked", function()
			local data = fresh()
			data.Stats.Rebirths = 1000
			CurrencyLogic.Add(data, "Gems", 1e12)
			T.expect((select(2, WorldLogic.Unlock(data, "Volcano", allEnabled)))).toBe("PreviousWorldLocked")
		end)

		T.it("refuses disabled, unknown and already unlocked worlds", function()
			local data = fresh()
			data.Stats.Rebirths = 1000
			CurrencyLogic.Add(data, "Gems", 1e12)
			T.expect((select(2, WorldLogic.Unlock(data, "City", noneEnabled)))).toBe("WorldDisabled")
			T.expect((select(2, WorldLogic.Unlock(data, "Atlantis", allEnabled)))).toBe("UnknownWorld")
			T.expect((select(2, WorldLogic.Unlock(data, "Training", allEnabled)))).toBe("AlreadyUnlocked")
		end)
	end)

	T.describe("WorldLogic.Travel", function()
		T.it("only to unlocked, enabled worlds", function()
			local data = fresh()
			T.expect((select(2, WorldLogic.Travel(data, "City", allEnabled)))).toBe("WorldNotUnlocked")
			data.Worlds.Unlocked.City = true
			T.expect((select(2, WorldLogic.Travel(data, "City", noneEnabled)))).toBe("WorldDisabled")
			T.expect((WorldLogic.Travel(data, "City", allEnabled))).toBe(true)
			T.expect(data.Worlds.Current).toBe("City")
		end)
	end)

	T.describe("WorldLogic.Sanitize", function()
		T.it("sends players in disabled/locked worlds home, keeps unlocks", function()
			local data = fresh()
			data.Worlds.Unlocked.City = true
			data.Worlds.Current = "City"
			T.expect(WorldLogic.Sanitize(data, function(world)
				return world.Id == WorldConfig.DefaultWorld
			end)).toBe(true)
			T.expect(data.Worlds.Current).toBe(WorldConfig.DefaultWorld)
			T.expect(data.Worlds.Unlocked.City).toBe(true)
		end)

		T.it("repairs a missing default unlock and unknown current world", function()
			local data = fresh()
			data.Worlds.Unlocked = {}
			data.Worlds.Current = "Atlantis"
			WorldLogic.Sanitize(data, allEnabled)
			T.expect(data.Worlds.Unlocked[WorldConfig.DefaultWorld]).toBe(true)
			T.expect(data.Worlds.Current).toBe(WorldConfig.DefaultWorld)
		end)
	end)

	T.describe("Eggs x worlds", function()
		T.it("eggs can only be opened in their own world", function()
			local data = fresh()
			data.Worlds.Unlocked.City = true
			data.Worlds.Current = "City"
			CurrencyLogic.Add(data, "Power", 1e9)
			local ok, code = EggLogic.Hatch(data, "BasicEgg", 1, function()
				return 0
			end, 0)
			T.expect(ok).toBe(false)
			T.expect(code).toBe("WrongWorld")
			T.expect(CurrencyLogic.Get(data, "Power")).toBe(1e9)
		end)
	end)
end
