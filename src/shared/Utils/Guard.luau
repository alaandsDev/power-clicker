--!strict
--[[
	Guard
	Composable runtime validators for untrusted input (remote arguments).
	Pure — safe to unit test.

		local validate = Guard.Args(Guard.KeyOf(EggConfig.Eggs), Guard.Integer(1, 3))
		if not validate(...) then return end

	Every check rejects: wrong types, NaN, ±inf, out-of-range values, overly long
	strings and invalid UTF-8. Args() also rejects EXTRA arguments.
]]

export type Check = (value: any) -> boolean

local Guard = {}

function Guard.IsFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function Guard.Number(min: number, max: number): Check
	return function(value: any): boolean
		return Guard.IsFiniteNumber(value) and value >= min and value <= max
	end
end

function Guard.Integer(min: number, max: number): Check
	return function(value: any): boolean
		return Guard.IsFiniteNumber(value) and value % 1 == 0 and value >= min and value <= max
	end
end

function Guard.String(maxLength: number): Check
	return function(value: any): boolean
		if type(value) ~= "string" or #value > maxLength then
			return false
		end
		return utf8.len(value) ~= nil
	end
end

function Guard.Boolean(): Check
	return function(value: any): boolean
		return type(value) == "boolean"
	end
end

-- Value must be one of the given strings.
function Guard.OneOf(options: { string }): Check
	local set: { [string]: boolean } = {}
	for _, option in options do
		set[option] = true
	end
	return function(value: any): boolean
		return type(value) == "string" and set[value] == true
	end
end

-- Value must be an existing string key of `map` (e.g. a config table).
function Guard.KeyOf(map: { [string]: any }): Check
	return function(value: any): boolean
		return type(value) == "string" and #value <= 100 and map[value] ~= nil
	end
end

function Guard.Optional(check: Check): Check
	return function(value: any): boolean
		return value == nil or check(value)
	end
end

-- Validates a full argument list: exact positional checks, no extra args.
function Guard.Args(...: Check): (...any) -> boolean
	local checks = { ... }
	local count = select("#", ...)
	return function(...: any): boolean
		if select("#", ...) > count then
			return false
		end
		for i = 1, count do
			if not checks[i]((select(i, ...))) then
				return false
			end
		end
		return true
	end
end

return Guard
