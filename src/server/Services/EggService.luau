--!strict
--[[
	EggService
	"HatchEgg"(eggId) → EggLogic.Hatch with a SERVER Random. The client only
	names the egg; price, luck, roll and result are all decided here.

	Luck = (1 + permanent Luck upgrades) × Π(luck providers), capped by
	EggConfig.MaxLuckMultiplier. Boosts/passes (Phase 6) register providers:
		EggService.RegisterLuckProvider("Luck2x", function(player) return 2 end)

	Rare hatches (rarity.Announce) are broadcast to the server via Notify.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Guard = require(Shared.Utils.Guard)
local Logger = require(Shared.Utils.Logger)
local Signal = require(Shared.Utils.Signal)
local EggConfig = require(Shared.Config.EggConfig)
local PetConfig = require(Shared.Config.PetConfig)
local EggOdds = require(Shared.Formulas.EggOdds)

local NetService = require(script.Parent.NetService)
local DataService = require(script.Parent.DataService)
local CurrencyService = require(script.Parent.CurrencyService)
local PetService = require(script.Parent.PetService)
local EggLogic = require(script.Parent.Parent.Logic.EggLogic)
local UpgradeLogic = require(script.Parent.Parent.Logic.UpgradeLogic)

type RemoteResponse = Types.RemoteResponse
type LuckProvider = (player: Player) -> number

local log = Logger.new("Eggs")

local EggService = {
	-- (player, petId, rarity, eggId)
	Hatched = Signal.new() :: Signal.Signal<Player, string, string, string>,
}

local rng = Random.new()
local luckProviders: { [string]: LuckProvider } = {}
local lastHatch: { [Player]: number } = {}

function EggService.RegisterLuckProvider(name: string, provider: LuckProvider)
	assert(not luckProviders[name], "Luck provider already registered: " .. name)
	luckProviders[name] = provider
end

function EggService.GetLuck(player: Player): number
	local data = DataService.GetData(player)
	if not data then
		return 1
	end
	local luck = 1 + UpgradeLogic.GetEffect(data, "Permanent", "LuckMultiplier")
	for name, provider in luckProviders do
		local ok, value = pcall(provider, player)
		if ok and type(value) == "number" and value == value and value >= 1 then
			luck *= value
		elseif not ok then
			log:Error("Luck provider failed:", name, value)
		end
	end
	return EggOdds.ClampLuck(luck)
end

local function hatch(player: Player, eggId: string): RemoteResponse
	local data = DataService.GetData(player)
	if not data then
		return { Ok = false, Code = "NotReady" }
	end
	local now = os.clock()
	local last = lastHatch[player]
	if last and now - last < EggConfig.HatchCooldownSeconds then
		return { Ok = false, Code = "RateLimited" }
	end
	lastHatch[player] = now

	local ok, code, result = EggLogic.Hatch(data, eggId, EggService.GetLuck(player), function()
		return rng:NextNumber()
	end, os.time())
	if not ok or not result then
		return { Ok = false, Code = code }
	end

	CurrencyService.NotifyChanged(player, result.Currency :: any, -result.Price, "Egg:" .. eggId)
	DataService.MarkChanged(player, "Stats")
	PetService.NotifyChanged(player)

	log:Debug(string.format("user=%d hatched %s (%s) from %s", player.UserId, result.PetId, result.Rarity, eggId))
	local rarity = PetConfig.Rarities[result.Rarity]
	if rarity and rarity.Announce then
		NetService.FireAllClients("Notify", "RareHatch", { Player = player.DisplayName, UserId = player.UserId, PetId = result.PetId, Rarity = result.Rarity })
	end
	EggService.Hatched:Fire(player, result.PetId, result.Rarity, eggId)
	return { Ok = true, Data = result }
end

-- Publishes each player's effective luck as an attribute (display only),
-- every 2 s and only when it changed.
function EggService.Start()
	task.spawn(function()
		while true do
			task.wait(2)
			for _, player in Players:GetPlayers() do
				if DataService.IsLoaded(player) then
					local luck = EggService.GetLuck(player)
					if player:GetAttribute("Luck") ~= luck then
						player:SetAttribute("Luck", luck)
					end
				end
			end
		end
	end)
end

function EggService.Init()
	NetService.OnInvoke("HatchEgg", Guard.Args(Guard.KeyOf(EggConfig.Eggs)), hatch)
	Players.PlayerRemoving:Connect(function(player)
		lastHatch[player] = nil
	end)
end

return EggService
