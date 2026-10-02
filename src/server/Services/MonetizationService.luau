--!strict
--[[
	MonetizationService
	Game Passes + Developer Products, using the official Roblox flow.

	GAME PASSES
	- Ownership: MarketplaceService:UserOwnsGamePassAsync on load (retried),
	  plus MarketplaceService.PromptGamePassPurchaseFinished (a SERVER event
	  fired by Roblox) for purchases made in-session. Never a client claim.
	- Benefits (ProductConfig): PowerMultiplier → "GamePass" power layer;
	  LuckMultiplier → luck provider; ExtraEquipSlots → PetService;
	  AutoClick → server auto-click ticks (toggle via "SetAutoClick");
	  Vip → "VIP" attribute (chat tag) + one-time exclusive pet.
	- Owned passes are mirrored as player attributes "Pass_<Key>" (display).

	DEVELOPER PRODUCTS — MarketplaceService.ProcessReceipt:
	  1. player in server with data loaded, else NotProcessedYet (Roblox retries)
	  2. product id configured, else NotProcessedYet (+ error log; never guess)
	  3. PurchaseId already in ledger → PurchaseGranted (idempotent)
	  4. grant (pets ignore inventory capacity: the player paid) + record the
	     receipt IN THE SAME synchronous step
	  5. DataService.SaveNow → PurchaseGranted; if the save fails →
	     NotProcessedYet (the in-memory ledger prevents a double grant when
	     Roblox retries in this session; if the server dies, nothing was
	     saved, so the retry grants exactly once)

	PROMPTS: "PromptPurchase"(key) — the server validates the key, refuses
	unconfigured ids (0), owned passes and claimed one-time offers, then calls
	PromptGamePassPurchase / PromptProductPurchase itself.
]]

local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Guard = require(Shared.Utils.Guard)
local Logger = require(Shared.Utils.Logger)
local Signal = require(Shared.Utils.Signal)
local ProductConfig = require(Shared.Config.ProductConfig)

local NetService = require(script.Parent.NetService)
local DataService = require(script.Parent.DataService)
local PowerService = require(script.Parent.PowerService)
local EggService = require(script.Parent.EggService)
local PetService = require(script.Parent.PetService)
local ClickService = require(script.Parent.ClickService)
local OverdriveService = require(script.Parent.OverdriveService)
local RewardService = require(script.Parent.RewardService)
local PurchaseLogic = require(script.Parent.Parent.Logic.PurchaseLogic)

type RemoteResponse = Types.RemoteResponse
type DeveloperProductData = Types.DeveloperProductData

local OWNERSHIP_RETRIES = 3
local VIP_PET_OFFER_KEY = "VipPet"
local VIP_PET_ID = "VipCrownCat"

local log = Logger.new("Monetization")

local MonetizationService = {
	-- (player, passKey)
	PassOwned = Signal.new() :: Signal.Signal<Player, string>,
	-- (player, productKey, purchaseId)
	ProductGranted = Signal.new() :: Signal.Signal<Player, string, string>,
}

local owned: { [Player]: { [string]: boolean } } = {}

function MonetizationService.OwnsPass(player: Player, key: string): boolean
	local passes = owned[player]
	return passes ~= nil and passes[key] == true
end

--[[
	Product of a numeric benefit over owned passes (1 when none).
	Passes of the same ladder (x2 / x4 / x8) do NOT multiply with each other:
	only the highest step owned counts, so upgrading is an upgrade and not a
	stack of everything bought before.
]]
local function passMultiplier(player: Player, benefit: string): number
	local total = 1
	local passes = owned[player]
	if not passes then
		return total
	end
	local ladders: { [string]: number } = {}
	for key in passes do
		local pass = ProductConfig.GamePasses[key]
		local value = pass and (pass.Benefits :: any)[benefit]
		if type(value) ~= "number" or value < 1 then
			continue
		end
		local ladder = pass.Ladder
		if ladder then
			ladders[ladder] = math.max(ladders[ladder] or 1, value)
		else
			total *= value
		end
	end
	for _, value in ladders do
		total *= value
	end
	return total
end

