--!strict
-- Authoritative in-memory queue operations for ClubMusic.
-- The controller supplies the one shared queue and its slot-release callback.
-- This service deliberately does not create a second queue or own playback state.

local MusicQueueManagerService = {}
MusicQueueManagerService.__index = MusicQueueManagerService

export type QueueManagerService = {
	queue: {any},
	releaseSlot: ((any) -> ())?,
	GetQueue: (self: QueueManagerService) -> {any},
	GetSize: (self: QueueManagerService) -> number,
	IsEmpty: (self: QueueManagerService) -> boolean,
	Insert: (self: QueueManagerService, index: number, entry: any) -> boolean,
	PopNext: (self: QueueManagerService) -> any?,
	RemoveAt: (self: QueueManagerService, index: number, release: boolean?) -> any?,
	RemoveUserSongs: (self: QueueManagerService, userId: number) -> number,
	Clear: (self: QueueManagerService, release: boolean?) -> number,
	ClearAutomatic: (self: QueueManagerService) -> number,
}

function MusicQueueManagerService.new(sharedQueue: {any}, releaseSlot: ((any) -> ())?): QueueManagerService
	assert(type(sharedQueue) == "table", "MusicQueueManagerService requires the controller-owned queue table")
	assert(releaseSlot == nil or type(releaseSlot) == "function", "MusicQueueManagerService releaseSlot must be a function")
	local self = setmetatable({}, MusicQueueManagerService)
	self.queue = sharedQueue
	self.releaseSlot = releaseSlot
	return self
end

function MusicQueueManagerService:GetQueue(): {any}
	return self.queue
end

function MusicQueueManagerService:GetSize(): number
	return #self.queue
end

function MusicQueueManagerService:IsEmpty(): boolean
	return #self.queue == 0
end

function MusicQueueManagerService:Insert(index: number, entry: any): boolean
	if type(index) ~= "number"
		or index % 1 ~= 0
		or index < 1
		or index > #self.queue + 1
		or type(entry) ~= "table"
	then
		return false
	end
	table.insert(self.queue, index, entry)
	return true
end

function MusicQueueManagerService:PopNext(): any?
	if #self.queue == 0 then
		return nil
	end
	local entry = table.remove(self.queue, 1)
	if self.releaseSlot then
		self.releaseSlot(entry)
	end
	return entry
end

function MusicQueueManagerService:RemoveAt(index: number, release: boolean?): any?
	if type(index) ~= "number"
		or index % 1 ~= 0
		or index < 1
		or index > #self.queue
	then
		return nil
	end

	local entry = table.remove(self.queue, index)
	if release ~= false and self.releaseSlot then
		self.releaseSlot(entry)
	end
	return entry
end

function MusicQueueManagerService:RemoveUserSongs(userId: number): number
	if type(userId) ~= "number" or userId <= 0 or userId % 1 ~= 0 then
		return 0
	end

	local removed = 0
	for index = #self.queue, 1, -1 do
		local entry = self.queue[index]
		if type(entry) == "table" and entry.source == "player" and entry.userId == userId then
			self:RemoveAt(index, true)
			removed += 1
		end
	end
	return removed
end

function MusicQueueManagerService:Clear(release: boolean?): number
	local removed = #self.queue
	if release ~= false and self.releaseSlot then
		for _, entry in ipairs(self.queue) do
			self.releaseSlot(entry)
		end
	end
	table.clear(self.queue)
	return removed
end

function MusicQueueManagerService:ClearAutomatic(): number
	local removed = 0
	for index = #self.queue, 1, -1 do
		local entry = self.queue[index]
		if type(entry) == "table" and entry.source ~= "player" then
			self:RemoveAt(index, false)
			removed += 1
		end
	end
	return removed
end

return MusicQueueManagerService
