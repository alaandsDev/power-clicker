--!strict
--[[
	ClickController
	The main click button + combo + Overdrive bar + floating numbers.

	Input: the button (mouse, touch, gamepad selection), a click/tap anywhere
	on the 3D view (not on UI; touch drags that move the camera don't count)
	and gamepad R2 / X via ContextActionService (console).

	The client only sends "Click" (no data). A local rate limiter mirrors the
	server's so legit fast clickers never hit the server limit. Floating
	numbers and combo are PREDICTED locally for instant feedback; the real
	values come from the server (Power via data, combo via ClickFeedback).
]]

local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local NumberFormat = require(Shared:WaitForChild("Utils"):WaitForChild("NumberFormat"))
local RateLimiter = require(Shared:WaitForChild("Utils"):WaitForChild("RateLimiter"))
local EconomyFormulas = require(Shared:WaitForChild("Formulas"):WaitForChild("EconomyFormulas"))
local EconomyConfig = require(Config:WaitForChild("EconomyConfig"))
local ComboConfig = require(Config:WaitForChild("ComboConfig"))
local OverdriveConfig = require(Config:WaitForChild("OverdriveConfig"))
local Text = require(Shared:WaitForChild("Localization"))

local Theme = require(script.Parent.Parent.UI.Theme)
local Build = require(script.Parent.Parent.UI.Build)
local Anim = require(script.Parent.Parent.UI.Anim)
local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local UIController = require(script.Parent.UIController)
local DataController = require(script.Parent.DataController)
local GameStateController = require(script.Parent.GameStateController)
local SoundController = require(script.Parent.SoundController)
local HudController = require(script.Parent.HudController)
local SlashController = require(script.Parent.SlashController)

local FLOAT_POOL_SIZE = 16
-- Bottom-centre layout (keeps the character visible). Reference pixels.
-- Heights come from Theme.Hud so the level bar (built by HudController) and
-- this stack cannot overlap.
local BUTTON_WIDTH = Theme.Hud.ClickWidth
local BUTTON_HEIGHT = Theme.Hud.ClickHeight
local TOUCH_EXTRA = Theme.Hud.ClickTouchExtra -- bigger target on phones/tablets
local BOTTOM_MARGIN = Theme.Hud.ClickBottom
-- A barra de nível fica ABAIXO do botão agora, então o que vem acima dele
-- (overdrive, combo, números) começa logo acima do próprio botão.
local STACK_BASE = 0
local BUTTON_CORNER = UDim.new(0, 20)
-- Tap on the world counts as a click only if it's a quick, still tap.
local TAP_MAX_SECONDS = 0.35
local TAP_MAX_MOVE = 14 -- screen pixels
-- Holding (button or screen) keeps clicking at EconomyConfig.Click.HoldClicksPerSecond.
local HOLD_INTERVAL = 1 / EconomyConfig.Click.HoldClicksPerSecond

local ClickController = {}

local limiter = RateLimiter.new(EconomyConfig.Click.ClickBurst, EconomyConfig.Click.MaxClicksPerSecond)
local random = Random.new()

local button: TextButton
local buttonGradient: UIGradient
local comboLabel: TextLabel
local floatLayer: Frame
local floatPool: { TextLabel } = {}
local floatIndex = 0
local lastTier = 0
local buttonTop = BOTTOM_MARGIN + BUTTON_HEIGHT -- distance from the bottom edge, set in Init
local shineGradient: UIGradient
local overdriveBanner: TextLabel
local flyers: { GuiObject } = {}
local flyerIndex = 0
local lastFlyerAt = 0
local lastStacks = 0
-- While something is held: how many inputs are down and when the next
-- auto-fire is due.
local holding = 0
local holdAt: Vector2? = nil
local nextHold = 0
-- True once the hold auto-fired: the release must not add one more click.
local holdFired = false

local FLYER_POOL_SIZE = 10
local FLYER_INTERVAL = 0.09 -- max one ⚡ flyer per 90 ms
local FLOAT_TEXT_SIZES = { 24, 28, 32, 36 } -- por tier de combo (eram 32..46)
local ring: Frame
local ringStroke: UIStroke
local overdriveGlow: Frame

local function reducedEffects(): boolean
	local settings = DataController.Get("Settings")
	return settings ~= nil and settings.ReducedEffects == true
end

-- Expanding outline on each click (single pooled frame; skipped in reduced mode).
local function pulseRing()
	if reducedEffects() then
		return
	end
	ring.Size = UDim2.fromScale(1, 1)
	ringStroke.Transparency = 0.2
	TweenService:Create(ring, Theme.Tween.Float, { Size = UDim2.new(1, 36, 1, 28) }):Play()
	TweenService:Create(ringStroke, Theme.Tween.Float, { Transparency = 1 }):Play()
end

local function comboTier(stacks: number): number
	local tier = 0
	for i, threshold in ComboConfig.VisualTiers do
		if stacks >= threshold then
			tier = i
		end
	end
	return tier
end

-- `at` (canvas pixels) spawns the number where the player tapped; default is above the button.
local function showFloat(text: string, color: Color3, tier: number?, at: Vector2?)
	floatIndex = (floatIndex % FLOAT_POOL_SIZE) + 1
	local label = floatPool[floatIndex]
	label.TextSize = FLOAT_TEXT_SIZES[(tier or 0) + 1] or FLOAT_TEXT_SIZES[1]
	label.Rotation = random:NextNumber(-10, 10)
	Anim.PopIn(label, 0.4, 0.22)
	-- Numbers pop just above the button (or at the tap) and rise.
	local origin = if at then UDim2.fromOffset(at.X, at.Y) else UDim2.new(0.5, random:NextNumber(-130, 130), 1, -buttonTop - random:NextNumber(10, 40))
	label.Text = text
	Build.paint(label, "TextColor3", color)
	label.Position = origin
	label.TextTransparency = 0
	label.Visible = true
	-- The outline must fade too, otherwise it stays on screen as a black smear.
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 0
		TweenService:Create(stroke, Theme.Tween.Float, { Transparency = 1 }):Play()
	end
	local tween = TweenService:Create(label, Theme.Tween.Float, {
		Position = origin - UDim2.fromOffset(0, 120),
		TextTransparency = 1,
	})
	local previous = label:GetAttribute("Stamp")
	local stamp = (if type(previous) == "number" then previous else 0) + 1
	label:SetAttribute("Stamp", stamp)
	tween.Completed:Once(function()
		if label:GetAttribute("Stamp") == stamp then
			label.Visible = false
		end
	end)
	tween:Play()
end

-- Light band sweeping across the button.
local function shine()
	if reducedEffects() then
		return
	end
	shineGradient.Offset = Vector2.new(-1, 0)
	TweenService:Create(shineGradient, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { Offset = Vector2.new(1, 0) }):Play()
end

-- A ⚡ icon flies from the button to the Power counter (throttled, pooled).
local function flyToPower(from: Vector2?)
	local now = os.clock()
	if reducedEffects() or now - lastFlyerAt < FLYER_INTERVAL then
		return
	end
	local pill = HudController.GetPowerPill()
	if not pill then
		return
	end
	lastFlyerAt = now
	flyerIndex = (flyerIndex % FLYER_POOL_SIZE) + 1
	local flyer = flyers[flyerIndex]
	local canvasSize = UIController.GetCanvasSize()
	local start = from or Vector2.new(canvasSize.X / 2 + random:NextNumber(-80, 80), canvasSize.Y - buttonTop)
	local target = HudController.GetPowerTarget() or UIController.CenterOf(pill)
	flyer.Position = UDim2.fromOffset(start.X, start.Y)
	flyer.Rotation = 0
	flyer.Visible = true
	local tween = TweenService:Create(flyer, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = UDim2.fromOffset(target.X, target.Y),
		Rotation = random:NextNumber(-180, 180),
	})
	tween.Completed:Once(function()
		flyer.Visible = false
		Anim.Pop(pill, 1.08, 0.18)
	end)
	tween:Play()
