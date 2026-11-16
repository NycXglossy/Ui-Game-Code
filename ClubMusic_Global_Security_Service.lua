--!strict
-- Consolidated ClubMusic security services.
-- Each service keeps its original constructor and public methods; the bundle only
-- centralizes module delivery and does not merge or weaken their responsibilities.
local Bundle = {}

-- Per-server MemoryStore protection shared by the bundled security services.
-- Enforcement and authorization never depend on this reporting/storage guard.
local StorageGuard = (function()
	local tokens = 5
	local updatedAt = os.clock()
	local openUntil = 0
	local failures = 0
	local function isThrottleOrTimeout(err)
		local message = string.lower(tostring(err))
		return string.find(message, "thrott", 1, true) ~= nil
			or string.find(message, "timeout", 1, true) ~= nil
			or string.find(message, "timed out", 1, true) ~= nil
			or string.find(message, "request queue", 1, true) ~= nil
	end
	local function Allow()
		local now = os.clock()
		if now < openUntil then return false, "CircuitOpen" end
		tokens = math.min(5, tokens + math.max(0, now - updatedAt) * 0.2)
		updatedAt = now
		if tokens < 1 then return false, "LocalTokenBucketEmpty" end
		tokens -= 1
		return true
	end
	local function Failure(err)
		if isThrottleOrTimeout(err) then
			failures += 1
			openUntil = os.clock() + math.random(15, 30)
			return true
		end
		return false
	end
	local function GetStatus()
		return {tokens = tokens, circuitOpen = os.clock() < openUntil,
			openForSeconds = math.max(0, openUntil - os.clock()), failures = failures,
			refillPerSecond = 0.2, capacity = 5}
	end
	return {Allow = Allow, Failure = Failure, GetStatus = GetStatus}
end)()

Bundle.Authorization = (function()
--!strict
-- Local authorization adapter for ClubMusic global controls.
-- This service is intentionally independent of cross-server enablement and Studio isolation.
-- It always denies by default unless the controller supplies a trusted permission resolver.

local Service = {}
Service.__index = Service

local ALLOWED_PERMISSIONS = {
	GlobalDJ = true,
	GlobalModeration = true,
	GlobalAnnouncement = true,
	GlobalConfig = true,
	SecurityPolicy = true,
	IncidentResponse = true,
}

local function validActor(actorUserId: any): boolean
	return typeof(actorUserId) == "number"
		and actorUserId == actorUserId
		and actorUserId > 0
		and actorUserId < math.huge
		and actorUserId % 1 == 0
end

function Service.new(dependencies: {[string]: any})
	assert(typeof(dependencies) == "table", "Authorization dependencies missing")
	assert(type(dependencies.resolvePermission) == "function", "Trusted permission resolver is required")

	return setmetatable({
		dependencies = dependencies,
		checks = 0,
		denied = 0,
		lastError = nil,
		started = false,
	}, Service)
end

function Service:Start(): boolean
	-- Do not require DataStore, MemoryStore, MessagingService, or global enablement.
	self.started = true
	return true
end

function Service:Check(actorUserId: any, permission: any): (boolean, string?)
	if not validActor(actorUserId) or typeof(permission) ~= "string"
		or not ALLOWED_PERMISSIONS[permission] then
		self.denied += 1
		return false, "Invalid actor or permission."
	end

	local resolver = self.dependencies.resolvePermission
	if type(resolver) ~= "function" then
		self.denied += 1
		self.lastError = "Trusted permission resolver is unavailable."
		return false, self.lastError
	end

	local ok, allowed = pcall(resolver, math.floor(actorUserId), permission)
	self.checks += 1
	if not ok then
		self.denied += 1
		self.lastError = string.sub(tostring(allowed), 1, 180)
		warn("[ClubMusic][Authorization] Trusted resolver failed; permission=" .. permission
			.. "; error=" .. self.lastError)
		return false, "Authorization resolver failed."
	end
	if allowed ~= true then
		self.denied += 1
		return false, "Permission denied."
	end

	self.lastError = nil
	return true
end

function Service:GetStatus(): {[string]: any}
	local available = false
	local availabilityError = nil
	if type(self.dependencies.isResolverAvailable) == "function" then
		local ok, result = pcall(self.dependencies.isResolverAvailable)
		available = ok and result == true
		if not ok then availabilityError = string.sub(tostring(result), 1, 180) end
	end

	return {
		state = if not self.started then "Stopped" elseif available then "Ready" else "ResolverUnavailable",
		started = self.started,
		resolverAvailable = available,
		checks = self.checks,
		denied = self.denied,
		lastError = self.lastError or availabilityError,
		default = "Deny",
	}
end

function Service:Stop()
	self.started = false
end

return Service

end)()

