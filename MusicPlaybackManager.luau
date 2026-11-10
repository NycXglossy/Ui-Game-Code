--!strict
-- ClubMusic controller-owned playback facade.
-- This module never owns playback state, clocks, remotes, Heartbeat loops, or Sound.Ended.
-- Inject controller callbacks; the controller remains the sole playback authority.

local MusicPlaybackManager = {}
MusicPlaybackManager.__index = MusicPlaybackManager

export type Context = {
	GetSnapshot: () -> any,
	GetSound: (() -> Sound?)?,
	GetAudioSnapshot: (() -> any)?,
	GetElapsedTime: (() -> number)?,
	PlayTrack: ((any, any?) -> (boolean, string?))?,
	StopTrack: (() -> (boolean, string?))?,
	TogglePause: ((Player) -> (boolean, string?))?,
	RestartTrack: ((Player) -> (boolean, string?))?,
}

local function call(callback: any, ...)
	if typeof(callback) ~= "function" then
		return false, "This operation is owned by UI_Server_Controller."
	end
	local ok, result, message = pcall(callback, ...)
	if not ok then
		warn("[ClubMusic Playback Adapter] Controller callback failed: " .. tostring(result))
		return false, "The controller operation failed."
	end
	return result == true, if typeof(message) == "string" then message else nil
end

function MusicPlaybackManager.new(context: Context)
	assert(typeof(context) == "table", "Playback manager requires an injected controller context.")
	assert(typeof(context.GetSnapshot) == "function", "Playback context requires GetSnapshot.")
	assert(typeof(context.GetSound) == "function" or typeof(context.GetAudioSnapshot) == "function",
		"Playback context requires GetSound or GetAudioSnapshot.")
	return setmetatable({ context = context, destroyed = false }, MusicPlaybackManager)
end

function MusicPlaybackManager:GetState()
	if self.destroyed then return nil end
	local ok, snapshot = pcall(self.context.GetSnapshot)
	if not ok then
		warn("[ClubMusic Playback Adapter] Snapshot callback failed: " .. tostring(snapshot))
		return nil
	end
	return snapshot
end

function MusicPlaybackManager:GetCurrentSong()
	local snapshot = self:GetState()
	if typeof(snapshot) ~= "table" then return nil end
	return snapshot.nowPlaying or snapshot.current
end

function MusicPlaybackManager:GetSound(): Sound?
	if self.destroyed or typeof(self.context.GetSound) ~= "function" then return nil end
	local ok, sound = pcall(self.context.GetSound)
	if ok and typeof(sound) == "Instance" and sound:IsA("Sound") then return sound end
	return nil
end

function MusicPlaybackManager:IsPlaying(): boolean
	local sound = self:GetSound()
	return sound ~= nil and sound.IsPlaying
end

function MusicPlaybackManager:IsPaused(): boolean
	local snapshot = self:GetState()
	if typeof(snapshot) == "table" then
		if typeof(snapshot.playbackPaused) == "boolean" then return snapshot.playbackPaused end
		if typeof(snapshot.paused) == "boolean" then return snapshot.paused end
	end
	return false
end

function MusicPlaybackManager:GetElapsedTime(): number
	if self.destroyed then return 0 end
	if typeof(self.context.GetElapsedTime) == "function" then
		local ok, value = pcall(self.context.GetElapsedTime)
		if ok and typeof(value) == "number" and value == value and math.abs(value) < math.huge then
			return math.max(0, value)
		end
	end
	local song = self:GetCurrentSong()
	if typeof(song) == "table" and typeof(song.elapsed) == "number" then return math.max(0, song.elapsed) end
	local sound = self:GetSound()
	return if sound then math.max(0, sound.TimePosition) else 0
end

-- Passive quality inspection; caller owns scheduling and recovery policy.
-- No task loop, playback mutation, or automatic track transition is started here.
function MusicPlaybackManager:InspectQuality()
	if self.destroyed then return { state = "Unavailable", reason = "AdapterDestroyed" } end
	local song = self:GetCurrentSong()
	if typeof(song) ~= "table" or tostring(song.trackId or "") == "" then
		return { state = "Idle" }
	end
	if tostring(song.soundId or "") == "" then
		return { state = "SilentCatalogTrack" }
	end

	local snapshot = nil
	if typeof(self.context.GetAudioSnapshot) == "function" then
		local ok, value = pcall(self.context.GetAudioSnapshot)
		if ok and typeof(value) == "table" then snapshot = value end
	end
	if snapshot then
		local elapsed = self:GetElapsedTime()
		local isReady = snapshot.ready == true
		local isPlaying = snapshot.playing == true
		local length = if isReady then math.max(0, tonumber(snapshot.length) or 0) else 0
		if isPlaying then
			return { state = "Playing", backend = snapshot.kind, elapsed = elapsed, loaded = isReady, length = length }
		end
		if snapshot.paused == true then
			return { state = "Paused", backend = snapshot.kind, elapsed = elapsed, loaded = isReady, length = length }
		end
		if isReady and length > 0 then
			return { state = "StoppedAfterLoad", backend = snapshot.kind, elapsed = elapsed, loaded = true, length = length }
		end
		return { state = "BufferingOrStopped", backend = snapshot.kind, elapsed = elapsed, loaded = isReady, length = length }
	end

	local sound = self:GetSound()
	if not sound then return { state = "Unavailable", reason = "AudioInstanceMissing" } end
	local elapsed = self:GetElapsedTime()
	local isPlaying = sound.IsPlaying
	local isLoaded = sound.IsLoaded
	local length = if isLoaded then sound.TimeLength else 0
	if isPlaying then return { state = "Playing", elapsed = elapsed, loaded = isLoaded, length = length } end
	if isLoaded and length > 0 then
		return { state = "StoppedAfterLoad", elapsed = elapsed, loaded = true, length = length }
	end
	return { state = "BufferingOrStopped", elapsed = elapsed, loaded = isLoaded, length = length }
end

function MusicPlaybackManager:GetRemainingTime(): number
	local song = self:GetCurrentSong()
	if typeof(song) ~= "table" then return 0 end
	local duration = tonumber(song.duration) or 0
	return math.max(0, duration - self:GetElapsedTime())
end

function MusicPlaybackManager:Play(songData: any, options: any?)
	if self.destroyed then return false, "Playback adapter has been cleaned up." end
	return call(self.context.PlayTrack, songData, options)
end

function MusicPlaybackManager:Stop()
	if self.destroyed then return false, "Playback adapter has been cleaned up." end
	return call(self.context.StopTrack)
end

function MusicPlaybackManager:Pause(player: Player)
	if self.destroyed then return false, "Playback adapter has been cleaned up." end
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent == nil then
		return false, "A connected player is required."
	end
	return call(self.context.TogglePause, player)
end

function MusicPlaybackManager:Restart(player: Player)
	if self.destroyed then return false, "Playback adapter has been cleaned up." end
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent == nil then
		return false, "A connected player is required."
	end
	return call(self.context.RestartTrack, player)
end

function MusicPlaybackManager:Reset()
	return self:Stop()
end

function MusicPlaybackManager:Cleanup()
	-- Deliberately does not stop music or disconnect controller-owned events.
	self.destroyed = true
	self.context = nil
end

return MusicPlaybackManager
