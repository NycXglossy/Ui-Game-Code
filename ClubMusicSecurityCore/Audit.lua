--!strict
local StorageGuard = require(script.Parent:WaitForChild("StorageGuard"))

-- Local bounded audit queue; compact JSON batches are written to sharded expiring keys.
local Service={}; Service.__index=Service
local ALLOWED={AdminAction=true,CatalogChange=true,SecurityEvent=true,Maintenance=true,Moderation=true}
local MAX_ITEMS=200
local MAX_PAYLOAD=24000
local TTL=1800
local function severity(kind) return if kind=="SecurityEvent" or kind=="Moderation" then 3 else if kind=="AdminAction" then 2 else 1 end
function Service.new(d)
 assert(type(d)=="table" and d.memoryStoreService and type(d.isEnabled)=="function","Audit dependencies missing")
 local self=setmetatable({d=d,written=0,queued=0,droppedLow=0,lastError=nil,buffer={},bufferHead=1,bufferCount=0,lastFlushAt=0,batchSequence=0,
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
 local allowed,reason=StorageGuard.Allow("low")
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
 self.batchSequence=(self.batchSequence%999)+1
 local job=string.sub(tostring(self.d.jobId or "server"),1,32)
 local key="TT:A:"..tostring(shard)..":"..job..":"..tostring(bucket)..":"..tostring(self.batchSequence)
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
 local allowed,reason=StorageGuard.Allow("low")
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
   if self.bufferCount>0 then self:_flush() end
  end
 end)
 return true
end
function Service:Stop()
 self.flushRunning=false
 -- Do not attempt unbounded shutdown writes; remaining records expire with this server.
end
return Service
