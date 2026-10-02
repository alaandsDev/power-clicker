--!strict
--[[
	EventController
	Draws the live events (Phase 10):
		- happy hour: a chip with the multiplier and the time left
		- world boss: a bar at the top with HP and the time left
		- notices for a boss appearing, dying or escaping
		- floating "+N ⚡" when a Power orb or a boss reward is collected

	Everything shown here was decided by the server (BossService /
	PickupService); this controller never grants anything.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local NumberFormat = require(Shared:WaitForChild("Utils"):WaitForChild("NumberFormat"))
local WorldConfig = require(Shared:WaitForChild("Config"):WaitForChild("WorldConfig"))
local Text = require(Shared:WaitForChild("Localization"))

local Theme = require(script.Parent.Parent.UI.Theme)
local Build = require(script.Parent.Parent.UI.Build)
local Anim = require(script.Parent.Parent.UI.Anim)
local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local DataController = require(script.Parent.DataController)
local SoundController = require(script.Parent.SoundController)
local NotificationController = require(script.Parent.NotificationController)
local HudController = require(script.Parent.HudController)

-- Compacta: título + tempo numa linha e a barra embaixo. Mora na coluna
-- central ABAIXO das moedas (HudController.GetTopStack) — antes ficava em
-- y = 76 e cobria Power/Gemas/Vitórias.
local BAR_SIZE = Vector2.new(420, 14)

local EventController = {}

local panel: Frame
local eventChip: TextLabel
local titleLabel: TextLabel
local timerLabel: TextLabel
local setBar: (number) -> ()

-- The boss lands in ONE world: its bar and its notices are for the players
-- standing there, not for the whole server.
local function isHere(worldId: any): boolean
	local worlds = DataController.Get("Worlds")
	return type(worlds) == "table" and worlds.Current == worldId
end

local function worldName(worldId: any): string
	local world = if type(worldId) == "string" then WorldConfig.Worlds[worldId] else nil
	return if world then Text.Name("world", world) else ""
end

local function setActive(active: boolean)
	if panel.Visible == active then
		return
	end
	panel.Visible = active
	if active then
		Anim.PopIn(panel, 0.4)
		SoundController.Play("OverdriveStart")
	end
end

function EventController.Init()
	panel = Build.new("Frame", {
		Name = "BossBar",
		Size = UDim2.fromOffset(BAR_SIZE.X + 20, 52),
		Visible = false,
		ZIndex = 17,
		LayoutOrder = 3,
		Parent = HudController.GetTopStack(),
	})
	Build.hudSurface(panel, UDim.new(0, 14), Theme.Colors.Bad)
	Build.padding(panel, 10)

	titleLabel = Build.label({
		Name = "Title",
		Text = "",
		Font = Theme.FontDisplay,
		TextSize = 17,
		TextColor3 = Theme.Colors.Bad,
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 18,
		Parent = panel,
	})
	timerLabel = Build.label({
		Name = "Timer",
		Text = "",
		Font = Theme.FontMono,
		TextSize = 14,
		TextColor3 = Theme.Colors.TextDim,
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 18,
		Parent = panel,
	})
	local bar, set = Build.progressBar({
		Name = "Hp",
		Position = UDim2.fromOffset(0, 22),
		Size = UDim2.fromOffset(BAR_SIZE.X, BAR_SIZE.Y),
		ZIndex = 18,
		Parent = panel,
	}, Theme.Colors.Bad)
	Build.stroke(bar, 2)
	setBar = set

	eventChip = Build.label({
		Name = "HappyHour",
		Text = "",
		Font = Theme.FontDisplay,
		TextSize = 18,
		TextColor3 = Theme.Colors.Power,
		BackgroundColor3 = Theme.Hud.Surface,
		BackgroundTransparency = 0.15,
		Size = UDim2.fromOffset(0, 28),
		AutomaticSize = Enum.AutomaticSize.X,
		Visible = false,
		ZIndex = 17,
		LayoutOrder = 2,
		Parent = HudController.GetTopStack(),
	})
	Build.corner(eventChip, UDim.new(1, 0))
	Build.new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), Parent = eventChip })

	ClientNet.On("EventState", function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		local multiplier = tonumber(payload.Multiplier) or 1
		if type(payload.EventId) ~= "string" or multiplier <= 1 then
			eventChip.Visible = false
			return
		end
		eventChip.Text = Text.Get("event.chip", {
			mult = NumberFormat.Short(multiplier),
			time = NumberFormat.Duration(tonumber(payload.SecondsLeft) or 0),
		})
		if not eventChip.Visible then
			eventChip.Visible = true
			Anim.PopIn(eventChip, 0.35)
		end
	end)

	ClientNet.On("BossState", function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		setActive(payload.Active == true and isHere(payload.WorldId))
		if payload.Active ~= true then
			return
		end
		local hp = tonumber(payload.Hp) or 0
		local maxHp = math.max(tonumber(payload.MaxHp) or 1, 1)
		titleLabel.Text = Text.Get("boss.title", { hp = NumberFormat.Short(math.max(hp, 0)), max = NumberFormat.Short(maxHp) })
		timerLabel.Text = NumberFormat.Duration(tonumber(payload.SecondsLeft) or 0)
		setBar(hp / maxHp)
	end)

	ClientNet.On("Notify", function(kind: any, payload: any)
		if type(payload) ~= "table" then
			return
		end
		if kind == "BossSpawned" then
			NotificationController.Show(
				if isHere(payload.WorldId)
					then Text.Get("boss.spawned")
					else Text.Get("boss.spawnedElsewhere", { world = worldName(payload.WorldId) }),
				"Bad"
			)
		elseif kind == "BossDefeated" then
			NotificationController.Show(Text.Get("boss.defeated"), "Good")
			SoundController.Play("Reward")
		elseif kind == "BossEscaped" then
			NotificationController.Show(Text.Get("boss.escaped"), "Info")
		elseif kind == "BossReward" then
			NotificationController.Show(Text.Get("boss.reward", {
				amount = NumberFormat.Short(tonumber(payload.Amount) or 0),
				percent = NumberFormat.Short(math.floor((tonumber(payload.Share) or 0) * 100)),
			}), "Good")
		elseif kind == "PlaytimeChest" then
			NotificationController.Show(Text.Get("session.chest", {
				minutes = tostring(payload.Minutes or 0),
				amount = NumberFormat.Short(tonumber(payload.Power) or 0),
			}), "Good")
			SoundController.Play("Reward")
		elseif kind == "FriendBonus" then
			NotificationController.Show(Text.Get("social.friendBonus", {
				friends = tostring(payload.Friends or 0),
				percent = tostring(payload.Percent or 0),
			}), "Good")
		elseif kind == "GroupReward" then
			NotificationController.Show(Text.Get("social.groupReward"), "Good")
			SoundController.Play("Reward")
		elseif kind == "PickupClaimed" then
			NotificationController.Show(Text.Get("pickup.claimed", { amount = NumberFormat.Short(tonumber(payload.Amount) or 0) }), "Good")
			SoundController.Play("Reward")
		end
	end)
end

return EventController
