--!strict
local StorageGuard = require(script.Parent:WaitForChild("StorageGuard"))

-- Local security telemetry with priority queues, scheduled/size flushes, and retry-safe batch IDs.
local Service={}; Service.__index=Service
local STANDARD_CAPACITY=200
local CRITICAL_CAPACITY=200
local MAX_BATCH_EVENTS=50
local MAX_PAYLOAD=16000
local FLUSH_INTERVAL=10
local BATCH_TTL=600
local SENT_ID_CAPACITY=32
local MAX_BACKOFF=60

local function severity(signal)
 local s=string.lower(tostring(signal))
 if string.find(s,"exploit",1,true) or string.find(s,"unauthorized",1,true)
  or string.find(s,"admin",1,true) or string.find(s,"ban",1,true)
  or string.find(s,"invalid_message",1,true) or string.find(s,"validator_unavailable",1,true) then return 3 end
 return 1
end
local function eventKey(event) return event.signal..":"..event.subject end

function Service.new(d)
 assert(type(d)=="table" and type(d.isEnabled)=="function","Security monitor dependencies missing")
 return setmetatable({
  d=d,signals={},total=0,alerts=0,lastAlertAt=0,
  standardEvents={},criticalEvents={},written=0,
  droppedLow=0,coalescedCritical=0,lastError=nil,
  flushRunning=false,flushInFlight=false,lastFlushAt=0,
  retryAt=0,retryDelay=1,pendingBatch=nil,
  sentBatchIds={},sentBatchSet={},sentBatchIndex=1,
 },Service)
end

function Service:_rememberSentBatch(batchId)
 if self.sentBatchSet[batchId] then return end
 local old=self.sentBatchIds[self.sentBatchIndex]
 if old then self.sentBatchSet[old]=nil end
 self.sentBatchIds[self.sentBatchIndex]=batchId
 self.sentBatchSet[batchId]=true
 self.sentBatchIndex=(self.sentBatchIndex%SENT_ID_CAPACITY)+1
end

function Service:_queue(signal,subject,count)
 local level=severity(signal)
 local item={
  signal=string.sub(signal,1,48),
  subject=string.sub(tostring(subject or "server"),1,48),
  count=count or 1,at=os.time(),severity=level,
  priority=if level>=3 then "Critical" else "Standard",
 }
 if item.priority=="Critical" then
  local key=eventKey(item)
  for _,existing in ipairs(self.criticalEvents) do
   if eventKey(existing)==key then
    existing.count=math.min(1000000,existing.count+item.count)
    existing.at=item.at
    self.coalescedCritical+=1
    return true
   end
  end
  if #self.criticalEvents<CRITICAL_CAPACITY-1 then
   table.insert(self.criticalEvents,item)
  else
   -- Preserve critical occurrence counts during a flood without allowing
   -- unique attacker-controlled signals to grow memory without bound.
   local overflow=self.criticalEvents[CRITICAL_CAPACITY]
   if overflow and overflow.signal=="critical_overflow" then
    overflow.count=math.min(1000000,overflow.count+item.count)
    overflow.at=item.at
   else
    self.criticalEvents[CRITICAL_CAPACITY]={
     signal="critical_overflow",subject="server",count=1,at=item.at,
     severity=3,priority="Critical",
    }
   end
   self.coalescedCritical+=1
  end
 else
  if #self.standardEvents>=STANDARD_CAPACITY then
   self.droppedLow+=1
   return false
  end
  table.insert(self.standardEvents,item)
 end
 if #self.criticalEvents+#self.standardEvents>=25 and not self.flushInFlight then
  task.spawn(function() self:_flush() end)
 end
 return true
end

function Service:Record(signal,subject)
 if not self.d.isEnabled() or type(signal)~="string" or #signal<1 or #signal>48 then return false end
 local key=signal..":"..string.sub(tostring(subject or "server"),1,64)
 local now=os.clock()
 local entry=self.signals[key]
 if not entry then
  local tracked=0
  for _ in pairs(self.signals) do tracked+=1 end
  if tracked>=512 then
   local oldestKey,oldestAt=nil,math.huge
   for k,v in pairs(self.signals) do if v.updated<oldestAt then oldestKey,oldestAt=k,v.updated end end
   if oldestKey then self.signals[oldestKey]=nil end
  end
  entry={count=0,windowStart=now,updated=now}
  self.signals[key]=entry
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

function Service:_removeSentEvents(events)
 for _,sent in ipairs(events) do
  local source=if sent.priority=="Critical" then self.criticalEvents else self.standardEvents
  for index,event in ipairs(source) do
   if event==sent then table.remove(source,index); break end
  end
 end
end

