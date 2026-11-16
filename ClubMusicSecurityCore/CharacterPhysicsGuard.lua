--!strict
-- CharacterPhysicsGuard
-- Server-local, detection-only character movement and world gravity observer.
-- It never kicks, bans, teleports, or changes character properties.
-- All authorization checks are delegated to MovementAuthority; no persistent
-- storage or MemoryStore records are created by this module.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Service = {}
Service.__index = Service

local CHECK_DELAY = 0.18
local SIGNAL_COOLDOWN = 10
local SCALE_EPSILON = 0.08
local LIMITS = {
	WalkSpeed = {min = 0, max = 100},
	JumpPower = {min = 0, max = 250},
	JumpHeight = {min = 0, max = 100},
	WorldGravity = {min = 0, max = 500},
	BodyScale = {min = 0.1, max = 10},
}

local function finite(value: any): boolean
	return typeof(value) == "number" and value == value
		and value > -math.huge and value < math.huge
end

local function near(a: number, b: number, epsilon: number?): boolean
	return math.abs(a - b) <= (epsilon or 0.05)
end

local function getScaleValues(humanoid: Humanoid)
	local names = {"BodyHeightScale", "BodyWidthScale", "BodyDepthScale", "HeadScale"}
	local values = {}
	for _, name in ipairs(names) do
		local value = humanoid:FindFirstChild(name)
		if not value or not value:IsA("NumberValue") or not finite(value.Value) then
			return nil
		end
		values[name] = value.Value
	end
	return values
end

local function scaleFactor(current, baseline)
	if not current or not baseline then return nil end
	local total, count = 0, 0
	for name, baseValue in pairs(baseline) do
		if finite(baseValue) and math.abs(baseValue) > 0.001 then
			total += current[name] / baseValue
			count += 1
		end
	end
	if count ~= 4 then return nil end
	return total / count
end

function Service.new(dependencies)
	dependencies = dependencies or {}
	return setmetatable({
		d = dependencies,
		started = false,
		playerStates = {},
		characterAddedConnections = {},
		totalSignals = 0,
		suppressedSignals = 0,
		lastSignalAt = {},
		gravityBaseline = Workspace.Gravity,
		gravityChecks = 0,
	}, Service)
end

function Service:_emit(signal: string, player: Player?, detail: string)
	local subject = if player then tostring(player.UserId) else "server"
	local now = os.clock()
	local key = signal .. ":" .. subject
	local lastAt = self.lastSignalAt[key]
	if lastAt and now - lastAt < SIGNAL_COOLDOWN then
		self.suppressedSignals += 1
		return
	end
	self.lastSignalAt[key] = now
	self.totalSignals += 1
	if type(self.d.onSignal) == "function" then
		local ok, err = pcall(self.d.onSignal, signal, subject, string.sub(detail, 1, 100))
		if not ok then
			warn("[Tiki Tide][CharacterPhysicsGuard] Signal callback failed: " .. tostring(err))
		end
	else
		warn("[Tiki Tide][CharacterPhysicsGuard] " .. signal .. " subject=" .. subject .. " detail=" .. detail)
	end
end

function Service:_checkAuthority(targetUserId: number, property: string, value: number): boolean
	local authority = ServerStorage:FindFirstChild("TikiTideMovementAuthority")
	if not authority or not authority:IsA("BindableFunction") or authority.Parent ~= ServerStorage then
		return false
	end
	local ok, allowed = pcall(function()
		return authority:Invoke("Check", targetUserId, property, value)
	end)
	return ok and allowed == true
end

function Service:_checkNumeric(player: Player, state, property: string, current: number, previous: number)
	if not finite(current) or near(current, previous, 0.001) then return end
	local limits = LIMITS[property]
	local outsideLimits = limits ~= nil and (current < limits.min or current > limits.max)
	local authorized = self:_checkAuthority(player.UserId, property, current)
	if outsideLimits then
		self:_emit("movement_limit_exceeded", player,
			property .. "=" .. string.format("%.3f", current))
	elseif not authorized then
		self:_emit("unverified_movement_change", player,
			property .. "=" .. string.format("%.3f", current))
	end
end

