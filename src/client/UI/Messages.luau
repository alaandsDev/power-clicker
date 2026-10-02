--!strict
--[[
	Messages
	Player-facing text for server response codes (keys "code.<Code>" in
	Shared/Localization). Unknown codes fall back to a generic error.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Text = require(Shared:WaitForChild("Localization"))

local Messages = {}

function Messages.ForCode(code: string?): string
	local key = "code." .. (code or "ServerError")
	local message = Text.Get(key)
	return if message == key then Text.Get("code.ServerError") else message
end

return Messages