end

local function click(at: Vector2?)
	if not DataController.IsLoaded() or not limiter:Consume("local") then
		return
	end
	ClientNet.Fire("Click")

	-- Display-only prediction.
	local stacks = GameStateController.RegisterLocalClick()
	local predicted = GameStateController.GetPowerInfo().PerClick * EconomyFormulas.ComboMultiplier(stacks)
	local settings = DataController.Get("Settings")
	local tier = comboTier(stacks)
	local overdrive = GameStateController.IsOverdriveActive()
	local color = if overdrive then Theme.Colors.OverdriveTop else (Theme.Colors.ComboTiers[tier + 1] or Theme.Colors.Power)
	if (not settings or settings.ShowFloatingNumbers ~= false) and not reducedEffects() then
		showFloat("+" .. NumberFormat.Short(predicted), if tier == 0 and not overdrive then Theme.Colors.Power else color, tier, at)
	end
	Anim.Squash(button)
	pulseRing()
	shine()
	local canvasSize = UIController.GetCanvasSize()
	Anim.Burst(floatLayer, at or Vector2.new(canvasSize.X / 2 + random:NextNumber(-60, 60), canvasSize.Y - buttonTop + 6), color, if overdrive then 8 else 5, 60)
	flyToPower(at)
	SlashController.Play()
	SoundController.Play("Click")
