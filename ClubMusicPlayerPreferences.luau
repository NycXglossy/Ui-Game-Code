--!strict
-- Client-local player audio preferences. This module intentionally never
-- changes SoundService-wide SoundGroup or server-owned playback volume.
local Preferences = {}
Preferences.__index = Preferences

local function finite(value)
	return typeof(value) == "number" and value == value and math.abs(value) < math.huge
end

local VALID_PROFILES = {
	Standard = true,
	Soft = true,
	Bass = true,
	Night = true,
}

function Preferences.new(context)
	assert(typeof(context) == "table", "Player preferences require a local audio context.")
	assert(typeof(context.SetLocalGain) == "function", "Player preferences require SetLocalGain.")
	return setmetatable({
		context = context,
		volume = 1,
		muted = false,
		profile = "Standard",
		destroyed = false,
	}, Preferences)
end

function Preferences:SetVolume(value: number)
	if self.destroyed or not finite(value) then return false, "Invalid local volume." end
	self.volume = math.clamp(value, 0, 1)
	return self:Apply()
end

function Preferences:SetMuted(value: boolean)
	if self.destroyed or typeof(value) ~= "boolean" then return false, "Invalid mute setting." end
	self.muted = value
	return self:Apply()
end

function Preferences:SetProfile(value: string)
	if self.destroyed or typeof(value) ~= "string" or not VALID_PROFILES[value] then
		return false, "Unknown preference profile."
	end
	local previous = self.profile
	self.profile = value
	if typeof(self.context.SetLocalProfile) == "function" then
		local ok, result = pcall(self.context.SetLocalProfile, value)
		if not ok or result == false then
			self.profile = previous
			return false, "Local profile could not be applied."
		end
	end
	local applied, message = self:Apply()
	if not applied then
		self.profile = previous
		if typeof(self.context.SetLocalProfile) == "function" then
			pcall(self.context.SetLocalProfile, previous)
		end
		return false, message
	end
	return true, nil
end

function Preferences:Apply()
	if self.destroyed then return false, "Player preferences are unavailable." end
	local gain = if self.muted then 0 else self.volume
	local ok, result = pcall(self.context.SetLocalGain, gain)
	if not ok or result == false then return false, "Local volume could not be applied." end
	return true, nil
end

function Preferences:GetState()
	return { volume = self.volume, muted = self.muted, profile = self.profile }
end

function Preferences:Cleanup()
	self.destroyed = true
	self.context = nil
end

return Preferences
