--!strict
--[[
	BuffController
	Os buffs ativos (boosts do jogador e eventos do servidor, como a Hora
	Feliz) em CHIPS compactos — ícone + multiplicador + tempo:

		⚡ x2 59:08   🔥 x2 01:01   🍀 x2 04:32   +1

	Onde: à ESQUERDA da fileira de moedas, na mesma altura delas. Antes eram
	faixas de texto empilhadas no centro, logo abaixo das moedas e em cima da
	faixa da barreira ("RECURSOS → BUFF → BUFF → HUD DA BARREIRA"); agora a
	coluna central fica só para recursos e combate. (À direita das moedas fica
	a lista de jogadores do Roblox, por isso a esquerda.)

	- No máximo MAX_CHIPS chips; o resto vira "+N" (clicar mostra o detalhe).
	- Clicar num chip mostra o nome completo por alguns segundos.
	- Buff que COMEÇA: destaque curto (BANNER_SECONDS) embaixo do chip de
	  missões — "🔥 HORA FELIZ! / PODER x2 POR 10 MIN" — e recolhe sozinho.
	- Nos últimos LAST_SECONDS o tempo pisca em vermelho, sem crescer.

	Só apresentação: duração, multiplicador e lógica continuam no servidor.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local NumberFormat = require(Shared:WaitForChild("Utils"):WaitForChild("NumberFormat"))
local BoostConfig = require(Shared:WaitForChild("Config"):WaitForChild("BoostConfig"))
local Text = require(Shared:WaitForChild("Localization"))

local Theme = require(script.Parent.Parent.UI.Theme)
local Build = require(script.Parent.Parent.UI.Build)
local Anim = require(script.Parent.Parent.UI.Anim)
local UIController = require(script.Parent.UIController)
local DataController = require(script.Parent.DataController)

local MAX_CHIPS = 3
local BAR_WIDTH = 330
local BANNER_SECONDS = 2.6
local DETAIL_SECONDS = 3
local LAST_SECONDS = 10
local ICONS = { Power = "⚡", Luck = "🍀", Event = "🔥" }

export type Buff = {
	Key: string,
	Icon: string,
	Multiplier: number,
	EndsAt: number, -- os.clock()
	Name: string, -- nome completo (detalhe e destaque)
}

local BuffController = {}

local buffs: { [string]: Buff } = {}
local seen: { [string]: boolean } = {}
local bar: Frame
local chips: { TextButton } = {}
local more: TextButton
local banner: TextLabel
local detail: TextLabel
local bannerStamp = 0
local detailStamp = 0
local boostsReceivedAt = 0

-- Texto do chip: "⚡ x2 59:08".
function BuffController.ChipText(buff: Buff, now: number): string
	local left = math.max(buff.EndsAt - now, 0)
	return string.format("%s x%s %s", buff.Icon, NumberFormat.Short(buff.Multiplier), NumberFormat.Duration(left))
end

-- Os buffs na ordem de exibição: eventos primeiro, depois o maior multiplicador.
function BuffController.Ordered(now: number): { Buff }
	local list = {}
	for _, buff in buffs do
		if buff.EndsAt > now then
			table.insert(list, buff)
		end
	end
	table.sort(list, function(a, b)
		local aEvent, bEvent = string.sub(a.Key, 1, 6) == "Event:", string.sub(b.Key, 1, 6) == "Event:"
		if aEvent ~= bEvent then
			return aEvent
		end
		if a.Multiplier ~= b.Multiplier then
			return a.Multiplier > b.Multiplier
		end
		return a.Key < b.Key
	end)
	return list
end

local function showDetail(text: string)
	detail.Text = text
	detail.Visible = true
	detailStamp += 1
	local stamp = detailStamp
	task.delay(DETAIL_SECONDS, function()
		if detailStamp == stamp then
			detail.Visible = false
		end
	end)
end

local function announce(buff: Buff, now: number)
	local minutes = math.max(math.floor((buff.EndsAt - now) / 60 + 0.5), 1)
	banner.Text = Text.Get("buff.started", { icon = buff.Icon, name = string.upper(buff.Name), mult = NumberFormat.Short(buff.Multiplier), minutes = tostring(minutes) })
	banner.Visible = true
	Anim.PopIn(banner, 0.35)
	bannerStamp += 1
	local stamp = bannerStamp
	task.delay(BANNER_SECONDS, function()
		if bannerStamp == stamp then
			banner.Visible = false
		end
	end)
end

-- Redesenha os chips (chamado a cada segundo e a cada mudança).
function BuffController.Refresh()
	local now = os.clock()
	local list = BuffController.Ordered(now)
	for index, chip in chips do
		local buff = list[index]
		chip.Visible = buff ~= nil
		if buff then
			chip.Text = BuffController.ChipText(buff, now)
			local ending = buff.EndsAt - now <= LAST_SECONDS
			chip.TextColor3 = if ending and math.floor(now * 2) % 2 == 0 then Theme.Colors.Bad else Theme.Colors.Text
			chip:SetAttribute("BuffKey", buff.Key)
		end
	end
	local extra = #list - MAX_CHIPS
	more.Visible = extra > 0
	more.Text = "+" .. tostring(math.max(extra, 0))
	bar.Visible = #list > 0
end

--[[
	Coloca/atualiza um buff. `secondsLeft` <= 0 tira. Um buff que não estava
	ativo ganha o destaque de início.
]]
function BuffController.Set(key: string, icon: string, multiplier: number, secondsLeft: number, name: string)
	local now = os.clock()
	if secondsLeft <= 0 or multiplier <= 1 then
		buffs[key] = nil
		seen[key] = nil
		BuffController.Refresh()
		return
	end
	local buff: Buff = { Key = key, Icon = icon, Multiplier = multiplier, EndsAt = now + secondsLeft, Name = name }
	buffs[key] = buff
	if not seen[key] then
		seen[key] = true
		if banner then
			announce(buff, now)
		end
	end
	BuffController.Refresh()
end

-- Hora Feliz e outros eventos do servidor (EventController repassa o EventState).
function BuffController.SetEvent(eventId: string?, multiplier: number, secondsLeft: number)
	for key in buffs do
		if string.sub(key, 1, 6) == "Event:" and key ~= "Event:" .. tostring(eventId) then
			buffs[key] = nil
			seen[key] = nil
		end
	end
	if type(eventId) ~= "string" then
		BuffController.Refresh()
		return
	end
	BuffController.Set("Event:" .. eventId, ICONS.Event, multiplier, secondsLeft, Text.Get("buff.happyHour"))
end

local function syncBoosts()
	local boosts = DataController.Get("Boosts")
	local remaining = if type(boosts) == "table" then boosts.Remaining else nil
	local elapsed = os.clock() - boostsReceivedAt
	local active: { [string]: boolean } = {}
	if type(remaining) == "table" then
		for boostId, seconds in remaining do
			local config = BoostConfig.Boosts[boostId]
			local left = (tonumber(seconds) or 0) - elapsed
			if config and left > 0 then
				active["Boost:" .. boostId] = true
				local key = "Boost:" .. boostId
				local current = buffs[key]
				-- Só reprograma quando muda de verdade (o dado chega a cada lote).
				if not current or math.abs(current.EndsAt - (os.clock() + left)) > 1.5 then
					BuffController.Set(key, ICONS[config.Category] or ICONS.Power, config.Multiplier, left, Text.Get("boost." .. boostId .. ".name"))
				end
			end
		end
	end
	for key in buffs do
		if string.sub(key, 1, 6) == "Boost:" and not active[key] then
			buffs[key] = nil
			seen[key] = nil
		end
	end
	BuffController.Refresh()
end

local function chip(name: string, order: number, textSize: number, height: number): TextButton
	local button: TextButton = Build.button({
		Name = name,
		Text = "",
		TextSize = textSize,
		Font = Theme.FontDisplay,
		TextColor3 = Theme.Colors.Text,
		BackgroundColor3 = Theme.Hud.Surface,
		BackgroundTransparency = 0.25,
		Size = UDim2.fromOffset(0, height),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = order,
		Visible = false,
		Parent = bar,
	})
	Build.corner(button, UDim.new(1, 0))
	Build.new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = button })
	return button