end

-- Press/release of anything that fires clicks while held.
local function setHolding(down: boolean, at: Vector2?)
	if down then
		if holding == 0 then
			holdFired = false
		end
		holding += 1
		holdAt = at
		-- The press itself already clicked; the repeat starts one beat later.
		nextHold = os.clock() + HOLD_INTERVAL
	else
		holding = math.max(holding - 1, 0)
		if holding == 0 then
			holdAt = nil
		end
	end
end

local function updateOverdriveVisuals(active: boolean)
	if active then
		buttonGradient.Color = ColorSequence.new(Theme.Colors.OverdriveTop, Theme.Colors.OverdriveBottom)
		SoundController.Play("OverdriveStart")
	else
		buttonGradient.Color = ColorSequence.new(Theme.Colors.ClickTop, Theme.Colors.ClickBottom)
		SoundController.Play("OverdriveEnd")
	end
	overdriveGlow.Visible = active and not reducedEffects()
	if active then
		overdriveBanner.Visible = true
		overdriveBanner.TextTransparency = 0
		Anim.PopIn(overdriveBanner, 0.3, 0.4)
		Anim.Shake(button, 8, 0.4)
		task.delay(1.4, function()
			local fade = TweenService:Create(overdriveBanner, TweenInfo.new(0.4), { TextTransparency = 1 })
			fade.Completed:Once(function()
				overdriveBanner.Visible = false
			end)
			fade:Play()
		end)
	end
end

-- Per-frame text updates (cheap: a few property writes).
local function onRenderStep()
	if holding > 0 then
		local now = os.clock()
		if now >= nextHold then
			-- Jitter so a held finger does not produce machine-perfect timing.
			nextHold = now + HOLD_INTERVAL + random:NextNumber(-1, 1) * EconomyConfig.Click.HoldJitterSeconds
			holdFired = true
			click(holdAt)
		end
	end
	local stacks = GameStateController.GetCombo()
	local tier = comboTier(stacks)
	if stacks > 0 then
		comboLabel.Visible = true
		comboLabel.Text = Text.Get("combo.label", { stacks = stacks, mult = NumberFormat.Short(EconomyFormulas.ComboMultiplier(stacks)) })
		Build.paint(comboLabel, "TextColor3", Theme.Colors.ComboTiers[tier + 1] or Theme.Colors.Text)
	else
		comboLabel.Visible = false
	end
	if stacks > lastStacks then
		Anim.Pop(comboLabel, if tier > lastTier then 1.4 else 1.08, if tier > lastTier then 0.35 else 0.15)
	end
	if tier > lastTier then
		SoundController.Play("ComboTier")
		Anim.Shake(comboLabel, 6, 0.25)
	end
	lastStacks = stacks
	lastTier = tier

	-- O estado do overdrive é desenhado pelo componente do rodapé; aqui fica só
	-- o brilho na borda da tela, que é efeito e não informação.
	if GameStateController.IsOverdriveActive() and overdriveGlow.Visible then
		local stroke = overdriveGlow:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = 0.35 + 0.25 * math.sin(os.clock() * 6)
		end
	end
