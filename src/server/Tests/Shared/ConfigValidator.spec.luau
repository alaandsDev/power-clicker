local Shared = game:GetService("ReplicatedStorage").Shared
local ConfigValidator = require(Shared.Formulas.ConfigValidator)
local TableUtil = require(Shared.Utils.TableUtil)
local DataTemplate = require(script.Parent.Parent.Parent.Services.DataService.DataTemplate)

-- Configs are frozen at boot, so broken variants are built from deep copies.
local function freshBundle()
	local bundle = TableUtil.DeepCopy(ConfigValidator.LoadBundle())
	bundle.StatKeys = DataTemplate.StatKeys()
	return bundle
end

local function hasErrorContaining(errors: { string }, fragment: string): boolean
	for _, message in errors do
		if string.find(message, fragment, 1, true) then
			return true
		end
	end
	return false
end

return function(T)
	T.describe("ConfigValidator", function()
		T.it("shipped configs are valid", function()
			local errors = ConfigValidator.Validate(freshBundle())
			if #errors > 0 then
				error(table.concat(errors, "\n"))
			end
		end)

		T.it("detects an egg dropping an unknown pet", function()
			local bundle = freshBundle()
			table.insert(bundle.Egg.Eggs.BasicEgg.Drops, { PetId = "Ghost", Weight = 1 })
			T.expect(hasErrorContaining(ConfigValidator.Validate(bundle), "unknown pet Ghost")).toBe(true)
		end)

		T.it("detects non-positive weights and prices", function()
			local bundle = freshBundle()
			bundle.Egg.Eggs.BasicEgg.Drops[1].Weight = 0
			bundle.Egg.Eggs.BasicEgg.Price = -1
			local errors = ConfigValidator.Validate(bundle)
			T.expect(hasErrorContaining(errors, "Weight must be > 0")).toBe(true)
			T.expect(hasErrorContaining(errors, "Price must be > 0")).toBe(true)
		end)

		T.it("detects rewards referencing unknown boosts", function()
			local bundle = freshBundle()
			bundle.Quest.Quests.Click100.Rewards = { { Type = "Boost", BoostId = "Nope", Amount = 1 } }
			T.expect(hasErrorContaining(ConfigValidator.Validate(bundle), "unknown boost Nope")).toBe(true)
		end)

		T.it("detects duplicated product ids", function()
			local bundle = freshBundle()
			bundle.Product.DeveloperProducts.GemsSmall.ProductId = 123
			bundle.Product.DeveloperProducts.GemsLarge.ProductId = 123
			T.expect(hasErrorContaining(ConfigValidator.Validate(bundle), "duplicated id")).toBe(true)
		end)

		T.it("detects achievements on unknown stats", function()
			local bundle = freshBundle()
			bundle.Achievement.Achievements.FirstClick.Stat = "NotAStat"
			T.expect(hasErrorContaining(ConfigValidator.Validate(bundle), "unknown stat NotAStat")).toBe(true)
		end)

		T.it("detects ClientToServer remotes without rate limit", function()
			local bundle = freshBundle()
			bundle.Remotes.Remotes.Evil = { Kind = "Event", Direction = "ClientToServer" }
			T.expect(hasErrorContaining(ConfigValidator.Validate(bundle), "Remote Evil")).toBe(true)
		end)

		T.it("detects malformed pet/egg icons", function()
			local bundle = freshBundle()
			bundle.Pet.Pets.Dog.Icon = "https://example.com/dog.png"
			bundle.Egg.Eggs.BasicEgg.Icon = "rbxassetid://abc"
			local errors = ConfigValidator.Validate(bundle)
			T.expect(hasErrorContaining(errors, "Pet Dog: Icon")).toBe(true)
			T.expect(hasErrorContaining(errors, "Egg BasicEgg: Icon")).toBe(true)
		end)

		T.it("accepts real asset ids", function()
			local bundle = freshBundle()
			bundle.Pet.Pets.Dog.Icon = "rbxassetid://123456789"
			T.expect(hasErrorContaining(ConfigValidator.Validate(bundle), "Pet Dog: Icon")).toBe(false)
		end)

		T.it("detects a zone target that pays more than it costs", function()
			local bundle = freshBundle()
			bundle.Zone.Zones.Meadow.Target.Reward = bundle.Zone.Zones.Meadow.Target.Hp
			T.expect(hasErrorContaining(ConfigValidator.Validate(bundle), "Reward must be smaller than Hp")).toBe(true)
		end)

		T.it("detects a zone in an unknown world", function()
			local bundle = freshBundle()
			bundle.Zone.Zones.Meadow.WorldId = "Nowhere"
			T.expect(hasErrorContaining(ConfigValidator.Validate(bundle), "unknown world Nowhere")).toBe(true)
		end)

		T.it("detects a disabled default world", function()
			local bundle = freshBundle()
			bundle.World.Worlds.Training.Enabled = false
			T.expect(hasErrorContaining(ConfigValidator.Validate(bundle), "DefaultWorld")).toBe(true)
		end)
	end)
end
