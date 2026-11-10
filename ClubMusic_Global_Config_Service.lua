--!strict
-- Validated, revisioned shared configuration with safe local defaults.
local Service={}; Service.__index=Service
local DEFAULTS={maintenanceEnabled=false,maintenanceMessage="",allowPlayerRequests=true,metricsEnabled=true,auditEnabled=true,messageMaxBytes=4096,messageMaxAgeSeconds=120,suspiciousSignalThreshold=8,idempotencyTtlSeconds=120,monitoringEnabled=true}
local function validate(raw)
 local out={}
 for k,v in pairs(DEFAULTS) do
  local candidate=if typeof(raw)=="table" then raw[k] else nil
  if typeof(candidate)==typeof(v) then
   if k=="maintenanceMessage" then out[k]=string.sub(candidate,1,240) else out[k]=candidate end
  else out[k]=v end
 end
 return out
end
function Service.new(d)
 assert(type(d)=="table" and d.dataStore and type(d.isEnabled)=="function" and type(d.allowStoreOperation)=="function","Config dependencies missing")
 local self=setmetatable({d=d,state="Starting",revision=0,values=table.clone(DEFAULTS),lastError=nil},Service)
 self.store=d.dataStore; return self
end
function Service:Refresh()
 if not self.d.isEnabled() then self.state="Disabled"; return false end
 if not self.d.allowStoreOperation() then self.state="Degraded"; self.lastError="Shared DataStore budget unavailable."; return false end
 local ok,value=pcall(function() return self.store:GetAsync("config") end)
 if not ok then self.state="Degraded"; self.lastError=tostring(value); return false end
 if typeof(value)=="table" then self.values=validate(value.values); self.revision=if type(value.revision)=="number" then math.max(0,math.floor(value.revision)) else 0 end
 self.state="Healthy"; self.lastError=nil; return true
end
function Service:Set(key,value,actor)
 if not self.d.isEnabled() or DEFAULTS[key]==nil or typeof(value)~=typeof(DEFAULTS[key]) then return false,"Invalid or disabled config update." end
 if key=="maintenanceMessage" and #value>240 then return false,"Message too long." end
 if not self.d.allowStoreOperation() then return false,"Shared configuration budget unavailable." end
 local ok,result=pcall(function()
  return self.store:UpdateAsync("config",function(old)
   local current=if typeof(old)=="table" then validate(old.values) else table.clone(DEFAULTS)
   current[key]=value
   return {values=current,revision=(if typeof(old)=="table" and type(old.revision)=="number" then math.floor(old.revision) else 0)+1,updatedAt=os.time(),updatedBy=actor}
  end)
 end)
 if not ok then self.lastError=tostring(result); return false,"Shared configuration unavailable." end
 self.values=validate(result.values); self.revision=result.revision; self.state="Healthy"; return true,self:GetStatus()
end
function Service:Get(key) return self.values[key] end
function Service:GetStatus() return {state=if not self.d.isEnabled() then "Disabled" else self.state,revision=self.revision,values=table.clone(self.values),lastError=self.lastError} end
function Service:Start() if self.running then return false end; self.running=true; task.spawn(function() while self.running do self:Refresh(); task.wait(30) end end); return true end
function Service:Stop() self.running=false end
return Service
