--!strict
--[[
	PowerPathAmbientController
	O VFX ambiental do Caminho do Poder (Fase B: a cintilação das formações de
	gelo do estágio 3). O servidor cria os emissores DESLIGADOS com a tag
	PowerPathAmbient (PowerPathDecor); aqui cada um só liga se:

	  · a câmera está a até CorridorThemes.Rules.AmbientDistance dele;
	  · "Efeitos reduzidos" está desligado.

	Sem loop por quadro: confere a cada CHECK_EVERY segundos (task.wait), e
	só escreve Enabled quando muda. O cenário estático não tem script.
]]

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local CorridorThemes = require(Shared:WaitForChild("Config"):WaitForChild("CorridorThemes"))

local DataController = require(script.Parent.DataController)

local TAG = "PowerPathAmbient"
local CHECK_EVERY = 0.5

local PowerPathAmbientController = {}

-- Lista (poucos itens: 2 na Fase B); nomes repetidos não colidem.
local emitters: { ParticleEmitter } = {}

local function register(item: Instance)
	if item:IsA("ParticleEmitter") then
		item.Enabled = false
		if not table.find(emitters, item) then
			table.insert(emitters, item)
		end
	end
end

local function forget(item: Instance)
	local index = table.find(emitters, item :: any)
	if index then
		table.remove(emitters, index)
	end
end

local function reduced(): boolean
	local settings = DataController.Get("Settings")
	return settings ~= nil and settings.ReducedEffects == true
end

-- Uma conferência (exposta para os testes). Devolve quantos ficaram ligados.
function PowerPathAmbientController.Step(): number
	local camera = Workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else nil
	local allowed = eye ~= nil and not reduced()
	local range = CorridorThemes.Rules.AmbientDistance
	local on = 0
	for _, emitter in emitters do
		local owner = emitter.Parent
		local near = allowed and owner ~= nil and owner:IsA("BasePart") and (owner.CFrame.Position - (eye :: Vector3)).Magnitude <= range
		if emitter.Enabled ~= near then
			emitter.Enabled = near
		end
		on += if near then 1 else 0
	end
	return on
end

function PowerPathAmbientController.Count(): number
	return #emitters
end

function PowerPathAmbientController.Init()
	for _, item in CollectionService:GetTagged(TAG) do
		register(item)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(register)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(forget)
end

function PowerPathAmbientController.Start()
	task.spawn(function()
		while true do
			PowerPathAmbientController.Step()
			task.wait(CHECK_EVERY)
		end
	end)
end

return PowerPathAmbientController
