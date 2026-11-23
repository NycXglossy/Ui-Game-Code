--!strict
-- ServerStorage/ClubNeon_SkipVoting.lua
-- Server-local skip-vote counting and threshold evaluation.

local SkipVoting = {}

function SkipVoting.initialize(deps: {[string]: any})
	local Players: Players = deps.Players
	local CONFIG = deps.CONFIG
	local skipVotes: {[number]: boolean} = deps.skipVotes
	local ControllerFunctions = deps.ControllerFunctions

	ControllerFunctions.skipStatus = function(player: Player?): (number, number, boolean)
		local list = Players:GetPlayers()
		local count = #list
		local votes = 0
		for _, p in ipairs(list) do
			if skipVotes[p.UserId] then votes += 1 end
		end
		local needed = math.min(count, math.max(CONFIG.SkipVoteMin, math.ceil(count * CONFIG.SkipVoteRatio)))
		needed = math.max(needed, 1)
		local voted = if player then skipVotes[player.UserId] == true else false
		return votes, needed, voted
	end

	ControllerFunctions.checkSkipVotes = function(): boolean
		local votes, needed = ControllerFunctions.skipStatus(nil)
		if votes > 0 and votes >= needed then
			ControllerFunctions.advance()
			return true
		end
		return false
	end
end

return SkipVoting
