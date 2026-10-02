--!strict
--[[
	ShopController
	"Loja" panel: Offers (Starter Pack), Passes, Items (developer products).
	- Prices are read LIVE from Roblox (MarketplaceService:GetProductInfo);
	  ProductConfig.SuggestedPriceRobux is never shown as the real price.
	- Unconfigured ids (0) show "Em breve" and can't be bought.
	- "Comprar" asks the server to prompt (PromptPurchase); the grant only
	  ever happens server-side in ProcessReceipt / PromptGamePassPurchaseFinished.
	- Ownership/claimed offers come from server attributes (Pass_*, Offer_*).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local ProductConfig = require(Shared:WaitForChild("Config"):WaitForChild("ProductConfig"))
local Text = require(Shared:WaitForChild("Localization"))

local Theme = require(script.Parent.Parent.UI.Theme)
local Build = require(script.Parent.Parent.UI.Build)
local Messages = require(script.Parent.Parent.UI.Messages)
local RewardText = require(script.Parent.Parent.UI.RewardText)
local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local UIController = require(script.Parent.UIController)
local MenuController = require(script.Parent.MenuController)
local SoundController = require(script.Parent.SoundController)
local NotificationController = require(script.Parent.NotificationController)

-- `Needs` is the pass key that has to be owned first (ladder steps).
type Item = { Key: string, Kind: string, Id: number, Button: TextButton, OneTime: boolean, Icon: ImageLabel, Needs: string? }

local PANEL = "Shop"
local PASS_ORDER = { "DoublePower", "QuadPower", "OctaPower", "AutoClick", "ExtraPets", "DoubleLuck", "VIP" }
local PRODUCT_ORDER = { "PowerBoost2x", "PowerBoost5x", "LuckBoost", "InstantOverdrive", "GemsSmall", "GemsMedium", "GemsLarge" }

local ICON_SIZE = 66
local TEXT_LEFT = ICON_SIZE + 22

local ShopController = {}

local items: { Item } = {}
local prices: { [string]: number } = {}
local tabs: { [string]: { Button: TextButton, List: ScrollingFrame } } = {}
local autoClickButton: TextButton
local autoClickOn = true
local busy = false

local function isOwned(item: Item): boolean
	local player = Players.LocalPlayer
	if item.Kind == "Pass" then
		return player:GetAttribute("Pass_" .. item.Key) == true
	end
	return item.OneTime and player:GetAttribute("Offer_" .. item.Key) == true
end

local function refreshItems()
	for _, item in items do
		if item.Id == 0 then
			item.Button.Text = Text.Get("shop.soon")
			Build.paint(item.Button, "BackgroundColor3", Theme.Colors.Disabled)
		elseif isOwned(item) then
			item.Button.Text = Text.Get("shop.owned")
			Build.paint(item.Button, "BackgroundColor3", Theme.Colors.PanelLight)
		elseif item.Needs and Players.LocalPlayer:GetAttribute("Pass_" .. item.Needs) ~= true then
			-- Ladder step: the one before it has to be bought first.
			item.Button.Text = Text.Get("shop.needsPrevious")
			Build.paint(item.Button, "BackgroundColor3", Theme.Colors.Disabled)
		else
			local price = prices[item.Key]
			item.Button.Text = if price then Text.Get("shop.robux", { price = price }) else Text.Get("shop.buy")
			Build.paint(item.Button, "BackgroundColor3", Theme.Colors.Good)
		end
	end
	autoClickButton.Visible = Players.LocalPlayer:GetAttribute("Pass_AutoClick") == true
	autoClickButton.Text = Text.Get(if autoClickOn then "shop.autoClickOn" else "shop.autoClickOff")
end

--[[
	Live prices AND pictures (yields; runs in the background).
	The artwork is the one uploaded to Roblox with each pass/product, so the
	shop always shows what the player sees on the purchase prompt:
		passes   -> the thumbnail service knows them by id
		products -> GetProductInfo carries the icon asset
]]
local function fetchDetails()
	for _, item in items do
		if item.Id == 0 then
			continue
		end
		if item.Kind == "Pass" then
			item.Icon.Image = string.format("rbxthumb://type=GamePass&id=%d&w=150&h=150", item.Id)
			item.Icon.Visible = true
		end
		local infoType = if item.Kind == "Pass" then Enum.InfoType.GamePass else Enum.InfoType.Product
		local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, item.Id, infoType)
		if ok and type(info) == "table" then
			if type(info.PriceInRobux) == "number" then
				prices[item.Key] = info.PriceInRobux
			end
			local iconId = info.IconImageAssetId
			if item.Kind ~= "Pass" and type(iconId) == "number" and iconId > 0 then
				item.Icon.Image = "rbxassetid://" .. tostring(iconId)
				item.Icon.Visible = true
			end
		end
	end
	refreshItems()
end

local function buy(item: Item)
	if busy or item.Id == 0 or isOwned(item) then
		return
	end
	busy = true
	local response = ClientNet.Invoke("PromptPurchase", item.Key)
	busy = false
	if not response.Ok then
		NotificationController.Show(Messages.ForCode(response.Code), "Bad")
	end
end

local function showTab(name: string)
	for tabName, tab in tabs do
		tab.List.Visible = tabName == name
		Build.paint(tab.Button, "BackgroundColor3", if tabName == name then Theme.Colors.Accent else Theme.Colors.PanelLight)
	end
end

local function makeList(content: Frame): ScrollingFrame
	local list: ScrollingFrame = Build.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 56),
		Size = UDim2.new(1, 0, 1, -56),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 8,
		ZIndex = 22,
		Parent = content,
	})
	Build.new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	return list
