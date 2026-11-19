--!strict
-- Tiki Tide Social Actions. Place in ServerScriptService.
-- Server-authoritative requests, invitations, entitlement checks and animation playback.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")

local configFolder = script.Parent:FindFirstChild("TikiTideSocialActions")
local configModule = configFolder and configFolder:FindFirstChild("AnimationConfig")
assert(configModule and configModule:IsA("ModuleScript"), "[Tiki Tide Social] Missing AnimationConfig ModuleScript.")
local config = require(configModule)

local REMOTE_FOLDER = "TikiTideSocialRemotes"
local folder = ReplicatedStorage:FindFirstChild(REMOTE_FOLDER)
if folder and not folder:IsA("Folder") then error("[Tiki Tide Social] Remote folder name is occupied.") end
if not folder then folder = Instance.new("Folder"); folder.Name = REMOTE_FOLDER; folder.Parent = ReplicatedStorage end
local request = folder:FindFirstChild("Request")
if request and not request:IsA("RemoteEvent") then error("[Tiki Tide Social] Request has wrong class.") end
if not request then request = Instance.new("RemoteEvent"); request.Name = "Request"; request.Parent = folder end
local event = folder:FindFirstChild("Event")
if event and not event:IsA("RemoteEvent") then error("[Tiki Tide Social] Event has wrong class.") end
if not event then event = Instance.new("RemoteEvent"); event.Name = "Event"; event.Parent = folder end
local requestRemote = request :: RemoteEvent
local eventRemote = event :: RemoteEvent

local INVITE_TTL = 20
local MAX_DISTANCE = 12
local ACTION_COOLDOWN = 2
local INVITE_COOLDOWN = 5
local INBOUND_COOLDOWN = 3
local MAX_SAFE_INTEGER = 9007199254740991

type Invite = {id: string, from: number, to: number, action: string, expiresAt: number}
local invitesById: {[string]: Invite} = {}
local inviteBySender: {[number]: string} = {}
local inviteByTarget: {[number]: string} = {}
local lastActionAt: {[number]: number} = {}
local lastInviteAt: {[number]: number} = {}
local lastInboundAt: {[number]: number} = {}
local activeTracks: {[number]: {AnimationTrack}} = {}
local lastIngressAt: {[number]: number} = {}
local ingressTokens: {[number]: number} = {}
local MAX_TOKENS = 12
local REFILL_PER_SECOND = 4

local function recordSecuritySignal(player: Player, signal: string, detail: string)
	local replay = ServerStorage:FindFirstChild("TikiTideSecurityReplay")
	if replay and replay:IsA("BindableFunction") then
		pcall(function()
			replay:Invoke("Record", signal, player.UserId, 0, "Warning", "TikiTideSocialActions", {detail = string.sub(detail, 1, 100)})
		end)
	end
end

local function notify(player: Player, message: string, kind: string?)
	if player.Parent == Players then eventRemote:FireClient(player, "Notice", message, kind or "info") end
end

local function access(player: Player): boolean
	return player.Parent == Players and player:GetAttribute("HasTikiTideAccess") == true
end

local function vip(player: Player): boolean
	return player.Parent == Players and (player:GetAttribute("IsVIP") == true or player:GetAttribute("IsVVIP") == true or player:GetAttribute("HasTikiTideAccess") == true)
end

local function consumeIngress(player: Player): boolean
	local now = os.clock()
	local previous = lastIngressAt[player.UserId] or now
	local tokens = math.min(MAX_TOKENS, (ingressTokens[player.UserId] or MAX_TOKENS) + math.max(0, now - previous) * REFILL_PER_SECOND)
	lastIngressAt[player.UserId] = now
	if tokens < 1 then ingressTokens[player.UserId] = tokens; return false end
	ingressTokens[player.UserId] = tokens - 1
	return true
end

local function getRig(player: Player): (Model?, Humanoid?, Animator?, BasePart?)
	local character = player.Character
	if not character or character.Parent == nil then return nil, nil, nil, nil end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return character, nil, nil, nil end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then return character, humanoid, nil, nil end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	return character, humanoid, animator, root
end

local function closeEnough(a: Player, b: Player): boolean
	local _, ah, _, ar = getRig(a)
	local _, bh, _, br = getRig(b)
	return ah ~= nil and bh ~= nil and ar ~= nil and br ~= nil and (ar.Position - br.Position).Magnitude <= MAX_DISTANCE
end

