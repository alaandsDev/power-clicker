--[[
	check_power_hud.luau — FASE 0 do Caminho do Poder: placa de HP NA FRENTE
	da barreira, título temporário do estágio e faixa do HUD sem duplicação.

		lune run tools/lune/check_power_hud.luau [raiz]

	Roda o WallController e o CorridorHudController REAIS, um ambiente Lune
	por jogador (cada um recebe só o próprio WallState, como no jogo).

	  1. geometria: CorridorLayout bate com as fileiras construídas; a placa
	     flutuante permanente "Estágio N — Nome" saiu do mundo;
	  2. âncora: 1,5 stud à frente da face, 7,5 do chão nas barreiras 1, 5 e
	     10 (não depende da altura), segue o lado do jogador sem sair da
	     barreira, MaxDistance 70;
	  3. câmera (projeção da câmera de 3ª pessoa do Roblox, FOV vertical 70):
	     próxima/padrão/distante × barreiras 1/5/10 × 1920x1080, 1366x768,
	     tablet e celular: placa inteira na tela, acima do personagem, abaixo
	     da coluna do topo da HUD (moedas + faixa do corredor, na escala real
	     da HUD: referência 1280x720, 0,5–1,6) e fora do botão CLIQUE/Auto;
	  4. uma placa por vez (a da barreira à frente; nenhuma no lobby);
	  5. HP individual: jogador A 20% e jogador B 80% na MESMA barreira;
	  6. golpe: a barra cai na hora, rastro ~0,25 s; <25% e <10%; quebra de
	     fileira passa para a próxima (pontos das fileiras); barreira aberta =
	     placa some (janela de prêmio sem HP);
	  7. respawn (sem personagem) e troca de estágio;
	  8. "Efeitos reduzidos": sem pulso, mas HP e nome ficam;
	  9. título temporário "⚔ 7 · ROCHA VULCÂNICA" ao entrar na área (~1,5 s),
	     sem repetir no vaivém; faixa do HUD sem nome nem HP da barreira.

	TESTE AUTOMATIZADO NÃO SUBSTITUI O STUDIO: câmera real, escala real do
	BillboardGui no celular, leitura e sobreposição com a HUD de verdade.
]]
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")
local fs = require("@lune/fs")
local V3 = roblox.Vector3

