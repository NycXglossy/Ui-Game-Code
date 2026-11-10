--!strict
-- DJ session state facade. Controller supplies authorization and the only
-- callback that changes active DJ ownership; this module never mutates playback.
local Sessions = {}
Sessions.__index = Sessions

function Sessions.new(context)
	assert(typeof(context) == "table", "DJ session service requires context.")
	assert(typeof(context.Authorize) == "function", "DJ session service requires authorization.")
	assert(typeof(context.OnHandoff) == "function", "DJ session service requires OnHandoff.")
	return setmetatable({ context = context, current = nil, history = {}, destroyed = false }, Sessions)
end

local function validPlayer(player)
	return typeof(player) == "Instance" and player:IsA("Player") and player.Parent ~= nil
end

function Sessions:Start(player: Player)
	if self.destroyed then return false, "DJ session service is unavailable." end
	if not validPlayer(player) then return false, "A connected DJ is required." end
	local ok, allowed = pcall(self.context.Authorize, player, "Start")
	if not ok or allowed ~= true then return false, "You are not authorized to start a DJ session." end
	if self.current then return false, "A DJ session is already active." end
	self.current = { userId = player.UserId, name = player.Name, startedAt = os.time() }
	return true, table.clone(self.current)
end

function Sessions:Handoff(fromPlayer: Player, toPlayer: Player)
	if self.destroyed or not self.current then return false, "No active DJ session." end
	if not validPlayer(fromPlayer) or not validPlayer(toPlayer) then return false, "Both DJs must be connected." end
	if self.current.userId ~= fromPlayer.UserId then return false, "Only the active DJ can hand off the session." end
	local ok, allowed = pcall(self.context.Authorize, fromPlayer, "Handoff")
	if not ok or allowed ~= true then return false, "You are not authorized to hand off this session." end
	local callbackOk, accepted = pcall(self.context.OnHandoff, fromPlayer, toPlayer)
	if not callbackOk or accepted == false then return false, "The controller rejected the DJ handoff." end
	local previous = table.clone(self.current)
	table.insert(self.history, 1, { userId = previous.userId, name = previous.name, endedAt = os.time(), reason = "Handoff" })
	while #self.history > 50 do table.remove(self.history) end
	self.current = { userId = toPlayer.UserId, name = toPlayer.Name, startedAt = os.time() }
	return true, table.clone(self.current)
end

function Sessions:End(player: Player)
	if self.destroyed or not self.current then return false, "No active DJ session." end
	if not validPlayer(player) or self.current.userId ~= player.UserId then return false, "Only the active DJ can end this session." end
	local ok, allowed = pcall(self.context.Authorize, player, "End")
	if not ok or allowed ~= true then return false, "You are not authorized to end this session." end
	table.insert(self.history, 1, { userId = self.current.userId, name = self.current.name, endedAt = os.time(), reason = "Ended" })
	while #self.history > 50 do table.remove(self.history) end
	self.current = nil
	return true, nil
end

function Sessions:GetState()
	return { current = if self.current then table.clone(self.current) else nil, history = table.clone(self.history) }
end

function Sessions:Cleanup()
	self.destroyed = true
	self.current = nil
	table.clear(self.history)
	self.context = nil
end

return Sessions
