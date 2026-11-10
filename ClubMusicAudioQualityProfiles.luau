--!strict
-- Validated audio quality profiles. Applies only to a supplied AudioPlayer;
-- per-player preferences must use a client-local graph, never a shared server gain.
local Profiles = {}
Profiles.__index = Profiles

local DEFINITIONS = {
	Standard = { playbackSpeed = 1, gain = 1 },
	Soft = { playbackSpeed = 1, gain = 0.75 },
	Bass = { playbackSpeed = 1, gain = 1 },
	Night = { playbackSpeed = 1, gain = 0.55 },
}

function Profiles.new(context)
	assert(typeof(context) == "table", "Audio quality profiles require context.")
	return setmetatable({ context = context, current = "Standard", destroyed = false }, Profiles)
end

function Profiles:GetProfiles()
	local copy = {}
	for name, values in pairs(DEFINITIONS) do copy[name] = table.clone(values) end
	return copy
end

function Profiles:Apply(name: string)
	if self.destroyed then return false, "Audio quality service is unavailable." end
	local profile = DEFINITIONS[name]
	if not profile then return false, "Unknown audio quality profile." end
	if typeof(self.context.SetPlaybackSpeed) == "function" then
		local ok, result = pcall(self.context.SetPlaybackSpeed, profile.playbackSpeed)
		if not ok or result == false then return false, "Could not apply playback speed." end
	end
	if typeof(self.context.SetGain) == "function" then
		local ok, result = pcall(self.context.SetGain, profile.gain)
		if not ok or result == false then return false, "Could not apply audio gain." end
	end
	self.current = name
	return true, name
end

function Profiles:GetCurrent()
	return self.current
end

function Profiles:Cleanup()
	self.destroyed = true
	self.context = nil
end

return Profiles
