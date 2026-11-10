--!strict
-- Compatibility adapter for the ClubMusic controller.
-- Queue behavior lives in MusicQueueManagerService; this module owns no queue
-- table, counters, playback state, or duplicate service implementation.

local ServerStorage = game:GetService("ServerStorage")
local MusicQueueManager = {}

local serviceModule = ServerStorage:WaitForChild("MusicQueueManagerService", 20)
if not serviceModule or not serviceModule:IsA("ModuleScript") then
	error("[ClubMusic] Missing ServerStorage.MusicQueueManagerService ModuleScript.")
end

local serviceRequireOk, serviceRequireResult = pcall(require, serviceModule)
if not serviceRequireOk then
	error("[ClubMusic] MusicQueueManagerService failed to load: " .. tostring(serviceRequireResult))
end

local MusicQueueManagerService = serviceRequireResult
if type(MusicQueueManagerService) ~= "table" or type(MusicQueueManagerService.new) ~= "function" then
	error("[ClubMusic] MusicQueueManagerService must return a table with a .new() constructor.")
end

function MusicQueueManager.new(sharedQueue: {any}, releaseSlot: ((any) -> ())?): any
	return MusicQueueManagerService.new(sharedQueue, releaseSlot)
end

return MusicQueueManager