local problems = {}
local function check(condition: any, message: string)
	if condition then
		print("OK   " .. message)
	else
		table.insert(problems, message)
		print("FALHA " .. message)
	end
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
for _, pair in {
	{ "Instance", { "Changed", "ChildAdded", "ChildRemoved", "Destroying", "AncestryChanged", "AttributeChanged", "DescendantAdded" } },
	{ "GuiObject", { "InputBegan", "InputEnded", "InputChanged", "MouseEnter", "MouseLeave" } },
	{ "GuiButton", { "Activated", "MouseButton1Click" } },
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

-- ── Um cliente por jogador ──────────────────────────────────────────────────
local function makeClient(name: string)
	local C = require("./env")(process.args[1])
	local playerGui = roblox.Instance.new("Folder")
	playerGui.Name = "PlayerGui"
	local root = roblox.Instance.new("Part")
	root.Name = "HumanoidRootPart"
	local character = roblox.Instance.new("Model")
	root.Parent = character
	local attrs = {}
	local localPlayer = {
		Name = name,
		UserId = #name,
		LocaleId = "pt-br",
		Character = character,
		WaitForChild = function(_, n)
			return if n == "PlayerGui" then playerGui else nil
		end,
		FindFirstChild = function(_, n)
			return if n == "PlayerGui" then playerGui else nil
		end,
		GetAttribute = function(_, k)
			return attrs[k]
		end,
		GetAttributeChangedSignal = function()
			return Sig
		end,
	}
	C.stubs.Players = { LocalPlayer = localPlayer, GetPlayers = function()
		return { localPlayer }
	end, PlayerAdded = Sig, PlayerRemoving = Sig }
	C.stubs.TweenService = { Create = function()
		return { Play = function() end, Cancel = function() end, Completed = Sig }
	end }
	local beats = {}
	C.stubs.RunService.Heartbeat = { Connect = function(_, fn)
		table.insert(beats, fn)
		return { Disconnect = function() end }
	end }
	C.extraGlobals.TweenInfo = { new = function(...)
		return { ... }
	end }
	local handlers = {}
	local client = "StarterPlayer.Client."
	local topStack = roblox.Instance.new("Frame")
	local settings = { ReducedEffects = false }
	C.stubModules[client .. "Net.ClientNet"] = { On = function(n, fn)
		handlers[n] = fn
		return { Disconnect = function() end }
	end, Fire = function() end, Invoke = function()
		return { Ok = false }
	end }
	C.stubModules[client .. "Controllers.SoundController"] = { Play = function() end }
	C.stubModules[client .. "Controllers.NotificationController"] = { Show = function() end }
	C.stubModules[client .. "Controllers.HudController"] = { GetTopStack = function()
		return topStack
	end }
	C.stubModules[client .. "Controllers.UIController"] = { TogglePanel = function() end, IsTouch = function()
		return false
	end }
	C.stubModules[client .. "Controllers.GameStateController"] = { GetPowerInfo = function()
		return { PerClick = 10 }
	end, GetHitDamage = function()
		return 10
	end }
	C.stubModules[client .. "Controllers.DataController"] = { Get = function(k)
		return if k == "Settings" then settings else nil
	end, IsLoaded = function()
		return false
	end }
	for _, n in { "WallController", "CorridorHudController" } do
		C.patches[client .. "Controllers." .. n] = {
			{ "row.Position", "row.CFrame.Position", "all" },
			{ "root.Position", "root.CFrame.Position", "all" },
		}
	end
	local map = roblox.Instance.new("Folder")
	map.Name = "Map"
	local worlds = roblox.Instance.new("Folder")
	worlds.Name = "Worlds"
	worlds.Parent = map
	local spawns = roblox.Instance.new("Folder")
	spawns.Name = "Spawns"
	spawns.Parent = map
	map.Parent = C.Workspace
	local WallConfig = C.require(C.Shared.Config.WallConfig)
	local worldModel = C.require(C.Server.World.WorldBuilder).Build(C.require(C.Shared.Config.WorldConfig).Worlds[WallConfig.WorldId], V3.new(0, 0, 0), worlds, spawns, true)
	local Wall = C.require(C.Client.Controllers.WallController)
	local Hud = C.require(C.Client.Controllers.CorridorHudController)
	Wall.Init()
	Wall.Start()
	Hud.Init()
	Hud.Start()
	return {
		C = C,
		Wall = Wall,
		Hud = Hud,
		Root = root,
		Player = localPlayer,
		Character = character,
		Handlers = handlers,
		Settings = settings,
		TopStack = topStack,
		World = worldModel,
		WallConfig = WallConfig,
		MoveTo = function(x, z)
			root.CFrame = roblox.CFrame.new(x, 3, z or 0)
		end,
		Frame = function()
			Wall.Refresh()
		end,
		-- Um quadro de verdade: todos os Heartbeat (placa + faixa + título).
		Tick = function()
			for _, fn in beats do
				fn(1 / 60)
			end
		end,
	}
end

local A = makeClient("JogadorA")
local B = makeClient("JogadorB")
local function rowsOf(client)
	local map = {}
	for _, d in client.World:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("Wall") == true then
			map[d:GetAttribute("StageId")] = map[d:GetAttribute("StageId")] or {}
			map[d:GetAttribute("StageId")][d:GetAttribute("Row")] = d
		end
	end
	return map
end
local rowsB = rowsOf(B)
local WallConfig = A.WallConfig
local Layout = A.C.require(A.C.Shared.Formulas.CorridorLayout)

local rows = {}
for _, d in A.World:GetDescendants() do
	if d:IsA("BasePart") and d:GetAttribute("Wall") == true then
		rows[d:GetAttribute("StageId")] = rows[d:GetAttribute("StageId")] or {}
		rows[d:GetAttribute("StageId")][d:GetAttribute("Row")] = d
	end
end
local function faceOf(stageId)
	local row = rows[stageId][1]
	return row.CFrame.Position.X - row.Size.X / 2
end

-- ── 1. Geometria ────────────────────────────────────────────────────────────
local layoutOk = true
for _, segment in Layout.Segments() do
	local row = rows[segment.Id] and rows[segment.Id][1]
	if not row or math.abs(faceOf(segment.Id) - segment.Barrier) > 0.01 or math.abs(row.Size.Y - segment.Height) > 0.01 then
		layoutOk = false
		print("      " .. segment.Id .. " não bate")
	end
end
check(layoutOk and #Layout.Segments() == 10, "1. CorridorLayout bate com as 10 barreiras construídas (face e altura)")
local markers = 0
for _, d in A.World:GetDescendants() do
	if string.sub(d.Name, 1, 12) == "StageMarker_" then
		markers += 1
	end
end
check(markers == 0, "1. placa flutuante permanente \"Estágio N — Nome\" removida do corredor")

-- ── 2. Âncora ───────────────────────────────────────────────────────────────
local anchorOk = true
for _, id in { "Wood", "Gold", "Colossus" } do
	local row = rows[id][1]
	local floor = row.CFrame.Position.Y - row.Size.Y / 2
	for _, z in { 0, 20, -60, 200 } do
		local anchor = A.Wall.PlateAnchor(row, V3.new(faceOf(id) - 8, 3, z))
		local half = row.Size.Z / 2
		if math.abs(anchor.X - (faceOf(id) - 1.5)) > 0.01 or math.abs(anchor.Y - floor - A.Wall.PLATE_FLOOR_HEIGHT) > 0.01 or math.abs(anchor.Z) > half - 10 + 0.01 then
			anchorOk = false
			print(string.format("      %s z=%d: %s", id, z, tostring(anchor)))
		end
		if z == 20 and math.abs(anchor.Z - 20) > 0.01 then
			anchorOk = false
		end
	end
end
check(anchorOk and A.Wall.PLATE_FLOOR_HEIGHT == 7.5, "2. âncora 1,5 stud à frente da face e 7,5 studs do chão (B1, B5 e Colosso, mesma altura), seguindo o lado do jogador sem sair da barreira")

-- ── 3. Câmera de 3ª pessoa: a placa na tela ─────────────────────────────────
--[[
	Câmera padrão do Roblox: atrás do personagem, olhando a cabeça, um pouco
	de cima. FOV vertical 70 em qualquer tela (o horizontal muda com a
	proporção). Placa = BillboardGui de 10 x 3 studs + mínimo de 60 x 18 px.
	Coluna do topo da HUD: pílulas de recursos (y 44..88) + faixa do corredor
	(até 124) em pixels de referência, vezes a escala da HUD.
]]
local SCREENS = {
	{ "1920x1080", 1920, 1080, false },
	{ "1366x768", 1366, 768, false },
	{ "tablet 1024x768", 1024, 768, true },
	{ "celular 844x390", 844, 390, true },
}
local CAMERAS = { { "próxima", 8, 10 }, { "padrão", 12.5, 14 }, { "distante", 28, 24 } }
local function project(eye, look, right, up, k, w, h, point)
	local d = point - eye
	local z = d:Dot(look)
	if z < 0.5 then
		return nil
	end
	return w / 2 + k * d:Dot(right) / z, h / 2 - k * d:Dot(up) / z, z
end
local camOk = true
local worst = {}
for _, id in { "Wood", "Gold", "Colossus" } do
	local row = rows[id][1]
	local player = V3.new(faceOf(id) - 8, 0, 6)
	local anchor = A.Wall.PlateAnchor(row, player + V3.new(0, 3, 0))
	for _, cam in CAMERAS do
		local focus = player + V3.new(0, 4.5, 0)
		local pitch = math.rad(cam[3])
		local back = V3.new(-math.cos(pitch), math.sin(pitch), 0.12).Unit
		local eye = focus + back * cam[2]
		local target = focus + V3.new(20, -20 * math.tan(pitch), 0)
		local look = (target - eye).Unit
		local right = look:Cross(V3.new(0, 1, 0)).Unit
		local up = right:Cross(look)
		for _, screen in SCREENS do
			local w, h = screen[2], screen[3]
			local k = (h / 2) / math.tan(math.rad(35))
			local px, py, z = project(eye, look, right, up, k, w, h, anchor)
			local label = string.format("%s %s %s", id, cam[1], screen[1])
			if not px then
				camOk = false
				print("      " .. label .. ": atrás da câmera")
				continue
			end
			local size, minimum = A.Wall.PLATE_SIZE, A.Wall.PLATE_MIN_PIXELS
			local bw = k * size.X / z + minimum.X
			local bh = k * size.Y / z + minimum.Y
			local scale = math.clamp(math.min(w / 1280, h / 720), 0.5, 1.6)
			local hudBottom = (124 + 6) * scale
			local box = { px - bw / 2, py - bh / 2, px + bw / 2, py + bh / 2 }
			-- Cabeça do personagem (topo em ~5,6 studs).
			local _, headY = project(eye, look, right, up, k, w, h, player + V3.new(0, 5.6, 0))
			local inside = box[1] >= 0 and box[3] <= w and box[2] >= 0 and box[4] <= h
			local aboveHead = headY ~= nil and box[4] <= headY + 2
			-- Botão CLIQUE/Auto (canto inferior direito) e coluna de recursos (topo).
			local clickZone = { w - math.min(260, w * 0.32), h - math.min(260, h * 0.45), w, h }
			local hitsClick = box[3] > clickZone[1] and box[4] > clickZone[2]
			local hitsTop = box[2] < hudBottom
			if not (inside and aboveHead and not hitsClick and not hitsTop) then
				camOk = false
				print(string.format("      %s: caixa (%.0f,%.0f)-(%.0f,%.0f) cabeça y=%.0f dentro=%s acima=%s clique=%s topo=%s", label, box[1], box[2], box[3], box[4], headY or -1, tostring(inside), tostring(aboveHead), tostring(hitsClick), tostring(hitsTop)))
			end
			worst[screen[1]] = math.max(worst[screen[1]] or 0, bw / w)
		end
	end
end
check(camOk, "3. câmera próxima/padrão/distante × B1/B5/B10 × 1920x1080, 1366x768, tablet, celular: placa inteira na tela, acima da cabeça, fora do CLIQUE/Auto e dos recursos")
check((worst["celular 844x390"] or 1) <= 0.5, string.format("3. no celular a placa ocupa no máximo %.0f%% da largura da tela", (worst["celular 844x390"] or 1) * 100))

-- ── 4. Uma placa por vez ────────────────────────────────────────────────────
local function enabledSigns(client)
	local list = {}
	for id, sign in client.Wall.Signs() do
		if sign.Gui.Enabled then
			table.insert(list, id)
		end
	end
	return list
end
A.MoveTo(faceOf("Wood") - 8, 6)
A.Frame()
local on = enabledSigns(A)
local sign = A.Wall.Signs().Wood
check(#on == 1 and on[1] == "Wood" and sign.Gui.MaxDistance == 70 and sign.Gui.Adornee == rows.Wood[1], "4. diante da barreira 1: só a placa dela ligada (MaxDistance 70, presa à fileira da frente)")
local placed = sign.Gui.Adornee.CFrame.Position + sign.Gui.StudsOffsetWorldSpace
check((placed - A.Wall.PlateAnchor(rows.Wood[1], V3.new(0, 3, 6))).Magnitude < 0.01 and math.abs(placed.Z - 6) < 0.01, "4. a placa fica na âncora, do lado em que o jogador está")
A.MoveTo(-40, 0)
A.Frame()
check(#enabledSigns(A) == 0, "4. no lobby nenhuma placa de barreira aparece")
A.MoveTo(faceOf("Ice") - 20, 0)
A.Frame()
on = enabledSigns(A)
check(#on == 1 and on[1] == "Ice", "4. troca de estágio: diante da barreira 3 só a placa da 3 (a da 1 e a da 4 desligadas)")
A.MoveTo(faceOf("Ice") - 95, 0)
A.Frame()
check(#enabledSigns(A) == 0, "4. longe da barreira (> 70 studs): nada (não se vê o HP da próxima de longe)")

-- ── 5. HP individual ────────────────────────────────────────────────────────
local maxHp = WallConfig.Stages[1].Hp
A.Handlers.WallState({ Wood = { Hp = { maxHp * 0.2, maxHp, maxHp }, Open = false } })
B.Handlers.WallState({ Wood = { Hp = { maxHp * 0.8, maxHp, maxHp }, Open = false } })
A.MoveTo(faceOf("Wood") - 8, 0)
B.MoveTo(faceOf("Wood") - 8, 0)
A.Frame()
B.Frame()
local sa, sb = A.Wall.Signs().Wood, B.Wall.Signs().Wood
check(math.abs(sa.BarFill.Size.X.Scale - 0.2) < 0.001 and math.abs(sb.BarFill.Size.X.Scale - 0.8) < 0.001 and sa.BarText.Text ~= sb.BarText.Text, string.format("5. mesma barreira, HP próprio: A vê %s (20%%), B vê %s (80%%)", sa.BarText.Text, sb.BarText.Text))
check(sa.Name.Text == "1 · Madeira" and sb.Name.Text == "1 · Madeira", "5. nome na placa: \"1 · Madeira\"")

-- ── 6. Golpe, rastro, HP baixo, fileiras, quebra ────────────────────────────
B.Handlers.WallState({ Wood = { Hp = { maxHp * 0.5, maxHp, maxHp }, Open = false } })
B.Frame()
local fillNow, trailNow = sb.BarFill.Size.X.Scale, sb.Trail.Size.X.Scale
check(math.abs(fillNow - 0.5) < 0.001 and trailNow > 0.75, string.format("6. golpe: a barra cai NA HORA (%.2f) e o HP perdido fica como rastro (%.2f)", fillNow, trailNow))
task.wait(0.3)
B.Frame()
check(math.abs(sb.Trail.Size.X.Scale - 0.5) < 0.001, "6. o rastro some em ~0,25 s")
local ok = sb.BarFill.BackgroundColor3
B.Handlers.WallState({ Wood = { Hp = { maxHp * 0.2, maxHp, maxHp }, Open = false } })
B.Frame()
local low = sb.BarFill.BackgroundColor3
B.Handlers.WallState({ Wood = { Hp = { maxHp * 0.05, maxHp, maxHp }, Open = false } })
B.Frame()
local critical = sb.BarFill.BackgroundColor3
local pulses = {}
for _ = 1, 4 do
	B.Frame()
	pulses[sb.BarFill.BackgroundTransparency] = true
	task.wait(0.08)
end
local pulseCount = 0
local maxPulse = 0
for value in pulses do
	pulseCount += 1
	maxPulse = math.max(maxPulse, value)
end
check(ok ~= low and low ~= critical and pulseCount > 1 and maxPulse <= 0.2, "6. <25% muda a cor discretamente; <10% cor crítica e pulso leve (transparência ≤ 0,2, sem piscar a placa)")
-- Fileira 1 cai: a placa vai para a fileira 2 e os pontos mostram o avanço.
B.Handlers.WallState({ Wood = { Hp = { 0, maxHp, maxHp }, Open = false } })
B.Frame()
check(sb.Gui.Enabled and sb.Gui.Adornee == rowsB.Wood[2] and sb.BarFill.Size.X.Scale == 1 and #sb.Pips == 3 and sb.Pips[1].BackgroundTransparency > sb.Pips[2].BackgroundTransparency, "6. fileira 1 caiu: placa na fileira 2, barra cheia (sem rastro falso), ponto da 1 apagado")
B.Handlers.WallState({ Wood = { Hp = { 0, 0, 0 }, Open = true } })
B.MoveTo(faceOf("Wood") + 40, 0)
B.Frame()
check(not sb.Gui.Enabled and #enabledSigns(B) == 0, "6. 0 HP: a placa some (janela de prêmio sem HP competindo com os pads)")
B.MoveTo(faceOf("Wood") - 8, 0)
B.Frame()
check(not sb.Gui.Enabled, "6. barreira aberta não mostra \"0 / X\" nem de frente")
check(A.Wall.Signs().Wood.Gui.Enabled, "6. ... e o jogador A, que não quebrou, continua vendo a placa dele")

-- ── 7. Respawn ──────────────────────────────────────────────────────────────
A.Player.Character = nil
A.Frame()
check(#enabledSigns(A) == 0, "7. sem personagem (morreu/respawn): nenhuma placa")
A.Player.Character = A.Character
A.MoveTo(faceOf("Wood") - 8, 0)
A.Frame()
check(#enabledSigns(A) == 1, "7. voltou: a placa volta com o HP dele")

-- ── 8. Efeitos reduzidos ────────────────────────────────────────────────────
A.Settings.ReducedEffects = true
A.Handlers.WallState({ Wood = { Hp = { maxHp * 0.05, maxHp, maxHp }, Open = false } })
A.Frame()
local sa2 = A.Wall.Signs().Wood
check(sa2.Gui.Enabled and sa2.BarFill.BackgroundTransparency == 0 and sa2.BarText.Text ~= "" and sa2.Name.Text ~= "", "8. \"Efeitos reduzidos\": sem pulso, mas placa, nome e HP continuam")
A.Settings.ReducedEffects = false

-- ── 9. Título temporário e faixa do HUD ─────────────────────────────────────
local title = A.TopStack:FindFirstChild("StageTitle")
local segment7 = Layout.Segments()[7]
A.MoveTo(-40, 0)
A.Tick()
check(title and not title.Visible, "9. no lobby, nenhum título de estágio")
A.MoveTo(segment7.AreaStart + 10, 0)
A.Tick()
check(title and title.Visible and title.Text == "⚔ 7 · ROCHA VULCÂNICA", "9. ao ENTRAR na área do estágio 7 (laço real do HUD): \"" .. (title and title.Text or "?") .. "\"")
task.wait(1.6)
A.Tick()
check(title and not title.Visible, "9. o título some sozinho (~1,5 s)")
A.MoveTo(segment7.AreaStart - 5, 0)
A.Tick()
A.MoveTo(segment7.AreaStart + 5, 0)
A.Tick()
check(title and not title.Visible, "9. vaivém na fronteira: não repete o título em seguida (8 s)")
A.MoveTo(Layout.Segments()[8].AreaStart + 10, 0)
A.Tick()
check(title and title.Visible and title.Text == "⚔ 8 · MAGMA CRISTALIZADO", "9. troca de estágio: o título do 8 entra")
local panel = A.TopStack:FindFirstChild("CorridorHud")
local texts = {}
for _, d in panel:GetDescendants() do
	if d:IsA("TextLabel") then
		table.insert(texts, d.Name)
	end
end
check(panel and panel:FindFirstChild("Stage", true) == nil and panel:FindFirstChild("Damage", true) == nil and panel:FindFirstChild("Status", true) and panel:FindFirstChild("Reward", true), "9. faixa do HUD sem nome e sem barra de HP da barreira (só golpe, golpes restantes e prêmio)")
local strings = fs.readFile(A.C.Root .. "/src/shared/Localization/Strings/ptBR.luau")
check(string.find(strings, '"corridor.hit"] = "Seu golpe: {icon} {power}"', 1, true) and not string.find(strings, '"corridor.status"', 1, true) and not string.find(strings, '"wall.marker"', 1, true), "9. textos: \"Seu golpe\" no HUD; HP da fileira e \"Estágio N — Nome\" saíram (estão na placa)")

-- Servidor intocado.
local diff = fs.readFile(A.C.Root .. "/src/server/Services/WallService.luau")
check(not string.find(diff, "Plate", 1, true), "servidor: WallService sem mudança de placa (tudo no cliente)")

if #problems > 0 then
	print(#problems .. " problema(s).")
	process.exit(1)
end
print("OK: placa de HP na frente da barreira, uma por vez, individual; título temporário; HUD sem duplicação.")
print("REQUER VALIDAÇÃO NO ROBLOX STUDIO: câmera real, celular, leitura e sobreposição com a HUD.")
process.exit(0)
