--!strict
-- CLUB NEON MASTER INSTALLER v0.1.0
-- Separate target installer. Shared Tiki Tide/ClubMusic components are candidates,
-- not assumed dependencies. This release is READ-ONLY PREFLIGHT ONLY.
-- Run in Studio Command Bar with Play/Run stopped. No place export is required.
-- DRY_RUN=true and INSTALL_ENABLED=false are hard safety stops in this release.

local RunService = game:GetService("RunService")
local INSTALLER_VERSION = "0.1.0"
local TARGET_PROJECT = "Club Neon"
local DRY_RUN = true
local INSTALL_ENABLED = false

if RunService:IsRunning() then
	error("[Club Neon Master Installer] Stop Play/Run first. No changes made.")
end
if not DRY_RUN or INSTALL_ENABLED then
	error("[Club Neon Master Installer] This release is read-only. No changes made.")
end

local function log(s: string) print("[Club Neon Master Installer] " .. s) end
local function fullName(x: Instance): string
	local ok, value = pcall(function() return x:GetFullName() end)
	return if ok then value else "<path unavailable>"
end
local function sourceInfo(x: Instance): string
	local ok, source = pcall(function() return (x :: any).Source end)
	if not ok then return "Source=protected/unreadable" end
	if type(source) ~= "string" then return "Source=unavailable" end
	return "SourceLength=" .. tostring(#source)
end
local function classCounts(root: Instance): {[string]: number}
	local counts: {[string]: number} = {}
	for _, item in ipairs(root:GetDescendants()) do
		counts[item.ClassName] = (counts[item.ClassName] or 0) + 1
	end
	return counts
end
local function scriptCounts(root: Instance): (number, number, number)
	local a, b, c = 0, 0, 0
	for _, item in ipairs(root:GetDescendants()) do
		if item:IsA("Script") then a += 1 end
		if item:IsA("LocalScript") then b += 1 end
		if item:IsA("ModuleScript") then c += 1 end
	end
	return a, b, c
end
local function topClasses(root: Instance, limit: number)
	local rows = {}
	for name, count in pairs(classCounts(root)) do
		table.insert(rows, {name=name, count=count})
	end
	table.sort(rows, function(a, b)
		if a.count == b.count then return a.name < b.name end
		return a.count > b.count
	end)
	for i = 1, math.min(limit, #rows) do
		log("    " .. rows[i].name .. "=" .. tostring(rows[i].count))
	end
end
local function findNamed(root: Instance, name: string): {Instance}
	local out = {}
	if root.Name == name then table.insert(out, root) end
	for _, item in ipairs(root:GetDescendants()) do
		if item.Name == name then table.insert(out, item) end
	end
	return out
end
local function printMatches(root: Instance, name: string)
	local matches = findNamed(root, name)
	log("Name scan '" .. name .. "': " .. tostring(#matches) .. " match(es)")
	for _, item in ipairs(matches) do
		log("  " .. fullName(item) .. " [" .. item.ClassName .. "]")
	end
end
local function printCandidate(name: string)
	local matches = findNamed(game, name)
	if #matches == 0 then
		log("  MISSING: " .. name)
		return
	end
	for _, item in ipairs(matches) do
		local enabled = "n/a"
		if item:IsA("Script") or item:IsA("LocalScript") then
			local ok, value = pcall(function() return (item :: any).Enabled end)
			enabled = if ok then tostring(value) else "unreadable"
		end
		log("  FOUND: " .. fullName(item) .. " [" .. item.ClassName .. "] Enabled=" .. enabled .. " " .. sourceInfo(item))
	end
end

log("==================================================")
log("Target=" .. TARGET_PROJECT .. " | Installer v" .. INSTALLER_VERSION)
log("Mode=READ-ONLY PREFLIGHT | DRY_RUN=true | INSTALL_ENABLED=false")
log("No instances will be modified.")
log("PLACE-OWNED SERVICE INVENTORY")
local services = {"Workspace","ReplicatedStorage","ServerScriptService","ServerStorage","StarterPlayer","StarterGui","StarterPack","Lighting","SoundService","Teams","TextChatService"}
local total = 0
for _, serviceName in ipairs(services) do
	local ok, service = pcall(function() return game:GetService(serviceName) end)
	if ok and service then
		local descendants = #service:GetDescendants()
		total += descendants
		local scripts, locals, modules = scriptCounts(service)
		log(serviceName .. ": descendants=" .. descendants .. " Script=" .. scripts .. " LocalScript=" .. locals .. " ModuleScript=" .. modules)
		if descendants > 0 then topClasses(service, 8) end
	end
end
log("Total descendants across listed services (service roots are disjoint): " .. total)

log("SHARED-SYSTEM CANDIDATE SCAN")
local names = {
	"UI_Server_Controller","UI_Renderer","UI_Network","ClubMusicBootstrap",
	"ClubMusic_Global_Service","MusicCoreService","MusicPlaylistService",
	"ClubMusicAudioBackend","ClubMusicAudioCrossfadeManager",
	"ClubMusicAudioQualityProfiles","ClubMusicDJSessionManager","ClubMusicSpatialAudioGraph",
	"ClubMusic_Global_Config_Service","ClubMusic_Global_Diagnostics_Service",
	"ClubMusic_Global_Maintenance_Service","ClubMusic_Global_SafeCall_Service",
	"ClubMusic_Global_Security_Service","ClubMusic_Local_Service_Registry",
	"ClubMusic_Local_Watchdog_Service","ClubMusic_Server_Health_Service",
	"SecurityServer","StaffActions","UtilityBar","TikiTideSettingsService",
	"TikiTideSocialActionsServer","MusicGlobalPlaybackAuthority"
}
for _, name in ipairs(names) do printCandidate(name) end

log("THIRD-PARTY / LEGACY PACKAGE CHECKS")
for _, name in ipairs({"Kohl's Admin","MainModule","Config","Addons","MusicGlobalPlaybackAuthority"}) do
	printMatches(game, name)
end

log("PLACEHOLDER SCRIPT CHECK")
for _, item in ipairs(game:GetDescendants()) do
	if item:IsA("LuaSourceContainer") then
		local ok, source = pcall(function() return (item :: any).Source end)
		if ok and type(source) == "string" and string.find(source, "Hello world!", 1, true) then
			log("  Placeholder match: " .. fullName(item) .. " [" .. item.ClassName .. "] " .. sourceInfo(item))
		end
	end
end

log("INTERACTION ANIMATION INVENTORY")
local interactionAnims = game:GetService("ReplicatedStorage"):FindFirstChild("InteractionAnims")
if interactionAnims then
	log("Found: " .. fullName(interactionAnims))
	for _, branch in ipairs(interactionAnims:GetChildren()) do
		local keyframes, poses, anims = 0, 0, 0
		for _, item in ipairs(branch:GetDescendants()) do
			if item:IsA("Keyframe") then keyframes += 1 end
			if item:IsA("Pose") then poses += 1 end
			if item:IsA("Animation") or item:IsA("KeyframeSequence") then anims += 1 end
		end
		log("  " .. branch.Name .. " [" .. branch.ClassName .. "] descendants=" .. #branch:GetDescendants()
			.. " Keyframes=" .. keyframes .. " Poses=" .. poses .. " Animation/KeyframeSequence=" .. anims)
	end
else
	log("ReplicatedStorage.InteractionAnims not found.")
end

log("INSTALL PLAN / SAFETY")
log("  No remote sources fetched; no scripts/modules installed.")
log("  No folders, remotes, values, or attributes created.")
log("  No instances moved, replaced, archived, or deleted.")
log("  Tiki Tide playback-sync policy is not automatically applied to Club Neon.")
log("  Club Neon queue/sync policy must be explicitly defined in its own manifest.")
log("  Third-party packages and map assets remain untouched.")
log("  Next: map approved shared modules to verified Club Neon paths and define target-specific settings.")
log("READ-ONLY PREFLIGHT COMPLETE. No changes made.")