local function stopOwnedTracks(userId: number)
	local tracks = activeTracks[userId]
	if not tracks then return end
	activeTracks[userId] = nil
	for _, track in ipairs(tracks) do pcall(function() track:Stop(0.15); track:Destroy() end) end
end

local function playTrack(player: Player, assetId: any): boolean
	if typeof(assetId) ~= "number" or assetId % 1 ~= 0 or assetId < 1 or assetId > MAX_SAFE_INTEGER then return false end
	local _, humanoid, animator = getRig(player)
	if not humanoid or not animator then return false end
	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. tostring(assetId)
	local ok, track = pcall(function() return animator:LoadAnimation(animation) end)
	animation:Destroy()
	if not ok or not track then return false end
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = false
	local owned = activeTracks[player.UserId] or {}
	activeTracks[player.UserId] = owned
	table.insert(owned, track)
	track.Stopped:Connect(function()
		local current = activeTracks[player.UserId]
		if current then
			for index = #current, 1, -1 do if current[index] == track then table.remove(current, index) end end
			if #current == 0 then activeTracks[player.UserId] = nil end
		end
		track:Destroy()
	end)
	local played = pcall(function() track:Play(0.2, 1, 1) end)
	if not played then
		stopOwnedTracks(player.UserId)
		return false
	end
	return true
end

local function clearInvite(id: string, reason: string?)
	local invite = invitesById[id]
	if not invite then return end
	invitesById[id] = nil
	if inviteBySender[invite.from] == id then inviteBySender[invite.from] = nil end
	if inviteByTarget[invite.to] == id then inviteByTarget[invite.to] = nil end
	local sender = Players:GetPlayerByUserId(invite.from)
	local target = Players:GetPlayerByUserId(invite.to)
	if reason and sender then notify(sender, reason) end
	if target then eventRemote:FireClient(target, "InviteClosed", id) end
end

local function clearPlayerInvites(userId: number)
	local ids = {}
	for id, invite in pairs(invitesById) do
		if invite.from == userId or invite.to == userId then table.insert(ids, id) end
	end
	for _, id in ipairs(ids) do clearInvite(id, "The other player is no longer available.") end
end

