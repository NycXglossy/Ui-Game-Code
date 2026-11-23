--!strict
-- Club Neon server-authoritative rate-limit buckets.
-- Per-server budgets intentionally remain local; this module does not use
-- MemoryStore or introduce cross-server rate-limit state.

local RateLimitBuckets = {}

type TokenBucket = {
	tokens: number,
	capacity: number,
	refillPerSecond: number,
	updatedAt: number,
}

function RateLimitBuckets.create(config: any)
	local buckets = {
		globalActionBucket = nil :: TokenBucket?,
		globalAudioBucket = nil :: TokenBucket?,
		globalStateQueryBucket = nil :: TokenBucket?,
		globalCatalogQueryBucket = nil :: TokenBucket?,
		globalDataStoreBucket = nil :: TokenBucket?,
		perPlayerActionBuckets = {} :: {[number]: TokenBucket},
	}

	local function newTokenBucket(capacity: number, refillPerSecond: number): TokenBucket
		return {
			tokens = capacity,
			capacity = capacity,
			refillPerSecond = refillPerSecond,
			updatedAt = os.clock(),
		}
	end

	local function consumeToken(bucket: TokenBucket, now: number, cost: number?): boolean
		local amount = cost or 1
		local elapsed = math.max(0, now - bucket.updatedAt)
		bucket.updatedAt = now
		bucket.tokens = math.min(bucket.capacity, bucket.tokens + elapsed * bucket.refillPerSecond)
		if bucket.tokens < amount then return false end
		bucket.tokens -= amount
		return true
	end

	buckets.globalActionBucket = newTokenBucket(config.GlobalActionBurst, config.GlobalActionRefillPerSecond)
	buckets.globalAudioBucket = newTokenBucket(config.GlobalAudioBurst, config.GlobalAudioRefillPerSecond)
	buckets.globalStateQueryBucket = newTokenBucket(30, 15)
	buckets.globalCatalogQueryBucket = newTokenBucket(30, 15)
	buckets.globalDataStoreBucket = newTokenBucket(config.GlobalDataStoreBurst, config.GlobalDataStoreRefillPerSecond)

	function buckets.newTokenBucket(capacity: number, refillPerSecond: number): TokenBucket
		return newTokenBucket(capacity, refillPerSecond)
	end

	function buckets.consumeToken(bucket: TokenBucket, now: number, cost: number?): boolean
		return consumeToken(bucket, now, cost)
	end

	function buckets.waitForDataStoreBudget(maxWaitSeconds: number): boolean
		local startedAt = os.clock()
		while true do
			if consumeToken(buckets.globalDataStoreBucket :: TokenBucket, os.clock(), 1) then return true end
			if os.clock() - startedAt >= maxWaitSeconds then return false end
			task.wait(0.1)
		end
	end

	function buckets.consumeActionBudget(userId: number, now: number): boolean
		local bucket = buckets.perPlayerActionBuckets[userId]
		if not bucket then
			bucket = newTokenBucket(config.PerPlayerActionBurst, config.PerPlayerActionRefillPerSecond)
			buckets.perPlayerActionBuckets[userId] = bucket
		end
		-- Consume per-player capacity first so a noisy player cannot burn the
		-- shared server budget when their own bucket is already exhausted.
		if not consumeToken(bucket, now, 1) then return false end
		if not consumeToken(buckets.globalActionBucket :: TokenBucket, now, 1) then
			bucket.tokens = math.min(bucket.capacity, bucket.tokens + 1)
			return false
		end
		return true
	end

	return buckets
end

return RateLimitBuckets
