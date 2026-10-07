--!strict
--[[
	ZoneService
	Owns "which training zone is this player standing in".

	Every CheckIntervalSeconds the server reads each character's position
	(the server's copy — never a client claim) and:
		- locked zone  → a notice (the gate's barrier is what blocks the way)
		- zone change  → PowerService.Invalidate + "ZoneChanged" to the client
	The zone's multiplier is published through the "Zone" power layer, so the
	whole economy keeps flowing through PowerFormula.

	Requirements are Stats.TotalPowerEarned and Stats.Rebirths (ZoneRules), so
	a rebirth never takes a zone away.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Logger = require(Shared.Utils.Logger)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local ZoneRules = require(Shared.Formulas.ZoneRules)

local NetService = require(script.Parent.NetService)
local DataService = require(script.Parent.DataService)
local PowerService = require(script.Parent.PowerService)
local WorldService = require(script.Parent.WorldService)

type PlayerData = Types.PlayerData
type ZoneData = Types.ZoneData

local log = Logger.new("Zones")

local ZoneService = {}

local currentZone: { [Player]: string } = {}
-- Which locked zone each player was last warned about (one notice per attempt).
local lockedNoticeAt: { [Player]: string } = {}

function ZoneService.GetZone(player: Player): string?
	return currentZone[player]
end

local function publish(player: Player, zone: ZoneData?)
	local zoneId = if zone then zone.Id else nil
	if currentZone[player] == zoneId then
		return
	end
	if zoneId then
		currentZone[player] = zoneId
	else
		currentZone[player] = nil
	end
	PowerService.Invalidate(player)
	NetService.FireClient("ZoneChanged", player, {
		ZoneId = zoneId,
		Multiplier = ZoneRules.Multiplier(zoneId),
	})
end

local function characterPosition(player: Player): Vector3?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function update(player: Player)
	--[[
		Zonas desligadas (ZoneConfig.Build = false: as ilhas não são
		construídas) não dão bônus nenhum. Antes o serviço ainda aplicava o
		multiplicador pela POSIÇÃO, então qualquer chão novo naquelas
		coordenadas ligaria um ×3…×50 escondido.
	]]
	if not ZoneConfig.Build then
		publish(player, nil)
		return
	end
	local data = DataService.GetData(player)
	local position = characterPosition(player)
	if not data or not position then
		return
	end
	local worldId = data.Worlds.Current
	local origin = WorldService.OriginOf(worldId)
	if not origin then
		return
	end
	local zone = ZoneRules.ZoneAt(worldId, origin, position)
	if zone and not ZoneRules.IsUnlocked(zone, data.Stats.TotalPowerEarned, data.Stats.Rebirths) then
		-- The gate's barrier keeps players out; someone standing here anyway
		-- (an exploit, or a glitch through the wall) simply earns nothing extra.
		if lockedNoticeAt[player] ~= zone.Id then
			lockedNoticeAt[player] = zone.Id
			NetService.FireClient("Notify", player, "ZoneLocked", {
				ZoneId = zone.Id,
				Power = zone.Requirement.Power,
				Rebirths = zone.Requirement.Rebirths,
			})
		end
		publish(player, nil)
		return
	end
	lockedNoticeAt[player] = nil
	publish(player, zone)
end

function ZoneService.Init()
	PowerService.RegisterProvider("Zone", function(player: Player, _data: PlayerData): number
		if not ZoneConfig.Build then
			return 1
		end
		return ZoneRules.Multiplier(currentZone[player])
	end)

	Players.PlayerRemoving:Connect(function(player)
		currentZone[player] = nil
		lockedNoticeAt[player] = nil
	end)
end

function ZoneService.Start()
	task.spawn(function()
		while true do
			task.wait(ZoneConfig.CheckIntervalSeconds)
			for _, player in Players:GetPlayers() do
				local ok, err: any = pcall(update, player)
				if not ok then
					log:Warn("zone update failed:", tostring(err))
				end
			end
		end
	end)
end

return ZoneService