end

local function addRow(list: ScrollingFrame, order: number, title: string, description: string, key: string, kind: string, id: number, oneTime: boolean, height: number?, color: Color3?, needs: string?)
	local frame: Frame = Build.new("Frame", {
		BackgroundColor3 = color or Theme.Colors.PanelLight,
		Size = UDim2.new(1, -12, 0, height or 92),
		LayoutOrder = order,
		ZIndex = 22,
		Parent = list,
	})
	Build.corner(frame, Theme.CornerSmall)
	-- Hidden until fetchDetails finds the artwork; the row reads fine without it.
	local icon: ImageLabel = Build.new("ImageLabel", {
		Name = "Icon",
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE),
		Visible = false,
		ZIndex = 23,
		Parent = frame,
	})
	Build.corner(icon, Theme.CornerSmall)
	Build.label({ Text = title, TextSize = 24, Position = UDim2.fromOffset(TEXT_LEFT, 8), Size = UDim2.new(1, -(TEXT_LEFT + 210), 0, 30), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 23, Parent = frame })
	Build.label({ Text = description, TextSize = 16, TextWrapped = true, TextColor3 = Theme.Colors.Text, Position = UDim2.fromOffset(TEXT_LEFT, 40), Size = UDim2.new(1, -(TEXT_LEFT + 210), 1, -46), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 23, Parent = frame })
	local button = Build.button({ Text = "", TextSize = 20, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(190, 60), ZIndex = 23, Parent = frame })
	local item: Item = { Key = key, Kind = kind, Id = id, Button = button, OneTime = oneTime, Icon = icon, Needs = needs }
	button.Activated:Connect(function()
		buy(item)
	end)
	table.insert(items, item)
end

function ShopController.Init()
	local _, content = UIController.CreatePanel(PANEL, Text.Get("shop.title", { icon = Theme.Icons.Shop }), Vector2.new(720, 600))
	local tabBar: Frame = Build.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 46), ZIndex = 22, Parent = content })
	Build.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), Parent = tabBar })
	for _, tabName in { "Offers", "Passes", "Products" } do
		local button = Build.button({ Text = Text.Get("shop.tab" .. tabName), TextSize = 20, Size = UDim2.new(1 / 3, -6, 1, 0), ZIndex = 22, Parent = tabBar })
		button.Activated:Connect(function()
			showTab(tabName)
		end)
		tabs[tabName] = { Button = button, List = makeList(content) }
	end

	-- Offers: Starter Pack.
	local starter = ProductConfig.DeveloperProducts.StarterPack
	addRow(tabs.Offers.List, 1, "⭐ " .. Text.Get("shop.starterTitle"), Text.Get("shop.starterDesc", { contents = RewardText.List(starter.Rewards) }), starter.Key, "Product", starter.ProductId, true, 150, Theme.Colors.Accent)

	-- Passes.
	for index, key in PASS_ORDER do
		local pass = ProductConfig.GamePasses[key]
		if pass then
			-- The step before this one on the same ladder, if any.
			local needs: string? = nil
			if pass.Ladder and pass.LadderStep and pass.LadderStep > 1 then
				for _, other in ProductConfig.GamePasses do
					if other.Ladder == pass.Ladder and other.LadderStep == pass.LadderStep - 1 then
						needs = other.Key
					end
				end
			end
			addRow(tabs.Passes.List, index, Text.Get("pass." .. key .. ".name"), Text.Get("pass." .. key .. ".desc"), key, "Pass", pass.GamePassId, false, nil, nil, needs)
		end
	end
	autoClickButton = Build.button({ Text = "", TextSize = 20, BackgroundColor3 = Theme.Colors.Accent, Size = UDim2.new(1, -12, 0, 56), LayoutOrder = 100, ZIndex = 22, Parent = tabs.Passes.List })
	autoClickButton.Activated:Connect(function()
		if busy then
			return
		end
		busy = true
		local response = ClientNet.Invoke("SetAutoClick", not autoClickOn)
		busy = false
		if response.Ok then
			autoClickOn = not autoClickOn
			refreshItems()
		else
			NotificationController.Show(Messages.ForCode(response.Code), "Bad")
		end
	end)

	-- Developer products.
	for index, key in PRODUCT_ORDER do
		local product = ProductConfig.DeveloperProducts[key]
		if product then
			local description = if #product.Rewards > 0 then RewardText.List(product.Rewards) else Text.Get("product." .. key .. ".name")
			addRow(tabs.Products.List, index, Text.Get("product." .. key .. ".name"), description, key, "Product", product.ProductId, product.OneTimeOffer)
		end
	end
	showTab("Offers")

	MenuController.AddButton(Text.Get("menu.shop"), Theme.Icons.Shop, Theme.Colors.Power, 9, function()
		UIController.TogglePanel(PANEL)
	end)

	local player = Players.LocalPlayer
	player.AttributeChanged:Connect(function(name: string)
		if string.sub(name, 1, 5) == "Pass_" or string.sub(name, 1, 6) == "Offer_" then
			refreshItems()
		end
	end)
	ClientNet.On("Notify", function(kind: any)
		if kind == "Purchase" then
			SoundController.Play("Purchase")
			NotificationController.Show(Text.Get("shop.thanks"), "Good")
		end
	end)
	refreshItems()
	task.spawn(fetchDetails)
end

return ShopController
