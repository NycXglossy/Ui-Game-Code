--!strict
-- Server-observed animation inventory. Detection-only: never stops tracks,
-- changes AnimationIds, kicks, bans, or classifies an unfamiliar ID as an exploit.
local Players = game:GetService("Players")

local Service = {}
Service.__index = Service

local MAX_ASSET_IDS_PER_CHARACTER = 32
local MAX_TRACK_STARTS_PER_CHARACTER = 128
local MAX_INITIAL_TRACKS_TO_INSPECT = 64

type PlayerState = {
	character: Model?,
	playerConnections: {RBXScriptConnection},
	characterConnections: {RBXScriptConnection},
	animatorConnections: {[Animator]: RBXScriptConnection},
	observedAssetIds: {[number]: boolean},
	trackStarts: number,
	uniqueAssets: number,
	capSignaled: boolean,
}

local function finite(value: any): boolean
	return typeof(value) == "number" and value == value
		and value > -math.huge and value < math.huge
end

local function parseAssetId(animation: Animation?): number?
	if not animation then return nil end
	local ok, value = pcall(function() return animation.AnimationId end)
	if not ok or typeof(value) ~= "string" then return nil end
	local digits = string.match(value, "^rbxassetid://(%d+)$")
	if not digits or #digits > 16 then return nil end
	local id = tonumber(digits)
	if not finite(id) or id <= 0 or id % 1 ~= 0 or id > 9007199254740991 then return nil end
	return id
end

function Service.new(options: {[string]: any}?)
	local config = if typeof(options) == "table" then options else {}
	return setmetatable({
		onSignal = if type(config.onSignal) == "function" then config.onSignal else function() end,
		states = {} :: {[number]: PlayerState},
		connections = {} :: {RBXScriptConnection},
		started = false,
		observedTracks = 0,
		uniqueAssets = 0,
		unreadableIds = 0,
		cappedCharacters = 0,
		lastError = nil :: string?,
	}, Service)
end

function Service:_signal(player: Player, signal: string, detail: string, metadata: {[string]: any}?)
	local ok, err = pcall(self.onSignal, signal, player.UserId, string.sub(detail, 1, 120), metadata or {})
	if not ok then self.lastError = string.sub(tostring(err), 1, 180) end
end

function Service:_observeTrack(player: Player, state: PlayerState, track: AnimationTrack)
	if self.states[player.UserId] ~= state or state.character ~= player.Character then return end
	if state.trackStarts >= MAX_TRACK_STARTS_PER_CHARACTER then
		if not state.capSignaled then
			state.capSignaled = true
			self.cappedCharacters += 1
			self:_signal(player, "animation_track_observation_cap", tostring(MAX_TRACK_STARTS_PER_CHARACTER), {
				cap = MAX_TRACK_STARTS_PER_CHARACTER,
			})
		end
		return
	end
	state.trackStarts += 1
	self.observedTracks += 1

	local animation = track.Animation
	local assetId = parseAssetId(animation)
	if not assetId then
		self.unreadableIds += 1
		return
	end
	if state.observedAssetIds[assetId] then return end
	if state.uniqueAssets >= MAX_ASSET_IDS_PER_CHARACTER then
		if not state.capSignaled then
			state.capSignaled = true
			self.cappedCharacters += 1
			self:_signal(player, "animation_asset_observation_cap", tostring(MAX_ASSET_IDS_PER_CHARACTER), {
				cap = MAX_ASSET_IDS_PER_CHARACTER,
			})
		end
		return
	end

	state.observedAssetIds[assetId] = true
	state.uniqueAssets += 1
	self.uniqueAssets += 1
	local priorityValue = 0
	local priorityName = "Unknown"
	pcall(function()
		priorityValue = track.Priority.Value
		priorityName = track.Priority.Name
	end)
	local rigType = "Unknown"
	local character = state.character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid then rigType = humanoid.RigType.Name end

	-- One event per distinct asset ID per character. IDs and enum metadata only;
	-- no animation names, keyframes, chat, or client-supplied data are retained.
	self:_signal(player, "animation_asset_observed", tostring(assetId), {
		assetId = assetId,
		priority = if finite(priorityValue) then priorityValue else 0,
		priorityName = priorityName,
		rigType = rigType,
	})
end

