--!strict
--[[
	VipController
	Shows a [VIP] prefix on chat messages from players whose server-set "VIP"
	attribute is true (TextChatService, cosmetic only).
]]

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Text = require(Shared:WaitForChild("Localization"))

local VIP_COLOR = "#FFC42D"

local VipController = {}

function VipController.Init()
	TextChatService.OnIncomingMessage = function(message: TextChatMessage): TextChatMessageProperties?
		local source = message.TextSource
		if not source then
			return nil
		end
		local player = Players:GetPlayerByUserId(source.UserId)
		if not player or player:GetAttribute("VIP") ~= true then
			return nil
		end
		local properties = Instance.new("TextChatMessageProperties")
		properties.PrefixText = string.format('<font color="%s">%s</font> %s', VIP_COLOR, Text.Get("vip.tag"), message.PrefixText)
		return properties
	end
end

return VipController
