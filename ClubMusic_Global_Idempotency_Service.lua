--!strict
-- Atomic cross-server operation reservations using expiring MemoryStore keys.
local Service={}; Service.__index=Service
function Service.new(d)
 assert(type(d)=="table" and d.memoryStoreService and type(d.isEnabled)=="function","Idempotency dependencies missing")
 return setmetatable({d=d,map=d.memoryStoreService:GetHashMap(d.mapName or "ClubMusic_GlobalIdempotency_v1"),reserved=0,duplicates=0},Service)
end
function Service:Reserve(operationId,ttlSeconds)
 if not self.d.isEnabled() or type(operationId)~="string" or #operationId<1 or #operationId>128 then return false,"Invalid or disabled operation." end
 local ttl=math.clamp(math.floor(tonumber(ttlSeconds) or 120),30,600)
 local token=self.d.guid()
 local ok,result=pcall(function()
  return self.map:UpdateAsync("op:"..operationId,function(old)
   if typeof(old)=="table" and type(old.token)=="string" then return old end
   return {token=token,createdAt=os.time()}
  end,ttl)
 end)
 if not ok then return false,"Idempotency storage unavailable." end
 if typeof(result)=="table" and result.token==token then self.reserved+=1; return true,"Reserved" end
 self.duplicates+=1; return false,"Duplicate operation."
end
function Service:GetStatus() return {state=if self.d.isEnabled() then "Ready" else "Disabled",reserved=self.reserved,duplicates=self.duplicates} end
function Service:Start() return true end
function Service:Stop() end
return Service
