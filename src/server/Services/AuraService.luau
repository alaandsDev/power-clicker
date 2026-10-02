--!strict
--[[
	AuraService
	Owns the aura purchase/equip flow, the "Aura" power layer and the walk
	speed that comes with it.

	"AuraAction"(action, auraId) — the server re-checks the price, the rebirth
	requirement and the ownership every time, so a client can neither equip an
	aura it did not buy nor pay the wrong price.

	The equipped aura is mirrored to a player attribute ("EquippedAura") so
	CosmeticService can draw the ring everyone sees, without a second remote.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Guard = require(Shared.Utils.Guard)
local Logger = require(Shared.Utils.Logger)
local AuraConfig = require(Shared.Config.AuraConfig)
local AuraLogic = require(Shared.Formulas.AuraLogic)

local NetService = require(script.Parent.NetService)
local DataService = require(script.Parent.DataService)
local CurrencyService = require(script.Parent.CurrencyService)
local PowerService = require(script.Parent.PowerService)
local CosmeticService = require(script.Parent.CosmeticService)

type RemoteResponse = Types.RemoteResponse
type PlayerData = Types.PlayerData

local ACTIONS = { "Buy", "Equip" }
local ATTRIBUTE = "EquippedAura"

local log = Logger.new("Aura")

local AuraService = {}

-- Applies the equipped aura to the character that is alive right now.
local function applySpeed(player: Player, data: PlayerData)
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.WalkSpeed = AuraLogic.WalkSpeed(data.Auras)
	end
end

local function changed(player: Player, data: PlayerData)
	DataService.MarkChanged(player, "Auras")
	PowerService.Invalidate(player)
	player:SetAttribute(ATTRIBUTE, data.Auras.Equipped)
	applySpeed(player, data)
	CosmeticService.Refresh(player)
end

-- Grants an aura from a trusted server source (reward, product, admin).
function AuraService.Grant(player: Player, auraId: string, source: string): boolean
	local data = DataService.GetData(player)
	if not data or not AuraConfig.Auras[auraId] then
		return false
	end
	if data.Auras.Owned[auraId] then
		return true
	end
	data.Auras.Owned[auraId] = true
	changed(player, data)
	log:Info(string.format("user=%d got aura %s from %s", player.UserId, auraId, source))
	return true
end

local function buy(player: Player, data: PlayerData, auraId: string): RemoteResponse
	local allowed, code = AuraLogic.CanBuy(data.Auras, auraId, data.Currencies.Wins)
	if not allowed then
		return { Ok = false, Code = code }
	end
	local aura = AuraConfig.Auras[auraId]
	if not CurrencyService.Remove(player, AuraConfig.Currency, aura.Price, "Aura:" .. auraId) then
		return { Ok = false, Code = "NotEnoughCurrency" }
	end
	data.Auras.Owned[auraId] = true
	-- Buying equips it: nobody buys an aura to leave it in the drawer.
	AuraLogic.Equip(data.Auras, auraId)
	changed(player, data)
	log:Info(string.format("user=%d bought aura %s for %d", player.UserId, auraId, aura.Price))
	return { Ok = true, Data = { AuraId = auraId, Equipped = true } }
end

local function handleAction(player: Player, action: string, auraId: string): RemoteResponse
	local data = DataService.GetData(player)
	if not data then
		return { Ok = false, Code = "NotReady" }
	end
	if action == "Buy" then
		return buy(player, data, auraId)
	end
	local ok, code = AuraLogic.Equip(data.Auras, auraId)
	if not ok then
		return { Ok = false, Code = code }
	end
	changed(player, data)
	return { Ok = true, Data = { AuraId = auraId, Equipped = true } }
end

function AuraService.Init()
	PowerService.RegisterProvider("Aura", function(_player, data)
		return AuraLogic.Multiplier(data.Auras)
	end)

	NetService.OnInvoke(
		"AuraAction",
		Guard.Args(Guard.OneOf(ACTIONS), Guard.KeyOf(AuraConfig.Auras)),
		handleAction
	)

	DataService.PlayerLoaded:Connect(function(player: Player, data: PlayerData)
		local fixes = AuraLogic.Sanitize(data.Auras)
		if fixes > 0 then
			log:Warn(string.format("user=%d repaired %d aura issue(s)", player.UserId, fixes))
			DataService.MarkChanged(player, "Auras")
		end
		player:SetAttribute(ATTRIBUTE, data.Auras.Equipped)
	end)
	DataService.DataReset:Connect(function(player: Player, data: PlayerData)
		player:SetAttribute(ATTRIBUTE, data.Auras.Equipped)
		applySpeed(player, data)
	end)

	-- A new character starts at the default speed, so re-apply on every spawn.
	local function track(player: Player)
		player.CharacterAdded:Connect(function()
			local data = DataService.GetData(player)
			if data then
				applySpeed(player, data)
			end
		end)
	end
	for _, player in Players:GetPlayers() do
		track(player)
	end
	Players.PlayerAdded:Connect(track)
	Players.PlayerRemoving:Connect(function(player)
		player:SetAttribute(ATTRIBUTE, nil)
	end)
end

function AuraService.Start()
	for _, player in Players:GetPlayers() do
		local data = DataService.GetData(player)
		if data then
			player:SetAttribute(ATTRIBUTE, data.Auras.Equipped)
			applySpeed(player, data)
		end
	end
end

return AuraService
