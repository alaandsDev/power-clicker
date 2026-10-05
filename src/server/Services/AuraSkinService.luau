--!strict
--[[
	AuraSkinService
	As auras cosméticas no personagem: partículas e anel fino. Raridade é
	efeito mais INTERESSANTE (segunda camada de faíscas nas raras), não mais
	luz: nenhuma PointLight constante (ela estourava o avatar no jogo real; o
	LightRange do config fica sem uso de propósito).

	Cosmético de verdade: este serviço não registra nenhum provedor no
	PowerService, então é impossível uma aura daqui mexer na economia por
	acidente.

	Desbloqueio é por progressão (estágio da torre, renascimentos, vitórias) e o
	servidor concede sozinho — o cliente só pede para equipar o que já é dele.

	Teto de efeito: um emissor por jogador, taxa e tamanho cortados pelos
	limites do AuraSkinConfig. Numa praça cheia isso é a diferença entre rodar
	e não rodar no celular.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Guard = require(Shared.Utils.Guard)
local Logger = require(Shared.Utils.Logger)
local Signal = require(Shared.Utils.Signal)
local AuraSkinConfig = require(Shared.Config.AuraSkinConfig)
local AuraSkinLogic = require(Shared.Formulas.AuraSkinLogic)

local NetService = require(script.Parent.NetService)
local DataService = require(script.Parent.DataService)

type PlayerData = Types.PlayerData
type RemoteResponse = Types.RemoteResponse

local HOLDER_NAME = "AuraSkin"
local ATTRIBUTE = "EquippedAuraSkin"
local LIMB_TIMEOUT = 5

local log = Logger.new("AuraSkins")

local AuraSkinService = {
	-- (player, skinId)
	Unlocked = Signal.new() :: Signal.Signal<Player, string>,
}

local function progressOf(data: PlayerData)
	return {
		Rebirths = data.Stats.Rebirths,
		Wins = data.Currencies.Wins,
		Cleared = data.Tower.Cleared,
	}
end

--[[
	(Re)constrói a aura no personagem. O suporte é uma peça invisível presa ao
	tronco: assim o emissor, o anel e a luz nascem e morrem juntos, e limpar é
	destruir uma coisa só.
]]
local function buildAura(player: Player, skin: AuraSkinConfig.AuraSkinData)
	local character = player.Character
	if not character then
		return
	end
	local found: Instance? = character:FindFirstChild("HumanoidRootPart")
		or character:WaitForChild("HumanoidRootPart", LIMB_TIMEOUT)
	local root = if found and found:IsA("BasePart") then found else nil
	if not root then
		return
	end
	local existing = character:FindFirstChild(HOLDER_NAME)
	if existing then
		existing:Destroy()
	end

	local rate = AuraSkinLogic.SafeRate(skin)
	if rate <= 0 and not skin.Ring and skin.LightRange <= 0 then
		return -- "Nenhuma": não há o que construir
	end

	local holder = Instance.new("Part")
	holder.Name = HOLDER_NAME
	holder.Size = Vector3.new(1, 1, 1)
	holder.Transparency = 1
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Massless = true
	holder.CastShadow = false
	holder.CFrame = root.CFrame * CFrame.new(0, AuraSkinConfig.EmitterHeight, 0)
	holder.Parent = character

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = holder
	weld.Part1 = root
	weld.Parent = holder

	if rate > 0 then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "Aura"
		emitter.Color = ColorSequence.new(skin.Color, skin.SecondaryColor)
		emitter.Rate = rate
		emitter.Lifetime = NumberRange.new(skin.Lifetime * 0.7, skin.Lifetime)
		emitter.Speed = NumberRange.new(skin.Speed * 0.6, skin.Speed)
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, AuraSkinLogic.SafeSize(skin)),
			NumberSequenceKeypoint.new(1, 0),
		})
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.LightEmission = 0.25
		emitter.LightInfluence = 0.4
		emitter.SpreadAngle = Vector2.new(35, 35)
		emitter.Parent = holder
	end

	if skin.Ring then
		local ring = Instance.new("Part")
		ring.Name = "Ring"
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(0.3, AuraSkinConfig.RingSize, AuraSkinConfig.RingSize)
		ring.Color = skin.Color
		ring.Material = Enum.Material.ForceField
		ring.Transparency = 0.55
		ring.CanCollide = false
		ring.CanQuery = false
		ring.CanTouch = false
		ring.Massless = true
		ring.CastShadow = false
		ring.CFrame = holder.CFrame * CFrame.new(0, -1.2, 0) * CFrame.Angles(0, 0, math.rad(90))
		ring.Parent = holder
		local ringWeld = Instance.new("WeldConstraint")
		ringWeld.Part0 = ring
		ringWeld.Part1 = holder
		ringWeld.Parent = ring
	end

	-- As auras que antes ganhavam luz (as mais raras) ganham uma segunda
	-- camada: faíscas finas na cor secundária, subindo rápido.
	if skin.LightRange > 0 then
		local twinkle = Instance.new("ParticleEmitter")
		twinkle.Name = "AuraTwinkle"
		twinkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		twinkle.Color = ColorSequence.new(skin.SecondaryColor, skin.Color)
		twinkle.Rate = 4
		twinkle.Lifetime = NumberRange.new(0.5, 0.9)
		twinkle.Speed = NumberRange.new(2, 4)
		twinkle.SpreadAngle = Vector2.new(25, 25)
		twinkle.Size = NumberSequence.new(0.16, 0)
		twinkle.LightEmission = 0.6
		twinkle.Parent = holder
	end
