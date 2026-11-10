--!strict
-- Read-only cross-service consistency observer. Never overwrites queue/catalog state.
local Service={}; Service.__index=Service
function Service.new(d)
 assert(type(d)=="table" and type(d.isEnabled)=="function" and type(d.getSnapshot)=="function","Reconciliation dependencies missing")
 return setmetatable({d=d,running=false,state="Starting",lastRun=0,detail="Not checked"},Service)
end
function Service:Reconcile()
 if not self.d.isEnabled() then self.state="Disabled"; self.detail="Cross-server service disabled."; return false end
 local ok,snapshot,err=pcall(self.d.getSnapshot)
 if not ok or snapshot~=true then self.state="Degraded"; self.detail=tostring(err or snapshot); return false end
 self.state="Healthy"; self.detail="Authoritative global queue snapshot is readable."; self.lastRun=os.time(); return true
end
function Service:GetStatus() return {state=self.state,detail=self.detail,lastRun=self.lastRun,mode="ReadOnly"} end
function Service:Start() if self.running then return false end; self.running=true; task.spawn(function() while self.running do self:Reconcile(); task.wait(90) end end); return true end
function Service:Stop() self.running=false end
return Service
