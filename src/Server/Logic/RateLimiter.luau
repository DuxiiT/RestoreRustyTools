-- Per-player, per-remote token buckets.
local RateLimiter = {}
RateLimiter.__index = RateLimiter

function RateLimiter.New(Clock)
	return setmetatable({ Buckets = {}, Clock = Clock or os.clock }, RateLimiter)
end

function RateLimiter:Allow(Key, Name: string, Rate): boolean
	local Now = self.Clock()
	local PlayerBuckets = self.Buckets[Key]
	if not PlayerBuckets then
		PlayerBuckets = {}
		self.Buckets[Key] = PlayerBuckets
	end
	local Bucket = PlayerBuckets[Name]
	if not Bucket then
		Bucket = { Tokens = Rate.Count, Updated = Now }
		PlayerBuckets[Name] = Bucket
	end
	local RefillPerSecond = Rate.Count / Rate.Window
	Bucket.Tokens = math.min(Rate.Count, Bucket.Tokens + (Now - Bucket.Updated) * RefillPerSecond)
	Bucket.Updated = Now
	if Bucket.Tokens < 1 then
		return false
	end
	Bucket.Tokens -= 1
	return true
end

function RateLimiter:Forget(Key)
	self.Buckets[Key] = nil
end

return RateLimiter
