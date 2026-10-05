--!strict
--[[
	SwordSwingController
	O corpo com a espada (SwordSwing: procedural, local, sem AnimationTrack):
	a POSTURA DE COMBATE quando o personagem está parado com a espada (com
	respiração sutil), o "carregar" andando/pulando, e o GOLPE a cada hit,
	que parte da pose atual e volta para a postura. O SlashController chama
	Swing() no clique e desenha o arco e o corte (CutFx) no momento do
	impacto que Swing() devolve, então lâmina, corte e impacto coincidem.

	ORDEM NO QUADRO (o que faz a pose aparecer de verdade):
	  PreAnimation → Animator escreve o Transform das articulações
	  PreSimulation → AQUI: a pose é somada por cima (SwordSwing.Step)
	  física/juntas resolvem as partes
	  PostSimulation → AQUI: mede se o braço REAL ficou na pose (verificação)
	  render
	Antes a pose ia no RenderStepped, no C0/Attachment0, com a base guardada
	no spawn e o rig montado uma vez só: se o Roblox trocava a articulação
	ou a base depois do spawn (aparência carregando, Joint Upgrade, escala),
	a escrita ia para o lugar errado e nada aparecia. Agora o rig é
	revalidado todo quadro e remontado quando a articulação muda.

	Verificação (só do jogador local): com pose de 8°+ no ombro, mede o braço
	de verdade; se depois de ~20 medições ele NÃO está na pose, troca a
	camada (Transform → Offset) e avisa no Output. SwordDebug (só Studio)
	mostra tudo no Output com [SwordRuntime] e num painel.

	- Jogador local: golpe completo a cada hit (até ~9/s; um golpe novo
	  continua da pose atual), no combo visual A→B→C (SwordSwing). Trocar de
	  espada recomeça o combo no A. "Efeitos reduzidos" NÃO tira o golpe: é a
	  informação básica de que você está atacando.
	- Outros jogadores perto (até REMOTE_DISTANCE): o servidor marca o atributo
	  "SwingSeq" no jogador no máximo ~4 vezes por segundo enquanto ele clica
	  (ClickService); aqui isso vira uma sequência curta de golpes no
	  personagem dele. Sem remote novo, sem replicar cada hit. Longe: nada.
	- Postura dos outros jogadores: só os que estão perto (REMOTE_DISTANCE) e
	  com a espada na mão ganham rig (varredura a cada SCAN_SECONDS); quem se
	  afasta volta ao original e o rig é descartado.

	Sem espada e já sem pose, um rig não escreve nada. Personagem que
	sai/morre: o rig é descartado (e o que foi escrito é devolvido).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local SwordSwing = require(script.Parent.Parent.Effects.SwordSwing)
local SwordTrail = require(script.Parent.Parent.Effects.SwordTrail)
local SwordDebug = require(script.Parent.Parent.Effects.SwordDebug)

local REMOTE_DISTANCE = 80
-- Um sinal do servidor (a cada ~0,25 s de cliques) vira golpes por este tempo.
local REMOTE_BURST_SECONDS = 0.3
local REMOTE_SWING_SPACING = 0.16
local BODY_TIMEOUT = 8
local SCAN_SECONDS = 0.5
-- Quadro mais longo que isto (janela minimizada, travada) conta como isto.
local MAX_FRAME = 0.1
-- Verificação: pose mínima para medir, medições por veredito, acerto mínimo.
local VERIFY_MIN_DEGREES = 8
local VERIFY_SAMPLES = 20
local VERIFY_SHARE = 0.6
local PANEL_SECONDS = 0.2
-- Rede de segurança: procura articulação nova/trocada mesmo sem evento.
local REBIND_SECONDS = 1

type Remote = {
	Rig: SwordSwing.Rig?,
	BurstUntil: number,
	NextAt: number,
	Failed: Model?, -- personagem sem articulações reconhecíveis: não tenta de novo
	Connections: { RBXScriptConnection },
}

type Verify = {
	Samples: number,
	Reached: number,
	Confirmed: { [string]: boolean },
	Failed: { [string]: boolean },
	Last: string,
}

local SwordSwingController = {}

local localRig: SwordSwing.Rig? = nil
local localDirty = false
local localConnections: { RBXScriptConnection } = {}
local remotes: { [Player]: Remote } = {}
-- Rastro ligado enquanto o golpe dura: personagem -> a lâmina com rastro
-- ligado (uma lâmina nova, de troca de skin, ganha o rastro na hora).
local trailOn: { [Model]: Instance } = {}
local lastStep: number? = nil
local nextScan = 0
local nextRebind = 0
-- A camada que a verificação aprovou neste cliente (vale para os outros
-- jogadores e para o próximo respawn).
local preferred = "Transform"
local verify: Verify = { Samples = 0, Reached = 0, Confirmed = {}, Failed = {}, Last = "-" }
local debugState = { Stance = false, Armed = false, Minimal = false, NextPanel = 0 }

local function bladeOf(character: Model): Instance?
	local tool = character:FindFirstChild("CutBlade")
	return if tool then tool:FindFirstChild("Blade") else nil
end

local function bladeLength(blade: Instance?): number
	return if blade and blade:IsA("BasePart") then blade.Size.Y else SwordSwing.BASE_BLADE
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

-- ── Diagnóstico ─────────────────────────────────────────────────────────────

local function rigTypeOf(character: Model): string
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return "sem Humanoid"
	end
	local ok, rigType = pcall(function()
		return (humanoid :: Humanoid).RigType.Name
	end)
	return if ok then rigType else "?"
end

local function logCharacter(character: Model)
	if not SwordDebug.Enabled() then
		return
	end
	SwordDebug.Log("Character detectado: " .. character:GetFullName())
	SwordDebug.Log("RigType = " .. rigTypeOf(character))
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = if humanoid then humanoid:FindFirstChildOfClass("Animator") else nil
	local animate = character:FindFirstChild("Animate")
	SwordDebug.Log(string.format("Animator = %s | Animate = %s", if animator then "sim" else "NÃO", if animate then animate.ClassName else "NÃO"))
	local motors, constraints = 0, 0
	for _, item in character:GetDescendants() do
		if item:IsA("Motor6D") then
			motors += 1
		elseif item.ClassName == "AnimationConstraint" then
			constraints += 1
		end
	end
	SwordDebug.Log(string.format("articulações no personagem: %d Motor6D, %d AnimationConstraint", motors, constraints))
end

local function logRig(rig: SwordSwing.Rig, reason: string)
	if not SwordDebug.Enabled() then
		return
	end
	SwordDebug.Log(string.format("rig %s (RigType = %s)", reason, rigTypeOf(rig.Character)))
	for _, line in SwordSwing.Describe(rig) do
		SwordDebug.Log("joint encontrado: " .. line)
	end
	SwordDebug.Log(string.format("backend = %s sobre %s", rig.Backend, rig.Kind))
end

local function logTracks(character: Model)
	if not SwordDebug.Enabled() then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = if humanoid then humanoid:FindFirstChildOfClass("Animator") else nil
	if not animator then
		return
	end
	local ok, tracks = pcall(function()
		return (animator :: Animator):GetPlayingAnimationTracks()
	end)
	if ok then
		local names = {}
		for _, track in tracks do
			table.insert(names, string.format("%s(%s)", track.Name, track.Priority.Name))
		end
		SwordDebug.Log("animações tocando: " .. (if #names > 0 then table.concat(names, ", ") else "nenhuma"))
	end
end

local function resetVerify()
	verify.Samples = 0
	verify.Reached = 0
end

local function forcedBackend(rig: SwordSwing.Rig)
	local forced = SwordDebug.ForcedBackend()
	if forced and rig.Backend ~= forced then
		SwordSwing.SetBackend(rig, forced)
		resetVerify()
		SwordDebug.Log("backend forçado pelo atributo SwordBackend = " .. forced)
	end
end

--[[
	Depois da física: o braço de verdade está na pose? Veredito a cada
	VERIFY_SAMPLES medições com pose relevante; troca de camada se não chegou.
]]
function SwordSwingController.Verify()
	local rig = localRig
	if not rig then
		return
	end
	local size, toPosed, toPlain = SwordSwing.Measure(rig)
	if not size or not toPosed or not toPlain or size < VERIFY_MIN_DEGREES then
		return
	end
	verify.Samples += 1
	if toPosed < toPlain then
		verify.Reached += 1
	end
	verify.Last = string.format("pose %.0f° | real a %.1f° da pose, %.1f° do Animator", size, toPosed, toPlain)
	if verify.Samples < VERIFY_SAMPLES then
		return
	end
	local share = verify.Reached / verify.Samples
	local backend = rig.Backend
	resetVerify()
	if share >= VERIFY_SHARE then
		if not verify.Confirmed[backend] then
			verify.Confirmed[backend] = true
			verify.Failed[backend] = nil
			SwordDebug.Log(string.format("POSE CONFIRMADA no personagem (backend %s, %s)", backend, verify.Last))
		end
		return
	end
	verify.Confirmed[backend] = nil
	if not verify.Failed[backend] then
		verify.Failed[backend] = true
		SwordDebug.Log(string.format("POSE NÃO CHEGOU AO PERSONAGEM (backend %s, %d%% das medições; %s)", backend, math.floor(share * 100 + 0.5), verify.Last))
	end
	if SwordDebug.ForcedBackend() then
		return -- forçado na barra de comando: não troca sozinho
	end
	local other = if backend == "Transform" then "Offset" else "Transform"
	if not verify.Failed[other] then
		SwordSwing.SetBackend(rig, other)
		preferred = other
		SwordDebug.Log("trocando backend: " .. backend .. " → " .. other)
	elseif not verify.Failed.Both then
		verify.Failed.Both = true
		warn("[SwordRuntime] nenhuma camada (Transform nem Offset) moveu o braço de verdade — veja os logs [SwordRuntime] acima (joints/backend)")
	end
end

-- Para os testes / painel.
function SwordSwingController.VerifyState(): Verify
	return verify
end

local function panel(rig: SwordSwing.Rig?, at: number)
	if not SwordDebug.Enabled() or at < debugState.NextPanel then
		return
	end
	debugState.NextPanel = at + PANEL_SECONDS
	local state = "SEM RIG"
	if rig then
		state = if rig.Active then "ATTACK" elseif rig.Armed >= 0.99 and rig.Idle > 0.5 then "STANCE" elseif rig.Armed > 0 then "CARRY" else "SEM ESPADA"
	end
	local text = string.format(
		"RIG: %s\nJOINT: %s\nBACKEND: %s%s\nSTATE: %s\nCOMBO: %s\n%s",
		if rig then rigTypeOf(rig.Character) else "-",
		if rig then rig.Kind else "-",
		if rig then rig.Backend else "-",
		if rig and verify.Confirmed[rig.Backend] then " (CONFIRMADO)" elseif rig and verify.Failed[rig.Backend] then " (FALHOU)" else "",
		state .. (if rig and rig.Minimal then " [TESTE MÍNIMO]" else ""),
		if rig then rig.Variant else "-",
		verify.Last
	)
	SwordDebug.Panel(Players.LocalPlayer:FindFirstChildOfClass("PlayerGui"), text)
end

-- ── Rig local ───────────────────────────────────────────────────────────────

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

local JOINT_CLASSES = { Motor6D = true, AnimationConstraint = true, Attachment = true }

local function watchCharacter(character: Model)
	for _, connection in localConnections do
		connection:Disconnect()
	end
	table.clear(localConnections)
	-- Aparência carregando / Joint Upgrade convertendo trocam articulações
	-- DEPOIS do spawn: marca para remontar o rig no próximo quadro.
	local function touched(item: Instance)
		if JOINT_CLASSES[item.ClassName] or item:IsA("BasePart") then
			localDirty = true
		end
	end
	for _, name in { "DescendantAdded", "DescendantRemoving" } do
		local ok, event = pcall(function()
			return (character :: any)[name]
		end)
		if ok and event then
			table.insert(localConnections, event:Connect(touched))
		end
	end
end

local function onLocalCharacter(character: Model)
	if localRig then
		SwordSwing.Reset(localRig :: SwordSwing.Rig)
	end
	localRig = nil
	resetVerify()
	logCharacter(character)
	watchCharacter(character)
	task.spawn(function()
		local rig = buildRig(character)
		if rig and Players.LocalPlayer.Character == character then
			SwordSwing.SetBackend(rig, preferred)
			localRig = rig
			localDirty = false
			logRig(rig, "montado")
		elseif not rig and Players.LocalPlayer.Character == character and not warned then
			-- Sem isto o golpe sumia em silêncio.
			warned = true
			warn("[SwordSwing] nenhuma articulação de ombro direito reconhecida no personagem (Motor6D R15/R6 ou AnimationConstraint): o golpe da espada ficou desligado")
		end
	end)
end

-- Rig local ainda bate com o personagem? Remonta se o Roblox trocou algo.
local function refreshLocal(rig: SwordSwing.Rig): SwordSwing.Rig?
	if not localDirty and SwordSwing.Valid(rig) then
		return rig
	end
	localDirty = false
	if SwordSwing.Rebind(rig) then
		resetVerify()
		table.clear(verify.Confirmed)
		table.clear(verify.Failed)
		logRig(rig, "remontado (o Roblox trocou articulações do personagem)")
	end
	if not rig.Joints.Shoulder then
		SwordDebug.Log("ombro direito sumiu do personagem: rig descartado")
		localRig = nil
		return nil
	end
	return rig
end

--[[
	Golpe do jogador local AGORA. Devolve (segundos até o impacto, variação);
	sem rig (personagem montando) devolve (0, nil). O chamador desenha o
	corte nesse momento, inclinado como o golpe.
]]
function SwordSwingController.Swing(): (number, SwordSwing.Variant?)
	local rig = localRig
	if not rig or rig.Character ~= Players.LocalPlayer.Character then
		SwordDebug.Log("HIT VISUAL RECEBIDO, mas sem rig no personagem (montando ou sem ombro reconhecido)")
		return 0, nil
	end
	rig.Minimal = SwordDebug.Minimal()
	local variant, impact = SwordSwing.Start(rig, now())
	SwordDebug.Log("HIT VISUAL RECEBIDO")
	SwordDebug.Log("COMBO = " .. variant .. (if rig.Minimal then " (teste mínimo: braço sobe e volta)" else ""))
	setTrail(rig.Character, Players.LocalPlayer:GetAttribute("EquippedSword"), true)
	SwordTrail.Emphasis(rig.Character, SwordSwing.IsFinisher(variant))
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

-- Para os testes: o rig de outro jogador (nil se longe/sem espada).
function SwordSwingController.RemoteRig(player: Player): SwordSwing.Rig?
	local remote = remotes[player]
	return if remote then remote.Rig else nil
end

local function rootOf(character: Model?): BasePart?
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

-- ── Outros jogadores ────────────────────────────────────────────────────────

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
	if (not remote.Rig or (remote.Rig :: SwordSwing.Rig).Character ~= character) and remote.Failed ~= character then
		remote.Rig = SwordSwing.NewRig(character)
		remote.Failed = if remote.Rig then nil else character
	end
	remote.BurstUntil = now() + REMOTE_BURST_SECONDS
end

local function track(player: Player)
	if player == Players.LocalPlayer or remotes[player] then
		return
	end
	local remote: Remote = { Rig = nil, BurstUntil = 0, NextAt = 0, Failed = nil, Connections = {} }
	remotes[player] = remote
	table.insert(remote.Connections, player:GetAttributeChangedSignal("SwingSeq"):Connect(function()
		onRemoteSwing(player)
	end))
	table.insert(remote.Connections, player.CharacterRemoving:Connect(function(character: Model)
		if remote.Rig then
			SwordSwing.Reset(remote.Rig :: SwordSwing.Rig)
		end
		remote.Rig = nil
		remote.Failed = nil
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

-- Quem está perto e com espada ganha rig; quem se afastou volta ao original.
local function scan()
	local mine = rootOf(Players.LocalPlayer.Character)
	for player, remote in remotes do
		local rig = remote.Rig
		local character = player.Character
		local theirs = rootOf(character)
		local near = mine ~= nil and theirs ~= nil and ((mine :: BasePart).Position - (theirs :: BasePart).Position).Magnitude <= REMOTE_DISTANCE
		if near and character then
			local stale = rig == nil or (rig :: SwordSwing.Rig).Character ~= character
			if stale and remote.Failed ~= character and character:FindFirstChild("CutBlade") then
				remote.Rig = SwordSwing.NewRig(character)
				remote.Failed = if remote.Rig then nil else character
			elseif rig and not SwordSwing.Valid(rig) then
				SwordSwing.Rebind(rig)
			end
		elseif rig and not rig.Active then
			trailOn[rig.Character] = nil
			SwordSwing.Reset(rig)
			remote.Rig = nil
		end
	end
end

-- ── Quadro ──────────────────────────────────────────────────────────────────

local function stepRig(rig: SwordSwing.Rig, at: number, dt: number, swordId: any, minimal: boolean)
	local character = rig.Character
	if rig ~= localRig and rig.Backend ~= preferred then
		SwordSwing.SetBackend(rig, preferred)
	end
	local armed = character:FindFirstChild("CutBlade") ~= nil
	local blade = if armed then bladeOf(character) else nil
	if blade and blade ~= rig.Blade then
		if rig.Blade then
			SwordSwing.ResetCombo(rig) -- espada nova: o combo recomeça no A
		end
		rig.Blade = blade
	end
	local root = rootOf(character)
	local moving = SwordSwing.Track(rig, if root then root.Position else nil, dt)
	-- Teste mínimo: sem postura (só o golpe "sobe e volta").
	SwordSwing.Settle(rig, at, dt, armed and not minimal, moving, bladeLength(blade))
	local wasActive = rig.Active
	local swinging = SwordSwing.Step(rig, at)
	if swinging or wasActive then
		setTrail(character, swordId, swinging)
	end
end

local function logLocalState(rig: SwordSwing.Rig)
	if not SwordDebug.Enabled() then
		return
	end
	local armed = rig.Character:FindFirstChild("CutBlade") ~= nil
	if armed ~= debugState.Armed then
		debugState.Armed = armed
		SwordDebug.Log(if armed then string.format("espada na mão (CutBlade, lâmina %.1f)", bladeLength(bladeOf(rig.Character))) else "sem espada na mão")
	end
	local stance = rig.Armed >= 0.99 and rig.Idle > 0.9 and not rig.Minimal
	if stance ~= debugState.Stance then
		debugState.Stance = stance
		SwordDebug.Log(if stance then "STANCE ACTIVE" else "STANCE OFF")
		if stance then
			logTracks(rig.Character)
		end
	end
	if rig.Minimal ~= debugState.Minimal then
		debugState.Minimal = rig.Minimal
		SwordDebug.Log(if rig.Minimal then "TESTE MÍNIMO ligado (clique = braço sobe e volta; sem postura/combo)" else "TESTE MÍNIMO desligado")
	end
end

-- Um quadro para todos os rigs, DEPOIS do Animator (exposto para os testes).
function SwordSwingController.Step(at: number)
	local dt = math.clamp(at - (lastStep or at), 0, MAX_FRAME)
	lastStep = at
	if at >= nextScan then
		nextScan = at + SCAN_SECONDS
		scan()
	end
	local rig = localRig
	if at >= nextRebind then
		nextRebind = at + REBIND_SECONDS
		localDirty = true
	end
	if rig then
		rig = refreshLocal(rig :: SwordSwing.Rig)
	end
	if rig then
		forcedBackend(rig)
		rig.Minimal = SwordDebug.Minimal()
		stepRig(rig, at, dt, Players.LocalPlayer:GetAttribute("EquippedSword"), rig.Minimal)
		logLocalState(rig)
	end
	panel(rig, at)
	for player, remote in remotes do
		local remoteRig = remote.Rig
		if remoteRig then
			if at < remote.BurstUntil and at >= remote.NextAt then
				remote.NextAt = at + REMOTE_SWING_SPACING
				local variant = SwordSwing.Start(remoteRig, at)
				SwordTrail.Emphasis(remoteRig.Character, SwordSwing.IsFinisher(variant))
			end
			stepRig(remoteRig, at, dt, player:GetAttribute("EquippedSword"), false)
		end
	end
end

function SwordSwingController.Init()
	local player = Players.LocalPlayer
	SwordDebug.Log("SwordController iniciado")
	player.CharacterAdded:Connect(onLocalCharacter)
	player.CharacterRemoving:Connect(function(character: Model)
		if localRig then
			SwordSwing.Reset(localRig :: SwordSwing.Rig)
		end
		localRig = nil
		trailOn[character] = nil
		for _, connection in localConnections do
			connection:Disconnect()
		end
		table.clear(localConnections)
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

-- Sinal do quadro: o novo nome, ou o antigo (Stepped/Heartbeat) se faltar.
local function signal(name: string, fallback: string): RBXScriptSignal
	local ok, value = pcall(function()
		return (RunService :: any)[name]
	end)
	return if ok and value then value else (RunService :: any)[fallback]
end

function SwordSwingController.Start()
	-- Depois do Animator e antes da física: a pose entra no mesmo quadro.
	signal("PreSimulation", "Stepped"):Connect(function()
		SwordSwingController.Step(now())
	end)
	-- Depois da física: o braço de verdade ficou na pose?
	signal("PostSimulation", "Heartbeat"):Connect(function()
		SwordSwingController.Verify()
	end)
end

return SwordSwingController
