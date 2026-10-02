--!strict
--[[
	ComboLogic
	Pure combo rules (ComboConfig). The server is authoritative; the client
	uses the same functions only to animate the combo between server updates.

	- A click within TimeoutSeconds of the previous one keeps the stacks.
	- After the timeout, stacks decay at DecayStacksPerSecond (0 = reset).
	- Each click then adds 1 stack, capped at MaxStacks.
]]

local ComboConfig = require(script.Parent.Parent.Config.ComboConfig)

local ComboLogic = {}

-- Stacks remaining at `now` given the last click time (no new click).
function ComboLogic.Current(stacks: number, lastClickAt: number, now: number): number
	if stacks <= 0 then
		return 0
	end
	local idle = now - lastClickAt
	if idle <= ComboConfig.TimeoutSeconds then
		return stacks
	end
	if ComboConfig.DecayStacksPerSecond <= 0 then
		return 0
	end
	local lost = math.floor((idle - ComboConfig.TimeoutSeconds) * ComboConfig.DecayStacksPerSecond)
	return math.max(0, stacks - lost)
end

-- Stacks after registering a click at `now`.
function ComboLogic.Register(stacks: number, lastClickAt: number, now: number): number
	local current = ComboLogic.Current(stacks, lastClickAt, now)
	return math.min(current + 1, ComboConfig.MaxStacks)
end

return ComboLogic
