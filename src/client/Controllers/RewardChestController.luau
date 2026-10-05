--!strict
--[[
	RewardChestController
	O baú de Prêmios da Central (StationMachines.BuildRewardTotem) mostra se
	há prêmio diário para pegar. Não calcula nada: lê o atributo LOCAL
	"RewardReady" que o RewardsController escreve com o MESMO CanClaim que
	acende o badge do menu (o preview do prêmio diário). Sem timer novo, sem
	lógica paralela, sem remote.

	  sem prêmio: brilho interno quase apagado, sem faíscas, sem "!";
	  com prêmio: brilho dourado que respira, poucas faíscas e um "!"
	              pequeno balançando sobre o baú.

	Só a até ACTIVE_DISTANCE da câmera; "Efeitos reduzidos" tira as faíscas.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DataController = require(script.Parent.DataController)

local TAG = "StationReward"
local ACTIVE_DISTANCE = 140
local IDLE_GLOW = 0.75 -- transparência do brilho sem prêmio
local READY_GLOW = 0.2
local BREATH = 0.12
local BREATH_SECONDS = 1.6
local MARK_BOB = 0.25
local SETTINGS_EVERY = 1

type Item = { Instance: Instance, Role: string, Base: CFrame? }

local RewardChestController = {}

local items: { [string]: Item } = {}
local reducedNow = false
local nextSettings = 0

local function register(item: Instance)
	local role = item:GetAttribute("Role")
	if type(role) ~= "string" then
		return
	end
	items[item:GetFullName()] = {
		Instance = item,
		Role = role,
		Base = if item:IsA("BasePart") then item.CFrame else nil,
	}
end

local function forget(item: Instance)
	items[item:GetFullName()] = nil
end

local function ready(): boolean
	local player = Players.LocalPlayer
	return player ~= nil and player:GetAttribute("RewardReady") == true
end

local function positionOf(item: Item): Vector3?
	local instance = item.Instance
	if instance:IsA("BasePart") then
		return instance.CFrame.Position
	end
	local parent = instance.Parent
	while parent and not parent:IsA("BasePart") do
		parent = parent.Parent
	end
	return if parent and parent:IsA("BasePart") then parent.CFrame.Position else nil
end

-- Um quadro (exposto para os testes): `at` em segundos.
function RewardChestController.Step(at: number)
	if at >= nextSettings then
		nextSettings = at + SETTINGS_EVERY
		local settings = DataController.Get("Settings")
		reducedNow = settings ~= nil and settings.ReducedEffects == true
	end
	local camera = Workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else nil
	local on = ready()
	for _, item in items do
		local position = positionOf(item)
		local near = eye ~= nil and position ~= nil and (position - eye).Magnitude <= ACTIVE_DISTANCE
		local instance = item.Instance
		if item.Role == "Sparkle" and instance:IsA("ParticleEmitter") then
			instance.Enabled = on and near and not reducedNow
		elseif item.Role == "Glow" and instance:IsA("BasePart") then
			if on and near then
				instance.Transparency = READY_GLOW + BREATH * (1 + math.sin(at * 2 * math.pi / BREATH_SECONDS)) / 2
			else
				instance.Transparency = IDLE_GLOW
			end
		elseif item.Role == "Mark" and instance:IsA("BasePart") then
			instance.Transparency = if on then 0 else 1
			if item.Base then
				instance.CFrame = if on and near then item.Base + Vector3.new(0, MARK_BOB * math.sin(at * 2.4), 0) else item.Base
			end
		end
	end
end

function RewardChestController.Count(): number
	local count = 0
	for _ in items do
		count += 1
	end
	return count
end

function RewardChestController.Init()
	for _, item in CollectionService:GetTagged(TAG) do
		register(item)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(register)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(forget)
end

function RewardChestController.Start()
	RunService.RenderStepped:Connect(function()
		RewardChestController.Step(os.clock())
	end)
end

return RewardChestController
