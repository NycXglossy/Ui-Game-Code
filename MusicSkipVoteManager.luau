--!strict
-- ClubMusic skip-vote facade.
-- Vote eligibility, cooldowns, vote storage, thresholds, and track transitions
-- remain exclusively owned by UI_Server_Controller.

local MusicSkipVoteManager = {}
MusicSkipVoteManager.__index = MusicSkipVoteManager

export type Context = {
	GetVoteState: () -> any,
	CastVote: (Player) -> (boolean, string?),
	RemoveVoter: ((number) -> ())?,
}

function MusicSkipVoteManager.new(context: Context)
	assert(typeof(context) == "table", "Skip-vote manager requires an injected controller context.")
	assert(typeof(context.GetVoteState) == "function", "Skip-vote context requires GetVoteState.")
	assert(typeof(context.CastVote) == "function", "Skip-vote context requires CastVote.")
	return setmetatable({ context = context, destroyed = false }, MusicSkipVoteManager)
end

function MusicSkipVoteManager:IsActive(): boolean
	if self.destroyed then return false end
	local ok, state = pcall(self.context.GetVoteState)
	return ok and typeof(state) == "table" and state.active == true
end

function MusicSkipVoteManager:GetVoteState()
	if self.destroyed then return nil end
	local ok, state = pcall(self.context.GetVoteState)
	if not ok then
		warn("[ClubMusic Skip Vote Adapter] Vote snapshot failed: " .. tostring(state))
		return nil
	end
	return state
end

function MusicSkipVoteManager:CastVote(player: Player)
	if self.destroyed then return false, "Skip-vote adapter has been cleaned up." end
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent == nil then
		return false, "A connected player is required."
	end
	local ok, accepted, message = pcall(self.context.CastVote, player)
	if not ok then
		warn("[ClubMusic Skip Vote Adapter] Controller vote callback failed: " .. tostring(accepted))
		return false, "The controller could not process that vote."
	end
	return accepted == true, if typeof(message) == "string" then message else nil
end

function MusicSkipVoteManager:UpdateVoteOnPlayerLeave(userId: number)
	if self.destroyed or typeof(userId) ~= "number" or userId % 1 ~= 0 then return end
	if typeof(self.context.RemoveVoter) == "function" then
		local ok, err = pcall(self.context.RemoveVoter, userId)
		if not ok then warn("[ClubMusic Skip Vote Adapter] Voter cleanup failed: " .. tostring(err)) end
	end
end

function MusicSkipVoteManager:Cleanup()
	-- Never ends or resets the controller-owned vote.
	self.destroyed = true
	self.context = nil
end

return MusicSkipVoteManager
