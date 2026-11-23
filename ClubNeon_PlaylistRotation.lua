-- Club Neon playlist rotation service.
-- Owns playlist selection/cursor lifecycle while the controller retains the
-- authoritative queue, catalog, playback state, and Auto DJ refill.
return function(context)
	local function nextPlaylistTrack()
		local activePlaylistId = context.getActivePlaylistId()
		local tracks = context.getActivePlaylistTracks()
		if not activePlaylistId or #tracks == 0 then return nil end
		local cursor = context.getActivePlaylistCursor()
		for _ = 1, #tracks do
			if cursor > #tracks then cursor = 1 end
			local track = tracks[cursor]
			cursor += 1
			context.setActivePlaylistCursor(cursor)
			if context.isPlayableTrack(context.TRACK_BY_ID[track.id]) and not context.ControllerFunctions.isTrackBlocked(track.id) then
				return context.TRACK_BY_ID[track.id]
			end
		end
		return nil
	end

	local function reloadActivePlaylist(): boolean
		local activePlaylistId = context.getActivePlaylistId()
		if not activePlaylistId then return false end
		local activePlaylistTracks = context.getActivePlaylistTracks()
		for _, playlist in ipairs(context.MusicPlaylistService:GetAll()) do
			if playlist.id == activePlaylistId then
				local validTracks = {}
				for _, trackId in ipairs(playlist.trackIds) do
					local track = context.TRACK_BY_ID[trackId]
					if track then table.insert(validTracks, track) end
				end
				if #validTracks == 0 then
					context.setActivePlaylist(nil, "", {}, 1)
					return false
				end
				local nowPlaying = context.nowPlaying
				local nextCursor = 1
				if nowPlaying.source == "playlist" then
					local currentIndex = nil
					for index, track in ipairs(validTracks) do
						if track.id == nowPlaying.trackId then currentIndex = index; break end
					end
					if currentIndex then
						nextCursor = if currentIndex >= #validTracks then 1 else currentIndex + 1
					else
						local oldIndex = nil
						for index, track in ipairs(activePlaylistTracks) do
							if track.id == nowPlaying.trackId then oldIndex = index; break end
						end
						if oldIndex then
							local foundNext = false
						for offset = 1, #activePlaylistTracks do
							if not foundNext then
								local oldTrack = activePlaylistTracks[((oldIndex + offset - 1) % #activePlaylistTracks) + 1]
								for index, track in ipairs(validTracks) do
									if track.id == oldTrack.id then nextCursor = index; foundNext = true; break end
								end
							end
						end
					end
					end
				end
				context.setActivePlaylist(playlist.id, playlist.name, validTracks, nextCursor)
				return true
			end
		end
		context.setActivePlaylist(nil, "", {}, 1)
		return false
	end

	local function startPlaylistRotation(player: Player, playlistId: any): boolean
		if typeof(playlistId) ~= "string" or #playlistId == 0 or #playlistId > 64 then
			context.notify(player, "Choose a valid playlist.", "warn")
			return false
		end
		local found = nil
		for _, playlist in ipairs(context.MusicPlaylistService:GetAll()) do
			if playlist.id == playlistId then found = playlist; break end
		end
		if not found then
			context.notify(player, "Playlist not found. Refresh the playlist list and try again.", "warn")
			return false
		end
		local validTracks = {}
		for _, trackId in ipairs(found.trackIds) do
			local track = context.TRACK_BY_ID[trackId]
			if track then table.insert(validTracks, track) end
		end
		if #validTracks == 0 then
			context.notify(player, "This playlist has no tracks available in the current catalog.", "warn")
			return false
		end
		context.setActivePlaylist(found.id, found.name, validTracks, 1)
		context.ControllerFunctions.clearAutomaticQueue()
		context.ControllerFunctions.topUpAuto()
		context.notify(player, "Playlist rotation enabled: " .. found.name .. ". The current track will finish first.", "ok")
		return true
	end

	local function stopPlaylistRotation(player: Player?): boolean
		local activePlaylistId = context.getActivePlaylistId()
		if not activePlaylistId then
			if player then context.notify(player, "No playlist rotation is active.", "info") end
			return false
		end
		local stoppedName = context.getActivePlaylistName()
		context.setActivePlaylist(nil, "", {}, 1)
		context.ControllerFunctions.clearAutomaticQueue()
		context.ControllerFunctions.topUpAuto()
		if player then context.notify(player, "Playlist rotation stopped: " .. stoppedName .. ".", "ok") end
		return true
	end

	return {
		nextPlaylistTrack = nextPlaylistTrack,
		reloadActivePlaylist = reloadActivePlaylist,
		startPlaylistRotation = startPlaylistRotation,
		stopPlaylistRotation = stopPlaylistRotation,
	}
end
