--!strict
-- Controller-invoked crossfade coordinator. No independent queue or playback loop.
-- The caller supplies both decks and owns when a transition is committed.
local Manager = {}
Manager.__index = Manager

export type Deck = {
	SetGain: (self: any, gain: number) -> (boolean, string?),
	Play: (self: any, asset: string?, position: number?) -> (boolean, string?),
	Stop: (self: any) -> (boolean, string?),
	GetTimePosition: (self: any) -> number,
	Cleanup: (self: any) -> (),
}

function Manager.new(context)
	assert(typeof(context) == "table", "Crossfade manager requires controller context.")
	assert(typeof(context.CreateDeck) == "function", "Crossfade manager requires CreateDeck.")
	assert(typeof(context.OnCommit) == "function", "Crossfade manager requires OnCommit.")
	return setmetatable({ context = context, generation = 0, active = false, destroyed = false }, Manager)
end

function Manager:Cancel()
	self.generation += 1
	self.active = false
	if self.incoming then pcall(function() self.incoming:Stop() end) end
	if self.incoming then pcall(function() self.incoming:Cleanup() end) end
	self.incoming = nil
	return true
end

function Manager:Begin(asset: string, duration: number)
	if self.destroyed then return false, "Crossfade manager is unavailable." end
	if self.active then return false, "A crossfade is already in progress." end
	if typeof(asset) ~= "string" or not string.match(asset, "^rbxassetid://%d+$") then
		return false, "Invalid incoming audio asset."
	end
	if typeof(duration) ~= "number" or duration ~= duration or duration < 0.25 or duration > 12 then
		return false, "Crossfade duration must be between 0.25 and 12 seconds."
	end
	local deckOk, incoming = pcall(self.context.CreateDeck)
	if not deckOk or not incoming then return false, "Could not create the incoming audio deck." end
	local generation = self.generation + 1
	self.generation = generation
	self.incoming = incoming
	self.active = true
	local playOk, playError = incoming:Play(asset, 0)
	if not playOk then self:Cancel(); return false, tostring(playError) end

	task.spawn(function()
		local elapsed = 0
		local step = 0.05
		while elapsed < duration and self.generation == generation and not self.destroyed do
			local alpha = math.clamp(elapsed / duration, 0, 1)
			local ok = incoming:SetGain(alpha)
			if not ok then self:Cancel(); return end
			if typeof(self.context.SetOutgoingGain) == "function" then
				local outOk = pcall(self.context.SetOutgoingGain, 1 - alpha)
				if not outOk then self:Cancel(); return end
			end
			task.wait(step)
			elapsed += step
		end
		if self.generation ~= generation or self.destroyed then return end
		incoming:SetGain(1)
		if typeof(self.context.SetOutgoingGain) == "function" then
			pcall(self.context.SetOutgoingGain, 0)
		end
		local commitOk, commitResult = pcall(self.context.OnCommit, incoming)
		if not commitOk or commitResult == false then self:Cancel(); return end
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
