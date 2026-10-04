--!strict
--[[
	SwordSwingController
	Faz o personagem GOLPEAR com a espada a cada hit (SwordSwing: procedural,
	local, sem AnimationTrack). O SlashController chama Swing() no clique e
	desenha o arco e o corte (CutFx) no momento do impacto que Swing() devolve,
	então lâmina, corte e impacto coincidem.

	- Jogador local: golpe completo a cada hit (até ~9/s; um golpe novo
	  continua da pose atual). "Efeitos reduzidos" NÃO tira o golpe: é a
	  informação básica de que você está atacando.
	- Outros jogadores perto (até REMOTE_DISTANCE): o servidor marca o atributo
	  "SwingSeq" no jogador no máximo ~4 vezes por segundo enquanto ele clica
	  (ClickService); aqui isso vira uma sequência curta de golpes no
	  personagem dele. Sem remote novo, sem replicar cada hit. Longe: nada.

	Uma conexão por quadro para todos os rigs, e ela não faz nada quando
	ninguém está golpeando. Personagem que sai/morre: o rig é descartado
	(e o C0 volta ao original se a peça ainda existir).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local SwordSwing = require(script.Parent.Parent.Effects.SwordSwing)
local SwordTrail = require(script.Parent.Parent.Effects.SwordTrail)

local REMOTE_DISTANCE = 80
-- Um sinal do servidor (a cada ~0,25 s de cliques) vira golpes por este tempo.
local REMOTE_BURST_SECONDS = 0.3
local REMOTE_SWING_SPACING = 0.16
local BODY_TIMEOUT = 8

type Remote = { Rig: SwordSwing.Rig?, BurstUntil: number, NextAt: number, Connections: { RBXScriptConnection } }

local SwordSwingController = {}

local localRig: SwordSwing.Rig? = nil
local remotes: { [Player]: Remote } = {}
-- Rastro ligado enquanto o golpe dura: personagem -> a lâmina com rastro
-- ligado (uma lâmina nova, de troca de skin, ganha o rastro na hora).
local trailOn: { [Model]: Instance } = {}

local function bladeOf(character: Model): Instance?
	local tool = character:FindFirstChild("CutBlade")
	return if tool then tool:FindFirstChild("Blade") else nil
end

local function setTrail(character: Model, swordId: any, moving: boolean)
	if moving then
		local blade = bladeOf(character)
		if blade and trailOn[character] ~= blade then
			trailOn[character] = blade
			SwordTrail.Set(character, swordId, true)
		end
	elseif trailOn[character] then
		trailOn[character] = nil
		SwordTrail.Set(character, swordId, false)
	end
end

local function now(): number
	return os.clock()
end

local function buildRig(character: Model): SwordSwing.Rig?
	-- O R15 monta as partes um instante depois do personagem.
	local deadline = now() + BODY_TIMEOUT
	while now() < deadline and character.Parent do
		local rig = SwordSwing.NewRig(character)
		if rig then
			return rig
		end
		task.wait(0.2)
	end
	return nil
end

local warned = false

local function onLocalCharacter(character: Model)
	if localRig then
		SwordSwing.Reset(localRig :: SwordSwing.Rig)
	end
	localRig = nil
	task.spawn(function()
		local rig = buildRig(character)
		if rig and Players.LocalPlayer.Character == character then
			localRig = rig
		elseif not rig and Players.LocalPlayer.Character == character and not warned then
			-- Sem isto o golpe sumia em silêncio (foi o que aconteceu no Studio).
			warned = true
			warn("[SwordSwing] nenhuma articulação de ombro direito reconhecida no personagem (Motor6D R15/R6 ou AnimationConstraint): o golpe da espada ficou desligado")
		end
	end)
end

--[[
	Golpe do jogador local AGORA. Devolve (segundos até o impacto, variação);
	sem rig (R6, personagem montando) devolve (0, nil). O chamador desenha o
	corte nesse momento, inclinado como o golpe.
]]
function SwordSwingController.Swing(): (number, SwordSwing.Variant?)
	local rig = localRig
	if not rig or rig.Character ~= Players.LocalPlayer.Character then
		return 0, nil
	end
	local variant, impact = SwordSwing.Start(rig, now())
	setTrail(rig.Character, Players.LocalPlayer:GetAttribute("EquippedSword"), true)
	return impact, variant
end

--[[
	"Hit stop" VISUAL: segura a pose do golpe por `seconds` (0,03–0,06) no
	impacto da quebra. Só o braço deste cliente; servidor e jogo seguem.
]]
function SwordSwingController.HitStop(seconds: number)
	local rig = localRig
	if rig and rig.Active then
		rig.Started += math.clamp(seconds, 0, 0.08)
	end
end

function SwordSwingController.LocalRig(): SwordSwing.Rig?
	return localRig
end

local function rootOf(character: Model?): BasePart?
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

local function onRemoteSwing(player: Player)
	local remote = remotes[player]
	if not remote then
		return
	end
	local character = player.Character
	local mine = rootOf(Players.LocalPlayer.Character)
	local theirs = rootOf(character)
	if not character or not mine or not theirs or (mine.Position - theirs.Position).Magnitude > REMOTE_DISTANCE then
		return
	end
	if not remote.Rig or (remote.Rig :: SwordSwing.Rig).Character ~= character then
		remote.Rig = SwordSwing.NewRig(character)
	end
	remote.BurstUntil = now() + REMOTE_BURST_SECONDS
end

local function track(player: Player)
	if player == Players.LocalPlayer or remotes[player] then
		return
	end
	local remote: Remote = { Rig = nil, BurstUntil = 0, NextAt = 0, Connections = {} }
	remotes[player] = remote
	table.insert(remote.Connections, player:GetAttributeChangedSignal("SwingSeq"):Connect(function()
		onRemoteSwing(player)
	end))
	table.insert(remote.Connections, player.CharacterRemoving:Connect(function(character: Model)
		if remote.Rig then
			SwordSwing.Reset(remote.Rig :: SwordSwing.Rig)
		end
		remote.Rig = nil
		trailOn[character] = nil
	end))
end

local function untrack(player: Player)
	local remote = remotes[player]
	if not remote then
		return
	end
	for _, connection in remote.Connections do
		connection:Disconnect()
	end
	if remote.Rig then
		trailOn[(remote.Rig :: SwordSwing.Rig).Character] = nil
		SwordSwing.Reset(remote.Rig :: SwordSwing.Rig)
	end
	remotes[player] = nil
end

local function stepRig(rig: SwordSwing.Rig, at: number, swordId: any)
	local wasActive = rig.Active
	local moving = SwordSwing.Step(rig, at)
	if moving or wasActive then
		setTrail(rig.Character, swordId, moving)
	end
end

-- Um quadro para todos os rigs (exposto para os testes).
function SwordSwingController.Step(at: number)
	if localRig then
		stepRig(localRig :: SwordSwing.Rig, at, Players.LocalPlayer:GetAttribute("EquippedSword"))
	end
	for player, remote in remotes do
		local rig = remote.Rig
		if rig then
			if at < remote.BurstUntil and at >= remote.NextAt then
				remote.NextAt = at + REMOTE_SWING_SPACING
				SwordSwing.Start(rig, at)
			end
			stepRig(rig, at, player:GetAttribute("EquippedSword"))
		end
	end
end

function SwordSwingController.Init()
	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(onLocalCharacter)
	player.CharacterRemoving:Connect(function(character: Model)
		if localRig then
			SwordSwing.Reset(localRig :: SwordSwing.Rig)
		end
		localRig = nil
		trailOn[character] = nil
	end)
	if player.Character then
		onLocalCharacter(player.Character)
	end
	for _, other in Players:GetPlayers() do
		track(other)
	end
	Players.PlayerAdded:Connect(track)
	Players.PlayerRemoving:Connect(untrack)
end

function SwordSwingController.Start()
	RunService.RenderStepped:Connect(function()
		SwordSwingController.Step(now())
	end)
end

return SwordSwingController
