--!strict
--[[
	PowerService
	Builds the inputs of PowerFormula for a player and caches the result.

		PowerPerClick = (BasePowerPerClick + ClickPowerFlat upgrades + flat providers)
		              × Upgrade × Rebirth × World × Permanent   (built in here)
		              × Pet × GamePass × TemporaryBoost × Overdrive (providers)
		              × Combo                                   (per click)

	Systems that add FLAT damage (the cut pads) register a base provider:
		PowerService.RegisterBaseProvider("Cut", function(player, data) return 5 end)
	and systems that multiply register a PROVIDER for their layer instead of
	multiplying anywhere themselves:
		PowerService.RegisterProvider("Overdrive", function(player, data) return 3 end)
	and call PowerService.Invalidate(player) whenever their value changes.

	The cache is recomputed lazily; the client gets a PowerInfo push (batched)
	after every invalidation, for display only.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Logger = require(Shared.Utils.Logger)
local GameConfig = require(Shared.Config.GameConfig)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local WorldConfig = require(Shared.Config.WorldConfig)
local EconomyFormulas = require(Shared.Formulas.EconomyFormulas)
local PowerFormula = require(Shared.Formulas.PowerFormula)
local WorldRules = require(Shared.Formulas.WorldRules)

local NetService = require(script.Parent.NetService)
local DataService = require(script.Parent.DataService)
local UpgradeLogic = require(script.Parent.Parent.Logic.UpgradeLogic)
local RebirthLogic = require(script.Parent.Parent.Logic.RebirthLogic)

type PlayerData = Types.PlayerData
type Provider = (player: Player, data: PlayerData) -> number

export type PowerInfo = {
	PerClick: number, -- before combo
	Base: number,
	Total: number, -- product of all layers
	Layers: { [string]: number },
}

local BUILT_IN_LAYERS = { Upgrade = true, Rebirth = true, World = true, Permanent = true, Combo = true }

local log = Logger.new("Power")

local PowerService = {}

local providers: { [string]: Provider } = {}
local baseProviders: { [string]: Provider } = {}
local cache: { [Player]: PowerInfo } = {}
local pendingPush: { [Player]: boolean } = {}
local lastProblemLog: { [string]: number } = {}
-- SÓ NO STUDIO (DebugService "ColossusHits"): golpe fixo para testar a UX.
local debugPerClick: { [Player]: number } = {}

function PowerService.RegisterProvider(layer: string, provider: Provider)
	assert(PowerFormula.IsKnownLayer(layer), "Unknown multiplier layer (add it to EconomyConfig.MultiplierLayers): " .. layer)
	assert(not BUILT_IN_LAYERS[layer], "Layer is computed by PowerService itself: " .. layer)
	assert(not providers[layer], "Provider already registered for " .. layer)
	providers[layer] = provider
end

--[[
	Flat damage added to the base, before any multiplier. `name` is for the
	error log only — flat providers simply sum, they have no layer in the
	formula.
]]
function PowerService.RegisterBaseProvider(name: string, provider: Provider)
	assert(not baseProviders[name], "Base provider already registered for " .. name)
	baseProviders[name] = provider
end

local function worldMultiplier(data: PlayerData): number
	local world = WorldConfig.Worlds[data.Worlds.Current]
	if world and WorldRules.IsEnabled(world) and data.Worlds.Unlocked[world.Id] then
		return world.Multiplier
	end
	return 1
end

local function compute(player: Player, data: PlayerData): PowerInfo
	local base = EconomyConfig.Click.BasePowerPerClick + UpgradeLogic.GetEffect(data, "Temporary", "ClickPowerFlat")
	for name, provider in baseProviders do
		local ok, value = pcall(provider, player, data)
		if ok and type(value) == "number" and value == value and value >= 0 and value < math.huge then
			base += value
		elseif not ok then
			log:Error("Base provider failed:", name, value)
		end
	end
	local layers: { [string]: number } = {
		Upgrade = 1 + UpgradeLogic.GetEffect(data, "Temporary", "PowerMultiplier"),
		Permanent = 1 + UpgradeLogic.GetEffect(data, "Permanent", "PowerMultiplier"),
		Rebirth = EconomyFormulas.RebirthMultiplier(RebirthLogic.GetRebirths(data)),
		World = worldMultiplier(data),
	}
	for layer, provider in providers do
		local ok, value = pcall(provider, player, data)
		layers[layer] = if ok then value else 1
		if not ok then
			log:Error("Provider failed:", layer, value)
		end
	end

	local perClick, total, problems = PowerFormula.Compute(base, layers)
	local override = debugPerClick[player]
	if override then
		perClick = override
		total = if base > 0 then override / base else total
	end
	if #problems > 0 then
		local key = table.concat(problems, ";")
		local now = os.clock()
		if not lastProblemLog[key] or now - lastProblemLog[key] > 60 then
			lastProblemLog[key] = now
			log:Error("PowerFormula ignored invalid inputs:", key)
		end
	end
	return { PerClick = perClick, Base = base, Total = total, Layers = layers }
end

-- Current power info (without combo). nil if data is not loaded.
function PowerService.GetInfo(player: Player): PowerInfo?
	local cached = cache[player]
	if cached then
		return cached
	end
	local data = DataService.GetData(player)
	if not data then
		return nil
	end
	local info = compute(player, data)
	cache[player] = info
	return info
end

-- Power for one click with the given combo multiplier (1 = no combo).
function PowerService.ComputeClick(player: Player, comboMultiplier: number): number
	local info = PowerService.GetInfo(player)
	if not info then
		return 0
	end
	local combo = if comboMultiplier == comboMultiplier and comboMultiplier >= 1 then comboMultiplier else 1
	return math.min(info.PerClick * combo, GameConfig.Numbers.MaxValue)
end

--[[
	FERRAMENTA DE TESTE, SÓ NO STUDIO: fixa o Poder por clique (= dano do
	golpe, antes do combo) deste jogador; nil volta à fórmula. Recusa fora do
	Studio. Não é salvo; some ao sair.
]]
function PowerService.SetDebugPerClick(player: Player, value: number?): boolean
	if not RunService:IsStudio() then
		log:Error("SetDebugPerClick refused outside Studio")
		return false
	end
	debugPerClick[player] = if value and value > 0 and value < math.huge then value else nil
	PowerService.Invalidate(player)
	return true
end

-- Call whenever anything feeding the formula changes.
function PowerService.Invalidate(player: Player)
	cache[player] = nil
	pendingPush[player] = true
end

function PowerService.Init()
	DataService.PlayerReady:Connect(PowerService.Invalidate)
	DataService.DataReset:Connect(PowerService.Invalidate)
	Players.PlayerRemoving:Connect(function(player)
		cache[player] = nil
		pendingPush[player] = nil
		debugPerClick[player] = nil
	end)
end

function PowerService.Start()
	task.spawn(function()
		while true do
			task.wait(GameConfig.Replication.FlushIntervalSeconds)
			for player in pendingPush do
				pendingPush[player] = nil
				local info = PowerService.GetInfo(player)
				if info then
					NetService.FireClient("PowerInfo", player, info)
				end
			end
		end
	end)
end

return PowerService
