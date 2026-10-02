local Migrations = require(script.Parent.Parent.Parent.Services.DataService.Migrations)

return function(T)
	T.describe("Migrations", function()
		T.it("no-op when already at target version", function()
			local data = { DataVersion = 1 }
			local ok = Migrations.Run(data, 1, {})
			T.expect(ok).toBe(true)
			T.expect(data.DataVersion).toBe(1)
		end)

		T.it("runs steps sequentially and bumps the version", function()
			local order = {}
			local steps = {
				[1] = function(data)
					table.insert(order, 1)
					data.Renamed = data.Old
					data.Old = nil
				end,
				[2] = function(data)
					table.insert(order, 2)
					data.Renamed ..= "!"
				end,
			}
			local data = { DataVersion = 1, Old = "value" }
			local ok = Migrations.Run(data, 3, steps)
			T.expect(ok).toBe(true)
			T.expect(order).toEqual({ 1, 2 })
			T.expect(data.DataVersion).toBe(3)
			T.expect(data.Renamed).toBe("value!")
		end)

		T.it("fails on missing steps", function()
			local ok, err = Migrations.Run({ DataVersion = 1 }, 2, {})
			T.expect(ok).toBe(false)
			T.expect(string.find(err, "missing migration", 1, true) ~= nil).toBe(true)
		end)

		T.it("fails (without throwing) when a step errors", function()
			local ok = Migrations.Run({ DataVersion = 1 }, 2, {
				[1] = function()
					error("boom")
				end,
			})
			T.expect(ok).toBe(false)
		end)

		T.it("refuses data from the future", function()
			local ok = Migrations.Run({ DataVersion = 5 }, 2, {})
			T.expect(ok).toBe(false)
		end)

		T.it("refuses invalid versions", function()
			T.expect((Migrations.Run({}, 1, {}))).toBe(false)
			T.expect((Migrations.Run({ DataVersion = "1" }, 1, {}))).toBe(false)
			T.expect((Migrations.Run({ DataVersion = 0 }, 1, {}))).toBe(false)
		end)

		T.it("shipped migration table covers every version below current", function()
			local DataConfig = require(script.Parent.Parent.Parent.ServerConfig.DataConfig)
			for version = 1, DataConfig.DataVersion - 1 do
				T.expect(Migrations.Steps[version] ~= nil).toBe(true)
			end
		end)
	end)
end
