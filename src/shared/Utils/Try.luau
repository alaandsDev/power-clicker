--!strict
--[[
	Try
	Protected call helper with a stable, well-typed result:
		local ok, err = Try.Call(fn, a, b)
	`err` is a string with a traceback when `fn` errors, nil otherwise.

	(Plain pcall/xpcall on a function that returns nothing is typed as
	returning only `boolean`, which hides the error value in strict mode.)
]]

local Try = {}

function Try.Call(fn: (...any) -> ...any, ...: any): (boolean, string?)
	local args = table.pack(...)
	local ok, err = xpcall(function(): any
		fn(table.unpack(args, 1, args.n))
		return nil
	end, debug.traceback)
	if ok then
		return true, nil
	end
	return false, tostring(err)
end

return Try
