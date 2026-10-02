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
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PetConfig = require(Shared:WaitForChild("Config"):WaitForChild("PetConfig"))
local AssetIds = require(Shared:WaitForChild("Config"):WaitForChild("AssetIds"))

local ATTRIBUTE = "EquippedPets"
local CULL_DISTANCE = 180
local RING_RADIUS = 5
local HEIGHT = 1.5
local BOB_SPEED = 3
local BOB_AMOUNT = 0.35
local PLACEHOLDER_SIZE = 1.6
local ART_SIZE = 3.8 -- studs; a pet reads at about two thirds of a player

local PetFollowController = {}

type Visual = { Parts: { BasePart }, Offsets: { number } }

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
		-- A rarity glow reads better than the ball ever did.
		if rarity then
			local glow = Instance.new("PointLight")
			glow.Color = rarity.Color
			glow.Range = 8
			glow.Brightness = 0.8
			glow.Shadows = false
			glow.Parent = part
		end
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
	local visual: Visual = { Parts = {}, Offsets = {} }
	for index, petId in ids do
		if index > PetConfig.MaxEquipSlots then
			break
		end
		local part = makePetPart(petId)
		part.Parent = folder
		table.insert(visual.Parts, part)
		table.insert(visual.Offsets, (index - 1) / #ids * math.pi * 2)
	end
	visuals[player] = visual
end

local function track(player: Player)
	connections[player] = player:GetAttributeChangedSignal(ATTRIBUTE):Connect(function()
		rebuild(player)
	end)
	rebuild(player)
end

local function onHeartbeat()
	local camera = workspace.CurrentCamera
	local cameraPosition = if camera then camera.CFrame.Position else Vector3.zero
	local now = os.clock()
	local parts: { BasePart } = {}
	local cframes: { CFrame } = {}

	for player, visual in visuals do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and (root.Position - cameraPosition).Magnitude < CULL_DISTANCE then
			local base = root.CFrame
			for i, part in visual.Parts do
				local angle = visual.Offsets[i] + now * 0.4
				local bob = math.sin(now * BOB_SPEED + i) * BOB_AMOUNT
				local offset = Vector3.new(math.cos(angle) * RING_RADIUS, HEIGHT + bob, math.sin(angle) * RING_RADIUS + 2)
				table.insert(parts, part)
				table.insert(cframes, CFrame.new(base:PointToWorldSpace(offset)) * base.Rotation)
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
