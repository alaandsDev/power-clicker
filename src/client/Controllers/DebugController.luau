--!strict
--[[
	DebugController — DEVELOPMENT TOOL.
	Only built when the server says this player may use debug commands
	(DebugAccess). Showing it is cosmetic: every command is re-validated by
	DebugService on the server against AdminConfig.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local NumberFormat = require(Shared:WaitForChild("Utils"):WaitForChild("NumberFormat"))
local Text = require(Shared:WaitForChild("Localization"))
local PetConfig = require(Shared:WaitForChild("Config"):WaitForChild("PetConfig"))

local Theme = require(script.Parent.Parent.UI.Theme)
local Build = require(script.Parent.Parent.UI.Build)
local Messages = require(script.Parent.Parent.UI.Messages)
local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local UIController = require(script.Parent.UIController)
local NotificationController = require(script.Parent.NotificationController)

type Command = { Label: string, Command: string, Amount: number? }

local COMMANDS: { Command } = {
	{ Label = "debug.addPower1K", Command = "AddPower", Amount = 1e3 },
	{ Label = "debug.addPower1M", Command = "AddPower", Amount = 1e6 },
	{ Label = "debug.addPower1B", Command = "AddPower", Amount = 1e9 },
	{ Label = "debug.addGems", Command = "AddGems", Amount = 100 },
	{ Label = "debug.addWins", Command = "AddWins", Amount = 50 },
	{ Label = "debug.rebirth", Command = "Rebirth" },
	{ Label = "debug.overdrive", Command = "Overdrive" },
	{ Label = "debug.autoClick", Command = "ToggleAutoClick" },
	{ Label = "debug.randomPet", Command = "GiveRandomPet" },
	{ Label = "debug.unlockWorlds", Command = "UnlockWorlds" },
	{ Label = "debug.addBoosts", Command = "AddBoosts" },
	{ Label = "debug.skipDay", Command = "SkipDay" },
	{ Label = "debug.spawnBoss", Command = "SpawnBoss" },
	{ Label = "debug.spawnOrb", Command = "SpawnOrb" },
	{ Label = "debug.giveAuras", Command = "GiveAuras" },
	{ Label = "debug.randomRune", Command = "GiveRandomRune" },
	{ Label = "debug.testPasses", Command = "TestPasses" },
	{ Label = "debug.testStarter", Command = "TestStarterPack" },
	{ Label = "debug.testGems", Command = "TestGems" },
	{ Label = "debug.reset", Command = "ResetData" },
}

local DebugController = {}

local built = false
local TOGGLE_SIZE = 34
-- Left edge of the menu grid, in canvas pixels from the right edge.
local MENU_EDGE = Theme.Hud.Margin + Theme.Hud.MenuColumns * Theme.Hud.MenuCell + (Theme.Hud.MenuColumns - 1) * Theme.Hud.Gap + Theme.Hud.Gap

local function run(entry: Command)
	local response = ClientNet.Invoke("DebugCommand", entry.Command, entry.Amount)
	if not response.Ok then
		NotificationController.Show(Text.Get("debug.error", { message = Messages.ForCode(response.Code) }), "Bad")
	elseif entry.Command == "ToggleAutoClick" then
		local enabled = type(response.Data) == "table" and response.Data.Enabled
		NotificationController.Show(Text.Get(if enabled then "debug.autoClickOn" else "debug.autoClickOff"), "Info")
	elseif entry.Command == "GiveRandomPet" then
		local petId = type(response.Data) == "table" and response.Data.PetId
		local pet = if type(petId) == "string" then PetConfig.Pets[petId] else nil
		NotificationController.Show(Text.Get("debug.gotPet", { name = if pet then Text.Name("pet", pet) else "?" }), "Info")
	elseif entry.Amount then
		NotificationController.Show(Text.Get("debug.added", { amount = NumberFormat.Short(entry.Amount) }), "Info")
	end
end

local function build()
	if built then
		return
	end
	built = true
	local frame: Frame = Build.new("Frame", {
		Name = "DebugPanel",
		BackgroundColor3 = Theme.Colors.Background,
		BackgroundTransparency = 0.2,
		Active = true,
		-- Studio only: left of the menu grid and of its toggle.
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -(MENU_EDGE + TOGGLE_SIZE + Theme.Hud.Gap), Theme.Hud.MenuCenterY, 0),
		Size = UDim2.fromOffset(336, 280),
		Visible = false, -- opened by the toggle below; it covers the view
		Parent = UIController.GetCanvas(),
	})
	local toggle = Build.button({
		Name = "DebugToggle",
		Text = Theme.Icons.Debug,
		TextSize = 20,
		BackgroundColor3 = Theme.Colors.Bad,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -MENU_EDGE, Theme.Hud.MenuCenterY, 0),
		Size = UDim2.fromOffset(TOGGLE_SIZE, TOGGLE_SIZE),
		Parent = UIController.GetCanvas(),
	})
	toggle.Activated:Connect(function()
		frame.Visible = not frame.Visible
	end)
	Build.corner(frame, Theme.CornerSmall)
	Build.stroke(frame, 2, Theme.Colors.Bad)
	Build.padding(frame, 8)
	Build.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(102, 38),
		CellPadding = UDim2.fromOffset(6, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = frame,
	})
	for index, entry in COMMANDS do
		local button = Build.button({
			Text = Text.Get(entry.Label),
			TextSize = 14,
			BackgroundColor3 = if entry.Command == "ResetData" then Theme.Colors.Bad else Theme.Colors.PanelLight,
			LayoutOrder = index,
			Parent = frame,
		})
		button.Activated:Connect(function()
			run(entry)
		end)
	end
end

function DebugController.Init()
	ClientNet.On("DebugAccess", function(allowed: any)
		if allowed == true then
			build()
		end
	end)
end

return DebugController
