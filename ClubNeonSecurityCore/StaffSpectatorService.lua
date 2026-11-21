--!strict
-- Server-authoritative staff observation state. Camera presentation is handled
-- by the paired StarterPlayerScripts client adapter; this module owns authority.
local Players = game:GetService("Players")

local Service = {}
Service.__index = Service

local MAX_ACTIVE = 64
local MAX_TARGET_ID = 9007199254740991

local function livePlayer(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Player") and value.Parent == Players
end

local function validUserId(value: any): boolean
	return typeof(value) == "number" and value == value and value > 0
		and value < math.huge and value % 1 == 0 and value <= MAX_TARGET_ID
end

function Service.new(dependencies: {[string]: any})
	assert(typeof(dependencies) == "table" and type(dependencies.authorize) == "function",
		"StaffSpectatorService requires an authorization callback")
	return setmetatable({
		d = dependencies,
		active = {},
		movementSnapshots = {},
		stealthSnapshots = {},
		started = false,
		connections = {},
		entered = 0,
		switched = 0,
		exited = 0,
		denied = 0,
	}, Service)
end

function Service:_audit(actor: Player, target: Player?, action: string)
	if type(self.d.audit) == "function" then
		pcall(self.d.audit, actor.UserId, if target then target.UserId else 0, action)
	end
end

function Service:_authorized(actor: Player): boolean
	if not livePlayer(actor) then return false end
	local ok, allowed = pcall(self.d.authorize, actor.UserId, "GlobalModeration")
	return ok and allowed == true and livePlayer(actor)
end

function Service:_setStealth(actor: Player, enabled: boolean): boolean
	local userId = actor.UserId
	if not enabled then
		local snapshot = self.stealthSnapshots[userId]
		self.stealthSnapshots[userId] = nil
		if snapshot then
			if snapshot.connection then snapshot.connection:Disconnect() end
			for instance, values in pairs(snapshot.properties) do
				if typeof(instance) == "Instance" and instance.Parent
					and instance:IsDescendantOf(snapshot.character) then
					pcall(function()
						if values.kind == "BasePart" then
							instance.Transparency = values.transparency
							instance.CanCollide = values.canCollide
							instance.CanTouch = values.canTouch
							instance.CanQuery = values.canQuery
						else
							instance.Transparency = values.transparency
						end
					end)
				end
			end
		end
		if livePlayer(actor) then actor:SetAttribute("ClubNeonSpectatorStealth", false) end
		return true
	end

	local character = actor.Character
	if not character or not character.Parent then return false end
	local existing = self.stealthSnapshots[userId]
	if existing and existing.character == character then
		if livePlayer(actor) then actor:SetAttribute("ClubNeonSpectatorStealth", true) end
		return true
	end
	self:_setStealth(actor, false)
	local snapshot = {
		character = character,
		properties = {},
		connection = nil,
	}
	local function hide(instance: Instance)
		if snapshot.properties[instance] then return end
		if instance:IsA("BasePart") then
			snapshot.properties[instance] = {
				kind = "BasePart",
				transparency = instance.Transparency,
				canCollide = instance.CanCollide,
				canTouch = instance.CanTouch,
				canQuery = instance.CanQuery,
			}
			instance.Transparency = 1
			instance.CanCollide = false
			instance.CanTouch = false
			instance.CanQuery = false
		elseif instance:IsA("Decal") then
			snapshot.properties[instance] = {
				kind = "Decal",
				transparency = instance.Transparency,
			}
			instance.Transparency = 1
		end
	end
	for _, descendant in ipairs(character:GetDescendants()) do hide(descendant) end
	snapshot.connection = character.DescendantAdded:Connect(function(descendant)
		if self.stealthSnapshots[userId] == snapshot and actor.Character == character then
			hide(descendant)
		end
	end)
	self.stealthSnapshots[userId] = snapshot
	actor:SetAttribute("ClubNeonSpectatorStealth", true)
	return true
end

function Service:_registerMovement(actor: Player, humanoid: Humanoid)
	local authority = game:GetService("ServerStorage"):FindFirstChild("ClubNeonMovementAuthority")
	if not authority or not authority:IsA("BindableFunction") or authority.Parent ~= game:GetService("ServerStorage") then
		warn("[Club Neon][StaffSpectator] Movement authority unavailable; character guard may report spectator movement changes.")
		return false
	end
	local values = {
		WalkSpeed = humanoid.WalkSpeed,
		JumpPower = humanoid.JumpPower,
		JumpHeight = humanoid.JumpHeight,
	}
	local allRegistered = true
	for property, value in pairs(values) do
		local ok, accepted = pcall(function()
			return authority:Invoke("Register", actor.UserId, actor.UserId, property, value, "StaffSpectator", 120)
		end)
		if not ok or accepted ~= true then
			allRegistered = false
			warn("[Club Neon][StaffSpectator] Movement authorization registration failed for " .. property .. ".")
		end
	end
	return allRegistered
end

function Service:_freezeActor(actor: Player)
	local character = actor.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return false end
	self.movementSnapshots[actor.UserId] = {
		humanoid = humanoid,
		walkSpeed = humanoid.WalkSpeed,
		jumpPower = humanoid.JumpPower,
		jumpHeight = humanoid.JumpHeight,
		autoRotate = humanoid.AutoRotate,
		useJumpPower = humanoid.UseJumpPower,
		jumpingEnabled = humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping),
	}
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.AutoRotate = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	self:_registerMovement(actor, humanoid)
	actor:SetAttribute("ClubNeonSpectatorNoWorldActions", true)
	return true
