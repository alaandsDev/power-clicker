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
	- O servidor decide tudo: posição do personagem, requisito de vitórias e
	  quanto pagar. O cliente só lê o atributo "Training" para mostrar o aviso.
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

local DataService = require(script.Parent.DataService)
local CurrencyService = require(script.Parent.CurrencyService)
local PowerService = require(script.Parent.PowerService)
local WorldService = require(script.Parent.WorldService)
local LobbyConfig = require(Shared.Config.LobbyConfig)
local WallConfig = require(Shared.Config.WallConfig)

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

-- World position of a station (the lobby area plus its local offset).
local function stationCentre(station: Station): Vector3?
	local origin = WorldService.OriginOf(WallConfig.WorldId)
	local area = LobbyConfig.Areas[TrainingConfig.Area]
	if not origin or not area then
		return nil
	end
	return origin + area.Offset + station.Local
end

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

-- The station this player is standing on, if any (and if they qualify for it).
local function stationFor(player: Player, wins: number): Station?
	local position, grounded = characterState(player)
	if not position then
		return nil
	end
	if TrainingConfig.RequireGrounded and not grounded then
		return nil
	end
	for _, station in TrainingConfig.Stations do
		local centre = stationCentre(station)
		if centre and wins >= station.RequiredWins then
			local flat = (position - centre) * Vector3.new(1, 0, 1)
			-- Height matters too: standing under or over the pad is not training.
			if flat.Magnitude <= station.Radius and math.abs(position.Y - centre.Y) <= 14 then
				return station
			end
		end
	end
	return nil
end

local function tick(dt: number)
	for _, player in Players:GetPlayers() do
		local data = DataService.GetData(player)
		if not data then
			continue
		end
		local station = stationFor(player, data.Currencies.Wins)
		if not station then
			if player:GetAttribute(ATTRIBUTE) ~= nil then
				player:SetAttribute(ATTRIBUTE, nil)
				player:SetAttribute(RATE_ATTRIBUTE, nil)
			end
			continue
		end
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
