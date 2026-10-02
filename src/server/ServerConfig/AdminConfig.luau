--!strict
--[[
	AdminConfig (server-only)
	Who may use DebugService (Phase 2+). Checked exclusively on the server by
	UserId — never by name, never by a client flag.
]]

return {
	-- UserIds allowed to run debug commands in LIVE servers (keep empty for launch).
	AdminUserIds = {} :: { number },

	-- In Studio every player (i.e. the developer + test clients) may use debug tools.
	DebugEnabledInStudio = true,
	-- Master switch for live servers. Must stay false for public release.
	DebugEnabledInLive = false,
}