Bundle.RateLimit = (function()
--!strict
-- Facade over the existing shared token buckets; intentionally creates no second limiter.
local Service = {}
Service.__index = Service

local function isFiniteNumber(value)
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function Service.new(dependencies)
	assert(type(dependencies) == "table", "RateLimit dependencies must be a table")
	assert(type(dependencies.isEnabled) == "function", "RateLimit requires isEnabled")
	assert(type(dependencies.consumeShared) == "function", "RateLimit requires consumeShared")
	return setmetatable({
		d = dependencies,
		checks = 0,
		rejected = 0,
		sharedFailures = 0,
		lastError = nil,
	}, Service)
end

function Service:Consume(key, capacity, refill, cost)
	local enabledOk, enabled = pcall(self.d.isEnabled)
	if not enabledOk then
		self.lastError = tostring(enabled)
		return false, false
	end
	-- Cross-server limits are deliberately bypassed while global service is disabled
	-- (for example, ordinary isolated Studio sessions).
	if enabled ~= true then return true, true end
	if type(key) ~= "string" or #key < 1 or #key > 100
		or not isFiniteNumber(capacity) or capacity <= 0
		or not isFiniteNumber(refill) or refill < 0
		or not isFiniteNumber(cost) or cost <= 0 or cost > capacity then
		self.rejected += 1
		return false, false
	end
	self.checks += 1
	local callOk, allowed, shared = pcall(self.d.consumeShared, key, capacity, refill, cost)
	if not callOk then
		self.sharedFailures += 1
		self.rejected += 1
		self.lastError = tostring(allowed)
		return false, false
	end
	if allowed ~= true then self.rejected += 1 end
	if shared ~= true then self.sharedFailures += 1 end
	self.lastError = nil
	return allowed == true, shared == true
end

function Service:GetStatus()
	local enabledOk, enabled = pcall(self.d.isEnabled)
	local state = if not enabledOk then "Degraded" else if enabled ~= true then "Disabled" else "Healthy"
	return {
		state = state,
		checks = self.checks,
		rejected = self.rejected,
		sharedFailures = self.sharedFailures,
		usesExistingBuckets = true,
		lastError = self.lastError,
	}
end

function Service:Start()
	return true
end

function Service:Stop()
end

return Service

end)()

Bundle.MessageValidation = (function()
--!strict
-- Shared envelope validation for cross-server messages; topic handlers still validate payload schemas.
local Service={}; Service.__index=Service
local KINDS={Announcements={Announcement=true},Moderation={Moderation=true},DJ={DJ=true},XPBoost={XPBoost=true},Catalog={Catalog=true},Queue={QueueChanged=true,ServerHeartbeat=true},Playback={PlaybackChanged=true,PlaybackSyncModeChanged=true,PlaybackCommand=true}}
function Service.new(d)
 assert(type(d)=="table" and type(d.getJobId)=="function","Message validation dependencies missing")
 return setmetatable({d=d,accepted=0,rejected=0},Service)
end
function Service:Validate(topic,data)
 local function reject(reason) self.rejected+=1; return false,reason end
 if type(topic)~="string" or not KINDS[topic] or typeof(data)~="table" then return reject("Unknown topic or non-table payload.") end
 if data.version~=1 or typeof(data.senderJob)~="string" or #data.senderJob<1 or #data.senderJob>64 or data.senderJob==self.d.getJobId() then return reject("Invalid message identity.") end
 if typeof(data.id)~="string" or #data.id<1 or #data.id>64 then return reject("Invalid message ID.") end
 if typeof(data.at)~="number" or data.at~=data.at or data.at==math.huge or data.at==-math.huge or math.abs(os.time()-data.at)>(self.d.getMaxAge and self.d.getMaxAge() or 120) then return reject("Invalid or expired timestamp.") end
 if not KINDS[topic][data.kind] then return reject("Message kind is not allowed for topic.") end
 local ok,encoded=pcall(function() return self.d.jsonEncode(data) end)
 if not ok or type(encoded)~="string" or #encoded>(self.d.getMaxBytes and self.d.getMaxBytes() or self.d.maxBytes or 4096) then return reject("Message exceeds size limit or cannot be encoded.") end
 self.accepted+=1; return true
end
function Service:GetStatus() return {state="Ready",accepted=self.accepted,rejected=self.rejected} end
function Service:Start() return true end
function Service:Stop() end
return Service

end)()

