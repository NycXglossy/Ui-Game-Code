--!strict
-- Detection-only avatar/accessory validation. Observations are evidence, not proof.
-- This service never kicks, bans, strips, or rewrites player avatars.

local Players = game:GetService("Players")

local Service = {}
Service.__index = Service

local MAX_ACCESSORIES = 50
local MAX_TRACKED_TOOLS = 100
local MAX_PARTS_PER_ACCESSORY = 32
local MAX_HANDLE_AXIS = 30
local ADD_WINDOW_SECONDS = 10
local MAX_ADDITIONS_PER_WINDOW = 12

type PlayerState = {
	character: Model?,
	playerConnections: {RBXScriptConnection},
	characterConnections: {RBXScriptConnection},
	inventoryContainers: {[Instance]: boolean},
	knownTools: {[Tool]: boolean},
	presentTools: {[Tool]: boolean},
	knownAccessories: {[Accessory]: boolean},
	observedAccessoryHandles: {[Accessory]: BasePart},
	accessoryObservationCapSignaled: boolean,
	toolCapSignaled: boolean,
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

function Service:_observeToolAdded(player: Player, tool: Tool)
	local state = self.states[player.UserId]
	if not state or not tool:IsA("Tool") then return end
	local known = state.knownTools[tool] == true
	if not known then
		local count = 0
		for _ in pairs(state.knownTools) do count += 1 end
		if count >= MAX_TRACKED_TOOLS then
			if not state.toolCapSignaled then
				state.toolCapSignaled = true
				self:_signal(player, "tool_inventory_observation_cap", tostring(MAX_TRACKED_TOOLS))
			end
			return
		end
		state.knownTools[tool] = true
		if state.appearanceReady then
			self:_signal(player, "tool_added_after_appearance", tool.Name)
		end
	elseif state.presentTools[tool] == false and state.appearanceReady then
		self:_signal(player, "tool_returned_to_inventory", tool.Name)
	end
	state.presentTools[tool] = true
end

function Service:_observeToolRemoved(player: Player, tool: Tool)
	local state = self.states[player.UserId]
	if not state or not state.knownTools[tool] then return end
	task.defer(function()
		if self.states[player.UserId] ~= state then return end
		local backpack = player:FindFirstChildOfClass("Backpack")
		local starterGear = player:FindFirstChild("StarterGear")
		if tool.Parent == player.Character or (backpack and tool.Parent == backpack)
			or (starterGear and tool.Parent == starterGear) then return end
		if state.presentTools[tool] then
			state.presentTools[tool] = nil
			state.knownTools[tool] = nil
			if state.appearanceReady then
				self:_signal(player, "tool_removed_from_inventory", tool.Name)
			end
		end
	end)
end

function Service:_attachToolContainer(player: Player, container: Instance, connections: {RBXScriptConnection})
	local state = self.states[player.UserId]
	if not state or state.inventoryContainers[container] then return end
	state.inventoryContainers[container] = true
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Tool") then self:_observeToolAdded(player, child) end
	end
	table.insert(connections, container.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then self:_observeToolAdded(player, child) end
	end))
	table.insert(connections, container.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then self:_observeToolRemoved(player, child) end
	end))
end