end

local function publish(player: Player, data: PlayerData)
	local skin = AuraSkinLogic.Equipped(data.AuraSkins)
	player:SetAttribute(ATTRIBUTE, skin.Id)
	task.spawn(buildAura, player, skin)
end

-- Concede toda aura cuja condição de progressão já está cumprida.
function AuraSkinService.RefreshUnlocks(player: Player)
	local data = DataService.GetData(player)
	if not data then
		return
	end
	local progress = progressOf(data)
	local granted = 0
	for _, skin in AuraSkinConfig.Skins do
		if not AuraSkinLogic.Owns(data.AuraSkins, skin.Id) and AuraSkinLogic.IsUnlocked(skin, progress) then
			data.AuraSkins.Owned[skin.Id] = true
			granted += 1
			NetService.FireClient("Notify", player, "AuraSkinUnlocked", { SkinId = skin.Id })
			AuraSkinService.Unlocked:Fire(player, skin.Id)
			log:Info(string.format("user=%d unlocked aura skin %s", player.UserId, skin.Id))
		end
	end
	if granted > 0 then
		DataService.MarkChanged(player, "AuraSkins")
	end
end

local function handleAction(player: Player, skinId: string): RemoteResponse
	local data = DataService.GetData(player)
	if not data then
		return { Ok = false, Code = "NotReady" }
	end
	local ok, code = AuraSkinLogic.Equip(data.AuraSkins, skinId)
	if not ok then
		return { Ok = false, Code = code }
	end
	DataService.MarkChanged(player, "AuraSkins")
	publish(player, data)
	return { Ok = true, Data = { SkinId = skinId } }
end

function AuraSkinService.Init()
	NetService.OnInvoke("AuraSkinAction", Guard.Args(Guard.KeyOf(AuraSkinConfig.Skins)), handleAction)

	DataService.PlayerLoaded:Connect(function(player: Player, data: PlayerData)
		local fixes = AuraSkinLogic.Sanitize(data.AuraSkins)
		if fixes > 0 then
			log:Warn(string.format("user=%d repaired %d aura skin issue(s)", player.UserId, fixes))
			DataService.MarkChanged(player, "AuraSkins")
		end
		AuraSkinService.RefreshUnlocks(player)
		publish(player, data)
	end)
	DataService.DataReset:Connect(publish)

	local function track(player: Player)
		player.CharacterAdded:Connect(function()
			local data = DataService.GetData(player)
			if data then
				publish(player, data)
			end
		end)
	end
	for _, player in Players:GetPlayers() do
		track(player)
	end
	Players.PlayerAdded:Connect(track)
	Players.PlayerRemoving:Connect(function(player)
		player:SetAttribute(ATTRIBUTE, nil)
	end)
end

function AuraSkinService.Start()
	for _, player in Players:GetPlayers() do
		local data = DataService.GetData(player)
		if data then
			AuraSkinService.RefreshUnlocks(player)
			publish(player, data)
		end
	end
end

return AuraSkinService
