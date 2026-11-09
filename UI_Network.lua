--!strict
-- UI_Network
-- Place as ModuleScript: ReplicatedStorage/UI_Network
-- Client-side bridge to the authoritative UI_Server_Controller.
--
-- Remote contract (created/owned by the server): ReplicatedStorage/ClubMusicRemotes
--   RequestAction (RemoteEvent)   client -> server: (action: string, payload: table)
--   StateChanged  (RemoteEvent)   server -> client: snapshot table
--   Notice        (RemoteEvent)   server -> client: { text: string, kind: string }
--   GetState      (RemoteFunction) client -> server: returns snapshot table
--
-- Security note: client checks are defense-in-depth only. Exploiters can bypass this
-- ModuleScript and fire remotes directly. Authorization, validation and throttling
-- MUST remain enforced by UI_Server_Controller.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FOLDER_NAME = "ClubMusicRemotes"
local REMOTE_TIMEOUT = 3
local MAX_STATE_DEPTH = 8
local MAX_STATE_ENTRIES = 2500
local MAX_NOTICE_TEXT = 400
local MAX_NOTICE_KIND = 32

local Network = {}

local initialized = false
local initializing = false
local destroyed = false
local receivedState = false
local lastInitWarningAt = 0

local actionRemote: RemoteEvent? = nil
local catalogFunction: RemoteFunction? = nil
local playlistFunction: RemoteFunction? = nil
local currentState: {[string]: any} = {}
local connections: {RBXScriptConnection} = {}
local stateEvent = Instance.new("BindableEvent")
local noticeEvent = Instance.new("BindableEvent")

-- Must stay aligned with UI_Renderer_Secure.lua and the server handleAction().
local ALLOWED_ACTIONS: {[string]: boolean} = {
	RequestTrack = true,
	CatalogAddAudio = true,
	CatalogRemoveTrack = true,
	PlaylistCreate = true,
	PlaylistDelete = true,
	PlaylistAddTrack = true,
	PlaylistRemoveTrack = true,
	PlaylistMoveTrack = true,
	DJPlayPlaylist = true,
	DJStopPlaylist = true,
	RequestAudioAsset = true,
	ReloadSong = true,
	ToggleFavorite = true,
	VoteSkip = true,
	DJMoveUp = true,
	DJRemove = true,
	DJPause = true,
	DJRestart = true,
	DJSkip = true,
	DJClearQueue = true,
	DJToggleLock = true,
	ModBlockUser = true,
	ModSetVip = true,
	ModPurgeUser = true,
	ClaimDailyReward = true,
	EquipTitleTag = true,
	SaveCustomTitle = true,
	SaveTitleSlot = true,
	SelectTitleSlot = true,
	ClearTitleSlot = true,
	SetTitleVisible = true,
}

-- Mirrors the server's action cooldowns where known. This only prevents accidental
-- client spam; the server remains authoritative and independently enforces them.
local ACTION_COOLDOWNS: {[string]: number} = {
	RequestTrack = 0.5,
	CatalogAddAudio = 10,
	CatalogRemoveTrack = 2,
	PlaylistCreate = 2,
	PlaylistDelete = 1,
	PlaylistAddTrack = 0.5,
	PlaylistRemoveTrack = 0.5,
	PlaylistMoveTrack = 0.5,
	DJPlayPlaylist = 2,
	DJStopPlaylist = 1,
	RequestAudioAsset = 10,
	ReloadSong = 3,
	ToggleFavorite = 0.2,
	VoteSkip = 0.5,
	DJMoveUp = 0.2,
	DJRemove = 0.2,
	DJPause = 0.5,
	DJRestart = 1,
	DJSkip = 0.5,
	DJClearQueue = 1,
	DJToggleLock = 1,
	ModBlockUser = 0.5,
	ModSetVip = 0.5,
	ModPurgeUser = 0.5,
	ClaimDailyReward = 1,
	EquipTitleTag = 0.5,
	SaveCustomTitle = 2,
	SaveTitleSlot = 2,
	SelectTitleSlot = 0.3,
	ClearTitleSlot = 0.5,
	SetTitleVisible = 0.3,
}

local lastGlobalSend = 0
local lastActionSend: {[string]: number} = {}

