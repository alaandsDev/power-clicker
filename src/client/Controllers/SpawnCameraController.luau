--!strict
--[[
	SpawnCameraController
	Enquadra a câmera ao nascer: atrás do personagem, olhando para onde o
	marcador de spawn aponta (no mundo inicial, a avenida e o portão do
	Caminho do Poder).

	Por que existe: o servidor (WorldService) teleporta o personagem para o
	marcador com PivotTo logo depois de ele nascer. No Roblox a câmera padrão
	NÃO acompanha essa rotação — ela fica no ângulo em que estava —, então o
	jogador nascia olhando para outro lado mesmo com o marcador certo.

	Só mexe na câmera UMA vez por personagem (ao nascer e a cada respawn),
	depois que o teleporte chegou; a partir daí o jogador controla a câmera
	normalmente. Nada aqui afeta posição, dados ou jogo.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local WorldConfig = require(Shared:WaitForChild("Config"):WaitForChild("WorldConfig"))

local DataController = require(script.Parent.DataController)

local SpawnCameraController = {}

-- Distância e altura da câmera atrás do personagem (perto do padrão do Roblox).
local BACK = 14
local UP = 6
-- Quanto tempo esperar o teleporte do servidor antes de desistir.
local WAIT_SECONDS = 6
-- O personagem "chegou" ao marcador quando está a esta distância dele.
local ARRIVED = 8

local function currentMarker(): BasePart?
	local worlds = DataController.Get("Worlds")
	local worldId = if type(worlds) == "table" then worlds.Current else nil
	local world = WorldConfig.Worlds[worldId or WorldConfig.DefaultWorld] or WorldConfig.Worlds[WorldConfig.DefaultWorld]
	local map = Workspace:FindFirstChild("Map")
	local spawns = if map then map:FindFirstChild("Spawns") else nil
	local marker = if spawns and world then spawns:FindFirstChild(world.SpawnName) else nil
	return if marker and marker:IsA("BasePart") then marker else nil
end

local function frame(root: BasePart, direction: Vector3)
	local camera = Workspace.CurrentCamera
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if not camera or flat.Magnitude < 1e-3 then
		return
	end
	flat = flat.Unit
	-- Câmera atrás e acima do personagem, olhando na HORIZONTAL: assim o
	-- portão inteiro (com a espada no alto) e a barreira 1 cabem no quadro.
	local eye = root.Position + Vector3.new(0, 2 + UP, 0) - flat * BACK
	camera.CFrame = CFrame.lookAt(eye, eye + flat)
end

local function onCharacter(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root or not root:IsA("BasePart") then
		return
	end
	local deadline = os.clock() + WAIT_SECONDS
	local marker: BasePart? = nil
	-- Espera o teleporte do servidor chegar (dados carregados + PivotTo).
	while os.clock() < deadline and character.Parent do
		local candidate = currentMarker()
		if candidate and (candidate.Position - root.Position).Magnitude <= ARRIVED then
			marker = candidate
			break
		end
		task.wait(0.1)
	end
	if not character.Parent then
		return
	end
	-- Um quadro depois, para a câmera padrão já ter assumido o personagem.
	RunService.RenderStepped:Wait()
	frame(root, if marker then marker.CFrame.LookVector else root.CFrame.LookVector)
end

function SpawnCameraController.Init()
	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(function(character)
		task.spawn(onCharacter, character)
	end)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

return SpawnCameraController
