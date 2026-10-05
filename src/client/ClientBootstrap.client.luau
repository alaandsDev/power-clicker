--!strict
--[[
	ClientBootstrap
	Single client entry point. Initializes controllers in a fixed order:
	Init() for all (wiring, no yields), then Start() for all.
	Controllers are presentation/input only — no economy logic lives here.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Logger = require(Shared:WaitForChild("Utils"):WaitForChild("Logger"))
local TableUtil = require(Shared:WaitForChild("Utils"):WaitForChild("TableUtil"))
local Try = require(Shared:WaitForChild("Utils"):WaitForChild("Try"))
local NumberFormat = require(Shared:WaitForChild("Utils"):WaitForChild("NumberFormat"))
local Text = require(Shared:WaitForChild("Localization"))

local log = Logger.new("ClientBootstrap")

local Controllers = script.Parent:WaitForChild("Controllers")

-- Order matters: later controllers may depend on earlier ones.
local CONTROLLER_ORDER = {
	"DataController", -- replicated data (must connect before ClientReady)
	"UIController", -- root ScreenGui + scaling
	"SoundController",
	"NotificationController",
	"GameStateController", -- power info, overdrive, combo mirror
	"MenuController",
	"HudController",
	"BuffController", -- active buffs as compact chips beside the currencies
	"SwordController", -- cosmetic blade skins
	"SwordSwingController", -- the character swings the blade on every hit (procedural)
	"SlashController", -- the cut arc in front of the character
	"CutShowcaseController", -- cut pads: orb, live demo of the cut, per-player card
	"ClickController",
	"AutoClickController", -- AUTO on/off (or the pass offer) beside the CLICK button
	"UpgradeController",
	"RebirthController",
	"PetController",
	"EggController",
	"WorldController",
	"TowerController", -- progresso do corredor (substitui Mundos no menu)
	"ZoneController", -- training zones + target HP bars
	"TrainingController", -- "treinando" chip while on a machine
	"WallController", -- win corridor: row HP bars and stage signs
	"CorridorHudController", -- stage/damage strip while at a barrier
	"CombatFxController", -- impact, cracks, break, camera and damage numbers at the barriers
	"EventController", -- world boss bar + orb notices
	"RewardsController",
	"QuestController",
	"SeasonController", -- season pass panel
	"LeaderboardController",
	"ScoreboardController", -- 3D boards; needs LeaderboardController
	"AuraController", -- auras: speed + power
	"RuneController", -- boss rune drops and slots
	"ShopController",
	"VipController",
	"SettingsController",
	"WorldAmbientController", -- per-world lighting (client only)
	"StationFxController", -- lobby station machines: core spin, rings, rising arrows, technician
	"TrainingFieldController", -- training field: padlock per player, dummies react to whoever trains
	"SpawnCameraController", -- aims the camera along the spawn marker after the server teleport
	"InteractController", -- world stations (ProximityPrompts) open panels
	"TutorialController", -- must come after every controller that adds menu buttons
	"PetFollowController", -- world visuals of equipped pets (all players)
	"DebugController", -- Studio/admin only (server decides)
}

-- Number separators follow the player's language (pt-BR: "2,54K").
do
	local separators = Text.Separators(game:GetService("Players").LocalPlayer.LocaleId)
	NumberFormat.SetSeparators(separators.Decimal, separators.Thousands)
end

-- Configs are read-only at runtime.
for _, module in Shared:WaitForChild("Config"):GetChildren() do
	if module:IsA("ModuleScript") then
		-- Dynamic require (path unknown to the type checker): intentional.
		TableUtil.DeepFreeze((require :: any)(module))
	end
end

type Controller = { Init: (() -> ())?, Start: (() -> ())? }

local loaded: { { Name: string, Module: Controller } } = {}
for _, name in CONTROLLER_ORDER do
	local module = Controllers:WaitForChild(name) :: ModuleScript
	table.insert(loaded, { Name = name, Module = require(module) :: any })
end

for _, entry in loaded do
	local init = entry.Module.Init
	if init then
		local ok, err = Try.Call(init)
		if not ok then
			log:Error("Init failed:", entry.Name, err)
		end
	end
end

for _, entry in loaded do
	local start = entry.Module.Start
	if start then
		task.spawn(function()
			local ok, err = Try.Call(start)
			if not ok then
				log:Error("Start failed:", entry.Name, err)
			end
		end)
	end
end

log:Info("Client started")