local function validatePlayerId(value: any): Player?
	if typeof(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge
		or value % 1 ~= 0 or value < 1 or value > MAX_SAFE_INTEGER then return nil end
	return Players:GetPlayerByUserId(value)
end

local function playSolo(player: Player, action: string)
	if not access(player) then notify(player, "Tiki Tide access is required.", "error"); return end
	local now = os.clock()
	local previousAction = lastActionAt[player.UserId] or 0
	if previousAction > 0 and now - previousAction < ACTION_COOLDOWN then notify(player, "Please wait before starting another social action."); return end
	if action ~= "Dance1" and action ~= "Dance2" and action ~= "VIPDance" then return end
	if action == "VIPDance" and not vip(player) then notify(player, "VIP or higher access is required.", "error"); return end
	local assetId = config[action]
	if not playTrack(player, assetId) then notify(player, "This animation is not configured or could not be loaded.", "error"); return end
	lastActionAt[player.UserId] = now
end

local function invite(player: Player, target: Player, action: string)
	if action ~= "Hug" or target == player then return end
	if not access(player) or not access(target) then notify(player, "Both players need Tiki Tide access for duo actions.", "error"); return end
	local now = os.clock()
	local previousInvite = lastInviteAt[player.UserId] or 0
	if previousInvite > 0 and now - previousInvite < INVITE_COOLDOWN then notify(player, "Please wait before sending another invitation."); return end
	local previousInbound = lastInboundAt[target.UserId] or 0
	if previousInbound > 0 and now - previousInbound < INBOUND_COOLDOWN then notify(player, "That player has recently received an invitation."); return end
	if inviteBySender[player.UserId] or inviteByTarget[player.UserId] then notify(player, "You already have a pending social invitation."); return end
	if inviteBySender[target.UserId] or inviteByTarget[target.UserId] then notify(player, "That player is already handling another invitation."); return end
	if not closeEnough(player, target) then notify(player, "Move closer before sending a duo invitation."); return end
	local id = HttpService:GenerateGUID(false)
	local record: Invite = {id = id, from = player.UserId, to = target.UserId, action = action, expiresAt = now + INVITE_TTL}
	invitesById[id] = record
	inviteBySender[player.UserId] = id
	inviteByTarget[target.UserId] = id
	lastInviteAt[player.UserId] = now
	lastInboundAt[target.UserId] = now
	eventRemote:FireClient(target, "Invite", id, player.UserId, player.DisplayName, action, INVITE_TTL)
	notify(player, "Invitation sent. Waiting for a response.", "success")
	task.delay(INVITE_TTL, function()
		if invitesById[id] == record then clearInvite(id, "Your social invitation expired.") end
	end)
end

local function respond(player: Player, id: any, accepted: any)
	if typeof(id) ~= "string" or #id > 64 or typeof(accepted) ~= "boolean" then return end
	local invite = invitesById[id]
	if not invite or invite.to ~= player.UserId then notify(player, "This invitation is no longer available."); return end
	local now = os.clock()
	if now > invite.expiresAt then clearInvite(id, "Your social invitation expired."); return end
	local sender = Players:GetPlayerByUserId(invite.from)
	if not sender or sender.Parent ~= Players or player.Parent ~= Players then clearInvite(id, "The other player is no longer available."); return end
	if not accepted then clearInvite(id, nil); notify(sender, player.DisplayName .. " declined your invitation."); notify(player, "Invitation declined."); return end
	-- Revalidate entitlement, identities, character life and distance at acceptance.
	if not access(sender) or not access(player) or invite.action ~= "Hug" or not closeEnough(sender, player) then
		clearInvite(id, "The duo action could not start; check access, distance and character state.")
		notify(player, "The duo action could not start; check access, distance and character state.", "error")
		return
	end
	local senderCharacter = sender.Character
	local targetCharacter = player.Character
	clearInvite(id, nil)
	local actorOk = playTrack(sender, config.HugActor)
	local targetOk = playTrack(player, config.HugTarget)
	if not actorOk or not targetOk or sender.Character ~= senderCharacter or player.Character ~= targetCharacter then
		stopOwnedTracks(sender.UserId)
		stopOwnedTracks(player.UserId)
		notify(sender, "The duo animation is not configured or could not be loaded.", "error")
		notify(player, "The duo animation is not configured or could not be loaded.", "error")
		return
	end
	lastActionAt[sender.UserId] = now
	lastActionAt[player.UserId] = now
	notify(sender, "Hug started.", "success")
	notify(player, "Hug started.", "success")
end

requestRemote.OnServerEvent:Connect(function(player: Player, action: any, payload: any)
	if player.Parent ~= Players then return end
	if not consumeIngress(player) then
		recordSecuritySignal(player, "social_action_ingress_limited", "per-player token bucket exhausted")
		return
	end
	if typeof(action) ~= "string" or #action > 24 or typeof(payload) ~= "table" then
		recordSecuritySignal(player, "social_action_invalid_request", "invalid action or payload type")
		return
	end
	local count = 0
	for key, value in pairs(payload) do
		count += 1
		if count > 4 or typeof(key) ~= "string" or #key > 24 then
			recordSecuritySignal(player, "social_action_invalid_payload", "payload shape exceeded bounds")
			return
		end
		local kind = typeof(value)
		if kind ~= "string" and kind ~= "number" and kind ~= "boolean" then return end
		if kind == "string" and #value > 64 then
			recordSecuritySignal(player, "social_action_invalid_payload", "payload string exceeded bounds")
			return
		end
		if kind == "number" and (value ~= value or math.abs(value) == math.huge) then
			recordSecuritySignal(player, "social_action_invalid_payload", "non-finite numeric payload")
			return
		end
	end
	if action == "Play" then
		if typeof(payload.name) == "string" then playSolo(player, payload.name) end
	elseif action == "Invite" then
		local target = validatePlayerId(payload.userId)
		if target then invite(player, target, payload.name) else notify(player, "Select a valid player.", "error") end
	elseif action == "Respond" then
		respond(player, payload.id, payload.accepted)
	elseif action == "Cancel" then
		local id = inviteBySender[player.UserId]
		if id then clearInvite(id, "You cancelled your invitation.") end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	clearPlayerInvites(player.UserId)
	stopOwnedTracks(player.UserId)
	lastActionAt[player.UserId] = nil
	lastInviteAt[player.UserId] = nil
	lastInboundAt[player.UserId] = nil
	lastIngressAt[player.UserId] = nil
	ingressTokens[player.UserId] = nil
end)

task.spawn(function()
	while true do
		task.wait(5)
		local now = os.clock()
		for id, invite in pairs(invitesById) do
			if now > invite.expiresAt then clearInvite(id, "Your social invitation expired.") end
		end
	end
end)

print("[Tiki Tide Social] Server-authoritative social actions ready.")
