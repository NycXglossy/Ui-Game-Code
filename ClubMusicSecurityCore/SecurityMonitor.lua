--!strict
-- Local-only bounded security signal aggregation.
-- Threshold crossings are forwarded to the unified Audit service by onAlert.
-- No queue, background flusher, or separate MemoryStore map is created.
local ResourceGuard = require(script.Parent:WaitForChild("ResourceGuard"))
local Service={}; Service.__index=Service
local MAX_TRACKED_KEYS=512
local WINDOW_SECONDS=60

local function cleanPart(value,maxLength)
	local result=string.sub(tostring(value or "server"),1,maxLength)
	return (result:gsub("[%c]", "_"))
end

function Service.new(d)
	assert(type(d)=="table" and type(d.isEnabled)=="function","Security monitor dependencies missing")
	return setmetatable({
		d=d,signals={},total=0,alerts=0,droppedKeys=0,lastAlertAt=0,
		started=false,lastSignal=nil,
	},Service)
end

function Service:Record(signal,subject)
	if not self.d.isEnabled() or type(signal)~="string" or #signal<1 or #signal>48 then return false end
	local safeSignal=cleanPart(signal,48)
	local safeSubject=cleanPart(subject,48)
	local key=safeSignal..":"..safeSubject
	local now=os.clock()
	local entry=self.signals[key]
	if not entry then
		local tracked=0
		local oldestKey,oldestAt=nil,math.huge
		for existingKey,value in pairs(self.signals) do
			tracked+=1
			if value.updated<oldestAt then oldestAt=value.updated; oldestKey=existingKey end
		end
		if tracked>=MAX_TRACKED_KEYS then
			if oldestKey then self.signals[oldestKey]=nil end
			self.droppedKeys+=1
		end
		entry={count=0,windowStart=now,updated=now,lastAlertAt=0}
		self.signals[key]=entry
	end
	if now-entry.windowStart>WINDOW_SECONDS then
		entry.count=0
		entry.windowStart=now
	end
	entry.count+=1
	entry.updated=now
	self.total+=1
	self.lastSignal=safeSignal
	local configured=if type(self.d.getThreshold)=="function" then self.d.getThreshold() else self.d.threshold
	local threshold=if type(configured)=="number" then math.clamp(math.floor(configured),1,100) else 8
	if entry.count==threshold then
		self.alerts+=1
		self.lastAlertAt=os.time()
		entry.lastAlertAt=now
		if type(self.d.onAlert)=="function" then pcall(self.d.onAlert,safeSignal,entry.count,safeSubject) end
	end
	return true,entry.count
end

function Service:GetStatus()
	local tracked=0
	for _ in pairs(self.signals) do tracked+=1 end
	return {
		state=if self.d.isEnabled() then "Observing" else "Disabled",
		totalSignals=self.total,alerts=self.alerts,trackedKeys=tracked,
		maxTrackedKeys=MAX_TRACKED_KEYS,droppedKeys=self.droppedKeys,
		lastSignal=self.lastSignal,lastAlertAt=self.lastAlertAt,
		persistence="Unified Audit threshold events only",
		independentMemoryStoreMap=false,memoryStoreWrites=0,
		resourceGuard=ResourceGuard.GetStatus(),
	}
end

function Service:Start()
	self.started=true
	return true
end
function Service:Stop()
	self.started=false
	table.clear(self.signals)
end
return Service
