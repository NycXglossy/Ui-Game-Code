--!strict
local StorageGuard = require(script.Parent:WaitForChild("StorageGuard"))

-- Per-user temporary incident snapshots. Writes are coalesced and locally rate-limited.
local Service={}; Service.__index=Service
local ALLOWED={SecurityAlert=true,ServiceDegraded=true,AbuseReport=true,ManualReview=true}
local function validUserId(value) return type(value)=="number" and value>=0 and value%1==0 and value<math.huge end
function Service.new(d)
 assert(type(d)=="table" and d.isEnabled and d.memoryStoreService and type(d.authorize)=="function","Incident response dependencies missing")
 return setmetatable({d=d,map=d.memoryStoreService:GetSortedMap(d.mapName or "ClubMusic_GlobalIncidents_v1"),
  opened=0,resolved=0,lastError=nil,lastWriteAt=0,activeByUser={},pendingFlags={},readCache={},readCacheAt={}},Service)
end
function Service:Open(kind,summary,actorUserId,subjectUserId)
 if not self.d.isEnabled() or not ALLOWED[kind] or type(summary)~="string" or #summary<1 or #summary>120 then return false,"Invalid incident." end
 if self.d.authorize(actorUserId,"IncidentResponse")~=true then return false,"Incident response permission denied." end
 local userId=if validUserId(subjectUserId) then math.floor(subjectUserId) else math.floor(actorUserId)
 local key="TT:INC:"..tostring(userId)
 if #key>64 then return false,"Incident key exceeds 64 characters." end
 local now=os.clock()
 local existing=self.activeByUser[userId]
 if existing and now-self.lastWriteAt<1 then
  self.pendingFlags[userId]=(self.pendingFlags[userId] or 1)+1
  existing.localFlags=(existing.localFlags or 0)+1
  return true,existing.id,"Coalesced"
 end
 if now-self.lastWriteAt<1 then return false,"Incident write rate limited." end
 local allowed,reason=StorageGuard.Allow("critical")
 if not allowed then self.pendingFlags[userId]=(self.pendingFlags[userId] or 0)+1; return false,reason end
 local item
 local ok,result=pcall(function()
  return self.map:UpdateAsync(key,function(old)
   local nextItem
   if typeof(old)=="table" and old.state=="Open" then
    nextItem=table.clone(old)
    nextItem.eventCount=(tonumber(nextItem.eventCount) or 1)+1+(self.pendingFlags[userId] or 0)
    nextItem.lastFlagAt=os.time()
    nextItem.lastKind=kind
    nextItem.summary=string.sub(summary,1,120)
   else
    nextItem={id=key,userId=userId,kind=kind,summary=string.sub(summary,1,120),
     openedAt=os.time(),lastFlagAt=os.time(),actorUserId=actorUserId,state="Open",
     eventCount=1+(self.pendingFlags[userId] or 0)}
   end
   local encodedOk,encoded=pcall(self.d.jsonEncode,nextItem)
   if not encodedOk or type(encoded)~="string" or #encoded>5120 then
    item=nil
    return old
   end
   item=nextItem
   return nextItem
  end,math.clamp(math.floor(tonumber(self.d.getTtlSeconds and self.d.getTtlSeconds()) or 3600),3600,86400),os.time())
 end)
 if not ok then self.lastError=tostring(result); StorageGuard.Failure(result); self.pendingFlags[userId]=(self.pendingFlags[userId] or 0)+1; return false,"Incident storage unavailable." end
 if item==nil then return false,"Incident snapshot exceeds the 5 KB safety limit." end
 self.lastWriteAt=now; self.pendingFlags[userId]=nil; self.activeByUser[userId]=item
 self.opened+=1; self.readCache={}; self.readCacheAt={}
 if type(self.d.onChange)=="function" then pcall(self.d.onChange,"opened",item) end
 return true,key
end
function Service:Resolve(id,actorUserId)
 if not self.d.isEnabled() or type(id)~="string" or #id<1 or #id>64 then return false,"Invalid incident ID." end
 if self.d.authorize(actorUserId,"IncidentResponse")~=true then return false,"Incident response permission denied." end
 local now=os.clock()
 if now-self.lastWriteAt<1 then return false,"Incident write rate limited." end
 local allowed,reason=StorageGuard.Allow("critical")
 if not allowed then return false,reason end
 local ok,result=pcall(function()
  local resolved=self.map:UpdateAsync(id,function(old)
   if typeof(old)~="table" or old.state~="Open" then return old end
   local item=table.clone(old); item.state="Resolved"; item.resolvedAt=os.time(); item.resolvedBy=actorUserId
   return item
  end,3600,os.time())
  if typeof(resolved)~="table" or resolved.state~="Resolved" or resolved.resolvedBy~=actorUserId then return nil end
  self.map:RemoveAsync(id)
  return resolved
 end)
 if not ok then self.lastError=tostring(result); StorageGuard.Failure(result); return false,"Incident storage unavailable." end
 if typeof(result)~="table" then return false,"Incident not found, already resolved, or resolution was not applied." end
 self.lastWriteAt=now; self.resolved+=1; self.readCache={}; self.readCacheAt={}
 if validUserId(result.userId) then self.activeByUser[result.userId]=nil end
 if type(self.d.onChange)=="function" then pcall(self.d.onChange,"resolved",result) end
 return true
end
function Service:GetRecent(limit,moderatorUserId)
 if not self.d.isEnabled() then return false,{} end
 local cacheKey=tostring(if validUserId(moderatorUserId) then math.floor(moderatorUserId) else "server")
 local now=os.clock()
 if self.readCache[cacheKey] and now-(self.readCacheAt[cacheKey] or 0)<10 then
  local cached={}; for i,item in ipairs(self.readCache[cacheKey]) do if i>math.clamp(math.floor(tonumber(limit) or 20),1,50) then break end; table.insert(cached,table.clone(item)) end
  return true,cached
 end
 local allowed,reason=StorageGuard.Allow("low")
 if not allowed then self.lastError=reason; return false,{} end
 local ok,result=pcall(function() return self.map:GetRangeAsync(Enum.SortDirection.Descending,math.clamp(math.floor(tonumber(limit) or 20),1,50)) end)
 if not ok then self.lastError=tostring(result); StorageGuard.Failure(result); return false,{} end
 local out={}
 for _,entry in ipairs(result) do if typeof(entry.value)=="table" then table.insert(out,table.clone(entry.value)) end end
 self.readCache[cacheKey]=out; self.readCacheAt[cacheKey]=now
 return true,out
end
function Service:GetStatus()
 local active=0; for _,item in pairs(self.activeByUser) do if item.state=="Open" then active+=1 end end
 return {state=if self.d.isEnabled() then "Healthy" else "Disabled",opened=self.opened,resolved=self.resolved,
  active=active,automaticEnforcement=false,lastError=self.lastError,recordBytes={min=1024,max=5120},
  maxWritesPerSecondPerServer=1,coalescesRapidFlags=true,ttlSeconds={min=3600,max=86400},
  keyStrategy="UserId",adminReadCacheSeconds=10,storageGuard=StorageGuard.GetStatus()}
end
function Service:Start() return true end
function Service:Stop() table.clear(self.readCache); table.clear(self.activeByUser); table.clear(self.pendingFlags) end
return Service
