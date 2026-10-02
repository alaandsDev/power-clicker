--[[
	Receipt ledger / purchase rules (pure). The Roblox purchase flow itself
	(ProcessReceipt, prompts) is exercised manually — see TESTING.md.
]]

local Server = script.Parent.Parent.Parent
local Shared = game:GetService("ReplicatedStorage").Shared
local PurchaseLogic = require(Server.Logic.PurchaseLogic)
local RewardLogic = require(Server.Logic.RewardLogic)
local PetLogic = require(Server.Logic.PetLogic)
local DataTemplate = require(Server.Services.DataService.DataTemplate)
local ProductConfig = require(Shared.Config.ProductConfig)

local function fresh()
	return DataTemplate.Create(0)
end

return function(T)
	local gems = ProductConfig.DeveloperProducts.GemsSmall
	local starter = ProductConfig.DeveloperProducts.StarterPack

	T.describe("PurchaseLogic ledger", function()
		T.it("records a receipt once (idempotency check)", function()
			local data = fresh()
			T.expect(PurchaseLogic.IsProcessed(data, "P1")).toBe(false)
			PurchaseLogic.Record(data, "P1", 10, 49, gems)
			T.expect(PurchaseLogic.IsProcessed(data, "P1")).toBe(true)
			T.expect(data.Purchases.TotalRobuxSpent).toBe(49)
		end)
		T.it("keeps only the most recent N receipts (FIFO)", function()
			local data = fresh()
			for i = 1, 5 do
				PurchaseLogic.Record(data, "P" .. i, i, 0, gems, 3)
			end
			T.expect(#data.Purchases.ReceiptOrder).toBe(3)
			T.expect(PurchaseLogic.IsProcessed(data, "P1")).toBe(false)
			T.expect(PurchaseLogic.IsProcessed(data, "P2")).toBe(false)
			T.expect(PurchaseLogic.IsProcessed(data, "P5")).toBe(true)
		end)
		T.it("one-time offers are marked claimed", function()
			local data = fresh()
			T.expect(PurchaseLogic.IsOfferClaimed(data, "StarterPack")).toBe(false)
			PurchaseLogic.Record(data, "S1", 0, 99, starter)
			T.expect(PurchaseLogic.IsOfferClaimed(data, "StarterPack")).toBe(true)
		end)
		T.it("ignores NaN robux amounts", function()
			local data = fresh()
			PurchaseLogic.Record(data, "P1", 0, 0 / 0, gems)
			T.expect(data.Purchases.TotalRobuxSpent).toBe(0)
		end)
		T.it("unconfigured ids (0) are never resolvable", function()
			T.expect(PurchaseLogic.ProductById(0)).toBeNil()
			T.expect(PurchaseLogic.PassById(0)).toBeNil()
		end)
	end)

	T.describe("Paid rewards", function()
		T.it("starter pack rewards are valid", function()
			T.expect((RewardLogic.CanGrant(fresh(), starter.Rewards))).toBe(true)
		end)
		T.it("paid pet rewards are granted even with a full inventory", function()
			local data = fresh()
			for _ = 1, PetLogic.GetInventoryCapacity(data) do
				PetLogic.Add(data, "Dog", nil, 0)
			end
			T.expect((RewardLogic.Grant(data, starter.Rewards, 0))).toBe(false) -- free source: blocked
			T.expect((RewardLogic.Grant(data, starter.Rewards, 0, { IgnoreCapacity = true }))).toBe(true) -- paid: granted
			T.expect(PetLogic.Count(data)).toBe(PetLogic.GetInventoryCapacity(data) + 1)
		end)
		T.it("every developer product has valid rewards", function()
			for key, product in ProductConfig.DeveloperProducts do
				if #product.Rewards > 0 and not RewardLogic.CanGrant(fresh(), product.Rewards) then
					error("invalid rewards in product " .. key)
				end
			end
		end)
	end)
end
