--!strict
-- Controller-invoked crossfade coordinator. No independent queue or playback loop.
-- The caller supplies both decks and owns when a transition is committed.
-- Cancellation invalidates the running generation before touching either deck.
local Manager = {}
Manager.__index = Manager

export type Deck = {
	SetGain: (self: any, gain: number) -> (boolean, string?),
	Play: (self: any, asset: string?, position: number?) -> (boolean, string?),
	Stop: (self: any) -> (boolean, string?),
	GetTimePosition: (self: any) -> number,
	Cleanup: (self: any) -> (),
}

local function safeMethod(object: any, methodName: string, ...: any): (boolean, any, any)
	if object == nil or typeof(object[methodName]) ~= "function" then
		return false, nil, "Missing deck method: " .. methodName
	end
	return pcall(object[methodName], object, ...)
end

local function setOutgoingGain(context: any, gain: number): boolean
	-- Missing gain control is a hard failure, never a silent full-volume fallback.
	if typeof(context) ~= "table" or typeof(context.SetOutgoingGain) ~= "function" then
		return false
	end
	local ok, result = pcall(context.SetOutgoingGain, gain)
	return ok and result ~= false
end

function Manager.new(context)
	assert(typeof(context) == "table", "Crossfade manager requires controller context.")
	assert(typeof(context.CreateDeck) == "function", "Crossfade manager requires CreateDeck.")
	assert(typeof(context.SetOutgoingGain) == "function", "Crossfade manager requires SetOutgoingGain; refusing an unsafe full-volume dual-deck fade.")
	assert(typeof(context.OnCommit) == "function", "Crossfade manager requires OnCommit.")
	return setmetatable({
		context = context,
		generation = 0,
		active = false,
		destroyed = false,
		incoming = nil,
	}, Manager)
end

function Manager:Cancel()
	-- Invalidate first so a sleeping transition coroutine cannot commit afterward.
	self.generation += 1
	self.active = false
	local incoming = self.incoming
	self.incoming = nil
	if incoming then
		safeMethod(incoming, "Stop")
		safeMethod(incoming, "Cleanup")
	end
	-- Restore the still-controller-owned outgoing deck after an interrupted fade.
	setOutgoingGain(self.context, 1)
	return true
end

function Manager:Begin(asset: string, duration: number)
	if self.destroyed or typeof(self.context) ~= "table" then
		return false, "Crossfade manager is unavailable."
	end
	if self.active then return false, "A crossfade is already in progress." end
	if typeof(asset) ~= "string" or #asset > 64 or not string.match(asset, "^rbxassetid://%d+$") then
		return false, "Invalid incoming audio asset."
	end
	if typeof(duration) ~= "number" or duration ~= duration or duration < 0.25 or duration > 12 then
		return false, "Crossfade duration must be between 0.25 and 12 seconds."
	end

	local createOk, incoming = pcall(self.context.CreateDeck)
	if not createOk or typeof(incoming) ~= "table" then
		return false, "Could not create the incoming audio deck."
	end
	for _, methodName in ipairs({ "Play", "SetGain", "Stop", "Cleanup" }) do
		if typeof(incoming[methodName]) ~= "function" then
			pcall(function() incoming:Cleanup() end)
			return false, "Incoming audio deck is missing " .. methodName .. "."
		end
	end

	local generation = self.generation + 1
	self.generation = generation
	self.incoming = incoming
	self.active = true

	local gainOk, gainResult, gainError = safeMethod(incoming, "SetGain", 0)
	if not gainOk or gainResult == false then
		self:Cancel()
		return false, tostring(gainError or "Could not initialize incoming deck gain.")
	end
	local playOk, playResult, playError = safeMethod(incoming, "Play", asset, 0)
	if not playOk or playResult == false then
		self:Cancel()
		return false, tostring(playError or "Could not start incoming audio deck.")
	end

	task.spawn(function()
		local elapsed = 0
		local step = 0.05
		while elapsed < duration and self.generation == generation and not self.destroyed do
			local alpha = math.clamp(elapsed / duration, 0, 1)
			local incomingOk, incomingResult = safeMethod(incoming, "SetGain", alpha)
			if not incomingOk or incomingResult == false then self:Cancel(); return end
			if not setOutgoingGain(self.context, 1 - alpha) then self:Cancel(); return end
			task.wait(step)
			elapsed += step
		end
		if self.generation ~= generation or self.destroyed or self.incoming ~= incoming then return end

		local fullGainOk, fullGainResult = safeMethod(incoming, "SetGain", 1)
		if not fullGainOk or fullGainResult == false or not setOutgoingGain(self.context, 0) then
			self:Cancel()
			return
		end

		-- OnCommit must atomically transfer controller ownership or return false.
		local commitOk, commitResult = pcall(self.context.OnCommit, incoming)
		if not commitOk or commitResult == false then self:Cancel(); return end
		if self.generation ~= generation or self.incoming ~= incoming then return end
		self.incoming = nil
		self.active = false
	end)
	return true, nil
end

function Manager:Cleanup()
	if self.destroyed then return end
	self:Cancel()
	self.destroyed = true
	self.context = nil
end

return Manager
