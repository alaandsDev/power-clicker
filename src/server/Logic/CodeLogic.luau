--!strict
--[[
	CodeLogic
	Promo code validation (codes live in server-only CodeConfig).
	Normalize: trim + uppercase + only A-Z/0-9, so " release " == "RELEASE".
	Each player redeems a code once (data.Codes.Redeemed[code]).
	The optional GLOBAL MaxRedemptions cap is enforced by CodeService with an
	atomic DataStore counter (not here: that needs I/O).
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)

type PlayerData = Types.PlayerData

export type CodeEntry = {
	Rewards: { Types.RewardData },
	ExpiresAt: number?,
	MaxRedemptions: number?,
	Enabled: boolean,
}

local CodeLogic = {}

function CodeLogic.Normalize(raw: string): string
	local trimmed = string.gsub(raw, "^%s+", "")
	trimmed = string.gsub(trimmed, "%s+$", "")
	return string.upper(trimmed)
end

function CodeLogic.IsWellFormed(code: string, maxLength: number): boolean
	return #code > 0 and #code <= maxLength and string.match(code, "^[A-Z0-9]+$") ~= nil
end

-- Codes: "InvalidCode" | "CodeExpired" | "AlreadyRedeemed"
function CodeLogic.Validate(data: PlayerData, code: string, codes: { [string]: CodeEntry }, now: number): (boolean, string?, CodeEntry?)
	local entry = codes[code]
	if not entry or not entry.Enabled then
		return false, "InvalidCode"
	end
	if entry.ExpiresAt and now >= entry.ExpiresAt then
		return false, "CodeExpired"
	end
	if data.Codes.Redeemed[code] then
		return false, "AlreadyRedeemed"
	end
	return true, nil, entry
end

function CodeLogic.MarkRedeemed(data: PlayerData, code: string, now: number)
	data.Codes.Redeemed[code] = now
end

return CodeLogic
