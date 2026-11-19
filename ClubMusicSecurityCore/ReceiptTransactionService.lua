--!strict
-- ReceiptTransactionService
-- Security Core owns the durable Developer Product transaction journal.
-- Existing DataStore names, hashed keys, profile schema, pending markers, and
-- recovery semantics are intentionally preserved for compatibility.

local Service = {}
Service.__index = Service

function Service.new(dependencies: {[string]: any})
	assert(typeof(dependencies) == "table", "ReceiptTransactionService dependencies are required")
	for _, name in ipairs({
		"getProfile", "waitForDataStoreBudget", "acquireProfileWriteLock", "releaseProfileWriteLock",
		"applyReceiptToStoredData", "applyReceiptToMemory", "keySuffix",
	}) do
		assert(type(dependencies[name]) == "function", "ReceiptTransactionService missing dependency: " .. name)
	end
	assert(dependencies.profileStore ~= nil, "ReceiptTransactionService profileStore is required")
	assert(dependencies.journalStore ~= nil, "ReceiptTransactionService journalStore is required")
	return setmetatable({
		profileStore = dependencies.profileStore,
		journalStore = dependencies.journalStore,
		getProfile = dependencies.getProfile,
		getSessionToken = dependencies.getSessionToken,
		getSessionLockSeconds = dependencies.getSessionLockSeconds,
		waitForDataStoreBudget = dependencies.waitForDataStoreBudget,
		acquireProfileWriteLock = dependencies.acquireProfileWriteLock,
		releaseProfileWriteLock = dependencies.releaseProfileWriteLock,
		applyReceiptToStoredData = dependencies.applyReceiptToStoredData,
		applyReceiptToMemory = dependencies.applyReceiptToMemory,
		keySuffix = dependencies.keySuffix,
		useStudioMemoryProfiles = dependencies.useStudioMemoryProfiles == true,
		pendingMemory = {} :: {[string]: {profile: any, productData: {[string]: any}}},
		appliedMemory = {} :: {[string]: any},
		commits = 0,
		recoveries = 0,
		retries = 0,
	}, Service)
end

function Service:_key(userId: number, purchaseId: string): string
	return "r_" .. self.keySuffix(tostring(userId) .. ":" .. purchaseId)
end

function Service:HasPendingMemory(profile: any, purchaseId: string): boolean
	local pending = self.pendingMemory[purchaseId]
	return pending ~= nil and pending.profile == profile
end

function Service:ForgetProfile(profile: any)
	for purchaseId, pending in pairs(self.pendingMemory) do
		if pending.profile == profile then self.pendingMemory[purchaseId] = nil end
	end
	for purchaseId, appliedProfile in pairs(self.appliedMemory) do
		if appliedProfile == profile then self.appliedMemory[purchaseId] = nil end
	end
end

function Service:_reconcilePendingMemory(userId: number, purchaseId: string)
	local profile = self.getProfile(userId)
	local pending = self.pendingMemory[purchaseId]
	if pending and profile and pending.profile == profile then
		self.applyReceiptToMemory(profile, pending.productData)
		self.appliedMemory[purchaseId] = profile
		self.pendingMemory[purchaseId] = nil
	end
	return profile
end

function Service:RecoverPendingProductReceipt(userId: number): (boolean, string?)
	if not self.waitForDataStoreBudget(10) then return false, "DataStore budget is busy while recovering a receipt" end
	local readOk, profileData = pcall(function()
		return self.profileStore:GetAsync(tostring(userId))
	end)
	if not readOk then return false, tostring(profileData) end
	if typeof(profileData) ~= "table" or typeof(profileData.pendingReceipt) ~= "string" then
		return true, nil
	end

	local pendingId = profileData.pendingReceipt
	local journalKey = self:_key(userId, pendingId)
	if not self.waitForDataStoreBudget(10) then return false, "DataStore budget is busy while reading receipt journal" end
	local journalOk, journal = pcall(function() return self.journalStore:GetAsync(journalKey) end)
	if not journalOk then return false, tostring(journal) end
	if typeof(journal) ~= "table" or journal.purchaseId ~= pendingId
		or journal.userId ~= userId or (journal.status ~= "Prepared" and journal.status ~= "Completed") then
		warn("[ClubMusic][ReceiptTransaction] Pending receipt journal is missing or mismatched for userId " .. tostring(userId))
		return false, "Pending receipt journal is missing or mismatched"
	end

	self:_reconcilePendingMemory(userId, pendingId)
	if journal.status ~= "Completed" then
		if not self.waitForDataStoreBudget(10) then return false, "DataStore budget is busy while completing receipt journal" end
		local completeOk, completed = pcall(function()
			return self.journalStore:UpdateAsync(journalKey, function(old)
				if typeof(old) ~= "table" or old.purchaseId ~= pendingId or old.userId ~= userId then return nil end
				local nextRecord = table.clone(old)
				nextRecord.status = "Completed"
				nextRecord.completedAt = os.time()
				return nextRecord
			end)
		end)
		if not completeOk or typeof(completed) ~= "table" or completed.status ~= "Completed" then
			return false, "Could not complete pending receipt journal"
		end
	end

	if not self.waitForDataStoreBudget(10) then return false, "DataStore budget is busy while clearing pending receipt" end
	local sessionToken = self.getSessionToken()
	local sessionLockSeconds = self.getSessionLockSeconds()
	local clearOk, cleared = pcall(function()
		return self.profileStore:UpdateAsync(tostring(userId), function(old)
			if typeof(old) ~= "table" or typeof(old.sessionLock) ~= "table"
				or old.sessionLock.owner ~= sessionToken then return nil end
			if old.pendingReceipt ~= pendingId then return old end
			local nextData = table.clone(old)
			nextData.pendingReceipt = nil
			nextData.sessionLock = { owner = sessionToken, expiresAt = os.time() + sessionLockSeconds }
			return nextData
		end)
	end)
	if not clearOk or typeof(cleared) ~= "table" or cleared.pendingReceipt == pendingId then
		return false, "Could not clear recovered pending receipt marker"
	end
	self.recoveries += 1
	return true, nil
