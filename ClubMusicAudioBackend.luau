--!strict
-- ClubMusic modern Roblox audio backend.
-- This module owns only its injected AudioPlayer graph. The server controller
-- remains the sole authority for queue state, track selection, and transitions.
-- It is opt-in until the experience has completed Studio/multiplayer validation.

local Backend = {}
Backend.__index = Backend

export type Config = {
	Parent: Instance?,
	Name: string?,
	Volume: number?,
	PlaybackSpeed: number?,
	InitialGain: number?,
	OutputPlayer: Player?,
}

local function finite(value: any): boolean
	return typeof(value) == "number" and value == value and math.abs(value) < math.huge
end

local function makeWire(parent: Instance, source: Instance, target: Instance): Wire
	local wire = Instance.new("Wire")
	wire.SourceInstance = source
	wire.TargetInstance = target
	wire.Parent = parent
	return wire
end

function Backend.new(config: Config?)
	config = config or {}
	local parent = config.Parent or game:GetService("SoundService")
	local name = config.Name or "ClubMusicModernAudio"
	local root = Instance.new("Folder")
	root.Name = name
	root:SetAttribute("ManagedByClubMusicAudioBackend", true)
	root.Parent = parent

	local player = Instance.new("AudioPlayer")
	player.Name = "AudioPlayer"
	player.AutoLoad = true
	player.AutoPlay = false
	player.Looping = false
	player.Volume = math.clamp(if finite(config.Volume) then config.Volume else 1, 0, 10)
	player.PlaybackSpeed = math.clamp(if finite(config.PlaybackSpeed) then config.PlaybackSpeed else 1, 0.05, 20)
	player.Parent = root

	local equalizer = Instance.new("AudioEqualizer")
	equalizer.Name = "MusicEqualizer"
	equalizer.MidRange = NumberRange.new(400, 3000)
	equalizer.LowGain = 0
	equalizer.MidGain = 0
	equalizer.HighGain = 0
	equalizer.Parent = root

	local fader = Instance.new("AudioFader")
	fader.Name = "MusicFader"
	fader.Volume = math.clamp(if finite(config.InitialGain) then config.InitialGain else 1, 0, 1)
	fader.Parent = root

	local output = Instance.new("AudioDeviceOutput")
	output.Name = "MusicOutput"
	if config.OutputPlayer then output.Player = config.OutputPlayer end
	output.Parent = root

	local inputWire = makeWire(root, player, equalizer)
	local equalizerWire = makeWire(root, equalizer, fader)
	local outputWire = makeWire(root, fader, output)

	return setmetatable({
		root = root,
		player = player,
		fader = fader,
		equalizer = equalizer,
		output = output,
		wires = { inputWire, equalizerWire, outputWire },
		destroyed = false,
		paused = false,
		pausedAt = 0,
		currentAsset = "",
	}, Backend)
end

function Backend:IsAvailable(): boolean
	return not self.destroyed and self.player ~= nil and self.player.Parent ~= nil
end

function Backend:SetAsset(asset: string): (boolean, string?)
	if not self:IsAvailable() then return false, "Audio backend is unavailable." end
	if typeof(asset) ~= "string" or #asset > 64 or not string.match(asset, "^rbxassetid://%d+$") then
		return false, "Invalid audio asset ID."
	end
	local stopped, stopError = self:Stop()
	if not stopped then return false, stopError or "The current audio could not be stopped safely." end
	local previousAsset = self.currentAsset
	local ok, err = pcall(function()
		self.player.Asset = asset
	end)
	if not ok then
		-- Keep the previous asset selected if replacement fails. Playback remains
		-- stopped; the controller can explicitly retry or resume it.
		if previousAsset ~= "" then
			pcall(function() self.player.Asset = previousAsset end)
		end
		return false, tostring(err)
	end
	self.currentAsset = asset
	self.paused = false
	self.pausedAt = 0
	return true, nil
end

function Backend:IsReady(): boolean
	if not self:IsAvailable() then return false end
	local ok, ready = pcall(function() return self.player.IsReady end)
	return ok and ready == true
end

-- Readiness is a multi-property condition for safe handoff: the asset must be
-- selected, the decoder must be ready, and duration must be finite and positive.
function Backend:GetReadinessSnapshot(): {ready: boolean, length: number, asset: string}
	if not self:IsAvailable() then
		return { ready = false, length = 0, asset = "" }
	end
	local ok, ready, length, asset = pcall(function()
		return self.player.IsReady, self.player.TimeLength, self.player.Asset
	end)
	if not ok then return { ready = false, length = 0, asset = self.currentAsset } end
	local validLength = if finite(length) then math.max(0, length) else 0
	local validAsset = if typeof(asset) == "string" then asset else self.currentAsset
	return {
		ready = ready == true and validLength > 0 and validAsset ~= "",
		length = validLength,
		asset = validAsset,
	}
