local DataSanitizer = require(script.Parent.Parent.Parent.Services.DataService.DataSanitizer)
local DataTemplate = require(script.Parent.Parent.Parent.Services.DataService.DataTemplate)

return function(T)
	T.describe("DataSanitizer", function()
		T.it("default template is clean", function()
			T.expect(#DataSanitizer.Sanitize(DataTemplate.Create(os.time()) :: any, 1e100)).toBe(0)
		end)

		T.it("repairs NaN and infinities", function()
			local data = { a = 0 / 0, b = math.huge, c = -math.huge, d = 5 }
			local issues = DataSanitizer.Sanitize(data, 1e100)
			T.expect(#issues).toBe(3)
			T.expect(data.a).toBe(0)
			T.expect(data.b).toBe(1e100)
			T.expect(data.c).toBe(-1e100)
			T.expect(data.d).toBe(5)
		end)

		T.it("removes unsupported values and non-string keys", function()
			local data = { f = function() end, inst = Instance.new("Folder"), nested = { [true] = 1, ok = "x" } }
			local issues = DataSanitizer.Sanitize(data, 1e100)
			T.expect(#issues).toBe(3)
			T.expect(data.f).toBeNil()
			T.expect(data.inst).toBeNil()
			T.expect(data.nested.ok).toBe("x")
		end)

		T.it("keeps arrays contiguous when removing items", function()
			local data = { list = { "a", function() end, "b", function() end, "c" } }
			DataSanitizer.Sanitize(data, 1e100)
			T.expect(data.list).toEqual({ "a", "b", "c" })
		end)

		T.it("breaks cycles", function()
			local data = { child = {} }
			data.child.parent = data
			local issues = DataSanitizer.Sanitize(data, 1e100)
			T.expect(#issues).toBe(1)
			T.expect(data.child.parent).toBeNil()
		end)
	end)
end
