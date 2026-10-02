--!strict
--[[
	RebirthService
	"Rebirth"() → RebirthLogic.Perform (requirement check, reset, reward) on
	the server. The client sends nothing but the request.

	Responses: { Ok = true, Data = { Rebirths, Gems } }
	           { Ok = false, Code = "MaxRebirths" | "NotEnoughCurrency" }
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Guard = require(Shared.Utils.Guard)
local Logger = require(Shared.Utils.Logger)
local Signal = require(Shared.Utils.Signal)

local NetService = require(script.Parent.NetService)
local DataService = require(script.Parent.DataService)
local CurrencyService = require(script.Parent.CurrencyService)
local PowerService = require(script.Parent.PowerService)
local RebirthLogic = require(script.Parent.Parent.Logic.RebirthLogic)

type RemoteResponse = Types.RemoteResponse

local log = Logger.new("Rebirth")

local RebirthService = {
	-- (player, totalRebirths, gemsGranted)
	Rebirthed = Signal.new() :: Signal.Signal<Player, number, number>,
}

function RebirthService.Perform(player: Player): RemoteResponse
	local data = DataService.GetData(player)
	if not data then
		return { Ok = false, Code = "NotReady" }
	end
	local ok, code, result = RebirthLogic.Perform(data)
	if not ok or not result then
		return { Ok = false, Code = code or "NotEnoughCurrency" }
	end

	for _, key in { "Upgrades", "Overdrive", "Stats" } do
		DataService.MarkChanged(player, key)
	end
	CurrencyService.NotifyChanged(player, "Power", 0, "Rebirth")
	CurrencyService.NotifyChanged(player, "Gems", result.Gems, "Rebirth")
	PowerService.Invalidate(player)

	log:Info(string.format("user=%d rebirth #%d (+%d gems)", player.UserId, result.Rebirths, result.Gems))
	NetService.FireClient("Notify", player, "Rebirth", { Rebirths = result.Rebirths, Gems = result.Gems })
	RebirthService.Rebirthed:Fire(player, result.Rebirths, result.Gems)
	return { Ok = true, Data = { Rebirths = result.Rebirths, Gems = result.Gems } }
end

function RebirthService.Init()
	NetService.OnInvoke("Rebirth", Guard.Args(), RebirthService.Perform)
end

return RebirthService
