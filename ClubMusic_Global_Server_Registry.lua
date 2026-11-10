--!strict
-- Expiring cross-server registry. No player identifiers are stored.
local Service = {}; Service.__index = Service
function Service.new(d)
 assert(type(d)=="table" and type(d.isEnabled)=="function" and d.memoryStoreService, "Registry dependencies missing")
 local self=setmetatable({d=d,running=false,state="Starting",lastHeartbeat=0,lastError=nil},Service)
 self.map=d.memoryStoreService:GetSortedMap(d.mapName or "ClubMusic_ServerRegistry_v1")
 return self
end
function Service:Heartbeat()
 if not self.d.isEnabled() then self.state="Disabled"; return false end
 local value={jobId=self.d.jobId,placeId=game.PlaceId,players=game:GetService("Players").NumPlayers,
  maxPlayers=game:GetService("Players").MaxPlayers,updatedAt=os.time(),health=self.d.getHealth and self.d.getHealth() or "Unknown"}
 local ok,err=pcall(function() self.map:SetAsync(self.d.jobId,value,180,os.time()) end)
 if not ok then self.state="Degraded"; self.lastError=tostring(err); return false end
 self.state="Healthy"; self.lastHeartbeat=os.time(); self.lastError=nil; return true
end
function Service:GetServers(limit)
 if not self.d.isEnabled() then return false,{},"Disabled" end
 local ok,result=pcall(function() return self.map:GetRangeAsync(Enum.SortDirection.Descending,math.clamp(tonumber(limit) or 50,1,100)) end)
 if not ok then self.state="Degraded"; self.lastError=tostring(result); return false,{},self.lastError end
 local out={}
 for _,entry in ipairs(result) do if typeof(entry.value)=="table" then table.insert(out,table.clone(entry.value)) end end
 return true,out
end
function Service:GetStatus()
 return {state=if not self.d.isEnabled() then "Disabled" else self.state,lastHeartbeat=self.lastHeartbeat,
  lastError=self.lastError,ttlSeconds=180}
end
function Service:Start()
 if self.running then return false end; self.running=true
 task.spawn(function() while self.running do self:Heartbeat(); task.wait(60) end end); return true
end
function Service:Stop() self.running=false end
return Service
