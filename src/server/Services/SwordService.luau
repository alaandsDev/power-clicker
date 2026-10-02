--!strict
--[[
	SwordService
	A espada que o jogador carrega: dono da skin equipada e de construir a
	lâmina no personagem.

	A skin é COSMÉTICA — quem dá dano é o Corte (CutService). Aqui só se decide
	aparência, e por isso nada nesta classe toca na economia.

	Desbloqueio é por progressão (estágio da torre, renascimentos, vitórias): o
	servidor concede sozinho quando a condição é atingida, então não existe
	compra nem pedido do cliente para "liberar" nada. O cliente só pede para
	EQUIPAR o que já é dele ("SwordAction"), e isso é revalidado aqui.

	A lâmina é uma Tool: é o Humanoid do Roblox que encaixa a Handle na mão e
	põe o personagem na pose de quem segura arma. Soldar peça na mão à mão
	(a primeira tentativa) deixava a espada flutuando ao lado do punho.

	Orçamento de efeito por jogador: um rastro, uma luz. O arco do clique é
	local (SlashController) e não custa rede.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Guard = require(Shared.Utils.Guard)
local Logger = require(Shared.Utils.Logger)
local Signal = require(Shared.Utils.Signal)
local SwordConfig = require(Shared.Config.SwordConfig)
local SwordLogic = require(Shared.Formulas.SwordLogic)

local NetService = require(script.Parent.NetService)
local DataService = require(script.Parent.DataService)

type PlayerData = Types.PlayerData
type RemoteResponse = Types.RemoteResponse

local SWORD_NAME = "CutBlade"
local ATTRIBUTE = "EquippedSword"
local LIMB_TIMEOUT = 5

local log = Logger.new("Swords")

local SwordService = {
	-- (player, swordId)
	Unlocked = Signal.new() :: Signal.Signal<Player, string>,
}

local function progressOf(data: PlayerData): SwordLogic.Progress
	return {
		Rebirths = data.Stats.Rebirths,
		Wins = data.Currencies.Wins,
		Cleared = data.Tower.Cleared,
	}
end

--[[
	(Re)constrói a lâmina no personagem atual do jogador.
	Parte do R15 aparece um instante depois do personagem, então esperamos o
	Humanoid em vez de desistir na hora (era isso que deixava gente sem espada).
]]
local function buildSword(player: Player, sword: Types.SwordData)
	local character = player.Character
	if not character then
		return
	end
	local found: Instance? = character:FindFirstChildOfClass("Humanoid")
		or character:WaitForChild("Humanoid", LIMB_TIMEOUT)
	local humanoid = if found and found:IsA("Humanoid") then found else nil
	if not humanoid then
		log:Warn(string.format("user=%d has no humanoid to hold the blade", player.UserId))
		return
	end
	local existing = character:FindFirstChild(SWORD_NAME)
	if existing then
		existing:Destroy()
	end

	local grip = SwordConfig.Grip
	local tool = Instance.new("Tool")
	tool.Name = SWORD_NAME
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ManualActivationOnly = true -- clicar é a entrada do jogo, não da Tool
	tool.Grip = CFrame.new(grip.Offset) * CFrame.Angles(math.rad(grip.Pitch), 0, 0)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = grip.GripSize
	handle.Color = Color3.fromRGB(60, 44, 36)
	handle.Material = Enum.Material.Wood
	handle.CanCollide = false
	handle.CanQuery = false
	handle.CanTouch = false
	handle.Massless = true
	handle.TopSurface = Enum.SurfaceType.Smooth
	handle.BottomSurface = Enum.SurfaceType.Smooth
	handle.Parent = tool

	local function attach(name: string, size: Vector3, offset: Vector3, color: Color3, material: Enum.Material): BasePart
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.Color = color
		part.Material = material
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.CFrame = handle.CFrame * CFrame.new(offset)
		part.Parent = tool
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = part
		weld.Part1 = handle
		weld.Parent = part
		return part
	end

	attach("Guard", grip.GuardSize, Vector3.new(0, grip.GripSize.Y / 2, 0), Color3.fromRGB(120, 110, 90), Enum.Material.Metal)
	local blade = attach(
		"Blade",
		sword.BladeSize,
		Vector3.new(0, grip.GripSize.Y / 2 + sword.BladeSize.Y / 2, 0),
		sword.Color,
		if sword.Neon then Enum.Material.Neon else sword.Material
	)

	if sword.TrailSeconds > 0 then
		local tip = Instance.new("Attachment")
		tip.Position = Vector3.new(0, sword.BladeSize.Y / 2, 0)
		tip.Parent = blade
		local spine = Instance.new("Attachment")
		spine.Position = Vector3.new(0, -sword.BladeSize.Y / 2, 0)
		spine.Parent = blade

		local trail = Instance.new("Trail")
		trail.Attachment0 = tip
		trail.Attachment1 = spine
		trail.Color = ColorSequence.new(sword.ArcColor)
		trail.Lifetime = sword.TrailSeconds
		trail.MinLength = 0.2
		trail.WidthScale = NumberSequence.new(sword.TrailWidth)
		trail.LightEmission = 0.6
		trail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		trail.Parent = blade
	end
	if sword.LightRange > 0 then
		local glow = Instance.new("PointLight")
		glow.Color = sword.ArcColor
		glow.Range = sword.LightRange
		glow.Brightness = 1.6
		glow.Shadows = false
		glow.Parent = blade
	end

	tool.Parent = character
	humanoid:EquipTool(tool)
end

local function publish(player: Player, data: PlayerData)
	local sword = SwordLogic.Equipped(data.Swords)
	player:SetAttribute(ATTRIBUTE, sword.Id)
	-- buildSword pode esperar por um membro do personagem: nunca na thread do sinal.
	task.spawn(buildSword, player, sword)
end

--[[
	Concede toda skin cuja condição de progressão já foi cumprida.
	Chamado quando algo que conta muda (renascimento, vitórias, estágio), e
	também ao carregar os dados — então quem já passou do estágio antes desta
	fase existir recebe a skin na entrada.
]]
function SwordService.RefreshUnlocks(player: Player)
	local data = DataService.GetData(player)
	if not data then
		return
	end
	local progress = progressOf(data)
	local granted = 0
	for _, sword in SwordConfig.Swords do
		if not SwordLogic.Owns(data.Swords, sword.Id) and SwordLogic.IsUnlocked(sword, progress) then
			data.Swords.Owned[sword.Id] = true
			granted += 1
			NetService.FireClient("Notify", player, "SwordUnlocked", { SwordId = sword.Id })
			SwordService.Unlocked:Fire(player, sword.Id)
			log:Info(string.format("user=%d unlocked sword %s", player.UserId, sword.Id))
		end
	end
	if granted > 0 then
		DataService.MarkChanged(player, "Swords")
	end
end

local function handleAction(player: Player, swordId: string): RemoteResponse
	local data = DataService.GetData(player)
	if not data then
		return { Ok = false, Code = "NotReady" }
	end
	local ok, code = SwordLogic.Equip(data.Swords, swordId)
	if not ok then
		return { Ok = false, Code = code }
	end
	DataService.MarkChanged(player, "Swords")
	publish(player, data)
	return { Ok = true, Data = { SwordId = swordId } }
end

function SwordService.Init()
	NetService.OnInvoke("SwordAction", Guard.Args(Guard.KeyOf(SwordConfig.Swords)), handleAction)

	DataService.PlayerLoaded:Connect(function(player: Player, data: PlayerData)
		local fixes = SwordLogic.Sanitize(data.Swords)
		if fixes > 0 then
			log:Warn(string.format("user=%d repaired %d sword issue(s)", player.UserId, fixes))
			DataService.MarkChanged(player, "Swords")
		end
		SwordService.RefreshUnlocks(player)
		publish(player, data)
	end)
	DataService.DataReset:Connect(publish)

	-- Personagem novo nasce sem a Tool: reconstrói a cada spawn.
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

function SwordService.Start()
	for _, player in Players:GetPlayers() do
		local data = DataService.GetData(player)
		if data then
			SwordService.RefreshUnlocks(player)
			publish(player, data)
		end
	end
end

return SwordService