function Service:_attachAnimator(player: Player, state: PlayerState, animator: Animator)
	if state.animatorConnections[animator] then return end
	state.animatorConnections[animator] = animator.AnimationPlayed:Connect(function(track)
		if typeof(track) == "Instance" and track:IsA("AnimationTrack") then
			self:_observeTrack(player, state, track)
		end
	end)
	local ok, tracks = pcall(function() return animator:GetPlayingAnimationTracks() end)
	if ok and typeof(tracks) == "table" then
		for index = 1, math.min(#tracks, MAX_INITIAL_TRACKS_TO_INSPECT) do
			local track = tracks[index]
			if track and track:IsA("AnimationTrack") then
				self:_observeTrack(player, state, track)
			end
		end
	end
end

function Service:_detachCharacter(state: PlayerState)
	for _, connection in ipairs(state.characterConnections) do connection:Disconnect() end
	table.clear(state.characterConnections)
	for _, connection in pairs(state.animatorConnections) do connection:Disconnect() end
	table.clear(state.animatorConnections)
	state.character = nil
	table.clear(state.observedAssetIds)
	state.trackStarts = 0
	state.uniqueAssets = 0
	state.capSignaled = false
end

function Service:_attachCharacter(player: Player, character: Model)
	local state = self.states[player.UserId]
	if not state then return end
	self:_detachCharacter(player, state)
	state.character = character

	local function attachHumanoid(humanoid: Humanoid)
		local function attachAnimator(child: Instance)
			if child:IsA("Animator") then self:_attachAnimator(player, state, child) end
		end
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then self:_attachAnimator(player, state, animator) end
		table.insert(state.characterConnections, humanoid.ChildAdded:Connect(attachAnimator))
		table.insert(state.characterConnections, humanoid.ChildRemoved:Connect(function(child)
			if child:IsA("Animator") then
				local connection = state.animatorConnections[child]
				if connection then connection:Disconnect(); state.animatorConnections[child] = nil end
			end
		end))
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then attachHumanoid(humanoid) end
	table.insert(state.characterConnections, character.ChildAdded:Connect(function(child)
		if child:IsA("Humanoid") then attachHumanoid(child) end
	end))
	table.insert(state.characterConnections, character.AncestryChanged:Connect(function(_, parent)
		if parent == nil and self.states[player.UserId] == state and state.character == character then
			self:_detachCharacter(player, state)
		end
	end))
end

function Service:_attachPlayer(player: Player)
	if self.states[player.UserId] then return end
	local state: PlayerState = {
		character = nil,
		playerConnections = {},
		characterConnections = {},
		animatorConnections = {},
		observedAssetIds = {},
		trackStarts = 0,
		uniqueAssets = 0,
		capSignaled = false,
	}
	self.states[player.UserId] = state
	table.insert(state.playerConnections, player.CharacterAdded:Connect(function(character)
		self:_attachCharacter(player, character)
	end))
	if player.Character then self:_attachCharacter(player, player.Character) end
end

function Service:Start(): boolean
	if self.started then return true end
	self.started = true
	table.insert(self.connections, Players.PlayerAdded:Connect(function(player)
		self:_attachPlayer(player)
	end))
	table.insert(self.connections, Players.PlayerRemoving:Connect(function(player)
		local state = self.states[player.UserId]
		if state then
			self:_detachCharacter(state)
			for _, connection in ipairs(state.playerConnections) do connection:Disconnect() end
			table.clear(state.playerConnections)
			self.states[player.UserId] = nil
		end
	end))
	for _, player in ipairs(Players:GetPlayers()) do self:_attachPlayer(player) end
	return true
end

function Service:GetStatus(): {[string]: any}
	local players, currentAssets = 0, 0
	for _, state in pairs(self.states) do
		players += 1
		currentAssets += state.uniqueAssets
	end
	return {
		state = if self.started then "Ready" else "Stopped",
		trackedPlayers = players,
		observedTracks = self.observedTracks,
		uniqueAssetsObserved = self.uniqueAssets,
		currentCharacterAssets = currentAssets,
		unreadableIds = self.unreadableIds,
		cappedCharacters = self.cappedCharacters,
		lastError = self.lastError,
		scope = "ServerObservedPerCharacter",
		mode = "DetectionOnly",
		automaticEnforcement = false,
	}
end

function Service:Stop()
	for _, connection in ipairs(self.connections) do connection:Disconnect() end
	table.clear(self.connections)
	for _, state in pairs(self.states) do
		self:_detachCharacter(state)
		for _, connection in ipairs(state.playerConnections) do connection:Disconnect() end
		table.clear(state.playerConnections)
	end
	table.clear(self.states)
	self.started = false
end

return Service
