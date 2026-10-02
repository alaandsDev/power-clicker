--!strict
--[[
	PurchaseLogic
	Pure receipt ledger + product lookups for MonetizationService.

	Idempotency: a PurchaseId recorded in data.Purchases.ProcessedReceipts is
	never granted again. The ledger keeps the most recent ReceiptLedgerSize
	ids (FIFO). Roblox only retries receipts that were NOT acknowledged with
	PurchaseGranted, and we only acknowledge after the ledger entry is saved,
	so a bounded ledger is sufficient.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local ProductConfig = require(Shared.Config.ProductConfig)

type PlayerData = Types.PlayerData
type DeveloperProductData = Types.DeveloperProductData
type GamePassData = Types.GamePassData

local PurchaseLogic = {}

local productsById: { [number]: DeveloperProductData } = {}
for _, product in ProductConfig.DeveloperProducts do
	if product.ProductId ~= 0 then
		productsById[product.ProductId] = product
	end
end
local passesById: { [number]: GamePassData } = {}
for _, pass in ProductConfig.GamePasses do
	if pass.GamePassId ~= 0 then
		passesById[pass.GamePassId] = pass
	end
end

function PurchaseLogic.ProductById(productId: number): DeveloperProductData?
	return productsById[productId]
end

function PurchaseLogic.PassById(passId: number): GamePassData?
	return passesById[passId]
end

function PurchaseLogic.IsProcessed(data: PlayerData, purchaseId: string): boolean
	return data.Purchases.ProcessedReceipts[purchaseId] ~= nil
end

function PurchaseLogic.IsOfferClaimed(data: PlayerData, key: string): boolean
	return data.Purchases.OneTimeOffersClaimed[key] == true
end

-- Records a processed receipt (call in the same synchronous step as the grant).
function PurchaseLogic.Record(data: PlayerData, purchaseId: string, now: number, robuxSpent: number, product: DeveloperProductData, ledgerSize: number?)
	local purchases = data.Purchases
	local size = ledgerSize or ProductConfig.ReceiptLedgerSize
	purchases.ProcessedReceipts[purchaseId] = now
	table.insert(purchases.ReceiptOrder, purchaseId)
	while #purchases.ReceiptOrder > size do
		local oldest = table.remove(purchases.ReceiptOrder, 1)
		if oldest then
			purchases.ProcessedReceipts[oldest] = nil
		end
	end
	if robuxSpent == robuxSpent and robuxSpent > 0 then
		purchases.TotalRobuxSpent += robuxSpent
	end
	if product.OneTimeOffer then
		purchases.OneTimeOffersClaimed[product.Key] = true
	end
end

return PurchaseLogic
