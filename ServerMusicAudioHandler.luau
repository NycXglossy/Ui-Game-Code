--!strict
-- Non-owning, backend-neutral adapter for the controller's canonical audio source.
-- Legacy Sound remains supported; an injected modern AudioPlayer backend can be
-- inspected without transferring queue, transition, or playback authority.

local ServerMusicAudioHandler = {}
ServerMusicAudioHandler.__index = ServerMusicAudioHandler

export type Context = {
	Sound: Sound?,
	Backend: any?,
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
	local hasSound = typeof(context.Sound) == "Instance" and context.Sound:IsA("Sound")
	local hasBackend = typeof(context.Backend) == "table"
	assert(hasSound or hasBackend, "Audio handler requires the canonical Sound or an injected modern backend.")
	if hasSound then
		assert(context.Sound.Name == "ServerMusicSound", "Audio handler must reference SoundService.ServerMusicSound.")
		assert(context.Sound:GetAttribute("ManagedByClubMusicController") == true,
			"Audio handler refuses a Sound not marked as controller-owned.")
	end
	return setmetatable({ context = context, destroyed = false }, ServerMusicAudioHandler)
end

function ServerMusicAudioHandler:GetSound(): Sound?
	if self.destroyed then return nil end
	local sound = self.context.Sound
	return if sound and sound.Parent then sound else nil
end

function ServerMusicAudioHandler:GetAudioPlayer(): AudioPlayer?
	if self.destroyed or typeof(self.context.Backend) ~= "table" then return nil end
	local ok, player = pcall(function() return self.context.Backend:GetPlayer() end)
	if ok and typeof(player) == "Instance" and player:IsA("AudioPlayer") then return player end
	return nil
end

-- Snapshot contract used by controller diagnostics and playback quality checks.
-- It is read-only and does not start, stop, seek, or otherwise mutate playback.
function ServerMusicAudioHandler:GetPlaybackSnapshot()
	if self.destroyed then
		return { kind = "Unavailable", ready = false, playing = false, paused = false, position = 0, length = 0, asset = "" }
	end
	local backend = self.context.Backend
	if typeof(backend) == "table" then
		local player = self:GetAudioPlayer()
		local ok, ready = pcall(function() return backend:IsReady() end)
		local playingOk, playing = pcall(function() return backend:IsPlaying() end)
		local positionOk, position = pcall(function() return backend:GetTimePosition() end)
		local lengthOk, length = pcall(function() return backend:GetTimeLength() end)
		local asset = ""
		if player then pcall(function() asset = tostring(player.Asset) end) end
		return {
			kind = "AudioPlayer",
			ready = ok and ready == true,
			playing = playingOk and playing == true,
			paused = self:IsPaused(),
			position = positionOk and math.max(0, tonumber(position) or 0) or 0,
			length = lengthOk and math.max(0, tonumber(length) or 0) or 0,
			asset = asset,
		}
	end
	local sound = self:GetSound()
	return {
		kind = "Sound",
		ready = sound ~= nil and sound.IsLoaded,
		playing = sound ~= nil and sound.IsPlaying,
		paused = self:IsPaused(),
		position = if sound then math.max(0, sound.TimePosition) else 0,
		length = if sound then math.max(0, sound.TimeLength) else 0,
		asset = if sound then sound.SoundId else "",
	}
end

function ServerMusicAudioHandler:GetTimePosition(): number
	local snapshot = self:GetPlaybackSnapshot()
	return snapshot.position
end

function ServerMusicAudioHandler:GetTimeLength(): number
	local snapshot = self:GetPlaybackSnapshot()
	return snapshot.length
end

function ServerMusicAudioHandler:GetCurrentSoundId(): string?
	if self.destroyed then return nil end
	local snapshot = self:GetPlaybackSnapshot()
	if typeof(snapshot.asset) == "string" then return snapshot.asset end
	return nil
end

function ServerMusicAudioHandler:IsPlaying(): boolean
	local snapshot = self:GetPlaybackSnapshot()
	return snapshot.playing == true
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
	if sound then return sound.Volume end
	local player = self:GetAudioPlayer()
	return if player then player.Volume else 1
end

function ServerMusicAudioHandler:Cleanup()
	-- The Sound and SoundGroup belong to the controller; cleanup only drops this reference.
	self.destroyed = true
	self.context = nil
end

return ServerMusicAudioHandler
