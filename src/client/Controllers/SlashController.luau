--!strict
--[[
	SlashController
	The arc that flashes in front of the character on every click, in the colour
	of the cut the player bought (CutService welds the blade and mirrors the cut
	id on the "BestCut" attribute).

	Purely local: the slash is drawn on this client only, so a 9-clicks-a-second
	hold costs the network nothing. The blade, its trail and its glow are the
	server-built part everyone else sees.

	The arcs are pooled — creating and destroying parts at click speed is what
	makes a clicker stutter on a weak phone.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local SwordConfig = require(Shared:WaitForChild("Config"):WaitForChild("SwordConfig"))

local DataController = require(script.Parent.DataController)

local POOL_SIZE = 4
-- A thin, wide streak. A cylinder read as a round blob from the front, which
-- is not what a slash looks like.
local ARC_SIZE = Vector3.new(0.25, 6.5, 1.1)
local ARC_DISTANCE = 3.4 -- studs in front of the character
local ARC_SECONDS = 0.16
local MIN_INTERVAL = 0.05 -- never more than ~20 arcs a second

local SlashController = {}

local pool: { BasePart } = {}
local poolIndex = 0
local lastAt = 0
local folder: Folder

-- A skin equipada decide a cor e o tamanho do arco (SwordService escreve o
-- atributo). Cosmético: não há número de dano nenhum aqui.
local function equippedSword(): SwordConfig.SwordData
	local swordId = Players.LocalPlayer:GetAttribute("EquippedSword")
	local sword = if type(swordId) == "string" then SwordConfig.Swords[swordId] else nil
	return sword or SwordConfig.Swords[SwordConfig.DefaultSword]
end

local function createArc(): BasePart
	local part = Instance.new("Part")
	part.Name = "Slash"
	part.Size = ARC_SIZE
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Parent = folder
	return part
end

--[[
	Flashes one arc in front of the local character. Safe to call on every
	click: it rate-limits itself and reuses the pooled parts, and it does
	nothing at all when reduced effects are on.
]]
function SlashController.Play()
	local settings = DataController.Get("Settings")
	if settings and settings.ReducedEffects == true then
		return
	end
	local now = os.clock()
	if now - lastAt < MIN_INTERVAL then
		return
	end
	lastAt = now

	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		return
	end

	poolIndex = (poolIndex % POOL_SIZE) + 1
	local arc = pool[poolIndex]
	local sword = equippedSword()
	arc.Color = sword.ArcColor
	-- Diagonal in front of the chest, tilted a different way each time so a
	-- held click never looks like the same frame stamped over and over.
	arc.CFrame = root.CFrame
		* CFrame.new(math.random(-12, 12) / 10, 0.4, -ARC_DISTANCE)
		* CFrame.Angles(0, 0, math.rad(math.random(25, 65) * (if math.random() < 0.5 then 1 else -1)))
	arc.Transparency = 0.25
	arc.Size = ARC_SIZE * sword.ArcScale

	TweenService:Create(arc, TweenInfo.new(ARC_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Size = Vector3.new(
			ARC_SIZE.X * sword.ArcScale,
			ARC_SIZE.Y * sword.ArcScale * 1.5,
			ARC_SIZE.Z * sword.ArcScale * 0.4
		),
	}):Play()
end

function SlashController.Init()
	folder = Instance.new("Folder")
	folder.Name = "SlashEffects"
	folder.Parent = Workspace.CurrentCamera or Workspace
	for index = 1, POOL_SIZE do
		pool[index] = createArc()
	end
end

return SlashController