Bundle.Idempotency = (function()
--!strict
-- Local-first idempotency. Shared atomic reservations are opt-in for cross-server actions.
local Service={}; Service.__index=Service
function Service.new(d)
 assert(type(d)=="table" and d.memoryStoreService and type(d.isEnabled)=="function","Idempotency dependencies missing")
 return setmetatable({d=d,map=d.memoryStoreService:GetHashMap(d.mapName or "ClubMusic_GlobalIdempotency_v1"),
	seenNonces={},reserved=0,duplicates=0,sharedChecks=0,localHits=0,lastError=nil},Service)
end
function Service:Reserve(operationId,ttlSeconds,crossServer)
 if type(operationId)~="string" or #operationId<1 or #operationId>55 then return false,"Invalid operation key." end
 local now=os.clock()
 for key,entry in pairs(self.seenNonces) do if entry.expiresAt<=now then self.seenNonces[key]=nil end end
 if self.seenNonces[operationId] then
  self.localHits+=1; self.duplicates+=1; return false,"Duplicate operation."
 end
 local ttl=math.clamp(math.floor(tonumber(ttlSeconds) or 120),60,300)
 -- A purely local action never queries MemoryStore.
 if crossServer~=true then
  self.seenNonces[operationId]={expiresAt=now+ttl,createdAt=os.time(),bytes=160}
  self.reserved+=1
  return true,"ReservedLocal"
 end
 if not self.d.isEnabled() then return false,"Cross-server idempotency is disabled." end
 local allowed,reason=StorageGuard.Allow()
 if not allowed then return false,reason end
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
 if not ok then
  self.lastError=tostring(result); StorageGuard.Failure(result)
  return false,"Idempotency storage unavailable."
 end
 if typeof(result)=="table" and result.token==token then
  self.seenNonces[operationId]={expiresAt=now+ttl,createdAt=os.time(),bytes=160}
  self.reserved+=1; self.lastError=nil; return true,"Reserved"
 end
 self.duplicates+=1
 self.seenNonces[operationId]={expiresAt=now+ttl,createdAt=os.time(),bytes=160}
 return false,"Duplicate operation."
end
function Service:GetStatus()
 return {state=if self.d.isEnabled() then "Ready" else "Disabled",reserved=self.reserved,
  duplicates=self.duplicates,localCacheHits=self.localHits,sharedChecks=self.sharedChecks,
  keyStrategy="Direct transaction key",recordBytes={min=100,max=250},storageGuard=StorageGuard.GetStatus()}
end
function Service:Start() return true end
function Service:Stop() table.clear(self.seenNonces) end
return Service
end)()

Bundle.SecurityMonitor = (function()
--!strict
-- Bounded, observational security signal aggregation. Never bans or restricts players.
local Service={}; Service.__index=Service
function Service.new(d)
 assert(type(d)=="table" and type(d.isEnabled)=="function","Security monitor dependencies missing")
 return setmetatable({d=d,signals={},total=0,alerts=0,lastAlertAt=0},Service)
end
function Service:Record(signal,subject)
 if not self.d.isEnabled() or type(signal)~="string" or #signal<1 or #signal>48 then return false end
 local key=signal..":"..string.sub(tostring(subject or "server"),1,64)
 local now=os.clock(); local entry=self.signals[key]
 if not entry then
  local count=0; for _ in pairs(self.signals) do count+=1 end
  if count>=512 then
   local oldestKey,oldestAt=nil,math.huge
   for k,v in pairs(self.signals) do if v.updated<oldestAt then oldestKey,oldestAt=k,v.updated end end
   if oldestKey then self.signals[oldestKey]=nil end
  end
  entry={count=0,windowStart=now,updated=now}; self.signals[key]=entry
 end
 if now-entry.windowStart>60 then entry.count=0; entry.windowStart=now end
 entry.count+=1; entry.updated=now; self.total+=1
 local configured=if type(self.d.getThreshold)=="function" then self.d.getThreshold() else self.d.threshold
 local threshold=if type(configured)=="number" then math.max(1,math.floor(configured)) else 8
 if entry.count==threshold then
  self.alerts+=1; self.lastAlertAt=os.time()
  if type(self.d.onAlert)=="function" then pcall(self.d.onAlert,signal,entry.count) end
 end
 return true,entry.count
end
function Service:GetStatus() return {state=if self.d.isEnabled() then "Observing" else "Disabled",totalSignals=self.total,alerts=self.alerts,trackedKeys=(function() local n=0; for _ in pairs(self.signals) do n+=1 end; return n end)(),lastAlertAt=self.lastAlertAt,automaticEnforcement=false} end
function Service:Start() return true end
function Service:Stop() end
return Service

end)()

