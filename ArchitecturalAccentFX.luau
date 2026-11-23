--!strict
-- ArchitecturalAccentFX: client-local architectural LED accent choreography.
-- Server owns the tagged fixture layout; clients animate local appearance only.
-- Set ClubNeonAccentZone on existing BaseParts; see CLUB_NEON_ARCHITECTURAL_ACCENTS.md.
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ClubAudioSync = require(ReplicatedStorage:WaitForChild("ClubAudioSync"))

local TAG = "ClubNeonArchitecturalAccent"
local UPDATE_INTERVAL = 1 / 12
local PALETTE = {
	Color3.fromRGB(0, 220, 255),
	Color3.fromRGB(180, 65, 255),
	Color3.fromRGB(255, 55, 185),
	Color3.fromRGB(30, 255, 170),
}

local ZONE_PHASE = {
	Pillar = 0,
	Balcony = 0.18,
	Railing = 0.36,
	DJBooth = 0.54,
	Structure = 0.72,
}
local fixtures = {}
local elapsed = 0
local lastPhrase = -1

local function collect()
	table.clear(fixtures)
	for _, part in ipairs(CollectionService:GetTagged(TAG)) do
		if part:IsA("BasePart") and part:GetAttribute("ClubNeonAccentEnabled") ~= false then
			local zone = part:GetAttribute("ClubNeonAccentZone")
			if typeof(zone) == "string" and ZONE_PHASE[zone] ~= nil then
				table.insert(fixtures, {
					part = part,
					zone = zone,
					phase = ZONE_PHASE[zone],
					seed = (part.Position.X * 0.013 + part.Position.Z * 0.017) % 1,
					base = part:GetAttribute("ClubNeonAccentBaseColor"),
				})
			end
		end
	end
end
collect()
CollectionService:GetInstanceAddedSignal(TAG):Connect(collect)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(collect)

local function samplePalette(position)
	local scaled = (position % 1) * #PALETTE
	local index = math.floor(scaled) + 1
	local nextIndex = (index % #PALETTE) + 1
	return PALETTE[index]:Lerp(PALETTE[nextIndex], scaled - math.floor(scaled))
end

RunService.Heartbeat:Connect(function(dt)
	elapsed += dt
	if elapsed < UPDATE_INTERVAL then return end
	elapsed = 0
	local beat = ClubAudioSync.getBeatState()
	local beatCount = beat.beatCount or 0
	local phrase = math.floor(beatCount / 16)
	local phraseChanged = phrase ~= lastPhrase
	lastPhrase = phrase

	local phase = (beatCount * 0.045 + (beat.beatPhase or 0) * 0.035) % 1
	local pulse = beat.playing and math.exp(-(beat.beatPhase or 0) * 5) or 0
	for _, fixture in ipairs(fixtures) do
		local part = fixture.part
		if not part.Parent then continue end
		local zoneOffset = fixture.phase
		local drift = phase + zoneOffset + fixture.seed * 0.12
		local color = samplePalette(drift)
		-- Gentle phrase accent; never force white or full-brightness flashing.
		if phraseChanged and fixture.zone == "DJBooth" then
			color = color:Lerp(Color3.fromRGB(255, 235, 255), 0.12)
		elseif pulse > 0.7 and fixture.zone == "Pillar" then
			color = color:Lerp(Color3.new(1, 1, 1), 0.035)
		end
		if typeof(fixture.base) == "Color3" then
			color = fixture.base:Lerp(color, 0.82)
		end
		part.Color = color
	end
end)
