--!strict
-- Server-side honeypots for detecting interaction with isolated decoy remotes.
-- A hit is evidence for review only: this module never enforces or changes gameplay.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Service = {}
Service.__index = Service

local FOLDER_NAME = "TikiTideSecurityDecoys"
local DECOYS = {
	{ name = "TTHP_AdminPrivilegeEvent", kind = "RemoteEvent", signal = "honeypot_admin_privilege_remote" },
	{ name = "TTHP_PurchaseReceiptFunction", kind = "RemoteFunction", signal = "honeypot_purchase_receipt_remote" },
	{ name = "TTHP_VIPEntitlementEvent", kind = "RemoteEvent", signal = "honeypot_vip_entitlement_remote" },
	{ name = "TTHP_ModerationActionFunction", kind = "RemoteFunction", signal = "honeypot_moderation_action_remote" },
}
local COOLDOWN_SECONDS = 5
local MAX_SUBJECTS = 256
local MAX_USER_ID = 9007199254740991

local function validUserId(value: any): boolean
	return typeof(value) == "number" and value == value and value > 0
		and value < math.huge and value % 1 == 0 and value <= MAX_USER_ID
end

function Service.new(dependencies: {[string]: any})
	assert(typeof(dependencies) == "table", "HoneypotManager dependencies are required")
	assert(type(dependencies.recordThreat) == "function", "HoneypotManager requires recordThreat")
	assert(type(dependencies.recordReplay) == "function", "HoneypotManager requires recordReplay")
	return setmetatable({
		d = dependencies,
		started = false,
		folder = nil,
		connections = {},
		lastHitByUser = {},
		totalHits = 0,
		suppressedHits = 0,
		eventHits = 0,
		functionHits = 0,
		lastHitAt = 0,
	}, Service)
end

function Service:_record(player: Player, kind: string, signal: string)
	if not self.started or player.Parent ~= Players or not validUserId(player.UserId) then return end
	local now = os.clock()
	local key = tostring(player.UserId)
	local previous = self.lastHitByUser[key]
	if previous and now - previous < COOLDOWN_SECONDS then
		self.suppressedHits = math.min(1000000000, self.suppressedHits + 1)
		return
	end

	if not previous then
		local count, oldestKey, oldestAt = 0, nil, math.huge
		for existingKey, lastAt in pairs(self.lastHitByUser) do
			count += 1
			if lastAt < oldestAt then oldestAt = lastAt; oldestKey = existingKey end
		end
		if count >= MAX_SUBJECTS and oldestKey then self.lastHitByUser[oldestKey] = nil end
	end
	self.lastHitByUser[key] = now
	self.totalHits = math.min(1000000000, self.totalHits + 1)
	self.lastHitAt = now
	if kind == "RemoteEvent" then
		self.eventHits = math.min(1000000000, self.eventHits + 1)
	else
		self.functionHits = math.min(1000000000, self.functionHits + 1)
	end

	pcall(self.d.recordThreat, signal, player.UserId, "HoneypotManager", "Warning")
	pcall(self.d.recordReplay, signal, player.UserId, kind)
end

function Service:Start(): boolean
	if self.started then return true end
	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if existing and not existing:IsA("Folder") then
		warn("[Tiki Tide][Honeypot] Decoy folder name is occupied by a non-Folder.")
		return false
	end
	if existing then
		warn("[Tiki Tide][Honeypot] Refusing to replace an existing decoy folder.")
		return false
	end

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	for _, decoy in ipairs(DECOYS) do
		if decoy.kind == "RemoteEvent" then
			local remote = Instance.new("RemoteEvent")
			remote.Name = decoy.name
			remote.OnServerEvent:Connect(function(player)
				self:_record(player, decoy.kind, decoy.signal)
			end)
			remote.Parent = folder
		else
			local remote = Instance.new("RemoteFunction")
			remote.Name = decoy.name
			remote.OnServerInvoke = function(player)
				self:_record(player, decoy.kind, decoy.signal)
				return false, "Request unavailable."
			end
			remote.Parent = folder
		end
	end

	folder.Parent = ReplicatedStorage
	self.folder = folder
	self.started = true
	table.insert(self.connections, Players.PlayerRemoving:Connect(function(player)
		self.lastHitByUser[tostring(player.UserId)] = nil
	end))
	return true
end

function Service:GetStatus()
	local subjects = 0
	for _ in pairs(self.lastHitByUser) do subjects += 1 end
	return {
		state = if self.started then "Observing" else "Stopped",
		scope = "ServerLocal",
		decoyFolderPresent = self.folder ~= nil and self.folder.Parent == ReplicatedStorage,
		decoyRemoteCount = if self.started then #DECOYS else 0,
		totalHits = self.totalHits,
		remoteEventHits = self.eventHits,
		remoteFunctionHits = self.functionHits,
		suppressedHits = self.suppressedHits,
		trackedSubjects = subjects,
		maxTrackedSubjects = MAX_SUBJECTS,
		lastHitAgeSeconds = if self.lastHitAt > 0 then math.max(0, os.clock() - self.lastHitAt) else nil,
		automaticEnforcement = false,
		persistentWrites = 0,
		crossServerSharing = false,
	}
end

function Service:Stop()
	self.started = false
	for _, connection in ipairs(self.connections) do connection:Disconnect() end
	table.clear(self.connections)
	if self.folder and self.folder.Parent then self.folder:Destroy() end
	self.folder = nil
	table.clear(self.lastHitByUser)
end

return Service
