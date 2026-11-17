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

-- Failed deck teardown must remain reachable after transition ownership is released.
-- Retries are bounded; a final failure stays in the manager registry for a later
-- explicit Cleanup() call rather than being abandoned or retried forever.
local function cleanupRetiredDeck(self: any, deck: any, reason: string): boolean
	if deck == nil then return true end
	self.retiredDecks = self.retiredDecks or {}
	if self.retiredDecks[deck] == "retrying" then return false end
	local cleanupOk, cleanupResult, cleanupError = safeMethod(deck, "Cleanup")
	if cleanupOk and cleanupResult ~= false then
		self.retiredDecks[deck] = nil
		return true
	end

	self.retiredDecks[deck] = "retrying"
	local detail = tostring(cleanupError or cleanupResult)
	local context = self.context
	if typeof(context) == "table" and typeof(context.OnFailure) == "function" then
		pcall(context.OnFailure, "Retired deck cleanup failed (" .. reason .. "): " .. detail)
	end
	task.spawn(function()
		for attempt = 1, 3 do
			task.wait(attempt)
			local retryOk, retryResult, retryError = safeMethod(deck, "Cleanup")
			if retryOk and retryResult ~= false then
				self.retiredDecks[deck] = nil
				return
			end
			if typeof(self.context) == "table" and typeof(self.context.OnFailure) == "function" then
				pcall(self.context.OnFailure, "Retired deck cleanup retry " .. tostring(attempt)
					.. " failed (" .. reason .. "): " .. tostring(retryError or retryResult))
			end
		end
		if self.retiredDecks[deck] == "retrying" then
			self.retiredDecks[deck] = "pending"
		end
	end)
	return false
end

local function retryPendingDecks(self: any): boolean
	local allClean = true
	for deck, status in pairs(self.retiredDecks or {}) do
		if status == "pending" and not cleanupRetiredDeck(self, deck, "manager cleanup retry") then
			allClean = false
		elseif status == "retrying" then
			allClean = false
		end
	end
	return allClean
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

local function cancelGenerationAfterFailure(self: any, generation: number, incoming: any, reason: string)
	-- A yielding deck/context call may resume after Cancel and a newer Begin.
	-- Never let an obsolete worker cancel or report failure against that newer run.
	if self.generation ~= generation or self.incoming ~= incoming
		or not self.active or self.destroyed then return end
	cancelAfterFailure(self, reason)
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
		retiredDecks = {},
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
		if not cleanupRetiredDeck(self, incoming, "cancelled incoming deck") then cleanupFailed = true end
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
		local cleanupOk = true
		if deck then cleanupOk = cleanupRetiredDeck(self, deck, "rejected incoming deck") end
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
	if self.generation ~= generation or not self.active or self.incoming ~= incoming or self.destroyed then
		return false, "Crossfade start was cancelled."
	end
	if not incomingGainOk or gainResult == false then
		cancelGenerationAfterFailure(self, generation, incoming, "Could not initialize incoming deck gain.")
		return false, tostring(gainError or "Could not initialize incoming deck gain.")
	end
	local assetOk, assetResult, assetError = safeMethod(incoming, "SetAsset", asset)
	if self.generation ~= generation or not self.active or self.incoming ~= incoming or self.destroyed then
		return false, "Crossfade start was cancelled."
	end
	if not assetOk or assetResult == false then
		cancelGenerationAfterFailure(self, generation, incoming, "Could not assign the incoming asset.")
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
		if not ready then cancelGenerationAfterFailure(self, generation, incoming, "Incoming audio did not become ready within 8 seconds."); return end

		-- Prepare early, but do not attenuate the current track until its
		-- remaining-time window reaches the requested fade duration.
		if typeof(self.context.GetRemainingTime) == "function" then
			while self.generation == generation and self.active and self.incoming == incoming and not self.destroyed do
				local remainingOk, remaining = pcall(self.context.GetRemainingTime)
				if not remainingOk or typeof(remaining) ~= "number" or remaining ~= remaining
					or remaining < 0 or remaining == math.huge then
					cancelGenerationAfterFailure(self, generation, incoming, "Could not read a valid remaining playback duration.")
					return
				end
				if remaining <= duration then break end
				task.wait(math.min(0.1, remaining - duration))
			end
		end
		if self.generation ~= generation or not self.active or self.incoming ~= incoming or self.destroyed then return end

		local playOk, playResult = safeMethod(incoming, "Play", nil, 0)
		if not playOk or playResult == false then cancelGenerationAfterFailure(self, generation, incoming, "Incoming AudioPlayer could not start."); return end
		local elapsed = 0
		local step = 0.05
		while elapsed < duration and self.generation == generation and not self.destroyed do
			local alpha = math.clamp(elapsed / duration, 0, 1)
			local incomingOk, incomingResult = safeMethod(incoming, "SetGain", outgoingBaseGain * alpha)
			if self.generation ~= generation or self.incoming ~= incoming or not self.active or self.destroyed then return end
			if not incomingOk or incomingResult == false then cancelGenerationAfterFailure(self, generation, incoming, "Incoming deck gain update failed during crossfade."); return end
			local outgoingOk = setOutgoingGain(self.context, outgoingBaseGain * (1 - alpha))
			if self.generation ~= generation or self.incoming ~= incoming or not self.active or self.destroyed then return end
			if not outgoingOk then cancelGenerationAfterFailure(self, generation, incoming, "Outgoing deck gain update failed during crossfade."); return end
			task.wait(step)
			elapsed += step
		end
		if self.generation ~= generation or self.destroyed or self.incoming ~= incoming then return end

		local fullGainOk, fullGainResult = safeMethod(incoming, "SetGain", outgoingBaseGain)
		if self.generation ~= generation or self.incoming ~= incoming or not self.active or self.destroyed then return end
		if not fullGainOk or fullGainResult == false then
			cancelGenerationAfterFailure(self, generation, incoming, "Could not finalize incoming deck gain.")
			return
		end
		local outgoingMuteOk = setOutgoingGain(self.context, 0)
		if self.generation ~= generation or self.incoming ~= incoming or not self.active or self.destroyed then return end
		if not outgoingMuteOk then
			cancelGenerationAfterFailure(self, generation, incoming, "Could not finalize outgoing deck gain.")
			return
		end

		-- OnCommit must atomically transfer controller ownership or return false.
		local commitOk, commitResult = pcall(self.context.OnCommit, incoming)
		if not commitOk or commitResult == false then
			cancelGenerationAfterFailure(self, generation, incoming, "Controller rejected the crossfade commit.")
			return
		end
		if self.generation ~= generation or self.incoming ~= incoming then return end
		self.incoming = nil
		self.outgoingBaseGain = nil
		self.active = false
		notifySettled(self, "committed")
	end)
	if not spawnOk then
		cancelGenerationAfterFailure(self, generation, incoming, "Could not schedule the crossfade worker: " .. tostring(spawnError))
		return false, "Could not schedule the crossfade worker."
	end
	return true, nil
