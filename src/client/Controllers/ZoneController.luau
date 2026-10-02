--!strict
--[[
	ZoneController
	Shows which training zone the player is in:
		- a chip in the HUD column ("Pedreira · x8")
		- a banner when entering a zone
		- HP bars over the breakable targets (from the server's attributes)
		- the gate barriers: solid until THIS player meets the requirement

	Barriers are switched locally because a character's collisions run on its
	own client. That is safe: the zone's multiplier and its target rewards are
	decided by the server, so walking in without the requirement earns nothing.

	Display only: HP, rewards and the right to be in a zone all live on the
	server (ZoneService / TargetService).
]]

local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local NumberFormat = require(Shared:WaitForChild("Utils"):WaitForChild("NumberFormat"))
local ZoneConfig = require(Shared:WaitForChild("Config"):WaitForChild("ZoneConfig"))
local ZoneRules = require(Shared:WaitForChild("Formulas"):WaitForChild("ZoneRules"))
local Text = require(Shared:WaitForChild("Localization"))

local Theme = require(script.Parent.Parent.UI.Theme)
local Build = require(script.Parent.Parent.UI.Build)
local Anim = require(script.Parent.Parent.UI.Anim)
local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local UIController = require(script.Parent.UIController)
local DataController = require(script.Parent.DataController)
local SoundController = require(script.Parent.SoundController)
local NotificationController = require(script.Parent.NotificationController)

local BANNER_SECONDS = 2.2
local BAR_WIDTH = 16 -- studs
local BAR_HEIGHT = 3.4 -- studs
local BAR_LABEL_SHARE = 0.46 -- how much of the billboard the number takes

local ZoneController = {}

local chip: TextLabel
local banner: TextLabel
local bannerStamp = 0
local bars: { [BasePart]: { Gui: BillboardGui, Fill: Frame, Label: TextLabel } } = {}
local barriers: { [BasePart]: string } = {}

local function zoneName(zoneId: string): string
	local zone = ZoneConfig.Zones[zoneId]
	return if zone then Text.Name("zone", zone) else zoneId
end

local function showBanner(zoneId: string?)
	if not zoneId then
		banner.Visible = false
		return
	end
	local zone = ZoneConfig.Zones[zoneId]
	banner.Text = Text.Get("zone.entered", { name = zoneName(zoneId), mult = NumberFormat.Short(if zone then zone.Multiplier else 1) })
	banner.Visible = true
	Anim.PopIn(banner, 0.35)
	bannerStamp += 1
	local stamp = bannerStamp
	task.delay(BANNER_SECONDS, function()
		if bannerStamp == stamp then
			banner.Visible = false
		end
	end)
end

local function setZone(zoneId: string?, multiplier: number)
	if zoneId then
		chip.Text = Text.Get("zone.chip", { name = zoneName(zoneId), mult = NumberFormat.Short(multiplier) })
		chip.Visible = true
		SoundController.Play("Reward")
	else
		chip.Visible = false
	end
	showBanner(zoneId)
end

-- One HP bar per target part, created on demand and updated from attributes.
local function bindTarget(part: BasePart)
	if bars[part] then
		return
	end
	local gui: BillboardGui = Build.new("BillboardGui", {
		Name = "TargetHp",
		-- Studs, not pixels: the bar shrinks with distance like the world signs.
		Size = UDim2.fromScale(BAR_WIDTH, BAR_HEIGHT),
		StudsOffset = Vector3.new(0, part:GetAttribute("BarHeight") or (part.Size.Y / 2 + 4), 0),
		MaxDistance = 180,
		AlwaysOnTop = false,
		Parent = part,
	})
	local label = Build.label({
		Name = "Amount",
		Text = "",
		TextScaled = true, -- the billboard is measured in studs; let it fill
		Size = UDim2.fromScale(1, BAR_LABEL_SHARE),
		Parent = gui,
	})
	local container, _set = Build.progressBar({
		Name = "Bar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(0.94, 1 - BAR_LABEL_SHARE - 0.08),
		Parent = gui,
	}, Theme.Colors.Bad)
	Build.stroke(container, 3)
	local fill = container:FindFirstChild("Fill") :: Frame

	local entry = { Gui = gui, Fill = fill, Label = label }
	bars[part] = entry

	local function refresh()
		local hp = part:GetAttribute("Hp")
		local maxHp = part:GetAttribute("MaxHp")
		if type(hp) ~= "number" or type(maxHp) ~= "number" or maxHp <= 0 then
			return
		end
		local ratio = math.clamp(hp / maxHp, 0, 1)
		fill.Size = UDim2.fromScale(ratio, 1)
		Build.paint(fill, "BackgroundColor3", if ratio > 0.5 then Theme.Colors.Good elseif ratio > 0.2 then Theme.Colors.Power else Theme.Colors.Bad)
		label.Text = NumberFormat.Short(math.max(hp, 0))
		gui.Enabled = part:GetAttribute("Broken") ~= true
	end

	part:GetAttributeChangedSignal("Hp"):Connect(refresh)
	part:GetAttributeChangedSignal("Broken"):Connect(refresh)
	refresh()
end

-- Opens the barriers this player already earned and keeps the rest solid.
local function refreshBarriers()
	local stats = DataController.Get("Stats")
	if not stats then
		return
	end
	for part, zoneId in barriers do
		if not part.Parent then
			barriers[part] = nil
			continue
		end
		local zone = ZoneConfig.Zones[zoneId]
		local open = zone ~= nil and ZoneRules.IsUnlocked(zone, stats.TotalPowerEarned or 0, stats.Rebirths or 0)
		part.CanCollide = not open
		part.Transparency = if open then 0.9 else 0.45
	end
end

local function scan()
	local map = Workspace:FindFirstChild("Map")
	local worlds = if map then map:FindFirstChild("Worlds") else nil
	if not worlds then
		return
	end
	for _, descendant in worlds:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:GetAttribute("Target") == true then
			bindTarget(descendant)
		end
		local barrierZone = descendant:GetAttribute("ZoneBarrier")
		if descendant:IsA("BasePart") and type(barrierZone) == "string" then
			barriers[descendant] = barrierZone
		end
	end
	refreshBarriers()
end

function ZoneController.Init()
	local canvas = UIController.GetCanvas()
	local hud = Theme.Hud

	chip = Build.label({
		Name = "ZoneChip",
		Text = "",
		Font = Theme.FontDisplay,
		TextSize = 18,
		TextColor3 = Theme.Colors.Text,
		BackgroundColor3 = Theme.Hud.Surface,
		BackgroundTransparency = 0.15,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, hud.Margin, 1, -hud.Margin),
		Size = UDim2.fromOffset(0, hud.ChipHeight),
		AutomaticSize = Enum.AutomaticSize.X,
		Visible = false,
		Parent = canvas,
	})
	Build.corner(chip, UDim.new(1, 0))
	Build.new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), Parent = chip })

	banner = Build.label({
		Name = "ZoneBanner",
		Text = "",
		Font = Theme.FontDisplay,
		TextSize = 40,
		TextColor3 = Theme.Colors.Power,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 200),
		Size = UDim2.fromOffset(700, 52),
		Visible = false,
		ZIndex = 16,
		Parent = canvas,
	})
	Build.textStroke(banner, 3)

	-- Power earned and rebirths are what open a gate; both live in Stats.
	DataController.Changed:Connect(function(key: string)
		if key == "Stats" then
			refreshBarriers()
		end
	end)

	ClientNet.On("ZoneChanged", function(payload: any)
		if type(payload) == "table" then
			setZone(payload.ZoneId, tonumber(payload.Multiplier) or 1)
		end
	end)

	ClientNet.On("Notify", function(kind: any, payload: any)
		if kind ~= "ZoneLocked" or type(payload) ~= "table" then
			return
		end
		NotificationController.Show(Text.Get("zone.locked", {
			name = zoneName(tostring(payload.ZoneId)),
			power = NumberFormat.Short(tonumber(payload.Power) or 0),
			rebirths = tostring(payload.Rebirths or 0),
		}), "Bad")
	end)
end

function ZoneController.Start()
	task.spawn(function()
		-- Worlds stream in after join; keep looking until the targets exist.
		for _ = 1, 20 do
			scan()
			if next(bars) then
				return
			end
			task.wait(1)
		end
	end)
end

return ZoneController
