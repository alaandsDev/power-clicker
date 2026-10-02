local Shared = game:GetService("ReplicatedStorage").Shared
local Signal = require(Shared.Utils.Signal)
local Try = require(Shared.Utils.Try)

return function(T)
	T.describe("Signal", function()
		T.it("delivers arguments to every connected handler", function()
			local signal = Signal.new()
			local received = {}
			signal:Connect(function(a, b)
				table.insert(received, a + b)
			end)
			signal:Connect(function(a, b)
				table.insert(received, a * b)
			end)
			signal:Fire(2, 3)
			table.sort(received)
			T.expect(received).toEqual({ 5, 6 })
		end)

		T.it("Disconnect and Once stop delivery", function()
			local signal = Signal.new()
			local count, onceCount = 0, 0
			local connection = signal:Connect(function()
				count += 1
			end)
			signal:Once(function()
				onceCount += 1
			end)
			signal:Fire()
			connection:Disconnect()
			signal:Fire()
			T.expect(count).toBe(1)
			T.expect(onceCount).toBe(1)
			T.expect(connection.Connected).toBe(false)
		end)

		T.it("an erroring handler does not break other handlers", function()
			local signal = Signal.new()
			local reached = false
			signal:Connect(function()
				error("handler failure (expected in test)")
			end)
			signal:Connect(function()
				reached = true
			end)
			signal:Fire()
			T.expect(reached).toBe(true)
		end)
	end)

	T.describe("Try", function()
		T.it("returns true, nil on success and passes arguments", function()
			local got
			local ok, err = Try.Call(function(a, b)
				got = a .. b
			end, "x", "y")
			T.expect(ok).toBe(true)
			T.expect(err).toBeNil()
			T.expect(got).toBe("xy")
		end)

		T.it("returns false and the error message on failure", function()
			local ok, err = Try.Call(function()
				error("boom")
			end)
			T.expect(ok).toBe(false)
			T.expect(string.find(err, "boom", 1, true) ~= nil).toBe(true)
		end)
	end)
end
