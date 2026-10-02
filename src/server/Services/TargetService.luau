--!strict
--[[
	TargetService
	Breakable targets (punching bags / rocks / crystals / orbs) standing in the
	training zones. Every click a player makes also hits the closest target in
	range; when its HP reaches zero the breaker gets the zone's Power reward and
	the target comes back after RespawnSeconds.

	Authority: HP lives HERE. The client never sends damage — it only sees the
	"Hp" attribute the server writes on each target part, and is told about a
	break through the normal Notify event.

	Parts are created by WorldBuilder with attributes:
		Target = true, ZoneId = "<zone id>", TargetIndex = <n>
]]

local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Logger = require(Shared.Utils.Logger)
local ZoneConfig = require(Shared.Config.ZoneConfig)

local Signal = require(Shared.Utils.Signal)
local NetService = require(script.Parent.NetService)
local CurrencyService = require(script.Parent.CurrencyService)

type ZoneData = Types.ZoneData

type TargetState = {
	Part: BasePart,
	Zone: ZoneData,
	Hp: number,
	BrokenUntil: number, -- os.clock(); 0 = alive
}

local log = Logger.new("Targets")

local TargetService = {
	-- (player, zoneId, reward)
	Broken = Signal.new() :: Signal.Signal<Player, string, number>,
}

local targets: { TargetState } = {}
local scanned = false

local function setHp(state: TargetState, hp: number)
	state.Hp = hp
	state.Part:SetAttribute("Hp", hp)
end

local function setBroken(state: TargetState, broken: boolean)
	-- A standee's anchor is invisible on purpose; only the geometric targets
	-- fade. The artwork lives in a BillboardGui, which needs Enabled instead.
	if state.Part:GetAttribute("Standee") ~= true then
		state.Part.Transparency = if broken then 1 else 0
	end
	state.Part.CanCollide = not broken
	state.Part:SetAttribute("Broken", broken)
	for _, child in state.Part:GetChildren() do
		if child:IsA("BasePart") then
			child.Transparency = if broken then 1 else child:GetAttribute("BaseTransparency") or 0
		elseif child:IsA("BillboardGui") and child.Name == "Monster" then
			child.Enabled = not broken
		end
	end
end

-- Finds every target part built into the map (once the worlds exist).
local function scan()
	local map = Workspace:FindFirstChild("Map")
	local worlds = if map then map:FindFirstChild("Worlds") else nil
	if not worlds then
		return
	end
	table.clear(targets)
	for _, descendant in worlds:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:GetAttribute("Target") == true then
			local zoneId = descendant:GetAttribute("ZoneId")
			local zone = if type(zoneId) == "string" then ZoneConfig.Zones[zoneId] else nil
			if zone then
				local state: TargetState = { Part = descendant, Zone = zone, Hp = zone.Target.Hp, BrokenUntil = 0 }
				descendant:SetAttribute("MaxHp", zone.Target.Hp)
				setHp(state, zone.Target.Hp)
				table.insert(targets, state)
			end
		end
	end
	scanned = #targets > 0
	if scanned then
		log:Info(string.format("%d targets registered", #targets))
	end
end

local function characterPosition(player: Player): Vector3?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root.Position else nil
end

-- Closest living target of `zone` within HitRange of the player.
local function nearestTarget(player: Player, zoneId: string): TargetState?
	local position = characterPosition(player)
	if not position then
		return nil
	end
	local best: TargetState? = nil
	local bestDistance = ZoneConfig.HitRange
	for _, state in targets do
		if state.Zone.Id == zoneId and state.BrokenUntil == 0 then
			local distance = (state.Part.Position - position).Magnitude
			if distance <= bestDistance then
				best, bestDistance = state, distance
			end
		end
	end
	return best
end

--[[
	Applies one click's worth of damage for `player` in `zoneId`.
	Returns the Power granted for a break (0 when nothing broke).
	Called by ClickService after the click's own Power was granted.
]]
function TargetService.OnClick(player: Player, zoneId: string?, damage: number): number
	if not zoneId or damage <= 0 or not scanned then
		return 0
	end
	local state = nearestTarget(player, zoneId)
	if not state then
		return 0
	end
	setHp(state, state.Hp - damage)
	if state.Hp > 0 then
		return 0
	end
	-- Broken: pay the finisher and start the respawn timer.
	local reward = CurrencyService.Add(player, "Power", state.Zone.Target.Reward, "Target:" .. state.Zone.Id)
	state.BrokenUntil = os.clock() + state.Zone.Target.RespawnSeconds
	setBroken(state, true)
	setHp(state, 0)
	-- One timer per break instead of a per-frame sweep over every target.
	task.delay(state.Zone.Target.RespawnSeconds, function()
		if state.Part.Parent and state.BrokenUntil ~= 0 then
			state.BrokenUntil = 0
			setHp(state, state.Zone.Target.Hp)
			setBroken(state, false)
		end
	end)
	NetService.FireClient("Notify", player, "TargetBroken", {
		ZoneId = state.Zone.Id,
		Reward = reward,
		Position = state.Part.Position,
	})
	TargetService.Broken:Fire(player, state.Zone.Id, reward)
	return reward
end

function TargetService.Init()
	-- nothing to wire: ClickService calls OnClick directly
end

function TargetService.Start()
	scan()
	task.spawn(function()
		-- Worlds may still be building on the first frames.
		while not scanned do
			task.wait(1)
			scan()
		end
	end)
end

return TargetService
