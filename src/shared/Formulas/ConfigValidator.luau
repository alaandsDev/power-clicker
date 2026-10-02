--!strict
--[[
	ConfigValidator
	Cross-checks every config module for broken references and unsafe values
	(missing pets in eggs, non-positive prices, unknown boosts in rewards,
	duplicated product ids, remotes without rate limits...).

	Runs on server boot (ServerBootstrap): errors abort the boot in Studio and
	are logged loudly in live servers. Pure: accepts a config bundle so tests can
	feed broken configs.
]]

local Shared = script.Parent.Parent
local Config = Shared.Config
local Types = require(Shared.Types)

type RewardData = Types.RewardData

export type ConfigBundle = {
	Pet: any,
	Egg: any,
	World: any,
	Zone: any,
	Upgrade: any,
	Boost: any,
	Product: any,
	Quest: any,
	Achievement: any,
	DailyReward: any,
	Remotes: any,
	Ambient: any?,
	Aura: any?,
	Rune: any?,
	Wall: any?,
	StatKeys: { [string]: boolean }?, -- valid Stat names for achievements
}

local ConfigValidator = {}

local CURRENCIES = { Power = true, Gems = true }

local function isPositive(value: any): boolean
	return type(value) == "number" and value == value and value > 0 and value < math.huge
end

local function isPositiveInteger(value: any): boolean
	return isPositive(value) and value % 1 == 0
end

-- "TODO_ASSET" (placeholder) or "rbxassetid://<digits>".
local function isValidIcon(value: any): boolean
	return type(value) == "string" and (value == "TODO_ASSET" or string.match(value, "^rbxassetid://%d+$") ~= nil)
end

function ConfigValidator.LoadBundle(): ConfigBundle
	return {
		Pet = require(Config.PetConfig),
		Egg = require(Config.EggConfig),
		World = require(Config.WorldConfig),
		Zone = require(Config.ZoneConfig),
		Upgrade = require(Config.UpgradeConfig),
		Boost = require(Config.BoostConfig),
		Product = require(Config.ProductConfig),
		Quest = require(Config.QuestConfig),
		Achievement = require(Config.AchievementConfig),
		DailyReward = require(Config.DailyRewardConfig),
		Remotes = require(Shared.Net.RemoteDefinitions),
		Ambient = require(Config.AmbientConfig),
		Aura = require(Config.AuraConfig),
		Wall = require(Config.WallConfig),
		Rune = require(Config.RuneConfig),
	}
end

