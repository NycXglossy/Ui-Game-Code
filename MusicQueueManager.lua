--!strict
-- Adapter for the ClubMusic controller's authoritative queue.
-- This module deliberately owns no queue table or per-player counters.
local MusicQueueManager = {}
MusicQueueManager.__index = MusicQueueManager

export type QueueManager = {
	queue: {any},
	releaseSlot: ((any) -> ())?,
	GetQueue: (self: QueueManager) -> {any},
	GetSize: (self: QueueManager) -> number,
	IsEmpty: (self: QueueManager) -> boolean,
	Insert: (self: QueueManager, index: number, entry: any) -> boolean,
	PopNext: (self: QueueManager) -> any?,
	RemoveAt: (self: QueueManager, index: number, release: boolean?) -> any?,
	RemoveUserSongs: (self: QueueManager, userId: number) -> number,
	Clear: (self: QueueManager, release: boolean?) -> number,
	ClearAutomatic: (self: QueueManager) -> number,
}

function MusicQueueManager.new(sharedQueue: {any}, releaseSlot: ((any) -> ())?): QueueManager
	assert(type(sharedQueue) == "table", "MusicQueueManager requires the controller-owned queue table")
	local self = setmetatable({}, MusicQueueManager)
	self.queue = sharedQueue
	self.releaseSlot = releaseSlot
	return self
end

function MusicQueueManager:GetQueue(): {any}
	return self.queue
end

function MusicQueueManager:GetSize(): number
	return #self.queue
end

function MusicQueueManager:IsEmpty(): boolean
	return #self.queue == 0
end

function MusicQueueManager:Insert(index: number, entry: any): boolean
	if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > #self.queue + 1 or type(entry) ~= "table" then
		return false
	end
	table.insert(self.queue, index, entry)
	return true
end

function MusicQueueManager:PopNext(): any?
	if #self.queue == 0 then return nil end
	local entry = table.remove(self.queue, 1)
	if self.releaseSlot then self.releaseSlot(entry) end
	return entry
end

function MusicQueueManager:RemoveAt(index: number, release: boolean?): any?
	if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > #self.queue then return nil end
	local entry = table.remove(self.queue, index)
	if release ~= false and self.releaseSlot then self.releaseSlot(entry) end
	return entry
end

function MusicQueueManager:RemoveUserSongs(userId: number): number
	if type(userId) ~= "number" or userId <= 0 or userId % 1 ~= 0 then return 0 end
	local removed = 0
	for index = #self.queue, 1, -1 do
		local entry = self.queue[index]
		if entry.source == "player" and entry.userId == userId then
			self:RemoveAt(index, true)
			removed += 1
		end
	end
	return removed
end

function MusicQueueManager:Clear(release: boolean?): number
	local removed = #self.queue
	if release ~= false and self.releaseSlot then
		for _, entry in ipairs(self.queue) do self.releaseSlot(entry) end
	end
	table.clear(self.queue)
	return removed
end

function MusicQueueManager:ClearAutomatic(): number
	local removed = 0
	for index = #self.queue, 1, -1 do
		if self.queue[index].source ~= "player" then
			self:RemoveAt(index, false)
			removed += 1
		end
	end
	return removed
end

return MusicQueueManager
