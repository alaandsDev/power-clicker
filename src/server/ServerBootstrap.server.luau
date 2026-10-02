--!strict
--[[
	ServerBootstrap
	The ONLY server Script. Boots the game in a deterministic order:

	1. Freeze configs (runtime mutation of config is a bug).
	2. Validate configs (broken references abort the boot in Studio).
	3. Init() every service in SERVICE_ORDER (wiring only, must not yield).
	4. Start() every service in SERVICE_ORDER (may spawn loops).
	5. Studio only: run unit tests.

	To add a service: create Services/<Name>.luau exposing Init/Start and add
	its name to SERVICE_ORDER after every service it depends on.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Logger = require(Shared.Utils.Logger)
local TableUtil = require(Shared.Utils.TableUtil)
local ConfigValidator = require(Shared.Formulas.ConfigValidator)
local Try = require(Shared.Utils.Try)
local GameConfig = require(Shared.Config.GameConfig)

local Server = script.Parent
local Services = Server.Services
local ServerConfig = Server.ServerConfig
local DevConfig = require(ServerConfig.DevConfig)
local DataTemplate = require(Services.DataService.DataTemplate)

local log = Logger.new("Bootstrap")

local SERVICE_ORDER = {
	"AntiExploitService", -- no deps
	"NetService", -- AntiExploitService
	"DataService", -- NetService
	"CurrencyService", -- DataService
	"PowerService", -- NetService, DataService
	"OverdriveService", -- PowerService
	"PetService", -- DataService, PowerService
	"EggService", -- CurrencyService, PetService
	"WorldService", -- CurrencyService, PowerService
	"PickupService", -- CurrencyService, PowerService, WorldService (power orbs)
	"BossService", -- CurrencyService, PowerService, BoostService, WorldService
	"ZoneService", -- PowerService (Zone layer), WorldService
	"TargetService", -- CurrencyService, NetService (zone targets)
	"WallService", -- CurrencyService, WorldService (win corridor)
	"ClickService", -- CurrencyService, PowerService, OverdriveService, AntiExploitService, ZoneService, TargetService, WallService
	"CutService", -- CurrencyService, PowerService (flat damage pads)
	"TrainingService", -- CurrencyService, PowerService, WorldService (lobby machines)
	"SwordService", -- DataService (cosmetic blade; unlocks follow progression)
	"AuraSkinService", -- DataService (cosmetic aura; no power provider on purpose)
	"UpgradeService", -- CurrencyService, PowerService
	"RebirthService", -- CurrencyService, PowerService
	"BoostService", -- PowerService, EggService (providers)
	"RewardService", -- CurrencyService, PetService, BoostService
	"DailyRewardService", -- RewardService
	"QuestService", -- RewardService + gameplay signals
	"AchievementService", -- RewardService + gameplay signals
	"CodeService", -- RewardService
	"SocialService", -- PowerService (Social layer), RewardService (group gift)
	"SeasonService", -- RewardService, QuestService, DailyRewardService, SessionService, BossService, TargetService
	"MonetizationService", -- RewardService, PetService, ClickService, OverdriveService
	"SessionService", -- PowerService (Event layer), RewardService (playtime chests)
	"CosmeticService", -- DataService, RebirthService, ZoneService (visual status)
	"AuraService", -- CurrencyService, PowerService (Aura layer), CosmeticService (ring)
	"RuneService", -- PowerService (Rune layer), BossService (drops)
	"LeaderboardService", -- DataService, CurrencyService
	"SettingsService", -- DataService
	"DebugService", -- all of the above (dev tool, AdminConfig-gated)
}

type Service = { Init: (() -> ())?, Start: (() -> ())? }

local isStudio = RunService:IsStudio()
local bootStart = os.clock()

-- 1. Freeze configs
for _, container in { Shared.Config, ServerConfig } do
	for _, module in container:GetChildren() do
		if module:IsA("ModuleScript") then
			TableUtil.DeepFreeze(require(module) :: any)
		end
	end
end

-- 2. Validate configs
do
	local bundle = ConfigValidator.LoadBundle()
	bundle.StatKeys = DataTemplate.StatKeys()
	local errors = ConfigValidator.Validate(bundle)
	if #errors > 0 then
		for _, message in errors do
			log:Error("Config:", message)
		end
		if isStudio and DevConfig.FailBootOnConfigErrorsInStudio then
			error(string.format("Boot aborted: %d config error(s). See output above.", #errors))
		end
	else
		log:Info("Configs valid")
	end
end

-- 3/4. Services
local services: { { Name: string, Module: Service } } = {}
for _, name in SERVICE_ORDER do
	local module = Services:FindFirstChild(name)
	assert(module and module:IsA("ModuleScript"), "Service not found: " .. name)
	table.insert(services, { Name = name, Module = require(module) :: any })
end

for _, entry in services do
	local init = entry.Module.Init
	if init then
		local ok, err = Try.Call(init)
		if not ok then
			-- A service that fails to init leaves the game in an unknown state: stop.
			error(string.format("Init failed for %s: %s", entry.Name, tostring(err)))
		end
	end
end

for _, entry in services do
	local start = entry.Module.Start
	if start then
		local ok, err = Try.Call(start)
		if not ok then
			error(string.format("Start failed for %s: %s", entry.Name, tostring(err)))
		end
	end
end

log:Info(string.format("%s %s booted %d services in %.1f ms", GameConfig.GameName, GameConfig.BuildVersion, #services, (os.clock() - bootStart) * 1000))

-- 5. Tests (Studio only)
if isStudio and DevConfig.RunTestsInStudio then
	task.spawn(function()
		local TestRunner = require(Server.Tests.TestRunner)
		TestRunner.RunAll(Server.Tests)
	end)
end
