--!strict
--[[
	RateLimiter
	Token bucket keyed by an arbitrary key (usually a Player or UserId).
	Pure logic: time is injectable so it can be unit tested deterministically.

		local limiter = RateLimiter.new(10, 20)  -- burst 10, refill 20/s
		if limiter:Consume(player) then ... end
		limiter:Remove(player)                    -- on PlayerRemoving (avoid leaks)
]]

export type RateLimiter = {
	Consume: (self: RateLimiter, key: any, cost: number?) -> boolean,
	Peek: (self: RateLimiter, key: any) -> number,
	Remove: (self: RateLimiter, key: any) -> (),
	Clear: (self: RateLimiter) -> (),
}

type Bucket = { Tokens: number, Last: number }

type Self = {
	_capacity: number,
	_refill: number,
	_clock: () -> number,
	_buckets: { [any]: Bucket },
}

local RateLimiter = {}
RateLimiter.__index = RateLimiter

function RateLimiter.new(capacity: number, refillPerSecond: number, clock: (() -> number)?): RateLimiter
	assert(capacity > 0, "RateLimiter capacity must be > 0")
	assert(refillPerSecond >= 0, "RateLimiter refill must be >= 0")
	local self: Self = {
		_capacity = capacity,
		_refill = refillPerSecond,
		_clock = clock or os.clock,
		_buckets = {},
	}
	return setmetatable(self, RateLimiter) :: any
end

local function getBucket(self: Self, key: any): Bucket
	local now = self._clock()
	local bucket = self._buckets[key]
	if not bucket then
		bucket = { Tokens = self._capacity, Last = now }
		self._buckets[key] = bucket
	else
		local elapsed = math.max(0, now - bucket.Last)
		bucket.Tokens = math.min(self._capacity, bucket.Tokens + elapsed * self._refill)
		bucket.Last = now
	end
	return bucket
end

-- Returns true and spends `cost` tokens if available; otherwise false and spends nothing.
function RateLimiter.Consume(self: Self, key: any, cost: number?): boolean
	local amount = cost or 1
	local bucket = getBucket(self, key)
	if bucket.Tokens >= amount then
		bucket.Tokens -= amount
		return true
	end
	return false
end

function RateLimiter.Peek(self: Self, key: any): number
	return getBucket(self, key).Tokens
end

function RateLimiter.Remove(self: Self, key: any)
	self._buckets[key] = nil
end

function RateLimiter.Clear(self: Self)
	table.clear(self._buckets)
end

return RateLimiter
