--!strict
-- Validated local security policy defaults. Mutations require the authorization adapter.
local Service={}; Service.__index=Service
local DEFAULTS={messageMaxBytes=4096,messageMaxAgeSeconds=120,suspiciousSignalThreshold=8,idempotencyTtlSeconds=120,monitoringEnabled=true}
local function validate(key,value)
 local defaults=DEFAULTS
 if defaults[key]==nil or typeof(value)~=typeof(defaults[key]) then return false end
 if key=="messageMaxBytes" then return value>=512 and value<=4096 and value%1==0 end
 if key=="messageMaxAgeSeconds" then return value>=30 and value<=300 and value%1==0 end
 if key=="suspiciousSignalThreshold" then return value>=3 and value<=100 and value%1==0 end
 if key=="idempotencyTtlSeconds" then return value>=30 and value<=600 and value%1==0 end
 return true
end
function Service.new(d) assert(type(d)=="table","Security policy dependencies missing"); return setmetatable({d=d,values=table.clone(DEFAULTS),revision=1},Service) end
function Service:Get(key) return self.values[key] end
function Service:GetAll() return {revision=self.revision,values=table.clone(self.values)} end
function Service:Set(key,value,actor)
 if not validate(key,value) then return false,"Invalid security policy value." end
 if type(self.d.authorize)~="function" or self.d.authorize(actor,"SecurityPolicy")~=true then return false,"Security policy permission denied." end
 self.values[key]=value; self.revision+=1
 if type(self.d.onChange)=="function" then pcall(self.d.onChange,key,value,self.revision,actor) end
 return true,self:GetAll()
end
function Service:GetStatus() return {state="Ready",revision=self.revision,keys=5,scope="Per-server defaults; no persistent policy store configured"} end
function Service:Start() return true end
function Service:Stop() end
return Service
