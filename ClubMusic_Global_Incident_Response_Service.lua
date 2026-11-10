--!strict
-- Incident coordination and audit hooks only; no automatic bans, kicks, or controller shutdown.
local Service={}; Service.__index=Service
local ALLOWED={SecurityAlert=true,ServiceDegraded=true,AbuseReport=true,ManualReview=true}
function Service.new(d)
 assert(type(d)=="table" and type(d.isEnabled)=="function","Incident response dependencies missing")
 return setmetatable({d=d,incidents={},opened=0,resolved=0},Service)
end
function Service:Open(kind,summary,actorUserId)
 if not self.d.isEnabled() or not ALLOWED[kind] or type(summary)~="string" or #summary<1 or #summary>200 then return false,"Invalid incident." end
 if type(self.d.authorize)~="function" or self.d.authorize(actorUserId,"IncidentResponse")~=true then return false,"Incident response permission denied." end
 local id=self.d.guid()
 self.incidents[id]={id=id,kind=kind,summary=summary,openedAt=os.time(),actorUserId=actorUserId,state="Open"}
 self.opened+=1
 if type(self.d.onChange)=="function" then pcall(self.d.onChange,"opened",self.incidents[id]) end
 return true,id
end
function Service:Resolve(id,actorUserId)
 local item=self.incidents[id]
 if not item or item.state~="Open" then return false,"Incident not found or already resolved." end
 if type(self.d.authorize)~="function" or self.d.authorize(actorUserId,"IncidentResponse")~=true then return false,"Incident response permission denied." end
 item.state="Resolved"; item.resolvedAt=os.time(); item.resolvedBy=actorUserId; self.resolved+=1
 if type(self.d.onChange)=="function" then pcall(self.d.onChange,"resolved",item) end
 return true
end
function Service:GetRecent(limit)
 local out={}; for _,v in pairs(self.incidents) do table.insert(out,table.clone(v)) end
 table.sort(out,function(a,b) return a.openedAt>b.openedAt end)
 while #out>math.clamp(math.floor(tonumber(limit) or 25),1,100) do table.remove(out) end
 return out
end
function Service:GetStatus() local open=0; for _,v in pairs(self.incidents) do if v.state=="Open" then open+=1 end end; return {state=if self.d.isEnabled() then "Ready" else "Disabled",opened=self.opened,resolved=self.resolved,active=open,automaticEnforcement=false} end
function Service:Start() return true end
function Service:Stop() end
return Service
