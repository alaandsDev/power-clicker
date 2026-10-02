--!strict
--[[
	DebugService — DEVELOPMENT TOOL, locked down by AdminConfig.

	Allowed when:
	- Studio and AdminConfig.DebugEnabledInStudio, or
	- live server and AdminConfig.DebugEnabledInLive AND UserId in AdminUserIds.
	Every command re-checks access. Commands go through the normal services
	(CurrencyService, RebirthService...) so they exercise real code paths.
	"ResetData" works in Studio only, regardless of config.

	Future phases add: CreatePet, UnlockWorld, ActivateBoost.
]]

local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Guard = require(Shared.Utils.Guard)
local Logger = require(Shared.Utils.Logger)
local GameConfig = require(Shared.Config.GameConfig)
local PetConfig = require(Shared.Config.PetConfig)
local AuraConfig = require(Shared.Config.AuraConfig)
local RuneConfig = require(Shared.Config.RuneConfig)
local WorldConfig = require(Shared.Config.WorldConfig)
local WorldRules = require(Shared.Formulas.WorldRules)

local AdminConfig = require(script.Parent.Parent.ServerConfig.AdminConfig)
local NetService = require(script.Parent.NetService)
local DataService = require(script.Parent.DataService)
local CurrencyService = require(script.Parent.CurrencyService)
local RebirthService = require(script.Parent.RebirthService)
local OverdriveService = require(script.Parent.OverdriveService)
local ClickService = require(script.Parent.ClickService)
local PetService = require(script.Parent.PetService)
local BoostService = require(script.Parent.BoostService)
local MonetizationService = require(script.Parent.MonetizationService)
local BossService = require(script.Parent.BossService)
local PickupService = require(script.Parent.PickupService)
local AuraService = require(script.Parent.AuraService)
local RuneService = require(script.Parent.RuneService)
local RebirthLogic = require(script.Parent.Parent.Logic.RebirthLogic)

type RemoteResponse = Types.RemoteResponse

local log = Logger.new("Debug")

local COMMANDS = { "AddPower", "AddGems", "AddWins", "Rebirth", "Overdrive", "ToggleAutoClick", "ResetData", "GiveRandomPet", "UnlockWorlds", "AddBoosts", "SkipDay", "TestPasses", "TestStarterPack", "TestGems", "SpawnBoss", "SpawnOrb", "GiveAuras", "GiveRandomRune" }

local DebugService = {}

function DebugService.IsAllowed(player: Player): boolean
	if RunService:IsStudio() then
		return AdminConfig.DebugEnabledInStudio
	end
	return AdminConfig.DebugEnabledInLive and table.find(AdminConfig.AdminUserIds, player.UserId) ~= nil
end

