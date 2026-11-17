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
	actor:SetAttribute("TikiTideSpectatorNoWorldActions", true)
	return true
end

function Service:_restoreActor(actor: Player)
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
		end
	end
	if livePlayer(actor) then actor:SetAttribute("TikiTideSpectatorNoWorldActions", false) end
end

function Service:_setTarget(actor: Player, target: Player): boolean
	if not livePlayer(actor) or not livePlayer(target) or actor == target then return false end
	local character = target.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not character.Parent or not humanoid or humanoid.Health <= 0 then return false end
	actor:SetAttribute("TikiTideSpectatorTargetUserId", target.UserId)
	actor:SetAttribute("TikiTideSpectatorActive", true)
	self.active[actor.UserId] = target.UserId
	return true
end

function Service:Enter(actor: Player, targetUserId: any): (boolean, string)
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
		actor:SetAttribute("TikiTideSpectatorActive", false)
		actor:SetAttribute("TikiTideSpectatorTargetUserId", 0)
		return false, "Your character is not ready for observation mode."
	end
	self.entered += 1
	self:_audit(actor, target, "spectator-enter")
	return true, "Staff observation enabled."
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

function Service:Exit(actor: Player, reason: string?): (boolean, string)
	if not livePlayer(actor) then return false, "A live staff player is required." end
	if self.active[actor.UserId] == nil then
		actor:SetAttribute("TikiTideSpectatorActive", false)
		actor:SetAttribute("TikiTideSpectatorTargetUserId", 0)
		return true, "Staff observation is already inactive."
	end
	local targetId = self.active[actor.UserId]
	local target = Players:GetPlayerByUserId(targetId)
	self.active[actor.UserId] = nil
	self:_restoreActor(actor)
	actor:SetAttribute("TikiTideSpectatorActive", false)
	actor:SetAttribute("TikiTideSpectatorTargetUserId", 0)
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
	return true, {active = true, targetUserId = targetId, targetName = target.Name}
end

function Service:GetStatus()
	local activeCount = 0
	for _ in pairs(self.active) do activeCount += 1 end
	return {
		state = if self.started then "Ready" else "Stopped",
		activeObservers = activeCount,
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
			actor:SetAttribute("TikiTideSpectatorActive", false)
			actor:SetAttribute("TikiTideSpectatorTargetUserId", 0)
		end
	end
	table.clear(self.active)
	table.clear(self.movementSnapshots)
	self.started = false
end

return Service
