--!strict
-- ClubNeonArchitecturalAccentRig.server.lua
-- Server-owned discovery/metadata only. Does not create or move map geometry.
-- Tag existing BaseParts by setting ClubNeonAccentZone to:
-- Pillar, Balcony, Railing, DJBooth, or Structure.
local CollectionService = game:GetService("CollectionService")

local TAG = "ClubNeonArchitecturalAccent"
local VALID_ZONES = {
	Pillar = true,
	Balcony = true,
	Railing = true,
	DJBooth = true,
	Structure = true,
}

local function register(instance: Instance)
	if not instance:IsA("BasePart") then return end
	local zone = instance:GetAttribute("ClubNeonAccentZone")
	if typeof(zone) ~= "string" or not VALID_ZONES[zone] then return end
	if not CollectionService:HasTag(instance, TAG) then
		CollectionService:AddTag(instance, TAG)
	end
	if instance:GetAttribute("ClubNeonAccentEnabled") == nil then
		instance:SetAttribute("ClubNeonAccentEnabled", true)
	end
end

for _, instance in ipairs(workspace:GetDescendants()) do
	register(instance)
end
workspace.DescendantAdded:Connect(register)

local counts = {Pillar = 0, Balcony = 0, Railing = 0, DJBooth = 0, Structure = 0}
for _, instance in ipairs(CollectionService:GetTagged(TAG)) do
	local zone = instance:GetAttribute("ClubNeonAccentZone")
	if typeof(zone) == "string" and counts[zone] ~= nil then
		counts[zone] += 1
	end
end
local total = 0
for zone, count in pairs(counts) do
	total += count
	print("[ClubNeon][ArchitecturalAccentRig] " .. zone .. "=" .. count)
end
workspace:SetAttribute("ClubNeonArchitecturalAccentReady", true)
workspace:SetAttribute("ClubNeonArchitecturalAccentFixtureCount", total)
print("[ClubNeon][ArchitecturalAccentRig] Server layout ready; tagged fixtures=" .. total
	.. ". Existing map geometry preserved; no parts created.");
