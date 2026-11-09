local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MusicModule = require(ReplicatedStorage.Modules:WaitForChild("MusicModule"))

local MusicPlaylistManager = {}
MusicPlaylistManager.__index = MusicPlaylistManager

function MusicPlaylistManager.new(config)
	local self = setmetatable({}, MusicPlaylistManager)

	self.config = config
	self.playlistIndex = 1
	self.shuffleMode = false
	self.playedSongs = {}

	return self
end

-- ====================================
-- PLAYLIST OPERATIONS
-- ====================================

function MusicPlaylistManager:GetNextSong()
	local playlist = MusicModule:GetAllMusic()

	if #playlist == 0 then
		warn("Playlist kosong!")
		return nil
	end

	local nextSong

	if self.shuffleMode then
		-- Random mode - avoid recently played songs
		local availableSongs = {}

		for i, song in ipairs(playlist) do
			if not self.playedSongs[song.id] then
				table.insert(availableSongs, song)
			end
		end

		-- Reset if all songs have been played
		if #availableSongs == 0 then
			self.playedSongs = {}
			availableSongs = playlist
		end

		-- Pick random song
		local randomIndex = math.random(1, #availableSongs)
		nextSong = availableSongs[randomIndex]

	else
		-- Sequential mode
		nextSong = playlist[self.playlistIndex]

		-- Move to next index
		self.playlistIndex = self.playlistIndex + 1
		if self.playlistIndex > #playlist then
			self.playlistIndex = 1
		end
	end

	-- Mark as played
	if nextSong then
		self.playedSongs[nextSong.id] = true
	end

	return nextSong
end

function MusicPlaylistManager:SetShuffleMode(enabled)
	self.shuffleMode = enabled
	if enabled then
		self.playedSongs = {}
	end
end

function MusicPlaylistManager:ResetPlaylist()
	self.playlistIndex = 1
	self.playedSongs = {}
end

function MusicPlaylistManager:GetPlaylistSize()
	return #MusicModule:GetAllMusic()
end

return MusicPlaylistManager