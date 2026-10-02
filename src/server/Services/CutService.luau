--!strict
--[[
	CutService
	The cut pads in front of the spawn: buying raw damage per click.

	There is no remote. The pads carry a ProximityPrompt built by WorldBuilder,
	and ProximityPromptService.PromptTriggered is a SERVER event — the player
	pressing E is reported by Roblox itself, so the price, the wins requirement
	and the ownership are all checked here with nothing the client can forge.

	Owning is using: the best cut a player owns feeds the flat part of
	PowerFormula (PowerService base provider), so there is nothing to equip.

	The blade the player carries is NOT here: the look comes from the cosmetic
	skin (SwordConfig/SwordService). The cut is the damage; the sword is how it
	looks. Keeping them apart is what stops a rare blade from becoming a
	requirement to progress.

	Pads come from WorldBuilder with the prompt attribute:
		CutId = "<cut id>"
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Logger = require(Shared.Utils.Logger)
local Signal = require(Shared.Utils.Signal)
local CutConfig = require(Shared.Config.CutConfig)
local CutLogic = require(Shared.Formulas.CutLogic)

local NetService = require(script.Parent.NetService)
local DataService = require(script.Parent.DataService)
local CurrencyService = require(script.Parent.CurrencyService)
local PowerService = require(script.Parent.PowerService)

type PlayerData = Types.PlayerData

local ATTRIBUTE = "BestCut"

local log = Logger.new("Cuts")

local CutService = {
	-- (player, cutId)
	Bought = Signal.new() :: Signal.Signal<Player, string>,
}

--[[
	Mirrors the best cut owned on the player. The LOOK of the blade is
	SwordService's job (cosmetic skins); this attribute is the damage tier, read
	by the HUD and by the pads.
]]
local function publish(player: Player, data: PlayerData)
	player:SetAttribute(ATTRIBUTE, CutLogic.Best(data.Cuts).Id)
end

local function buy(player: Player, cutId: string)
	local data = DataService.GetData(player)
	if not data then
		return
	end
	local allowed, code = CutLogic.CanBuy(data.Cuts, cutId, data.Currencies.Wins)
	if not allowed then
		NetService.FireClient("Notify", player, "CutRefused", { CutId = cutId, Code = code })
		return
	end
	local cut = CutConfig.Cuts[cutId]
	if not CurrencyService.Remove(player, CutConfig.Currency, cut.Price, "Cut:" .. cutId) then
		NetService.FireClient("Notify", player, "CutRefused", { CutId = cutId, Code = "NotEnoughCurrency" })
		return
	end
	data.Cuts.Owned[cutId] = true
	DataService.MarkChanged(player, "Cuts")
	PowerService.Invalidate(player)
	publish(player, data)
	NetService.FireClient("Notify", player, "CutBought", { CutId = cutId, Flat = cut.Flat })
	CutService.Bought:Fire(player, cutId)
	log:Info(string.format("user=%d bought %s for %.0f", player.UserId, cutId, cut.Price))
end

function CutService.Init()
	PowerService.RegisterBaseProvider("Cut", function(_player, data)
		return CutLogic.FlatBonus(data.Cuts)
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		local cutId = prompt:GetAttribute("CutId")
		if type(cutId) == "string" then
			buy(player, cutId)
		end
	end)

	DataService.PlayerLoaded:Connect(function(player: Player, data: PlayerData)
		local fixes = CutLogic.Sanitize(data.Cuts)
		if fixes > 0 then
			log:Warn(string.format("user=%d repaired %d cut issue(s)", player.UserId, fixes))
			DataService.MarkChanged(player, "Cuts")
		end
		publish(player, data)
	end)
	DataService.DataReset:Connect(publish)

	Players.PlayerRemoving:Connect(function(player)
		player:SetAttribute(ATTRIBUTE, nil)
	end)
end

function CutService.Start()
	for _, player in Players:GetPlayers() do
		local data = DataService.GetData(player)
		if data then
			publish(player, data)
		end
	end
end

return CutService
