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
-- Local signal aggregation plus compact, bounded cross-server security-event batches.
local Service={}; Service.__index=Service
local CAPACITY=200
local MAX_PAYLOAD=16000
local function severity(signal)
 local s=string.lower(tostring(signal))
 if string.find(s,"exploit",1,true) or string.find(s,"unauthorized",1,true)
  or string.find(s,"admin",1,true) or string.find(s,"ban",1,true) then return 3 end
 return 1
end
function Service.new(d)
 assert(type(d)=="table" and type(d.isEnabled)=="function","Security monitor dependencies missing")
 local self=setmetatable({d=d,signals={},total=0,alerts=0,lastAlertAt=0,events={},eventHead=1,eventCount=0,written=0,
  droppedLow=0,lastError=nil,flushRunning=false,lastFlushAt=0},Service)
 if d.memoryStoreService then self.map=d.memoryStoreService:GetSortedMap(d.mapName or "ClubMusic_GlobalSecurityBatches_v1") end
 return self
end
function Service:_queue(signal,subject,count)
 local item={signal=string.sub(signal,1,48),subject=string.sub(tostring(subject or "server"),1,48),
  count=count or 1,at=os.time(),severity=severity(signal)}
 if self.eventCount>=CAPACITY then
  local lowestOffset,lowest=nil,math.huge
  for offset=1,self.eventCount do
   local index=((self.eventHead+offset-2)%CAPACITY)+1
   local level=self.events[index].severity
   if level<lowest then lowestOffset,lowest=offset,level end
  end
  if lowestOffset and lowest<3 then
   local rebuilt={}
   for offset=1,self.eventCount do
    if offset~=lowestOffset then
     local index=((self.eventHead+offset-2)%CAPACITY)+1
     table.insert(rebuilt,self.events[index])
    end
   end
   table.clear(self.events); self.eventHead=1; self.eventCount=0
   for _,event in ipairs(rebuilt) do self.eventCount+=1; self.events[self.eventCount]=event end
   self.droppedLow+=1
  else
   warn("[ClubMusic][SecurityBatch] Local queue full of high-severity events; newest event could not be retained.")
   return false
  end
 end
 local tail=((self.eventHead+self.eventCount-1)%CAPACITY)+1
 self.events[tail]=item; self.eventCount+=1
 return true
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
 self:_queue(signal,subject,entry.count)
 local configured=if type(self.d.getThreshold)=="function" then self.d.getThreshold() else self.d.threshold
 local threshold=if type(configured)=="number" then math.max(1,math.floor(configured)) else 8
 if entry.count==threshold then
  self.alerts+=1; self.lastAlertAt=os.time()
  if type(self.d.onAlert)=="function" then pcall(self.d.onAlert,signal,entry.count) end
 end
 return true,entry.count
end
function Service:_flush()
 if not self.map or not self.d.isEnabled() or self.eventCount<25 then return false end
 if os.clock()-self.lastFlushAt<5 then return false end
 local allowed,reason=StorageGuard.Allow()
 if not allowed then self.lastError=reason; return false end
 local batch={}
 for offset=1,math.min(50,self.eventCount) do
  local index=((self.eventHead+offset-2)%CAPACITY)+1
  local event=self.events[index]
  table.insert(batch,{s=event.signal,u=event.subject,n=event.count,t=event.at,p=event.severity})
 end
 local ok,payload=pcall(self.d.jsonEncode,batch)
 if not ok or type(payload)~="string" then self.lastError="Security batch JSON serialization failed."; return false end
 while #payload>MAX_PAYLOAD and #batch>25 do
  table.remove(batch)
  ok,payload=pcall(self.d.jsonEncode,batch)
  if not ok or type(payload)~="string" then self.lastError="Security batch JSON serialization failed."; return false end
 end
 if #payload>MAX_PAYLOAD then
  for _,event in ipairs(batch) do event.s=string.sub(event.s,1,24); event.u=string.sub(event.u,1,24) end
  ok,payload=pcall(self.d.jsonEncode,batch)
  if not ok or type(payload)~="string" or #payload>MAX_PAYLOAD then self.lastError="Security batch exceeds 16 KB ceiling."; return false end
 end
 local bucket=math.floor(os.time()/10)
 local job=string.sub(tostring(self.d.jobId or "server"),1,36)
 local key="TT:SEC:"..job..":"..tostring(bucket)
 if #key>64 then key=string.sub(key,1,64) end
 local writeOk,writeError=pcall(function() self.map:SetAsync(key,payload,600,os.time()) end)
 if not writeOk then self.lastError=tostring(writeError); StorageGuard.Failure(writeError); return false end
 for _=1,#batch do self.events[self.eventHead]=nil; self.eventHead=(self.eventHead%CAPACITY)+1; self.eventCount-=1 end
 self.written+=#batch; self.lastFlushAt=os.clock(); self.lastError=nil
 return true
end
function Service:GetStatus()
 return {state=if self.d.isEnabled() then "Observing" else "Disabled",totalSignals=self.total,
  alerts=self.alerts,trackedKeys=(function() local n=0; for _ in pairs(self.signals) do n+=1 end; return n end)(),
  queued=self.eventCount,written=self.written,droppedLowSeverity=self.droppedLow,lastError=self.lastError,
  eventsPerFlush={min=25,max=50},payloadMaxBytes=MAX_PAYLOAD,flushSeconds={min=5,max=10},
  maxFlushesPerMinute=12,ttlSeconds={min=300,max=900},keySharding="ServerId+TimeBucket",
  automaticEnforcement=false,storageGuard=StorageGuard.GetStatus()}
