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

-- One signal repeated three times is capped and cannot create a review.
for _ = 1, 3 do
	expect(service:Record("movement_limit_exceeded", 900001, "CharacterPhysicsGuard", "Critical") == true,
		"known movement signal accepted")
end
expect(service.buckets["900001"].score == 8, "category/source contribution cap is enforced")
expect(service.buckets["900001"].capped == true, "capped contribution is explained")
expect(#service.incidents == 0, "repeated one-code signal does not create a review")

-- Different codes from one category still do not satisfy category diversity.
service:Record("unverified_movement_change", 900001, "CharacterPhysicsGuard", "Warning")
expect(#service.incidents == 0, "same-category evidence does not create a review")

-- Sustained extreme assembly velocity and rotation are registered Movement signals.
expect(service:Record("suspicious_physics_velocity", 900006, "CharacterPhysicsGuard", "Warning") == true,
	"extreme assembly velocity signal is registered")
expect(service:Record("suspicious_physics_rotation", 900006, "CharacterPhysicsGuard", "Warning") == true,
	"extreme assembly rotation signal is registered")
expect(service.buckets["900006"].score == 4, "physics signals receive bounded Movement weight")
expect(service.buckets["900006"].categories.Movement == true, "physics signals use Movement category")
expect(#service.incidents == 0, "physics signals alone do not satisfy category diversity")

-- Unknown strings containing alarming words are zero-weight and cannot classify by substring.
service:Record("movement_exploit_critical", 900002, "UnregisteredAdapter", "Critical")
expect(service.buckets["900002"].score == 0, "unknown code receives no score")
expect(service:GetStatus().unknownSignals == 1, "unknown code is counted")

-- Invalid severity is normalized to Info rather than granting a bonus.
service:Record("movement_limit_exceeded", 900005, "PhysicsAdapter", "Critical-ish")
expect(service.buckets["900005"].score == 2, "invalid severity receives no Critical bonus")

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

-- Cohort join capacity is bounded.
for userId = 920001, 920140 do service:JoinUserId(userId) end
expect(service:GetStatus().cohortWindowJoins <= 128, "cohort joiner cap is enforced")
expect(service:GetStatus().subjectEvictions > 0, "cohort capacity eviction is counted")

-- Rolling cohort evidence expires.
clock += 61
service:Record("movement_limit_exceeded", 910001, "PhysicsAdapter", "Warning")
expect(service:GetStatus().cohortWindowJoins == 0, "join cohort expires after its window")
expect(service:GetStatus().cohortSignaledPlayers == 0, "cohort evidence expires with joins")

-- Subject window expiry and bounded tracked-subject capacity.
clock += 601
service:Record("movement_limit_exceeded", 930001, "PhysicsAdapter", "Warning")
expect(service.buckets["900001"] == nil, "expired subject bucket is pruned")
for userId = 940001, 940270 do service:Record("movement_limit_exceeded", userId, "PhysicsAdapter", "Warning") end
expect(service:GetStatus().trackedSubjects <= 256, "subject bucket cap is enforced")
expect(service:GetStatus().subjectEvictions > 0, "subject eviction counter is nonzero")

-- Unauthorized queries are rejected; Stop disconnects and clears retained state.
local allowed = service:Query(nil, nil, 10)
expect(allowed == false, "non-Player query actor rejected")
service:Stop()
expect(service.started == false and next(service.buckets) == nil and #service.raidReviews == 0,
	"Stop clears local state")

return true
