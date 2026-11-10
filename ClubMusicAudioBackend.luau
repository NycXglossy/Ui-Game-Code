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

	local fader = Instance.new("AudioFader")
	fader.Name = "MusicFader"
	fader.Volume = 1
	fader.Parent = root

	local output = Instance.new("AudioDeviceOutput")
	output.Name = "MusicOutput"
	if config.OutputPlayer then output.Player = config.OutputPlayer end
	output.Parent = root

	local inputWire = makeWire(root, player, fader)
	local outputWire = makeWire(root, fader, output)

	return setmetatable({
		root = root,
		player = player,
		fader = fader,
		output = output,
		wires = { inputWire, outputWire },
		destroyed = false,
		paused = false,
		pausedAt = 0,
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
	self:Stop()
	local ok, err = pcall(function()
		self.player.Asset = asset
	end)
	if not ok then return false, tostring(err) end
	return true, nil
end

function Backend:IsReady(): boolean
	return self:IsAvailable() and self.player.IsReady
end

function Backend:GetTimePosition(): number
	if not self:IsAvailable() then return 0 end
	return math.max(0, self.player.TimePosition)
end

function Backend:GetTimeLength(): number
	if not self:IsAvailable() or not self.player.IsReady then return 0 end
	return math.max(0, self.player.TimeLength)
end

function Backend:IsPlaying(): boolean
	return self:IsAvailable() and self.player.IsPlaying and not self.paused
end

function Backend:Play(asset: string?, position: number?): (boolean, string?)
	if asset ~= nil then
		local ok, err = self:SetAsset(asset)
		if not ok then return false, err end
	end
	if not self:IsAvailable() then return false, "Audio backend is unavailable." end
	if position ~= nil then
		if not finite(position) or position < 0 then return false, "Invalid playback position." end
		self.player.TimePosition = position
	end
	self.paused = false
	self.pausedAt = 0
	local ok, err = pcall(function() self.player:Play() end)
	if not ok then return false, tostring(err) end
	return true, nil
end

-- AudioPlayer has no Sound-style Pause method. Preserve the playhead and stop;
-- Resume restores the saved position and starts the same asset again.
function Backend:Pause(): (boolean, string?)
	if not self:IsAvailable() then return false, "Audio backend is unavailable." end
	if not self.player.IsPlaying then return true, nil end
	self.pausedAt = self.player.TimePosition
	self.paused = true
	local ok, err = pcall(function() self.player:Stop() end)
	if not ok then self.paused = false; return false, tostring(err) end
	return true, nil
end

function Backend:Resume(): (boolean, string?)
	if not self:IsAvailable() then return false, "Audio backend is unavailable." end
	if not self.paused then return true, nil end
	self.player.TimePosition = math.max(0, self.pausedAt)
	self.paused = false
	local ok, err = pcall(function() self.player:Play() end)
	if not ok then self.paused = true; return false, tostring(err) end
	return true, nil
end

function Backend:Stop(): (boolean, string?)
	if not self:IsAvailable() then return false, "Audio backend is unavailable." end
	self.paused = false
	self.pausedAt = 0
	local ok, err = pcall(function() self.player:Stop() end)
	if not ok then return false, tostring(err) end
	return true, nil
end

function Backend:Seek(position: number): (boolean, string?)
	if not self:IsAvailable() or not finite(position) or position < 0 then
		return false, "Invalid seek request."
	end
	local ok, err = pcall(function()
		self.player.TimePosition = position
		if self.paused then self.pausedAt = position end
	end)
	if not ok then return false, tostring(err) end
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
	self.output = nil
	table.clear(self.wires)
end

return Backend
