--!strict
local StorageGuard = require(script.Parent:WaitForChild("StorageGuard"))
local ResourceGuard = require(script.Parent:WaitForChild("ResourceGuard"))

-- Per-user temporary incident snapshots. All local indexes are bounded.
local Service={}; Service.__index=Service
local ALLOWED={SecurityAlert=true,ServiceDegraded=true,AbuseReport=true,ManualReview=true}
local LOCAL_INDEX_CAP=256
local READ_CACHE_CAPACITY=32
local function cacheRead(self,key,value,now)
	if self.readCache[key]==nil then
		local count=0
		local oldestKey,oldestAt=nil,math.huge
		for existingKey,stamp in pairs(self.readCacheAt) do
			count+=1
			if stamp<oldestAt then oldestAt=stamp; oldestKey=existingKey end
		end
		if count>=READ_CACHE_CAPACITY and oldestKey then
			self.readCache[oldestKey]=nil
			self.readCacheAt[oldestKey]=nil
		end
	end
	self.readCache[key]=value
	self.readCacheAt[key]=now
end
local function validUserId(value)
	return type(value)=="number" and value>=0 and value%1==0 and value<math.huge
end
local function incrementPending(self,userId)
	if self.pendingFlags[userId]==nil then
		local count=0
		for _ in pairs(self.pendingFlags) do count+=1 end
		if count>=LOCAL_INDEX_CAP then return end
	end
	self.pendingFlags[userId]=(self.pendingFlags[userId] or 0)+1
end
local function rememberActive(self,userId,item)
	if self.activeByUser[userId]==nil then
		local count=0
		local oldestId,oldestAt=nil,math.huge
		for id,entry in pairs(self.activeByUser) do
			count+=1
			local stamp=tonumber(entry.lastFlagAt or entry.openedAt) or 0
			if stamp<oldestAt then oldestAt=stamp; oldestId=id end
		end
		if count>=LOCAL_INDEX_CAP and oldestId then self.activeByUser[oldestId]=nil end
	end
	self.activeByUser[userId]=item
end

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
		incrementPending(self,userId)
		existing.localFlags=math.min(1000000,(existing.localFlags or 0)+1)
		return true,existing.id,"Coalesced"
	end
	if now-self.lastWriteAt<1 then return false,"Incident write rate limited." end
	local writeAcquired,releaseWrite=ResourceGuard.TryAcquire("MemoryStoreWrite")
	if not writeAcquired then incrementPending(self,userId); return false,"LocalResourceLimit:MemoryStoreWrite" end
	local incidentAcquired,releaseIncident=ResourceGuard.TryAcquire("IncidentWrite")
	if not incidentAcquired then releaseWrite(); incrementPending(self,userId); return false,"LocalResourceLimit:IncidentWrite" end
	local allowed,reason=StorageGuard.Allow("critical")
	if not allowed then releaseIncident(); releaseWrite(); incrementPending(self,userId); return false,reason end
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
			if not encodedOk or type(encoded)~="string" or #encoded>5120 then item=nil; return old end
			item=nextItem
			return nextItem
		end,math.clamp(math.floor(tonumber(self.d.getTtlSeconds and self.d.getTtlSeconds()) or 1800),900,3600),os.time())
	end)
	releaseIncident(); releaseWrite()
	if not ok then self.lastError=tostring(result); StorageGuard.Failure(result); incrementPending(self,userId); return false,"Incident storage unavailable." end
	StorageGuard.Success()
	if item==nil then return false,"Incident snapshot exceeds the 5 KB safety limit." end
	self.lastWriteAt=now
	self.pendingFlags[userId]=nil
	rememberActive(self,userId,item)
	self.opened+=1
	self.readCache={}; self.readCacheAt={}
	if type(self.d.onChange)=="function" then pcall(self.d.onChange,"opened",item) end
	return true,key
end

function Service:Resolve(id,actorUserId)
 if not self.d.isEnabled() or type(id)~="string" or #id<1 or #id>64 then return false,"Invalid incident ID." end
 if self.d.authorize(actorUserId,"IncidentResponse")~=true then return false,"Incident response permission denied." end
 local now=os.clock()
 if now-self.lastWriteAt<1 then return false,"Incident write rate limited." end
 local writeAcquired,releaseWrite=ResourceGuard.TryAcquire("MemoryStoreWrite")
 if not writeAcquired then return false,"LocalResourceLimit:MemoryStoreWrite" end
 local incidentAcquired,releaseIncident=ResourceGuard.TryAcquire("IncidentWrite")
 if not incidentAcquired then releaseWrite(); return false,"LocalResourceLimit:IncidentWrite" end
 local allowed,reason=StorageGuard.Allow("critical")
 if not allowed then releaseIncident(); releaseWrite(); return false,reason end
 local ok,result=pcall(function()
  return self.map:UpdateAsync(id,function(old)
   if typeof(old)~="table" or old.state~="Open" then return old end
   local item=table.clone(old); item.state="Resolved"; item.resolvedAt=os.time(); item.resolvedBy=actorUserId
   return item
  end,3600,os.time())
 end)
 releaseIncident(); releaseWrite()
 if not ok then self.lastError=tostring(result); StorageGuard.Failure(result); return false,"Incident storage unavailable." end
 StorageGuard.Success()
 if typeof(result)~="table" or result.state~="Resolved" or result.resolvedBy~=actorUserId then
  return false,"Incident not found, already resolved, or resolution was not applied."
 end
 -- Retain the resolved snapshot until TTL expiry. A second RemoveAsync could fail
 -- after the state update succeeds and falsely report the resolution as failed.
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
		local cached={}
		for i,item in ipairs(self.readCache[cacheKey]) do
			if i>math.clamp(math.floor(tonumber(limit) or 20),1,50) then break end
			table.insert(cached,table.clone(item))
		end
		return true,cached
	end
	local allowed,reason=StorageGuard.Allow("low")
	if not allowed then self.lastError=reason; return false,{} end
	local acquired,release=ResourceGuard.TryAcquire("MemoryStoreRead")
	if not acquired then self.lastError="LocalResourceLimit:MemoryStoreRead"; return false,{} end
	local ok,result=pcall(function()
		return self.map:GetRangeAsync(Enum.SortDirection.Descending,math.clamp(math.floor(tonumber(limit) or 20),1,50))
	end)
	release()
	if not ok then self.lastError=tostring(result); StorageGuard.Failure(result); return false,{} end
	StorageGuard.Success()
	local out={}
	for _,entry in ipairs(result) do if typeof(entry.value)=="table" then table.insert(out,table.clone(entry.value)) end end
	cacheRead(self,cacheKey,out,now)
	return true,out
end

function Service:GetStatus()
	local active=0
	for _,item in pairs(self.activeByUser) do if item.state=="Open" then active+=1 end end
	return {state=if self.d.isEnabled() then "Healthy" else "Disabled",opened=self.opened,resolved=self.resolved,
		active=active,localIndexEntries=active,localIndexCapacity=LOCAL_INDEX_CAP,automaticEnforcement=false,
		lastError=self.lastError,recordBytes={min=1024,max=5120},maxWritesPerSecondPerServer=1,
		coalescesRapidFlags=true,ttlSeconds={min=900,max=3600,default=1800},
		keyStrategy="UserId",adminReadCacheSeconds=10,storageGuard=StorageGuard.GetStatus(),
		resourceGuard=ResourceGuard.GetStatus()}
end
function Service:Start() return true end
function Service:Stop()
	table.clear(self.readCache); table.clear(self.readCacheAt)
	table.clear(self.activeByUser); table.clear(self.pendingFlags)
end
return Service