function Service:_makePendingBatch()
 local selected={}
 for _,event in ipairs(self.criticalEvents) do
  if #selected>=MAX_BATCH_EVENTS then break end
  table.insert(selected,event)
 end
 if #selected<MAX_BATCH_EVENTS then
  for _,event in ipairs(self.standardEvents) do
   if #selected>=MAX_BATCH_EVENTS then break end
   table.insert(selected,event)
  end
 end
 if #selected==0 then return nil end
 local payload={}
 for _,event in ipairs(selected) do
  table.insert(payload,{s=event.signal,u=event.subject,n=event.count,t=event.at,p=event.severity,priority=event.priority})
 end
 local ok,encoded=pcall(self.d.jsonEncode,payload)
 if not ok or type(encoded)~="string" then
  table.clear(payload)
  return nil,"Security batch JSON serialization failed: "..tostring(encoded)
 end
 while #encoded>MAX_PAYLOAD and #payload>1 do
  table.remove(payload); table.remove(selected)
  ok,encoded=pcall(self.d.jsonEncode,payload)
  if not ok or type(encoded)~="string" then
   table.clear(payload)
   return nil,"Security batch JSON serialization failed: "..tostring(encoded)
  end
 end
 if #encoded>MAX_PAYLOAD then
  table.clear(payload)
  return nil,"A single security event exceeds the 16 KB batch ceiling."
 end
 local guidOk,batchId=pcall(self.d.guid)
 if not guidOk or type(batchId)~="string" or #batchId<1 then
  table.clear(payload)
  return nil,"Security batch UUID generation failed."
 end
 return {id=batchId,events=selected,payload=payload,encoded=encoded}
end

function Service:_flush()
 if self.flushInFlight or not self.map or not self.d.isEnabled() then return false end
 if #self.criticalEvents+#self.standardEvents<1 then return false end
 local now=os.clock()
 if now<self.retryAt then return false end
 if self.lastFlushAt>0 and now-self.lastFlushAt<5 then return false end
 self.flushInFlight=true
 self.lastFlushAt=now
 local pending=self.pendingBatch
 if not pending then
  local buildError
  pending,buildError=self:_makePendingBatch()
  if not pending then
   self.lastError=buildError
   self.retryAt=now+self.retryDelay
   self.retryDelay=math.min(MAX_BACKOFF,self.retryDelay*2)
   self.flushInFlight=false
   return false
  end
  self.pendingBatch=pending
 end
 if self.sentBatchSet[pending.id] then
  self:_removeSentEvents(pending.events)
  table.clear(pending.payload)
  self.pendingBatch=nil
  self.flushInFlight=false
  return true
 end
 local hasCritical=false
 for _,event in ipairs(pending.events) do
  if event.priority=="Critical" then hasCritical=true; break end
 end
 local allowed,reason=StorageGuard.Allow(if hasCritical then "critical" else "low")
 if not allowed then
  self.lastError=reason
  self.retryAt=now+self.retryDelay
  self.retryDelay=math.min(MAX_BACKOFF,self.retryDelay*2)
  self.flushInFlight=false
  return false
 end
 local key="TT:SEC:"..pending.id
 local writeOk,writeError=pcall(function()
  self.map:SetAsync(key,pending.encoded,BATCH_TTL,os.time())
 end)
 if not writeOk then
  self.lastError=tostring(writeError)
  StorageGuard.Failure(writeError)
  self.retryAt=now+self.retryDelay
  self.retryDelay=math.min(MAX_BACKOFF,self.retryDelay*2)
  self.flushInFlight=false
  return false
 end
 self:_rememberSentBatch(pending.id)
 self:_removeSentEvents(pending.events)
 self.written+=#pending.events
 table.clear(pending.payload)
 self.pendingBatch=nil
 self.retryDelay=1
 self.retryAt=0
 self.lastError=nil
 self.flushInFlight=false
 return true
end

function Service:GetStatus()
 return {
  state=if self.d.isEnabled() then "Observing" else "Disabled",
  totalSignals=self.total,alerts=self.alerts,
  trackedKeys=(function() local n=0; for _ in pairs(self.signals) do n+=1 end; return n end)(),
  queuedCritical=#self.criticalEvents,queuedStandard=#self.standardEvents,
  queued=#self.criticalEvents+#self.standardEvents,written=self.written,
  droppedLowSeverity=self.droppedLow,coalescedCritical=self.coalescedCritical,
  lastError=self.lastError,retryInSeconds=math.max(0,self.retryAt-os.clock()),
  eventsPerFlush={min=1,max=MAX_BATCH_EVENTS},payloadMaxBytes=MAX_PAYLOAD,
  flushSeconds=FLUSH_INTERVAL,maxFlushesPerMinute=12,ttlSeconds=BATCH_TTL,
  batchIdempotency="UUID + 32-entry recent-send ring",
  automaticEnforcement=false,storageGuard=StorageGuard.GetStatus(),
 }
end

function Service:Start()
 if self.flushRunning then return true end
 self.flushRunning=true
 task.spawn(function()
  while self.flushRunning do
   task.wait(1)
   if os.clock()-self.lastFlushAt>=FLUSH_INTERVAL then self:_flush() end
  end
 end)
 return true
end
function Service:Stop() self.flushRunning=false end
return Service
