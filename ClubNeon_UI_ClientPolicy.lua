--!strict
-- Client-side action allowlists, pacing hints, and bounded state sanitization.
-- The server independently validates all privileged actions and payloads.
local ALLOWED_ACTIONS: {[string]: boolean} = {
	ReloadSong = true, ToggleFavorite = true, RequestTrack = true, VoteSkip = true,
	RequestAudioAsset = true, CatalogAddAudio = true, CatalogRemoveTrack = true, DJSkip = true, DJToggleLock = true,
	DJMoveUp = true, DJRemove = true, DJPause = true, DJRestart = true, ModSetPassTier = true,
	ClaimDailyReward = true, EquipTitleTag = true, BuyTitleTag = true,
	SaveTitleSlot = true, SetTitleVisible = true, SelectTitleSlot = true,
	ClearTitleSlot = true,
	-- Playlist and DJ playlist actions are server-validated in UI_Server_Controller.
	PlaylistCreate = true, PlaylistDelete = true, PlaylistAddTrack = true,
	PlaylistRemoveTrack = true, PlaylistMoveTrack = true,
	DJPlayPlaylist = true, DJStopPlaylist = true,
	-- Owner/Co-Owner playback-sync mode toggle; server rechecks SecurityCore permissions.
	DJToggleGlobalPlaybackSync = true,
}
local ALLOWED_NETWORK_METHODS: {[string]: boolean} = {
	RequestTrack = true, ToggleFavorite = true, VoteSkip = true,
	DJSkip = true, DJMoveUp = true, DJRemove = true, DJPause = true, DJRestart = true, ClaimDailyReward = true,
	EquipTitleTag = true, BuyTitleTag = true, RequestAudioAsset = true, SaveTitleSlot = true,
	SaveCustomTitle = true,
	-- Wrappers that UI_Network exposes; act() prefers these over raw Network.Send.
	ReloadSong = true, DJToggleLock = true, DJToggleGlobalPlaybackSync = true,
	ModSetPassTier = true,
	SelectTitleSlot = true, ClearTitleSlot = true, SetTitleVisible = true,
}
local ACTION_MIN_INTERVAL: {[string]: number} = {
	RequestTrack = 0.35, RequestAudioAsset = 1.0, CatalogAddAudio = 10.0, CatalogRemoveTrack = 2.0, ReloadSong = 3.0,
	SaveTitleSlot = 0.35, ClaimDailyReward = 0.35,
}

local function sanitizeStateValue(value: any, depth: number, seen: {[any]: boolean}): any
	local kind = typeof(value)
	if kind == "string" then
		return string.sub(value, 1, 500)
	elseif kind == "number" then
		if value ~= value or value == math.huge or value == -math.huge then return nil end
		return math.clamp(value, -1e9, 1e9)
	elseif kind == "boolean" then
		return value
	elseif kind ~= "table" or depth >= 5 or seen[value] then
		return nil
	end
	seen[value] = true
	local copy = {}
	local count = 0
	for key, child in pairs(value) do
		count += 1
		if count > 500 then break end
		if typeof(key) == "string" then
			copy[string.sub(key, 1, 80)] = sanitizeStateValue(child, depth + 1, seen)
		elseif typeof(key) == "number" and key == math.floor(key) and key >= 1 and key <= 10000 then
			copy[key] = sanitizeStateValue(child, depth + 1, seen)
		end
	end
	seen[value] = nil
	return copy
end

return {
	ALLOWED_ACTIONS = ALLOWED_ACTIONS,
	ALLOWED_NETWORK_METHODS = ALLOWED_NETWORK_METHODS,
	ACTION_MIN_INTERVAL = ACTION_MIN_INTERVAL,
	sanitizeStateValue = sanitizeStateValue,
}
