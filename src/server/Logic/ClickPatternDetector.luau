--!strict
--[[
	ClickPatternDetector
	Flags click timing that is implausibly regular for a human (macro /
	autoclicker). This is only a SIGNAL for AntiExploitService — it never
	blocks clicks or punishes by itself. Rate limiting is separate (NetService).

	Humans at high speed show interval jitter of several milliseconds; a
	software clicker at a fixed rate typically shows ~0-2 ms.
]]

export type Detector = {
	Record: (self: Detector, now: number) -> boolean,
	Reset: (self: Detector) -> (),
}

type Self = {
	_size: number,
	_minStdDev: number,
	_maxMean: number,
	_intervals: { number },
	_index: number,
	_count: number,
	_last: number?,
}

local ClickPatternDetector = {}
ClickPatternDetector.__index = ClickPatternDetector

--[[
	sampleSize: intervals analysed (window)
	minStdDevSeconds: below this jitter the pattern is "too regular"
	maxMeanSeconds: only fast clicking is analysed (slow regular clicks are fine)
]]
function ClickPatternDetector.new(sampleSize: number, minStdDevSeconds: number, maxMeanSeconds: number): Detector
	local self: Self = {
		_size = sampleSize,
		_minStdDev = minStdDevSeconds,
		_maxMean = maxMeanSeconds,
		_intervals = table.create(sampleSize, 0),
		_index = 0,
		_count = 0,
		_last = nil,
	}
	return setmetatable(self, ClickPatternDetector) :: any
end

-- Records a click. Returns true when the current window looks automated;
-- the window is then cleared so one pattern produces one signal.
function ClickPatternDetector.Record(self: Self, now: number): boolean
	local last = self._last
	self._last = now
	if last == nil then
		return false
	end
	self._index = (self._index % self._size) + 1
	self._intervals[self._index] = now - last
	self._count = math.min(self._count + 1, self._size)
	if self._count < self._size then
		return false
	end

	local sum = 0
	for _, interval in self._intervals do
		sum += interval
	end
	local mean = sum / self._size
	if mean > self._maxMean then
		return false
	end
	local variance = 0
	for _, interval in self._intervals do
		variance += (interval - mean) ^ 2
	end
	local stdDev = math.sqrt(variance / self._size)
	if stdDev < self._minStdDev then
		ClickPatternDetector.Reset(self)
		self._last = now
		return true
	end
	return false
end

function ClickPatternDetector.Reset(self: Self)
	self._index = 0
	self._count = 0
	self._last = nil
end

return ClickPatternDetector