Bundle.SecurityPolicy = (function()
--!strict
-- Shared security policy backed by the existing revisioned Global Config DataStore.
local Service={}; Service.__index=Service
local RANGES={
 messageMaxBytes={512,4096},messageMaxAgeSeconds={30,300},suspiciousSignalThreshold={3,100},idempotencyTtlSeconds={30,600}
}
function Service.new(d)
 assert(type(d)=="table" and d.configService and type(d.authorize)=="function","Security policy dependencies missing")
 return setmetatable({d=d},Service)
end
function Service:Get(key) return self.d.configService:Get(key) end
function Service:GetAll()
 local status=self.d.configService:GetStatus()
 return {revision=status.revision,values=status.values}
end
function Service:Set(key,value,actor)
 if key=="monitoringEnabled" then
  if typeof(value)~="boolean" then return false,"Invalid monitoring policy." end
 else
  local range=RANGES[key]
  if not range or typeof(value)~="number" or value%1~=0 or value<range[1] or value>range[2] then return false,"Invalid security policy value." end
 end
 if self.d.authorize(actor,"SecurityPolicy")~=true then return false,"Security policy permission denied." end
 local ok,result=self.d.configService:Set(key,value,actor)
 if not ok then return false,result end
 if type(self.d.onChange)=="function" then pcall(self.d.onChange,key,value,result.revision,actor) end
 return true,self:GetAll()
end
function Service:GetStatus() local all=self:GetAll(); return {state="Ready",revision=all.revision,keys=5,scope="Shared Global Config DataStore"} end
function Service:Start() return true end
function Service:Stop() end
return Service

end)()

