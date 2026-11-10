--!strict
-- ClubMusic queue adapter.
-- The controller owns the queue table, ordering policy, request accounting and
-- global queue synchronization. This module mutates only the injected table.
-- A legacy config-backed mode is retained for older standalone consumers.

local MusicQueueManager = {}
MusicQueueManager.__index = MusicQueueManager

function MusicQueueManager.new(queueOrConfig: any, releaseSlot: ((any) -> ())?)
	local sharedQueue = typeof(queueOrConfig) == "table"
		and (releaseSlot ~= nil or queueOrConfig.MAX_QUEUE_SIZE == nil)
	local self = setmetatable({}, MusicQueueManager)
	self.sharedQueue = sharedQueue
	self.queue = if sharedQueue then queueOrConfig else {}
	self.config = if sharedQueue then nil else queueOrConfig
	self.releaseSlot = if sharedQueue then releaseSlot else nil
	self.playerQueueCount = {}
	self.destroyed = false
	return self
end

local function release(self, entry: any)
	if typeof(self.releaseSlot) == "function" then
		local ok, err = pcall(self.releaseSlot, entry)
		if not ok then warn("[ClubMusic Queue Adapter] Request-slot release failed: " .. tostring(err)) end
	end
end

function MusicQueueManager:Insert(index: number, entry: any)
	if self.destroyed or typeof(entry) ~= "table" or typeof(index) ~= "number" then return false end
	local target = math.clamp(math.floor(index), 1, #self.queue + 1)
	table.insert(self.queue, target, entry)
	return true
end

function MusicQueueManager:PopNext()
	if self.destroyed or #self.queue == 0 then return nil end
	local entry = table.remove(self.queue, 1)
	release(self, entry)
	return entry
end

function MusicQueueManager:RemoveAt(index: number, releaseRequestSlot: boolean?)
	if self.destroyed or typeof(index) ~= "number" or index % 1 ~= 0 then return nil end
	if index < 1 or index > #self.queue then return nil end
	local entry = table.remove(self.queue, index)
	if releaseRequestSlot == true then release(self, entry) end
	return entry
end

function MusicQueueManager:Clear(releaseRequestSlots: boolean?)
	if self.destroyed then return false end
	if releaseRequestSlots == true then
		for _, entry in ipairs(self.queue) do release(self, entry) end
	end
	table.clear(self.queue)
	return true
end

function MusicQueueManager:ClearAutomatic()
	if self.destroyed then return 0 end
	local removed = 0
	for index = #self.queue, 1, -1 do
		local entry = self.queue[index]
		-- Preserve player requests and any future explicitly protected entry type.
		if typeof(entry) == "table" and entry.source ~= "player" then
			table.remove(self.queue, index)
			removed += 1
		end
	end
	return removed
end

function MusicQueueManager:GetQueue()
	return self.queue
end

function MusicQueueManager:IsEmpty(): boolean
	return #self.queue == 0
end

function MusicQueueManager:GetSize(): number
	return #self.queue
end

-- Legacy config-backed API. Shared-controller mode intentionally rejects these
-- methods because the controller owns validation and request-slot policy.
function MusicQueueManager:AddToQueue(musicData: any, uploaderName: string, userId: number)
	if self.sharedQueue or not self.config then return false, "Queue policy is owned by UI_Server_Controller." end
	if #self.queue >= (self.config.MAX_QUEUE_SIZE or 0) then return false, "Queue is full." end
	local count = self.playerQueueCount[userId] or 0
	if count >= (self.config.MAX_QUEUE_PER_USER or 0) then return false, "Your queue limit has been reached." end
	table.insert(self.queue, { musicData = musicData, uploader = uploaderName, userId = userId, addedTime = os.clock() })
	self.playerQueueCount[userId] = count + 1
	return true, nil
end

function MusicQueueManager:GetNext()
	if self.sharedQueue then return self:PopNext() end
	local entry = table.remove(self.queue, 1)
	if entry and entry.userId then self.playerQueueCount[entry.userId] = math.max(0, (self.playerQueueCount[entry.userId] or 0) - 1) end
	return entry
end

function MusicQueueManager:RemoveUserSongs(userId: number)
	if self.sharedQueue then return 0 end
	local removed = 0
	for index = #self.queue, 1, -1 do
		if self.queue[index].userId == userId then table.remove(self.queue, index); removed += 1 end
	end
	self.playerQueueCount[userId] = nil
	return removed
end

function MusicQueueManager:GetUserQueueCount(userId: number): number
	return self.playerQueueCount[userId] or 0
end

function MusicQueueManager:Cleanup()
	-- Shared queue data is never cleared by adapter cleanup.
	self.destroyed = true
	self.queue = nil
	self.releaseSlot = nil
end

return MusicQueueManager
