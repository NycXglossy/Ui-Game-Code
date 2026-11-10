--!strict
-- Shared, expiring incident records. Response is manual and never auto-bans or shuts down controllers.
local Service={}; Service.__index=Service
local ALLOWED={SecurityAlert=true,ServiceDegraded=true,AbuseReport=true,ManualReview=true}
function Service.new(d)
 assert(type(d)=="table" and d.isEnabled and d.memoryStoreService and type(d.authorize)=="function","Incident response dependencies missing")
 return setmetatable({d=d,map=d.memoryStoreService:GetSortedMap(d.mapName or "ClubMusic_GlobalIncidents_v1"),opened=0,resolved=0,lastError=nil},Service)
end
function Service:Open(kind,summary,actorUserId)
 if not self.d.isEnabled() or not ALLOWED[kind] or type(summary)~="string" or #summary<1 or #summary>200 then return false,"Invalid incident." end
 if self.d.authorize(actorUserId,"IncidentResponse")~=true then return false,"Incident response permission denied." end
 local id=self.d.guid()
 local item={id=id,kind=kind,summary=summary,openedAt=os.time(),actorUserId=actorUserId,state="Open"}
 local ok,err=pcall(function() self.map:SetAsync(id,item,604800,item.openedAt) end)
 if not ok then self.lastError=tostring(err); return false,"Incident storage unavailable." end
 self.opened+=1
 if type(self.d.onChange)=="function" then pcall(self.d.onChange,"opened",item) end
 return true,id
end
function Service:Resolve(id,actorUserId)
 if not self.d.isEnabled() or type(id)~="string" or #id>64 then return false,"Invalid incident ID." end
 if self.d.authorize(actorUserId,"IncidentResponse")~=true then return false,"Incident response permission denied." end
 local ok,result=pcall(function()
  return self.map:UpdateAsync(id,function(old)
   if typeof(old)~="table" or old.state~="Open" then return old end
   local item=table.clone(old); item.state="Resolved"; item.resolvedAt=os.time(); item.resolvedBy=actorUserId; return item
  end,604800,os.time())
 end)
 if not ok then self.lastError=tostring(result); return false,"Incident storage unavailable." end
 if typeof(result)~="table" or result.state~="Resolved" or result.resolvedBy~=actorUserId then return false,"Incident not found, already resolved, or resolution was not applied." end
 self.resolved+=1
 if type(self.d.onChange)=="function" then pcall(self.d.onChange,"resolved",result) end
 return true
end
function Service:GetRecent(limit)
 if not self.d.isEnabled() then return false,{} end
 local ok,result=pcall(function() return self.map:GetRangeAsync(Enum.SortDirection.Descending,math.clamp(math.floor(tonumber(limit) or 25),1,100)) end)
 if not ok then self.lastError=tostring(result); return false,{} end
 local out={}; for _,entry in ipairs(result) do if typeof(entry.value)=="table" then table.insert(out,table.clone(entry.value)) end end
 return true,out
end
function Service:GetStatus()
 local ok,items=self:GetRecent(100); local active=0
 if ok then for _,item in ipairs(items) do if item.state=="Open" then active+=1 end end end
 return {state=if self.d.isEnabled() then (if ok then "Healthy" else "Degraded") else "Disabled",opened=self.opened,resolved=self.resolved,active=active,automaticEnforcement=false,lastError=self.lastError}
end
function Service:Start() return true end
function Service:Stop() end
return Service
