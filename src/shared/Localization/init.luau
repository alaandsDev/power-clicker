--!strict
--[[
	Localization
	All player-facing text goes through here. No UI/server code contains
	hard-coded display strings.

		local Text = require(Shared.Localization)
		Text.Get("hud.perClick", { amount = "10", icon = "⚡", mult = "2" })
		Text.GetFor(player.LocaleId, "kick.Failed")      -- server side
		Text.Upgrade(upgradeConfig).Name / .Desc         -- config display names

	Language selection (GameConfig.Localization):
	- ForceLocale set  → everyone sees that language (default: "pt-br").
	- ForceLocale nil  → the player's Roblox locale, falling back to Fallback.
	Missing keys fall back to the Fallback language, then to the key itself
	(so a missing translation is visible, never a crash).
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local GameConfig = require(script.Parent.Config.GameConfig)

type StringTable = { [string]: string }

local LOCALES: { [string]: StringTable } = {
	["pt-br"] = require(script.Strings.ptBR),
	["en"] = require(script.Strings.en),
}

-- Number separators per locale (decimal, thousands).
local SEPARATORS: { [string]: { Decimal: string, Thousands: string } } = {
	["pt-br"] = { Decimal = ",", Thousands = "." },
	["en"] = { Decimal = ".", Thousands = "," },
}

local Text = {}

-- Normalizes a Roblox LocaleId ("pt-br", "pt_BR", "en-us") to a supported key.
function Text.Resolve(localeId: string?): string
	local forced = GameConfig.Localization.ForceLocale
	if forced and LOCALES[forced] then
		return forced
	end
	if localeId then
		local normalized = string.lower((string.gsub(localeId, "_", "-")))
		if LOCALES[normalized] then
			return normalized
		end
		local language = string.match(normalized, "^(%a+)")
		if language == "pt" then
			return "pt-br"
		end
		if language and LOCALES[language] then
			return language
		end
	end
	return GameConfig.Localization.Fallback
end

local function format(template: string, args: { [string]: any }?): string
	if not args then
		return template
	end
	return (string.gsub(template, "{(%w+)}", function(name: string): string
		local value = args[name]
		return if value ~= nil then tostring(value) else "{" .. name .. "}"
	end))
end

function Text.GetFor(localeId: string?, key: string, args: { [string]: any }?): string
	local locale = Text.Resolve(localeId)
	local template = LOCALES[locale][key] or LOCALES[GameConfig.Localization.Fallback][key] or key
	return format(template, args)
end

-- Client: uses the local player's locale. Server: uses the fallback/forced
-- locale (use GetFor with player.LocaleId for player-specific text).
local clientLocale: string? = nil
function Text.Get(key: string, args: { [string]: any }?): string
	if clientLocale == nil and RunService:IsClient() then
		local player = Players.LocalPlayer
		clientLocale = if player then player.LocaleId else nil
	end
	return Text.GetFor(clientLocale, key, args)
end

function Text.Separators(localeId: string?): { Decimal: string, Thousands: string }
	return SEPARATORS[Text.Resolve(localeId)] or SEPARATORS.en
end

-- Localized name/description for a config entry that has DisplayName (+ Description).
function Text.Upgrade(upgrade: { Id: string, DisplayName: string, Description: string }): { Name: string, Desc: string }
	local nameKey = "upgrade." .. upgrade.Id .. ".name"
	local descKey = "upgrade." .. upgrade.Id .. ".desc"
	local name = Text.Get(nameKey)
	local desc = Text.Get(descKey)
	return {
		Name = if name == nameKey then upgrade.DisplayName else name,
		Desc = if desc == descKey then upgrade.Description else desc,
	}
end

-- Localized name for any config entry by kind ("world", "pet", "egg"...).
function Text.Name(kind: string, entry: { Id: string, DisplayName: string }): string
	local key = kind .. "." .. entry.Id .. ".name"
	local value = Text.Get(key)
	return if value == key then entry.DisplayName else value
end

-- For tests: every locale table.
function Text.AllLocales(): { [string]: StringTable }
	return LOCALES
end

return Text
