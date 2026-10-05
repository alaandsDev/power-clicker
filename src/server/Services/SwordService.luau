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

	ESPADA PARADA = energia contida; ESPADA ATACANDO = energia forte. No jogo
	real a lâmina estourava (Neon inteira + luz de alcance 10–28 sempre acesa).
	Agora, parada: lâmina sólida na cor da skin (as skins "neon" ganham só um
	FIO de energia nas bordas), luz fraca e rastro desligado. Durante o golpe,
	cada cliente acende fio, luz e rastro (SwordTrail, a partir dos atributos
	IdleBrightness/SwingBrightness e IdleTransparency abaixo).
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
local LIMB_TIMEOUT = 8
-- Depois de equipar, confere uma vez se a espada ficou mesmo na mão.
local VERIFY_SECONDS = 0.6

--[[
	Uma "senha" por jogador: cada publish() gera uma nova, e só a montagem com
	a senha mais recente termina. Sem isso, o carregamento dos dados e o
	CharacterAdded (ou duas trocas rápidas) montavam duas espadas ao mesmo
	tempo no mesmo personagem.
]]
local buildTokens: { [Player]: number } = {}

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
local function handOf(character: Model): Instance?
	return character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
end

--[[
	Espera o personagem estar MONTADO: no Workspace, com Humanoid, a mão
	direita e o HumanoidRootPart. Bug encontrado no Studio: no primeiro
	personagem a espada era criada assim que o Humanoid aparecia, antes da
	mão; o EquipTool não tinha onde soldar o cabo, e a espada (solta, sem
	colisão) caía para fora do mapa. Trocar de espada depois funcionava porque
	aí o personagem já estava pronto.
]]
local function waitForBody(player: Player, character: Model): Humanoid?
	local deadline = os.clock() + LIMB_TIMEOUT
	while os.clock() < deadline do
		if player.Character ~= character then
			return nil -- respawnou no meio: a montagem do novo personagem assume
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if
			humanoid
			and handOf(character)
			and character:FindFirstChild("HumanoidRootPart")
			and character:IsDescendantOf(workspace)
		then
			return humanoid
		end
		task.wait(0.1)
	end
	return nil
end

-- Remove qualquer espada nossa do personagem e da mochila (nunca duas).
local function removeBlades(player: Player, character: Model)
	for _, container in { character, player:FindFirstChildOfClass("Backpack") } do
		if container then
			for _, child in container:GetChildren() do
				if child.Name == SWORD_NAME then
					child:Destroy()
				end
			end
		end
	end
end

local function buildSword(player: Player, sword: Types.SwordData, token: number)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = waitForBody(player, character)
	if buildTokens[player] ~= token or player.Character ~= character then
		return -- uma montagem mais nova (troca, respawn) já assumiu
	end
	if not humanoid then
		log:Warn(string.format("user=%d character never got a hand to hold the blade", player.UserId))
		return
	end
	removeBlades(player, character)

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
	local bladeOffset = Vector3.new(0, grip.GripSize.Y / 2 + sword.BladeSize.Y / 2, 0)
	local blade = attach(
		"Blade",
		sword.BladeSize,
		bladeOffset,
		sword.Color,
		-- Material Neon na lâmina inteira estourava o formato: corpo sólido.
		if sword.Material == Enum.Material.Neon then Enum.Material.SmoothPlastic else sword.Material
	)
	if sword.Neon then
		-- O brilho das skins de energia mora num fio nas duas bordas.
		for _, side in { -1, 1 } do
			local edge = attach(
				"BladeEdge",
				Vector3.new(sword.BladeSize.X * 1.1, sword.BladeSize.Y * 0.94, 0.14),
				bladeOffset + Vector3.new(0, 0, side * (sword.BladeSize.Z / 2 + 0.02)),
				sword.ArcColor,
				Enum.Material.Neon
			)
			edge.Transparency = 0.4
			edge:SetAttribute("IdleTransparency", 0.4)
		end
	end

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
		-- Desligado parado; o cliente liga durante o golpe (SwordTrail).
		trail.Enabled = false
		trail.Parent = blade
	end
	if sword.LightRange > 0 then
		local glow = Instance.new("PointLight")
		glow.Color = sword.ArcColor
		glow.Range = sword.LightRange
		glow.Brightness = 0.35
		glow.Shadows = false
		glow:SetAttribute("IdleBrightness", 0.35)
		glow:SetAttribute("SwingBrightness", 1.6)
		glow.Parent = blade
	end

	tool.Parent = character
	humanoid:EquipTool(tool)
	-- Confere uma vez: se algo tirou a espada da mão, equipa de novo.
	task.delay(VERIFY_SECONDS, function()
		if buildTokens[player] == token and player.Character == character and tool.Parent ~= character and tool.Parent ~= nil then
			humanoid:EquipTool(tool)
		end
	end)
end

--[[
	Aplica a espada equipada ao personagem atual. Chamado ao carregar os
	dados, a cada CharacterAdded (respawn), ao trocar de espada e no reset de
	dados do Studio — sempre o mesmo caminho, então o que a UI mostra como
	"Equipada" é o que aparece na mão.
]]
local function publish(player: Player, data: PlayerData)
	local sword = SwordLogic.Equipped(data.Swords)
	player:SetAttribute(ATTRIBUTE, sword.Id)
	local token = (buildTokens[player] or 0) + 1
	buildTokens[player] = token
	-- buildSword espera o personagem montar: nunca na thread do sinal.
	task.spawn(buildSword, player, sword, token)
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
		buildTokens[player] = nil
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