function Service:_inspectAccessory(player: Player, accessory: Accessory, runtimeAdded: boolean)
	local state = self.states[player.UserId]
	if not state or not accessory:IsA("Accessory") then return end
	state.knownAccessories[accessory] = true
	if state.observedAccessoryHandles[accessory] == nil then
		local tracked = 0
		for _ in pairs(state.observedAccessoryHandles) do tracked += 1 end
		if tracked >= MAX_ACCESSORIES then
			if not state.accessoryObservationCapSignaled then
				state.accessoryObservationCapSignaled = true
				self:_signal(player, "avatar_accessory_observation_cap", tostring(MAX_ACCESSORIES))
			end
		else
			state.observedAccessoryHandles[accessory] = accessory:FindFirstChild("Handle") :: BasePart?
		end
	end
	if runtimeAdded and state.appearanceReady then
		self:_signal(player, "avatar_accessory_added_after_appearance", accessory.Name)
	end

	local partCount = 0
	for _, descendant in ipairs(accessory:GetDescendants()) do
		if descendant:IsA("BasePart") then
			partCount += 1
			if partCount > MAX_PARTS_PER_ACCESSORY then
				self:_signal(player, "avatar_accessory_excessive_parts", accessory.Name)
				break
			end
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
	if state.observedAccessoryHandles[accessory] == handle then
		table.insert(state.characterConnections, handle:GetPropertyChangedSignal("Size"):Connect(function()
			if self.states[player.UserId] == state and accessory.Parent == state.character then
				self:_signal(player, "avatar_accessory_handle_size_changed", accessory.Name)
			end
		end))
		table.insert(state.characterConnections, handle:GetPropertyChangedSignal("CanCollide"):Connect(function()
			if self.states[player.UserId] == state and accessory.Parent == state.character then
				self:_signal(player, "avatar_accessory_handle_collision_changed", accessory.Name)
			end
		end))
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
	local state = self.states[player.UserId]
	if not state then return end
	for _, connection in ipairs(state.characterConnections) do connection:Disconnect() end
	table.clear(state.characterConnections)

	if state.character then state.inventoryContainers[state.character] = nil end
	state.character = character
	state.appearanceReady = false
	table.clear(state.knownAccessories)
	table.clear(state.observedAccessoryHandles)
	table.clear(state.additions)
	table.clear(state.lastSignalAt)

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
			elseif child:IsA("Tool") then
				self:_observeToolAdded(player, child)
			end
		end
		if count > MAX_ACCESSORIES then
			self:_signal(player, "avatar_accessory_count_exceeded", tostring(count))
		end
	end

	self:_attachToolContainer(player, character, state.characterConnections)
	table.insert(state.characterConnections, character.ChildAdded:Connect(function(child)
		if child:IsA("Accessory") then
			self:_inspectAccessory(player, child, state.appearanceReady)
		end
	end))
	table.insert(state.characterConnections, character.ChildRemoved:Connect(function(child)
		if child:IsA("Accessory") and state.knownAccessories[child] then
			task.defer(function()
				if self.states[player.UserId] == state and child.Parent ~= character then
					state.knownAccessories[child] = nil
					if state.appearanceReady then
						self:_signal(player, "avatar_accessory_removed_after_appearance", child.Name)
					end
				end
			end)
		end
	end))

	table.insert(state.characterConnections, character.AncestryChanged:Connect(function(_, parent)
		if parent == nil and self.states[player.UserId] == state then
			for _, connection in ipairs(state.characterConnections) do connection:Disconnect() end
			table.clear(state.characterConnections)
			state.inventoryContainers[character] = nil
			table.clear(state.knownAccessories)
			table.clear(state.observedAccessoryHandles)
			state.character = nil
			state.appearanceReady = false
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
		table.insert(state.characterConnections, connection)
	end
end

function Service:_attachPlayer(player: Player)
	if self.states[player.UserId] then return end
	local state: PlayerState = {
		character = nil,
		playerConnections = {},
		characterConnections = {},
		inventoryContainers = {},
		knownTools = {},
		presentTools = {},
		knownAccessories = {},
		observedAccessoryHandles = {},
		accessoryObservationCapSignaled = false,
		toolCapSignaled = false,
		appearanceReady = false,
		additions = {},
		lastSignalAt = {},
		signals = 0,
	}
	self.states[player.UserId] = state
	local function attachInventoryContainer(container: Instance)
		if container:IsA("Backpack") or container.Name == "StarterGear" then
			self:_attachToolContainer(player, container, state.playerConnections)
		end
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then attachInventoryContainer(backpack) end
	local starterGear = player:FindFirstChild("StarterGear")
	if starterGear then attachInventoryContainer(starterGear) end
	table.insert(state.playerConnections, player.ChildAdded:Connect(attachInventoryContainer))
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
			for _, connection in ipairs(state.playerConnections) do connection:Disconnect() end
			for _, connection in ipairs(state.characterConnections) do connection:Disconnect() end
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
		for _, connection in ipairs(state.playerConnections) do connection:Disconnect() end
		for _, connection in ipairs(state.characterConnections) do connection:Disconnect() end
	end
	table.clear(self.states)
	self.started = false
end

return Service
