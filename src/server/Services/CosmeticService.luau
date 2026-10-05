--!strict
--[[
	CosmeticService
	Builds what other players SEE on a character: the aura ring at the feet, the
	outline for high tiers, and the overhead plate with name, rebirths, current
	zone and the VIP mark.

	Server-built on purpose: everyone sees the same thing, and a client cannot
	fake a tier it did not earn. Everything is cosmetic — no power, no currency.

	Rebuilt when: the character spawns, the player rebirths, VIP is granted, or
	the player changes zone.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local CosmeticConfig = require(Shared.Config.CosmeticConfig)
local AuraConfig = require(Shared.Config.AuraConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local AssetIds = require(Shared.Config.AssetIds)
local Text = require(Shared.Localization)

local DataService = require(script.Parent.DataService)
local RebirthService = require(script.Parent.RebirthService)
local ZoneService = require(script.Parent.ZoneService)

type PlayerData = Types.PlayerData
type AuraTier = CosmeticConfig.AuraTier

local STATUS_NAME = "Status"
local AURA_NAME = "PowerAura"
local BADGE_NAME = "PowerBadge"
local RING_THICKNESS = 0.4

local CosmeticService = {}

--[[
	The ring a player wears. A bought aura (AuraService) wins over the rebirth
	ring: it is what the player chose and paid for. Read from the attribute so
	this service does not depend on AuraService.
]]
local function ringFor(player: Player, tier: AuraTier): AuraTier
	local equipped = player:GetAttribute("EquippedAura")
	local aura = if type(equipped) == "string" then AuraConfig.Auras[equipped] else nil
	if not aura or aura.RingSize <= 0 then
		return tier
	end
	return {
		Id = aura.Id,
		Rebirths = tier.Rebirths,
		DisplayName = aura.DisplayName,
		Color = aura.Color,
		RingSize = aura.RingSize,
		LightRange = aura.LightRange,
		Outline = aura.Outline or tier.Outline,
	}
end

local function tierFor(rebirths: number): AuraTier
	local best = CosmeticConfig.Tiers[1]
	for _, tier in CosmeticConfig.Tiers do
		if rebirths >= tier.Rebirths and tier.Rebirths >= best.Rebirths then
			best = tier
		end
	end
	return best
end

local function clear(character: Model)
	for _, name in { AURA_NAME, BADGE_NAME } do
		local existing = character:FindFirstChild(name, true)
		if existing then
			existing:Destroy()
		end
	end
	local highlight = character:FindFirstChildOfClass("Highlight")
	if highlight then
		highlight:Destroy()
	end
end

--[[
	A aura de poder no personagem. ANTES: anel Neon nos pés + PointLight
	(alcance 10–22) + contorno forte — no jogo real isso estourava o avatar
	(roupa e silhueta sumiam num clarão branco/ciano). AGORA o poder é
	PARTÍCULA, não holofote:
	- pontinhos de energia subindo devagar em volta do corpo (na cor do tier);
	- um anel FINO e quase transparente no chão (ForceField, sem brilho);
	- nenhuma luz constante; contorno (tiers altos) bem suave.
	Tiers maiores ganham partícula mais viva (mais pontos, faíscas), não mais
	luz. Os valores do tier (RingSize etc.) continuam vindo do config.
]]
local function buildAura(character: Model, root: BasePart, tier: AuraTier)
	if tier.RingSize <= 0 then
		return
	end
	local ring = Instance.new("Part")
	ring.Name = AURA_NAME
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.1, tier.RingSize * 0.8, tier.RingSize * 0.8)
	ring.Color = tier.Color
	ring.Material = Enum.Material.ForceField
	ring.Transparency = 0.55
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Massless = true
	ring.CastShadow = false
	ring.CFrame = root.CFrame * CFrame.new(0, -2.9, 0) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = character

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = ring
	weld.Part1 = root
	weld.Parent = ring

	-- Energia: pontos pequenos subindo do chão em volta do corpo e sumindo.
	local level = math.clamp((tier.RingSize - 5) / 5, 0, 1) -- 0 (primeiro tier) .. 1 (último)
	local motes = Instance.new("ParticleEmitter")
	motes.Name = "PowerMotes"
	motes.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	motes.Color = ColorSequence.new(tier.Color, Color3.new(1, 1, 1):Lerp(tier.Color, 0.6))
	motes.Rate = 3 + math.floor(level * 5)
	motes.Lifetime = NumberRange.new(0.9, 1.5)
	motes.Speed = NumberRange.new(1.2, 2.4)
	motes.SpreadAngle = Vector2.new(12, 12)
	motes.EmissionDirection = Enum.NormalId.Right -- o eixo do anel aponta para cima
	motes.Shape = Enum.ParticleEmitterShape.Disc
	motes.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	motes.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.2, 0.18 + level * 0.08),
		NumberSequenceKeypoint.new(1, 0),
	})
	motes.Transparency = NumberSequence.new(0.1, 1)
	motes.LightEmission = 0.35
	motes.LightInfluence = 0.4
	motes.Parent = ring
	if level >= 0.5 then
		-- Tiers altos: algumas faíscas rápidas, não mais brilho.
		local sparks = Instance.new("ParticleEmitter")
		sparks.Name = "PowerSparks"
		sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparks.Color = ColorSequence.new(tier.Color)
		sparks.Rate = 2 + math.floor(level * 2)
		sparks.Lifetime = NumberRange.new(0.25, 0.45)
		sparks.Speed = NumberRange.new(3, 6)
		sparks.SpreadAngle = Vector2.new(40, 40)
		sparks.EmissionDirection = Enum.NormalId.Right
		sparks.Shape = Enum.ParticleEmitterShape.Disc
		sparks.Size = NumberSequence.new(0.14, 0)
		sparks.LightEmission = 0.6
		sparks.Parent = ring
	end

	if tier.Outline then
		local highlight = Instance.new("Highlight")
		highlight.FillTransparency = 1
		highlight.OutlineColor = tier.Color
		highlight.OutlineTransparency = 0.6
		highlight.Parent = character
	end
