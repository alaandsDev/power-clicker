--[[
	Pets & eggs rule tests on real PlayerData templates.
]]

local Server = script.Parent.Parent.Parent
local Shared = game:GetService("ReplicatedStorage").Shared
local PetLogic = require(Server.Logic.PetLogic)
local EggLogic = require(Server.Logic.EggLogic)
local CurrencyLogic = require(Server.Logic.CurrencyLogic)
local DataTemplate = require(Server.Services.DataService.DataTemplate)
local EggOdds = require(Shared.Formulas.EggOdds)
local PetConfig = require(Shared.Config.PetConfig)
local EggConfig = require(Shared.Config.EggConfig)

local function fresh()
	return DataTemplate.Create(0)
end

local function constantRoll(value: number): () -> number
	return function()
		return value
	end
end

return function(T)
	T.describe("PetLogic", function()
		T.it("adds pets with unique increasing uids", function()
			local data = fresh()
			local _, _, a = PetLogic.Add(data, "Dog", nil, 0)
			local _, _, b = PetLogic.Add(data, "Cat", nil, 0)
			T.expect(a).toBe("1")
			T.expect(b).toBe("2")
			T.expect(PetLogic.Count(data)).toBe(2)
		end)

		T.it("never overwrites an existing pet even if NextUid is stale", function()
			local data = fresh()
			PetLogic.Add(data, "Dog", nil, 0)
			data.Pets.NextUid = 1 -- corrupted counter
			local _, _, uid = PetLogic.Add(data, "Cat", nil, 0)
			T.expect(uid).toBe("2")
			T.expect(data.Pets.Inventory["1"].PetId).toBe("Dog")
		end)

		T.it("rejects unknown pets and disabled variants", function()
			local data = fresh()
			T.expect((select(2, PetLogic.Add(data, "Godzilla", nil, 0)))).toBe("UnknownPet")
			T.expect((select(2, PetLogic.Add(data, "Dog", "Rainbow", 0)))).toBe("UnknownVariant")
			T.expect(PetLogic.Count(data)).toBe(0)
		end)

		T.it("respects inventory capacity", function()
			local data = fresh()
			local capacity = PetLogic.GetInventoryCapacity(data)
			for _ = 1, capacity do
				PetLogic.Add(data, "Dog", nil, 0)
			end
			local ok, code = PetLogic.Add(data, "Dog", nil, 0)
			T.expect(ok).toBe(false)
			T.expect(code).toBe("InventoryFull")
		end)

		T.it("equip: ownership, duplicates and capacity", function()
			local data = fresh()
			local uids = {}
			for i = 1, PetConfig.BaseEquipSlots + 1 do
				local _, _, uid = PetLogic.Add(data, "Dog", nil, 0)
				uids[i] = uid
			end
			local capacity = PetLogic.GetEquipCapacity(data)
			T.expect(capacity).toBe(PetConfig.BaseEquipSlots)
			T.expect((PetLogic.Equip(data, "999", capacity))).toBe(false) -- not owned
			T.expect((PetLogic.Equip(data, uids[1], capacity))).toBe(true)
			T.expect((select(2, PetLogic.Equip(data, uids[1], capacity)))).toBe("AlreadyEquipped")
			for i = 2, capacity do
				PetLogic.Equip(data, uids[i], capacity)
			end
			T.expect((select(2, PetLogic.Equip(data, uids[capacity + 1], capacity)))).toBe("EquipFull")
			T.expect(#data.Pets.Equipped).toBe(capacity)
		end)

		T.it("pet slot upgrade and game pass slots raise capacity (capped)", function()
			local data = fresh()
			data.PermanentUpgrades.PetSlots = 2
			T.expect(PetLogic.GetEquipCapacity(data)).toBe(PetConfig.BaseEquipSlots + 2)
			T.expect(PetLogic.GetEquipCapacity(data, 3)).toBe(PetConfig.BaseEquipSlots + 5)
			T.expect(PetLogic.GetEquipCapacity(data, 1000)).toBe(PetConfig.MaxEquipSlots)
		end)

		T.it("multiplier sums equipped bonuses and ignores unknown pets", function()
			local data = fresh()
			local _, _, dog = PetLogic.Add(data, "Dog", nil, 0)
			local _, _, cat = PetLogic.Add(data, "Cat", nil, 0)
			PetLogic.Equip(data, dog, 3)
			PetLogic.Equip(data, cat, 3)
			local expected = 1 + PetConfig.Pets.Dog.Bonus + PetConfig.Pets.Cat.Bonus
			T.expect(PetLogic.GetMultiplier(data)).toBeNear(expected)
			data.Pets.Inventory[cat].PetId = "RemovedPet"
			T.expect(PetLogic.GetMultiplier(data)).toBeNear(1 + PetConfig.Pets.Dog.Bonus)
		end)

		T.it("equip best picks the strongest", function()
			local data = fresh()
			for _, id in { "Dog", "Wolf", "Cat", "Fox", "Bunny" } do
				PetLogic.Add(data, id, nil, 0)
			end
			PetLogic.EquipBest(data, 3)
			local equippedIds = {}
			for _, uid in data.Pets.Equipped do
				table.insert(equippedIds, data.Pets.Inventory[uid].PetId)
			end
			table.sort(equippedIds)
			T.expect(equippedIds).toEqual({ "Bunny", "Fox", "Wolf" })
		end)

		T.it("locked pets cannot be deleted; deleting unequips", function()
			local data = fresh()
			local _, _, uid = PetLogic.Add(data, "Dog", nil, 0)
			PetLogic.Equip(data, uid, 3)
			PetLogic.SetLocked(data, uid, true)
			T.expect((select(2, PetLogic.Delete(data, uid)))).toBe("Locked")
			PetLogic.SetLocked(data, uid, false)
			T.expect((PetLogic.Delete(data, uid))).toBe(true)
			T.expect(#data.Pets.Equipped).toBe(0)
			T.expect((select(2, PetLogic.Delete(data, uid)))).toBe("NotOwned")
		end)

		T.it("sanitize repairs duplicates, ghosts, overflow and counter", function()
			local data = fresh()
			local _, _, a = PetLogic.Add(data, "Dog", nil, 0)
			local _, _, b = PetLogic.Add(data, "Cat", nil, 0)
			data.Pets.Equipped = { a, a, "ghost", b }
			data.Pets.NextUid = 0
			local fixes = PetLogic.Sanitize(data, 1)
			T.expect(data.Pets.Equipped).toEqual({ a })
			T.expect(data.Pets.NextUid).toBe(3)
			T.expect(fixes > 0).toBe(true)
		end)
	end)

	T.describe("EggOdds", function()
		local egg = EggConfig.Eggs.BasicEgg

		T.it("chances sum to 1", function()
			local total = 0
			for _, chance in EggOdds.Chances(egg, 1) do
				total += chance
			end
			T.expect(total).toBeNear(1, 1e-9)
		end)

		T.it("luck raises rare chances and lowers common ones", function()
			local base = EggOdds.Chances(egg, 1)
			local lucky = EggOdds.Chances(egg, 3)
			T.expect(lucky.Wolf > base.Wolf).toBe(true)
			T.expect(lucky.Dog < base.Dog).toBe(true)
		end)

		T.it("luck is clamped to [1, MaxLuckMultiplier]", function()
			T.expect(EggOdds.ClampLuck(0.2)).toBe(1)
			T.expect(EggOdds.ClampLuck(0 / 0)).toBe(1)
			T.expect(EggOdds.ClampLuck(1e9)).toBe(EggConfig.MaxLuckMultiplier)
		end)

		T.it("pick maps roll boundaries correctly", function()
			local weights = { { PetId = "A", Weight = 1 }, { PetId = "B", Weight = 3 } }
			T.expect(EggOdds.Pick(weights, 0)).toBe("A")
			T.expect(EggOdds.Pick(weights, 0.2499)).toBe("A")
			T.expect(EggOdds.Pick(weights, 0.25)).toBe("B")
			T.expect(EggOdds.Pick(weights, 0.99999)).toBe("B")
			T.expect(EggOdds.Pick(weights, 5)).toBe("B") -- clamped
			T.expect(EggOdds.Pick({ { PetId = "A", Weight = 0 } }, 0.5)).toBeNil()
		end)

		T.it("100k rolls match configured chances (±1%)", function()
			local rng = Random.new(1234)
			local weights = EggOdds.Weights(egg, 1)
			local chances = EggOdds.Chances(egg, 1)
			local counts: { [string]: number } = {}
			local rolls = 100000
			for _ = 1, rolls do
				local id = EggOdds.Pick(weights, rng:NextNumber()) :: string
				counts[id] = (counts[id] or 0) + 1
			end
			for id, chance in chances do
				T.expect(math.abs((counts[id] or 0) / rolls - chance) < 0.01).toBe(true)
			end
		end)
	end)

	T.describe("EggLogic", function()
		T.it("refuses without funds and charges nothing", function()
			local data = fresh()
			local ok, code = EggLogic.Hatch(data, "BasicEgg", 1, constantRoll(0), 0)
			T.expect(ok).toBe(false)
			T.expect(code).toBe("NotEnoughCurrency")
			T.expect(PetLogic.Count(data)).toBe(0)
		end)

		T.it("charges the configured price, adds the rolled pet, updates stats", function()
			local data = fresh()
			CurrencyLogic.Add(data, "Power", EggConfig.Eggs.BasicEgg.Price + 5)
			local ok, _, result = EggLogic.Hatch(data, "BasicEgg", 1, constantRoll(0), 0)
			T.expect(ok).toBe(true)
			T.expect(result.PetId).toBe("Dog") -- roll 0 = first drop
			T.expect(CurrencyLogic.Get(data, "Power")).toBe(5)
			T.expect(data.Stats.EggsOpened).toBe(1)
			T.expect(data.Pets.Inventory[result.Uid].PetId).toBe("Dog")
		end)

		T.it("full inventory: refused BEFORE charging", function()
			local data = fresh()
			for _ = 1, PetLogic.GetInventoryCapacity(data) do
				PetLogic.Add(data, "Dog", nil, 0)
			end
			CurrencyLogic.Add(data, "Power", 1e9)
			local ok, code = EggLogic.Hatch(data, "BasicEgg", 1, constantRoll(0), 0)
			T.expect(ok).toBe(false)
			T.expect(code).toBe("InventoryFull")
			T.expect(CurrencyLogic.Get(data, "Power")).toBe(1e9)
		end)

		T.it("unknown/disabled egg and locked world are refused", function()
			local data = fresh()
			CurrencyLogic.Add(data, "Power", 1e9)
			T.expect((select(2, EggLogic.Hatch(data, "NopeEgg", 1, constantRoll(0), 0)))).toBe("UnknownEgg")
			data.Worlds.Unlocked.Training = nil
			T.expect((select(2, EggLogic.Hatch(data, "BasicEgg", 1, constantRoll(0), 0)))).toBe("WorldLocked")
		end)

		T.it("legendary/mythic counters increase", function()
			local data = fresh()
			CurrencyLogic.Add(data, "Gems", 1e6)
			-- Last drop of MysticEgg is the Mythic.
			local ok, _, result = EggLogic.Hatch(data, "MysticEgg", 1, constantRoll(0.9999999), 0)
			T.expect(ok).toBe(true)
			T.expect(result.Rarity).toBe("Mythic")
			T.expect(data.Stats.MythicHatched).toBe(1)
		end)
	end)
end
