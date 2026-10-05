--!strict
--[[
	PetFollowController
	Renders equipped pets following EVERY player, client-side only (no server
	physics, no replication cost). Source of truth: the "EquippedPets" player
	attribute written by PetService.

	Looks, in order: a 3D model in ReplicatedStorage.Assets.Pets.<ModelName>
	when one exists; otherwise the pet's uploaded picture on a billboard (it
	always faces the camera, which is what a flat cut-out needs); and only if
	there is no art either, a ball in the rarity colour.
	Performance: one Heartbeat loop, BulkMoveTo, distance culling, pooled
	per-player visuals rebuilt only when the attribute changes.

	FORMAÇÃO (não órbita): o jogador lidera e os pets vêm ATRÁS, em fileiras
	de dois (um pet sozinho na fileira fica no meio), na direção para onde o
	jogador olha. Cada pet persegue a sua vaga com suavização — as fileiras de
	trás com um pouco mais de atraso — e nunca passa por dentro do personagem
	(se o caminho cruza o corpo, é empurrado para fora). Parado: um balanço bem
	sutil. Longe do personagem (teleporte para a praça), o pet reaparece direto
	na vaga. Pets são COMPANHEIROS: ~25% menores que antes (arte 3,8 → 2,8) e
	baixos, abaixo da linha entre a câmera e o tronco do jogador.

	LOD: pets do jogador local e de quem está perto atualizam todo quadro;
	de quem está longe (> NEAR_DISTANCE), um quadro sim, dois não.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PetConfig = require(Shared:WaitForChild("Config"):WaitForChild("PetConfig"))
local AssetIds = require(Shared:WaitForChild("Config"):WaitForChild("AssetIds"))

local ATTRIBUTE = "EquippedPets"
local CULL_DISTANCE = 180
local NEAR_DISTANCE = 60
local FAR_FRAME_SKIP = 3
-- Formação atrás do jogador (studs, no espaço do jogador: +Z é para trás).
local FIRST_ROW = 4
local ROW_GAP = 3
local SIDE = 2.6
local HEIGHT = -1 -- relativo à HumanoidRootPart: baixo, abaixo do tronco
local BOB_SPEED = 2
local BOB_AMOUNT = 0.12
local FOLLOW_SPEED = 9 -- quanto maior, mais rápido chega na vaga
local ROW_SLOWDOWN = 1.5 -- cada fileira para trás segue um pouco mais devagar
local BODY_CLEARANCE = 2.6 -- nunca mais perto que isso do centro do jogador
local SNAP_DISTANCE = 40 -- além disso (teleporte), reaparece direto na vaga
local PLACEHOLDER_SIZE = 1.2
local ART_SIZE = 2.8 -- studs; antes 3.8 (competia com o jogador e a barreira)
local MODEL_SCALE = 0.75 -- modelos 3D: o mesmo -25%

local PetFollowController = {}

type Visual = { Parts: { BasePart }, Current: { CFrame? }, Frame: number }

local folder: Folder
local visuals: { [Player]: Visual } = {}
local connections: { [Player]: RBXScriptConnection } = {}

local function assetsFolder(): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	return assets and assets:FindFirstChild("Pets")
end

local function makePetPart(petId: string): BasePart
	local config = PetConfig.Pets[petId]
	local models = assetsFolder()
	local template = if config and models then models:FindFirstChild(config.ModelName) else nil
	if template and template:IsA("BasePart") then
		local part = template:Clone() :: BasePart
		part.Size *= MODEL_SCALE
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		return part
	end
	local rarity = config and PetConfig.Rarities[config.Rarity]
	local part = Instance.new("Part")
	part.Name = "Pet_" .. petId
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(PLACEHOLDER_SIZE, PLACEHOLDER_SIZE, PLACEHOLDER_SIZE)
	part.Color = if rarity then rarity.Color else Color3.new(1, 1, 1)
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false

	-- With artwork the ball becomes an invisible anchor carrying the picture.
	local artwork = AssetIds["pet_" .. petId]
	if artwork and artwork ~= "" then
		part.Transparency = 1
		local gui = Instance.new("BillboardGui")
		gui.Name = "Art"
		gui.Size = UDim2.fromScale(ART_SIZE, ART_SIZE) -- studs, shrinks with distance
		gui.MaxDistance = CULL_DISTANCE
		gui.Parent = part
		local image = Instance.new("ImageLabel")
		image.BackgroundTransparency = 1
		image.Image = artwork
		image.ScaleType = Enum.ScaleType.Fit
		image.Size = UDim2.fromScale(1, 1)
		image.Parent = gui
		-- Sem luz constante (somava ao clarão em volta do jogador); a raridade
		-- aparece na própria arte e nos painéis.
	end
	return part
end

local function clear(player: Player)
	local visual = visuals[player]
	if visual then
		for _, part in visual.Parts do
			part:Destroy()
		end
	end
	visuals[player] = nil
end

local function rebuild(player: Player)
	clear(player)
	local value = player:GetAttribute(ATTRIBUTE)
	if type(value) ~= "string" or value == "" then
		return
	end
	local ids = string.split(value, ",")
	local visual: Visual = { Parts = {}, Current = {}, Frame = 0 }
	for index, petId in ids do
		if index > PetConfig.MaxEquipSlots then
			break
		end
		local part = makePetPart(petId)
		part.Parent = folder
		table.insert(visual.Parts, part)
	end
	visuals[player] = visual
end

local function track(player: Player)
	connections[player] = player:GetAttributeChangedSignal(ATTRIBUTE):Connect(function()
		rebuild(player)
	end)
	rebuild(player)
end

--[[
	Vaga do pet `index` de `count` na formação, no espaço do jogador
	(x = lado, z = para trás). Fileiras de 2; o último sozinho fica no meio.
]]
function PetFollowController.Slot(index: number, count: number): Vector3
	local row = math.floor((index - 1) / 2)
	local column = (index - 1) % 2
	local alone = index == count and count % 2 == 1
	local x = if alone then 0 else (if column == 0 then -SIDE else SIDE)
	return Vector3.new(x, HEIGHT, FIRST_ROW + row * ROW_GAP)
end

-- Um passo de suavização em direção à vaga, sem atravessar o jogador.
function PetFollowController.StepToward(current: CFrame?, target: CFrame, rootPosition: Vector3, row: number, dt: number): CFrame
	if not current or (current.Position - target.Position).Magnitude > SNAP_DISTANCE then
		return target
	end
	local speed = math.max(FOLLOW_SPEED - row * ROW_SLOWDOWN, 3)
	local alpha = 1 - math.exp(-speed * dt)
	local nextFrame = current:Lerp(target, alpha)
	local flat = Vector3.new(nextFrame.Position.X - rootPosition.X, 0, nextFrame.Position.Z - rootPosition.Z)
	if flat.Magnitude < BODY_CLEARANCE then
		-- O caminho cruzaria o corpo (ex.: o jogador virou 180°): contorna.
		local away = if flat.Magnitude > 0.01 then flat.Unit else (target.Position - rootPosition) * Vector3.new(1, 0, 1)
		if away.Magnitude < 0.01 then
			away = Vector3.new(1, 0, 0)
		end
		local pushed = rootPosition + away.Unit * BODY_CLEARANCE
		nextFrame = CFrame.new(Vector3.new(pushed.X, nextFrame.Position.Y, pushed.Z)) * nextFrame.Rotation
	end
	return nextFrame
end

local lastBeat = os.clock()

local function onHeartbeat()
	local camera = workspace.CurrentCamera
	local cameraPosition = if camera then camera.CFrame.Position else Vector3.zero
	local now = os.clock()
	local dt = math.clamp(now - lastBeat, 0, 0.1)
	lastBeat = now
	local localPlayer = Players.LocalPlayer
	local parts: { BasePart } = {}
	local cframes: { CFrame } = {}

	for player, visual in visuals do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local distance = (root.Position - cameraPosition).Magnitude
			if distance < CULL_DISTANCE then
				visual.Frame += 1
				local far = player ~= localPlayer and distance > NEAR_DISTANCE
				if not far or visual.Frame % FAR_FRAME_SKIP == 0 then
					local step = if far then dt * FAR_FRAME_SKIP else dt
					-- Só o giro horizontal do jogador: a formação não inclina.
					local look = root.CFrame.LookVector
					local yaw = math.atan2(-look.X, -look.Z)
					local base = CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0)
					local count = #visual.Parts
					for index, part in visual.Parts do
						local slot = PetFollowController.Slot(index, count)
						local bob = math.sin(now * BOB_SPEED + index) * BOB_AMOUNT
						local target = base * CFrame.new(slot + Vector3.new(0, bob, 0))
						local row = math.floor((index - 1) / 2)
						local nextFrame = PetFollowController.StepToward(visual.Current[index], target, root.Position, row, step)
						visual.Current[index] = nextFrame
						table.insert(parts, part)
						table.insert(cframes, nextFrame)
					end
				end
			end
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function PetFollowController.Init()
	folder = Instance.new("Folder")
	folder.Name = "PetVisuals"
	folder.Parent = workspace

	for _, player in Players:GetPlayers() do
		track(player)
	end
	Players.PlayerAdded:Connect(track)
	Players.PlayerRemoving:Connect(function(player)
		clear(player)
		local connection = connections[player]
		if connection then
			connection:Disconnect()
		end
		connections[player] = nil
	end)
	RunService.Heartbeat:Connect(onHeartbeat)
end

return PetFollowController