end

function Service:_restoreActor(actor: Player)
	self:_setStealth(actor, false)
	local snapshot = self.movementSnapshots[actor.UserId]
	self.movementSnapshots[actor.UserId] = nil
	if snapshot then
		local humanoid = snapshot.humanoid
		if typeof(humanoid) == "Instance" and humanoid:IsA("Humanoid") and humanoid.Parent then
			pcall(function()
				humanoid.UseJumpPower = snapshot.useJumpPower
				humanoid.WalkSpeed = snapshot.walkSpeed
				humanoid.JumpPower = snapshot.jumpPower
				humanoid.JumpHeight = snapshot.jumpHeight
				humanoid.AutoRotate = snapshot.autoRotate
				humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, snapshot.jumpingEnabled)
			end)
			self:_registerMovement(actor, humanoid)
		end
	end
	if livePlayer(actor) then actor:SetAttribute("ClubNeonSpectatorNoWorldActions", false) end
end

function Service:_setTarget(actor: Player, target: Player): boolean
	if not livePlayer(actor) or not livePlayer(target) or actor == target then return false end
	local character = target.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not character.Parent or not humanoid or humanoid.Health <= 0 then return false end
	actor:SetAttribute("ClubNeonSpectatorTargetUserId", target.UserId)
	actor:SetAttribute("ClubNeonSpectatorActive", true)
	self.active[actor.UserId] = target.UserId
	return true
end

function Service:Enter(actor: Player, targetUserId: any, stealth: any?): (boolean, string)
	if stealth ~= nil and typeof(stealth) ~= "boolean" then return false, "Invalid stealth setting." end
	if not self:_authorized(actor) then self.denied += 1; return false, "Staff observation permission denied." end
	if self.active[actor.UserId] ~= nil then return false, "You are already observing; use SwitchTarget instead." end
	if not validUserId(targetUserId) then self.denied += 1; return false, "Invalid observation target." end
	local target = Players:GetPlayerByUserId(targetUserId)
	if not livePlayer(target) or target == actor then self.denied += 1; return false, "That player cannot be observed." end
	if self.active[actor.UserId] == nil then
		local count = 0
		for _ in pairs(self.active) do count += 1 end
		if count >= MAX_ACTIVE then return false, "The staff observation capacity is full." end
	end
	if not self:_setTarget(actor, target) then return false, "The target has no active character." end
	if not self:_freezeActor(actor) then
		self.active[actor.UserId] = nil
		actor:SetAttribute("ClubNeonSpectatorActive", false)
		actor:SetAttribute("ClubNeonSpectatorTargetUserId", 0)
		return false, "Your character is not ready for observation mode."
	end
	if stealth == true and not self:_setStealth(actor, true) then
		self.active[actor.UserId] = nil
		self:_restoreActor(actor)
		actor:SetAttribute("ClubNeonSpectatorActive", false)
		actor:SetAttribute("ClubNeonSpectatorTargetUserId", 0)
		return false, "Stealth mode could not be applied; observation was not started."
	end
	self.entered += 1
	self:_audit(actor, target, if stealth == true then "spectator-enter-stealth" else "spectator-enter")
	return true, if stealth == true then "Staff observation enabled in stealth mode." else "Staff observation enabled."
end

function Service:SwitchTarget(actor: Player, targetUserId: any): (boolean, string)
	if not self:_authorized(actor) then self.denied += 1; return false, "Staff observation permission denied." end
	if self.active[actor.UserId] == nil then return false, "Enter staff observation before switching targets." end
	if not validUserId(targetUserId) then self.denied += 1; return false, "Invalid observation target." end
	local target = Players:GetPlayerByUserId(targetUserId)
	if not livePlayer(target) or target == actor then self.denied += 1; return false, "That player cannot be observed." end
	if not self:_setTarget(actor, target) then return false, "The target has no active character." end
	self.switched += 1
	self:_audit(actor, target, "spectator-switch")
	return true, "Observation target changed."
