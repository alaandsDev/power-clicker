--[[
	check_hud.luau — inicializa os controllers REAIS do cliente (na ordem do
	ClientBootstrap) fora do Roblox e mede onde cada elemento do HUD cai na
	tela, em várias resoluções, com mouse e com toque.

		lune run tools/lune/check_hud.luau [raiz]

	Para cada combinação verifica:
	  - nenhuma sobreposição entre moedas, coluna central (buffs, evento,
	    chefe, treino, faixa do corredor), chip de missões, menu, painel do
	    "Mais", faixa do rodapé e botão CLIQUE — com TUDO visível ao mesmo
	    tempo (pior caso);
	  - nenhuma sobreposição dentro do rodapé (nível · combo · overdrive ·
	    barra · botão);
	  - tudo dentro da tela;
	  - tutorial e avisos (toasts) também entram no pior caso;
	  - faixa de feedback: no máximo 6 números de clique e 3 do automático;
	    o trajeto deles não cruza moedas, menu, rodapé nem botão e não sobe
	    sobre o personagem (acima de 60% da altura).

	REQUER VALIDAÇÃO NO STUDIO: tamanho real do texto (TextScaled, fontes),
	a câmera/personagem real e a sensação de leitura — este script mede caixas.

	Resoluções são o "canvas" de referência: o UIController escala a tela
	inteira de forma uniforme a partir de 1280x720, então um celular em
	paisagem vira um canvas mais largo e um tablet 4:3 um canvas mais alto.

	O resolvedor de layout é simples (Position/Size/AnchorPoint, UIPadding,
	UIListLayout e UIGridLayout); não mede texto. Controllers que dependem de
	serviços sem stub (Shop, Vip, Interact, PetFollow) falham no Init aqui e
	são listados — isso é limitação do ambiente, não do jogo.

	Sai com código 1 se houver problema de layout.
]]
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local makeEnv = require("./env")
local V2 = roblox.Vector2
local root = process.args[1]

local function anyStub()
	return setmetatable({}, {
		__index = function(_, key)
			if key == "Connect" or key == "Once" then
				return function()
					return { Disconnect = function() end }
				end
			end
			return anyStub()
		end,
		__call = function()
			return anyStub()
		end,
	})
end
local Sig = {
	Connect = function()
		return { Disconnect = function() end }
	end,
	Once = function()
		return { Disconnect = function() end }
	end,
	Wait = function() end,
}
-- Eventos de instância (o Lune não tem): todos viram um sinal inerte.
for _, pair in {
	{ "Instance", { "Changed", "ChildAdded", "ChildRemoved", "Destroying", "AncestryChanged", "AttributeChanged", "DescendantAdded" } },
	{ "GuiObject", { "InputBegan", "InputEnded", "InputChanged", "MouseEnter", "MouseLeave", "MouseMoved", "SelectionGained", "SelectionLost" } },
	{ "GuiButton", { "Activated", "MouseButton1Down", "MouseButton1Up", "MouseButton1Click", "MouseButton2Click" } },
	{ "TextBox", { "FocusLost", "Focused" } },
	{ "BasePart", { "Touched", "TouchEnded" } },
	{ "ProximityPrompt", { "Triggered", "PromptShown", "PromptHidden" } },
} do
	for _, name in pair[2] do
		roblox.implementProperty(pair[1], name, function()
			return Sig
		end)
	end
end
roblox.implementMethod("Instance", "GetPropertyChangedSignal", function()
	return Sig
end)
roblox.implementMethod("Instance", "GetAttributeChangedSignal", function()
	return Sig
end)

