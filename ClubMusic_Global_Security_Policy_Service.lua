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
