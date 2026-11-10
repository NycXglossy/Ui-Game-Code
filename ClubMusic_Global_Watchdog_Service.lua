--!strict
-- Observational watchdog only: reports stalled services; never restarts controllers.
local Service={}; Service.__index=Service
function Service.new(d)
 assert(type(d)=="table" and type(d.isEnabled)=="function" and type(d.getChecks)=="function","Watchdog dependencies missing")
 return setmetatable({d=d,running=false,state="Starting",lastCheck=0,failures=0,issues={}},Service)
end
function Service:Check()
 if not self.d.isEnabled() then self.state="Disabled"; self.issues={}; return end
 local ok,checks=pcall(self.d.getChecks)
 if not ok or typeof(checks)~="table" then self.state="Degraded"; self.failures+=1; self.issues={"Health probes unavailable"}; return end
 local issues={}
 for name,result in pairs(checks) do
  if result~=true and not (typeof(result)=="table" and result.healthy==true) then table.insert(issues,tostring(name).." is not healthy") end
 end
 self.issues=issues; self.lastCheck=os.time(); self.state=if #issues==0 then "Healthy" else "Degraded"
 if #issues>0 and self.d.reportError then pcall(self.d.reportError,"GlobalWatchdog","Probe",table.concat(issues,"; ")) end
end
function Service:GetStatus() return {state=self.state,lastCheck=self.lastCheck,failures=self.failures,issues=table.clone(self.issues)} end
function Service:Start() if self.running then return false end; self.running=true; task.spawn(function() while self.running do self:Check(); task.wait(30) end end); return true end
function Service:Stop() self.running=false end
return Service
