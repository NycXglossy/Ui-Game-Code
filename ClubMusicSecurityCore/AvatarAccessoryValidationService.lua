--!strict
-- Detection-only avatar/accessory validation. Server observations are evidence,
-- not proof of exploitation; this module never kicks, bans, strips, or rewrites avatars.

local Players = game:GetService("Players")

local Service = {}
Service.__index = Service

local MAX_ACCESSORIES = 50
local MAX_PARTS_PER_ACCESSORY = 32
local MAX_HANDLE_AXIS = 30
local ADD_WINDOW_SECONDS = 10
local MAX_ADDITIONS_PER_WINDOW = 12
local STATE_TTL_SECONDS = 30

type PlayerState = {
	character: Model?,
	connections: {RBXScriptConnection},
	appearanceReady: boolean,
	additions: {number},
	lastSignalAt: {[string]: number},
	signals: number,
}

local function isFinite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local function validAssetId(value: any): boolean
	return typeof(value) == "number"
		and isFinite(value)
		and value > 0
		and value <= 9007199254740991
		and value % 1 == 0
end

function Service.new(options: {[string]: any}?)
	local config = if typeof(options) == "table" then options else {}
	return setmetatable({
		onSignal = if type(config.onSignal) == "function" then config.onSignal else function() end,
		states = {} :: {[number]: PlayerState},
		connections = {} :: {RBXScriptConnection},
		started = false,
		totalSignals = 0,
		suppressedSignals = 0,
		lastError = nil :: string?,
	}, Service)
end

function Service:_signal(player: Player, signal: string, detail: string)
	local state = self.states[player.UserId]
	if not state then return end
	local now = os.clock()
	local previous = state.lastSignalAt[signal] or 0
	if now - previous < 2 then
		self.suppressedSignals += 1
		return
	end
	state.lastSignalAt[signal] = now
	state.signals += 1
	self.totalSignals += 1
	local ok, err = pcall(self.onSignal, signal, player.UserId, string.sub(detail, 1, 180))
	if not ok then self.lastError = string.sub(tostring(err), 1, 180) end
end

