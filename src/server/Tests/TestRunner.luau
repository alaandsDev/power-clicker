--!strict
--[[
	TestRunner
	Tiny dependency-free unit test runner. Runs every ModuleScript named
	"*.spec" under the given folder. Studio only (see ServerBootstrap).

	Spec format:
		return function(T)
			T.describe("Thing", function()
				T.it("does X", function()
					T.expect(1 + 1).toBe(2)
				end)
			end)
		end

	Specs must only test pure modules or explicit Mock* backends — never live
	DataStores or real purchases.
]]

local TableUtil = require(game:GetService("ReplicatedStorage").Shared.Utils.TableUtil)

export type Expectation = {
	toBe: (expected: any) -> (),
	toEqual: (expected: any) -> (),
	toBeNear: (expected: number, epsilon: number?) -> (),
	toBeTruthy: () -> (),
	toBeFalsy: () -> (),
	toBeNil: () -> (),
	toBeGreaterThan: (value: number) -> (),
	toBeLessThan: (value: number) -> (),
	toThrow: () -> (),
	toContain: (item: any) -> (),
}

export type T = {
	describe: (name: string, body: () -> ()) -> (),
	it: (name: string, body: () -> ()) -> (),
	expect: (actual: any) -> Expectation,
}

local TestRunner = {}

local function deepEqual(a: any, b: any): boolean
	if type(a) ~= type(b) then
		return false
	end
	if type(a) ~= "table" then
		return a == b
	end
	for k, v in a do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function show(value: any): string
	if type(value) == "table" then
		local parts = {}
		for _, key in TableUtil.Keys(value) do
			table.insert(parts, tostring(key) .. "=" .. show(value[key]))
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return tostring(value)
end

local function expect(actual: any): Expectation
	local function check(condition: boolean, message: string)
		if not condition then
			error(message, 3)
		end
	end
	return {
		toBe = function(expected: any)
			check(actual == expected, string.format("expected %s to be %s", show(actual), show(expected)))
		end,
		toEqual = function(expected: any)
			check(deepEqual(actual, expected), string.format("expected %s to equal %s", show(actual), show(expected)))
		end,
		toBeNear = function(expected: number, epsilon: number?)
			local eps = epsilon or 1e-9
			check(type(actual) == "number" and math.abs(actual - expected) <= eps, string.format("expected %s to be near %s", show(actual), show(expected)))
		end,
		toBeTruthy = function()
			check(actual and true or false, string.format("expected %s to be truthy", show(actual)))
		end,
		toBeFalsy = function()
			check(not actual, string.format("expected %s to be falsy", show(actual)))
		end,
		toBeNil = function()
			check(actual == nil, string.format("expected %s to be nil", show(actual)))
		end,
		toBeGreaterThan = function(value: number)
			check(type(actual) == "number" and actual > value, string.format("expected %s > %s", show(actual), show(value)))
		end,
		toBeLessThan = function(value: number)
			check(type(actual) == "number" and actual < value, string.format("expected %s < %s", show(actual), show(value)))
		end,
		toThrow = function()
			check(type(actual) == "function" and not pcall(actual), "expected function to throw")
		end,
		toContain = function(item: any)
			check(type(actual) == "table" and table.find(actual, item) ~= nil, string.format("expected %s to contain %s", show(actual), show(item)))
		end,
	}
end

export type Result = { Passed: number, Failed: number, Failures: { string } }

-- pcall with a typed (ok, message) result and without a traceback, so test
-- failure lines stay short. (pcall on a no-return function hides `err` in strict mode.)
local function run(body: () -> ()): (boolean, string?)
	local ok, err = pcall(function(): any
		body()
		return nil
	end)
	return ok, if ok then nil else tostring(err)
end

function TestRunner.RunSpec(name: string, spec: (T) -> ()): Result
	local result: Result = { Passed = 0, Failed = 0, Failures = {} }
	local prefix: { string } = { name }

	local api: T = {
		describe = function(describeName: string, body: () -> ())
			table.insert(prefix, describeName)
			local ok, err = run(body)
			if not ok then
				result.Failed += 1
				table.insert(result.Failures, table.concat(prefix, " > ") .. " [describe error]: " .. tostring(err))
			end
			table.remove(prefix)
		end,
		it = function(testName: string, body: () -> ())
			local ok, err = run(body)
			if ok then
				result.Passed += 1
			else
				result.Failed += 1
				table.insert(result.Failures, table.concat(prefix, " > ") .. " > " .. testName .. ": " .. tostring(err))
			end
		end,
		expect = expect,
	}

	local ok, err = run(function()
		spec(api)
	end)
	if not ok then
		result.Failed += 1
		table.insert(result.Failures, name .. " [spec error]: " .. tostring(err))
	end
	return result
end

function TestRunner.RunAll(root: Instance): Result
	local total: Result = { Passed = 0, Failed = 0, Failures = {} }
	local started = os.clock()

	local specs = {}
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("ModuleScript") and string.match(descendant.Name, "%.spec$") then
			table.insert(specs, descendant)
		end
	end
	table.sort(specs, function(a, b)
		return a.Name < b.Name
	end)

	for _, module in specs do
		local okRequire, spec = pcall(require, module)
		local result: Result
		if not okRequire or type(spec) ~= "function" then
			result = { Passed = 0, Failed = 1, Failures = { module.Name .. " [require error]: " .. tostring(spec) } }
		else
			result = TestRunner.RunSpec(module.Name, spec)
		end
		total.Passed += result.Passed
		total.Failed += result.Failed
		for _, failure in result.Failures do
			table.insert(total.Failures, failure)
		end
	end

	local summary = string.format("[TESTS] %d passed, %d failed (%d specs, %.0f ms)", total.Passed, total.Failed, #specs, (os.clock() - started) * 1000)
	if total.Failed > 0 then
		for _, failure in total.Failures do
			warn("[TESTS][FAIL] " .. failure)
		end
		warn(summary)
	else
		print(summary)
	end
	return total
end

return TestRunner
