--!strict
--[[
	RateLimiter — seau à jetons (token bucket) par clé.

	Chaque remote serveur a son propre limiteur (capacité = rafale tolérée, refill = débit
	soutenu). Un client qui spamme un remote vide son seau : les requêtes excédentaires sont
	ignorées et signalées à l'AntiCheatService (score de suspicion), sans jamais bloquer le
	thread serveur. Les clés sont typiquement des Player (table faible : pas de fuite quand
	le joueur part).

	`clock` est injectable : les tests unitaires contrôlent le temps.
]]

export type RateLimiter = {
	capacity: number,
	refill: number,
	consume: (self: RateLimiter, key: any, cost: number?) -> boolean,
	peek: (self: RateLimiter, key: any) -> number,
	reset: (self: RateLimiter, key: any) -> (),
}

type Bucket = { tokens: number, last: number }

local RateLimiterClass = {}
RateLimiterClass.__index = RateLimiterClass

local function getBucket(self: any, key: any): Bucket
	local bucket = self._buckets[key]
	local now = self._clock()
	if not bucket then
		bucket = { tokens = self.capacity, last = now }
		self._buckets[key] = bucket
		return bucket
	end
	local elapsed = now - bucket.last
	if elapsed > 0 then
		bucket.tokens = math.min(self.capacity, bucket.tokens + elapsed * self.refill)
		bucket.last = now
	end
	return bucket
end

function RateLimiterClass.consume(self: any, key: any, cost: number?): boolean
	local bucket = getBucket(self, key)
	local price = cost or 1
	if bucket.tokens >= price then
		bucket.tokens -= price
		return true
	end
	return false
end

function RateLimiterClass.peek(self: any, key: any): number
	return getBucket(self, key).tokens
end

function RateLimiterClass.reset(self: any, key: any)
	self._buckets[key] = nil
end

local RateLimiter = {}

function RateLimiter.new(capacity: number, refillPerSecond: number, clock: (() -> number)?): RateLimiter
	local self = {
		capacity = capacity,
		refill = refillPerSecond,
		_clock = clock or os.clock,
		_buckets = setmetatable({}, { __mode = "k" }),
	}
	return (setmetatable(self, RateLimiterClass) :: any) :: RateLimiter
end

return RateLimiter
