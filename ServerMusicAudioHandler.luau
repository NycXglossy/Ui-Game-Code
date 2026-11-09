local ServerMusicAudioHandler = {}
ServerMusicAudioHandler.__index = ServerMusicAudioHandler

local CONFIG = {
	Audio = {
		DefaultVolume = 1
	}
}

function ServerMusicAudioHandler.new()
	local self = setmetatable({}, ServerMusicAudioHandler)

	self.serverSound = nil
	self.soundContainer = nil
	self.musicGroup = nil
	self.currentSoundId = nil
	self.isPlaying = false
	self.isPaused = false

	self:CreateSoundContainer()
	self:CreateServerSound()

	return self
end

function ServerMusicAudioHandler:CreateSoundContainer()
	local soundService = game:GetService("SoundService")

	local musicGroup = soundService:FindFirstChild("MusicGroup")
	if not musicGroup then
		musicGroup = Instance.new("SoundGroup")
		musicGroup.Name = "MusicGroup"
		musicGroup.Parent = soundService
		musicGroup.Volume = 1
	end

	self.soundContainer = soundService
	self.musicGroup = musicGroup

	return soundService
end

function ServerMusicAudioHandler:CreateServerSound()
	if self.serverSound and self.serverSound.Parent then
		return self.serverSound
	end

	if self.serverSound then
		pcall(function()
			self.serverSound:Stop()
			self.serverSound:Destroy()
		end)
	end

	if not self.soundContainer then
		self:CreateSoundContainer()
	end

	local existingSound = self.soundContainer:FindFirstChild("ServerMusicSound")
	if existingSound and existingSound:IsA("Sound") then
		self.serverSound = existingSound
		return existingSound
	end

	local sound = Instance.new("Sound")
	sound.Name = "ServerMusicSound"
	sound.Parent = self.soundContainer
	sound.Volume = CONFIG.Audio.DefaultVolume
	sound.Looped = false
	sound.SoundGroup = self.musicGroup

	self.serverSound = sound
	return sound
end

function ServerMusicAudioHandler:Play(soundId, timePosition)
	if not self.serverSound or not self.serverSound.Parent then
		self:CreateServerSound()
	end

	if self.serverSound.IsPlaying then
		self.serverSound:Stop()
	end

	local assetId = "rbxassetid://" .. soundId
	self.serverSound.SoundId = assetId
	self.serverSound.TimePosition = timePosition or 0

	local success = pcall(function()
		self.serverSound:Play()
	end)

	if success then
		self.currentSoundId = soundId
		self.isPlaying = true
		self.isPaused = false
		return true
	else
		warn("[ServerAudio] Failed to play:", soundId)
		return false
	end
end

function ServerMusicAudioHandler:Stop()
	if not self.serverSound then return end

	pcall(function()
		self.serverSound:Stop()
	end)

	self.isPlaying = false
	self.isPaused = false
	self.currentSoundId = nil
end

function ServerMusicAudioHandler:Pause()
	if not self.serverSound then return end

	pcall(function()
		self.serverSound:Pause()
	end)

	self.isPaused = true
end

function ServerMusicAudioHandler:Resume()
	if not self.serverSound then return end

	pcall(function()
		self.serverSound:Resume()
	end)

	self.isPaused = false
end

function ServerMusicAudioHandler:SetVolume(volume)
	if not self.serverSound then return end
	volume = math.clamp(volume, 0, 1)
	self.serverSound.Volume = volume
end

function ServerMusicAudioHandler:GetVolume()
	if not self.serverSound then return CONFIG.Audio.DefaultVolume end
	return self.serverSound.Volume
end

function ServerMusicAudioHandler:IsPlaying()
	return self.isPlaying and self.serverSound and self.serverSound.IsPlaying
end

function ServerMusicAudioHandler:IsPaused()
	return self.isPaused
end

function ServerMusicAudioHandler:GetTimePosition()
	if not self.serverSound then return 0 end
	return self.serverSound.TimePosition
end

function ServerMusicAudioHandler:GetTimeLength()
	if not self.serverSound then return 0 end
	return self.serverSound.TimeLength
end

function ServerMusicAudioHandler:GetCurrentSoundId()
	return self.currentSoundId
end

-- NEW: Method to get Sound object for connecting events
function ServerMusicAudioHandler:GetSound()
	return self.serverSound
end

function ServerMusicAudioHandler:Cleanup()
	if self.serverSound then
		pcall(function()
			self.serverSound:Stop()
			self.serverSound:Destroy()
		end)
		self.serverSound = nil
	end
end

return ServerMusicAudioHandler