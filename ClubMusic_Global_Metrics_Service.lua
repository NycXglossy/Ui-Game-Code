--!strict
-- Bounded local metrics with optional expiring cross-server aggregates.
local Service={}; Service.__index=Service
function Service.new(d)
 assert(type(d)=="table" and type(d.isEnabled)=="function" and d.memoryStoreService,"Metrics dependencies missing")
 local self=setmetatable({d=d,counters={},latency={},lastFlush=0,lastError=nil},Service)
 self.map=d.memoryStoreService:GetHashMap(d.mapName or "ClubMusic_GlobalMetrics_v1"); return self
end
function Service:Record(name,value)
 if not self.d.isEnabled() or type(name)~="string" or #name>48 then return false end
 value=if type(value)=="number" and value==value and value<math.huge and value>=0 then value else 1
 self.counters[name]=math.min(1000000000,(self.counters[name] or 0)+value); return true
end
function Service:ObserveLatency(name,seconds)
 if not self.d.isEnabled() or type(name)~="string" or type(seconds)~="number" or seconds<0 or seconds>120 then return false end
 local s=self.latency[name] or {count=0,total=0,max=0}; s.count+=1; s.total+=seconds; s.max=math.max(s.max,seconds); self.latency[name]=s; return true
end
function Service:Flush()
 if not self.d.isEnabled() then return false end
 local snapshot={counters=table.clone(self.counters),latency=table.clone(self.latency),updatedAt=os.time()}
 local ok,err=pcall(function() self.map:UpdateAsync(self.d.jobId,function(old)
  local nextValue=if typeof(old)=="table" then old else {counters={},latency={}}
  nextValue.counters=if typeof(nextValue.counters)=="table" then nextValue.counters else {}
  nextValue.latency=if typeof(nextValue.latency)=="table" then nextValue.latency else {}
  for k,v in pairs(snapshot.counters) do nextValue.counters[k]=math.min(1000000000,(nextValue.counters[k] or 0)+v) end
  for k,v in pairs(snapshot.latency) do local a=nextValue.latency[k] or {count=0,total=0,max=0}; a.count+=v.count; a.total+=v.total; a.max=math.max(a.max,v.max); nextValue.latency[k]=a end
  nextValue.updatedAt=os.time(); return nextValue
 end,180) end)
 if not ok then self.lastError=tostring(err); return false end
 table.clear(self.counters); table.clear(self.latency); self.lastFlush=os.time(); return true
end
function Service:GetStatus() return {state=if not self.d.isEnabled() then "Disabled" else if self.lastError then "Degraded" else "Healthy",counters=table.clone(self.counters),lastFlush=self.lastFlush,lastError=self.lastError} end
function Service:Start() if self.running then return false end; self.running=true; task.spawn(function() while self.running do self:Flush(); task.wait(60) end end); return true end
function Service:Stop() self.running=false; self:Flush() end
return Service