local function cloneBounded(value: any, depth: number, budget: {[string]: number}, seen: {[any]: boolean}): any
	local kind = typeof(value)
	if kind == "string" then
		return string.sub(value, 1, 2000)
	elseif kind == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			return nil
		end
		return math.clamp(value, -1e12, 1e12)
	elseif kind == "boolean" then
		return value
	elseif kind ~= "table" or depth >= MAX_STATE_DEPTH or seen[value] then
		return nil
	end

	seen[value] = true
	local output: {[any]: any} = {}
	for key, child in pairs(value :: {[any]: any}) do
		budget.count += 1
		if budget.count > MAX_STATE_ENTRIES then
			break
		end
		local keyType = typeof(key)
		if keyType == "string" then
			local safeKey = string.sub(key, 1, 100)
			local safeValue = cloneBounded(child, depth + 1, budget, seen)
			if safeValue ~= nil then output[safeKey] = safeValue end
		elseif keyType == "number" and key == key and key ~= math.huge and key ~= -math.huge then
			local safeValue = cloneBounded(child, depth + 1, budget, seen)
			if safeValue ~= nil then output[key] = safeValue end
		end
	end
	seen[value] = nil
	return output
end

local function safeClone(value: any): any
	return cloneBounded(value, 0, {count = 0}, {})
end

-- Bounded structural comparison. If a payload is too large/deep or cyclic,
-- treat it as changed instead of risking unbounded recursive work.
local function sameStateInner(a: any, b: any, depth: number, budget: {[string]: number}, seen: {[any]: any}): boolean
	if a == b then return true end
	if typeof(a) ~= "table" or typeof(b) ~= "table" or depth >= MAX_STATE_DEPTH then return false end
	if seen[a] == b then return false end
	seen[a] = b
	for key, value in pairs(a :: {[any]: any}) do
		budget.count += 1
		if budget.count > MAX_STATE_ENTRIES then return false end
		if key ~= "elapsed" and not sameStateInner(value, (b :: {[any]: any})[key], depth + 1, budget, seen) then
			return false
		end
	end
	for key in pairs(b :: {[any]: any}) do
		budget.count += 1
		if budget.count > MAX_STATE_ENTRIES then return false end
		if key ~= "elapsed" and (a :: {[any]: any})[key] == nil then return false end
	end
	seen[a] = nil
	return true
end

local function sameState(a: any, b: any): boolean
	return sameStateInner(a, b, 0, {count = 0}, {})
end

local function applyState(newState: any)
	if destroyed or typeof(newState) ~= "table" then return end
	local safeState = safeClone(newState)
	if typeof(safeState) ~= "table" then return end
	receivedState = true

	if sameState(currentState, safeState) then
		-- Preserve the newest playback clock without forcing the renderer to rebuild.
		local newNow = safeState.nowPlaying
		local cachedNow = currentState.nowPlaying
		if typeof(newNow) == "table" and typeof(cachedNow) == "table" then
			cachedNow.elapsed = newNow.elapsed
		end
		return
	end

	currentState = safeState
	stateEvent:Fire(safeClone(currentState))
end

local function applyNotice(notice: any)
	if destroyed then return end
	if typeof(notice) == "string" then
		noticeEvent:Fire({text = string.sub(notice, 1, MAX_NOTICE_TEXT), kind = "info"})
		return
	end
	if typeof(notice) ~= "table" then return end

	local textValue = notice.text
	if typeof(textValue) ~= "string" then textValue = notice.message end
	if typeof(textValue) ~= "string" or textValue == "" then return end

	local kindValue = notice.kind
	if typeof(kindValue) ~= "string" then kindValue = "info" end
	noticeEvent:Fire({
		text = string.sub(textValue, 1, MAX_NOTICE_TEXT),
		kind = string.sub(kindValue, 1, MAX_NOTICE_KIND),
	})
end

local function waitForRemote(folder: Instance, name: string, className: string): Instance
	local child = folder:WaitForChild(name, REMOTE_TIMEOUT)
	assert(child ~= nil, ("UI_Network: remote '%s' not found. Is UI_Server_Controller running?"):format(name))
	assert(child:IsA(className), ("UI_Network: '%s' must be a %s"):format(name, className))
	return child
end

