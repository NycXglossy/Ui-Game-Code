--!strict
-- Server-side authorization adapter. Denies by default until a trusted resolver is supplied.
local Service={}; Service.__index=Service
local ALLOWED={GlobalDJ=true,GlobalModeration=true,GlobalAnnouncement=true,GlobalConfig=true,SecurityPolicy=true,IncidentResponse=true}
function Service.new(d)
 assert(type(d)=="table","Authorization dependencies missing")
 return setmetatable({d=d,checks=0,denied=0},Service)
end
function Service:Check(actorUserId,permission)
 if type(actorUserId)~="number" or actorUserId<1 or actorUserId%1~=0 or not ALLOWED[permission] then self.denied+=1; return false,"Invalid actor or permission." end
 if type(self.d.resolvePermission)~="function" then self.denied+=1; return false,"No trusted permission resolver is configured." end
 local ok,allowed=pcall(self.d.resolvePermission,math.floor(actorUserId),permission)
 self.checks+=1
 if not ok or allowed~=true then self.denied+=1; return false,"Permission denied." end
 return true
end
function Service:GetStatus() return {state=if type(self.d.resolvePermission)=="function" then "Ready" else "Unconfigured",checks=self.checks,denied=self.denied,default="Deny"} end
function Service:Start() return true end
function Service:Stop() end
return Service
