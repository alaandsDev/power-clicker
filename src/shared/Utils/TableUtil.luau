--!strict
--[[
	TableUtil
	Pure table helpers. No Roblox APIs — safe to unit test.
]]

local TableUtil = {}

-- Deep copy of plain data tables (no metatables, no cycles).
function TableUtil.DeepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value :: any do
		copy[TableUtil.DeepCopy(k)] = TableUtil.DeepCopy(v)
	end
	return (copy :: any) :: T
end

--[[
	Adds keys that exist in `template` but are missing in `target` (deep).
	Never overwrites existing values, never removes unknown keys (data from a
	newer schema or a removed feature is preserved, not destroyed).
	Mutates and returns `target`.

	Arrays in the template are treated as values: an existing value is kept
	as-is; a missing one is copied from the template.
]]
function TableUtil.Reconcile(target: { [any]: any }, template: { [any]: any }): { [any]: any }
	for key, templateValue in template do
		local current = target[key]
		if current == nil then
			target[key] = TableUtil.DeepCopy(templateValue)
		elseif type(current) == "table" and type(templateValue) == "table" and not TableUtil.IsArray(templateValue) then
			TableUtil.Reconcile(current, templateValue)
		end
	end
	return target
end

-- True for sequential 1..n arrays (an empty table counts as an array).
function TableUtil.IsArray(value: any): boolean
	if type(value) ~= "table" then
		return false
	end
	local count = 0
	for _ in value do
		count += 1
	end
	return count == #value
end

function TableUtil.Count(value: { [any]: any }): number
	local count = 0
	for _ in value do
		count += 1
	end
	return count
end

-- Sorted list of the table's keys (keys must be comparable).
function TableUtil.Keys<K>(value: { [K]: any }): { K }
	local keys = {}
	for key in value do
		table.insert(keys, key)
	end
	table.sort(keys :: { any }, function(a: any, b: any)
		return tostring(a) < tostring(b)
	end)
	return keys
end

-- Recursively freezes a table so config modules cannot be mutated at runtime.
function TableUtil.DeepFreeze<T>(value: T): T
	if type(value) == "table" and not table.isfrozen(value :: any) then
		for _, v in value :: any do
			TableUtil.DeepFreeze(v)
		end
		table.freeze(value :: any)
	end
	return value
end

return TableUtil