function Network.Init(): boolean
	if destroyed then return false end
	if initialized then return true end
	if initializing then return false end
	initializing = true

	local ok, err = pcall(function()
		local foundFolder = ReplicatedStorage:WaitForChild(FOLDER_NAME, REMOTE_TIMEOUT)
		if not foundFolder or not foundFolder:IsA("Folder") then
			error("Waiting for ReplicatedStorage.ClubMusicRemotes; the server controller may still be starting.")
		end
		local readyStartedAt = os.clock()
		while foundFolder:GetAttribute("Ready") ~= true do
			if os.clock() - readyStartedAt >= REMOTE_TIMEOUT then
				error("ClubMusicRemotes exists but the server controller has not finished initializing.")
			end
			task.wait(0.1)
		end

		local action = waitForRemote(foundFolder, "RequestAction", "RemoteEvent") :: RemoteEvent
		local stateRemote = waitForRemote(foundFolder, "StateChanged", "RemoteEvent") :: RemoteEvent
		local noticeRemote = waitForRemote(foundFolder, "Notice", "RemoteEvent") :: RemoteEvent
		local stateFunction = waitForRemote(foundFolder, "GetState", "RemoteFunction") :: RemoteFunction
		local musicCatalogFunction = waitForRemote(foundFolder, "GetMusicCatalog", "RemoteFunction") :: RemoteFunction
		local musicPlaylistFunction = waitForRemote(foundFolder, "GetMusicPlaylists", "RemoteFunction") :: RemoteFunction

		-- Subscribe before the initial snapshot request so no push update is missed.
		actionRemote = action
		catalogFunction = musicCatalogFunction
		playlistFunction = musicPlaylistFunction
		table.insert(connections, stateRemote.OnClientEvent:Connect(applyState))
		table.insert(connections, noticeRemote.OnClientEvent:Connect(applyNotice))

		initialized = true
		task.spawn(function()
			local fetchOk, result = pcall(function()
				return stateFunction:InvokeServer()
			end)
			-- A pushed update is authoritative if it arrived before this fetch completed.
			if fetchOk and not receivedState then
				applyState(result)
			elseif not fetchOk then
				warn("[ClubMusic Network] Initial state fetch failed: " .. tostring(result))
			end
		end)
	end)

	initializing = false
	if not ok then
		for _, connection in ipairs(connections) do connection:Disconnect() end
		table.clear(connections)
		actionRemote = nil
		catalogFunction = nil
		playlistFunction = nil
		initialized = false
		if os.clock() - lastInitWarningAt >= 10 then
			lastInitWarningAt = os.clock()
			warn("[ClubMusic Network] Initialization is waiting for server remotes: " .. tostring(err))
		end
		return false
	end
	return true
end

function Network.Destroy()
	if destroyed then return end
	destroyed = true
	initialized = false
	initializing = false
	for _, connection in ipairs(connections) do connection:Disconnect() end
	table.clear(connections)
	actionRemote = nil
	catalogFunction = nil
	playlistFunction = nil
	table.clear(lastActionSend)
	currentState = {}
	if stateEvent then stateEvent:Destroy() end
	if noticeEvent then noticeEvent:Destroy() end
end

-- Return a detached copy: callers may inspect/change it without mutating the cache.
function Network.GetState(): {[string]: any}
	return safeClone(currentState)
end

-- Fetch a bounded page from the server-owned song catalog. This is a read-only
-- metadata API; it cannot queue tracks or bypass RequestTrack authorization.
function Network.GetMusicCatalog(query: string?, genreId: string?, offset: number?, limit: number?)
	if destroyed or not initialized then
		if not Network.Init() then return nil end
	end
	local remote = catalogFunction
	if remote == nil or remote.Parent == nil then return nil end
	local safeQuery = if typeof(query) == "string" then string.sub(query, 1, 48) else ""
	local safeGenre = if typeof(genreId) == "string" then string.sub(genreId, 1, 24) else ""
	local safeOffset = if typeof(offset) == "number" then math.clamp(math.floor(offset), 0, 10000) else 0
	local safeLimit = if typeof(limit) == "number" then math.clamp(math.floor(limit), 1, 50) else 30
	local ok, result = pcall(function()
		return remote:InvokeServer(safeQuery, safeGenre, safeOffset, safeLimit)
	end)
	if not ok then
		warn("[ClubMusic Network] GetMusicCatalog failed: " .. tostring(result))
		return nil
	end
	if typeof(result) ~= "table" or typeof(result.items) ~= "table"
		or typeof(result.total) ~= "number" or typeof(result.offset) ~= "number" then
		return nil
	end
	return safeClone(result)
end

