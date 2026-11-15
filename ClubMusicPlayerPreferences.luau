--!strict
-- Client-local modern audio routing and preferences.
-- The server replicates one authoritative AudioPlayer graph per active deck.
-- This module adds a private AudioFader -> AudioDeviceOutput route for this
-- LocalPlayer after each server-owned MusicFader. It never changes server gain.

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")

local Preferences = {}
Preferences.__index = Preferences

local function finite(value)
	return typeof(value) == "number" and value == value and math.abs(value) < math.huge
end

local VALID_PROFILES = {
	Standard = true,
	Soft = true,
	Bass = true,
	Night = true,
}

function Preferences.new(context)
	assert(typeof(context) == "table", "Player preferences require a local audio context.")
	assert(typeof(context.SetLocalGain) == "function", "Player preferences require SetLocalGain.")
	local player = Players.LocalPlayer
	assert(player ~= nil, "Modern local audio routing requires Players.LocalPlayer.")

	local self = setmetatable({
		context = context,
		player = player,
		volume = 1,
		muted = false,
		profile = "Standard",
		destroyed = false,
		routes = {},
		connections = {},
	}, Preferences)

	local function destroyRoute(root)
		local route = self.routes[root]
		if not route then return end
		self.routes[root] = nil
		for _, connection in ipairs(route.connections) do
			pcall(function() connection:Disconnect() end)
		end
		if route.graph then pcall(function() route.graph:Destroy() end) end
	end

	local function attachFader(root, sourceFader)
		local route = self.routes[root]
		if not route or route.fader or self.destroyed then return end
		if not sourceFader:IsA("AudioFader") or sourceFader.Name ~= "MusicFader" then return end

		local graph = Instance.new("Folder")
		graph.Name = "ClubMusicLocalAudioRoute"
		graph:SetAttribute("ManagedByClubMusicPlayerPreferences", true)

		local localFader = Instance.new("AudioFader")
		localFader.Name = "PlayerMusicGain"
		localFader.Volume = if self.muted then 0 else self.volume
		localFader.Parent = graph

		local output = Instance.new("AudioDeviceOutput")
		output.Name = "PlayerMusicOutput"
		output.Player = player
		output.Parent = graph

		local inputWire = Instance.new("Wire")
		inputWire.Name = "PlayerMusicInput"
		inputWire.SourceInstance = sourceFader
		inputWire.TargetInstance = localFader
		inputWire.Parent = graph

		local outputWire = Instance.new("Wire")
		outputWire.Name = "PlayerMusicOutputWire"
		outputWire.SourceInstance = localFader
		outputWire.TargetInstance = output
		outputWire.Parent = graph

		route.fader = localFader
		route.graph = graph
		graph.Parent = SoundService
	end

	local function inspectRoot(root)
		if self.destroyed or not root:IsA("Folder")
			or root:GetAttribute("ManagedByClubMusicAudioBackend") ~= true then
			return
		end
		if self.routes[root] then return end

		local route = { connections = {}, fader = nil, graph = nil }
		self.routes[root] = route
		table.insert(route.connections, root.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("AudioFader") and descendant.Name == "MusicFader" then
				attachFader(root, descendant)
			end
		end))
		table.insert(route.connections, root.AncestryChanged:Connect(function(_, parent)
			if parent == nil then destroyRoute(root) end
		end))

		local existing = root:FindFirstChild("MusicFader", true)
		if existing and existing:IsA("AudioFader") then
			attachFader(root, existing)
		end
	end

	table.insert(self.connections, SoundService.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("Folder") then inspectRoot(descendant) end
	end))

	-- Catch main playback or a crossfade deck that replicated before this UI
	-- initialized. The same scanner handles decks created later.
	for _, descendant in ipairs(SoundService:GetDescendants()) do
		if descendant:IsA("Folder") then inspectRoot(descendant) end
	end

	return self
end

function Preferences:SetVolume(value: number)
	if self.destroyed or not finite(value) then return false, "Invalid local volume." end
	local previous = self.volume
	self.volume = math.clamp(value, 0, 1)
	local applied, message = self:Apply()
	if not applied then
		self.volume = previous
		self:Apply()
		return false, message
	end
	return true, nil
end

function Preferences:SetMuted(value: boolean)
	if self.destroyed or typeof(value) ~= "boolean" then return false, "Invalid mute setting." end
	local previous = self.muted
	self.muted = value
	local applied, message = self:Apply()
	if not applied then
		self.muted = previous
		self:Apply()
		return false, message
	end
	return true, nil
end

function Preferences:SetProfile(value: string)
	if self.destroyed or typeof(value) ~= "string" or not VALID_PROFILES[value] then
		return false, "Unknown preference profile."
	end
	local previous = self.profile
	self.profile = value
	if typeof(self.context.SetLocalProfile) == "function" then
		local ok, result = pcall(self.context.SetLocalProfile, value)
		if not ok or result == false then
			self.profile = previous
			return false, "Local profile could not be applied."
		end
	end
	local applied, message = self:Apply()
	if not applied then
		self.profile = previous
		if typeof(self.context.SetLocalProfile) == "function" then
			pcall(self.context.SetLocalProfile, previous)
		end
		return false, message
	end
	return true, nil
end

function Preferences:Apply()
	if self.destroyed or typeof(self.context) ~= "table"
		or typeof(self.context.SetLocalGain) ~= "function" then
		return false, "Player preferences are unavailable."
	end
	local gain = if self.muted then 0 else self.volume
	if not finite(gain) then return false, "Invalid local gain." end
	gain = math.clamp(gain, 0, 1)

	local ok, result = pcall(self.context.SetLocalGain, gain)
	if not ok or result == false then return false, "Local preview volume could not be applied." end
	for _, route in pairs(self.routes) do
		if route.fader and route.fader.Parent then
			local applied = pcall(function() route.fader.Volume = gain end)
			if not applied then return false, "A local AudioFader could not be updated." end
		end
	end
	return true, nil
end

function Preferences:GetState()
	return {
		volume = math.clamp(self.volume, 0, 1),
		muted = self.muted == true,
		profile = self.profile,
	}
end

function Preferences:Cleanup()
	if self.destroyed then return end
	self.destroyed = true
	for _, connection in ipairs(self.connections) do
		pcall(function() connection:Disconnect() end)
	end
	table.clear(self.connections)
	for root, route in pairs(self.routes) do
		self.routes[root] = nil
		for _, connection in ipairs(route.connections) do
			pcall(function() connection:Disconnect() end)
		end
		if route.graph then pcall(function() route.graph:Destroy() end) end
	end
	self.context = nil
	self.player = nil
end

return Preferences
