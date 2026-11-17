--!strict
-- Controller-invoked crossfade coordinator. No independent queue or playback loop.
-- The caller supplies both decks and owns when a transition is committed.
-- Cancellation invalidates the running generation before touching either deck.
local Manager = {}
Manager.__index = Manager

export type Deck = {
	SetGain: (self: any, gain: number) -> (boolean, string?),
	SetAsset: (self: any, asset: string) -> (boolean, string?),
	IsReady: (self: any) -> boolean,
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

local function readOutgoingGain(context: any): (boolean, number)
	if typeof(context) ~= "table" or typeof(context.GetOutgoingGain) ~= "function" then
		return false, 0
	end
	local ok, value = pcall(context.GetOutgoingGain)
	if not ok or typeof(value) ~= "number" or value ~= value
		or value < 0 or value > 1 or value == math.huge then
		return false, 0
	end
	return true, value
end

local function setOutgoingGain(context: any, gain: number): boolean
	-- Missing gain control is a hard failure, never a silent full-volume fallback.
	if typeof(context) ~= "table" or typeof(context.SetOutgoingGain) ~= "function" then
		return false
	end
	local ok, result = pcall(context.SetOutgoingGain, gain)
	return ok and result ~= false
end

local function notifySettled(self: any, outcome: string)
	local context = self.context
	if typeof(context) == "table" and typeof(context.OnSettled) == "function" then
		pcall(context.OnSettled, outcome)
	end
end

local function cancelAfterFailure(self: any, reason: string)
	local cancelOk, cancelError = self:Cancel()
	local detail = reason
	if not cancelOk then
		detail ..= " Cleanup also reported: " .. tostring(cancelError)
	end
	local context = self.context
	if typeof(context) == "table" and typeof(context.OnFailure) == "function" then
		pcall(context.OnFailure, detail)
	end
end

function Manager.new(context)
	assert(typeof(context) == "table", "Crossfade manager requires controller context.")
	assert(typeof(context.CreateDeck) == "function", "Crossfade manager requires CreateDeck.")
	assert(typeof(context.SetOutgoingGain) == "function", "Crossfade manager requires SetOutgoingGain; refusing an unsafe full-volume dual-deck fade.")
	assert(typeof(context.GetOutgoingGain) == "function", "Crossfade manager requires GetOutgoingGain so it can preserve the active gain profile.")
	assert(typeof(context.OnCommit) == "function", "Crossfade manager requires OnCommit.")
	return setmetatable({
		context = context,
		generation = 0,
		active = false,
		starting = false,
		destroyed = false,
		incoming = nil,
	}, Manager)
end

function Manager:Cancel(): (boolean, string?)
	-- Invalidate first so a sleeping transition coroutine cannot commit afterward.
	self.generation += 1
	self.active = false
	self.starting = false
	local incoming = self.incoming
	self.incoming = nil
	local restoreGain = self.outgoingBaseGain
	self.outgoingBaseGain = nil

	local cleanupFailed = false
	if incoming then
		local stopOk, stopResult = safeMethod(incoming, "Stop")
		if not stopOk or stopResult == false then cleanupFailed = true end
		local cleanupOk = safeMethod(incoming, "Cleanup")
		if not cleanupOk then cleanupFailed = true end
	end

	-- Restore the still-controller-owned outgoing deck after an interrupted fade.
	local restoreFailed = false
	if typeof(restoreGain) == "number" and not setOutgoingGain(self.context, restoreGain) then
		restoreFailed = true
	end
	local cancelError = if restoreFailed then "Outgoing gain restoration failed."
		else if cleanupFailed then "Incoming deck cleanup failed." else nil
	notifySettled(self, "cancelled")
	if cancelError then return false, cancelError end
	return true, nil
end

function Manager:Begin(asset: string, duration: number)
	if self.destroyed or typeof(self.context) ~= "table" then
		return false, "Crossfade manager is unavailable."
	end
	if self.active or self.starting then return false, "A crossfade is already in progress." end
	if typeof(asset) ~= "string" or #asset > 64 or not string.match(asset, "^rbxassetid://%d+$") then
		return false, "Invalid incoming audio asset."
	end
	if typeof(duration) ~= "number" or duration ~= duration or duration < 0.25 or duration > 12 then
		return false, "Crossfade duration must be between 0.25 and 12 seconds."
	end

	-- Reserve the generation before invoking injected callbacks. Those callbacks
	-- may yield; a concurrent Begin must see the reservation, and Cancel/Cleanup
	-- must invalidate it before a late setup continuation can register a deck.
	self.generation += 1
	local generation = self.generation
	self.starting = true
	local function startIsCurrent(): boolean
		return self.generation == generation and self.starting
			and not self.destroyed and typeof(self.context) == "table"
	end
	local function rejectStart(message: string, deck: any?): (boolean, string)
		if deck then safeMethod(deck, "Cleanup") end
		local stillCurrent = startIsCurrent()
		if stillCurrent then
			self.starting = false
			notifySettled(self, "rejected")
		end
		return false, if stillCurrent then message else "Crossfade start was cancelled."
	end

	local createOk, incoming = pcall(self.context.CreateDeck)
	if not createOk or typeof(incoming) ~= "table" then
		return rejectStart("Could not create the incoming audio deck.")
	end
	if not startIsCurrent() then
		return rejectStart("Crossfade start was cancelled.", incoming)
	end
	for _, methodName in ipairs({ "Play", "SetGain", "SetAsset", "IsReady", "Stop", "Cleanup" }) do
		if typeof(incoming[methodName]) ~= "function" then
			return rejectStart("Incoming audio deck is missing " .. methodName .. ".", incoming)
		end
	end

	local gainOk, outgoingBaseGain = readOutgoingGain(self.context)
	if not gainOk then
		return rejectStart("Could not read the outgoing audio gain.", incoming)
	end
	if not startIsCurrent() then
		return rejectStart("Crossfade start was cancelled.", incoming)
	end

	self.outgoingBaseGain = outgoingBaseGain
	self.incoming = incoming
	self.active = true
	self.starting = false

	local incomingGainOk, gainResult, gainError = safeMethod(incoming, "SetGain", 0)
	if not incomingGainOk or gainResult == false then
		cancelAfterFailure(self, "Could not initialize incoming deck gain.")
		return false, tostring(gainError or "Could not initialize incoming deck gain.")
	end
	local assetOk, assetResult, assetError = safeMethod(incoming, "SetAsset", asset)
	if not assetOk or assetResult == false then
		cancelAfterFailure(self, "Could not assign the incoming asset.")
		return false, tostring(assetError or "Could not assign the incoming asset.")
	end

	-- Wait for the incoming asset before fading; otherwise the outgoing deck
	-- could be attenuated while the AudioPlayer is still buffering.
	local spawnOk, spawnError = pcall(task.spawn, function()
		local readyDeadline = os.clock() + 8
		local ready = false
		while os.clock() < readyDeadline and self.generation == generation
			and self.active and self.incoming == incoming and not self.destroyed do
			local readyOk, readyValue = safeMethod(incoming, "IsReady")
			if readyOk and readyValue == true then ready = true; break end
			task.wait(0.1)
		end
		if self.generation ~= generation or not self.active or self.incoming ~= incoming or self.destroyed then return end
		if not ready then cancelAfterFailure(self, "Incoming audio did not become ready within 8 seconds."); return end

		-- Prepare early, but do not attenuate the current track until its
		-- remaining-time window reaches the requested fade duration.
		if typeof(self.context.GetRemainingTime) == "function" then
			while self.generation == generation and self.active and self.incoming == incoming and not self.destroyed do
				local remainingOk, remaining = pcall(self.context.GetRemainingTime)
				if not remainingOk or typeof(remaining) ~= "number" or remaining ~= remaining
					or remaining < 0 or remaining == math.huge then
					cancelAfterFailure(self, "Could not read a valid remaining playback duration.")
					return
				end
				if remaining <= duration then break end
				task.wait(math.min(0.1, remaining - duration))
			end
		end
		if self.generation ~= generation or not self.active or self.incoming ~= incoming or self.destroyed then return end

		local playOk, playResult = safeMethod(incoming, "Play", nil, 0)
		if not playOk or playResult == false then cancelAfterFailure(self, "Incoming AudioPlayer could not start."); return end
		local elapsed = 0
		local step = 0.05
		while elapsed < duration and self.generation == generation and not self.destroyed do
			local alpha = math.clamp(elapsed / duration, 0, 1)
			local incomingOk, incomingResult = safeMethod(incoming, "SetGain", outgoingBaseGain * alpha)
			if not incomingOk or incomingResult == false then cancelAfterFailure(self, "Incoming deck gain update failed during crossfade."); return end
			if not setOutgoingGain(self.context, outgoingBaseGain * (1 - alpha)) then cancelAfterFailure(self, "Outgoing deck gain update failed during crossfade."); return end
			task.wait(step)
			elapsed += step
		end
		if self.generation ~= generation or self.destroyed or self.incoming ~= incoming then return end

		local fullGainOk, fullGainResult = safeMethod(incoming, "SetGain", outgoingBaseGain)
		if not fullGainOk or fullGainResult == false or not setOutgoingGain(self.context, 0) then
			cancelAfterFailure(self, "Could not finalize crossfade gains.")
			return
		end

		-- OnCommit must atomically transfer controller ownership or return false.
		local commitOk, commitResult = pcall(self.context.OnCommit, incoming)
		if not commitOk or commitResult == false then
			cancelAfterFailure(self, "Controller rejected the crossfade commit.")
			return
		end
		if self.generation ~= generation or self.incoming ~= incoming then return end
		self.incoming = nil
		self.outgoingBaseGain = nil
		self.active = false
		notifySettled(self, "committed")
	end)
	if not spawnOk then
		cancelAfterFailure(self, "Could not schedule the crossfade worker: " .. tostring(spawnError))
		return false, "Could not schedule the crossfade worker."
	end
	return true, nil
end

function Manager:Cleanup(): (boolean, string?)
	if self.destroyed then return true, nil end
	-- Close admission before cancellation touches resources. If cleanup yields
	-- inside a deck method, no new Begin may reserve this manager meanwhile.
	self.destroyed = true
	local cancelOk, cancelError = self:Cancel()
	self.context = nil
	if not cancelOk then return false, cancelError end
	return true, nil
end

return Manager