function Network.GetMusicPlaylists()
	if destroyed or not initialized then
		if not Network.Init() then return nil end
	end
	local remote = playlistFunction
	if remote == nil or remote.Parent == nil then return nil end
	local ok, result = pcall(function() return remote:InvokeServer() end)
	if not ok or typeof(result) ~= "table" then return nil end
	return safeClone(result)
end

function Network.PlaylistCreate(name: string)
	Network.Send("PlaylistCreate", {name = name})
end

function Network.PlaylistDelete(playlistId: string)
	Network.Send("PlaylistDelete", {playlistId = playlistId})
end

function Network.PlaylistAddTrack(playlistId: string, trackId: string)
	Network.Send("PlaylistAddTrack", {playlistId = playlistId, trackId = trackId})
end

function Network.PlaylistRemoveTrack(playlistId: string, trackId: string)
	Network.Send("PlaylistRemoveTrack", {playlistId = playlistId, trackId = trackId})
end

function Network.PlaylistMoveTrack(playlistId: string, trackId: string, position: number)
	Network.Send("PlaylistMoveTrack", {playlistId = playlistId, trackId = trackId, position = position})
end

function Network.OnStateChanged(callback: (any) -> ()): RBXScriptConnection
	assert(typeof(callback) == "function", "UI_Network.OnStateChanged expects a callback")
	return stateEvent.Event:Connect(callback)
end

function Network.OnNotice(callback: (any) -> ()): RBXScriptConnection
	assert(typeof(callback) == "function", "UI_Network.OnNotice expects a callback")
	return noticeEvent.Event:Connect(callback)
end

function Network.Send(action: string, payload: any?): boolean
	if destroyed then return false end
	if typeof(action) ~= "string" or not ALLOWED_ACTIONS[action] then
		warn("[ClubMusic Network] Blocked unknown action: " .. tostring(action))
		return false
	end
	if payload ~= nil and typeof(payload) ~= "table" then
		warn("[ClubMusic Network] Blocked malformed payload for " .. action)
		return false
	end
	if not initialized and not Network.Init() then return false end

	local remote = actionRemote
	if remote == nil or remote.Parent == nil then
		for _, connection in ipairs(connections) do connection:Disconnect() end
		table.clear(connections)
		actionRemote = nil
		initialized = false
		receivedState = false
		if not Network.Init() then return false end
		remote = actionRemote
	end
	if remote == nil then return false end

	local now = os.clock()
	if lastGlobalSend > 0 and now - lastGlobalSend < 0.12 then return false end
	local cooldown = ACTION_COOLDOWNS[action] or 0.2
	local previousActionSend = lastActionSend[action] or 0
	if previousActionSend > 0 and now - previousActionSend < cooldown then return false end

	local safePayload = safeClone(if typeof(payload) == "table" then payload else {})
	if typeof(safePayload) ~= "table" then return false end

	lastGlobalSend = now
	lastActionSend[action] = now
	local fired, fireError = pcall(function()
		(remote :: RemoteEvent):FireServer(action, safePayload)
	end)
	if not fired then
		warn("[ClubMusic Network] Remote send failed: " .. tostring(fireError))
		return false
	end
	return true
end

-- Named actions used by UI_Renderer. Payload keys intentionally match the
-- hardened server controller's handleAction() contract.
function Network.RequestTrack(trackId: string)
	Network.Send("RequestTrack", {trackId = trackId})
end

-- Staff-only on the server; these methods only request catalog mutations.
function Network.CatalogAddAudio(assetId: number, genreId: string)
	Network.Send("CatalogAddAudio", {assetId = assetId, genreId = genreId})
end

function Network.CatalogRemoveTrack(trackId: string)
	Network.Send("CatalogRemoveTrack", {trackId = trackId})
end

function Network.ToggleFavorite(trackId: string)
	Network.Send("ToggleFavorite", {trackId = trackId})
end

function Network.VoteSkip()
	Network.Send("VoteSkip", {})
end

function Network.ReloadSong()
	Network.Send("ReloadSong", {})
end

function Network.DJSkip()
	Network.Send("DJSkip", {})
end

function Network.DJPause()
	Network.Send("DJPause", {})
end

function Network.DJRestart()
	Network.Send("DJRestart", {})
end

function Network.DJMoveUp(queueId: string)
	Network.Send("DJMoveUp", {queueId = queueId})
end

function Network.DJRemove(queueId: string)
	Network.Send("DJRemove", {queueId = queueId})
end

