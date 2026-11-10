--!strict
-- Append-only, expiring audit events; bounded and excludes arbitrary payloads.
local Service={}; Service.__index=Service
local ALLOWED={AdminAction=true,CatalogChange=true,GlobalQueueChange=true,SecurityEvent=true,Maintenance=true}
function Service.new(d)
 assert(type(d)=="table" and d.memoryStoreService and type(d.isEnabled)=="function","Audit dependencies missing")
 local self=setmetatable({d=d,written=0,lastError=nil},Service)
 self.map=d.memoryStoreService:GetSortedMap(d.mapName or "ClubMusic_GlobalAudit_v1"); return self
end
function Service:Record(kind,actorUserId,target,action)
 if not self.d.isEnabled() or not ALLOWED[kind] then return false end
 local actor=if type(actorUserId)=="number" and actorUserId>0 then math.floor(actorUserId) else 0
 local safeTarget=if type(target)=="string" then string.sub(target,1,64) else ""
 local safeAction=if type(action)=="string" then string.sub(action,1,64) else ""
 local id=tostring(os.time())..":"..self.d.jobId..":"..tostring(self.d.guid())
 local record={kind=kind,actorUserId=actor,target=safeTarget,action=safeAction,jobId=self.d.jobId,at=os.time()}
 local ok,err=pcall(function() self.map:SetAsync(id,record,604800,os.time()) end)
 if ok then self.written+=1 else self.lastError=tostring(err) end
 return ok
end
function Service:GetRecent(limit)
 if not self.d.isEnabled() then return false,{} end
 local ok,result=pcall(function() return self.map:GetRangeAsync(Enum.SortDirection.Descending,math.clamp(tonumber(limit) or 25,1,100)) end)
 if not ok then self.lastError=tostring(result); return false,{} end
 local out={}; for _,entry in ipairs(result) do if typeof(entry.value)=="table" then table.insert(out,table.clone(entry.value)) end end; return true,out
end
function Service:GetStatus() return {state=if self.d.isEnabled() then "Healthy" else "Disabled",written=self.written,lastError=self.lastError} end
function Service:Start() return true end
function Service:Stop() end
return Service
