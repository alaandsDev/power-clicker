local ClickPatternDetector = require(script.Parent.Parent.Parent.Logic.ClickPatternDetector)

return function(T)
	T.describe("ClickPatternDetector", function()
		T.it("flags machine-regular fast clicking", function()
			local detector = ClickPatternDetector.new(30, 0.003, 0.12)
			local flagged = false
			for i = 0, 40 do
				if detector:Record(i * 0.05) then -- exactly 20 CPS, zero jitter
					flagged = true
				end
			end
			T.expect(flagged).toBe(true)
		end)

		T.it("does not flag human-like jitter", function()
			local detector = ClickPatternDetector.new(30, 0.003, 0.12)
			local random = Random.new(42)
			local now = 0
			local flagged = false
			for _ = 1, 200 do
				now += 0.1 + random:NextNumber(-0.03, 0.03)
				if detector:Record(now) then
					flagged = true
				end
			end
			T.expect(flagged).toBe(false)
		end)

		T.it("ignores slow regular clicking", function()
			local detector = ClickPatternDetector.new(30, 0.003, 0.12)
			local flagged = false
			for i = 0, 60 do
				if detector:Record(i * 0.5) then
					flagged = true
				end
			end
			T.expect(flagged).toBe(false)
		end)

		T.it("one pattern produces one signal per window", function()
			local detector = ClickPatternDetector.new(10, 0.003, 0.12)
			local signals = 0
			for i = 0, 25 do
				if detector:Record(i * 0.05) then
					signals += 1
				end
			end
			T.expect(signals).toBe(2) -- 25 intervals / window of 10
		end)
	end)
end
