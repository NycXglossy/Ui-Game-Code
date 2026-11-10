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
