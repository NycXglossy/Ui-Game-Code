--!strict
-- Compatibility adapter for the ClubMusic controller.
-- Queue behavior lives in MusicQueueManagerService; this module owns no queue
-- table, counters, playback state, or duplicate service implementation.

local ServerStorage = game:GetService("ServerStorage")
local MusicQueueManager = {}

-- Support both direct ServerStorage installation and the canonical
-- ClubMusic_ServerStorage_Modules RBXMX folder layout.
local serviceModule = script.Parent:FindFirstChild("MusicQueueManagerService")
if not serviceModule then serviceModule = ServerStorage:FindFirstChild("MusicQueueManagerService") end
if not serviceModule then
	local packageFolder = ServerStorage:FindFirstChild("ClubMusic_ServerStorage_Modules")
	if packageFolder and packageFolder:IsA("Folder") then
		serviceModule = packageFolder:FindFirstChild("MusicQueueManagerService")
	end
end
if not serviceModule then serviceModule = ServerStorage:WaitForChild("MusicQueueManagerService", 20) end
if not serviceModule or not serviceModule:IsA("ModuleScript") then
	error("[ClubMusic] Missing MusicQueueManagerService ModuleScript in the controller's ServerStorage package.")
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
