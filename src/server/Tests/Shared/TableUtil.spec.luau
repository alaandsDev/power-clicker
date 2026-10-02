local TableUtil = require(game:GetService("ReplicatedStorage").Shared.Utils.TableUtil)

return function(T)
	T.describe("TableUtil", function()
		T.it("DeepCopy produces an independent copy", function()
			local original = { a = { b = { 1, 2 } }, c = "x" }
			local copy = TableUtil.DeepCopy(original)
			T.expect(copy).toEqual(original)
			copy.a.b[1] = 99
			T.expect(original.a.b[1]).toBe(1)
		end)

		T.it("Reconcile adds missing keys without overwriting", function()
			local target = { Currencies = { Power = 50 }, Custom = true }
			local template = { Currencies = { Power = 0, Gems = 0 }, Stats = { TotalClicks = 0 } }
			TableUtil.Reconcile(target, template)
			T.expect(target.Currencies.Power).toBe(50)
			T.expect(target.Currencies.Gems).toBe(0)
			T.expect(target.Stats.TotalClicks).toBe(0)
			T.expect(target.Custom).toBe(true) -- unknown keys preserved
		end)

		T.it("Reconcile copies template tables (no shared references)", function()
			local template = { List = { Inner = {} } }
			local a = TableUtil.Reconcile({}, template)
			a.List.Inner.x = 1
			T.expect(template.List.Inner.x).toBeNil()
		end)

		T.it("Reconcile keeps arrays as values", function()
			local target = { Equipped = { "3", "7" } }
			TableUtil.Reconcile(target, { Equipped = { "1" } })
			T.expect(target.Equipped).toEqual({ "3", "7" })
		end)

		T.it("IsArray", function()
			T.expect(TableUtil.IsArray({ 1, 2 })).toBe(true)
			T.expect(TableUtil.IsArray({})).toBe(true)
			T.expect(TableUtil.IsArray({ a = 1 })).toBe(false)
			T.expect(TableUtil.IsArray({ [1] = 1, [3] = 3 })).toBe(false)
		end)

		T.it("DeepFreeze prevents mutation", function()
			local frozen = TableUtil.DeepFreeze({ a = { b = 1 } })
			T.expect(function()
				frozen.a.b = 2
			end).toThrow()
		end)
	end)
end
