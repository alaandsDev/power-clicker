--!strict
--[[
	TrainingService
	A área de treino: enquanto o jogador está em cima de uma máquina, ele ganha
	Power continuamente.

	Como funciona, e por que assim:
	- UM laço central (TrainingConfig.TickSeconds) percorre os jogadores. Um
	  laço por jogador, ou um Touched por máquina, significaria conexões
	  sobrando a cada respawn — e é justamente o tipo de vazamento que o
	  tools/audit.py procura.
	- O pagamento é `poderPorClique × Rate × tempo`, então o treino acompanha
	  todos os multiplicadores do jogador sem ter número próprio: nunca vira
	  uma segunda economia.
	- O servidor decide tudo: posição do personagem, requisito de
	  Renascimentos (TrainingLogic.CanTrain com Stats.Rebirths) e quanto
	  pagar. O cliente só lê o atributo "Training" para mostrar o aviso.
	- Quem pisa num alvo bloqueado não ganha nada e recebe UMA vez por
	  entrada o aviso "Você precisa de X Renascimentos para treinar aqui."
	  (Notify "TrainingLocked"); sair e voltar avisa de novo.
	- O ganho é limitado por TrainingConfig.MaxShareOfHoldClick, para que uma
	  config errada não possa pagar mais que o clique ativo.

	Dados: nada é persistido. Treino é renda, não progresso.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Logger = require(Shared.Utils.Logger)
local Signal = require(Shared.Utils.Signal)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local TrainingConfig = require(Shared.Config.TrainingConfig)
local TrainingLogic = require(Shared.Formulas.TrainingLogic)

local DataService = require(script.Parent.DataService)
local CurrencyService = require(script.Parent.CurrencyService)
local PowerService = require(script.Parent.PowerService)
local WorldService = require(script.Parent.WorldService)
local LobbyConfig = require(Shared.Config.LobbyConfig)
local WallConfig = require(Shared.Config.WallConfig)
local NetService = require(script.Parent.NetService)

type Station = TrainingConfig.Station

local ATTRIBUTE = "Training"
local RATE_ATTRIBUTE = "TrainingRate"

local log = Logger.new("Training")

local TrainingService = {
	-- (player, stationId, power)
	Trained = Signal.new() :: Signal.Signal<Player, string, number>,
}

-- Highest rate the economy allows, whatever the config says.
local MAX_RATE = EconomyConfig.Click.HoldClicksPerSecond * TrainingConfig.MaxShareOfHoldClick

local function rateOf(station: Station): number
	return math.min(station.Rate, MAX_RATE)
end

-- Centro da área de treino no mundo.
local function areaCentre(): Vector3?
	local origin = WorldService.OriginOf(WallConfig.WorldId)
	local area = LobbyConfig.Areas[TrainingConfig.Area]
	if not origin or not area then
		return nil
	end
	return origin + area.Offset
end

-- Último alvo bloqueado em que o jogador pisou (para avisar uma vez só).
local lockedNotice: { [Player]: string } = {}

local function characterState(player: Player): (Vector3?, boolean)
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		return nil, false
	end
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local grounded = true
	if humanoid and humanoid:IsA("Humanoid") then
		local state = humanoid:GetState()
		grounded = state ~= Enum.HumanoidStateType.Freefall and state ~= Enum.HumanoidStateType.Jumping
	end
	return root.Position, grounded
end

-- The station this player is in, if any, and whether they may train there
-- right now (requirement met and, when required, standing on the ground).
-- A jump inside a locked station keeps the station, so the notice is not
-- repeated on every jump.
local function stationFor(player: Player, rebirths: number): (Station?, boolean, boolean)
	local position, grounded = characterState(player)
	local centre = areaCentre()
	if not position or not centre then
		return nil, false, false
	end
	local station = TrainingLogic.StationAt(centre, position)
	if not station then
		return nil, false, false
	end
	local standing = grounded or not TrainingConfig.RequireGrounded
	return station, TrainingLogic.CanTrain(station, rebirths), standing
end

local function clear(player: Player)
	if player:GetAttribute(ATTRIBUTE) ~= nil then
		player:SetAttribute(ATTRIBUTE, nil)
		player:SetAttribute(RATE_ATTRIBUTE, nil)
	end
end

local function tick(dt: number)
	for _, player in Players:GetPlayers() do
		local data = DataService.GetData(player)
		if not data then
			continue
		end
		local station, allowed, standing = stationFor(player, data.Stats.Rebirths)
		if not station or not allowed or not standing then
			clear(player)
			if station and not allowed and standing and lockedNotice[player] ~= station.Id then
				lockedNotice[player] = station.Id
				NetService.FireClient("Notify", player, "TrainingLocked", {
					Station = station.Id,
					Rebirths = TrainingLogic.Required(station),
				})
			elseif not station or allowed then
				lockedNotice[player] = nil
			end
			continue
		end
		lockedNotice[player] = nil
		local info = PowerService.GetInfo(player)
		if not info then
			continue
		end
		local rate = rateOf(station)
		local amount = info.PerClick * rate * dt
		if amount <= 0 then
			continue
		end
		local granted = CurrencyService.Add(player, "Power", amount, "Training:" .. station.Id)
		-- Mirrored for the HUD: which machine and how much per second.
		player:SetAttribute(ATTRIBUTE, station.Id)
		player:SetAttribute(RATE_ATTRIBUTE, info.PerClick * rate)
		TrainingService.Trained:Fire(player, station.Id, granted)
	end
end

function TrainingService.Init()
	Players.PlayerRemoving:Connect(function(player)
		lockedNotice[player] = nil
		player:SetAttribute(ATTRIBUTE, nil)
		player:SetAttribute(RATE_ATTRIBUTE, nil)
	end)
end

function TrainingService.Start()
	log:Info(string.format("%d machines, cap %.2f clicks/s", #TrainingConfig.Stations, MAX_RATE))
	task.spawn(function()
		while true do
			local dt = task.wait(TrainingConfig.TickSeconds)
			tick(dt)
		end
	end)
end

return TrainingService