end

local function buildBadge(player: Player, character: Model, head: BasePart, data: PlayerData, tier: AuraTier)
	local config = CosmeticConfig.Badge
	local gui = Instance.new("BillboardGui")
	gui.Name = BADGE_NAME
	gui.Size = UDim2.fromOffset(240, 58)
	gui.StudsOffset = Vector3.new(0, config.Height, 0)
	gui.MaxDistance = config.MaxDistance
	gui.AlwaysOnTop = false
	gui.Parent = head

	local isVip = player:GetAttribute("VIP") == true
	if isVip and AssetIds.badge_vip then
		local crown = Instance.new("ImageLabel")
		crown.Name = "Vip"
		crown.BackgroundTransparency = 1
		crown.Image = AssetIds.badge_vip
		crown.ScaleType = Enum.ScaleType.Fit
		crown.Size = UDim2.fromOffset(26, 26)
		crown.Position = UDim2.new(0, 0, 0, 0)
		crown.Parent = gui
	end

	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.FredokaOne
	name.TextSize = 22
	name.TextColor3 = if isVip then config.VipColor else Color3.new(1, 1, 1)
	name.TextStrokeTransparency = 0.2
	name.Size = UDim2.new(1, 0, 0, 26)
	name.Text = player.DisplayName
	name.Parent = gui

	local zoneId = ZoneService.GetZone(player)
	local zone = if zoneId then ZoneConfig.Zones[zoneId] else nil
	local status = Instance.new("TextLabel")
	status.Name = STATUS_NAME
	status.BackgroundTransparency = 1
	status.Font = Enum.Font.GothamBold
	status.TextSize = 15
	status.TextColor3 = tier.Color
	status.TextStrokeTransparency = 0.4
	status.Position = UDim2.fromOffset(0, 26)
	status.Size = UDim2.new(1, 0, 0, 20)
	-- One plate is seen by EVERY player around, so it uses the game locale
	-- (nil) instead of the owner. GetFor takes a locale id, never a Player.
	status.Text = Text.GetFor(nil, "cosmetic.status", {
		rebirths = tostring(data.Stats.Rebirths),
		place = if zone then Text.Name("zone", zone) else Text.GetFor(nil, "cosmetic.plaza"),
	})
	status.Parent = gui
end

-- Only the "where am I" line changed: retext it instead of rebuilding.
local function updateStatusLine(player: Player): boolean
	local character = player.Character
	local head = if character then character:FindFirstChild("Head") else nil
	local badge = if head then head:FindFirstChild(BADGE_NAME) else nil
	local status = if badge then badge:FindFirstChild(STATUS_NAME) else nil
	local data = DataService.GetData(player)
	if not (status and status:IsA("TextLabel") and data) then
		return false
	end
	local zoneId = ZoneService.GetZone(player)
	local zone = if zoneId then ZoneConfig.Zones[zoneId] else nil
	status.Text = Text.GetFor(nil, "cosmetic.status", {
		rebirths = tostring(data.Stats.Rebirths),
		place = if zone then Text.Name("zone", zone) else Text.GetFor(nil, "cosmetic.plaza"),
	})
	return true
end

--[[
	(Re)builds every cosmetic on a player's current character.
	Safe to call often: it clears what it made before.
]]
function CosmeticService.Refresh(player: Player)
	local character = player.Character
	local data = DataService.GetData(player)
	if not character or not data then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local head = character:FindFirstChild("Head")
	if not (root and root:IsA("BasePart") and head and head:IsA("BasePart")) then
		return
	end
	clear(character)
	local tier = tierFor(data.Stats.Rebirths)
	player:SetAttribute("AuraTier", tier.Id) -- clients may react (pet colours, UI)
	-- The plate keeps the rebirth colour; the ring shows the equipped aura.
	buildAura(character, root, ringFor(player, tier))
	buildBadge(player, character, head, data, tier)
end

-- Hooks one player: every new character gets its cosmetics rebuilt.
local function track(player: Player)
	player.CharacterAdded:Connect(function()
		-- Appearance finishes loading a moment after the character exists.
		player.CharacterAppearanceLoaded:Wait()
		CosmeticService.Refresh(player)
	end)
	player:GetAttributeChangedSignal("VIP"):Connect(function()
		CosmeticService.Refresh(player)
	end)
	if player.Character then
		task.defer(CosmeticService.Refresh, player)
	end
end

function CosmeticService.Init()
	-- Players who joined before this service started are covered too.
	for _, player in Players:GetPlayers() do
		track(player)
	end
	Players.PlayerAdded:Connect(track)
	RebirthService.Rebirthed:Connect(function(player: Player)
		CosmeticService.Refresh(player)
	end)
end

function CosmeticService.Start()
	for _, player in Players:GetPlayers() do
		CosmeticService.Refresh(player)
	end
	-- The overhead plate shows the current zone, so keep it in step with it.
	task.spawn(function()
		local shown: { [Player]: string } = {}
		while true do
			task.wait(1)
			for _, player in Players:GetPlayers() do
				local zoneId = ZoneService.GetZone(player) or ""
				if shown[player] ~= zoneId then
					shown[player] = zoneId
					if not updateStatusLine(player) then
						CosmeticService.Refresh(player) -- plate missing (respawn)
					end
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		player:SetAttribute("AuraTier", nil)
	end)
end

return CosmeticService