end

function BuffController.Init()
	local canvas = UIController.GetCanvas()
	local hud = Theme.Hud
	local touch = UIController.IsTouch()
	local textSize = if touch then 13 else 15
	local height = if touch then 24 else 26
	local topBarWidth = hud.PillSize.X * 3 + hud.TopBarGap * 2

	bar = Build.new("Frame", {
		Name = "Buffs",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		-- Encostado à esquerda das moedas, na mesma altura (centrado nelas).
		Position = UDim2.new(0.5, -(topBarWidth / 2 + hud.TopBarGap + 4), 0, hud.TopBarY + (hud.PillSize.Y - height) / 2),
		Size = UDim2.fromOffset(BAR_WIDTH, height),
		Visible = false,
		Parent = canvas,
	})
	Build.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
		Parent = bar,
	})
	for index = 1, MAX_CHIPS do
		local button = chip("Buff" .. index, index, textSize, height)
		button.Activated:Connect(function()
			local key = button:GetAttribute("BuffKey")
			local buff = if type(key) == "string" then buffs[key] else nil
			if buff then
				showDetail(string.format("%s %s x%s · %s", buff.Icon, buff.Name, NumberFormat.Short(buff.Multiplier), NumberFormat.Duration(math.max(buff.EndsAt - os.clock(), 0))))
			end
		end)
		table.insert(chips, button)
	end
	more = chip("BuffMore", MAX_CHIPS + 1, textSize, height)
	more.Activated:Connect(function()
		local lines = {}
		for _, buff in BuffController.Ordered(os.clock()) do
			table.insert(lines, string.format("%s %s x%s · %s", buff.Icon, buff.Name, NumberFormat.Short(buff.Multiplier), NumberFormat.Duration(math.max(buff.EndsAt - os.clock(), 0))))
		end
		showDetail(table.concat(lines, "\n"))
	end)

	-- Destaque de início e detalhe: à esquerda, embaixo do chip de missões —
	-- nunca na coluna central (moedas → faixa da barreira).
	local leftY = hud.TopBarY + hud.PillSize.Y + hud.Gap + 32 + 8
	banner = Build.label({
		Name = "BuffBanner",
		Text = "",
		Font = Theme.FontDisplay,
		TextSize = 18,
		TextWrapped = true,
		TextColor3 = Theme.Colors.Power,
		BackgroundColor3 = hud.Surface,
		BackgroundTransparency = 0.15,
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromOffset(hud.Margin, leftY),
		Size = UDim2.fromOffset(BAR_WIDTH, 52),
		Visible = false,
		ZIndex = 24,
		Parent = canvas,
	})
	Build.corner(banner, UDim.new(0, 12))
	Build.textStroke(banner, 2)
	detail = Build.label({
		Name = "BuffDetail",
		Text = "",
		TextSize = 14,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundColor3 = hud.Surface,
		BackgroundTransparency = 0.15,
		Position = UDim2.fromOffset(hud.Margin, leftY + 52 + 6),
		Size = UDim2.fromOffset(BAR_WIDTH, 40),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		ZIndex = 25,
		Parent = canvas,
	})
	Build.corner(detail, UDim.new(0, 10))
	Build.new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), Parent = detail })

	DataController.Changed:Connect(function(key: string)
		if key == "Boosts" then
			boostsReceivedAt = os.clock()
			syncBoosts()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			BuffController.Refresh()
		end
	end)
end

return BuffController
