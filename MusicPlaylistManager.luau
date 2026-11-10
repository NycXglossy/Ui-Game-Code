--!strict
-- ClubMusic playlist facade.
-- Persistent playlist CRUD is delegated to MusicPlaylistService.
-- Active rotation and its cursor remain owned by UI_Server_Controller / global queue.

local MusicPlaylistManager = {}
MusicPlaylistManager.__index = MusicPlaylistManager

export type Context = {
	Service: any,
	GetRotationState: (() -> any)?,
	StartRotation: ((Player, any) -> (boolean, string?))?,
	StopRotation: ((Player) -> (boolean, string?))?,
	SelectNextTrack: (() -> any)?,
}

local function invoke(callback: any, ...)
	if typeof(callback) ~= "function" then
		return false, "Playlist rotation is owned by UI_Server_Controller."
	end
	local ok, result, message = pcall(callback, ...)
	if not ok then
		warn("[ClubMusic Playlist Adapter] Controller callback failed: " .. tostring(result))
		return false, "The controller playlist operation failed."
	end
	return result == true, if typeof(message) == "string" then message else nil
end

function MusicPlaylistManager.new(context: Context)
	assert(typeof(context) == "table", "Playlist manager requires an injected context.")
	assert(typeof(context.Service) == "table", "Playlist manager requires MusicPlaylistService.")
	for _, method in ipairs({"GetAll", "Create", "Delete", "AddTrack", "RemoveTrack", "MoveTrack"}) do
		assert(typeof(context.Service[method]) == "function", "MusicPlaylistService is missing " .. method .. ".")
	end
	return setmetatable({ context = context, destroyed = false }, MusicPlaylistManager)
end

function MusicPlaylistManager:GetAll()
	if self.destroyed then return {} end
	return self.context.Service:GetAll()
end

function MusicPlaylistManager:GetPlaylistSize(): number
	local playlists = self:GetAll()
	local count = 0
	for _, playlist in ipairs(playlists) do
		count += #(typeof(playlist.trackIds) == "table" and playlist.trackIds or {})
	end
	return count
end

function MusicPlaylistManager:Create(name: any)
	if self.destroyed then return false, "Playlist adapter has been cleaned up." end
	return self.context.Service:Create(name)
end

function MusicPlaylistManager:Delete(id: any)
	if self.destroyed then return false, "Playlist adapter has been cleaned up." end
	return self.context.Service:Delete(id)
end

function MusicPlaylistManager:AddTrack(id: any, trackId: any)
	if self.destroyed then return false, "Playlist adapter has been cleaned up." end
	return self.context.Service:AddTrack(id, trackId)
end

function MusicPlaylistManager:RemoveTrack(id: any, trackId: any)
	if self.destroyed then return false, "Playlist adapter has been cleaned up." end
	return self.context.Service:RemoveTrack(id, trackId)
end

function MusicPlaylistManager:MoveTrack(id: any, trackId: any, position: any)
	if self.destroyed then return false, "Playlist adapter has been cleaned up." end
	return self.context.Service:MoveTrack(id, trackId, position)
end

function MusicPlaylistManager:GetRotationState()
	if self.destroyed or typeof(self.context.GetRotationState) ~= "function" then return nil end
	local ok, state = pcall(self.context.GetRotationState)
	if not ok then
		warn("[ClubMusic Playlist Adapter] Rotation snapshot failed: " .. tostring(state))
		return nil
	end
	return state
end

function MusicPlaylistManager:StartRotation(player: Player, playlistId: any)
	if self.destroyed then return false, "Playlist adapter has been cleaned up." end
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent == nil then
		return false, "A connected player is required."
	end
	return invoke(self.context.StartRotation, player, playlistId)
end

function MusicPlaylistManager:StopRotation(player: Player)
	if self.destroyed then return false, "Playlist adapter has been cleaned up." end
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent == nil then
		return false, "A connected player is required."
	end
	return invoke(self.context.StopRotation, player)
end

function MusicPlaylistManager:GetNextSong()
	if self.destroyed or typeof(self.context.SelectNextTrack) ~= "function" then return nil end
	local ok, track = pcall(self.context.SelectNextTrack)
	if not ok then
		warn("[ClubMusic Playlist Adapter] Track selection failed: " .. tostring(track))
		return nil
	end
	return track
end

function MusicPlaylistManager:Cleanup()
	-- Does not clear service data, active rotation, or controller-owned cursor.
	self.destroyed = true
	self.context = nil
end

return MusicPlaylistManager
