--!strict
-- Observational watchdog only: reports stalled services; never restarts controllers.
local Service={}; Service.__index=Service
function Service.new(d)
 assert(type(d)=="table" and type(d.isEnabled)=="function" and type(d.getChecks)=="function","Watchdog dependencies missing")
 return setmetatable({d=d,running=false,state="Starting",lastCheck=0,failures=0,issues={}},Service)
end
function Service:Check()
 if not self.d.isEnabled() then self.state="Disabled"; self.issues={}; self.lastCheck=os.time(); return end
 local ok,checks=pcall(self.d.getChecks)
 if not ok or typeof(checks)~="table" then
  self.state="Degraded"; self.failures+=1; self.issues={"Health probes unavailable"}; self.lastCheck=os.time()
  if self.d.reportError then pcall(self.d.reportError,"GlobalWatchdog","Probe",table.concat(self.issues,"; ")) end
  return
 end
 local issues={}
 local pending={}
 for name,result in pairs(checks) do
  if result==true or (typeof(result)=="table" and result.healthy==true) then
   -- Explicitly healthy.
  elseif typeof(result)=="table" and result.pending==true then
   table.insert(pending,tostring(result.detail or (tostring(name).." is still starting")))
  else
   local detail=if typeof(result)=="table" then result.detail else nil
   table.insert(issues,tostring(name).." is not healthy"..(if detail then ": "..tostring(detail) else ""))
  end
 end
 self.issues=issues; self.lastCheck=os.time()
 if #issues>0 then
  self.state="Degraded"; self.failures+=1
  if self.d.reportError then pcall(self.d.reportError,"GlobalWatchdog","Probe",table.concat(issues,"; ")) end
 elseif #pending>0 then
  self.state="Starting"
 else
  self.state="Healthy"
 end
end
function Service:GetStatus() return {state=self.state,lastCheck=self.lastCheck,failures=self.failures,issues=table.clone(self.issues)} end
function Service:Start() if self.running then return false end; self.running=true; task.spawn(function() while self.running do self:Check(); task.wait(30) end end); return true end
function Service:Stop() self.running=false end
return Service
