--[[
	check_zones.luau — zonas dormentes não dão bônus.

		lune run tools/lune/check_zones.luau [raiz]

	O ZoneService REAL com um jogador parado no centro da 1ª zona (requisitos
	cumpridos). Com ZoneConfig.Build = false (o jogo de hoje) a camada "Zone"
	tem de ser ×1 e o jogador não fica "em" zona nenhuma. Controle: num
	ambiente separado com Build = true a mesma posição dá o multiplicador da
	zona — prova que o teste enxerga o bônus quando ele existe.

	Adaptação SÓ AQUI: `.Position` vira `.CFrame.Position` (o Lune não expõe
	BasePart.Position).
]]
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")
local Signal = nil

local problems = {}
local function check(condition: any, message: string)
	if condition then
		print("OK   " .. message)
	else
		table.insert(problems, message)
		print("FALHA " .. message)
	end
end

-- Monta um servidor com o ZoneService real; devolve (provider, GetZone, zona).
local function server(build: boolean)
	local E = require("./env")(process.args[1])
	Signal = Signal or E.require(E.Shared.Utils.Signal)
	local ZoneConfig = E.require(E.Shared.Config.ZoneConfig)
	ZoneConfig.Build = build
	local ZoneRules = E.require(E.Shared.Formulas.ZoneRules)
	local zone = ZoneRules.ForWorld("Training")[1]

	local character = roblox.Instance.new("Model")
	local root = roblox.Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.CFrame = roblox.CFrame.new(zone.Offset + roblox.Vector3.new(0, ZoneConfig.PlatformHeight + 3, 0))
	root.Parent = character
	local player = { UserId = 1, Name = "P1", Character = character }

	local provider = nil
	E.stubs.Players = { GetPlayers = function()
		return { player }
	end, PlayerRemoving = Signal.new(), PlayerAdded = Signal.new() }
	E.stubModules["ServerScriptService.Server.Services.PowerService"] = {
		RegisterProvider = function(layer, fn)
			if layer == "Zone" then
				provider = fn
			end
		end,
		Invalidate = function() end,
	}
	E.stubModules["ServerScriptService.Server.Services.DataService"] = {
		GetData = function()
			return { Worlds = { Current = "Training" }, Stats = { TotalPowerEarned = 1e30, Rebirths = 999 } }
		end,
	}
	E.stubModules["ServerScriptService.Server.Services.NetService"] = { FireClient = function() end }
	E.stubModules["ServerScriptService.Server.Services.WorldService"] = {
		OriginOf = function()
			return roblox.Vector3.new(0, 0, 0)
		end,
	}
	E.patches["ServerScriptService.Server.Services.ZoneService"] = {
		{ "root.Position", "root.CFrame.Position", "all" },
	}
	local ZoneService = E.require(E.Server.Services.ZoneService)
	ZoneService.Init()
	ZoneService.Start()
	task.wait(ZoneConfig.CheckIntervalSeconds * 3)
	return provider, ZoneService.GetZone, zone, player
end

local provider, getZone, zone, player = server(false)
check(provider ~= nil, "a camada Zone continua registrada (o PowerFormula espera a camada)")
check(provider(player, {}) == 1, string.format("Build = false: no centro de %s com tudo liberado, camada Zone = ×1", zone.Id))
check(getZone(player) == nil, "Build = false: o jogador não fica 'em' zona nenhuma")

local providerOn, getZoneOn, zoneOn, playerOn = server(true)
check(providerOn(playerOn, {}) == zoneOn.Multiplier and getZoneOn(playerOn) == zoneOn.Id,
	string.format("controle: com Build = true a mesma posição dá ×%s (o teste enxerga o bônus)", tostring(zoneOn.Multiplier)))

print("")
if #problems > 0 then
	print(string.format("FALHOU: %d verificação(ões)", #problems))
	process.exit(1)
end
print("OK: zonas dormentes (Build = false) não dão multiplicador pela posição.")
process.exit(0)
