--!strict
-- ServerStorage/ClubNeon_NativeBanHistory.lua
-- Reads Roblox-native ban history; this is separate from Club Neon's moderation store.

local NativeBanHistory = {}

function NativeBanHistory.create(Players: Players, RunService: RunService)
	return function(player: Player)
		if RunService:IsStudio() then return end
		local ok, banned, displayReason = pcall(function()
			local pages = Players:GetBanHistoryAsync(player.UserId)
			local currentPage = pages:GetCurrentPage()
			local latestRecord = nil
			local latestTimestamp = -math.huge
			for _, record in ipairs(currentPage) do
				if typeof(record) == "table" and typeof(record.StartTime) == "string"
					and typeof(record.Ban) == "boolean" then
					local parsed = DateTime.fromIsoDate(record.StartTime)
					local timestamp = parsed.UnixTimestamp
					if timestamp > latestTimestamp then
						latestTimestamp = timestamp
						latestRecord = record
					end
				end
			end
			if not latestRecord or latestRecord.Ban ~= true then return false, nil end
			local duration = latestRecord.Duration
			if typeof(duration) ~= "number" then error("Ban history returned an invalid duration") end
			if duration == -1 then
				return true, latestRecord.DisplayReason
			end
			if duration <= 0 then return false, nil end
			local expiresAt = latestTimestamp + duration
			return expiresAt > os.time(), latestRecord.DisplayReason
		end)
		if not ok then
			warn("[Club Neon][NativeBanLookup] Roblox ban history unavailable for UserId "
				.. tostring(player.UserId) .. ": " .. tostring(banned))
			return
		end
		if banned == true and player.Parent == Players then
			local reason = if typeof(displayReason) == "string" and #displayReason > 0
				then displayReason else "You are banned from this experience."
			player:Kick(reason)
		end
	end
end

return NativeBanHistory