end
function Service:Start()
 if self.flushRunning then return true end
 self.flushRunning=true
 task.spawn(function()
  while self.flushRunning do
   task.wait(7.5)
   self:_flush()
  end
 end)
 return true
end
function Service:Stop() self.flushRunning=false end
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
 local self=setmetatable({d=d,written=0,queued=0,droppedLow=0,lastError=nil,buffer={},bufferHead=1,bufferCount=0,lastFlushAt=0,
  readCache={},readCacheAt={},flushRunning=false},Service)
 self.map=d.memoryStoreService:GetSortedMap(d.mapName or "ClubMusic_GlobalAudit_v1")
 return self
end
function Service:_enqueue(record)
 if self.bufferCount>=MAX_ITEMS then
  local lowestOffset,lowestSeverity=nil,math.huge
  for offset=1,self.bufferCount do
   local index=((self.bufferHead+offset-2)%MAX_ITEMS)+1
   local level=severity(self.buffer[index].kind)
   if level<lowestSeverity then lowestOffset,lowestSeverity=offset,level end
  end
  if lowestOffset and lowestSeverity<3 then
   local rebuilt={}
   for offset=1,self.bufferCount do
    if offset~=lowestOffset then
     local index=((self.bufferHead+offset-2)%MAX_ITEMS)+1
     table.insert(rebuilt,self.buffer[index])
    end
   end
   table.clear(self.buffer); self.bufferHead=1; self.bufferCount=0
   for _,item in ipairs(rebuilt) do self.bufferCount+=1; self.buffer[self.bufferCount]=item end
   self.droppedLow+=1
  else self.droppedLow+=1; return false end
 end
 local tail=((self.bufferHead+self.bufferCount-1)%MAX_ITEMS)+1
 self.buffer[tail]=record; self.bufferCount+=1; self.queued+=1
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
 if not self.d.isEnabled() or self.bufferCount<1 then return false end
 local now=os.clock()
 if now-self.lastFlushAt<15 then return false end
 local allowed,reason=StorageGuard.Allow()
 if not allowed then self.lastError=reason; return false end
 local batch={}
 local count=math.min(100,self.bufferCount)
 for offset=1,count do local index=((self.bufferHead+offset-2)%MAX_ITEMS)+1; table.insert(batch,self.buffer[index]) end
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
 for _=1,#batch do self.buffer[self.bufferHead]=nil; self.bufferHead=(self.bufferHead%MAX_ITEMS)+1; self.bufferCount-=1 end
 self.written+=#batch; self.lastFlushAt=now; self.lastError=nil; self.readCache={}; self.readCacheAt={}
 return true
end
function Service:GetRecent(limit,moderatorUserId)
 if not self.d.isEnabled() then return false,{} end
 local cacheKey=tostring(if type(moderatorUserId)=="number" and moderatorUserId>0 then math.floor(moderatorUserId) else "server")
 local now=os.clock()
 if self.readCache[cacheKey] and now-(self.readCacheAt[cacheKey] or 0)<10 then
  local cached={}; for i,item in ipairs(self.readCache[cacheKey]) do if i>math.clamp(math.floor(tonumber(limit) or 20),1,50) then break end; table.insert(cached,table.clone(item)) end
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
 self.readCache[cacheKey]=out; self.readCacheAt[cacheKey]=now
 local selected={}; for i=1,math.min(#out,math.clamp(math.floor(tonumber(limit) or 20),1,50)) do table.insert(selected,table.clone(out[i])) end
 return true,selected
end
function Service:GetStatus()
 return {state=if self.d.isEnabled() then "Healthy" else "Disabled",written=self.written,
  queued=self.bufferCount,droppedLowSeverity=self.droppedLow,lastError=self.lastError,
  eventsPerBatch={min=50,max=100},payloadTargetBytes=MAX_PAYLOAD,flushSeconds={min=15,max=30},
  maxFlushesPerMinute=4,ttlSeconds=TTL,shards=3,storageGuard=StorageGuard.GetStatus()}
end
function Service:Start()
 if self.flushRunning then return true end
 self.flushRunning=true
 task.spawn(function()
  while self.flushRunning do
   task.wait(22.5)
   if self.bufferCount>=50 then self:_flush() end
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
-- Per-user temporary incident snapshots. Writes are coalesced and locally rate-limited.
local Service={}; Service.__index=Service
local ALLOWED={SecurityAlert=true,ServiceDegraded=true,AbuseReport=true,ManualReview=true}
local function validUserId(value) return type(value)=="number" and value>0 and value%1==0 and value<math.huge end
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
 local allowed,reason=StorageGuard.Allow()
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
   item=nextItem
   return nextItem
  end,math.clamp(math.floor(tonumber(self.d.getTtlSeconds and self.d.getTtlSeconds()) or 3600),3600,86400),os.time())
 end)
 if not ok then self.lastError=tostring(result); StorageGuard.Failure(result); self.pendingFlags[userId]=(self.pendingFlags[userId] or 0)+1; return false,"Incident storage unavailable." end
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
 local allowed,reason=StorageGuard.Allow()
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
 local allowed,reason=StorageGuard.Allow()
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
end)()

return Bundle
