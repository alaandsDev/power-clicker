--!strict
--[[
	StationFxController
	O MOVIMENTO das estações do lobby (server/World/StationMachines: Melhorias,
	Forja de Cortes...). Um controlador central para todas; tudo local e só
	visual:

	- núcleo de poder gira devagar e pulsa (Transparency), a casca gira ao
	  contrário;
	- os dois anéis giram em volta do núcleo;
	- as setas de energia nas colunas acendem de baixo para cima (↑↑↑), em
	  onda — "upgrade" sem precisar ler;
	- o técnico respira e vira um pouco para o jogador que chega perto;
	- a tela do console mostra barras subindo;
	- JOGADOR NO PONTO DE USO (a até ENGAGE_DISTANCE da tela): a máquina
	  "acorda" de leve — núcleo ~10% mais intenso e mais rápido, setas mais
	  rápidas, tela mais viva — e volta ao normal quando ele sai. Só visual;
	- peças marcadas StationCutTint (o slash da forja, a bigorna, as faíscas)
	  ficam na cor do Corte do jogador local (atributo "BestCut" +
	  CutVisuals, a mesma receita do golpe) e mudam quando ele troca;
	- StationFlash: um clarão curto de tempos em tempos (mini-impacto);
	- StationHolo: hologramas de pet (só imagem) flutuam e respiram de leve,
	  mais nítidos com o jogador no terminal — mexe só no StudsOffset;
	- "Efeitos reduzidos" desliga as partículas das estações (StationParticles);
	- StationEngage: ponto de uso sem tela (o núcleo do altar);
	- StationRise: emissor com poucas partículas em repouso e mais com o
	  jogador perto (atributos IdleRate/EngagedRate);
	- StationBurst: rajada local quando o jogador RENASCE de verdade — lido
	  do Stats.Rebirths que o DataController já recebe (nenhuma lógica nova:
	  só reage ao número subir);
	- RENASCER DISPONÍVEL (SetRebirthReady, chamado pelo RebirthController com
	  o mesmo custo do servidor): o altar deste jogador fica um pouco mais
	  ativo — núcleo mais intenso e pulsando mais rápido, mais partículas
	  subindo (nenhuma com Efeitos reduzidos) — e uma etiqueta pequena
	  "♻ RENASCER DISPONÍVEL" acima do pilar. Local: cada jogador vê o próprio.

	Peças achadas pelas tags (CollectionService) que o servidor põe; funciona
	com StreamingEnabled (peça que chega/sai é registrada/esquecida). Só mexe
	no que está a até ACTIVE_DISTANCE da câmera; longe, nada roda. A única
	instância criada aqui é a etiqueta do renascer (BillboardGui + TextLabel,
	uma vez, no PlayerGui).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local CutVisuals = require(Shared:WaitForChild("Formulas"):WaitForChild("CutVisuals"))
local Text = require(Shared:WaitForChild("Localization"))

local DataController = require(script.Parent.DataController)

local ACTIVE_DISTANCE = 140
local CORE_PULSE_SECONDS = 1.8
local CORE_PULSE = 0.14
local ARROW_CYCLE = 1.4 -- segundos para a onda subir as 3 setas
local ARROW_GLOW = 0.45 -- quanto dura o brilho de cada seta
local NPC_LOOK_DISTANCE = 20
local NPC_MAX_TURN = math.rad(50)
local NPC_TURN_RATE = 3
local ENGAGE_DISTANCE = 12
local ENGAGE_RATE = 4 -- quão rápido acorda/adormece (por segundo)
local ENGAGE_SPEED = 0.4 -- giro +40% com o jogador no ponto de uso
local ENGAGE_GLOW = 0.04 -- núcleo um pouco menos transparente (~10% mais intenso)
local ENGAGE_ARROWS = 1.0 -- ciclo das setas vira isto (de ARROW_CYCLE)
local FLASH_EVERY = 4.5 -- segundos entre clarões (mini-impacto)
local FLASH_SECONDS = 0.18
local FLASH_TRANSPARENCY = 0.3
local SETTINGS_EVERY = 1 -- "Efeitos reduzidos" conferido a cada tanto
local HOLO_BOB = 0.18
local HOLO_SECONDS = 2.6
-- Renascer disponível: só o altar deste jogador, discreto.
local REBIRTH_STATION = "Station_Rebirth_Machine"
local READY_RATE = 2.5 -- quão rápido acende/apaga (por segundo)
local READY_GLOW = 0.06 -- núcleo um pouco mais intenso
local READY_PULSE_SECONDS = 1.1 -- pulso mais rápido que o de repouso
local READY_RISE = 0.45 -- partículas subindo: fração do caminho até EngagedRate
local READY_TAG_HEIGHT = 3.6 -- etiqueta: entre o pilar e o cristal
local READY_TAG_DISTANCE = 70

local TAGS = {
	Spin = "StationSpin",
	Ring = "StationRing",
	Pulse = "StationPulse",
	Core = "StationCore",
	Npc = "StationNpc",
	Screen = "StationScreen",
	Particles = "StationParticles",
	CutTint = "StationCutTint",
	Flash = "StationFlash",
	Holo = "StationHolo",
	Engage = "StationEngage",
	Rise = "StationRise",
	Burst = "StationBurst",
}

-- Estado de cada estação (o Model "..._Machine", pela chave = caminho dele):
-- quanto está "acordada" e a fase da onda das setas (acumulada, para mudar
-- de velocidade sem salto).
type Station = { Weight: number, Phase: number }
type Spin = { Part: BasePart, Base: CFrame, Speed: number, Angle: number, Station: string? }
type Ring = { Model: Model, Centre: Vector3, Axis: Vector3, Speed: number, Angle: number, Members: { { Part: BasePart, Offset: CFrame } }, Station: string? }
type Pulse = { Part: BasePart, Order: number, Station: string? }
type Core = { Part: BasePart, Base: number, Station: string?, Rebirth: boolean }
type Npc = { Model: Model, Root: CFrame, Members: { { Part: BasePart, Offset: CFrame } }, Yaw: number }
type Screen = { Part: BasePart, Bars: { Frame }, Arrow: TextLabel?, Station: string? }
type Flash = { Part: BasePart, Base: number, Offset: number }
type Holo = { Part: BasePart, Gui: BillboardGui, Art: ImageLabel?, Phase: number, Station: string? }

local StationFxController = {}

local spins: { [Instance]: Spin } = {}
local rings: { [Instance]: Ring } = {}
local pulses: { [Instance]: Pulse } = {}
local cores: { [Instance]: Core } = {}
local npcs: { [Instance]: Npc } = {}
local screens: { [Instance]: Screen } = {}
local tints: { [Instance]: Instance } = {}
local flashes: { [Instance]: Flash } = {}
local emitters: { [Instance]: ParticleEmitter } = {}
local holos: { [Instance]: Holo } = {}
local anchors: { [Instance]: { Part: BasePart, Station: string? } } = {}
local risers: { [Instance]: { Emitter: ParticleEmitter, Idle: number, Engaged: number, Station: string?, Rebirth: boolean } } = {}
local bursts: { [Instance]: ParticleEmitter } = {}
local lastRebirths: number? = nil
local BURST_COUNT = 40
local reducedNow = false
local nextSettings = 0
local stations: { [string]: Station } = {}
local rebirthReady = false
local readyWeight = 0
local rebirthCore: BasePart? = nil
local readyTag: BillboardGui? = nil
local readyText: TextLabel? = nil

-- A estação (Model "..._Machine") a que uma peça pertence, pela chave.
local function stationOf(item: Instance): string?
	local current = item.Parent
	while current do
		if current:IsA("Model") and string.sub(current.Name, -8) == "_Machine" then
			return current:GetFullName()
		end
		current = current.Parent
	end
	return nil
end

local function isRebirthStation(station: string?): boolean
	return station ~= nil and string.sub(station, -#REBIRTH_STATION) == REBIRTH_STATION
end

local function stateOf(station: string?): Station
	if not station then
		return { Weight = 0, Phase = 0 }
	end
	local state = stations[station]
	if not state then
		state = { Weight = 0, Phase = 0 }
		stations[station] = state
	end
	return state
end
local started = os.clock()
local lastStep: number? = nil

local function members(model: Model, origin: CFrame): { { Part: BasePart, Offset: CFrame } }
	local list = {}
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			table.insert(list, { Part = item, Offset = origin:ToObjectSpace(item.CFrame) })
		end
	end
	return list
end

local function vectorAttribute(item: Instance, name: string, fallback: Vector3): Vector3
	local value = item:GetAttribute(name)
	return if typeof(value) == "Vector3" then value else fallback
end

local function numberAttribute(item: Instance, name: string, fallback: number): number
	local value = item:GetAttribute(name)
	return if type(value) == "number" then value else fallback
end

-- A cor do Corte do jogador local (a mesma receita do golpe).
local function cutColor(): Color3
	local player = Players.LocalPlayer
	local best = if player then player:GetAttribute("BestCut") else nil
	return CutVisuals.ForBest(best).Color
end

local function paint(item: Instance, color: Color3)
	if item:IsA("BasePart") then
		item.Color = color
	elseif item:IsA("ParticleEmitter") then
		item.Color = ColorSequence.new(color)
	end
end

-- Repinta tudo que segue o Corte (chamado quando o jogador troca de Corte).
function StationFxController.RefreshCutTint()
	local color = cutColor()
	for _, item in tints do
		paint(item, color)
	end
end

local function register(tag: string, item: Instance)
	if tag == TAGS.CutTint then
		tints[item] = item
		paint(item, cutColor())
	elseif tag == TAGS.Particles and item:IsA("ParticleEmitter") then
		emitters[item] = item
		item.Enabled = not reducedNow
	elseif tag == TAGS.Engage and item:IsA("BasePart") then
		anchors[item] = { Part = item, Station = stationOf(item) }
	elseif tag == TAGS.Rise and item:IsA("ParticleEmitter") then
		local station = stationOf(item)
		risers[item] = { Emitter = item, Idle = numberAttribute(item, "IdleRate", 1), Engaged = numberAttribute(item, "EngagedRate", 6), Station = station, Rebirth = isRebirthStation(station) }
	elseif tag == TAGS.Burst and item:IsA("ParticleEmitter") then
		bursts[item] = item
	elseif tag == TAGS.Holo and item:IsA("BasePart") then
		local gui = item:FindFirstChildOfClass("BillboardGui")
		if gui then
			local art = gui:FindFirstChildOfClass("ImageLabel")
			holos[item] = { Part = item, Gui = gui, Art = art, Phase = (#item:GetFullName() * 0.53) % HOLO_SECONDS, Station = stationOf(item) }
		end
	elseif tag == TAGS.Flash and item:IsA("BasePart") then
		flashes[item] = { Part = item, Base = item.Transparency, Offset = (#item:GetFullName() * 0.37) % FLASH_EVERY }
	elseif tag == TAGS.Spin and item:IsA("BasePart") then
		spins[item] = { Part = item, Base = item.CFrame, Speed = numberAttribute(item, "SpinSpeed", 20), Angle = 0, Station = stationOf(item) }
	elseif tag == TAGS.Ring and item:IsA("Model") then
		local centre = vectorAttribute(item, "Centre", item:GetPivot().Position)
		rings[item] = {
			Model = item,
			Centre = centre,
			Axis = vectorAttribute(item, "Axis", Vector3.yAxis).Unit,
			Speed = numberAttribute(item, "SpinSpeed", 30),
			Angle = 0,
			Members = members(item, CFrame.new(centre)),
			Station = stationOf(item),
		}
	elseif tag == TAGS.Pulse and item:IsA("BasePart") then
		pulses[item] = { Part = item, Order = numberAttribute(item, "Order", 1), Station = stationOf(item) }
	elseif tag == TAGS.Core and item:IsA("BasePart") then
		local station = stationOf(item)
		cores[item] = { Part = item, Base = item.Transparency, Station = station, Rebirth = isRebirthStation(station) }
		if item.Name == "RebirthCore" and isRebirthStation(station) then
			rebirthCore = item
		end
	elseif tag == TAGS.Screen and item:IsA("BasePart") then
		local gui = item:FindFirstChildOfClass("SurfaceGui")
		local bars = {}
		if gui then
			for index = 1, 3 do
				local bar = gui:FindFirstChild("Bar" .. index)
				if bar and bar:IsA("Frame") then
					table.insert(bars, bar)
				end
			end
		end
		local arrow = if gui then gui:FindFirstChild("Arrow") else nil
		screens[item] = { Part = item, Bars = bars, Arrow = if arrow and arrow:IsA("TextLabel") then arrow else nil, Station = stationOf(item) }
	elseif tag == TAGS.Npc and item:IsA("Model") then
		local root = item.PrimaryPart
		if root then
			local origin = root.CFrame
			npcs[item] = { Model = item, Root = origin, Members = members(item, origin), Yaw = 0 }
		end
	end
end

local function forget(item: Instance)
	spins[item] = nil
	rings[item] = nil
	pulses[item] = nil
	cores[item] = nil
	npcs[item] = nil
	screens[item] = nil
	tints[item] = nil
	flashes[item] = nil
	holos[item] = nil
	anchors[item] = nil
	risers[item] = nil
	bursts[item] = nil
	emitters[item] = nil
	if item == rebirthCore then
		rebirthCore = nil
	end
end

-- "Efeitos reduzidos": partículas das estações desligadas (o movimento fica).
local function applySettings(at: number)
	if at < nextSettings then
		return
	end
	nextSettings = at + SETTINGS_EVERY
	local settings = DataController.Get("Settings")
	local reduced = settings ~= nil and settings.ReducedEffects == true
	if reduced ~= reducedNow then
		reducedNow = reduced
		for _, particles in emitters do
			particles.Enabled = not reduced
		end
	end
end

local function near(position: Vector3, camera: Vector3): boolean
	return (position - camera).Magnitude <= ACTIVE_DISTANCE
end

-- Jogador mais perto do técnico (posição), dentro do alcance de olhar.
local function closestPlayer(position: Vector3): Vector3?
	local best, bestDistance = nil, NPC_LOOK_DISTANCE
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if root and root:IsA("BasePart") then
			local distance = (root.Position - position).Magnitude
			if distance < bestDistance then
				best, bestDistance = root.Position, distance
			end
		end
	end
	return best
end

-- Um quadro (exposto para os testes): `at` em segundos.
function StationFxController.Step(at: number)
	local dt = math.clamp(at - (lastStep or at), 0, 0.1)
	lastStep = at
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local eye = camera.CFrame.Position
	local t = at - started
	applySettings(at)
	readyWeight += ((if rebirthReady then 1 else 0) - readyWeight) * (1 - math.exp(-READY_RATE * dt))
	if readyTag then
		local show = rebirthReady and rebirthCore ~= nil
		if readyTag.Adornee ~= rebirthCore then
			readyTag.Adornee = rebirthCore
		end
		if readyTag.Enabled ~= show then
			readyTag.Enabled = show
		end
		if show and readyText then
			-- Respira com o núcleo; parado com Efeitos reduzidos.
			readyText.TextTransparency = if reducedNow then 0 else 0.2 * (0.5 + 0.5 * math.sin(t * 2 * math.pi / READY_PULSE_SECONDS))
		end
	end
	for _, holo in holos do
		if near(holo.Part.Position, eye) then
			local weight = stateOf(holo.Station).Weight
			local wave = math.sin((t + holo.Phase) * 2 * math.pi / HOLO_SECONDS)
			holo.Gui.StudsOffset = Vector3.new(0, HOLO_BOB * wave, 0)
			if holo.Art then
				holo.Art.ImageTransparency = 0.2 - 0.12 * weight + 0.05 * wave
			end
		end
	end
	for _, flash in flashes do
		if near(flash.Part.Position, eye) then
			local phase = (t + flash.Offset) % FLASH_EVERY
			flash.Part.Transparency = if phase < FLASH_SECONDS then FLASH_TRANSPARENCY else flash.Base
		end
	end

	-- Quanto cada estação está "acordada" (jogador local no ponto de uso).
	local localCharacter = Players.LocalPlayer and Players.LocalPlayer.Character
	local localRoot = if localCharacter then localCharacter:FindFirstChild("HumanoidRootPart") else nil
	local mine = if localRoot and localRoot:IsA("BasePart") then localRoot.Position else nil
	local function engage(part: BasePart, station: string?)
		local state = stateOf(station)
		local engaged = mine ~= nil and (mine - part.Position).Magnitude <= ENGAGE_DISTANCE
		state.Weight += ((if engaged then 1 else 0) - state.Weight) * (1 - math.exp(-ENGAGE_RATE * dt))
	end
	for _, screen in screens do
		engage(screen.Part, screen.Station)
	end
	for _, anchor in anchors do
		engage(anchor.Part, anchor.Station)
	end
	for _, riser in risers do
		local weight = stateOf(riser.Station).Weight
		if riser.Rebirth and not reducedNow then
			weight = math.max(weight, READY_RISE * readyWeight)
		end
		riser.Emitter.Rate = riser.Idle + (riser.Engaged - riser.Idle) * weight
	end
	for _, state in stations do
		local cycle = ARROW_CYCLE + (ENGAGE_ARROWS - ARROW_CYCLE) * state.Weight
		state.Phase += dt / cycle
	end

	for _, spin in spins do
		if near(spin.Base.Position, eye) then
			spin.Angle += spin.Speed * (1 + ENGAGE_SPEED * stateOf(spin.Station).Weight) * dt
			spin.Part.CFrame = spin.Base * CFrame.Angles(0, math.rad(spin.Angle), 0)
		end
	end
	for _, ring in rings do
		if near(ring.Centre, eye) then
			ring.Angle += ring.Speed * (1 + ENGAGE_SPEED * stateOf(ring.Station).Weight) * dt
			local frame = CFrame.new(ring.Centre) * CFrame.fromAxisAngle(ring.Axis, math.rad(ring.Angle))
			for _, member in ring.Members do
				member.Part.CFrame = frame * member.Offset
			end
		end
	end
	for _, core in cores do
		if near(core.Part.Position, eye) then
			local weight = stateOf(core.Station).Weight
			local ready = if core.Rebirth then readyWeight else 0
			local period = CORE_PULSE_SECONDS + (READY_PULSE_SECONDS - CORE_PULSE_SECONDS) * ready
			local pulse = 0.5 + 0.5 * math.sin(t * 2 * math.pi / period)
			core.Part.Transparency = math.max(core.Base + CORE_PULSE * (1 - 0.5 * weight) * pulse - ENGAGE_GLOW * weight - READY_GLOW * ready, 0)
		end
	end
	for _, pulse in pulses do
		if near(pulse.Part.Position, eye) then
			-- Onda subindo: a seta 1 acende, depois a 2, depois a 3.
			local phase = ((stateOf(pulse.Station).Phase - (pulse.Order - 1) / 3.5) % 1) * ARROW_CYCLE
			local glow = math.max(0, 1 - phase / ARROW_GLOW)
			pulse.Part.Transparency = 0.72 - 0.62 * glow
		end
	end
	for _, screen in screens do
		if near(screen.Part.Position, eye) then
			local state = stateOf(screen.Station)
			for index, bar in screen.Bars do
				local base = numberAttribute(bar, "BaseHeight", 0.5)
				local wave = 0.5 + 0.5 * math.sin((state.Phase - index * 0.18) * 2 * math.pi)
				bar.Size = UDim2.fromScale(bar.Size.X.Scale, base * (0.7 + 0.3 * wave) * (1 + 0.15 * state.Weight))
				bar.BackgroundTransparency = 0.3 - 0.25 * state.Weight
			end
			if screen.Arrow then
				screen.Arrow.TextTransparency = 0.25 - 0.25 * state.Weight
			end
		end
	end
	for _, npc in npcs do
		local position = npc.Root.Position
		if near(position, eye) then
			local target = closestPlayer(position)
			local wanted = 0
			if target then
				local localTarget = npc.Root:PointToObjectSpace(target)
				-- Frente do técnico = -Z local.
				wanted = math.clamp(math.atan2(-localTarget.X, -localTarget.Z), -NPC_MAX_TURN, NPC_MAX_TURN)
			end
			npc.Yaw += (wanted - npc.Yaw) * (1 - math.exp(-NPC_TURN_RATE * dt))
			local breathe = 0.05 * math.sin(t * 2 * math.pi / 2.6)
			local frame = npc.Root * CFrame.new(0, breathe, 0) * CFrame.Angles(0, npc.Yaw, 0)
			for _, member in npc.Members do
				member.Part.CFrame = frame * member.Offset
			end
		end
	end
end

-- A etiqueta "♻ RENASCER DISPONÍVEL" (criada uma vez, no PlayerGui).
local function ensureReadyTag()
	if readyTag then
		return
	end
	local player = Players.LocalPlayer
	local playerGui = if player then player:FindFirstChildOfClass("PlayerGui") else nil
	if not playerGui then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "RebirthReadyTag"
	gui.Size = UDim2.new(6, 40, 0.9, 10)
	gui.StudsOffsetWorldSpace = Vector3.new(0, -READY_TAG_HEIGHT, 0)
	gui.MaxDistance = READY_TAG_DISTANCE
	gui.LightInfluence = 0
	gui.Enabled = false
	gui.Adornee = rebirthCore
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne -- a mesma fonte das placas (Theme.FontDisplay)
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(150, 255, 190)
	label.TextStrokeTransparency = 0.35
	label.Text = Text.Get("station.rebirth.available")
	label.Parent = gui
	gui.Parent = playerGui
	readyTag, readyText = gui, label
end

--[[
	Renascer disponível para ESTE jogador? Chamado pelo RebirthController
	quando o estado muda (Power ≥ custo real do próximo renascimento).
]]
function StationFxController.SetRebirthReady(ready: boolean)
	rebirthReady = ready == true
	if rebirthReady then
		ensureReadyTag()
	end
	if readyTag then
		readyTag.Enabled = rebirthReady and rebirthCore ~= nil
		readyTag.Adornee = rebirthCore
	end
end

-- Para os testes: (pedido, intensidade 0..1, etiqueta).
function StationFxController.RebirthReady(): (boolean, number, BillboardGui?)
	return rebirthReady, readyWeight, readyTag
end

-- Rajada local do renascimento (só visual).
function StationFxController.RebirthBurst()
	if reducedNow then
		return
	end
	for _, particles in bursts do
		particles:Emit(BURST_COUNT)
	end
end

-- O número de renascimentos subiu? (Stats vem do servidor, como sempre.)
function StationFxController.OnStats(stats: any)
	local rebirths = if type(stats) == "table" and type(stats.Rebirths) == "number" then stats.Rebirths else nil
	if rebirths == nil then
		return
	end
	if lastRebirths ~= nil and rebirths > lastRebirths then
		StationFxController.RebirthBurst()
	end
	lastRebirths = rebirths
end

-- Para os testes.
function StationFxController.Counts(): { [string]: number }
	local function count(list: { [Instance]: any }): number
		local n = 0
		for _ in list do
			n += 1
		end
		return n
	end
	return {
		Spin = count(spins),
		Ring = count(rings),
		Pulse = count(pulses),
		Core = count(cores),
		Npc = count(npcs),
		Screen = count(screens),
		Tint = count(tints),
		Flash = count(flashes),
		Particles = count(emitters),
		Holo = count(holos),
		Engage = count(anchors),
		Rise = count(risers),
		Burst = count(bursts),
	}
end

-- Para os testes: quanto a estação de `item` está acordada (0..1).
function StationFxController.Engagement(item: Instance): number
	local station = stationOf(item)
	return if station and stations[station] then stations[station].Weight else 0
end

function StationFxController.Init()
	for _, tag in TAGS do
		for _, item in CollectionService:GetTagged(tag) do
			register(tag, item)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(item: Instance)
			register(tag, item)
		end)
		CollectionService:GetInstanceRemovedSignal(tag):Connect(forget)
	end
	local player = Players.LocalPlayer
	if player then
		player:GetAttributeChangedSignal("BestCut"):Connect(StationFxController.RefreshCutTint)
	end
	StationFxController.OnStats(DataController.Get("Stats"))
	DataController.Changed:Connect(function(key: string, value: any)
		if key == "Stats" then
			StationFxController.OnStats(value)
		end
	end)
end

function StationFxController.Start()
	RunService.RenderStepped:Connect(function()
		StationFxController.Step(os.clock())
	end)
end

return StationFxController