end

function Service:Commit(userId: number, purchaseId: string, productData: {[string]: any}): (boolean, boolean, string?)
	if self.useStudioMemoryProfiles then
		return self.getProfile(userId) ~= nil, false, nil
	end
	if not self.acquireProfileWriteLock(userId) then
		self.retries += 1
		return false, false, "Profile is busy; receipt will be retried"
	end

	local recovered, recoveryError = self:RecoverPendingProductReceipt(userId)
	if not recovered then
		self.releaseProfileWriteLock(userId)
		self.retries += 1
		return false, false, recoveryError
	end

	local journalKey = self:_key(userId, purchaseId)
	if not self.waitForDataStoreBudget(10) then
		self.releaseProfileWriteLock(userId)
		self.retries += 1
		return false, false, "DataStore budget is busy while reading receipt journal"
	end
	local readOk, journal = pcall(function() return self.journalStore:GetAsync(journalKey) end)
	if not readOk then
		self.releaseProfileWriteLock(userId)
		self.retries += 1
		return false, false, tostring(journal)
	end
	if typeof(journal) == "table" then
		if journal.purchaseId ~= purchaseId or journal.userId ~= userId or journal.productId ~= productData.productId then
			self.releaseProfileWriteLock(userId)
			return false, false, "Receipt journal key collision or product mismatch"
		end
		if journal.status == "Completed" then
			local currentProfile = self:_reconcilePendingMemory(userId, purchaseId)
			local memoryApplied = currentProfile ~= nil and self.appliedMemory[purchaseId] == currentProfile
			if not memoryApplied then self.pendingMemory[purchaseId] = nil end
			self.releaseProfileWriteLock(userId)
			return true, not memoryApplied, nil
		end
		if journal.status ~= "Prepared" then
			self.releaseProfileWriteLock(userId)
			return false, false, "Receipt journal has an invalid status"
		end
	else
		if not self.waitForDataStoreBudget(10) then
			self.releaseProfileWriteLock(userId)
			self.retries += 1
			return false, false, "DataStore budget is busy while preparing receipt"
		end
		local prepareOk, prepared = pcall(function()
			return self.journalStore:UpdateAsync(journalKey, function(old)
				-- Only a genuinely absent key may be initialized. Preserve any existing
				-- value, including malformed values, so validation below fails closed
				-- rather than replacing uncertain receipt history.
				if old ~= nil then return old end
				return {
					status = "Prepared", purchaseId = purchaseId, userId = userId,
					productId = productData.productId, productType = productData.type, createdAt = os.time(),
				}
			end)
		end)
		if not prepareOk or typeof(prepared) ~= "table" or prepared.purchaseId ~= purchaseId
			or prepared.userId ~= userId or prepared.productId ~= productData.productId
			or (prepared.status ~= "Prepared" and prepared.status ~= "Completed") then
			self.releaseProfileWriteLock(userId)
			self.retries += 1
			return false, false, "Could not prepare durable receipt journal"
		end
		journal = prepared
		if prepared.status == "Completed" then
			local currentProfile = self:_reconcilePendingMemory(userId, purchaseId)
			local memoryApplied = currentProfile ~= nil and self.appliedMemory[purchaseId] == currentProfile
			if not memoryApplied then self.pendingMemory[purchaseId] = nil end
			self.releaseProfileWriteLock(userId)
			return true, not memoryApplied, nil
		end
	end

	if not self.waitForDataStoreBudget(10) then
		self.releaseProfileWriteLock(userId)
		self.retries += 1
		return false, false, "DataStore budget is busy while applying receipt"
	end
	local alreadyProcessed = false
	local receiptProfile = self.getProfile(userId)
	if not receiptProfile then
		self.releaseProfileWriteLock(userId)
		self.retries += 1
		return false, false, "Profile disappeared before receipt application"
	end
	self.pendingMemory[purchaseId] = {profile = receiptProfile, productData = productData}
	local sessionToken = self.getSessionToken()
	local sessionLockSeconds = self.getSessionLockSeconds()
	local applyOk, applied = pcall(function()
		return self.profileStore:UpdateAsync(tostring(userId), function(oldData)
			if typeof(oldData) ~= "table" or typeof(oldData.sessionLock) ~= "table"
				or oldData.sessionLock.owner ~= sessionToken then return nil end
			if typeof(oldData.pendingReceipt) == "string" then return nil end
			local data = table.clone(oldData)
			data.receiptIds = if typeof(data.receiptIds) == "table" then table.clone(data.receiptIds) else {}
			if data.receiptIds[purchaseId] == true then
				alreadyProcessed = true
				return data
			end
			if not self.applyReceiptToStoredData(data, productData) then return nil end
			data.pendingReceipt = purchaseId
			data.sessionLock = { owner = sessionToken, expiresAt = os.time() + sessionLockSeconds }
			return data
		end)
	end)
	if not applyOk or typeof(applied) ~= "table" then
		self.releaseProfileWriteLock(userId)
		self.retries += 1
		return false, false, "Receipt reward was not confirmed in the profile"
	end

	if alreadyProcessed then
		self.pendingMemory[purchaseId] = nil
	else
		self.applyReceiptToMemory(receiptProfile, productData)
		self.appliedMemory[purchaseId] = receiptProfile
		self.pendingMemory[purchaseId] = nil
	end
	if not self.waitForDataStoreBudget(10) then
		self.releaseProfileWriteLock(userId)
		self.retries += 1
		return false, false, "DataStore budget is busy while completing receipt journal"
	end
	local completeOk, completed = pcall(function()
		return self.journalStore:UpdateAsync(journalKey, function(old)
			if typeof(old) ~= "table" or old.purchaseId ~= purchaseId or old.userId ~= userId then return nil end
			local nextRecord = table.clone(old)
			nextRecord.status = "Completed"
			nextRecord.completedAt = os.time()
			return nextRecord
		end)
	end)
	if not completeOk or typeof(completed) ~= "table" or completed.status ~= "Completed" then
		self.releaseProfileWriteLock(userId)
		self.retries += 1
		return false, false, "Reward is saved; receipt journal completion will recover on retry"
	end

	if not self.waitForDataStoreBudget(10) then
		self.releaseProfileWriteLock(userId)
		self.retries += 1
		return false, false, "Receipt is durable; pending marker cleanup will recover on retry"
	end
	local clearOk, cleared = pcall(function()
		return self.profileStore:UpdateAsync(tostring(userId), function(old)
			if typeof(old) ~= "table" or typeof(old.sessionLock) ~= "table"
				or old.sessionLock.owner ~= sessionToken then return nil end
			if old.pendingReceipt ~= purchaseId then return old end
			local nextData = table.clone(old)
			nextData.pendingReceipt = nil
			nextData.sessionLock = { owner = sessionToken, expiresAt = os.time() + sessionLockSeconds }
			return nextData
		end)
	end)
	if not clearOk or typeof(cleared) ~= "table" or cleared.pendingReceipt == purchaseId then
		self.releaseProfileWriteLock(userId)
		self.retries += 1
		return false, false, "Receipt is durable; pending marker cleanup will recover on retry"
	end

	self.releaseProfileWriteLock(userId)
	self.commits += 1
	return true, alreadyProcessed, nil
end

function Service:GetStatus(): {[string]: any}
	local pending, applied = 0, 0
	for _ in pairs(self.pendingMemory) do pending += 1 end
	for _ in pairs(self.appliedMemory) do applied += 1 end
	return {
		state = "Ready",
		durableStore = "ClubMusic_ProductReceipts_v1",
		commits = self.commits,
		recoveries = self.recoveries,
		retries = self.retries,
		pendingMemoryEntries = pending,
		appliedMemoryEntries = applied,
	}
end

function Service:Stop()
	table.clear(self.pendingMemory)
	table.clear(self.appliedMemory)
end

return Service