Bundle.Audit = (function()
--!strict
-- Local bounded audit queue; compact JSON batches are written to sharded expiring keys.
local Service={}; Service.__index=Service
local ALLOWED={AdminAction=true,CatalogChange=true,GlobalQueueChange=true,SecurityEvent=true,Maintenance=true,Moderation=true}
local MAX_ITEMS=200
local MAX_PAYLOAD=24500
local TTL=3600
local function severity(kind) return if kind=="SecurityEvent" or kind=="Moderation" then 3 else if kind=="AdminAction" then 2 else 1 end
function Service.new(d)
 assert(type(d)=="table" and d.memoryStoreService and type(d.isEnabled)=="function","Audit dependencies missing")
 local self=setmetatable({d=d,written=0,queued=0,droppedLow=0,lastError=nil,buffer={},lastFlushAt=0,
  readCache=nil,readCacheAt=0,flushRunning=false},Service)
 self.map=d.memoryStoreService:GetSortedMap(d.mapName or "ClubMusic_GlobalAudit_v1")
 return self
end
function Service:_enqueue(record)
 if #self.buffer>=MAX_ITEMS then
  local lowestIndex,lowestSeverity=nil,math.huge
  for i,item in ipairs(self.buffer) do
   local level=severity(item.kind)
   if level<lowestSeverity then lowestIndex,lowestSeverity=i,level end
  end
  if lowestIndex and lowestSeverity<3 then table.remove(self.buffer,lowestIndex); self.droppedLow+=1
  else self.droppedLow+=1; return false end
 end
 table.insert(self.buffer,record); self.queued+=1
 return true
end
function Service:Record(kind,actorUserId,target,action)
 if not self.d.isEnabled() or not ALLOWED[kind] then return false end
 local actor=if type(actorUserId)=="number" and actorUserId>0 then math.floor(actorUserId) else 0
 local record={kind=kind,actorUserId=actor,target=if type(target)=="string" then string.sub(target,1,32) else "",
  action=if type(action)=="string" then string.sub(action,1,32) else "",jobId=self.d.jobId,at=os.time(),
  severity=severity(kind)}
 return self:_enqueue(record)
end
function Service:_flush()
 if not self.d.isEnabled() or #self.buffer<1 then return false end
 local now=os.clock()
 if now-self.lastFlushAt<15 then return false end
 local allowed,reason=StorageGuard.Allow()
 if not allowed then self.lastError=reason; return false end
 local batch={}
 local count=math.min(100,#self.buffer)
 for i=1,count do table.insert(batch,self.buffer[i]) end
 local encodedOk,payload=pcall(self.d.jsonEncode,batch)
 if not encodedOk or type(payload)~="string" then self.lastError="Audit JSON serialization failed."; return false end
 while #payload>MAX_PAYLOAD and #batch>1 do
  table.remove(batch)
  encodedOk,payload=pcall(self.d.jsonEncode,batch)
  if not encodedOk or type(payload)~="string" then self.lastError="Audit JSON serialization failed."; return false end
 end
 if #payload>MAX_PAYLOAD then
  -- Trim optional detail fields before ever dropping a high-severity event.
  for _,item in ipairs(batch) do item.target=string.sub(item.target,1,16); item.action=string.sub(item.action,1,16) end
  encodedOk,payload=pcall(self.d.jsonEncode,batch)
  if not encodedOk or type(payload)~="string" or #payload>MAX_PAYLOAD then self.lastError="Audit batch exceeds payload ceiling."; return false end
 end
 local bucket=math.floor(os.time()/30)
 local shard=(bucket%3)+1
 local job=string.sub(tostring(self.d.jobId or "server"),1,32)
 local key="TT:A:"..tostring(shard)..":"..job..":"..tostring(bucket)
 if #key>64 then key=string.sub(key,1,64) end
 local writeOk,writeError=pcall(function() self.map:SetAsync(key,payload,TTL,os.time()) end)
 if not writeOk then
  self.lastError=tostring(writeError); StorageGuard.Failure(writeError); return false
 end
 for _=1,#batch do table.remove(self.buffer,1) end
 self.written+=#batch; self.lastFlushAt=now; self.lastError=nil; self.readCache=nil
 return true
end
function Service:GetRecent(limit)
 if not self.d.isEnabled() then return false,{} end
 local now=os.clock()
 if self.readCache and now-self.readCacheAt<10 then
  local cached={}; for i,item in ipairs(self.readCache) do if i>math.clamp(math.floor(tonumber(limit) or 20),1,50) then break end; table.insert(cached,table.clone(item)) end
  return true,cached
 end
 local allowed,reason=StorageGuard.Allow()
 if not allowed then self.lastError=reason; return false,{} end
 local ok,result=pcall(function() return self.map:GetRangeAsync(Enum.SortDirection.Descending,50) end)
 if not ok then self.lastError=tostring(result); StorageGuard.Failure(result); return false,{} end
 local out={}
 for _,entry in ipairs(result) do
  if type(entry.value)=="string" then
   local decodeOk,decoded=pcall(self.d.jsonDecode,entry.value)
   if decodeOk and typeof(decoded)=="table" then for _,item in ipairs(decoded) do if typeof(item)=="table" then table.insert(out,item) end end end
  elseif typeof(entry.value)=="table" then table.insert(out,table.clone(entry.value)) end
 end
 table.sort(out,function(a,b) return (tonumber(a.at) or 0)>(tonumber(b.at) or 0) end)
 self.readCache=out; self.readCacheAt=now
 local selected={}; for i=1,math.min(#out,math.clamp(math.floor(tonumber(limit) or 20),1,50)) do table.insert(selected,table.clone(out[i])) end
 return true,selected
end
function Service:GetStatus()
 return {state=if self.d.isEnabled() then "Healthy" else "Disabled",written=self.written,
  queued=#self.buffer,droppedLowSeverity=self.droppedLow,lastError=self.lastError,
  eventsPerBatch={min=50,max=100},payloadTargetBytes=MAX_PAYLOAD,flushSeconds={min=15,max=30},
  maxFlushesPerMinute=4,ttlSeconds=TTL,shards=3,storageGuard=StorageGuard.GetStatus()}
end
function Service:Start()
 if self.flushRunning then return true end
 self.flushRunning=true
 task.spawn(function()
  while self.flushRunning do
   task.wait(22.5)
   if #self.buffer>=50 then self:_flush() end
  end
 end)
 return true
end
function Service:Stop()
 self.flushRunning=false
 -- Do not attempt unbounded shutdown writes; remaining records expire with this server.
end
return Service
end)()

Bundle.IncidentResponse = (function()
--!strict
-- Shared, expiring incident records. Response is manual and never auto-bans or shuts down controllers.
local Service={}; Service.__index=Service
local ALLOWED={SecurityAlert=true,ServiceDegraded=true,AbuseReport=true,ManualReview=true}
function Service.new(d)
 assert(type(d)=="table" and d.isEnabled and d.memoryStoreService and type(d.authorize)=="function","Incident response dependencies missing")
 return setmetatable({d=d,map=d.memoryStoreService:GetSortedMap(d.mapName or "ClubMusic_GlobalIncidents_v1"),opened=0,resolved=0,lastError=nil},Service)
end
function Service:Open(kind,summary,actorUserId)
 if not self.d.isEnabled() or not ALLOWED[kind] or type(summary)~="string" or #summary<1 or #summary>120 then return false,"Invalid incident." end
 if self.d.authorize(actorUserId,"IncidentResponse")~=true then return false,"Incident response permission denied." end
 local id=self.d.guid()
 local item={id=id,kind=kind,summary=string.sub(summary,1,120),openedAt=os.time(),actorUserId=actorUserId,state="Open"}
 local ok,err=pcall(function() self.map:SetAsync(id,item,43200,item.openedAt) end)
 if not ok then self.lastError=tostring(err); return false,"Incident storage unavailable." end
 self.opened+=1
 if type(self.d.onChange)=="function" then pcall(self.d.onChange,"opened",item) end
 return true,id
end
function Service:Resolve(id,actorUserId)
 if not self.d.isEnabled() or type(id)~="string" or #id>64 then return false,"Invalid incident ID." end
 if self.d.authorize(actorUserId,"IncidentResponse")~=true then return false,"Incident response permission denied." end
 local ok,result=pcall(function()
  local resolved=self.map:UpdateAsync(id,function(old)
   if typeof(old)~="table" or old.state~="Open" then return old end
   local item=table.clone(old); item.state="Resolved"; item.resolvedAt=os.time(); item.resolvedBy=actorUserId
   return item
  end,43200,os.time())
  if typeof(resolved)~="table" or resolved.state~="Resolved" or resolved.resolvedBy~=actorUserId then return nil end
  self.map:RemoveAsync(id)
  return resolved
 end)
 if not ok then self.lastError=tostring(result); return false,"Incident storage unavailable." end
 if typeof(result)~="table" then return false,"Incident not found, already resolved, or resolution was not applied." end
 self.resolved+=1
 if type(self.d.onChange)=="function" then pcall(self.d.onChange,"resolved",result) end
 return true
end
function Service:GetRecent(limit)
 if not self.d.isEnabled() then return false,{} end
 local ok,result=pcall(function() return self.map:GetRangeAsync(Enum.SortDirection.Descending,math.clamp(math.floor(tonumber(limit) or 20),1,50)) end)
 if not ok then self.lastError=tostring(result); return false,{} end
 local out={}; for _,entry in ipairs(result) do if typeof(entry.value)=="table" then table.insert(out,table.clone(entry.value)) end end
 return true,out
end
function Service:GetStatus()
 local ok,items=self:GetRecent(100); local active=0
 if ok then for _,item in ipairs(items) do if item.state=="Open" then active+=1 end end end
 return {state=if self.d.isEnabled() then (if ok then "Healthy" else "Degraded") else "Disabled",opened=self.opened,resolved=self.resolved,active=active,automaticEnforcement=false,lastError=self.lastError}
end
function Service:Start() return true end
function Service:Stop() end
return Service

end)()

return Bundle
