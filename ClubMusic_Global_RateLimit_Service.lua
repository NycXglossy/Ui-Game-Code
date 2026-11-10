--!strict
-- Facade over the existing shared token buckets; intentionally creates no second limiter.
local Service={}; Service.__index=Service
function Service.new(d)
 assert(type(d)=="table" and type(d.isEnabled)=="function" and type(d.consumeShared)=="function","RateLimit dependencies missing")
 return setmetatable({d=d,checks=0,rejected=0,sharedFailures=0},Service)
end
function Service:Consume(key,capacity,refill,cost)
 if not self.d.isEnabled() then return true,true end
 self.checks+=1
 local ok,shared=self.d.consumeShared(key,capacity,refill,cost)
 if not ok then self.rejected+=1 end
 if not shared then self.sharedFailures+=1 end
 return ok,shared
end
function Service:GetStatus() return {state=if not self.d.isEnabled() then "Disabled" else "Healthy",checks=self.checks,rejected=self.rejected,sharedFailures=self.sharedFailures,usesExistingBuckets=true} end
function Service:Start() return true end
function Service:Stop() end
return Service
