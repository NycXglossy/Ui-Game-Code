--!strict
-- Manual Studio server test for SecurityThreatIntelligence.
-- Run from a server-side test harness after placing this ModuleScript beside
-- SecurityThreatIntelligence in ClubMusicSecurityCore. No enforcement is tested
-- because this service intentionally has no enforcement API.

local Service = require(script.Parent:WaitForChild("SecurityThreatIntelligence"))

local function expect(condition: boolean, message: string)
	if not condition then error("SecurityThreatIntelligence test failed: " .. message, 2) end
end

local clock = 100
local service = Service.new({
	authorize = function() return false end,
	now = function() return clock end,
})
expect(service:Start() == true, "service starts")

-- One signal repeated three times must not create a review.
for _ = 1, 3 do
	expect(service:Record("movement_limit_exceeded", 900001, "CharacterPhysicsGuard", "Critical") == true,
		"known movement signal accepted")
end
expect(#service.incidents == 0, "repeated one-code signal does not create a review")

-- Different codes from one category still do not satisfy category diversity.
service:Record("unverified_movement_change", 900001, "CharacterPhysicsGuard", "Warning")
expect(#service.incidents == 0, "same-category evidence does not create a review")

-- Unknown strings containing alarming words are zero-weight and cannot classify by substring.
local beforeScore = service.buckets["900002"]
service:Record("movement_exploit_critical", 900002, "UnregisteredAdapter", "Critical")
expect(service.buckets["900002"].score == 0, "unknown code receives no score")
expect(service:GetStatus().unknownSignals == 1, "unknown code is counted")

-- Two exact categories/codes cross Medium; one event ID forwarded twice is deduplicated.
service:Record("movement_limit_exceeded", 900003, "PhysicsAdapter", "Warning", "dedupe-1")
expect(service:Record("audio_asset_invalid_id", 900003, "AudioAdapter", "Warning", "dedupe-1") == false,
	"duplicate event ID rejected")
expect(service:GetStatus().duplicateEventIds == 1, "duplicate event counted")
expect(#service.incidents == 0, "deduplicated event cannot add a second category")
service:Record("audio_asset_invalid_id", 900003, "AudioAdapter", "Warning", "dedupe-2")
expect(#service.incidents == 1 and service.incidents[1].confidence == "Medium",
	"two independent categories create Medium review")

-- High confidence requires three categories, three codes, three sources, and score >= 8.
service:Record("movement_limit_exceeded", 900004, "PhysicsAdapter", "Critical")
service:Record("audio_asset_invalid_id", 900004, "AudioAdapter", "Critical")
service:Record("honeypot_admin_privilege_remote", 900004, "HoneypotManager", "Critical")
local high = service.incidents[#service.incidents]
expect(high and high.confidence == "High", "diverse evidence can create High review")
expect(high.sourceCount == 3, "source diversity is retained")

-- Join burst alone is not a raid. Eight distinct joins create no cohort review.
for userId = 910001, 910008 do service:JoinUserId(userId) end
expect(#service.raidReviews == 0, "join burst alone does not create raid review")

-- Corroboration across distinct joining players creates a server-wide advisory review.
service:Record("movement_limit_exceeded", 910001, "PhysicsAdapter", "Warning")
service:Record("audio_asset_invalid_id", 910002, "AudioAdapter", "Warning")
service:Record("avatar_accessory_excessive_parts", 910003, "AvatarAdapter", "Warning")
expect(#service.raidReviews == 1, "join burst plus three distinct signaled players creates cohort review")
expect(service.raidReviews[1].confidence == "Medium", "initial cohort threshold is Medium")
expect(service.raidReviews[1].automaticEnforcement == false, "cohort review is advisory only")

-- Rolling cohort evidence expires; session/event state remains bounded.
clock += 61
service:Record("movement_limit_exceeded", 910001, "PhysicsAdapter", "Warning")
expect(service:GetStatus().cohortWindowJoins == 0, "join cohort expires after its window")
expect(service:GetStatus().cohortSignaledPlayers == 0, "cohort evidence expires with joins")

-- Unauthorized queries are rejected; Stop disconnects and clears retained state.
local allowed = service:Query(nil, nil, 10)
expect(allowed == false, "non-Player query actor rejected")
service:Stop()
expect(service.started == false and next(service.buckets) == nil and #service.raidReviews == 0,
	"Stop clears local state")

return true
