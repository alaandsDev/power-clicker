--!strict
--[[
	TrainingFieldController
	O lado VISUAL do Campo de Treinamento (StationMachines.BuildTrainingField).
	Não decide nada: quem pode treinar é o servidor (TrainingService, por
	Renascimentos). Aqui só:

	- CADEADO por jogador: com os Renascimentos do jogador local (Stats),
	  cada alvo mostra "🔒 REQUER ♻ X RENASCIMENTOS" e o cadeado, com a
	  energia apagada; liberado, o cadeado some, a placa mostra
	  "♻ X RENASCIMENTOS" e a energia acende.
	- REAÇÃO ao treino: enquanto QUALQUER jogador treina num alvo (atributo
	  "Training" do jogador, escrito pelo servidor e replicado), o boneco
	  reage em golpes curtos:
	    I   balança (Sway)
	    II  as placas vibram + faíscas pequenas (Vibrate)
	    III a energia responde (Energy)
	    IV  o núcleo pulsa (Pulse)
	  Sem HP, sem loot, sem IA, sem ataque: só movimento local.

	Custo: um RenderStepped; só alvos a até ACTIVE_DISTANCE da câmera; parado
	quando ninguém treina. "Efeitos reduzidos" tira as faíscas.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DataController = require(script.Parent.DataController)

local TAG = "TrainingStation"
local ENERGY_TAG = "TrainingEnergy"
local ACTIVE_DISTANCE = 140
local HIT_PERIOD = 0.7 -- segundos entre "golpes" enquanto alguém treina
local LOCKED_TRANSPARENCY = 0.85 -- energia apagada no alvo bloqueado
local SETTINGS_EVERY = 1
local SPARKS_PER_HIT = 4
local UNLOCKED_COLOR = Color3.fromRGB(150, 236, 150)
local LOCKED_COLOR = Color3.fromRGB(255, 200, 110)

type Moving = { Part: BasePart, Base: CFrame, Size: Vector3, Plate: boolean, Order: number }
type Glow = { Part: BasePart, Base: number, InDummy: boolean }
type Entry = {
	Model: Model,
	Id: string,
	Required: number,
	Reaction: string,
	Centre: Vector3,
	Pivot: Vector3,
	Axis: Vector3, -- eixo do balanço (direita do boneco)
	Moving: { Moving },
	Energy: { Glow },
	Lock: { Glow },
	Label: TextLabel?,
	Board: BasePart?,
	Sparks: { ParticleEmitter },
	Core: Moving?,
	Unlocked: boolean,
	Moved: boolean,
	LastHit: number,
}

local TrainingFieldController = {}

local entries: { [string]: Entry } = {}
local rebirths = 0
local reducedNow = false
local nextSettings = 0

local function key(item: Instance): string
	return item:GetFullName()
end

local function apply(entry: Entry)
	local unlocked = rebirths >= entry.Required
	entry.Unlocked = unlocked
	for _, glow in entry.Lock do
		glow.Part.Transparency = if unlocked then 1 else glow.Base
	end
	for _, glow in entry.Energy do
		glow.Part.Transparency = if unlocked then glow.Base else math.max(glow.Base, LOCKED_TRANSPARENCY)
	end
	local board, label = entry.Board, entry.Label
	if board and label and entry.Required > 0 then
		local text = board:GetAttribute(if unlocked then "UnlockedText" else "LockedText")
		if type(text) == "string" then
			label.Text = text
		end
		label.TextColor3 = if unlocked then UNLOCKED_COLOR else LOCKED_COLOR
	end
end

local function register(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local id = model:GetAttribute("Station")
	local centre = model:GetAttribute("Centre")
	local front = model:GetAttribute("Front")
	local dummy = model:FindFirstChild("Dummy")
	if type(id) ~= "string" or typeof(centre) ~= "Vector3" or not dummy then
		return
	end
	local pivot = dummy:GetAttribute("Pivot")
	local look = if typeof(front) == "Vector3" then front else Vector3.new(0, 0, -1)
	local entry: Entry = {
		Model = model,
		Id = id,
		Required = tonumber(model:GetAttribute("RequiredRebirths")) or 0,
		Reaction = tostring(model:GetAttribute("Reaction") or "Sway"),
		Centre = centre,
		Pivot = if typeof(pivot) == "Vector3" then pivot else centre,
		Axis = look:Cross(Vector3.new(0, 1, 0)).Unit,
		Moving = {},
		Energy = {},
		Lock = {},
		Label = nil,
		Board = nil,
		Sparks = {},
		Core = nil,
		Unlocked = false,
		Moved = false,
		LastHit = -1,
	}
	for _, item in dummy:GetDescendants() do
		if item:IsA("BasePart") then
			local moving: Moving = {
				Part = item,
				Base = item.CFrame,
				Size = item.Size,
				Plate = item.Name == "ArmorPlate",
				Order = tonumber(item:GetAttribute("Order")) or 0,
			}
			table.insert(entry.Moving, moving)
			if item.Name == "GuardianCore" then
				entry.Core = moving
			end
		elseif item:IsA("ParticleEmitter") then
			table.insert(entry.Sparks, item)
		end
	end
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") and item:HasTag(ENERGY_TAG) then
			local base = tonumber(item:GetAttribute("BaseTransparency")) or item.Transparency
			table.insert(entry.Energy, { Part = item, Base = base, InDummy = item:IsDescendantOf(dummy) })
		end
	end
	local lock = model:FindFirstChild("Padlock")
	if lock then
		for _, item in lock:GetDescendants() do
			if item:IsA("BasePart") then
				table.insert(entry.Lock, { Part = item, Base = item.Transparency, InDummy = false })
			end
		end
	end
	local board = model:FindFirstChild("TrainingPlaque_" .. id, true)
	if board and board:IsA("BasePart") then
		entry.Board = board
		local gui = board:FindFirstChild("Text")
		local label = gui and gui:FindFirstChild("Requirement")
		if label and label:IsA("TextLabel") then
			entry.Label = label
		end
	end
	entries[key(model)] = entry
	apply(entry)
end

local function forget(model: Instance)
	entries[key(model)] = nil
end

local function restore(entry: Entry)
	for _, moving in entry.Moving do
		moving.Part.CFrame = moving.Base
		moving.Part.Size = moving.Size
	end
	for _, glow in entry.Energy do
		glow.Part.Transparency = if entry.Unlocked then glow.Base else math.max(glow.Base, LOCKED_TRANSPARENCY)
	end
	entry.Moved = false
end

local function lean(entry: Entry, angle: number)
	local pivot = CFrame.new(entry.Pivot)
	local turn = pivot * CFrame.fromAxisAngle(entry.Axis, angle) * pivot:Inverse()
	for _, moving in entry.Moving do
		moving.Part.CFrame = turn * moving.Base
	end
end

-- Um golpe: `phase` 0..1 dentro do golpe, `impulse` 1 → 0.
local function react(entry: Entry, phase: number, at: number)
	local impulse = math.exp(-phase * 5)
	local reaction = entry.Reaction
	if reaction == "Sway" then
		-- Recua com o golpe e volta balançando.
		lean(entry, math.rad(11) * math.sin(phase * math.pi * 2) * (1 - phase))
	elseif reaction == "Vibrate" then
		lean(entry, math.rad(2.5) * math.sin(phase * math.pi * 2) * (1 - phase))
		for _, moving in entry.Moving do
			if moving.Plate then
				local jitter = 0.08 * impulse * math.sin(at * 80 + moving.Order * 2.1)
				moving.Part.CFrame = moving.Part.CFrame * CFrame.new(jitter, jitter * 0.4, 0)
			end
		end
	elseif reaction == "Energy" then
		lean(entry, math.rad(3) * math.sin(phase * math.pi * 2) * (1 - phase))
		for _, glow in entry.Energy do
			if glow.InDummy then
				local base = if entry.Unlocked then glow.Base else math.max(glow.Base, LOCKED_TRANSPARENCY)
				glow.Part.Transparency = base * (1 - 0.9 * impulse)
			end
		end
	else
		local core = entry.Core
		if core then
			core.Part.Size = core.Size * (1 + 0.3 * impulse)
		end
		for _, glow in entry.Energy do
			local base = if entry.Unlocked then glow.Base else math.max(glow.Base, LOCKED_TRANSPARENCY)
			glow.Part.Transparency = base * (1 - 0.8 * impulse)
		end
	end
	entry.Moved = true
end

local function applySettings(at: number)
	if at < nextSettings then
		return
	end
	nextSettings = at + SETTINGS_EVERY
	local settings = DataController.Get("Settings")
	reducedNow = settings ~= nil and settings.ReducedEffects == true
end

-- Quem está treinando onde (atributo do servidor, replicado para todos).
local function training(): { [string]: boolean }
	local active = {}
	for _, player in Players:GetPlayers() do
		local station = player:GetAttribute("Training")
		if type(station) == "string" then
			active[station] = true
		end
	end
	return active
end

-- Um quadro (exposto para os testes): `at` em segundos.
function TrainingFieldController.Step(at: number)
	applySettings(at)
	local camera = Workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else nil
	local active = training()
	for _, entry in entries do
		local near = eye ~= nil and (entry.Centre - eye).Magnitude <= ACTIVE_DISTANCE
		if not near or not active[entry.Id] then
			if entry.Moved then
				restore(entry)
			end
			entry.LastHit = -1
			continue
		end
		local hit = math.floor(at / HIT_PERIOD)
		local phase = (at / HIT_PERIOD) - hit
		if hit ~= entry.LastHit then
			entry.LastHit = hit
			if not reducedNow then
				for _, sparks in entry.Sparks do
					sparks:Emit(SPARKS_PER_HIT)
				end
			end
		end
		react(entry, phase, at)
	end
end

function TrainingFieldController.OnStats(stats: any)
	local value = if type(stats) == "table" then tonumber(stats.Rebirths) else nil
	rebirths = value or 0
	for _, entry in entries do
		apply(entry)
	end
end

-- Para os testes.
function TrainingFieldController.Entry(id: string): Entry?
	for _, entry in entries do
		if entry.Id == id then
			return entry
		end
	end
	return nil
end

function TrainingFieldController.Count(): number
	local count = 0
	for _ in entries do
		count += 1
	end
	return count
end

function TrainingFieldController.Init()
	for _, item in CollectionService:GetTagged(TAG) do
		register(item)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(register)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(forget)
	TrainingFieldController.OnStats(DataController.Get("Stats"))
	DataController.Changed:Connect(function(name: string, value: any)
		if name == "Stats" then
			TrainingFieldController.OnStats(value)
		end
	end)
end

function TrainingFieldController.Start()
	RunService.RenderStepped:Connect(function()
		TrainingFieldController.Step(os.clock())
	end)
end

return TrainingFieldController