local function applyBenefits(player: Player)
	local passes: { [string]: boolean } = owned[player] or {}
	local extraSlots = 0
	local autoClick = false
	local vip = false
	for key in passes do
		local pass = ProductConfig.GamePasses[key]
		if pass then
			extraSlots += pass.Benefits.ExtraEquipSlots or 0
			autoClick = autoClick or pass.Benefits.AutoClick == true
			vip = vip or pass.Benefits.Vip == true
		end
		player:SetAttribute("Pass_" .. key, true)
	end
	PetService.SetExtraEquipSlots(player, extraSlots)
	if autoClick and not ClickService.IsAutoClickEnabled(player) then
		ClickService.SetAutoClick(player, true)
	end
	player:SetAttribute("VIP", vip)
	PowerService.Invalidate(player)

	-- VIP exclusive pet, granted once per account.
	local data = DataService.GetData(player)
	if vip and data and not data.Purchases.OneTimeOffersClaimed[VIP_PET_OFFER_KEY] then
		local ok = RewardService.Grant(player, { { Type = "Pet", PetId = VIP_PET_ID, Variant = "Normal" } }, "VIP", { IgnoreCapacity = true })
		if ok then
			data.Purchases.OneTimeOffersClaimed[VIP_PET_OFFER_KEY] = true
		end
	end
end

local function setOwned(player: Player, key: string)
	local passes = owned[player]
	if not passes then
		passes = {}
		owned[player] = passes
	end
	if not passes[key] then
		passes[key] = true
		MonetizationService.PassOwned:Fire(player, key)
	end
end

local function loadOwnership(player: Player)
	-- Mirror claimed one-time offers for the shop UI (display only).
	local data = DataService.GetData(player)
	if data then
		for key, claimed in data.Purchases.OneTimeOffersClaimed do
			if claimed then
				player:SetAttribute("Offer_" .. key, true)
			end
		end
	end
	for key, pass in ProductConfig.GamePasses do
		if pass.GamePassId ~= 0 then
			for attempt = 1, OWNERSHIP_RETRIES do
				local ok, result = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.GamePassId)
				if ok then
					if result then
						setOwned(player, key)
					end
					break
				elseif attempt == OWNERSHIP_RETRIES then
					log:Warn(string.format("user=%d ownership check failed for %s: %s", player.UserId, key, tostring(result)))
				else
					task.wait(attempt)
				end
			end
		end
	end
	if player.Parent == Players then
		applyBenefits(player)
	end
end

-- Grants a product's contents. Shared by ProcessReceipt and Studio testing.
local function grantProduct(player: Player, product: DeveloperProductData, purchaseId: string, robuxSpent: number): boolean
	local data = DataService.GetData(player)
	if not data then
		return false
	end
	if PurchaseLogic.IsProcessed(data, purchaseId) then
		return true
	end
	if product.OneTimeOffer and PurchaseLogic.IsOfferClaimed(data, product.Key) then
		-- Should never happen (prompt is refused), but the player paid: honor it.
		log:Warn(string.format("user=%d bought one-time offer %s again; granting anyway", player.UserId, product.Key))
	end

	if product.Key == "InstantOverdrive" then
		OverdriveService.ActivateOrExtend(player, "Product")
	end
	if #product.Rewards > 0 then
		local ok, code = RewardService.Grant(player, product.Rewards, "Product:" .. product.Key, { IgnoreCapacity = true })
		if not ok then
			log:Error(string.format("user=%d product %s grant failed: %s", player.UserId, product.Key, tostring(code)))
			return false
		end
	end
	PurchaseLogic.Record(data, purchaseId, os.time(), robuxSpent, product)
	if product.OneTimeOffer then
		player:SetAttribute("Offer_" .. product.Key, true) -- display only
	end
	log:Info(string.format("user=%d granted %s (purchase %s)", player.UserId, product.Key, purchaseId))
	NetService.FireClient("Notify", player, "Purchase", { Key = product.Key })
	MonetizationService.ProductGranted:Fire(player, product.Key, purchaseId)
	return true
end