end

local function drainRetiredDecks(self: any): boolean
	-- Let any bounded asynchronous retry already in flight finish before taking
	-- over the pending registry. This is especially important during BindToClose.
	local deadline = os.clock() + 6.5
	while os.clock() < deadline do
		local retrying = false
		for _, status in pairs(self.retiredDecks or {}) do
			if status == "retrying" then retrying = true; break end
		end
		if not retrying then break end
		task.wait(0.1)
	end

	local allClean = true
	for deck, status in pairs(self.retiredDecks or {}) do
		if status == "pending" then
			self.retiredDecks[deck] = "retrying"
			local cleaned = false
			for attempt = 1, 3 do
				if attempt > 1 then task.wait(attempt) end
				local ok, result, detail = safeMethod(deck, "Cleanup")
				if ok and result ~= false then
					self.retiredDecks[deck] = nil
					cleaned = true
					break
				end
				local context = self.context
				if typeof(context) == "table" and typeof(context.OnFailure) == "function" then
					pcall(context.OnFailure, "Final retired deck cleanup retry " .. tostring(attempt)
						.. " failed: " .. tostring(detail or result))
				end
			end
			if not cleaned then
				self.retiredDecks[deck] = "pending"
				allClean = false
			end
		elseif status == "retrying" then
			allClean = false
		end
	end
	return allClean
end

function Manager:Cleanup(): (boolean, string?)
	if not self.destroyed then
		-- Close admission before cancellation touches resources. If cleanup yields
		-- inside a deck method, no new Begin may reserve this manager meanwhile.
		self.destroyed = true
		local cancelOk, cancelError = self:Cancel()
		local pendingClean = drainRetiredDecks(self)
		self.context = nil
		if not cancelOk then return false, cancelError end
		if not pendingClean then return false, "One or more retired crossfade decks remain pending cleanup." end
		return true, nil
	end
	local pendingClean = drainRetiredDecks(self)
	if not pendingClean then return false, "One or more retired crossfade decks remain pending cleanup." end
	return true, nil
end

return Manager
