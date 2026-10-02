local RateLimiter = require(game:GetService("ReplicatedStorage").Shared.Utils.RateLimiter)

return function(T)
	T.describe("RateLimiter", function()
		local now = 0
		local function clock()
			return now
		end

		T.it("allows a full burst then blocks", function()
			now = 0
			local limiter = RateLimiter.new(3, 1, clock)
			T.expect(limiter:Consume("a")).toBe(true)
			T.expect(limiter:Consume("a")).toBe(true)
			T.expect(limiter:Consume("a")).toBe(true)
			T.expect(limiter:Consume("a")).toBe(false)
		end)

		T.it("refills over time, capped at capacity", function()
			now = 0
			local limiter = RateLimiter.new(2, 1, clock)
			limiter:Consume("a")
			limiter:Consume("a")
			now = 1
			T.expect(limiter:Consume("a")).toBe(true)
			T.expect(limiter:Consume("a")).toBe(false)
			now = 1000
			T.expect(limiter:Peek("a")).toBe(2)
		end)

		T.it("isolates keys (players)", function()
			now = 0
			local limiter = RateLimiter.new(1, 0.001, clock)
			T.expect(limiter:Consume("a")).toBe(true)
			T.expect(limiter:Consume("a")).toBe(false)
			T.expect(limiter:Consume("b")).toBe(true)
		end)

		T.it("does not spend tokens on a failed consume", function()
			now = 0
			local limiter = RateLimiter.new(2, 0, clock)
			T.expect(limiter:Consume("a", 3)).toBe(false)
			T.expect(limiter:Peek("a")).toBe(2)
		end)

		T.it("ignores clock going backwards", function()
			now = 10
			local limiter = RateLimiter.new(1, 1, clock)
			limiter:Consume("a")
			now = 5
			T.expect(limiter:Consume("a")).toBe(false)
		end)

		T.it("simulated spam: 1000 requests in 1s at 20/s + burst 10 allows ~30", function()
			now = 0
			local limiter = RateLimiter.new(10, 20, clock)
			local allowed = 0
			for i = 1, 1000 do
				now = i / 1000
				if limiter:Consume("p") then
					allowed += 1
				end
			end
			T.expect(allowed <= 31).toBe(true)
			T.expect(allowed >= 29).toBe(true)
		end)

		T.it("Remove frees the bucket", function()
			now = 0
			local limiter = RateLimiter.new(1, 0.001, clock)
			limiter:Consume("a")
			limiter:Remove("a")
			T.expect(limiter:Consume("a")).toBe(true)
		end)
	end)
end
