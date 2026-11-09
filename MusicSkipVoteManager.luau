-- ====================================
-- MUSIC SKIP VOTE MANAGER
-- Location: ServerStorage/Modules/MusicSystem/MusicSkipVoteManager
-- ====================================

local Players = game:GetService("Players")

local MusicSkipVoteManager = {}
MusicSkipVoteManager.__index = MusicSkipVoteManager

function MusicSkipVoteManager.new(config, roleSystem)
	local self = setmetatable({}, MusicSkipVoteManager)

	self.config = config
	self.roleSystem = roleSystem
	self.skipVote = {
		active = false,
		initiator = nil,
		songData = nil,
		voters = {},
		yesVotes = 0,
		noVotes = 0,
		startTime = 0
	}
	self.skipVoteRateLimit = {}

	return self
end

-- ====================================
-- ELIGIBLE VOTERS
-- ====================================

function MusicSkipVoteManager:GetEligibleVoters()
	local voters = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local role = self.roleSystem:GetPlayerRole(player)
		if self.roleSystem.Config.RoleHierarchy[role] >= self.roleSystem.Config.RoleHierarchy.VIP then
			table.insert(voters, player)
		end
	end
	return voters
end

-- ====================================
-- RATE LIMITING
-- ====================================

function MusicSkipVoteManager:CheckRateLimit(player)
	local userId = player.UserId
	local lastTime = self.skipVoteRateLimit[userId]

	if lastTime then
		local elapsed = tick() - lastTime
		if elapsed < self.config.SKIP_VOTE_COOLDOWN then
			return false
		end
	end

	self.skipVoteRateLimit[userId] = tick()
	return true
end

-- ====================================
-- VOTE MANAGEMENT
-- ====================================

function MusicSkipVoteManager:IsActive()
	return self.skipVote.active
end

function MusicSkipVoteManager:GetVoteState()
	return {
		active = self.skipVote.active,
		yesVotes = self.skipVote.yesVotes,
		noVotes = self.skipVote.noVotes,
		initiator = self.skipVote.initiator,
		songData = self.skipVote.songData
	}
end

function MusicSkipVoteManager:StartVote(initiatorPlayer, songData, dispatcher)
	if self.skipVote.active then
		return false, "Vote skip sudah aktif!"
	end

	local eligible = self:GetEligibleVoters()
	if #eligible < 2 then
		return false, "Tidak cukup player untuk memulai vote."
	end

	self.skipVote = {
		active = true,
		initiator = initiatorPlayer.DisplayName,
		songData = songData,
		voters = {},
		yesVotes = 0,
		noVotes = 0,
		startTime = tick()
	}

	-- Notify all eligible voters
	for _, player in ipairs(eligible) do
		dispatcher:SendToClient(player, "SKIP_VOTE_START", {
			initiator = initiatorPlayer.DisplayName,
			songTitle = songData.judul,
			totalVoters = #eligible
		})
	end

	-- Schedule auto-end
	task.delay(self.config.SKIP_VOTE_DURATION, function()
		if self.skipVote.active and self.skipVote.startTime == self.skipVote.startTime then
			self:EndVote(dispatcher, false)
		end
	end)

	return true, nil
end

function MusicSkipVoteManager:CastVote(player, voteType, dispatcher)
	if not self.skipVote.active then
		return false, "Tidak ada vote yang aktif!"
	end

	local userId = player.UserId

	if self.skipVote.voters[userId] then
		return false, "Anda sudah voting!"
	end

	self.skipVote.voters[userId] = voteType

	if voteType == "yes" then
		self.skipVote.yesVotes = self.skipVote.yesVotes + 1
	else
		self.skipVote.noVotes = self.skipVote.noVotes + 1
	end

	-- Update all eligible voters
	local eligible = self:GetEligibleVoters()
	for _, p in ipairs(Players:GetPlayers()) do
		local role = self.roleSystem:GetPlayerRole(p)
		if self.roleSystem.Config.RoleHierarchy[role] >= self.roleSystem.Config.RoleHierarchy.VIP then
			dispatcher:SendToClient(p, "SKIP_VOTE_UPDATE", {
				yesVotes = self.skipVote.yesVotes,
				noVotes = self.skipVote.noVotes,
				totalVoters = #eligible
			})
		end
	end

	-- Check if vote passed
	local requiredVotes = math.floor(#eligible / 2) + 1
	if self.skipVote.yesVotes >= requiredVotes then
		return true, true -- Vote passed
	end

	return true, false -- Vote registered but not passed
end

function MusicSkipVoteManager:EndVote(dispatcher, forced)
	if not self.skipVote.active then return false end

	local eligible = #self:GetEligibleVoters()
	local requiredVotes = math.floor(eligible / 2) + 1
	local passed = self.skipVote.yesVotes >= requiredVotes

	self.skipVote = {
		active = false,
		initiator = nil,
		songData = nil,
		voters = {},
		yesVotes = 0,
		noVotes = 0,
		startTime = 0
	}

	dispatcher:SendToAll("SKIP_VOTE_END", {
		result = passed and "passed" or "failed"
	})

	return passed
end

function MusicSkipVoteManager:UpdateVoteOnPlayerLeave(userId, dispatcher)
	if not self.skipVote.active then return end

	if self.skipVote.voters[userId] then
		if self.skipVote.voters[userId] == "yes" then
			self.skipVote.yesVotes = math.max(0, self.skipVote.yesVotes - 1)
		else
			self.skipVote.noVotes = math.max(0, self.skipVote.noVotes - 1)
		end
		self.skipVote.voters[userId] = nil

		-- Update all voters
		local eligible = self:GetEligibleVoters()
		for _, p in ipairs(Players:GetPlayers()) do
			local role = self.roleSystem:GetPlayerRole(p)
			if self.roleSystem.Config.RoleHierarchy[role] >= self.roleSystem.Config.RoleHierarchy.VIP then
				dispatcher:SendToClient(p, "SKIP_VOTE_UPDATE", {
					yesVotes = self.skipVote.yesVotes,
					noVotes = self.skipVote.noVotes,
					totalVoters = #eligible
				})
			end
		end
	end
end

return MusicSkipVoteManager