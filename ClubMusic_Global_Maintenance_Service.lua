--!strict
-- Coordinates maintenance state through the validated shared config service.
local Service={}; Service.__index=Service
function Service.new(d)
 assert(type(d)=="table" and type(d.isEnabled)=="function" and d.configService,"Maintenance dependencies missing")
 return setmetatable({d=d},Service)
end
function Service:Set(enabled,message,actor)
 if typeof(enabled)~="boolean" then return false,"Invalid maintenance flag." end
 if message~=nil and (typeof(message)~="string" or #message>240) then return false,"Maintenance message must be 240 characters or fewer." end
 if message~=nil then
  local msgOk,msgErr=self.d.configService:Set("maintenanceMessage",message,actor)
  if not msgOk then return false,msgErr end
 end
 local ok,err=self.d.configService:Set("maintenanceEnabled",enabled,actor)
 if not ok then return false,err end
 if self.d.publish then pcall(self.d.publish,{kind="Maintenance",enabled=enabled,message=self.d.configService:Get("maintenanceMessage")}) end
 return true
end
function Service:GetStatus()
 local config=self.d.configService:GetStatus()
 return {state=if not self.d.isEnabled() then "Disabled" else "Healthy",enabled=config.values.maintenanceEnabled,message=config.values.maintenanceMessage,revision=config.revision}
end
function Service:Start() return true end
function Service:Stop() end
return Service