end

function Backend:GetTimePosition(): number
	if not self:IsAvailable() then return 0 end
	local ok, position = pcall(function() return self.player.TimePosition end)
	return if ok and finite(position) then math.max(0, position) else 0
end

function Backend:GetTimeLength(): number
	if not self:IsReady() then return 0 end
	local ok, length = pcall(function() return self.player.TimeLength end)
	return if ok and finite(length) then math.max(0, length) else 0
end

function Backend:IsPlaying(): boolean
	if not self:IsAvailable() or self.paused then return false end
	local ok, playing = pcall(function() return self.player.IsPlaying end)
	return ok and playing == true
end

function Backend:Play(asset: string?, position: number?): (boolean, string?)
	if position ~= nil and (not finite(position) or position < 0) then
		return false, "Invalid playback position."
	end
	if asset ~= nil then
		local ok, err = self:SetAsset(asset)
		if not ok then return false, err end
	end
	if not self:IsAvailable() then return false, "Audio backend is unavailable." end
	local wasPaused = self.paused
	local previousPausedAt = self.pausedAt
	local ok, err = pcall(function()
		if position ~= nil then self.player.TimePosition = position end
		self.player:Play()
	end)
	if not ok then
		-- Play can fail after the engine has partially changed state. Prefer
		-- the engine's observable state over leaving a false paused snapshot.
		local stateOk, isPlaying = pcall(function() return self.player.IsPlaying end)
		if stateOk and isPlaying == true then
			self.paused = false
			self.pausedAt = 0
		else
			self.paused = wasPaused
			self.pausedAt = previousPausedAt
		end
		return false, tostring(err)
	end
	self.paused = false
	self.pausedAt = 0
	return true, nil
end

function Backend:GetAsset(): string
	if not self:IsAvailable() then return "" end
	if self.currentAsset ~= "" then return self.currentAsset end
	local ok, asset = pcall(function() return self.player.Asset end)
	return if ok and typeof(asset) == "string" then asset else ""
end

-- Re-select the current asset and restart it from a known position. The caller
-- owns readiness waits and decides when a recovered source may be committed.
function Backend:Reload(position: number?): (boolean, string?)
	if not self:IsAvailable() then return false, "Audio backend is unavailable." end
	local asset = self:GetAsset()
	if asset == "" then return false, "No audio asset is selected for reload." end
	local wasPaused = self.paused
	local target = if position == nil then (if wasPaused then self.pausedAt else self:GetTimePosition()) else position
	if not finite(target) or target < 0 then return false, "Invalid reload position." end
	local selected, selectError = self:SetAsset(asset)
	if not selected then return false, selectError end
	local seeked, seekError = self:Seek(target)
	if not seeked then return false, seekError end
	if wasPaused then
		-- Reloading a paused deck must not silently turn it into active playback.
		self.pausedAt = self:GetTimePosition()
		self.paused = true
		return true, nil
	end
	return self:Play()
end

-- AudioPlayer has no Sound-style Pause method. Preserve the playhead and stop;
-- Resume restores the saved position and starts the same asset again.
function Backend:Pause(): (boolean, string?, number?)
	if not self:IsAvailable() then return false, "Audio backend is unavailable.", nil end
	if self.paused then return true, nil, self.pausedAt end
	local playingOk, playing = pcall(function() return self.player.IsPlaying end)
	if not playingOk then return false, "Audio playback state could not be read for pause.", nil end
	if not playing then
		local positionOk, position = pcall(function() return self.player.TimePosition end)
		if not positionOk or not finite(position) or position < 0 then
			return false, "Audio playhead could not be captured for pause.", nil
		end
		self.pausedAt = position
		self.paused = true
		return true, nil, position
	end
	local positionOk, position = pcall(function() return self.player.TimePosition end)
	if not positionOk or not finite(position) or position < 0 then
		return false, "Audio playhead could not be captured for pause.", nil
	end
	local ok, err = pcall(function() self.player:Stop() end)
	if not ok then return false, tostring(err), nil end
	self.pausedAt = position
	self.paused = true
	return true, nil, position
end