local function run(player: Player, command: string, amount: number?): RemoteResponse
	if not DebugService.IsAllowed(player) then
		log:Warn(string.format("user=%d denied debug command %s", player.UserId, command))
		return { Ok = false, Code = "Forbidden" }
	end
	log:Info(string.format("user=%d %s %s", player.UserId, command, tostring(amount)))

	if command == "AddPower" or command == "AddGems" or command == "AddWins" then
		if not amount then
			return { Ok = false, Code = "AmountRequired" }
		end
		local currency: Types.CurrencyId = if command == "AddPower"
			then "Power"
			elseif command == "AddGems" then "Gems"
			else "Wins"
		local added = CurrencyService.Add(player, currency, amount, "Debug")
		return { Ok = added > 0, Data = { Added = added } }
	elseif command == "Rebirth" then
		-- Tops up exactly the missing Power, then performs a real rebirth.
		local data = DataService.GetData(player)
		if not data then
			return { Ok = false, Code = "NotReady" }
		end
		local missing = RebirthLogic.GetCost(data) - CurrencyService.Get(player, "Power")
		if missing > 0 then
			CurrencyService.Add(player, "Power", missing, "Debug")
		end
		return RebirthService.Perform(player)
	elseif command == "Overdrive" then
		local activated = OverdriveService.Activate(player, "Debug")
		return { Ok = activated, Code = if activated then nil else "AlreadyActive" }
	elseif command == "ToggleAutoClick" then
		local enabled = not ClickService.IsAutoClickEnabled(player)
		ClickService.SetAutoClick(player, enabled)
		return { Ok = true, Data = { Enabled = enabled } }
	elseif command == "GiveRandomPet" then
		local ids = {}
		for id in PetConfig.Pets do
			table.insert(ids, id)
		end
		table.sort(ids)
		local petId = ids[math.random(1, #ids)]
		local ok, code = PetService.Grant(player, petId, "Normal", "Debug")
		return { Ok = ok, Code = code, Data = { PetId = petId } }
	elseif command == "UnlockWorlds" then
		-- Unlocks every ENABLED world for free (requirements are skipped on purpose).
		local data = DataService.GetData(player)
		if not data then
			return { Ok = false, Code = "NotReady" }
		end
		for id, world in WorldConfig.Worlds do
			if WorldRules.IsEnabled(world) then
				data.Worlds.Unlocked[id] = true
			end
		end
		DataService.MarkChanged(player, "Worlds")
		return { Ok = true }
	elseif command == "AddBoosts" then
		BoostService.Add(player, "Power2x", 1, "Debug")
		BoostService.Add(player, "Luck2x", 1, "Debug")
		return { Ok = true }
	elseif command == "SkipDay" then
		-- Moves the last daily claim and the daily-quest period back 24h so the
		-- next day can be tested without waiting (server-side data only).
		local data = DataService.GetData(player)
		if not data then
			return { Ok = false, Code = "NotReady" }
		end
		local day = 24 * 60 * 60
		if data.DailyRewards.LastClaimTime > 0 then
			data.DailyRewards.LastClaimTime -= day
		end
		data.Quests.LastDailyReset -= day
		DataService.MarkChanged(player, "DailyRewards")
		DataService.MarkChanged(player, "Quests")
		return { Ok = true }
	elseif command == "SpawnBoss" then
		return { Ok = BossService.SpawnNow(), Code = "AlreadyActive" }
	elseif command == "GiveAuras" then
		-- Every aura at once: lets the ring, the speed and the layer be compared.
		local granted = 0
		for id in AuraConfig.Auras do
			if AuraService.Grant(player, id, "Debug") then
				granted += 1
			end
		end
		return { Ok = granted > 0, Data = { Granted = granted } }
	elseif command == "GiveRandomRune" then
		local ids = {}
		for id in RuneConfig.Runes do
			table.insert(ids, id)
		end
		table.sort(ids)
		local runeId = ids[math.random(1, #ids)]
		return { Ok = RuneService.Grant(player, runeId, "Debug"), Data = { RuneId = runeId } }
	elseif command == "SpawnOrb" then
		return { Ok = PickupService.SpawnNow(player) }
	elseif command == "TestPasses" then
		return { Ok = MonetizationService.TestGrantAllPasses(player) }
	elseif command == "TestStarterPack" then
		return { Ok = MonetizationService.TestGrantProduct(player, "StarterPack") }
	elseif command == "TestGems" then
		return { Ok = MonetizationService.TestGrantProduct(player, "GemsSmall") }
	elseif command == "ResetData" then
		return { Ok = DataService.ResetForTesting(player) }
	end
	return { Ok = false, Code = "UnknownCommand" }
end

function DebugService.Init()
	NetService.OnInvoke(
		"DebugCommand",
		Guard.Args(Guard.OneOf(COMMANDS), Guard.Optional(Guard.Number(1, GameConfig.Numbers.MaxValue))),
		run
	)
	DataService.PlayerReady:Connect(function(player)
		NetService.FireClient("DebugAccess", player, DebugService.IsAllowed(player))
	end)
end

return DebugService