end

function Service:SetStealth(actor: Player, enabled: any): (boolean, string)
	if not self:_authorized(actor) then self.denied += 1; return false, "Staff observation permission denied." end
	if self.active[actor.UserId] == nil then return false, "Enter staff observation before changing stealth mode." end
	if typeof(enabled) ~= "boolean" then return false, "Stealth must be enabled or disabled explicitly." end
	if not self:_setStealth(actor, enabled) then return false, "Your character is not ready for stealth mode." end
	local targetId = self.active[actor.UserId]
	local target = Players:GetPlayerByUserId(targetId)
	local action = if enabled then "spectator-stealth-enabled" else "spectator-stealth-disabled"
	self:_audit(actor, target, action)
	return true, if enabled then "Stealth mode enabled." else "Stealth mode disabled."
end

function Service:Exit(actor: Player, reason: string?): (boolean, string)
	if not livePlayer(actor) then return false, "A live staff player is required." end
	if self.active[actor.UserId] == nil then
		actor:SetAttribute("ClubNeonSpectatorActive", false)
		actor:SetAttribute("ClubNeonSpectatorTargetUserId", 0)
		return true, "Staff observation is already inactive."
	end
	local targetId = self.active[actor.UserId]
	local target = Players:GetPlayerByUserId(targetId)
	self.active[actor.UserId] = nil
	self:_restoreActor(actor)
	actor:SetAttribute("ClubNeonSpectatorActive", false)
	actor:SetAttribute("ClubNeonSpectatorTargetUserId", 0)
	self.exited += 1
	self:_audit(actor, target, if reason == "target-left" then "spectator-target-left" else "spectator-exit")
	return true, "Staff observation disabled."
end

function Service:GetState(actor: Player)
	if not self:_authorized(actor) then return false, nil end
	local targetId = self.active[actor.UserId]
	if not targetId then return true, {active = false, targetUserId = 0} end
	local target = Players:GetPlayerByUserId(targetId)
	if not livePlayer(target) then self:Exit(actor, "target-left"); return true, {active = false, targetUserId = 0} end
	return true, {active = true, targetUserId = targetId, targetName = target.Name,
		stealth = self.stealthSnapshots[actor.UserId] ~= nil}
end

function Service:GetStatus()
	local activeCount = 0
	local stealthCount = 0
	for _ in pairs(self.active) do activeCount += 1 end
	for _ in pairs(self.stealthSnapshots) do stealthCount += 1 end
	return {
		state = if self.started then "Ready" else "Stopped",
		activeObservers = activeCount,
		stealthObservers = stealthCount,
		capacity = MAX_ACTIVE,
		entered = self.entered,
		switched = self.switched,
		exited = self.exited,
		denied = self.denied,
		authority = "SecurityCore.Authorization",
		permission = "GlobalModeration",
		automaticEnforcement = false,
	}
end

function Service:Start(): boolean
	if self.started then return true end
	self.started = true
	table.insert(self.connections, Players.PlayerRemoving:Connect(function(leaving)
		local observersToExit = {}
		for actorId, targetId in pairs(self.active) do
			if actorId == leaving.UserId then
				local target = Players:GetPlayerByUserId(targetId)
				self:_audit(leaving, target, "spectator-staff-left")
				self:_restoreActor(leaving)
				self.active[actorId] = nil
			elseif targetId == leaving.UserId then
				local observer = Players:GetPlayerByUserId(actorId)
				if livePlayer(observer) then table.insert(observersToExit, observer) else self.active[actorId] = nil end
			end
		end
		for _, observer in ipairs(observersToExit) do self:Exit(observer, "target-left") end
	end))
	table.insert(self.connections, Players.PlayerAdded:Connect(function(player)
		player.CharacterRemoving:Connect(function()
			if self.active[player.UserId] ~= nil then self:Exit(player, "character-reset") end
		end)
	end))
	for _, player in ipairs(Players:GetPlayers()) do
		player.CharacterRemoving:Connect(function()
			if self.active[player.UserId] ~= nil then self:Exit(player, "character-reset") end
		end)
	end
	return true
end

function Service:Stop()
	for _, connection in ipairs(self.connections) do pcall(function() connection:Disconnect() end) end
	table.clear(self.connections)
	for actorId in pairs(self.active) do
		local actor = Players:GetPlayerByUserId(actorId)
		if livePlayer(actor) then
			self:_restoreActor(actor)
			actor:SetAttribute("ClubNeonSpectatorActive", false)
			actor:SetAttribute("ClubNeonSpectatorTargetUserId", 0)
		end
	end
	table.clear(self.active)
	table.clear(self.movementSnapshots)
	table.clear(self.stealthSnapshots)
	self.started = false
end

return Service
