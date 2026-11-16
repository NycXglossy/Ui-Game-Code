--!strict
local StorageGuard = require(script.Parent:WaitForChild("StorageGuard"))
local ResourceGuard = require(script.Parent:WaitForChild("ResourceGuard"))

-- Local-first idempotency. Shared atomic reservations are opt-in for cross-server actions.
local Service={}; Service.__index=Service
function Service.new(d)
 assert(type(d)=="table" and d.memoryStoreService and type(d.isEnabled)=="function","Idempotency dependencies missing")
 return setmetatable({d=d,map=d.memoryStoreService:GetHashMap(d.mapName or "ClubMusic_GlobalIdempotency_v1"),
	seenNonces={},reserved=0,duplicates=0,sharedChecks=0,localHits=0,lastError=nil,
	sharedWindowAt=0,sharedWindowCount=0},Service)
end
function Service:Reserve(operationId,ttlSeconds,crossServer)
 if type(operationId)~="string" or #operationId<1 or #operationId>55 then return false,"Invalid operation key." end
 local now=os.clock()
 local localCount=0
 local oldestKey,oldestAt=nil,math.huge
 for key,entry in pairs(self.seenNonces) do
  if entry.expiresAt<=now then self.seenNonces[key]=nil
  else
   localCount+=1
   local created=tonumber(entry.createdClock) or 0
   if created<oldestAt then oldestKey,oldestAt=key,created end
  end
 end
 if self.seenNonces[operationId] then
  self.localHits+=1; self.duplicates+=1; return false,"Duplicate operation."
 end
 if localCount>=512 and oldestKey then self.seenNonces[oldestKey]=nil end
 local ttl=math.clamp(math.floor(tonumber(ttlSeconds) or 120),60,300)
 -- A purely local action never queries MemoryStore.
 if crossServer~=true then
  self.seenNonces[operationId]={expiresAt=now+ttl,createdAt=os.time(),createdClock=now,bytes=160}
  self.reserved+=1
  return true,"ReservedLocal"
 end
 if not self.d.isEnabled() then return false,"Cross-server idempotency is disabled." end
 if now-self.sharedWindowAt>=1 then self.sharedWindowAt=now; self.sharedWindowCount=0 end
 if self.sharedWindowCount>=2 then return false,"Cross-server idempotency check rate limited." end
 self.sharedWindowCount+=1
 local acquired,release=ResourceGuard.TryAcquire("MemoryStoreWrite")
 if not acquired then return false,"LocalResourceLimit:MemoryStoreWrite" end
 local allowed,reason=StorageGuard.Allow("critical")
 if not allowed then release(); return false,reason end
 local token=self.d.guid()
 local key="TT:IDEM:"..operationId
 if #key>64 then return false,"Idempotency key exceeds 64 characters." end
 self.sharedChecks+=1
 local ok,result=pcall(function()
  return self.map:UpdateAsync(key,function(old)
   if typeof(old)=="table" and type(old.token)=="string" then return old end
   return {token=token,createdAt=os.time(),action=string.sub(operationId,1,48)}
  end,ttl)
 end)
 release()
 if not ok then
  self.lastError=tostring(result); StorageGuard.Failure(result)
  return false,"Idempotency storage unavailable."
 end
 StorageGuard.Success()
 if typeof(result)=="table" and result.token==token then
  self.seenNonces[operationId]={expiresAt=now+ttl,createdAt=os.time(),createdClock=now,bytes=160}
  self.reserved+=1; self.lastError=nil; return true,"Reserved"
 end
 self.duplicates+=1
 self.seenNonces[operationId]={expiresAt=now+ttl,createdAt=os.time(),createdClock=now,bytes=160}
 return false,"Duplicate operation."
end
function Service:GetStatus()
 return {state=if self.d.isEnabled() then "Ready" else "Disabled",reserved=self.reserved,
  duplicates=self.duplicates,localCacheHits=self.localHits,sharedChecks=self.sharedChecks,
  keyStrategy="Direct transaction key",recordBytes={min=100,max=250},storageGuard=StorageGuard.GetStatus(),resourceGuard=ResourceGuard.GetStatus()}
end
function Service:Start() return true end
function Service:Stop() table.clear(self.seenNonces) end
return Service
