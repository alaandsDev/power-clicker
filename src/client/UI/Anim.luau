--!strict
--[[
	Anim
	Reusable UI "game feel" helpers. Everything is tween based (no per-frame
	loops) and uses pooled instances where it spawns things.
	Respects the player's "Efeitos reduzidos" setting: particles and shakes are
	skipped, small pops are kept.

		Anim.Pop(gui, 1.2)                 -- scale bounce
		Anim.Squash(button)                -- press squash + overshoot
		Anim.Shake(gui, 8, 0.3)            -- position shake (restores exactly)
		Anim.CountUp(label, from, to, fmt) -- animated number
		Anim.Flash(frame, color)           -- background flash
		Anim.Burst(parent, pos, color, n)  -- spark particles (pooled)
]]

local TweenService = game:GetService("TweenService")

local DataController = require(script.Parent.Parent.Controllers.DataController)

local Anim = {}

local BACK_OUT = Enum.EasingStyle.Back
local OUT = Enum.EasingDirection.Out

function Anim.Reduced(): boolean
	local settings = DataController.Get("Settings")
	return settings ~= nil and settings.ReducedEffects == true
end

-- A dedicated UIScale per object so animations never fight each other.
function Anim.ScaleOf(gui: GuiObject): UIScale
	local existing = gui:FindFirstChild("AnimScale")
	if existing and existing:IsA("UIScale") then
		return existing
	end
	local scale = Instance.new("UIScale")
	scale.Name = "AnimScale"
	scale.Parent = gui
	return scale
end

function Anim.Pop(gui: GuiObject, peak: number?, duration: number?)
	local scale = Anim.ScaleOf(gui)
	scale.Scale = peak or 1.15
	TweenService:Create(scale, TweenInfo.new(duration or 0.28, BACK_OUT, OUT), { Scale = 1 }):Play()
end

-- Grows from `from` with an overshoot (entrances).
function Anim.PopIn(gui: GuiObject, from: number?, duration: number?)
	local scale = Anim.ScaleOf(gui)
	scale.Scale = from or 0.6
	TweenService:Create(scale, TweenInfo.new(duration or 0.3, BACK_OUT, OUT), { Scale = 1 }):Play()
end

-- Press feedback: quick squash, then springy return past 1.
function Anim.Squash(gui: GuiObject, rest: number?)
	local scale = Anim.ScaleOf(gui)
	scale.Scale = 0.86
	TweenService:Create(scale, TweenInfo.new(0.32, BACK_OUT, OUT), { Scale = rest or 1 }):Play()
end

-- Shakes around the original position and restores it exactly.
function Anim.Shake(gui: GuiObject, magnitude: number, duration: number)
	if Anim.Reduced() then
		return
	end
	local base = gui:GetAttribute("ShakeBase")
	local origin: UDim2 = if typeof(base) == "UDim2" then base else gui.Position
	gui:SetAttribute("ShakeBase", origin)
	task.spawn(function()
		local steps = math.max(2, math.floor(duration / 0.03))
		for i = 1, steps do
			local falloff = 1 - (i - 1) / steps
			local dx = (math.random() * 2 - 1) * magnitude * falloff
			local dy = (math.random() * 2 - 1) * magnitude * falloff
			gui.Position = origin + UDim2.fromOffset(dx, dy)
			task.wait(0.03)
		end
		gui.Position = origin
		gui:SetAttribute("ShakeBase", nil)
	end)
end

-- Animated number. `format` turns the value into text.
function Anim.CountUp(label: TextLabel, from: number, to: number, format: (number) -> string, duration: number?)
	local holder = label:FindFirstChild("CountValue")
	local value: NumberValue
	if holder and holder:IsA("NumberValue") then
		value = holder
	else
		value = Instance.new("NumberValue")
		value.Name = "CountValue"
		value.Parent = label
		value.Changed:Connect(function(current: number)
			label.Text = format(current)
		end)
	end
	if from ~= from or to ~= to or math.abs(to - from) < 1e-9 or to == math.huge then
		value.Value = to
		label.Text = format(to)
		return
	end
	value.Value = from
	TweenService:Create(value, TweenInfo.new(duration or 0.35, Enum.EasingStyle.Quad, OUT), { Value = to }):Play()
end

-- Briefly tints a frame's background, then restores it.
function Anim.Flash(gui: GuiObject, color: Color3, duration: number?)
	local base = gui:GetAttribute("FlashBase")
	local original: Color3 = if typeof(base) == "Color3" then base else gui.BackgroundColor3
	gui:SetAttribute("FlashBase", original)
	gui.BackgroundColor3 = color
	local tween = TweenService:Create(gui, TweenInfo.new(duration or 0.45), { BackgroundColor3 = original })
	tween.Completed:Once(function()
		gui:SetAttribute("FlashBase", nil)
	end)
	tween:Play()
end

-- Looping pulse (badges, highlights). Returns the tween so callers can stop it.
function Anim.Pulse(gui: GuiObject, peak: number?, period: number?): Tween
	local scale = Anim.ScaleOf(gui)
	scale.Scale = 1
	local tween = TweenService:Create(scale, TweenInfo.new((period or 0.9) / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = peak or 1.18 })
	tween:Play()
	return tween
end

-- ── Particles (pooled per parent) ───────────────────────────────────────────

type Pool = { Items: { Frame }, Index: number }
local pools: { [Instance]: Pool } = {}
local POOL_SIZE = 40

local function getSpark(parent: GuiObject): Frame
	local existing = pools[parent]
	local pool: Pool
	if existing then
		pool = existing
	else
		pool = { Items = {}, Index = 0 }
		pools[parent] = pool
		for i = 1, POOL_SIZE do
			local spark = Instance.new("Frame")
			spark.Name = "Spark" .. i
			spark.AnchorPoint = Vector2.new(0.5, 0.5)
			spark.BorderSizePixel = 0
			spark.Visible = false
			spark.ZIndex = 16
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(1, 0)
			corner.Parent = spark
			spark.Parent = parent
			table.insert(pool.Items, spark)
		end
		parent.Destroying:Once(function()
			pools[parent] = nil
		end)
	end
	pool.Index = (pool.Index % POOL_SIZE) + 1
	return pool.Items[pool.Index]
end

-- Spark burst at `position` (offset pixels inside `parent`).
function Anim.Burst(parent: GuiObject, position: Vector2, color: Color3, count: number, spread: number?)
	if Anim.Reduced() then
		return
	end
	local distance = spread or 70
	for _ = 1, count do
		local spark = getSpark(parent)
		local size = math.random(5, 11)
		local angle = math.random() * math.pi * 2
		local travel = distance * (0.5 + math.random() * 0.7)
		spark.Size = UDim2.fromOffset(size, size)
		spark.BackgroundColor3 = color
		spark.BackgroundTransparency = 0
		spark.Position = UDim2.fromOffset(position.X, position.Y)
		spark.Visible = true
		local target = position + Vector2.new(math.cos(angle), math.sin(angle)) * travel
		local tween = TweenService:Create(spark, TweenInfo.new(0.45 + math.random() * 0.2, Enum.EasingStyle.Quad, OUT), {
			Position = UDim2.fromOffset(target.X, target.Y),
			Size = UDim2.fromOffset(1, 1),
			BackgroundTransparency = 1,
		})
		tween:Play()
	end
end

return Anim