local function run(touch: boolean, CW: number, CH: number): ({ string }, { string })
	local E = makeEnv(root)
	local playerGui = roblox.Instance.new("Folder")
	playerGui.Name = "PlayerGui"
	local localPlayer = {
		Name = "Tester",
		DisplayName = "Tester",
		UserId = 1,
		LocaleId = "pt-br",
		PlayerGui = playerGui,
		WaitForChild = function(_, n)
			return if n == "PlayerGui" then playerGui else nil
		end,
		FindFirstChild = function(_, n)
			return if n == "PlayerGui" then playerGui else nil
		end,
		GetAttribute = function()
			return nil
		end,
		SetAttribute = function() end,
		GetAttributeChangedSignal = function()
			return Sig
		end,
		CharacterAdded = Sig,
		CharacterRemoving = Sig,
		Character = nil,
		GetMouse = function()
			return anyStub()
		end,
	}
	local function tween()
		return { Play = function() end, Cancel = function() end, Pause = function() end, Completed = Sig }
	end
	E.stubs.Players = { LocalPlayer = localPlayer, GetPlayers = function()
		return { localPlayer }
	end, PlayerAdded = Sig, PlayerRemoving = Sig, GetPlayerByUserId = function()
		return nil
	end }
	E.stubs.TweenService = { Create = function()
		return tween()
	end }
	E.stubs.UserInputService = setmetatable({
		TouchEnabled = touch,
		KeyboardEnabled = not touch,
		GamepadEnabled = false,
		MouseEnabled = not touch,
		InputBegan = Sig,
		InputEnded = Sig,
		InputChanged = Sig,
		TouchStarted = Sig,
		TouchEnded = Sig,
		LastInputTypeChanged = Sig,
		GetLastInputType = function()
			return roblox.Enum.UserInputType.MouseButton1
		end,
	}, { __index = function()
		return anyStub()
	end })
	E.stubs.ContextActionService = { BindAction = function() end, UnbindAction = function() end }
	E.stubs.StarterGui = { SetCoreGuiEnabled = function() end, SetCore = function() end }
	E.stubs.ContentProvider = { PreloadAsync = function() end }
	E.stubs.SoundService = anyStub()
	E.stubs.GuiService = anyStub()
	E.stubs.MarketplaceService = anyStub()
	E.stubs.Lighting = roblox.Instance.new("Lighting")
	E.stubs.TextService = { GetTextSize = function(_, text, size)
		return V2.new(#text * size * 0.5, size)
	end }
	E.stubs.RunService.RenderStepped = Sig
	E.stubs.RunService.Stepped = Sig
	E.stubs.RunService.BindToRenderStep = function() end
	E.extraGlobals.TweenInfo = { new = function(...)
		return { ... }
	end }
	local camera = { ViewportSize = V2.new(CW, CH), CFrame = roblox.CFrame.new(), GetPropertyChangedSignal = function()
		return Sig
	end }
	E.extraGlobals.workspace = setmetatable({ CurrentCamera = camera }, { __index = function(_, k)
		return E.Workspace[k]
	end })

	-- O UIController lê AbsoluteSize (que o Lune não calcula): fixa o canvas.
	local client = "StarterPlayer.Client."
	E.patches[client .. "Controllers.UIController"] = {
		{ "local size = screenGui.AbsoluteSize", "local size = Vector2.new(1280, 720)" },
		{ "return canvas.AbsoluteSize / math.max(uiScale.Scale, 0.01)", "return Vector2.new(" .. CW .. ", " .. CH .. ")" },
	}
	-- Sem servidor: remotes inertes.
	E.stubModules[client .. "Net.ClientNet"] = setmetatable({
		On = function() end,
		Fire = function() end,
		Invoke = function()
			return { Ok = false }
		end,
	}, { __index = function()
		return function() end
	end })

	-- Boot na ordem do ClientBootstrap (lida do próprio arquivo).
	local order = {}
	local list = string.match(E.Client.ClientBootstrap.Source, "local CONTROLLER_ORDER = (%b{})")
	for name in string.gmatch(list, '\n%s*"(%w+)",') do
		table.insert(order, name)
	end
	local initFailures = {}
	local loaded = {}
	for _, name in order do
		local ok, mod = pcall(E.require, E.Client.Controllers[name])
		if ok then
			loaded[name] = mod
		else
			table.insert(initFailures, name .. " (require)")
		end
	end
	for _, name in order do
		local mod = loaded[name]
		if mod and mod.Init then
			local ok = pcall(mod.Init)
			if not ok then
				table.insert(initFailures, name)
			end
		end
	end

	-- ── Resolvedor de layout ────────────────────────────────────────────────
	local CANVAS = V2.new(CW, CH)
	local canvasFrame = loaded.UIController.GetCanvas()
	local rects = {}
	local function sizeOf(g, parentSize)
		local s = g.Size
		return V2.new(s.X.Scale * parentSize.X + s.X.Offset, s.Y.Scale * parentSize.Y + s.Y.Offset)
	end
	local function visibleChildren(parent)
		local list2 = {}
		for _, c in parent:GetChildren() do
			if c:IsA("GuiObject") and c.Visible then
				table.insert(list2, c)
			end
		end
		table.sort(list2, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		return list2
	end
	local function rectOf(g)
		if g == canvasFrame then
			return V2.new(0, 0), CANVAS
		end
		if rects[g] then
			return rects[g][1], rects[g][2]
		end
		local parent = g.Parent
		local ppos, psize = rectOf(parent)
		local pad = parent:FindFirstChildOfClass("UIPadding")
		if pad then
			ppos += V2.new(pad.PaddingLeft.Offset, pad.PaddingTop.Offset)
			psize -= V2.new(pad.PaddingLeft.Offset + pad.PaddingRight.Offset, pad.PaddingTop.Offset + pad.PaddingBottom.Offset)
		end
		local size = sizeOf(g, psize)
		local pos
		local layout = parent:FindFirstChildOfClass("UIListLayout")
		local grid = parent:FindFirstChildOfClass("UIGridLayout")
		if layout and layout.FillDirection == roblox.Enum.FillDirection.Vertical then
			local y = 0
			for _, c in visibleChildren(parent) do
				local cs = sizeOf(c, psize)
				if c == g then
					pos = ppos + V2.new((psize.X - cs.X) / 2, y)
					break
				end
				y += cs.Y + layout.Padding.Offset
			end
		elseif layout then
			local sibs = visibleChildren(parent)
			local widths, totalWidth = {}, 0
			for i, c in sibs do
				widths[i] = sizeOf(c, psize).X
				totalWidth += widths[i] + (if i > 1 then layout.Padding.Offset else 0)
			end
			local x = (psize.X - totalWidth) / 2
			for i, c in sibs do
				if c == g then
					pos = ppos + V2.new(x, 0)
					break
				end
				x += widths[i] + layout.Padding.Offset
			end
		elseif grid then
			local cw, ch = grid.CellSize.X.Offset, grid.CellSize.Y.Offset
			local gap = grid.CellPadding
			local cols = math.max(math.floor((psize.X + gap.X.Offset) / (cw + gap.X.Offset)), 1)
			size = V2.new(cw, ch)
			for i, c in visibleChildren(parent) do
				if c == g then
					pos = ppos + V2.new(((i - 1) % cols) * (cw + gap.X.Offset), ((i - 1) // cols) * (ch + gap.Y.Offset))
				end
			end
		else
			local p = g.Position
			pos = ppos
				+ V2.new(p.X.Scale * psize.X + p.X.Offset, p.Y.Scale * psize.Y + p.Y.Offset)
				- V2.new(g.AnchorPoint.X * size.X, g.AnchorPoint.Y * size.Y)
		end
		pos = pos or ppos
		rects[g] = { pos, size }
		return pos, size
	end
	-- Altura de um frame AutomaticSize Y com grade (painel do "Mais").
	local function gridHeight(frame)
		local grid = frame:FindFirstChildOfClass("UIGridLayout")
		local pad = frame:FindFirstChildOfClass("UIPadding")
		local padX = if pad then pad.PaddingLeft.Offset + pad.PaddingRight.Offset else 0
		local padY = if pad then pad.PaddingTop.Offset + pad.PaddingBottom.Offset else 0
		local cols = math.max(math.floor((frame.Size.X.Offset - padX + grid.CellPadding.X.Offset) / (grid.CellSize.X.Offset + grid.CellPadding.X.Offset)), 1)
		local rows = math.ceil(#visibleChildren(frame) / cols)
		return rows * grid.CellSize.Y.Offset + math.max(rows - 1, 0) * grid.CellPadding.Y.Offset + padY
	end
	local function find(name)
		for _, d in canvasFrame:GetDescendants() do
			if d.Name == name then
				return d
			end
		end
		return nil
	end

	local problems = {}
	-- Pior caso: tudo que pode aparecer, visível ao mesmo tempo.
	-- Inclui tutorial e avisos: a versão anterior deixava os dois de fora e
	-- declarou "OK" enquanto o tutorial cobria as moedas no Studio.
	for _, n in { "TutorialBanner", "Toast1", "WallBanner", "ObjectiveChip", "Buffs", "BuffBanner", "BuffDetail", "AutoClick", "BossBar", "TrainingChip", "CorridorHud", "Combo", "QuestChip", "MenuSecondary" } do
		local g = find(n)
		if g then
			g.Visible = true
		else
			table.insert(problems, "elemento não encontrado: " .. n)
		end
	end
	for _, n in { "ObjectiveChip" } do -- AutomaticSize X: largura plausível
		local g = find(n)
		if g then
			g.Size = roblox.UDim2.fromOffset(260, g.Size.Y.Offset)
		end
	end
	local toasts = find("Toasts")
	local firstToast = find("Toast1")
	if toasts and firstToast then -- AutomaticSize Y: altura de um aviso visível
		toasts.Size = roblox.UDim2.fromOffset(toasts.Size.X.Offset, firstToast.Size.Y.Offset)
	end
	local secondary = find("MenuSecondary")
	if secondary then
		secondary.Size = roblox.UDim2.fromOffset(secondary.Size.X.Offset, gridHeight(secondary))
	end

	local items = {}
	for _, n in { "Power", "Gems", "Wins", "TutorialBanner", "Toasts", "WallBanner", "ObjectiveChip", "Buffs", "BuffBanner", "BuffDetail", "AutoClick", "BossBar", "TrainingChip", "CorridorHud", "QuestChip", "Menu", "MenuSecondary", "ClickStatus", "Level", "ComboSlot", "Overdrive", "Fill", "ClickButton" } do
		local g = find(n)
		if g then
			local p, s = rectOf(g)
			items[n] = { x = p.X, y = p.Y, w = s.X, h = s.Y }
		end
	end
	local function overlap(a, b)
		return a.x < b.x + b.w - 0.5 and b.x < a.x + a.w - 0.5 and a.y < b.y + b.h - 0.5 and b.y < a.y + a.h - 0.5
	end
	for _, group in {
		{ "Power", "Gems", "Wins", "TutorialBanner", "Toasts", "WallBanner", "ObjectiveChip", "Buffs", "BuffBanner", "BuffDetail", "AutoClick", "BossBar", "TrainingChip", "CorridorHud", "QuestChip", "Menu", "MenuSecondary", "ClickStatus", "ClickButton" },
		{ "Level", "ComboSlot", "Overdrive", "Fill", "ClickButton" },
	} do
		for i = 1, #group do
			for j = i + 1, #group do
				local a, b = items[group[i]], items[group[j]]
				if a and b and overlap(a, b) then
					table.insert(problems, "sobreposição: " .. group[i] .. " × " .. group[j])
				end
			end
		end
	end
	for name, r in items do
		if r.x < 0 or r.y < 0 or r.x + r.w > CW or r.y + r.h > CH then
			table.insert(problems, "fora da tela: " .. name)
		end
	end
	--[[
		Faixa de feedback (números flutuantes). Usa as constantes do próprio
		ClickController e a posição real da faixa do rodapé:
		  - no máximo 6 números de clique e 3 do automático existindo;
		  - o caminho inteiro de cada número (nascer -> subir) não cruza moedas,
		    menu, faixa do rodapé nem botão, e não sobe além de 60% da altura da
		    tela (onde fica o personagem).
	]]
	local clickSource = E.Client.Controllers.ClickController.Source
	local function constant(name: string): number
		return tonumber(string.match(clickSource, "local " .. name .. " = ([%d%.]+)")) or -1
	end
	local hud = loaded.HudController
	local floatLayer = find("FloatingNumbers")
	local clickFloats, autoFloats = 0, 0
	if floatLayer then
		for _, child in floatLayer:GetChildren() do
			if string.match(child.Name, "^Float%d+$") then
				clickFloats += 1
			elseif string.match(child.Name, "^AutoFloat%d+$") then
				autoFloats += 1
			end
		end
	end
	if clickFloats > 6 or clickFloats == 0 then
		table.insert(problems, string.format("feedback: %d números de clique simultâneos (máx. 6)", clickFloats))
	end
	if autoFloats > 3 or autoFloats == 0 then
		table.insert(problems, string.format("feedback: %d números do automático simultâneos (máx. 3)", autoFloats))
	end
	if items.ClickStatus and items.ClickButton and hud.DockHeight then
		local buttonTop = CH - items.ClickButton.y
		local lift, rise, spread = constant("FLOAT_LIFT"), constant("FLOAT_RISE"), constant("FLOAT_SPREAD_X")
		local autoRise = constant("AUTO_RISE")
		local floatW, floatH = 240, 44
		local startY = CH - buttonTop - hud.DockHeight() - lift
		local click = { x = CW / 2 - spread - floatW / 2, y = startY - 14 - rise - floatH / 2, w = spread * 2 + floatW, h = 14 + rise + floatH }
		-- Mesma posição que o ClickController usa para a trilha do automático.
		local Theme = E.require(E.Client.UI.Theme)
		local autoX = CW / 2 + Theme.Hud.LevelBar.X / 2 + 16
		local autoY = CH - buttonTop - hud.DockHeight() / 2
		local auto = { x = autoX, y = autoY - autoRise - 13, w = 160, h = autoRise + 26 }
		for label, lane in { clique = click, automatico = auto } do
			for _, other in { "ClickStatus", "ClickButton", "Menu", "Power", "Gems", "Wins" } do
				if items[other] and overlap(lane, items[other]) then
					table.insert(problems, string.format("feedback (%s): trajeto cruza %s", label, other))
				end
			end
			if lane.y < CH * 0.6 then
				table.insert(problems, string.format("feedback (%s): sobe até y=%.0f, em cima do personagem", label, lane.y))
			end
			if lane.x < 0 or lane.x + lane.w > CW then
				table.insert(problems, string.format("feedback (%s): sai da tela", label))
			end
		end
	end
	--[[
		Buffs: chips compactos (ícone + multiplicador + tempo), fora da coluna
		central (moedas → faixa da barreira), no máximo 3 + "+N", destaque só
		quando um buff começa.
	]]
	local Buffs = loaded.BuffController
	if Buffs then
		local bar, banner = find("Buffs"), find("BuffBanner")
		local corridor, coins = items.CorridorHud, items.Power
		if bar and corridor and coins then
			local p, s = rectOf(bar)
			local barRect = { x = p.X, y = p.Y, w = s.X, h = s.Y }
			if overlap(barRect, corridor) or barRect.x + barRect.w > coins.x + 1 then
				table.insert(problems, "buffs: invadem a coluna central (moedas/faixa da barreira)")
			end
			if barRect.y > coins.y + coins.h then
				table.insert(problems, "buffs: abaixo das moedas (empurrariam a faixa da barreira)")
			end
		end
		banner.Visible = false
		Buffs.Set("Boost:Power2x", "⚡", 2, 3548, "2x Poder")
		local chip1 = find("Buff1")
		if not (chip1 and chip1.Visible and string.match(chip1.Text, "^⚡ x2 ") and banner.Visible) then
			table.insert(problems, "buffs: 1 buff não virou chip compacto \"⚡ x2 tempo\" com destaque de início")
		end
		banner.Visible = false
		Buffs.Set("Boost:Power2x", "⚡", 2, 3500, "2x Poder")
		if banner.Visible then
			table.insert(problems, "buffs: o destaque repetiu num buff que já estava ativo")
		end
		Buffs.SetEvent("HappyHour", 2, 61)
		Buffs.Set("Boost:Luck2x", "🍀", 2, 272, "2x Sorte")
		Buffs.Set("Boost:Power5x", "⚡", 5, 600, "5x Poder")
		Buffs.Set("Boost:Extra", "⚡", 3, 900, "Extra")
		local visibleChips = 0
		for index = 1, 3 do
			local chip = find("Buff" .. index)
			if chip and chip.Visible then
				visibleChips += 1
			end
		end
		local more = find("BuffMore")
		if visibleChips ~= 3 or not more or not more.Visible or more.Text ~= "+2" then
			table.insert(problems, string.format("buffs: 5 ativos deveriam ser 3 chips + \"+2\" (%d chips, %s)", visibleChips, more and more.Text or "sem +N"))
		end
		if not string.match(find("Buff1").Text, "^🔥 x2 ") then
			table.insert(problems, "buffs: o evento (Hora Feliz) deveria vir primeiro")
		end
		Buffs.SetEvent(nil, 1, 0)
		for _, key in { "Boost:Power2x", "Boost:Luck2x", "Boost:Power5x", "Boost:Extra" } do
			Buffs.Set(key, "⚡", 2, 0, "")
		end
		if find("Buffs").Visible then
			table.insert(problems, "buffs: sem buff ativo a barra deveria sumir")
		end
	end
	return problems, initFailures
end

-- Controllers que usam serviços sem stub aqui (TextChatService,
-- ProximityPromptService, Marketplace...): falham no Init só neste ambiente.
local STUB_LIMITED = { ShopController = true, VipController = true, InteractController = true, PetFollowController = true }

local failed = false
for _, case in {
	{ false, 1280, 720, "PC 16:9" },
	{ true, 1280, 720, "toque 16:9" },
	{ true, 1561, 720, "celular paisagem (~19.5:9)" },
	{ true, 1280, 960, "tablet 4:3" },
	{ false, 1561, 720, "PC ultrawide" },
} do
	local problems, initFailures = run(case[1], case[2], case[3])
	local label = string.format("%-28s %dx%d", case[4], case[2], case[3])
	if #problems == 0 then
		print("OK   " .. label)
	else
		failed = true
		print("FALHA " .. label)
		for _, message in problems do
			print("      " .. message)
		end
	end
	for _, name in initFailures do
		if not STUB_LIMITED[name] then
			failed = true
			print("      Init falhou (inesperado): " .. name)
		end
	end
end
print("(Init sem stub no Lune, ignorados: ShopController, VipController, InteractController, PetFollowController)")
process.exit(if failed then 1 else 0)