function Service:_inspectAccessory(player: Player, accessory: Accessory, runtimeAdded: boolean)
	local state = self.states[player.UserId]
	if not state or not accessory:IsA("Accessory") then return end

	local partCount = 0
	for _, descendant in ipairs(accessory:GetDescendants()) do
		if descendant:IsA("BasePart") then
			partCount += 1
		end
		if partCount > MAX_PARTS_PER_ACCESSORY then
			self:_signal(player, "avatar_accessory_excessive_parts", accessory.Name)
			break
		end
	end

	local handle = accessory:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		self:_signal(player, "avatar_accessory_missing_handle", accessory.Name)
		return
	end

	local size = handle.Size
	if not (isFinite(size.X) and isFinite(size.Y) and isFinite(size.Z))
		or size.X <= 0 or size.Y <= 0 or size.Z <= 0
		or size.X > MAX_HANDLE_AXIS or size.Y > MAX_HANDLE_AXIS or size.Z > MAX_HANDLE_AXIS then
		self:_signal(player, "avatar_accessory_abnormal_handle_size", accessory.Name)
	end

	if handle.CanCollide then
		self:_signal(player, "avatar_accessory_collidable_handle", accessory.Name)
	end

	if runtimeAdded and state.appearanceReady then
		local now = os.clock()
		local additions = state.additions
		table.insert(additions, now)
		while additions[1] and now - additions[1] > ADD_WINDOW_SECONDS do
			table.remove(additions, 1)
		end
		if #additions > MAX_ADDITIONS_PER_WINDOW then
			self:_signal(player, "avatar_accessory_rapid_insertion", tostring(#additions))
		end
	end
end

function Service:_inspectDescription(player: Player, humanoid: Humanoid)
	local ok, description = pcall(function()
		return humanoid:GetAppliedDescription()
	end)
	if not ok or not description then
		self:_signal(player, "avatar_description_unavailable", "GetAppliedDescription failed")
		return
	end

	local accessoriesOk, accessories = pcall(function()
		return description:GetAccessories(true)
	end)
	if not accessoriesOk or typeof(accessories) ~= "table" then
		self:_signal(player, "avatar_accessory_description_invalid", "Accessory description could not be read")
		return
	end

	if #accessories > MAX_ACCESSORIES then
		self:_signal(player, "avatar_accessory_count_exceeded", tostring(#accessories))
	end

	local seen = {}
	for _, item in ipairs(accessories) do
		if typeof(item) ~= "table" or not validAssetId(item.AssetId) then
			self:_signal(player, "avatar_accessory_invalid_asset_id", "Invalid accessory description entry")
		elseif seen[item.AssetId] then
			self:_signal(player, "avatar_accessory_duplicate_asset", tostring(item.AssetId))
		else
			seen[item.AssetId] = true
		end
	end
end

function Service:_attachCharacter(player: Player, character: Model)
	local previous = self.states[player.UserId]
	if previous then
		for _, connection in ipairs(previous.connections) do connection:Disconnect() end
	end

	local state: PlayerState = {
		character = character,
		connections = {},
		appearanceReady = false,
		additions = {},
		lastSignalAt = {},
		signals = 0,
	}
	self.states[player.UserId] = state

	local function attachAppearance()
		if self.states[player.UserId] ~= state or player.Character ~= character then return end
		state.appearanceReady = true
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then self:_inspectDescription(player, humanoid) end
		local count = 0
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("Accessory") then
				count += 1
				self:_inspectAccessory(player, child, false)
			end
		end
		if count > MAX_ACCESSORIES then
			self:_signal(player, "avatar_accessory_count_exceeded", tostring(count))
		end
	end

	table.insert(state.connections, character.ChildAdded:Connect(function(child)
		if child:IsA("Accessory") then
			self:_inspectAccessory(player, child, state.appearanceReady)
		end
	end))

	table.insert(state.connections, character.AncestryChanged:Connect(function(_, parent)
		if parent == nil and self.states[player.UserId] == state then
			for _, connection in ipairs(state.connections) do connection:Disconnect() end
			self.states[player.UserId] = nil
		end
	end))

	if player:HasAppearanceLoaded() then
		task.defer(attachAppearance)
	else
		local connection: RBXScriptConnection? = nil
		connection = player.CharacterAppearanceLoaded:Connect(function(loadedCharacter)
			if loadedCharacter == character then
				if connection then connection:Disconnect() end
				attachAppearance()
			end
		end)
		table.insert(state.connections, connection)
	end
end

function Service:_attachPlayer(player: Player)
	if self.states[player.UserId] then return end
	local characterConnection = player.CharacterAdded:Connect(function(character)
		self:_attachCharacter(player, character)
	end)
	local state: PlayerState = {
		character = nil,
		connections = {characterConnection},
		appearanceReady = false,
		additions = {},
		lastSignalAt = {},
		signals = 0,
	}
	self.states[player.UserId] = state
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
			for _, connection in ipairs(state.connections) do connection:Disconnect() end
			self.states[player.UserId] = nil
		end
	end))
	for _, player in ipairs(Players:GetPlayers()) do self:_attachPlayer(player) end
	return true
end

function Service:GetStatus(): {[string]: any}
	local players = 0
	local trackedSignals = 0
	for _, state in pairs(self.states) do
		players += 1
		trackedSignals += state.signals
	end
	return {
		state = if self.started then "Ready" else "Stopped",
		trackedPlayers = players,
		totalSignals = self.totalSignals,
		suppressedSignals = self.suppressedSignals,
		trackedSignals = trackedSignals,
		lastError = self.lastError,
		mode = "DetectionOnly",
	}
end

function Service:Stop()
	for _, connection in ipairs(self.connections) do connection:Disconnect() end
	table.clear(self.connections)
	for _, state in pairs(self.states) do
		for _, connection in ipairs(state.connections) do connection:Disconnect() end
	end
	table.clear(self.states)
	self.started = false
end

return Service
