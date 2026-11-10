--!strict
-- Optional spatial-audio graph builder. Caller must provide the venue emitter
-- and listener placement policy; no spatial graph is created automatically.
local Spatial = {}
Spatial.__index = Spatial

local function validWorldParent(instance: any): boolean
	return typeof(instance) == "Instance"
		and (instance:IsA("BasePart") or instance:IsA("Attachment") or instance:IsA("Camera"))
end

function Spatial.new(context)
	assert(typeof(context) == "table", "Spatial audio requires context.")
	assert(typeof(context.AudioPlayer) == "Instance" and context.AudioPlayer:IsA("AudioPlayer"),
		"Spatial audio requires a valid AudioPlayer.")
	assert(typeof(context.AudioDeviceOutput) == "Instance" and context.AudioDeviceOutput:IsA("AudioDeviceOutput"),
		"Spatial audio requires a valid AudioDeviceOutput.")
	return setmetatable({ context = context, graphs = {}, enabled = false, destroyed = false }, Spatial)
end

function Spatial:CreateRoute(key: string, emitterParent: Instance, listenerParent: Instance)
	if self.destroyed then return false, "Spatial audio service is unavailable." end
	if typeof(key) ~= "string" or #key < 1 or #key > 48 or not string.match(key, "^[%w_%-]+$") then
		return false, "Invalid spatial route key."
	end
	if self.graphs[key] then return false, "Spatial route already exists." end
	if not validWorldParent(emitterParent) or not validWorldParent(listenerParent) then
		return false, "Emitter and listener must be parented to a BasePart, Attachment, or Camera."
	end
	local context = self.context
	if not context or not context.AudioPlayer or not context.AudioDeviceOutput
		or context.AudioPlayer.Parent == nil or context.AudioDeviceOutput.Parent == nil then
		return false, "Spatial audio endpoints are unavailable."
	end

	local folder = Instance.new("Folder")
	folder.Name = "ClubMusicSpatial_" .. key
	local emitter, listener
	local ok, err = pcall(function()
		emitter = Instance.new("AudioEmitter")
		emitter.Name = "MusicEmitter"
		emitter.Parent = emitterParent
		listener = Instance.new("AudioListener")
		listener.Name = "MusicListener"
		listener.Parent = listenerParent
		local sourceWire = Instance.new("Wire")
		sourceWire.SourceInstance = context.AudioPlayer
		sourceWire.TargetInstance = emitter
		sourceWire.Parent = folder
		local listenerWire = Instance.new("Wire")
		listenerWire.SourceInstance = emitter
		listenerWire.TargetInstance = listener
		listenerWire.Parent = folder
		local outputWire = Instance.new("Wire")
		outputWire.SourceInstance = listener
		outputWire.TargetInstance = context.AudioDeviceOutput
		outputWire.Parent = folder
		folder.Parent = context.Parent or workspace
	end)
	if not ok then
		pcall(function() folder:Destroy() end)
		if emitter then pcall(function() emitter:Destroy() end) end
		if listener then pcall(function() listener:Destroy() end) end
		return false, "Spatial route creation failed: " .. tostring(err)
	end
	self.graphs[key] = { folder = folder, emitter = emitter, listener = listener }
	return true, key
end

function Spatial:RemoveRoute(key: string)
	local graph = self.graphs[key]
	if not graph then return false end
	self.graphs[key] = nil
	pcall(function() graph.folder:Destroy() end)
	pcall(function() graph.emitter:Destroy() end)
	pcall(function() graph.listener:Destroy() end)
	return true
end

function Spatial:SetEnabled(value: boolean)
	if self.destroyed or typeof(value) ~= "boolean" then return false end
	if typeof(self.context.OnEnabledChanged) == "function" then
		local ok, result = pcall(self.context.OnEnabledChanged, value)
		if not ok or result == false then return false end
	end
	self.enabled = value
	return true
end

function Spatial:Cleanup()
	if self.destroyed then return end
	local keys = {}
	for key in pairs(self.graphs) do table.insert(keys, key) end
	for _, key in ipairs(keys) do self:RemoveRoute(key) end
	self.destroyed = true
	self.context = nil
end

return Spatial