function Service:_watchCharacter(player: Player, character: Model)
	local oldState = self.playerStates[player.UserId]
	if oldState then
		for _, connection in ipairs(oldState.connections) do
			connection:Disconnect()
		end
	end
	local state = {
		character = character,
		humanoid = nil,
		connections = {},
		baseline = nil,
		pending = {},
	}
	self.playerStates[player.UserId] = state

	task.delay(0.5, function()
		if not self.started or player.Parent ~= Players or player.Character ~= character
			or self.playerStates[player.UserId] ~= state then return end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then return end
		state.humanoid = humanoid
		state.baseline = {
			WalkSpeed = humanoid.WalkSpeed,
			JumpPower = humanoid.JumpPower,
			JumpHeight = humanoid.JumpHeight,
			Scales = getScaleValues(humanoid),
		}

		local function watchProperty(property: string)
			local connection = humanoid:GetPropertyChangedSignal(property):Connect(function()
				if state.pending[property] then return end
				state.pending[property] = true
				task.delay(CHECK_DELAY, function()
					state.pending[property] = nil
					if not self.started or player.Parent ~= Players
						or player.Character ~= character or state.humanoid ~= humanoid then return end
					local current = humanoid[property]
					local previous = state.baseline[property]
					if finite(current) and finite(previous) then
						self:_checkNumeric(player, state, property, current, previous)
						state.baseline[property] = current
					end
				end)
			end)
			table.insert(state.connections, connection)
		end

		watchProperty("WalkSpeed")
		watchProperty("JumpPower")
		watchProperty("JumpHeight")

		local function checkScaleChange()
			if state.pending.BodyScale then return end
			state.pending.BodyScale = true
			task.delay(CHECK_DELAY, function()
				state.pending.BodyScale = nil
				if not self.started or player.Parent ~= Players
					or player.Character ~= character or state.humanoid ~= humanoid then return end
				local current = getScaleValues(humanoid)
				local baseline = state.baseline.Scales
				if not current or not baseline then return end
				local factor = scaleFactor(current, baseline)
				if not factor or not finite(factor) then return end
				local minRatio, maxRatio = math.huge, -math.huge
				local outsideLimits = false
				for name, baseValue in pairs(baseline) do
					if math.abs(baseValue) > 0.001 then
						local ratio = current[name] / baseValue
						minRatio = math.min(minRatio, ratio)
						maxRatio = math.max(maxRatio, ratio)
						if ratio < LIMITS.BodyScale.min or ratio > LIMITS.BodyScale.max then
							outsideLimits = true
						end
					end
				end
				local inconsistentScale = maxRatio - minRatio > 0.15
				if math.abs(factor - 1) <= SCALE_EPSILON and not inconsistentScale and not outsideLimits then
					state.baseline.Scales = current
					return
				end
				local authorized = not inconsistentScale and not outsideLimits
					and self:_checkAuthority(player.UserId, "BodyScale", factor)
				if outsideLimits then
					self:_emit("movement_limit_exceeded", player, "BodyScale=" .. string.format("%.3f", factor))
				elseif inconsistentScale or not authorized then
					self:_emit("unverified_movement_change", player, "BodyScale=" .. string.format("%.3f", factor))
				end
				state.baseline.Scales = current
			end)
		end

		for _, name in ipairs({"BodyHeightScale", "BodyWidthScale", "BodyDepthScale", "HeadScale"}) do
			local value = humanoid:FindFirstChild(name)
			if value and value:IsA("NumberValue") then
				table.insert(state.connections, value.Changed:Connect(checkScaleChange))
			end
		end
	end)
end

function Service:_watchGravity()
	local connection = Workspace:GetPropertyChangedSignal("Gravity"):Connect(function()
		local previous = self.gravityBaseline
		task.delay(CHECK_DELAY, function()
			if not self.started then return end
			local current = Workspace.Gravity
			if not finite(current) or near(current, previous, 0.001) then return end
			self.gravityChecks += 1
			local limits = LIMITS.WorldGravity
			if current < limits.min or current > limits.max then
				self:_emit("world_physics_limit_exceeded", nil, "WorldGravity=" .. string.format("%.3f", current))
			elseif not self:_checkAuthority(0, "WorldGravity", current) then
				self:_emit("unverified_world_physics_change", nil,
					"WorldGravity=" .. string.format("%.3f", current))
			end
			self.gravityBaseline = current
		end)
	end)
	self.gravityConnection = connection
end

function Service:Start()
	if self.started then return true end
	self.started = true
	self.gravityBaseline = Workspace.Gravity
	self:_watchGravity()
	local function attachPlayer(player: Player)
		self.characterAddedConnections[player.UserId] = player.CharacterAdded:Connect(function(character)
			self:_watchCharacter(player, character)
		end)
		if player.Character then self:_watchCharacter(player, player.Character) end
	end
	self.playerAddedConnection = Players.PlayerAdded:Connect(attachPlayer)
	self.playerRemovingConnection = Players.PlayerRemoving:Connect(function(player)
		local characterConnection = self.characterAddedConnections[player.UserId]
		if characterConnection then characterConnection:Disconnect(); self.characterAddedConnections[player.UserId] = nil end
		local state = self.playerStates[player.UserId]
		if state then
			for _, connection in ipairs(state.connections) do connection:Disconnect() end
			self.playerStates[player.UserId] = nil
		end
		local suffix = ":" .. tostring(player.UserId)
		for key in pairs(self.lastSignalAt) do
			if string.sub(key, -#suffix) == suffix then self.lastSignalAt[key] = nil end
		end
	end)
	for _, player in ipairs(Players:GetPlayers()) do attachPlayer(player) end
	return true
end

function Service:GetStatus()
	local tracked = 0
	for _ in pairs(self.playerStates) do tracked += 1 end
	return {
		state = if self.started then "DetectionOnly" else "Stopped",
		trackedPlayers = tracked,
		totalSignals = self.totalSignals,
		suppressedSignals = self.suppressedSignals,
		gravityChecks = self.gravityChecks,
		automaticEnforcement = false,
		persistentStorage = false,
		memoryStoreWrites = 0,
	}
end

function Service:Stop()
	if not self.started then return end
	self.started = false
	if self.gravityConnection then self.gravityConnection:Disconnect(); self.gravityConnection = nil end
	if self.playerAddedConnection then self.playerAddedConnection:Disconnect(); self.playerAddedConnection = nil end
	if self.playerRemovingConnection then self.playerRemovingConnection:Disconnect(); self.playerRemovingConnection = nil end
	for _, state in pairs(self.playerStates) do
		for _, connection in ipairs(state.connections) do connection:Disconnect() end
	end
	table.clear(self.playerStates)
	for _, connection in pairs(self.characterAddedConnections) do connection:Disconnect() end
	table.clear(self.characterAddedConnections)
	table.clear(self.lastSignalAt)
end

return Service
