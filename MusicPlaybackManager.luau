local RunService = game:GetService("RunService")
local ServerMusicAudioHandler = require(script.Parent.ServerMusicAudioHandler)

local MusicPlaybackManager = {}
MusicPlaybackManager.__index = MusicPlaybackManager

local CONFIG = {
	PROGRESS_BROADCAST_INTERVAL = 1
}

function MusicPlaybackManager.new(config)
	local self = setmetatable({}, MusicPlaybackManager)

	self.config = config
	self.currentSong = nil
	self.currentUploader = nil
	self.isPlaying = false
	self.isPaused = false
	self.songStartTime = 0
	self.songDuration = 0
	self.isPlaylistMode = false

	self.audioHandler = ServerMusicAudioHandler.new()

	self.autoNextCallback = nil
	self.endedConnection = nil
	self.progressConnection = nil
	self.lastProgressBroadcast = 0

	return self
end

function MusicPlaybackManager:GetState()
	return {
		currentSong = self.currentSong,
		currentUploader = self.currentUploader,
		isPlaying = self.isPlaying,
		isPaused = self.isPaused,
		startTime = self.songStartTime,
		duration = self.songDuration,
		isPlaylistMode = self.isPlaylistMode,
		elapsedTime = self:GetElapsedTime()
	}
end

function MusicPlaybackManager:IsPlaying()
	return self.isPlaying and self.audioHandler:IsPlaying()
end

function MusicPlaybackManager:IsPaused()
	return self.isPaused
end

function MusicPlaybackManager:GetCurrentSong()
	return self.currentSong
end

function MusicPlaybackManager:GetElapsedTime()
	if self.isPaused then
		return self.audioHandler:GetTimePosition()
	elseif self.isPlaying then
		return self.audioHandler:GetTimePosition()
	end
	return 0
end

function MusicPlaybackManager:GetRemainingTime()
	if not self.isPlaying then return 0 end
	local elapsed = self:GetElapsedTime()
	return math.max(0, self.songDuration - elapsed)
end

function MusicPlaybackManager:IsFromPlaylist()
	return self.isPlaylistMode
end

function MusicPlaybackManager:ConnectEndedEvent()
	-- Disconnect previous
	if self.endedConnection then
		self.endedConnection:Disconnect()
		self.endedConnection = nil
	end

	local sound = self.audioHandler:GetSound()
	if not sound then 
		warn("[PlaybackManager] No sound object to connect Ended event")
		return 
	end

	-- Connect to Sound.Ended event
	self.endedConnection = sound.Ended:Connect(function()
		print(string.format("[PlaybackManager] Sound.Ended triggered for: %s", 
			self.currentSong and self.currentSong.judul or "Unknown"))

		if self.autoNextCallback and self.isPlaying then
			task.spawn(function()
				local success, err = pcall(self.autoNextCallback)
				if not success then
					warn("[PlaybackManager] AutoNext error:", err)
				end
			end)
		end
	end)
end

function MusicPlaybackManager:StartProgressBroadcast(remotes)
	if self.progressConnection then
		self.progressConnection:Disconnect()
	end

	self.progressConnection = RunService.Heartbeat:Connect(function()
		if not self.isPlaying or self.isPaused then return end

		local now = tick()
		if now - self.lastProgressBroadcast < CONFIG.PROGRESS_BROADCAST_INTERVAL then
			return
		end

		self.lastProgressBroadcast = now
		self:UpdateProgress(remotes)
	end)
end

function MusicPlaybackManager:StopProgressBroadcast()
	if self.progressConnection then
		self.progressConnection:Disconnect()
		self.progressConnection = nil
	end
end

function MusicPlaybackManager:Play(remotes, songData, uploaderName, isFromPlaylist)
	-- Cleanup previous
	if self.endedConnection then
		self.endedConnection:Disconnect()
		self.endedConnection = nil
	end
	self:StopProgressBroadcast()

	local musicData = songData.musicData or songData
	local duration = songData.Duration or musicData.Duration or self.config.DEFAULT_SONG_DURATION

	if duration <= 0 then
		warn("[PlaybackManager] Invalid duration:", duration)
		return false
	end

	-- Set state
	self.currentSong = musicData
	self.currentUploader = uploaderName or "System"
	self.isPlaying = true
	self.isPaused = false
	self.songStartTime = tick()
	self.songDuration = duration
	self.isPlaylistMode = isFromPlaylist or false

	local success = self.audioHandler:Play(musicData.id, 0)

	if not success then
		warn("[PlaybackManager] Failed to play:", musicData.id)
		self:Stop(remotes)
		return false
	end

	print(string.format("[PlaybackManager] Playing: %s | Duration: %.0fs", 
		musicData.judul or "Unknown", duration))

	-- Connect Ended event
	self:ConnectEndedEvent()

	-- Start progress broadcast
	self:StartProgressBroadcast(remotes)

	self:BroadcastSongUpdate(remotes, musicData, uploaderName, duration)

	return true
