--!strict
-- CharacterPhysicsGuard
-- Server-local, detection-only character movement and world gravity observer.
-- It never kicks, bans, teleports, or changes character properties.
-- All authorization checks are delegated to MovementAuthority; no persistent
-- storage or MemoryStore records are created by this module.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local TeleportValidationService = require(script.Parent:WaitForChild("TeleportValidationService"))

local Service = {
Service.__index = Service

local CHECK_DELAY = 0.18
local MAX_MOVEMENT_SAMPLE_GAP_SECONDS = 3.5
local SIGNAL_COOLDOWN = 10
local SCALE_EPSILON = 0.08
local LIMITS = {
	WalkSpeed = {min = 0, max = 100},
	JumpPower = {min = 0, max = 300},
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
		-- Aggregate-only movement sampling. No positions or per-player histories are retained.
		movementSamples = 0,
		movementSampleGaps = 0,
		movementSampleInvalid = 0,
		movementSampleDeferred = 0,
		movementSampleIntervalCurrent = 0.5,
		movementAuthorizedTeleports = 0,
		movementSpeedBands = {under1 = 0, under4 = 0, under8 = 0, under16 = 0, under32 = 0, over32 = 0},
		-- Separate aggregate axes support later horizontal-speed and vertical/fly analysis.
		-- These are measurement bins only; no thresholds or enforcement consume them.
		movementHorizontalSpeedBands = {under1 = 0, under4 = 0, under8 = 0, under16 = 0, under32 = 0, over32 = 0},
		movementVerticalSpeedBands = {under1 = 0, under4 = 0, under8 = 0, under16 = 0, under32 = 0, over32 = 0},
		movementContexts = {grounded = 0, airborne = 0, seated = 0, other = 0},
		movementOwners = {server = 0, client = 0, unknown = 0},
		movementLatencyBands = {under50ms = 0, under100ms = 0, under200ms = 0, over200ms = 0, unknown = 0},
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

	-- Custom rigs may finish assembling after CharacterAdded. Wait a bounded
	-- interval for the Humanoid instead of silently skipping the whole observer.
	task.spawn(function()
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not humanoid or not humanoid:IsA("Humanoid") then return end
		if not self.started or player.Parent ~= Players or player.Character ~= character
			or self.playerStates[player.UserId] ~= state then return end
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

		-- Observe only sustained extreme assembly motion. Ordinary running,
		-- jumping, and seated movement are intentionally below these thresholds.
		local rootPart = character:WaitForChild("HumanoidRootPart", 10)
		-- WaitForChild yields; re-check lifecycle state before attaching any
		-- late connections so respawn/shutdown cannot leave stale observers.
		if not self.started or player.Parent ~= Players or player.Character ~= character
			or self.playerStates[player.UserId] ~= state then return end
		if rootPart and rootPart:IsA("BasePart") then
			-- Passive server-observed displacement sampling for later baseline measurement.
			-- This is not an anomaly detector: no threshold, signal, correction, or enforcement
			-- is attached. Only the immediately previous position is retained per character.
			task.spawn(function()
				local previousPosition: Vector3? = nil
				local previousAt: number? = nil
				while self.started and player.Parent == Players and player.Character == character
					and self.playerStates[player.UserId] == state do
					local sampleInterval = 0.5
					if type(self.d.getMovementSampleInterval) == "function" then
						local intervalOk, intervalValue = pcall(self.d.getMovementSampleInterval)
						if intervalOk and finite(intervalValue) then sampleInterval = math.clamp(intervalValue, 0.5, 3.0) end
					end
					self.movementSampleIntervalCurrent = sampleInterval
					task.wait(sampleInterval)
					if not self.started or player.Parent ~= Players or player.Character ~= character
						or self.playerStates[player.UserId] ~= state or not rootPart:IsDescendantOf(character) then
						break
					end
					local now = os.clock()
					local position = rootPart.Position
					if not finite(position.X) or not finite(position.Y) or not finite(position.Z) then
						self.movementSampleInvalid += 1
						previousPosition, previousAt = nil, nil
						continue
					end
					-- A ticketed teleport is verified by the existing server-only
					-- TeleportValidationService. Consume its one-use marker and reset
					-- the displacement baseline instead of counting the CFrame move
					-- as ordinary movement. No exemption is created by the client.
					local teleportCheckOk, recentlyTeleported = pcall(
						TeleportValidationService.IsRecentlyTeleported, player, character
					)
					if teleportCheckOk and recentlyTeleported == true then
						self.movementAuthorizedTeleports += 1
						previousPosition, previousAt = position, now
						continue
					end
					local sampleAllowed = true
					if type(self.d.allowMovementSample) == "function" then
						local budgetOk, budgetResult = pcall(self.d.allowMovementSample)
						if budgetOk then sampleAllowed = budgetResult == true end
					end
					if not sampleAllowed then
						self.movementSampleDeferred = math.min(1000000000, self.movementSampleDeferred + 1)
						-- Keep the baseline fresh while optional measurement is deferred so
						-- the next accepted sample never treats the skipped interval as movement.
						previousPosition, previousAt = position, now
						continue
					end
					if previousPosition and previousAt then
						local elapsed = now - previousAt
						if elapsed < 0.2 or elapsed > MAX_MOVEMENT_SAMPLE_GAP_SECONDS then
							self.movementSampleGaps += 1
						else
							local displacement = position - previousPosition
						local observedSpeed = displacement.Magnitude / elapsed
						local horizontalSpeed = Vector3.new(displacement.X, 0, displacement.Z).Magnitude / elapsed
						local verticalSpeed = math.abs(displacement.Y) / elapsed
						self.movementSamples += 1
						local function incrementSpeedBand(bands, speed: number)
							if speed < 1 then bands.under1 += 1
							elseif speed < 4 then bands.under4 += 1
							elseif speed < 8 then bands.under8 += 1
							elseif speed < 16 then bands.under16 += 1
							elseif speed < 32 then bands.under32 += 1
							else bands.over32 += 1 end
						end
						incrementSpeedBand(self.movementSpeedBands, observedSpeed)
						incrementSpeedBand(self.movementHorizontalSpeedBands, horizontalSpeed)
						incrementSpeedBand(self.movementVerticalSpeedBands, verticalSpeed)

							local context = "other"
						if humanoid.SeatPart ~= nil then context = "seated"
						elseif humanoid.FloorMaterial == Enum.Material.Air then context = "airborne"
						elseif humanoid.FloorMaterial ~= Enum.Material.Air then context = "grounded" end
						self.movementContexts[context] += 1

							local ownerBucket = "unknown"
						local ownerOk, owner = pcall(function() return rootPart:GetNetworkOwner() end)
						if ownerOk then ownerBucket = if owner == nil then "server" elseif owner == player then "client" else "unknown" end
						self.movementOwners[ownerBucket] += 1

							local latencyBucket = "unknown"
						local pingOk, ping = pcall(function() return player:GetNetworkPing() end)
						if pingOk and finite(ping) and ping >= 0 then
							local milliseconds = ping * 1000
						latencyBucket = if milliseconds < 50 then "under50ms" elseif milliseconds < 100 then "under100ms" elseif milliseconds < 200 then "under200ms" else "over200ms"
						end
						self.movementLatencyBands[latencyBucket] += 1
						end
					end
					previousPosition, previousAt = position, now
				end
			end)

			local function checkVelocity(property: string, threshold: number, signal: string)
				if state.pending[property] then return end
				state.pending[property] = true
				task.delay(CHECK_DELAY, function()
					state.pending[property] = nil
					if not self.started or player.Parent ~= Players
						or player.Character ~= character or state.humanoid ~= humanoid
						or humanoid.SeatPart ~= nil then return end
					local magnitude = if property == "AssemblyLinearVelocity"
						then rootPart.AssemblyLinearVelocity.Magnitude
						else rootPart.AssemblyAngularVelocity.Magnitude
					if magnitude <= threshold then return end
					if self:_checkAuthority(player.UserId, "Fling", "ANY") then return end
					self:_emit(signal, player, property .. "=" .. string.format("%.1f", magnitude))
				end)
			end
			table.insert(state.connections, rootPart:GetPropertyChangedSignal("AssemblyLinearVelocity"):Connect(function()
				checkVelocity("AssemblyLinearVelocity", 300, "suspicious_physics_velocity")
			end))
			table.insert(state.connections, rootPart:GetPropertyChangedSignal("AssemblyAngularVelocity"):Connect(function()
				checkVelocity("AssemblyAngularVelocity", 120, "suspicious_physics_rotation")
			end))
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
		movementMeasurement = {
			sampleIntervalSeconds = self.movementSampleIntervalCurrent,
			maximumAcceptedSampleGapSeconds = MAX_MOVEMENT_SAMPLE_GAP_SECONDS,
			samples = self.movementSamples,
			deferredSamples = self.movementSampleDeferred,
			gaps = self.movementSampleGaps,
			invalidSamples = self.movementSampleInvalid,
			authorizedTeleportSamples = self.movementAuthorizedTeleports,
			observedSpeedBandsStudsPerSecond = table.clone(self.movementSpeedBands),
			horizontalSpeedBandsStudsPerSecond = table.clone(self.movementHorizontalSpeedBands),
			verticalSpeedBandsStudsPerSecond = table.clone(self.movementVerticalSpeedBands),
			contexts = table.clone(self.movementContexts),
			networkOwners = table.clone(self.movementOwners),
			latencyBands = table.clone(self.movementLatencyBands),
			storesPositions = false,
			anomalyThresholdsEnabled = false,
		},
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