end

function ClickController.Init()
	local canvas = UIController.GetCanvas()
	local isTouch = UIController.IsTouch()
	local width = BUTTON_WIDTH + (if isTouch then TOUCH_EXTRA.X else 0)
	local height = BUTTON_HEIGHT + (if isTouch then TOUCH_EXTRA.Y else 0)
	buttonTop = BOTTOM_MARGIN + height + STACK_BASE

	floatLayer = Build.new("Frame", {
		Name = "FloatingNumbers",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 15,
		Parent = canvas,
	})
	for i = 1, FLOAT_POOL_SIZE do
		floatPool[i] = Build.label({
			Name = "Float" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(240, 44),
			TextSize = 34,
			Visible = false,
			ZIndex = 15,
			Parent = floatLayer,
		})
	end

	button = Build.new("TextButton", {
		Name = "ClickButton",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -BOTTOM_MARGIN),
		Size = UDim2.fromOffset(width, height),
		BackgroundColor3 = Color3.new(1, 1, 1),
		-- Shows LOADING until the first data snapshot arrives (initial join
		-- replication can delay it a few seconds); clicks are ignored until then.
		Text = Text.Get(if DataController.IsLoaded() then "click.button" else "click.loading"),
		Font = Theme.FontDisplay,
		TextSize = 44,
		TextColor3 = Theme.Colors.Text,
		AutoButtonColor = false,
		ZIndex = 10,
		Parent = canvas,
	})
	Build.corner(button, BUTTON_CORNER)
	Build.stroke(button, 5)
	Build.textStroke(button, 3)
	buttonGradient = Build.gradient(button, Theme.Colors.ClickTop, Theme.Colors.ClickBottom)
	button.Activated:Connect(function()
		click()
	end)
	-- Holding the button keeps clicking (MouseButton1Down also fires on touch).
	button.MouseButton1Down:Connect(function()
		setHolding(true, nil)
	end)
	button.MouseButton1Up:Connect(function()
		setHolding(false)
	end)
	button.MouseLeave:Connect(function()
		setHolding(false)
	end)

	-- Shine band (clipped to the button's rounded shape by its own corner).
	local shineFrame: Frame = Build.new("Frame", {
		Name = "Shine",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 11,
		Parent = button,
	})
	Build.corner(shineFrame, BUTTON_CORNER)
	shineGradient = Build.new("UIGradient", {
		Rotation = 20,
		Offset = Vector2.new(-1, 0),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.42, 1),
			NumberSequenceKeypoint.new(0.5, 0.55),
			NumberSequenceKeypoint.new(0.58, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = shineFrame,
	})

	-- ⚡ flyers (pooled).
	for i = 1, FLYER_POOL_SIZE do
		flyers[i] = Build.icon(Theme.Icons.Power, {
			Name = "Flyer" .. i,
			TextSize = 30,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(36, 36),
			Visible = false,
			ZIndex = 17,
			Parent = floatLayer,
		})
	end

	overdriveBanner = Build.label({
		Name = "OverdriveBanner",
		Text = "⚡ OVERDRIVE! ⚡",
		TextSize = 64,
		TextColor3 = Theme.Colors.OverdriveTop,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.38),
		Size = UDim2.fromOffset(700, 80),
		Visible = false,
		ZIndex = 18,
		Parent = canvas,
	})
	Build.textStroke(overdriveBanner, 4)

	-- Click outline pulse (child of the button, centred) and Overdrive screen-edge glow.
	ring = Build.new("Frame", {
		Name = "ClickRing",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 9,
		Parent = button,
	})
	Build.corner(ring, BUTTON_CORNER)
	ringStroke = Build.stroke(ring, 6, Theme.Colors.Power)
	ringStroke.Transparency = 1
	overdriveGlow = Build.new("Frame", {
		Name = "OverdriveGlow",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 1,
		Parent = canvas,
	})
	Build.stroke(overdriveGlow, 14, Theme.Colors.OverdriveBottom)
	if not DataController.IsLoaded() then
		DataController.Loaded:Once(function()
			button.Text = Text.Get("click.button")
		end)
	end

	-- Combo: só aparece quando existe, logo acima do botão.
	comboLabel = Build.label({
		Name = "Combo",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -(buttonTop + 4)),
		Size = UDim2.fromOffset(300, 24),
		TextSize = 20,
		Visible = false,
		Parent = canvas,
	})

	--[[
		A barra e o texto do overdrive NÃO moram mais aqui: entraram no
		componente único do rodapé (HudController), junto com o nível. Antes
		eram quatro elementos empilhados disputando o mesmo espaço, e eles se
		sobrepunham.
	]]
	GameStateController.OverdriveChanged:Connect(updateOverdriveVisuals)
	--[[
		Ganho automático: número pequeno e apagado, ao lado do botão. Antes subia
		do mesmo tamanho do clique manual, no meio da tela, e os dois se
		atropelavam em cima do personagem.
	]]
	GameStateController.Feedback:Connect(function(_manualGain: number, _manualClicks: number, autoGain: number)
		if autoGain > 0 then
			local canvasSize = UIController.GetCanvasSize()
			showFloat(
				Text.Get("click.auto", { amount = NumberFormat.Short(autoGain) }),
				Theme.Colors.TextDim,
				nil,
				Vector2.new(canvasSize.X / 2 + 150, canvasSize.Y - buttonTop - 8)
			)
		end
	end)

	-- Console: R2 / X also click (touch/mouse use the button itself).
	ContextActionService:BindAction("PowerClicker_Click", function(_, state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin then
			click()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.ButtonR2, Enum.KeyCode.ButtonX)

	-- Click/tap on the world (outside any UI). Mouse: on press. Touch: on
	-- release, and only for a short still tap (camera swipes are ignored).
	local taps: { [InputObject]: { At: Vector3, Time: number } } = {}
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local at = UIController.ToCanvas(Vector2.new(input.Position.X, input.Position.Y))
			click(at)
			setHolding(true, at)
		elseif input.UserInputType == Enum.UserInputType.Touch then
			taps[input] = { At = input.Position, Time = os.clock() }
			-- A held finger on the world fires too; a swipe to move the camera
			-- is cancelled below when it travels.
			setHolding(true, UIController.ToCanvas(Vector2.new(input.Position.X, input.Position.Y)))
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			setHolding(false)
			return
		end
		local tap = taps[input]
		if not tap then
			return
		end
		taps[input] = nil
		setHolding(false)
		-- A quick still tap counts as one click; a long hold already fired
		-- while it was held, and a swipe counts as neither.
		local heldFor = os.clock() - tap.Time
		if not holdFired and heldFor <= TAP_MAX_SECONDS and (input.Position - tap.At).Magnitude <= TAP_MAX_MOVE then
			click(UIController.ToCanvas(Vector2.new(input.Position.X, input.Position.Y)))
		end
	end)
	-- A finger that travels is moving the camera, not clicking.
	UserInputService.InputChanged:Connect(function(input: InputObject)
		local tap = taps[input]
		if tap and (input.Position - tap.At).Magnitude > TAP_MAX_MOVE then
			taps[input] = nil
			setHolding(false)
		end
	end)

	RunService.RenderStepped:Connect(onRenderStep)
end

return ClickController
