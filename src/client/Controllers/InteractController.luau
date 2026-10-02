--!strict
--[[
	InteractController
	World stations (egg stands, rebirth altar, portal) carry ProximityPrompts
	built by the server's WorldBuilder with attributes:
		OpenPanel = panel id to open    TextKey / ObjectKey = localization keys
	Triggering a prompt only OPENS the UI panel; every real action still goes
	through the validated remotes. Prompt texts are localized on the client.

	The cut pads are the exception that proves the rule: their prompt carries a
	CutId and no panel, and the SERVER answers it (PromptTriggered is a server
	event too), so there is nothing to open and nothing to send. This
	controller only shows what came back.
]]

local ProximityPromptService = game:GetService("ProximityPromptService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local NumberFormat = require(Shared:WaitForChild("Utils"):WaitForChild("NumberFormat"))
local Text = require(Shared:WaitForChild("Localization"))

local Messages = require(script.Parent.Parent.UI.Messages)
local ClientNet = require(script.Parent.Parent.Net.ClientNet)
local UIController = require(script.Parent.UIController)
local SoundController = require(script.Parent.SoundController)
local NotificationController = require(script.Parent.NotificationController)

local InteractController = {}

function InteractController.Init()
	ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
		local textKey = prompt:GetAttribute("TextKey")
		if type(textKey) == "string" then
			prompt.ActionText = Text.Get(textKey)
		end
		local objectKey = prompt:GetAttribute("ObjectKey")
		if type(objectKey) == "string" then
			prompt.ObjectText = Text.Get(objectKey)
		end
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local panel = prompt:GetAttribute("OpenPanel")
		if type(panel) == "string" then
			UIController.OpenPanel(panel)
		end
	end)

	ClientNet.On("Notify", function(kind: any, payload: any)
		if type(payload) ~= "table" then
			return
		end
		if kind == "CutBought" then
			SoundController.Play("Upgrade")
			NotificationController.Show(Text.Get("cut.bought", {
				flat = NumberFormat.Short(tonumber(payload.Flat) or 0),
			}), "Good")
		elseif kind == "CutRefused" then
			NotificationController.Show(Messages.ForCode(payload.Code), "Bad")
		end
	end)
end

return InteractController
