--!strict
-- Non-owning adapter for SoundService.ServerMusicSound.
-- This module never creates, reparents, stops, or destroys the canonical Sound
-- unless an explicitly injected controller callback authorizes that operation.

local ServerMusicAudioHandler = {}
ServerMusicAudioHandler.__index = ServerMusicAudioHandler

export type Context = {
	Sound: Sound,
	GetPaused: (() -> boolean)?,
	Play: ((string, number?) -> (boolean, string?))?,
	Stop: (() -> (boolean, string?))?,
	Pause: (() -> (boolean, string?))?,
	Resume: (() -> (boolean, string?))?,
	SetVolume: ((number) -> (boolean, string?))?,
}

local function invoke(callback: any, ...)
	if typeof(callback) ~= "function" then
		return false, "Audio playback is owned by UI_Server_Controller."
	end
	local ok, result, message = pcall(callback, ...)
	if not ok then
		warn("[ClubMusic Audio Adapter] Controller callback failed: " .. tostring(result))
		return false, "The controller audio operation failed."
	end
	return result == true, if typeof(message) == "string" then message else nil
end

function ServerMusicAudioHandler.new(context: Context)
	assert(typeof(context) == "table", "Audio handler requires an injected context.")
	assert(typeof(context.Sound) == "Instance" and context.Sound:IsA("Sound"), "Audio handler requires the canonical Sound instance.")
	assert(context.Sound.Name == "ServerMusicSound", "Audio handler must reference SoundService.ServerMusicSound.")
	assert(context.Sound:GetAttribute("ManagedByClubMusicController") == true,
		"Audio handler refuses a Sound not marked as controller-owned.")
	return setmetatable({ context = context, destroyed = false }, ServerMusicAudioHandler)
end

function ServerMusicAudioHandler:GetSound(): Sound?
	if self.destroyed then return nil end
	local sound = self.context.Sound
	return if sound and sound.Parent then sound else nil
end

function ServerMusicAudioHandler:GetTimePosition(): number
	local sound = self:GetSound()
	return if sound then math.max(0, sound.TimePosition) else 0
end

function ServerMusicAudioHandler:GetTimeLength(): number
	local sound = self:GetSound()
	return if sound then math.max(0, sound.TimeLength) else 0
end

function ServerMusicAudioHandler:GetCurrentSoundId(): string?
	local sound = self:GetSound()
	return if sound then sound.SoundId else nil
end

function ServerMusicAudioHandler:IsPlaying(): boolean
	local sound = self:GetSound()
	return sound ~= nil and sound.IsPlaying
end

function ServerMusicAudioHandler:IsPaused(): boolean
	if self.destroyed then return false end
	if typeof(self.context.GetPaused) == "function" then
		local ok, value = pcall(self.context.GetPaused)
		if ok then return value == true end
	end
	return false
end

function ServerMusicAudioHandler:Play(soundId: string, timePosition: number?)
	if self.destroyed then return false, "Audio adapter has been cleaned up." end
	if typeof(soundId) ~= "string" or #soundId > 64 or not string.match(soundId, "^rbxassetid://%d+$") then
		return false, "Invalid audio asset ID."
	end
	local position = if typeof(timePosition) == "number" and timePosition == timePosition
		then math.clamp(timePosition, 0, 86400) else 0
	return invoke(self.context.Play, soundId, position)
end

function ServerMusicAudioHandler:Stop()
	if self.destroyed then return false, "Audio adapter has been cleaned up." end
	return invoke(self.context.Stop)
end

function ServerMusicAudioHandler:Pause()
	if self.destroyed then return false, "Audio adapter has been cleaned up." end
	return invoke(self.context.Pause)
end

function ServerMusicAudioHandler:Resume()
	if self.destroyed then return false, "Audio adapter has been cleaned up." end
	return invoke(self.context.Resume)
end

function ServerMusicAudioHandler:SetVolume(volume: number)
	if self.destroyed then return false, "Audio adapter has been cleaned up." end
	if typeof(volume) ~= "number" or volume ~= volume or math.abs(volume) == math.huge then
		return false, "Invalid volume."
	end
	return invoke(self.context.SetVolume, math.clamp(volume, 0, 1))
end

function ServerMusicAudioHandler:GetVolume(): number
	local sound = self:GetSound()
	return if sound then sound.Volume else 1
end

function ServerMusicAudioHandler:Cleanup()
	-- The Sound and SoundGroup belong to the controller; cleanup only drops this reference.
	self.destroyed = true
	self.context = nil
end

return ServerMusicAudioHandler
