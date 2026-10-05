--!strict
--[[
	StationFxController
	O MOVIMENTO das estações-máquina do lobby (protótipo: só Melhorias, ver
	server/World/StationMachines). Tudo local e só visual:

	- núcleo de poder gira devagar e pulsa (Transparency), a casca gira ao
	  contrário;
	- os dois anéis giram em volta do núcleo;
	- as setas de energia nas colunas acendem de baixo para cima (↑↑↑), em
	  onda — "upgrade" sem precisar ler;
	- o técnico respira e vira um pouco para o jogador que chega perto.

	Peças achadas pelas tags (CollectionService) que o servidor põe; funciona
	com StreamingEnabled (peça que chega/sai é registrada/esquecida). Só mexe
	no que está a até ACTIVE_DISTANCE da câmera; longe, nada roda. Nunca cria
	nem destrói instância.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ACTIVE_DISTANCE = 140
local CORE_PULSE_SECONDS = 1.8
local CORE_PULSE = 0.14
local ARROW_CYCLE = 1.4 -- segundos para a onda subir as 3 setas
local ARROW_GLOW = 0.45 -- quanto dura o brilho de cada seta
local NPC_LOOK_DISTANCE = 20
local NPC_MAX_TURN = math.rad(50)
local NPC_TURN_RATE = 3

local TAGS = {
	Spin = "StationSpin",
	Ring = "StationRing",
	Pulse = "StationPulse",
	Core = "StationCore",
	Npc = "StationNpc",
}

type Spin = { Part: BasePart, Base: CFrame, Speed: number }
type Ring = { Model: Model, Centre: Vector3, Axis: Vector3, Speed: number, Members: { { Part: BasePart, Offset: CFrame } } }
type Pulse = { Part: BasePart, Order: number }
type Core = { Part: BasePart, Base: number }
type Npc = { Model: Model, Root: CFrame, Members: { { Part: BasePart, Offset: CFrame } }, Yaw: number }

local StationFxController = {}

local spins: { [Instance]: Spin } = {}
local rings: { [Instance]: Ring } = {}
local pulses: { [Instance]: Pulse } = {}
local cores: { [Instance]: Core } = {}
local npcs: { [Instance]: Npc } = {}
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

local function register(tag: string, item: Instance)
	if tag == TAGS.Spin and item:IsA("BasePart") then
		spins[item] = { Part = item, Base = item.CFrame, Speed = numberAttribute(item, "SpinSpeed", 20) }
	elseif tag == TAGS.Ring and item:IsA("Model") then
		local centre = vectorAttribute(item, "Centre", item:GetPivot().Position)
		rings[item] = {
			Model = item,
			Centre = centre,
			Axis = vectorAttribute(item, "Axis", Vector3.yAxis).Unit,
			Speed = numberAttribute(item, "SpinSpeed", 30),
			Members = members(item, CFrame.new(centre)),
		}
	elseif tag == TAGS.Pulse and item:IsA("BasePart") then
		pulses[item] = { Part = item, Order = numberAttribute(item, "Order", 1) }
	elseif tag == TAGS.Core and item:IsA("BasePart") then
		cores[item] = { Part = item, Base = item.Transparency }
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

	for _, spin in spins do
		if near(spin.Base.Position, eye) then
			spin.Part.CFrame = spin.Base * CFrame.Angles(0, math.rad(spin.Speed * t), 0)
		end
	end
	for _, ring in rings do
		if near(ring.Centre, eye) then
			local frame = CFrame.new(ring.Centre) * CFrame.fromAxisAngle(ring.Axis, math.rad(ring.Speed * t))
			for _, member in ring.Members do
				member.Part.CFrame = frame * member.Offset
			end
		end
	end
	for _, core in cores do
		if near(core.Part.Position, eye) then
			core.Part.Transparency = core.Base + CORE_PULSE * (0.5 + 0.5 * math.sin(t * 2 * math.pi / CORE_PULSE_SECONDS))
		end
	end
	for _, pulse in pulses do
		if near(pulse.Part.Position, eye) then
			-- Onda subindo: a seta 1 acende, depois a 2, depois a 3.
			local phase = (t - (pulse.Order - 1) * (ARROW_CYCLE / 3.5)) % ARROW_CYCLE
			local glow = math.max(0, 1 - phase / ARROW_GLOW)
			pulse.Part.Transparency = 0.72 - 0.62 * glow
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

-- Para os testes.
function StationFxController.Counts(): { [string]: number }
	local function count(list: { [Instance]: any }): number
		local n = 0
		for _ in list do
			n += 1
		end
		return n
	end
	return { Spin = count(spins), Ring = count(rings), Pulse = count(pulses), Core = count(cores), Npc = count(npcs) }
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
end

function StationFxController.Start()
	RunService.RenderStepped:Connect(function()
		StationFxController.Step(os.clock())
	end)
end

return StationFxController
