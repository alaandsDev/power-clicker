--!strict
--[[
	EggController
	Egg shop panel (price, exact drop chances with the player's luck) and the
	hatch animation. The server decides the pet ("HatchEgg" returns the
	result); the animation only reveals what the server already decided.

	Luck shown here = 1 + permanent Luck upgrades (display only). Temporary
	luck boosts (Phase 6) will be reflected via a server attribute.

]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local NumberFormat = require(Shared:WaitForChild("Utils"):WaitForChild("NumberFormat"))
local EggOdds = require(Shared:WaitForChild("Formulas"):WaitForChild("EggOdds"))
local EggConfig = require(Config:WaitForChild("EggConfig"))
local WallConfig = require(Config:WaitForChild("WallConfig"))
local PetConfig = require(Config:WaitForChild("PetConfig"))
local UpgradeConfig = require(Config:WaitForChild("UpgradeConfig"))
local Types = require(Shared:WaitForChild("Types"))
local Text = require(Shared:WaitForChild("Localization"))

local Theme = require(script.Parent.Parent.UI.Theme)
local Build = require(script.Parent.Parent.UI.Build)
local Anim = require(script.Parent.Parent.UI.Anim)
local Messages = require(script.Parent.Parent.UI.Messages)
local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local UIController = require(script.Parent.UIController)
local MenuController = require(script.Parent.MenuController)
local DataController = require(script.Parent.DataController)
local SoundController = require(script.Parent.SoundController)
local NotificationController = require(script.Parent.NotificationController)

type EggData = Types.EggData
type EggCard = { Egg: EggData, Frame: Frame, Chances: TextLabel, Button: TextButton }
local PANEL = "Eggs"
local REVEAL_SECONDS = 2.5

local RARITY_SOUND: { [string]: string } = {
	Rare = "RarePet",
	Epic = "RarePet",
	Legendary = "Legendary",
	Mythic = "Mythic",
}

local EggController = {}

local eggCards: { EggCard } = {}
local luckLabel: TextLabel
local noEggsLabel: TextLabel
local overlay: Frame
local eggIcon: TextLabel
local resultLabel: TextLabel
local rarityLabel: TextLabel
local revealImage: ImageLabel
local rays: Frame
local raysSpin: Tween? = nil
local RAY_COUNT = 10
local busy = false

local function currentLuck(): number
	-- Server-published effective luck (upgrades + boosts + passes) when available.
	local published = Players.LocalPlayer:GetAttribute("Luck")
	if type(published) == "number" then
		return EggOdds.ClampLuck(published)
	end
	local levels = DataController.Get("PermanentUpgrades") or {}
	local luck = 1
	for id, upgrade in UpgradeConfig.Permanent do
		if upgrade.EffectType == "LuckMultiplier" then
			luck += upgrade.EffectPerLevel * (levels[id] or 0)
		end
	end
	return EggOdds.ClampLuck(luck)
end

local function refreshChances()
	local luck = currentLuck()
	luckLabel.Text = Text.Get("eggs.luck", { luck = NumberFormat.Short(luck) })
	local currencies = DataController.Get("Currencies") or {}
	local currentWorld = (DataController.Get("Worlds") or {}).Current
	local visibleCount = 0
	for _, card in eggCards do
		card.Frame.Visible = card.Egg.WorldId == currentWorld
		if card.Frame.Visible then
			visibleCount += 1
		end
		local chances = EggOdds.Chances(card.Egg, luck)
		local lines = {}
		for _, drop in card.Egg.Drops do
			local pet = PetConfig.Pets[drop.PetId]
			if pet then
				local rarity = PetConfig.Rarities[pet.Rarity]
				local hex = if rarity then rarity.Color:ToHex() else "FFFFFF"
				table.insert(lines, string.format('<font color="#%s">%s</font>  %s%%', hex, Text.Name("pet", pet), NumberFormat.Short((chances[drop.PetId] or 0) * 100)))
			end
		end
		card.Chances.Text = table.concat(lines, "\n")
		--[[
			Ovos presos a um estágio da torre: enquanto ele não cair uma vez, o
			botão diz qual estágio falta em vez de só ficar apagado. O servidor
			recusa de qualquer jeito (EggLogic), isto é só a explicação.
		]]
		local stage = card.Egg.RequiredStage
		local cleared = (DataController.Get("Tower") or {}).Cleared or {}
		if stage and cleared[stage] ~= true then
			local order = 0
			for _, item in WallConfig.Stages do
				if item.Id == stage then
					order = item.Order
				end
			end
			card.Button.Text = Text.Get("eggs.stageLocked", { order = tostring(order) })
			Build.paint(card.Button, "BackgroundColor3", Theme.Colors.Disabled)
		else
			local affordable = (currencies[card.Egg.Currency] or 0) >= card.Egg.Price
			card.Button.Text = Text.Get("eggs.hatch", {
				icon = if card.Egg.Currency == "Gems" then Theme.Icons.Gems else Theme.Icons.Power,
				price = NumberFormat.Short(card.Egg.Price),
			})
			Build.paint(card.Button, "BackgroundColor3", if affordable then Theme.Colors.Good else Theme.Colors.Disabled)
		end
	end
	noEggsLabel.Visible = visibleCount == 0
end

local function playReveal(result: any)
	local pet = PetConfig.Pets[result.PetId]
	local rarity = pet and PetConfig.Rarities[pet.Rarity]
	local color = if rarity then rarity.Color else Theme.Colors.Text

	overlay.Visible = true
	overlay.BackgroundTransparency = 0.35
	resultLabel.Text = Text.Get("eggs.hatching")
	rarityLabel.Text = ""
	-- Egg image (if configured) or the egg emoji.
	local eggConfig = EggConfig.Eggs[result.EggId]
	local eggImage = if eggConfig then eggConfig.Icon else nil
	if Build.isAsset(eggImage) then
		eggIcon.Text = ""
		revealImage.Image = eggImage :: string
		revealImage.Visible = true
	else
		eggIcon.Text = Theme.Icons.Eggs
		revealImage.Visible = false
	end
	eggIcon.Rotation = 0
	SoundController.Play("Egg")

	-- Shake harder and harder while the egg grows.
	local eggScale = Anim.ScaleOf(eggIcon)
	eggScale.Scale = 0.8
	TweenService:Create(eggScale, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 1.3 }):Play()
	for i = 1, 9 do
		local angle = (if i % 2 == 0 then -1 else 1) * (8 + i * 2.5)
		local tween = TweenService:Create(eggIcon, TweenInfo.new(0.1 - i * 0.004), { Rotation = angle })
		tween:Play()
		tween.Completed:Wait()
	end
	eggIcon.Rotation = 0

	-- Rays in the rarity color, spinning behind the reveal.
	for _, ray in rays:GetChildren() do
		if ray:IsA("Frame") then
			Build.paint(ray, "BackgroundColor3", color)
		end
	end
	rays.Visible = not Anim.Reduced()
	rays.Rotation = 0
	if raysSpin then
		raysSpin:Cancel()
	end
	raysSpin = TweenService:Create(rays, TweenInfo.new(6, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Rotation = 360 })
	;(raysSpin :: Tween):Play()
	Anim.PopIn(rays, 0.2, 0.4)

	-- Reveal.
	-- Pet image (if configured) or sparkles.
	local petImage = if pet then pet.Icon else nil
	if Build.isAsset(petImage) then
		eggIcon.Text = ""
		revealImage.Image = petImage :: string
		revealImage.Visible = true
	else
		eggIcon.Text = "✨"
		revealImage.Visible = false
	end
	resultLabel.Text = Text.Get("eggs.youGot", { name = if pet then Text.Name("pet", pet) else tostring(result.PetId) })
	Build.paint(resultLabel, "TextColor3", color)
	rarityLabel.Text = Text.Get("rarity." .. tostring(result.Rarity))
	Build.paint(rarityLabel, "TextColor3", color)
	Anim.Pop(eggIcon, 1.6, 0.4)
	Anim.PopIn(resultLabel, 0.3, 0.4)
	Anim.PopIn(rarityLabel, 0.3, 0.5)
	local center = UIController.CenterOf(eggIcon)
	local rare = result.Rarity == "Legendary" or result.Rarity == "Mythic"
	-- The overlay covers the whole canvas at (0,0), so canvas offsets work inside it.
	Anim.Burst(overlay, center, color, if rare then 36 else 18, if rare then 260 else 160)
	if rare then
		Anim.Shake(UIController.GetCanvas(), 12, 0.5)
	end
	SoundController.Play(RARITY_SOUND[result.Rarity] or "Reward")
	local settings = DataController.Get("Settings")
	local reduced = settings ~= nil and settings.ReducedEffects == true
	if (result.Rarity == "Legendary" or result.Rarity == "Mythic") and not reduced then
		Build.paint(overlay, "BackgroundColor3", color)
		overlay.BackgroundTransparency = 0.2
		TweenService:Create(overlay, TweenInfo.new(1.2), { BackgroundTransparency = 0.5 }):Play()
	end

	task.wait(REVEAL_SECONDS)
	if raysSpin then
		raysSpin:Cancel()
		raysSpin = nil
	end
	rays.Visible = false
	overlay.Visible = false
	Build.paint(overlay, "BackgroundColor3", Color3.new(0, 0, 0))
end

local function hatch(egg: EggData)
	if busy then
		return
	end
	busy = true
	local response = ClientNet.Invoke("HatchEgg", egg.Id)
	if response.Ok and type(response.Data) == "table" then
		UIController.ClosePanel()
		playReveal(response.Data)
	else
		NotificationController.Show(Messages.ForCode(response.Code), "Bad")
	end
	busy = false
end

local function createEggCard(list: ScrollingFrame, egg: EggData, order: number)
	local frame: Frame = Build.new("Frame", {
		Name = egg.Id,
		BackgroundColor3 = Theme.Colors.PanelLight,
		Size = UDim2.new(1, -12, 0, 190),
		LayoutOrder = order,
		ZIndex = 22,
		Parent = list,
	})
	Build.corner(frame, Theme.CornerSmall)
	local hasIcon = Build.isAsset(egg.Icon)
	if hasIcon then
		Build.new("ImageLabel", {
			Name = "EggIcon",
			BackgroundTransparency = 1,
			Image = egg.Icon,
			ScaleType = Enum.ScaleType.Fit,
			Position = UDim2.fromOffset(10, 4),
			Size = UDim2.fromOffset(40, 40),
			ZIndex = 23,
			Parent = frame,
		})
	end
	Build.label({
		Text = (if hasIcon then "" else Theme.Icons.Eggs .. " ") .. Text.Name("egg", egg),
		TextSize = 26,
		Position = UDim2.fromOffset(if hasIcon then 56 else 14, 8),
		Size = UDim2.new(0.5, 0, 0, 34),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 23,
		Parent = frame,
	})
	local chances = Build.label({
		Text = "",
		RichText = true,
		TextSize = 17,
		Font = Theme.FontRegular,
		Position = UDim2.fromOffset(14, 46),
		Size = UDim2.new(0.55, 0, 1, -54),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 23,
		Parent = frame,
	})
	local icon = if egg.Currency == "Gems" then Theme.Icons.Gems else Theme.Icons.Power
	local button = Build.button({
		Text = Text.Get("eggs.hatch", { icon = icon, price = NumberFormat.Short(egg.Price) }),
		TextSize = 22,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(220, 70),
		ZIndex = 23,
		Parent = frame,
	})
	button.Activated:Connect(function()
		hatch(egg)
	end)
	table.insert(eggCards, { Egg = egg, Frame = frame, Chances = chances, Button = button })
end

function EggController.Init()
	local _, content = UIController.CreatePanel(PANEL, Text.Get("eggs.title", { icon = Theme.Icons.Eggs }), Vector2.new(680, 600))
	luckLabel = Build.label({
		Text = "",
		TextSize = 20,
		TextColor3 = Theme.Colors.Good,
		Size = UDim2.new(1, 0, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 22,
		Parent = content,
	})
	local list: ScrollingFrame = Build.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 36),
		Size = UDim2.new(1, 0, 1, -36),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 8,
		ZIndex = 22,
		Parent = content,
	})
	Build.new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	noEggsLabel = Build.label({
		Text = Text.Get("eggs.none"),
		TextSize = 22,
		TextColor3 = Theme.Colors.TextDim,
		Position = UDim2.fromOffset(0, 60),
		Size = UDim2.new(1, 0, 0, 40),
		Visible = false,
		ZIndex = 23,
		Parent = content,
	})

	-- Cheapest first; only enabled eggs.
	local eggs: { EggData } = {}
	for _, egg in EggConfig.Eggs do
		if egg.Enabled then
			table.insert(eggs, egg)
		end
	end
	table.sort(eggs, function(a, b)
		if a.Currency ~= b.Currency then
			return a.Currency == "Power"
		end
		return a.Price < b.Price
	end)
	for index, egg in eggs do
		createEggCard(list, egg, index)
	end

	-- Full-screen hatch overlay.	-- Full-screen hatch overlay.
	overlay = Build.new("Frame", {
		Name = "HatchOverlay",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
		Active = true,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 90,
		Parent = UIController.GetCanvas(),
	})
	-- Starburst behind the egg: thin rays around a centre, rotated as a whole.
	rays = Build.new("Frame", {
		Name = "Rays",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(620, 620),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 90,
		Parent = overlay,
	})
	for i = 1, RAY_COUNT do
		local ray = Build.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, 34, 1, 0),
			Rotation = (i - 1) * 180 / RAY_COUNT,
			BackgroundTransparency = 0.55,
			BorderSizePixel = 0,
			ZIndex = 90,
			Parent = rays,
		})
		Build.new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0.2),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = ray,
		})
	end
	eggIcon = Build.label({ Text = "", TextSize = 160, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(260, 220), ZIndex = 91, Parent = overlay })
	-- Image variant of the reveal (egg, then pet), child of eggIcon so it shakes/scales with it.
	revealImage = Build.new("ImageLabel", {
		Name = "RevealImage",
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 92,
		Parent = eggIcon,
	})
	resultLabel = Build.label({ Text = "", TextSize = 44, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.62), Size = UDim2.fromOffset(900, 56), ZIndex = 91, Parent = overlay })
	rarityLabel = Build.label({ Text = "", TextSize = 32, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.62, 60), Size = UDim2.fromOffset(600, 40), ZIndex = 91, Parent = overlay })

	MenuController.AddButton(Text.Get("menu.eggs"), Theme.Icons.Eggs, Theme.Colors.Power, 4, function()
		UIController.TogglePanel(PANEL)
	end, "Eggs")

	DataController.Changed:Connect(function(key: string)
		if key == "Tower" or key == "Currencies" or key == "PermanentUpgrades" or key == "Worlds" then
			refreshChances()
		end
	end)
	Players.LocalPlayer:GetAttributeChangedSignal("Luck"):Connect(refreshChances)

	-- Rare hatches announced by the server for everyone.
	ClientNet.On("Notify", function(kind: any, payload: any)
		if kind ~= "RareHatch" or type(payload) ~= "table" then
			return
		end
		local pet = PetConfig.Pets[payload.PetId]
		if not pet or payload.UserId == Players.LocalPlayer.UserId then
			return
		end
		NotificationController.Show(
			Text.Get("notify.rareHatch", { player = tostring(payload.Player), rarity = Text.Get("rarity." .. pet.Rarity), name = Text.Name("pet", pet) }),
			"Good"
		)
	end)
end

return EggController
