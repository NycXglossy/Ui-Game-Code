--!strict
-- Optional spatial-audio graph builder. Caller must provide the venue emitter
-- and listener placement policy; no spatial graph is created automatically.
local Spatial = {}
Spatial.__index = Spatial

function Spatial.new(context)
	assert(typeof(context) == "table", "Spatial audio requires context.")
	return setmetatable({ context = context, graphs = {}, enabled = false, destroyed = false }, Spatial)
end

function Spatial:CreateRoute(key: string, emitterParent: Instance, listenerParent: Instance)
	if self.destroyed then return false, "Spatial audio service is unavailable." end
	if typeof(key) ~= "string" or #key < 1 or #key > 48 then return false, "Invalid spatial route key." end
	if self.graphs[key] then return false, "Spatial route already exists." end
	if typeof(emitterParent) ~= "Instance" or typeof(listenerParent) ~= "Instance" then
		return false, "Emitter and listener parents are required."
	end
	local folder = Instance.new("Folder")
	folder.Name = "ClubMusicSpatial_" .. key
	local emitter = Instance.new("AudioEmitter")
	emitter.Name = "MusicEmitter"
	emitter.Parent = emitterParent
	local listener = Instance.new("AudioListener")
	listener.Name = "MusicListener"
	listener.Parent = listenerParent
	local sourceWire = Instance.new("Wire")
	sourceWire.SourceInstance = self.context.AudioPlayer
	sourceWire.TargetInstance = emitter
	sourceWire.Parent = folder
	local listenerWire = Instance.new("Wire")
	listenerWire.SourceInstance = emitter
	listenerWire.TargetInstance = listener
	listenerWire.Parent = folder
	local outputWire = Instance.new("Wire")
	outputWire.SourceInstance = listener
	outputWire.TargetInstance = self.context.AudioDeviceOutput
	outputWire.Parent = folder
	folder.Parent = self.context.Parent or workspace
	self.graphs[key] = { folder = folder, emitter = emitter, listener = listener }
	return true, key
end

function Spatial:RemoveRoute(key: string)
	local graph = self.graphs[key]
	if not graph then return false end
	pcall(function() graph.folder:Destroy() end)
	pcall(function() graph.emitter:Destroy() end)
	pcall(function() graph.listener:Destroy() end)
	self.graphs[key] = nil
	return true
end

function Spatial:SetEnabled(value: boolean)
	if self.destroyed or typeof(value) ~= "boolean" then return false end
	self.enabled = value
	if typeof(self.context.OnEnabledChanged) == "function" then
		local ok, result = pcall(self.context.OnEnabledChanged, value)
		if not ok or result == false then self.enabled = not value; return false end
	end
	return true
end

function Spatial:Cleanup()
	if self.destroyed then return end
	for key in pairs(self.graphs) do self:RemoveRoute(key) end
	self.destroyed = true
	self.context = nil
end

return Spatial