end

function MusicPlaybackManager:Stop(remotes)
	if self.endedConnection then
		self.endedConnection:Disconnect()
		self.endedConnection = nil
	end
	self:StopProgressBroadcast()

	self.audioHandler:Stop()

	self.currentSong = nil
	self.currentUploader = nil
	self.isPlaying = false
	self.isPaused = false
	self.isPlaylistMode = false
	self.autoNextCallback = nil

	self:BroadcastStopMusic(remotes)
end

function MusicPlaybackManager:Pause(remotes)
	if not self.isPlaying then return false end

	self.isPaused = not self.isPaused

	if self.isPaused then
		self:StopProgressBroadcast()
		self.audioHandler:Pause()
	else
		self.audioHandler:Resume()
		self:StartProgressBroadcast(remotes)
	end

	self:BroadcastPauseState(remotes, self.isPaused)

	return true
end

function MusicPlaybackManager:Restart(remotes)
	if not self.currentSong then return false end

	if self.endedConnection then
		self.endedConnection:Disconnect()
		self.endedConnection = nil
	end
	self:StopProgressBroadcast()

	self.songStartTime = tick()
	self.isPaused = false

	local success = self.audioHandler:Play(self.currentSong.id, 0)

	if success then
		self:ConnectEndedEvent()
		self:StartProgressBroadcast(remotes)
		self:BroadcastSongUpdate(remotes, self.currentSong, self.currentUploader, self.songDuration)
		return true
	end

	return false
end

function MusicPlaybackManager:BroadcastSongUpdate(remotes, musicData, uploaderName, duration)
	pcall(function()
		remotes.MusicBroadcast:FireAllClients("SongUpdate", {
			SoundId = musicData.id,
			Title = musicData.judul or "Unknown",
			AddedBy = uploaderName or "Unknown",
			Duration = duration,
			IsPlaying = true,
			ServerTime = tick()
		})
	end)
end

function MusicPlaybackManager:BroadcastStopMusic(remotes)
	pcall(function()
		remotes.MusicBroadcast:FireAllClients("StopMusic", {})
	end)
end

function MusicPlaybackManager:BroadcastPauseState(remotes, isPaused)
	pcall(function()
		remotes.MusicBroadcast:FireAllClients("PauseState", {
			IsPaused = isPaused,
			TimePosition = self.audioHandler:GetTimePosition()
		})
	end)
end

function MusicPlaybackManager:UpdateProgress(remotes)
	if not self.isPlaying or self.isPaused then return end

	local elapsed = self.audioHandler:GetTimePosition()

	pcall(function()
		remotes.MusicBroadcast:FireAllClients("Progress", {
			Current = elapsed,
			Duration = self.songDuration,
			IsPlaying = true,
			ServerTime = tick()
		})
	end)
end

function MusicPlaybackManager:SyncToPlayer(remotes, player)
	if not self.isPlaying or not self.currentSong then
		return
	end

	local elapsed = self.audioHandler:GetTimePosition()

	pcall(function()
		remotes.MusicUpdate:FireClient(player, "SyncMusic", {
			SoundId = self.currentSong.id,
			Title = self.currentSong.judul,
			AddedBy = self.currentUploader,
			TimePosition = elapsed,
			Duration = self.songDuration,
			IsPlaying = self.isPlaying,
			IsPaused = self.isPaused
		})
	end)
end

function MusicPlaybackManager:Reset(remotes)
	self:Stop(remotes)
end

function MusicPlaybackManager:Cleanup()
	if self.endedConnection then
		self.endedConnection:Disconnect()
		self.endedConnection = nil
	end
	self:StopProgressBroadcast()
	self.audioHandler:Cleanup()
	self.autoNextCallback = nil
end

return MusicPlaybackManager