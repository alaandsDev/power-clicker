--!strict
--[[
	SettingsController
	"Ajustes" panel: toggle buttons (touch/gamepad friendly, no sliders) for
	sound effects, music, floating numbers and reduced effects. Values are
	saved server-side (UpdateSettings) and read back from replicated data.
	Music has no track yet (TODO_ASSET); the preference is stored already.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Text = require(Shared:WaitForChild("Localization"))

local Theme = require(script.Parent.Parent.UI.Theme)
local Build = require(script.Parent.Parent.UI.Build)
local Messages = require(script.Parent.Parent.UI.Messages)
local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local UIController = require(script.Parent.UIController)
local MenuController = require(script.Parent.MenuController)
local DataController = require(script.Parent.DataController)
local NotificationController = require(script.Parent.NotificationController)

type Toggle = { Key: string, Kind: string, Button: TextButton } -- Kind: "Volume" | "Boolean"

local PANEL = "Settings"
local DEFAULT_VOLUME = 0.8
local ORDER = {
	{ Key = "SfxVolume", Kind = "Volume" },
	{ Key = "MusicVolume", Kind = "Volume" },
	{ Key = "ShowFloatingNumbers", Kind = "Boolean" },
	{ Key = "ReducedEffects", Kind = "Boolean" },
}

local SettingsController = {}

local toggles: { Toggle } = {}
local busy = false

local function isOn(settings: any, toggle: Toggle): boolean
	local value = settings[toggle.Key]
	if toggle.Kind == "Volume" then
		return type(value) == "number" and value > 0
	end
	return value == true
end

local function refresh()
	local settings = DataController.Get("Settings") or {}
	for _, toggle in toggles do
		local on = isOn(settings, toggle)
		toggle.Button.Text = Text.Get(if on then "settings.on" else "settings.off")
		Build.paint(toggle.Button, "BackgroundColor3", if on then Theme.Colors.Good else Theme.Colors.Disabled)
	end
end

local function flip(toggle: Toggle)
	if busy then
		return
	end
	local settings = DataController.Get("Settings") or {}
	local on = isOn(settings, toggle)
	local value: any = if toggle.Kind == "Volume" then (if on then 0 else DEFAULT_VOLUME) else not on
	busy = true
	local response = ClientNet.Invoke("UpdateSettings", toggle.Key, value)
	busy = false
	if not response.Ok then
		NotificationController.Show(Messages.ForCode(response.Code), "Bad")
	end
end

-- Convenience getters for other controllers (display preferences only).
function SettingsController.ReducedEffects(): boolean
	local settings = DataController.Get("Settings")
	return settings ~= nil and settings.ReducedEffects == true
end

function SettingsController.SfxVolume(): number
	local settings = DataController.Get("Settings")
	local value = if settings then settings.SfxVolume else nil
	return if type(value) == "number" then math.clamp(value, 0, 1) else DEFAULT_VOLUME
end

function SettingsController.Init()
	local _, content = UIController.CreatePanel(PANEL, Text.Get("settings.title", { icon = Theme.Icons.Settings }), Vector2.new(520, 420))
	Build.new("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder, Parent = content })
	for index, entry in ORDER do
		local row: Frame = Build.new("Frame", { BackgroundColor3 = Theme.Colors.PanelLight, Size = UDim2.new(1, 0, 0, 64), LayoutOrder = index, ZIndex = 22, Parent = content })
		Build.corner(row, Theme.CornerSmall)
		Build.label({ Text = Text.Get("settings." .. entry.Key), TextSize = 22, Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -200, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 23, Parent = row })
		local button = Build.button({ Text = "", TextSize = 20, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(170, 48), ZIndex = 23, Parent = row })
		local toggle: Toggle = { Key = entry.Key, Kind = entry.Kind, Button = button }
		button.Activated:Connect(function()
			flip(toggle)
		end)
		table.insert(toggles, toggle)
	end

	MenuController.AddButton(Text.Get("menu.settings"), Theme.Icons.Settings, Theme.Colors.PanelLight, 10, function()
		UIController.TogglePanel(PANEL)
	end, "Settings")

	DataController.Changed:Connect(function(key: string)
		if key == "Settings" then
			refresh()
		end
	end)
end

return SettingsController