function Backend:Resume(): (boolean, string?)
	if not self:IsAvailable() then return false, "Audio backend is unavailable." end
	if not self.paused then return true, nil end
	if not self:IsReady() then return false, "Audio asset is not ready to resume." end
	local position = math.max(0, self.pausedAt)
	local ok, err = pcall(function()
		self.player.TimePosition = position
		self.player:Play()
	end)
	if not ok then
		-- Retain the saved pause point unless the engine actually began playing.
		-- This makes a retry safe after a transient property/API failure.
		local stateOk, isPlaying = pcall(function() return self.player.IsPlaying end)
		if stateOk and isPlaying == true then
			self.paused = false
			self.pausedAt = 0
		end
		return false, tostring(err)
	end
	self.paused = false
	self.pausedAt = 0
	return true, nil
end

function Backend:Stop(): (boolean, string?)
	if not self:IsAvailable() then return false, "Audio backend is unavailable." end
	-- Keep the logical pause snapshot intact unless the engine confirms Stop.
	-- A transient Stop failure must not silently turn a paused deck into a
	-- playing-state deck or discard the position needed by Resume.
	local ok, err = pcall(function() self.player:Stop() end)
	if not ok then return false, tostring(err) end
	self.paused = false
	self.pausedAt = 0
	return true, nil
end

function Backend:Seek(position: number): (boolean, string?)
	if not self:IsAvailable() or not finite(position) or position < 0 then
		return false, "Invalid seek request."
	end
	local target = position
	if self:IsReady() then
		local lengthOk, length = pcall(function() return self.player.TimeLength end)
		if lengthOk and finite(length) and length > 0 then
			if target > length then return false, "Seek position exceeds the loaded track duration." end
		end
	end
	local previousPausedAt = self.pausedAt
	local ok, err = pcall(function() self.player.TimePosition = target end)
	-- Some engine/property failures can occur after a partial playhead update.
	-- Read back the actual position so a paused snapshot never advertises a
	-- stale point when the AudioPlayer did move before reporting the error.
	local readOk, actualPosition = pcall(function() return self.player.TimePosition end)
	if readOk and finite(actualPosition) and actualPosition >= 0 and self.paused then
		self.pausedAt = actualPosition
	end
	if not ok then
		if not readOk or not finite(actualPosition) or actualPosition < 0 then
			self.pausedAt = previousPausedAt
		end
		return false, tostring(err)
	end
	if not readOk or not finite(actualPosition) or actualPosition < 0 then
		if self.paused then self.pausedAt = previousPausedAt end
		return false, "The seek position could not be verified."
	end
	return true, nil
end

function Backend:SetGain(value: number): (boolean, string?)
	if not self:IsAvailable() or not finite(value) then return false, "Invalid audio gain." end
	self.fader.Volume = math.clamp(value, 0, 1)
	return true, nil
end

function Backend:GetGain(): number
	if not self:IsAvailable() or not self.fader then return 0 end
	return math.clamp(self.fader.Volume, 0, 1)
end

function Backend:SetEqualizer(lowGain: number, midGain: number, highGain: number): (boolean, string?)
	if not self:IsAvailable() or not self.equalizer
		or not finite(lowGain) or not finite(midGain) or not finite(highGain) then
		return false, "Invalid equalizer settings."
	end
	self.equalizer.LowGain = math.clamp(lowGain, -20, 10)
	self.equalizer.MidGain = math.clamp(midGain, -20, 10)
	self.equalizer.HighGain = math.clamp(highGain, -20, 10)
	return true, nil
end

function Backend:GetEqualizer(): {low: number, mid: number, high: number}
	if not self:IsAvailable() or not self.equalizer then
		return { low = 0, mid = 0, high = 0 }
	end
	return { low = self.equalizer.LowGain, mid = self.equalizer.MidGain, high = self.equalizer.HighGain }
end

function Backend:SetPlaybackSpeed(value: number): (boolean, string?)
	if not self:IsAvailable() or not finite(value) then return false, "Invalid playback speed." end
	self.player.PlaybackSpeed = math.clamp(value, 0.5, 2)
	return true, nil
end

function Backend:GetPlayer(): AudioPlayer?
	return if self:IsAvailable() then self.player else nil
end

function Backend:Cleanup()
	if self.destroyed then return end
	self.destroyed = true
	if self.root then pcall(function() self.root:Destroy() end) end
	self.root = nil
	self.player = nil
	self.fader = nil
	self.equalizer = nil
	self.output = nil
	table.clear(self.wires)
end

return Backend
