--!strict
-- ClubMusic security smoke test (Studio only).
-- Install temporarily as a LocalScript under StarterPlayerScripts in a
-- separate test copy. Remove it after testing. This script sends malformed
-- requests only; it does not invoke valid queue, playback, purchase, or admin
-- mutations.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

if not RunService:IsStudio() then
	warn("[ClubMusic Security Test] Refusing to run outside Studio.")
	return
end

local remotes = ReplicatedStorage:WaitForChild("ClubMusicRemotes", 30)
if not remotes then
	warn("[ClubMusic Security Test] ClubMusicRemotes was not found.")
	return
end

local actionRemote = remotes:WaitForChild("RequestAction", 10)
local stateFunction = remotes:WaitForChild("GetState", 10)
local catalogFunction = remotes:WaitForChild("GetMusicCatalog", 10)
local playlistFunction = remotes:WaitForChild("GetMusicPlaylists", 10)

if not actionRemote or not stateFunction or not catalogFunction or not playlistFunction then
	warn("[ClubMusic Security Test] One or more remotes are missing; test aborted.")
	return
end

local function invoke(label: string, callback: () -> any)
	local ok, result = pcall(callback)
	if ok then
		print("[ClubMusic Security Test] PASS transport:", label, "returned", typeof(result))
	else
		warn("[ClubMusic Security Test] FAIL transport:", label, tostring(result))
	end
	return ok, result
end

print("[ClubMusic Security Test] Starting malformed-input smoke tests.")

-- Unknown and malformed action contracts must be rejected without mutation.
invoke("unknown action", function()
	actionRemote:FireServer("ClubMusicSecurityUnknownAction", {})
	return true
end)

invoke("non-string action", function()
	actionRemote:FireServer({}, {})
	return true
end)

invoke("non-table action payload", function()
	actionRemote:FireServer("RequestTrack", "not-a-table")
	return true
end)

invoke("oversized action payload string", function()
	actionRemote:FireServer("RequestTrack", {query = string.rep("X", 2048)})
	return true
end)

invoke("excessively nested action payload", function()
	actionRemote:FireServer("RequestTrack", {
		one = {two = {three = {four = "too deep"}}},
	})
	return true
end)

task.wait(1)

-- Invalid catalog argument types/ranges must return nil rather than error.
local catalogCases = {
	{"oversized query", string.rep("Q", 49), "", 0, 30},
	{"oversized genre", "", string.rep("G", 25), 0, 30},
	{"fractional offset", "", "", 1.5, 30},
	{"fractional page size", "", "", 0, 2.5},
	{"wrong offset type", "", "", "0", 30},
}

for _, testCase in ipairs(catalogCases) do
	local label, query, genre, offset, limit = table.unpack(testCase)
	invoke("catalog " .. label, function()
		return catalogFunction:InvokeServer(query, genre, offset, limit)
	end)
	task.wait(0.85)
end

invoke("GetState", function()
	return stateFunction:InvokeServer()
end)

task.wait(0.85)

invoke("GetMusicPlaylists", function()
	return playlistFunction:InvokeServer()
end)

print("[ClubMusic Security Test] Finished. Check Server Output for unexpected handler errors.")
print("[ClubMusic Security Test] A PASS transport result only means the call completed; verify rejected inputs caused no state change.")
