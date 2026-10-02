--!strict
--[[
	DevConfig (server-only)
	Development toggles. None of these have any effect in live servers.
]]

return {
	-- Run unit tests (ServerScriptService.Server.Tests) on every Studio play session.
	RunTestsInStudio = true,
	-- In Studio, stop the boot if config validation finds errors.
	FailBootOnConfigErrorsInStudio = true,
}
