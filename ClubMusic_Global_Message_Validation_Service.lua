--!strict
-- Shared envelope validation for cross-server messages; topic handlers still validate payload schemas.
local Service={}; Service.__index=Service
local KINDS={Announcements={Announcement=true},Moderation={Moderation=true},DJ={DJ=true},XPBoost={XPBoost=true},Catalog={Catalog=true},Queue={QueueChanged=true,ServerHeartbeat=true}}
function Service.new(d)
 assert(type(d)=="table" and type(d.getJobId)=="function","Message validation dependencies missing")
 return setmetatable({d=d,accepted=0,rejected=0},Service)
end
function Service:Validate(topic,data)
 local function reject(reason) self.rejected+=1; return false,reason end
 if type(topic)~="string" or not KINDS[topic] or typeof(data)~="table" then return reject("Unknown topic or non-table payload.") end
 if data.version~=1 or typeof(data.senderJob)~="string" or #data.senderJob<1 or #data.senderJob>64 or data.senderJob==self.d.getJobId() then return reject("Invalid message identity.") end
 if typeof(data.id)~="string" or #data.id<1 or #data.id>64 then return reject("Invalid message ID.") end
 if typeof(data.at)~="number" or data.at~=data.at or math.abs(os.time()-data.at)>120 then return reject("Invalid or expired timestamp.") end
 if not KINDS[topic][data.kind] then return reject("Message kind is not allowed for topic.") end
 local ok,encoded=pcall(function() return self.d.jsonEncode(data) end)
 if not ok or type(encoded)~="string" or #encoded>(self.d.maxBytes or 4096) then return reject("Message exceeds size limit or cannot be encoded.") end
 self.accepted+=1; return true
end
function Service:GetStatus() return {state="Ready",accepted=self.accepted,rejected=self.rejected} end
function Service:Start() return true end
function Service:Stop() end
return Service
