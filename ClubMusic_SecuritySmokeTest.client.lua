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
		print("[ClubMusic Security Test] SENT:", label, "returned", typeof(result))
	else
		warn("[ClubMusic Security Test] TRANSPORT ERROR:", label, tostring(result))
	end
	return ok, result
end

local function captureState(label: string)
	-- GetState can legitimately return nil when its local/shared query budget
	-- is exhausted or its cooldown is active. Retry slowly and report the
	-- distinction instead of treating one nil response as a test failure.
	for attempt = 1, 4 do
		local ok, result = pcall(function()
			return stateFunction:InvokeServer()
		end)
		if ok and typeof(result) == "table" then
			print("[ClubMusic Security Test] STATE:", label, "captured on attempt", attempt)
			return result
		end
		warn("[ClubMusic Security Test] STATE:", label, "unavailable on attempt", attempt,
			"transportOk=", ok, "resultType=", if ok then typeof(result) else "error",
			if not ok then tostring(result) else "")
		if attempt < 4 then task.wait(1.5) end
	end
	warn("[ClubMusic Security Test] Could not capture " .. label .. " after retries; state comparison will be skipped.")
	return nil
end

local baseline = captureState("baseline")

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

local tooManyTopLevelKeys = {}
for index = 1, 17 do
	tooManyTopLevelKeys["key" .. tostring(index)] = true
end
invoke("excessive top-level key count", function()
	actionRemote:FireServer("RequestTrack", tooManyTopLevelKeys)
	return true
end)

local tooManyNestedKeys = {}
for index = 1, 17 do
	tooManyNestedKeys["key" .. tostring(index)] = true
end
invoke("excessive nested key count", function()
	actionRemote:FireServer("RequestTrack", {data = tooManyNestedKeys})
	return true
end)

invoke("non-finite numeric payload", function()
	actionRemote:FireServer("RequestTrack", {trackId = math.huge})
	return true
end)

invoke("oversized payload key", function()
	actionRemote:FireServer("RequestTrack", {[string.rep("K", 33)] = true})
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

-- A valid control query helps distinguish malformed-argument rejection
-- from a catalog service/budget outage. It must return a table to be useful.
task.wait(1.25)
local validCatalogOk, validCatalog = pcall(function()
	return catalogFunction:InvokeServer("", "", 0, 10)
end)
if validCatalogOk and typeof(validCatalog) == "table" then
	print("[ClubMusic Security Test] CONTROL PASS: valid catalog query returned table.")
else
	warn("[ClubMusic Security Test] CONTROL INCONCLUSIVE: valid catalog query returned",
		if validCatalogOk then typeof(validCatalog) else "transport error",
		if not validCatalogOk then tostring(validCatalog) else "")
end

local finalState = captureState("post-test")

if baseline and typeof(finalState) == "table" then
	local unchanged = true
	local function check(label: string, before: any, after: any)
		if before ~= after then
			unchanged = false
			warn("[ClubMusic Security Test] STATE CHANGED:", label, tostring(before), "->", tostring(after))
		end
	end
	check("current track", baseline.nowPlaying and baseline.nowPlaying.trackId, finalState.nowPlaying and finalState.nowPlaying.trackId)
	check("paused state", baseline.nowPlaying and baseline.nowPlaying.paused, finalState.nowPlaying and finalState.nowPlaying.paused)
	check("request lock", baseline.locked, finalState.locked)
	check("request count", baseline.requests and baseline.requests.used, finalState.requests and finalState.requests.used)
	local beforeQueue = baseline.queue or {}
	local afterQueue = finalState.queue or {}
	if #beforeQueue ~= #afterQueue then
		unchanged = false
		warn("[ClubMusic Security Test] STATE CHANGED: queue length", #beforeQueue, "->", #afterQueue)
	else
		for index, entry in ipairs(beforeQueue) do
			if entry.id ~= afterQueue[index].id then
				unchanged = false
				warn("[ClubMusic Security Test] STATE CHANGED: queue entry", index, tostring(entry.id), "->", tostring(afterQueue[index].id))
				break
			end
		end
	end
	if unchanged then
		print("[ClubMusic Security Test] PASS: malformed action probes did not change the observed playback, lock, request, or queue state.")
	end
elseif baseline then
	warn("[ClubMusic Security Test] Could not verify post-test state; inspect server state manually.")
end

task.wait(0.85)

invoke("GetMusicPlaylists", function()
	return playlistFunction:InvokeServer()
end)

print("[ClubMusic Security Test] Finished. Check Server Output for unexpected handler errors.")
print("[ClubMusic Security Test] SENT confirms only that FireServer was called; the state comparison checks selected observable fields.")
