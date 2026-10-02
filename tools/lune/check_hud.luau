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
	  - números flutuantes nascem ACIMA da faixa do rodapé.

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
	for _, n in { "Boosts", "HappyHour", "BossBar", "TrainingChip", "CorridorHud", "Combo", "QuestChip", "MenuSecondary" } do
		local g = find(n)
		if g then
			g.Visible = true
		else
			table.insert(problems, "elemento não encontrado: " .. n)
		end
	end
	for _, n in { "Boosts", "HappyHour" } do -- AutomaticSize X: largura plausível
		local g = find(n)
		if g then
			g.Size = roblox.UDim2.fromOffset(260, g.Size.Y.Offset)
		end
	end
	local secondary = find("MenuSecondary")
	if secondary then
		secondary.Size = roblox.UDim2.fromOffset(secondary.Size.X.Offset, gridHeight(secondary))
	end

	local items = {}
	for _, n in { "Power", "Gems", "Wins", "Boosts", "HappyHour", "BossBar", "TrainingChip", "CorridorHud", "QuestChip", "Menu", "MenuSecondary", "ClickStatus", "Level", "ComboSlot", "Overdrive", "Fill", "ClickButton" } do
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
		{ "Power", "Gems", "Wins", "Boosts", "HappyHour", "BossBar", "TrainingChip", "CorridorHud", "QuestChip", "Menu", "MenuSecondary", "ClickStatus", "ClickButton" },
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
	local hud = loaded.HudController
	if items.ClickStatus and items.ClickButton and hud.DockHeight then
		local floatCentre = items.ClickButton.y - hud.DockHeight() - 26
		if floatCentre + 22 > items.ClickStatus.y + 0.5 then
			table.insert(problems, "números flutuantes nascem em cima da faixa do rodapé")
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
