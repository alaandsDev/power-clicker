--!strict
--[[
	DataSanitizer
	Makes a data table DataStore-safe before saving and reports what it fixed.
	A single NaN or a stray Instance would make the whole save fail, which
	would then lose ALL progress since the last good save — so bad values are
	repaired/removed and loudly reported instead.

	- NaN            -> 0
	- +inf / > max   -> maxValue
	- -inf           -> -maxValue
	- functions, Instances, other userdata, threads -> removed
	- non-string keys in dictionaries (or mixed tables) -> removed
	- cyclic references -> removed
]]

local TableUtil = require(game:GetService("ReplicatedStorage").Shared.Utils.TableUtil)

local DataSanitizer = {}

local function sanitizeNumber(value: number, maxValue: number): (number, boolean)
	if value ~= value then
		return 0, true
	elseif value > maxValue then
		return maxValue, true
	elseif value < -maxValue then
		return -maxValue, true
	end
	return value, false
end

-- Mutates `root` in place. Returns the list of issues found (empty = clean).
function DataSanitizer.Sanitize(root: { [any]: any }, maxValue: number): { string }
	local issues: { string } = {}
	local visiting: { [any]: boolean } = {}

	local function walk(node: { [any]: any }, path: string)
		visiting[node] = true
		local isArray = TableUtil.IsArray(node)
		local removals: { any } = {}

		for key, value in node do
			local keyPath = path .. "." .. tostring(key)
			if not isArray and type(key) ~= "string" then
				table.insert(issues, keyPath .. ": non-string key removed")
				table.insert(removals, key)
				continue
			end

			local valueType = type(value)
			if valueType == "number" then
				local fixed, changed = sanitizeNumber(value, maxValue)
				if changed then
					table.insert(issues, keyPath .. ": invalid number " .. tostring(value) .. " -> " .. tostring(fixed))
					node[key] = fixed
				end
			elseif valueType == "table" then
				if visiting[value] then
					table.insert(issues, keyPath .. ": cyclic reference removed")
					table.insert(removals, key)
				else
					walk(value, keyPath)
				end
			elseif valueType ~= "string" and valueType ~= "boolean" then
				table.insert(issues, keyPath .. ": unsupported " .. typeof(value) .. " removed")
				table.insert(removals, key)
			end
		end

		if isArray then
			-- Remove from the end so earlier indices stay valid; keeps arrays contiguous.
			table.sort(removals, function(a, b)
				return a > b
			end)
			for _, index in removals do
				table.remove(node, index)
			end
		else
			for _, key in removals do
				node[key] = nil
			end
		end
		visiting[node] = nil
	end

	walk(root, "Data")
	return issues
end

return DataSanitizer