function ConfigValidator.Validate(bundle: ConfigBundle): { string }
	local errors: { string } = {}
	local function fail(message: string)
		table.insert(errors, message)
	end

	local pets = bundle.Pet.Pets
	local rarities = bundle.Pet.Rarities
	local variants = bundle.Pet.Variants
	local eggs = bundle.Egg.Eggs
	local worlds = bundle.World.Worlds
	local boosts = bundle.Boost.Boosts

	local function validateRewards(where: string, rewards: { RewardData }?)
		if type(rewards) ~= "table" then
			fail(where .. ": Rewards must be a table")
			return
		end
		for i, reward in rewards do
			local at = string.format("%s reward #%d", where, i)
			if reward.Type == "Currency" then
				if not (reward.Currency and CURRENCIES[reward.Currency]) then
					fail(at .. ": unknown currency " .. tostring(reward.Currency))
				end
				if not isPositive(reward.Amount) then
					fail(at .. ": Amount must be > 0")
				end
			elseif reward.Type == "Boost" then
				if not (reward.BoostId and boosts[reward.BoostId]) then
					fail(at .. ": unknown boost " .. tostring(reward.BoostId))
				end
				if not isPositiveInteger(reward.Amount) then
					fail(at .. ": boost Amount must be a positive integer")
				end
			elseif reward.Type == "Pet" then
				if not (reward.PetId and pets[reward.PetId]) then
					fail(at .. ": unknown pet " .. tostring(reward.PetId))
				end
				if reward.Variant ~= nil and not variants[reward.Variant] then
					fail(at .. ": unknown variant " .. tostring(reward.Variant))
				end
			else
				fail(at .. ": unknown reward Type " .. tostring(reward.Type))
			end
		end
	end

	-- Pets
	for id, pet in pets do
		local at = "Pet " .. tostring(id)
		if pet.Id ~= id then
			fail(at .. ": Id field does not match key")
		end
		if not rarities[pet.Rarity] then
			fail(at .. ": unknown rarity " .. tostring(pet.Rarity))
		end
		if not isPositive(pet.Bonus) then
			fail(at .. ": Bonus must be > 0")
		end
		if not isValidIcon(pet.Icon) then
			fail(at .. ": Icon must be \"TODO_ASSET\" or \"rbxassetid://<id>\"")
		end
		if not worlds[pet.WorldId] then
			fail(at .. ": unknown world " .. tostring(pet.WorldId))
		end
		if pet.EggId ~= nil then
			local egg = eggs[pet.EggId]
			if not egg then
				fail(at .. ": unknown egg " .. tostring(pet.EggId))
			else
				local found = false
				for _, drop in egg.Drops do
					if drop.PetId == id then
						found = true
					end
				end
				if not found then
					fail(at .. ": says EggId " .. pet.EggId .. " but that egg does not drop it")
				end
			end
		end
	end

	for id, variant in variants do
		if variant.Id ~= id or not isPositive(variant.MultiplierScale) then
			fail("Variant " .. tostring(id) .. ": invalid Id or MultiplierScale")
		end
	end
	if not (variants.Normal and variants.Normal.Enabled) then
		fail("Variant Normal must exist and be enabled")
	end

	-- Eggs
	for id, egg in eggs do
		local at = "Egg " .. tostring(id)
		if egg.Id ~= id then
			fail(at .. ": Id field does not match key")
		end
		if not worlds[egg.WorldId] then
			fail(at .. ": unknown world " .. tostring(egg.WorldId))
		end
		if not CURRENCIES[egg.Currency] then
			fail(at .. ": unknown currency " .. tostring(egg.Currency))
		end
		if not isPositive(egg.Price) then
			fail(at .. ": Price must be > 0")
		end
		if not isValidIcon(egg.Icon) then
			fail(at .. ": Icon must be \"TODO_ASSET\" or \"rbxassetid://<id>\"")
		end
		if #egg.Drops == 0 then
			fail(at .. ": has no drops")
		end
		local seen: { [string]: boolean } = {}
		for _, drop in egg.Drops do
			if not pets[drop.PetId] then
				fail(at .. ": drops unknown pet " .. tostring(drop.PetId))
			elseif pets[drop.PetId].EggId ~= id then
				fail(at .. ": drops " .. drop.PetId .. " whose EggId is " .. tostring(pets[drop.PetId].EggId))
			end
			if seen[drop.PetId] then
				fail(at .. ": duplicated drop " .. tostring(drop.PetId))
			end
			seen[drop.PetId] = true
			if not isPositive(drop.Weight) then
				fail(at .. ": drop " .. tostring(drop.PetId) .. " Weight must be > 0")
			end
		end
	end
	if not isPositive(bundle.Egg.MaxLuckMultiplier) then
		fail("EggConfig.MaxLuckMultiplier must be > 0")
	end

	-- Zones (training islands with breakable targets)
	if bundle.Zone then
		local zoneOrders: { [string]: { [number]: string } } = {}
		for id, zone in bundle.Zone.Zones do
			local at = "Zone " .. tostring(id)
			if zone.Id ~= id then
				fail(at .. ": Id field does not match key")
			end
			if not worlds[zone.WorldId] then
				fail(at .. ": unknown world " .. tostring(zone.WorldId))
			end
			if not isPositive(zone.Multiplier) then
				fail(at .. ": Multiplier must be > 0")
			end
			if not isPositive(zone.Radius) then
				fail(at .. ": Radius must be > 0")
			end
			if zone.Requirement.Power < 0 or zone.Requirement.Rebirths < 0 then
				fail(at .. ": Requirement must not be negative")
			end
			local byWorld = zoneOrders[zone.WorldId] or {}
			zoneOrders[zone.WorldId] = byWorld
			if byWorld[zone.Order] then
				fail(at .. ": duplicated Order with " .. byWorld[zone.Order])
			end
			byWorld[zone.Order] = id
			local target = zone.Target
			if not isPositive(target.Hp) or not isPositive(target.Reward) or not isPositive(target.RespawnSeconds) or not isPositive(target.Count) then
				fail(at .. ": Target Hp/Reward/RespawnSeconds/Count must be > 0")
			elseif target.Reward >= target.Hp then
				-- Otherwise breaking a target pays more Power than it costs.
				fail(at .. ": Target Reward must be smaller than Hp")
			end
		end
	end

	-- Worlds
	local default = worlds[bundle.World.DefaultWorld]
	if not default or not default.Enabled then
		fail("WorldConfig.DefaultWorld must exist and be enabled")
	end
	local orders: { [number]: string } = {}
	for id, world in worlds do
		local at = "World " .. tostring(id)
		if world.Id ~= id then
			fail(at .. ": Id field does not match key")
		end
		if not isPositive(world.Multiplier) then
			fail(at .. ": Multiplier must be > 0")
		end
		if orders[world.Order] then
			fail(at .. ": duplicated Order with " .. orders[world.Order])
		end
		orders[world.Order] = id
		if not CURRENCIES[world.Requirement.Currency] then
			fail(at .. ": unknown requirement currency")
		end
		if bundle.Ambient and not bundle.Ambient.Presets[world.Ambient] then
			fail(at .. ": unknown ambient preset " .. tostring(world.Ambient))
		end
		for _, eggId in world.Eggs do
			if not eggs[eggId] then
				fail(at .. ": unknown egg " .. tostring(eggId))
			elseif eggs[eggId].WorldId ~= id then
				fail(at .. ": lists egg " .. eggId .. " that belongs to " .. eggs[eggId].WorldId)
			end
		end
	end

	-- Upgrades
	local upgradeGroups: { { Name: string, Upgrades: { [string]: any } } } = {
		{ Name = "Temporary", Upgrades = bundle.Upgrade.Temporary },
		{ Name = "Permanent", Upgrades = bundle.Upgrade.Permanent },
	}
	local seenUpgradeIds: { [string]: string } = {}
	for _, groupInfo in upgradeGroups do
		local groupName = groupInfo.Name
		for id, upgrade in groupInfo.Upgrades do
			local at = string.format("Upgrade %s.%s", groupName, tostring(id))
			-- BuyUpgrade receives only an id, so ids must be unique across groups.
			if seenUpgradeIds[id] then
				fail(at .. ": id also used in " .. seenUpgradeIds[id])
			end
			seenUpgradeIds[id] = groupName
			if upgrade.Id ~= id then
				fail(at .. ": Id field does not match key")
			end
			if not isPositive(upgrade.BaseCost) then
				fail(at .. ": BaseCost must be > 0")
			end
			if type(upgrade.CostGrowth) ~= "number" or upgrade.CostGrowth < 1 then
				fail(at .. ": CostGrowth must be >= 1")
			end
			if not isPositiveInteger(upgrade.MaxLevel) then
				fail(at .. ": MaxLevel must be a positive integer")
			end
			if not isPositive(upgrade.EffectPerLevel) then
				fail(at .. ": EffectPerLevel must be > 0")
			end
			local expected = if groupName == "Temporary" then "Power" else "Gems"
			if upgrade.Currency ~= expected then
				fail(at .. ": must cost " .. expected)
			end
		end
	end

	-- Boosts
	for id, boost in boosts do
		local at = "Boost " .. tostring(id)
		if boost.Id ~= id then
			fail(at .. ": Id field does not match key")
		end
		if type(boost.Multiplier) ~= "number" or boost.Multiplier < 1 then
			fail(at .. ": Multiplier must be >= 1")
		end
		if not isPositive(boost.DurationSeconds) or not isPositive(boost.MaxStoredSeconds) then
			fail(at .. ": durations must be > 0")
		elseif boost.MaxStoredSeconds < boost.DurationSeconds then
			fail(at .. ": MaxStoredSeconds must be >= DurationSeconds")
		end
	end

	-- Products (ids may be 0 = TODO, but real ids must be unique)
	local seenIds: { [number]: string } = {}
	for key, pass in bundle.Product.GamePasses do
		if pass.Key ~= key then
			fail("GamePass " .. tostring(key) .. ": Key does not match")
		end
		if pass.GamePassId ~= 0 then
			if seenIds[pass.GamePassId] then
				fail("GamePass " .. key .. ": duplicated id with " .. seenIds[pass.GamePassId])
			end
			seenIds[pass.GamePassId] = key
		end
	end
	for key, product in bundle.Product.DeveloperProducts do
		if product.Key ~= key then
			fail("Product " .. tostring(key) .. ": Key does not match")
		end
		if product.ProductId ~= 0 then
			if seenIds[product.ProductId] then
				fail("Product " .. key .. ": duplicated id with " .. seenIds[product.ProductId])
			end
			seenIds[product.ProductId] = key
		end
		validateRewards("Product " .. tostring(key), product.Rewards)
	end

	-- Quests
	for id, quest in bundle.Quest.Quests do
		local at = "Quest " .. tostring(id)
		if quest.Id ~= id then
			fail(at .. ": Id field does not match key")
		end
		if not isPositive(quest.Target) then
			fail(at .. ": Target must be > 0")
		end
		validateRewards(at, quest.Rewards)
	end

	-- Achievements
	for id, achievement in bundle.Achievement.Achievements do
		local at = "Achievement " .. tostring(id)
		if achievement.Id ~= id then
			fail(at .. ": Id field does not match key")
		end
		local byStat = achievement.Stat ~= nil
		local byWorld = achievement.WorldId ~= nil
		if byStat == byWorld then
			fail(at .. ": needs exactly one of Stat or WorldId")
		end
		if byStat then
			if not isPositive(achievement.Threshold) then
				fail(at .. ": Threshold must be > 0")
			end
			if bundle.StatKeys and not bundle.StatKeys[achievement.Stat] then
				fail(at .. ": unknown stat " .. tostring(achievement.Stat))
			end
		end
		if byWorld and not worlds[achievement.WorldId] then
			fail(at .. ": unknown world " .. tostring(achievement.WorldId))
		end
		validateRewards(at, achievement.Rewards)
	end

	-- Daily rewards
	if #bundle.DailyReward.Days == 0 then
		fail("DailyRewardConfig: no days")
	end
	for day, rewards in bundle.DailyReward.Days do
		validateRewards("DailyReward day " .. day, rewards)
	end
	if bundle.DailyReward.StreakResetSeconds <= bundle.DailyReward.ClaimIntervalSeconds then
		fail("DailyRewardConfig: StreakResetSeconds must be > ClaimIntervalSeconds")
	end

	-- Ovos presos a estágio da torre: o estágio tem de existir.
	if bundle.Wall then
		local stageIds: { [string]: boolean } = {}
		for _, stage in bundle.Wall.Stages do
			stageIds[stage.Id] = true
		end
		for id, egg in eggs do
			if egg.RequiredStage ~= nil and not stageIds[egg.RequiredStage] then
				fail(string.format("Egg %s: unknown RequiredStage %s", tostring(id), tostring(egg.RequiredStage)))
			end
		end
	end

	-- Auras (a Gem purchase that gives speed and Power)
	if bundle.Aura then
		local auraConfig = bundle.Aura
		if not auraConfig.Auras[auraConfig.DefaultAura] then
			fail("AuraConfig: DefaultAura " .. tostring(auraConfig.DefaultAura) .. " does not exist")
		end
		if auraConfig.MaxWalkSpeed < auraConfig.BaseWalkSpeed then
			fail("AuraConfig: MaxWalkSpeed must be >= BaseWalkSpeed")
		end
		for id, aura in auraConfig.Auras do
			local at = "Aura " .. tostring(id)
			if aura.Id ~= id then
				fail(at .. ": Id does not match its key")
			end
			if not rarities[aura.Rarity] then
				fail(at .. ": unknown rarity " .. tostring(aura.Rarity))
			end
			if type(aura.Price) ~= "number" or aura.Price < 0 then
				fail(at .. ": Price must be >= 0")
			end
			if not isPositive(aura.PowerMultiplier) or aura.PowerMultiplier < 1 then
				fail(at .. ": PowerMultiplier must be >= 1")
			end
			if type(aura.WalkSpeedBonus) ~= "number" or aura.WalkSpeedBonus < 0 then
				fail(at .. ": WalkSpeedBonus must be >= 0")
			end
			if auraConfig.BaseWalkSpeed + aura.WalkSpeedBonus > auraConfig.MaxWalkSpeed then
				fail(at .. ": WalkSpeedBonus goes past MaxWalkSpeed")
			end
			-- A free aura that is not the default one would be a shop item nobody pays for.
			if aura.Price == 0 and id ~= auraConfig.DefaultAura then
				fail(at .. ": only the default aura may be free")
			end
		end
	end

	-- Runes (boss drops)
	if bundle.Rune then
		local runeConfig = bundle.Rune
		if not isPositiveInteger(runeConfig.Slots) then
			fail("RuneConfig: Slots must be a positive integer")
		end
		local drop = runeConfig.Drop
		if drop.MinChance > drop.MaxChance or drop.MaxChance > 1 or drop.MinChance <= 0 then
			fail("RuneConfig.Drop: expected 0 < MinChance <= MaxChance <= 1")
		end
		if drop.MinShare <= 0 or drop.MinShare >= 1 then
			fail("RuneConfig.Drop: MinShare must be between 0 and 1")
		end
		for id, rune in runeConfig.Runes do
			local at = "Rune " .. tostring(id)
			if rune.Id ~= id then
				fail(at .. ": Id does not match its key")
			end
			if not worlds[rune.WorldId] then
				fail(at .. ": unknown world " .. tostring(rune.WorldId))
			end
			if not rarities[rune.Rarity] then
				fail(at .. ": unknown rarity " .. tostring(rune.Rarity))
			end
			if not isPositive(rune.PowerMultiplier) or rune.PowerMultiplier <= 1 then
				fail(at .. ": PowerMultiplier must be > 1")
			end
			if not isPositive(rune.Weight) then
				fail(at .. ": Weight must be > 0")
			end
		end
	end

	-- Remotes
	for name, spec in bundle.Remotes.Remotes do
		if spec.Direction == "ClientToServer" then
			local limit = spec.RateLimit
			if not limit or not isPositive(limit.Capacity) or not isPositive(limit.RefillPerSecond) then
				fail("Remote " .. tostring(name) .. ": ClientToServer remotes need a valid RateLimit")
			end
		end
	end

	table.sort(errors)
	return errors
end

return ConfigValidator
