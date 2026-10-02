local Shared = game:GetService("ReplicatedStorage").Shared
local AuraLogic = require(Shared.Formulas.AuraLogic)
local RuneLogic = require(Shared.Formulas.RuneLogic)
local AuraConfig = require(Shared.Config.AuraConfig)
local RuneConfig = require(Shared.Config.RuneConfig)

-- A roll function that hands out the given numbers in order (then repeats the last).
local function rolls(values: { number }): () -> number
	local index = 0
	return function(): number
		index += 1
		return values[math.min(index, #values)]
	end
end

local function anyPaidAura()
	for _, aura in AuraConfig.Auras do
		if aura.Price > 0 and aura.RequiredWins == 0 then
			return aura
		end
	end
	error("AuraConfig has no paid aura without a wins requirement")
end

return function(T)
	T.describe("AuraLogic", function()
		T.it("starts with the default aura equipped", function()
			local auras = AuraLogic.Fresh()
			T.expect(auras.Equipped).toBe(AuraConfig.DefaultAura)
			T.expect(AuraLogic.Multiplier(auras)).toBe(1)
			T.expect(AuraLogic.WalkSpeed(auras)).toBe(AuraConfig.BaseWalkSpeed)
		end)

		T.it("refuses to equip an aura that was not bought", function()
			local auras = AuraLogic.Fresh()
			local aura = anyPaidAura()
			local ok, code = AuraLogic.Equip(auras, aura.Id)
			T.expect(ok).toBe(false)
			T.expect(code).toBe("NotOwned")
			T.expect(auras.Equipped).toBe(AuraConfig.DefaultAura)
		end)

		T.it("refuses to buy twice, or without the rebirths", function()
			local auras = AuraLogic.Fresh()
			local aura = anyPaidAura()
			T.expect(AuraLogic.CanBuy(auras, aura.Id, 0)).toBe(true)
			auras.Owned[aura.Id] = true
			local ok, code = AuraLogic.CanBuy(auras, aura.Id, 0)
			T.expect(ok).toBe(false)
			T.expect(code).toBe("AlreadyOwned")

			local locked = AuraConfig.Auras.Singularity
			local allowed, reason = AuraLogic.CanBuy(auras, locked.Id, locked.RequiredWins - 1)
			T.expect(allowed).toBe(false)
			T.expect(reason).toBe("NeedsWins")
		end)

		T.it("gives speed and power once equipped, inside the cap", function()
			local auras = AuraLogic.Fresh()
			local aura = anyPaidAura()
			auras.Owned[aura.Id] = true
			T.expect(AuraLogic.Equip(auras, aura.Id)).toBe(true)
			T.expect(AuraLogic.Multiplier(auras)).toBe(aura.PowerMultiplier)
			T.expect(AuraLogic.WalkSpeed(auras)).toBe(AuraConfig.BaseWalkSpeed + aura.WalkSpeedBonus)
			T.expect(AuraLogic.WalkSpeed(auras) <= AuraConfig.MaxWalkSpeed).toBe(true)
		end)

		T.it("repairs a broken record instead of trusting it", function()
			local auras = { Owned = { Ghost = true }, Equipped = "Ghost" }
			T.expect(AuraLogic.Sanitize(auras :: any) > 0).toBe(true)
			T.expect(auras.Equipped).toBe(AuraConfig.DefaultAura)
			T.expect(auras.Owned.Ghost).toBe(nil)
		end)
	end)

	T.describe("RuneLogic", function()
		T.it("starts empty and multiplies by 1", function()
			local runes = RuneLogic.Fresh()
			T.expect(#runes.Equipped).toBe(0)
			T.expect(RuneLogic.Multiplier(runes)).toBe(1)
		end)

		T.it("never equips more copies than the player owns", function()
			local runes = RuneLogic.Fresh()
			RuneLogic.Add(runes, "TrainingCommon")
			T.expect(RuneLogic.Equip(runes, "TrainingCommon")).toBe(true)
			local ok, code = RuneLogic.Equip(runes, "TrainingCommon")
			T.expect(ok).toBe(false)
			T.expect(code).toBe("NotOwned")
			-- A second copy makes the same rune fit a second slot.
			RuneLogic.Add(runes, "TrainingCommon")
			T.expect(RuneLogic.Equip(runes, "TrainingCommon")).toBe(true)
			T.expect(RuneLogic.EquippedCount(runes, "TrainingCommon")).toBe(2)
		end)

		T.it("stops at the configured slot count", function()
			local runes = RuneLogic.Fresh()
			RuneLogic.Add(runes, "TrainingCommon", RuneConfig.Slots + 1)
			for _ = 1, RuneConfig.Slots do
				T.expect(RuneLogic.Equip(runes, "TrainingCommon")).toBe(true)
			end
			local ok, code = RuneLogic.Equip(runes, "TrainingCommon")
			T.expect(ok).toBe(false)
			T.expect(code).toBe("NoSlots")
		end)

		T.it("multiplies the equipped runes together", function()
			local runes = RuneLogic.Fresh()
			RuneLogic.Add(runes, "TrainingCommon")
			RuneLogic.Add(runes, "TrainingMythic")
			RuneLogic.Equip(runes, "TrainingCommon")
			RuneLogic.Equip(runes, "TrainingMythic")
			local expected = RuneConfig.Runes.TrainingCommon.PowerMultiplier * RuneConfig.Runes.TrainingMythic.PowerMultiplier
			T.expect(math.abs(RuneLogic.Multiplier(runes) - expected) < 1e-9).toBe(true)
		end)

		T.it("drops nothing for a player who barely touched the boss", function()
			local below = RuneConfig.Drop.MinShare / 2
			T.expect(RuneLogic.Roll("Training", below, rolls({ 0 }))).toBe(nil)
			-- Qualified, but the chance roll failed.
			T.expect(RuneLogic.Roll("Training", 1, rolls({ 0.999999 }))).toBe(nil)
		end)

		T.it("drops a rune of the world it was rolled for", function()
			local runeId = RuneLogic.Roll("Volcano", 1, rolls({ 0, 0 }))
			T.expect(runeId ~= nil).toBe(true)
			T.expect(RuneConfig.Runes[runeId :: string].WorldId).toBe("Volcano")
		end)

		T.it("drops the rarest rune on the highest pick", function()
			local runeId = RuneLogic.Roll("Training", 1, rolls({ 0, 0.999999 }))
			T.expect(RuneConfig.Runes[runeId :: string].Rarity).toBe("Mythic")
		end)

		T.it("repairs equipped runes the player does not own", function()
			local runes = { Owned = { Ghost = 3, TrainingCommon = 1 }, Equipped = { "TrainingCommon", "TrainingCommon", "Ghost" } }
			T.expect(RuneLogic.Sanitize(runes :: any) > 0).toBe(true)
			T.expect(#runes.Equipped).toBe(1)
			T.expect(runes.Equipped[1]).toBe("TrainingCommon")
			T.expect(runes.Owned.Ghost).toBe(nil)
		end)
	end)
end