local function processReceipt(receipt: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player or not DataService.IsLoaded(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local product = PurchaseLogic.ProductById(receipt.ProductId)
	if not product then
		log:Error(string.format("Receipt for unknown product id %s (user=%d)", tostring(receipt.ProductId), player.UserId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(receipt.PurchaseId)
	local granted = grantProduct(player, product, purchaseId, tonumber(receipt.CurrencySpent) or 0)
	if not granted then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- Only acknowledge once the ledger is persisted.
	if not DataService.SaveNow(player) then
		log:Warn(string.format("user=%d receipt %s granted but not saved yet; Roblox will retry", player.UserId, purchaseId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

--[[
	A ladder step (4x Power) can only be bought once the step before it (2x) is
	owned. Checked HERE and not only in the shop UI: the prompt is a remote.
]]
local function ladderBlocked(player: Player, pass: Types.GamePassData): boolean
	local ladder, step = pass.Ladder, pass.LadderStep
	if not ladder or not step or step <= 1 then
		return false
	end
	for _, other in ProductConfig.GamePasses do
		if other.Ladder == ladder and other.LadderStep == step - 1 then
			return not MonetizationService.OwnsPass(player, other.Key)
		end
	end
	return false
end

local function prompt(player: Player, key: string): RemoteResponse
	local pass = ProductConfig.GamePasses[key]
	if pass then
		if pass.GamePassId == 0 then
			return { Ok = false, Code = "NotAvailable" }
		end
		if MonetizationService.OwnsPass(player, key) then
			return { Ok = false, Code = "AlreadyOwned" }
		end
		if ladderBlocked(player, pass) then
			return { Ok = false, Code = "NeedsPreviousPass" }
		end
		MarketplaceService:PromptGamePassPurchase(player, pass.GamePassId)
		return { Ok = true }
	end
	local product = ProductConfig.DeveloperProducts[key]
	if product then
		if product.ProductId == 0 then
			return { Ok = false, Code = "NotAvailable" }
		end
		local data = DataService.GetData(player)
		if product.OneTimeOffer and data and PurchaseLogic.IsOfferClaimed(data, product.Key) then
			return { Ok = false, Code = "AlreadyOwned" }
		end
		MarketplaceService:PromptProductPurchase(player, product.ProductId)
		return { Ok = true }
	end
	return { Ok = false, Code = "InvalidRequest" }
end

local function setAutoClick(player: Player, enabled: boolean): RemoteResponse
	local allowed = MonetizationService.OwnsPass(player, "AutoClick")
	if enabled and not allowed then
		return { Ok = false, Code = "NotOwned" }
	end
	ClickService.SetAutoClick(player, enabled)
	return { Ok = true, Data = { Enabled = enabled } }
end

--[[
	STUDIO TESTING ONLY. Runs the real grant path (ledger included) with a
	synthetic "STUDIO-<guid>" purchase id, so product flows can be tested
	before products exist on Roblox. Refuses outside Studio.
]]
function MonetizationService.TestGrantProduct(player: Player, key: string): boolean
	if not RunService:IsStudio() then
		log:Error("TestGrantProduct refused outside Studio")
		return false
	end
	local product = ProductConfig.DeveloperProducts[key]
	if not product then
		return false
	end
	return grantProduct(player, product, "STUDIO-" .. HttpService:GenerateGUID(false), 0)
end

-- STUDIO TESTING ONLY: grants every game pass for this session (never persisted).
function MonetizationService.TestGrantAllPasses(player: Player): boolean
	if not RunService:IsStudio() then
		log:Error("TestGrantAllPasses refused outside Studio")
		return false
	end
	for key in ProductConfig.GamePasses do
		setOwned(player, key)
	end
	applyBenefits(player)
	return true
end

function MonetizationService.Init()
	PowerService.RegisterProvider("GamePass", function(player)
		return passMultiplier(player, "PowerMultiplier")
	end)
	EggService.RegisterLuckProvider("GamePass", function(player)
		return passMultiplier(player, "LuckMultiplier")
	end)

	local productKeys: { [string]: boolean } = {}
	for key in ProductConfig.GamePasses do
		productKeys[key] = true
	end
	for key in ProductConfig.DeveloperProducts do
		productKeys[key] = true
	end
	NetService.OnInvoke("PromptPurchase", Guard.Args(Guard.KeyOf(productKeys)), prompt)
	NetService.OnInvoke("SetAutoClick", Guard.Args(Guard.Boolean()), setAutoClick)

	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
		local pass = PurchaseLogic.PassById(passId)
		if purchased and pass then
			log:Info(string.format("user=%d bought pass %s", player.UserId, pass.Key))
			setOwned(player, pass.Key)
			applyBenefits(player)
			NetService.FireClient("Notify", player, "Purchase", { Key = pass.Key })
		end
	end)

	DataService.PlayerLoaded:Connect(function(player)
		task.spawn(loadOwnership, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		owned[player] = nil
	end)
end

return MonetizationService