function Network.DJClearQueue()
	Network.Send("DJClearQueue", {})
end

function Network.DJToggleLock()
	Network.Send("DJToggleLock", {})
end

-- Staff-only on the server. Client-side checks here are not authorization.
function Network.RequestAudioAsset(assetId: number, title: string?)
	local id = tonumber(assetId)
	if not id or id <= 0 or id ~= math.floor(id) or id > 9007199254740991 then
		warn("[ClubMusic Network] RequestAudioAsset: invalid asset id")
		return
	end
	Network.Send("RequestAudioAsset", {
		assetId = id,
		title = if typeof(title) == "string" then string.sub(title, 1, 80) else "",
	})
end

function Network.ModBlockUser(userId: number, blocked: boolean)
	if typeof(userId) ~= "number" or userId % 1 ~= 0 or userId <= 0 then return end
	Network.Send("ModBlockUser", {userId = userId, blocked = blocked == true})
end

function Network.ModSetVip(userId: number, vip: boolean)
	if typeof(userId) ~= "number" or userId % 1 ~= 0 or userId <= 0 then return end
	Network.Send("ModSetVip", {userId = userId, vip = vip == true})
end

function Network.ModPurgeUser(userId: number)
	if typeof(userId) ~= "number" or userId % 1 ~= 0 or userId <= 0 then return end
	Network.Send("ModPurgeUser", {userId = userId})
end

function Network.ClaimDailyReward(day: number)
	if typeof(day) ~= "number" or day % 1 ~= 0 or day < 1 or day > 7 then return end
	Network.Send("ClaimDailyReward", {day = day})
end

function Network.EquipTitleTag(tagId: string)
	if typeof(tagId) ~= "string" then return end
	Network.Send("EquipTitleTag", {tagId = string.sub(tagId, 1, 32)})
end

-- Legacy single custom title API retained for compatibility with older renderer paths.
function Network.SaveCustomTitle(text: string, color: string, style: string, visible: boolean?)
	Network.Send("SaveCustomTitle", {
		text = if typeof(text) == "string" then string.sub(text, 1, 48) else "",
		color = if typeof(color) == "string" then string.sub(color, 1, 24) else "gold",
		style = if typeof(style) == "string" then string.sub(style, 1, 24) else "normal",
		visible = if visible == nil then true else visible == true,
	})
end

-- Extended title slots: preserves the complete effect/font/offset/distance contract.
function Network.SaveTitleSlot(data: any)
	if typeof(data) ~= "table" then return end
	local rawSlot = tonumber(data.slot)
	if not rawSlot or rawSlot % 1 ~= 0 or rawSlot < 1 or rawSlot > 3 then
		warn("[ClubMusic Network] SaveTitleSlot: slot must be 1-3")
		return
	end

	local colors: {string} = {}
	if typeof(data.colors) == "table" then
		for index, value in ipairs(data.colors) do
			if index > 8 then break end
			if typeof(value) == "string" then table.insert(colors, string.sub(value, 1, 9)) end
		end
	end

	Network.Send("SaveTitleSlot", {
		slot = rawSlot,
		text = if typeof(data.text) == "string" then string.sub(data.text, 1, 48) else "",
		effect = if typeof(data.effect) == "string" then string.sub(data.effect, 1, 24) else "fixed",
		set = if typeof(data.set) == "string" then string.sub(data.set, 1, 32) else "",
		colors = colors,
		font = if typeof(data.font) == "string" then string.sub(data.font, 1, 32) else "gotham",
		style = if typeof(data.style) == "string" then string.sub(data.style, 1, 24) else "normal",
		heightOffset = math.clamp(tonumber(data.heightOffset) or 2.5, 0, 8),
		viewDistance = math.clamp(tonumber(data.viewDistance) or 80, 20, 200),
		visible = data.visible ~= false,
	})
end

function Network.SelectTitleSlot(slot: number)
	if typeof(slot) ~= "number" or slot % 1 ~= 0 or slot < 1 or slot > 3 then return end
	Network.Send("SelectTitleSlot", {slot = slot})
end

function Network.ClearTitleSlot(slot: number)
	if typeof(slot) ~= "number" or slot % 1 ~= 0 or slot < 1 or slot > 3 then return end
	Network.Send("ClearTitleSlot", {slot = slot})
end

function Network.SetTitleVisible(visible: boolean)
	Network.Send("SetTitleVisible", {visible = visible == true})
end

return Network
