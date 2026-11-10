--!strict
-- Bounded, expiring operational event log. Does not record chat or raw player data.
local Service={}; Service.__index=Service
function Service.new(d)
 assert(type(d)=="table" and d.memoryStoreService and type(d.isEnabled)=="function","EventLog dependencies missing")
 local self=setmetatable({d=d,count=0,lastError=nil},Service)
 self.map=d.memoryStoreService:GetSortedMap(d.mapName or "ClubMusic_EventLog_v1"); return self
end
function Service:Record(kind,detail,severity)
 if not self.d.isEnabled() then return false end
 if type(kind)~="string" or #kind<1 or #kind>48 then return false end
 local safe=if type(detail)=="string" then string.sub(detail,1,180) else tostring(detail or "")
 local id=tostring(os.time())..":"..self.d.jobId..":"..tostring(self.d.guid())
 local value={kind=kind,detail=safe,severity=severity or "Info",jobId=self.d.jobId,at=os.time()}
 local ok,err=pcall(function() self.map:SetAsync(id,value,86400,os.time()) end)
 if ok then self.count+=1 else self.lastError=tostring(err) end
 return ok
end
function Service:GetRecent(limit)
 if not self.d.isEnabled() then return false,{} end
 local ok,result=pcall(function() return self.map:GetRangeAsync(Enum.SortDirection.Descending,math.clamp(tonumber(limit) or 25,1,100)) end)
 if not ok then self.lastError=tostring(result); return false,{} end
 local out={}; for _,v in ipairs(result) do if typeof(v.value)=="table" then table.insert(out,table.clone(v.value)) end end
 return true,out
end
function Service:GetStatus() return {state=if self.d.isEnabled() then "Healthy" else "Disabled",written=self.count,lastError=self.lastError} end
function Service:Start() return true end
function Service:Stop() end
return Service
