--!strict
--[[
	TrainingController
	O aviso de "treinando" no HUD.

	O servidor (TrainingService) escreve dois atributos no jogador enquanto ele
	está numa máquina: "Training" (id da estação) e "TrainingRate" (Power por
	segundo já com todos os multiplicadores). Este controller só desenha isso —
	não decide nem calcula nada, e por isso não há o que burlar aqui.

	Também mostra o aviso curto quando o servidor recusa o treino num alvo
	bloqueado (Notify "TrainingLocked": "Você precisa de X Renascimentos para
	treinar aqui."). O servidor manda uma vez por entrada no alvo.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local NumberFormat = require(Shared:WaitForChild("Utils"):WaitForChild("NumberFormat"))
local Text = require(Shared:WaitForChild("Localization"))

local Theme = require(script.Parent.Parent.UI.Theme)
local Build = require(script.Parent.Parent.UI.Build)
local Anim = require(script.Parent.Parent.UI.Anim)
local HudController = require(script.Parent.HudController)
local NotificationController = require(script.Parent.NotificationController)
local ClientNet = require(script.Parent.Parent.Net.ClientNet)

local CHIP_WIDTH = 260

local TrainingController = {}

local chip: TextLabel

local function refresh()
	local player = Players.LocalPlayer
	local station = player:GetAttribute("Training")
	local rate = player:GetAttribute("TrainingRate")
	if type(station) ~= "string" or type(rate) ~= "number" then
		chip.Visible = false
		return
	end
	chip.Text = Text.Get("training.active", {
		amount = NumberFormat.Short(rate),
		icon = Theme.Icons.Power,
	})
	if not chip.Visible then
		chip.Visible = true
		Anim.PopIn(chip, 0.4)
	end
end

function TrainingController.Init()
	local hud = Theme.Hud
	chip = Build.label({
		Name = "TrainingChip",
		Text = "",
		Font = Theme.FontDisplay,
		TextSize = 20,
		BackgroundColor3 = Theme.Colors.Good,
		BackgroundTransparency = 0.1,
		-- Na coluna central abaixo das moedas: é um estado, não um botão.
		Size = UDim2.fromOffset(CHIP_WIDTH, hud.ChipHeight),
		Visible = false,
		LayoutOrder = 4,
		Parent = HudController.GetTopStack(),
	})
	Build.corner(chip, UDim.new(1, 0))
	Build.textStroke(chip, 2)

	local player = Players.LocalPlayer
	player:GetAttributeChangedSignal("Training"):Connect(refresh)
	player:GetAttributeChangedSignal("TrainingRate"):Connect(refresh)
	refresh()

	ClientNet.On("Notify", function(kind: any, payload: any)
		if kind ~= "TrainingLocked" or type(payload) ~= "table" then
			return
		end
		local count = math.max(math.floor(tonumber(payload.Rebirths) or 0), 1)
		local text = if count == 1 then Text.Get("training.lockedOne") else Text.Get("training.locked", { count = tostring(count) })
		NotificationController.Show(text, "Bad")
	end)
end

return TrainingController
