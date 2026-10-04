--!strict
--[[
	DamageNumbers
	O dano que o hit causou na fileira (vem do WallState: o número real, não
	uma previsão), flutuando perto do impacto: aparece rápido, sobe um pouco e
	some. Em spam (9 hits/s) não vira parede de números: hits na mesma fileira
	a menos de MERGE_SECONDS um do outro SOMAM no número que ainda está na tela,
	e nunca há mais que POOL números ao mesmo tempo.

	Pool fixo de âncoras + BillboardGui criados uma vez.
]]

local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local NumberFormat = require(Shared:WaitForChild("Utils"):WaitForChild("NumberFormat"))

local POOL = 4
local MERGE_SECONDS = 0.18
local LIFETIME = 0.6
local RISE = 2.2

type Slot = { Anchor: BasePart, Gui: BillboardGui, Label: TextLabel, Row: BasePart?, Total: number, ShownAt: number, Token: number }
export type Numbers = { Slots: { Slot }, Index: number, Alive: boolean }

local DamageNumbers = {}

function DamageNumbers.new(folder: Instance, playerGui: Instance): Numbers
	local slots = {}
	for index = 1, POOL do
		local anchor = Instance.new("Part")
		anchor.Name = "DamageNumber" .. index
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.Transparency = 1
		anchor.Size = Vector3.new(0.2, 0.2, 0.2)
		anchor.Parent = folder
		local gui = Instance.new("BillboardGui")
		gui.Name = "DamageNumber" .. index
		gui.Adornee = anchor
		gui.Size = UDim2.fromOffset(130, 38)
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		gui.MaxDistance = 80
		gui.Enabled = false
		gui.ResetOnSpawn = false
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0.2
		label.Parent = gui
		gui.Parent = playerGui
		table.insert(slots, { Anchor = anchor, Gui = gui, Label = label, Row = nil, Total = 0, ShownAt = -math.huge, Token = 0 })
	end
	return { Slots = slots, Index = 0, Alive = true }
end

function DamageNumbers.Text(amount: number): string
	return "-" .. NumberFormat.Short(amount)
end

--[[
	Mostra `amount` de dano perto de `point`. `strong` = hit que tirou uma
	fatia grande da fileira (número maior e dourado).
]]
function DamageNumbers.Show(numbers: Numbers, row: BasePart, point: Vector3, amount: number, strong: boolean, now: number)
	if not numbers.Alive or amount <= 0 then
		return
	end
	local slot: Slot? = nil
	for _, candidate in numbers.Slots do
		if candidate.Row == row and now - candidate.ShownAt < MERGE_SECONDS then
			slot = candidate
			break
		end
	end
	if slot then
		slot.Total += amount
	else
		numbers.Index = (numbers.Index % #numbers.Slots) + 1
		slot = numbers.Slots[numbers.Index]
		local fresh = slot :: Slot
		fresh.Row = row
		fresh.Total = amount
		-- Um pouco para o lado a cada número novo, para não empilhar.
		fresh.Anchor.CFrame = CFrame.new(point + Vector3.new(-0.8, 1.2, (math.random() - 0.5) * 2.5))
	end
	local s = slot :: Slot
	s.ShownAt = now
	s.Token += 1
	local token = s.Token
	s.Label.Text = DamageNumbers.Text(s.Total)
	s.Label.TextColor3 = if strong then Color3.fromRGB(255, 214, 90) else Color3.new(1, 1, 1)
	s.Label.TextTransparency = 0
	s.Label.TextStrokeTransparency = 0.2
	s.Gui.Size = UDim2.fromOffset(if strong then 160 else 130, if strong then 46 else 38)
	s.Gui.Enabled = true
	local start = s.Anchor.CFrame
	TweenService:Create(s.Anchor, TweenInfo.new(LIFETIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = start + Vector3.new(0, RISE * 0.5, 0) }):Play()
	TweenService:Create(s.Label, TweenInfo.new(LIFETIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(LIFETIME, function()
		if s.Token == token then
			s.Gui.Enabled = false
			s.Row = nil
		end
	end)
end

function DamageNumbers.Visible(numbers: Numbers): number
	local count = 0
	for _, slot in numbers.Slots do
		if slot.Gui.Enabled then
			count += 1
		end
	end
	return count
end

function DamageNumbers.Destroy(numbers: Numbers)
	numbers.Alive = false
	for _, slot in numbers.Slots do
		slot.Gui:Destroy()
		slot.Anchor:Destroy()
	end
end

return DamageNumbers
