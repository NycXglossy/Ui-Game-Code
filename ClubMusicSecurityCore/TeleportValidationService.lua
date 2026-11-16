--!strict
-- Server-only, per-server teleport authorization and verification.
-- This module never accepts client-created tickets and never enforces punishment.
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local TeleportValidationService = {}

local CAPACITY = 128
local DEFAULT_TTL = 8
local MAX_TTL = 15
local WORLD_LIMIT = 100000
local POSITION_TOLERANCE = 8
local ALLOWED_ORIGINS: {[string]: boolean} = {
	TikiTideSettings = true,
	KohlsAdmin = true,
	VIPZone = true,
	SpawnPad = true,
	GameTeleport = true,
}

type Ticket = {
	id: string,
	actorUserId: number,
	targetUserId: number,
	destination: Vector3,
	origin: string,
	createdAt: number,
	expiresAt: number,
}
local tickets: {[string]: Ticket} = {}
local ticketCount = 0
local started = false
local signalCallback: ((string, number, string) -> ())? = nil

local function finiteNumber(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local function validPosition(position: any): boolean
	if typeof(position) ~= "Vector3" then return false end
	return finiteNumber(position.X) and finiteNumber(position.Y) and finiteNumber(position.Z)
		and math.abs(position.X) <= WORLD_LIMIT
		and math.abs(position.Y) <= WORLD_LIMIT
		and math.abs(position.Z) <= WORLD_LIMIT
end

local function livePlayer(player: any): boolean
	return typeof(player) == "Instance" and player:IsA("Player")
		and player.Parent == Players and Players:GetPlayerByUserId(player.UserId) == player
end

local function characterReady(player: Player): (Model?, BasePart?)
	local character = player.Character
	if not character or not character:IsDescendantOf(workspace) then return nil, nil end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil, nil
	end
	return character, root
end

local function emit(signal: string, targetUserId: number, detail: string)
	if signalCallback then
		local ok = pcall(signalCallback, signal, targetUserId, string.sub(detail, 1, 160))
		if not ok then warn("[Tiki Tide][TeleportValidation] Signal callback failed.") end
	else
		warn("[Tiki Tide][TeleportValidation] " .. signal .. " target=" .. tostring(targetUserId) .. " detail=" .. string.sub(detail, 1, 160))
	end
end

local function prune(now: number)
	for id, ticket in pairs(tickets) do
		if ticket.expiresAt <= now then
			tickets[id] = nil
			ticketCount -= 1
		end
	end
end

function TeleportValidationService.Start(options: any?)
	if started then return true end
	if options ~= nil and typeof(options) ~= "table" then return false, "Invalid service options." end
	if options and options.onSignal ~= nil and typeof(options.onSignal) ~= "function" then
		return false, "Invalid signal callback."
	end
	signalCallback = options and options.onSignal or nil
	started = true
	Players.PlayerRemoving:Connect(function(player)
		for id, ticket in pairs(tickets) do
			if ticket.actorUserId == player.UserId or ticket.targetUserId == player.UserId then
				tickets[id] = nil
				ticketCount -= 1
			end
		end
	end)
	return true
end

-- Only trusted server scripts should call Begin after completing their own
-- entitlement, consent, and staff-permission checks.
function TeleportValidationService.Begin(actor: any, target: any, destination: any, origin: any, ttl: any)
	if not started then return nil, "Teleport validation is not started." end
	if not livePlayer(actor) or not livePlayer(target) then return nil, "Teleport participants are not active." end
	if typeof(origin) ~= "string" or not ALLOWED_ORIGINS[origin] then return nil, "Teleport origin is not authorized." end
	if not validPosition(destination) then return nil, "Teleport destination is invalid or outside world bounds." end
	local _, targetRoot = characterReady(target)
	if not targetRoot then return nil, "Target character is not ready." end
	local _, actorRoot = characterReady(actor)
	if actor == target and not actorRoot then return nil, "Teleporting character is not ready." end

	local lifetime = if finiteNumber(ttl) then math.clamp(ttl, 1, MAX_TTL) else DEFAULT_TTL
	local now = os.clock()
	prune(now)
	if ticketCount >= CAPACITY then return nil, "Teleport authorization capacity is busy." end

	local id = HttpService:GenerateGUID(false)
	tickets[id] = {
		id = id,
		actorUserId = actor.UserId,
		targetUserId = target.UserId,
		destination = destination,
		origin = origin,
		createdAt = now,
		expiresAt = now + lifetime,
	}
	ticketCount += 1
	return id
end

-- Complete consumes the ticket whether the observed destination matches or not.
-- This prevents retries/replays from reusing an authorization record.
function TeleportValidationService.Complete(ticketId: any, actor: any, target: any, observedPosition: any): (boolean, string?)
	if typeof(ticketId) ~= "string" or #ticketId > 64 then return false, "Invalid teleport ticket." end
	local ticket = tickets[ticketId]
	if not ticket then return false, "Teleport ticket is missing or already consumed." end
	tickets[ticketId] = nil
	ticketCount -= 1

	if ticket.expiresAt <= os.clock() then
		emit("TeleportTicketExpired", ticket.targetUserId, ticket.origin)
		return false, "Teleport authorization expired."
	end
	if not livePlayer(actor) or not livePlayer(target)
		or actor.UserId ~= ticket.actorUserId or target.UserId ~= ticket.targetUserId then
		emit("TeleportTicketIdentityMismatch", ticket.targetUserId, ticket.origin)
		return false, "Teleport authorization participant mismatch."
	end
	if not validPosition(observedPosition) then
		emit("TeleportObservedPositionInvalid", ticket.targetUserId, ticket.origin)
		return false, "Observed teleport position is invalid."
	end
	if (observedPosition - ticket.destination).Magnitude > POSITION_TOLERANCE then
		emit("TeleportDestinationMismatch", ticket.targetUserId, ticket.origin)
		return false, "Observed position did not match the authorized destination."
	end
	return true, ticket.origin
end

function TeleportValidationService.Cancel(ticketId: any)
	if typeof(ticketId) ~= "string" then return false end
	if tickets[ticketId] then
		tickets[ticketId] = nil
		ticketCount -= 1
		return true
	end
	return false
end

function TeleportValidationService.Status()
	prune(os.clock())
	return {
		started = started,
		activeTickets = ticketCount,
		capacity = CAPACITY,
		scope = "PerServerOnly",
		automaticEnforcement = false,
	}
end

return TeleportValidationService
