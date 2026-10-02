--!strict
--[[
	GameConfig
	Global, non-economy settings that are safe to replicate to clients.
	Server-only settings (DataStore names, admins, codes) live in
	ServerScriptService.Server.ServerConfig.
]]

local GameConfig = {
	GameName = "Power Clicker",
	BuildVersion = "0.8.0-mvp",

	Logging = {
		-- "Debug" | "Info" | "Warn" | "Error" | "None"
		StudioLevel = "Debug",
		LiveLevel = "Warn",
	},

	Replication = {
		-- Changed top-level data keys are batched and sent at most this often.
		FlushIntervalSeconds = 0.1,
	},

	Localization = {
		-- Language shown to everyone. nil = use each player's Roblox language.
		ForceLocale = "pt-br" :: string?,
		-- Used when a player's language (or a key) has no translation.
		Fallback = "en",
	},

	Dev = {
		-- Studio only: make every world playable (placeholder maps are generated)
		-- so the world system can be tested. No effect in live servers.
		EnableAllWorldsInStudio = true,
	},

	Numbers = {
		-- Hard ceiling for any currency/stat. Keeps values finite and JSON-safe.
		MaxValue = 1e100,
	},
}

return GameConfig
