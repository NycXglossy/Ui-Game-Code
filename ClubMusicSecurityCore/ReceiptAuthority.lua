--!strict
-- ReceiptAuthority
-- Security Core ingress and in-server transaction coordinator for Roblox
-- Developer Product receipts. Durable journals remain in the existing purchase
-- storage adapters; this module never acknowledges a receipt unless the
-- authoritative transaction handler returns PurchaseGranted.

local Service = {}
Service.__index = Service

local MAX_PURCHASE_ID_LENGTH = 128
local MAX_SAFE_INTEGER = 9007199254740991
local CACHE_CAPACITY = 512
local MAX_IN_FLIGHT = 64

local function validPositiveInteger(value: any): boolean
	return typeof(value) == "number"
		and value == value
		and value > 0
		and value < math.huge
		and value % 1 == 0
		and value <= MAX_SAFE_INTEGER
end

local function receiptKey(userId: number, productId: number, purchaseId: string): string
	return tostring(userId) .. ":" .. tostring(productId) .. ":" .. purchaseId
end

function Service.new(dependencies: {[string]: any})
	assert(typeof(dependencies) == "table", "ReceiptAuthority dependencies are required")
	assert(type(dependencies.resolveProduct) == "function", "ReceiptAuthority product resolver is required")
	assert(type(dependencies.processValidatedReceipt) == "function", "ReceiptAuthority transaction handler is required")
	return setmetatable({
		resolveProduct = dependencies.resolveProduct,
		processValidatedReceipt = dependencies.processValidatedReceipt,
		onEvent = if type(dependencies.onEvent) == "function" then dependencies.onEvent else nil,
		processed = {} :: {[string]: boolean},
		processedOrder = table.create(CACHE_CAPACITY) :: {string?},
		processedCursor = 0,
		inFlight = {} :: {[string]: boolean},
		inFlightCount = 0,
		callbacks = 0,
		granted = 0,
		duplicates = 0,
		invalid = 0,
		unknownProducts = 0,
		concurrentRetries = 0,
		failures = 0,
	}, Service)
end

function Service:_event(name: string, receiptInfo: any, detail: string?)
	if not self.onEvent then return end
	local ok, err = pcall(self.onEvent, name, receiptInfo, detail)
	if not ok then warn("[Tiki Tide][ReceiptAuthority] Event observer failed: " .. string.sub(tostring(err), 1, 160)) end
end

function Service:_remember(key: string)
	if self.processed[key] then return end
	self.processedCursor = (self.processedCursor % CACHE_CAPACITY) + 1
	local evicted = self.processedOrder[self.processedCursor]
	if evicted then self.processed[evicted] = nil end
	self.processedOrder[self.processedCursor] = key
	self.processed[key] = true
end

function Service:Process(receiptInfo: any): Enum.ProductPurchaseDecision
	self.callbacks += 1
	if typeof(receiptInfo) ~= "table" then
		self.invalid += 1
		self:_event("MalformedReceipt", nil, "Receipt payload is not a table.")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local userId = receiptInfo.PlayerId
	local productId = receiptInfo.ProductId
	local purchaseId = receiptInfo.PurchaseId
	if not validPositiveInteger(userId) or not validPositiveInteger(productId)
		or typeof(purchaseId) ~= "string" or #purchaseId < 1 or #purchaseId > MAX_PURCHASE_ID_LENGTH then
		self.invalid += 1
		self:_event("MalformedReceipt", receiptInfo, "Receipt identity fields failed validation.")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local key = receiptKey(userId, productId, purchaseId)
	if self.processed[key] then
		self.duplicates += 1
		self:_event("ReceiptDuplicate", receiptInfo, "Already acknowledged in this server session.")
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	if self.inFlight[key] then
		self.concurrentRetries += 1
		self:_event("ReceiptInFlight", receiptInfo, "Same purchase is already being processed.")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if self.inFlightCount >= MAX_IN_FLIGHT then
		self.concurrentRetries += 1
		self:_event("ReceiptCapacity", receiptInfo, "Receipt transaction concurrency capacity is full.")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local productOk, productData = pcall(self.resolveProduct, productId)
	if not productOk or typeof(productData) ~= "table" then
		self.unknownProducts += 1
		self:_event("UnknownProduct", receiptInfo, "ProductId is not in the server product registry.")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	self.inFlight[key] = true
	self.inFlightCount += 1
	local callOk, decision = pcall(self.processValidatedReceipt, receiptInfo, productData)
	self.inFlight[key] = nil
	self.inFlightCount = math.max(0, self.inFlightCount - 1)

	if not callOk then
		self.failures += 1
		self:_event("TransactionHandlerFailed", receiptInfo, string.sub(tostring(decision), 1, 160))
		warn("[Tiki Tide][ReceiptAuthority] Transaction handler failed; Roblox will retry the receipt.")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if decision == Enum.ProductPurchaseDecision.PurchaseGranted then
		self:_remember(key)
		self.granted += 1
		return decision
	end
	if decision ~= Enum.ProductPurchaseDecision.NotProcessedYet then
		self.failures += 1
		self:_event("InvalidDecision", receiptInfo, "Transaction handler returned an unsupported decision.")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return decision
end

function Service:GetStatus(): {[string]: any}
	local cached = 0
	for _ in pairs(self.processed) do cached += 1 end
	return {
		state = "Ready",
		scope = "ServerLocalIngress",
		callbacks = self.callbacks,
		granted = self.granted,
		duplicates = self.duplicates,
		invalid = self.invalid,
		unknownProducts = self.unknownProducts,
		concurrentRetries = self.concurrentRetries,
		failures = self.failures,
		inFlight = self.inFlightCount,
		inFlightLimit = MAX_IN_FLIGHT,
		cacheEntries = cached,
		cacheCapacity = CACHE_CAPACITY,
		durableAuthority = "ExistingClubMusicReceiptJournals",
	}
end

function Service:Stop()
	table.clear(self.inFlight)
	self.inFlightCount = 0
	table.clear(self.processed)
	table.clear(self.processedOrder)
	self.processedCursor = 0
end

return Service
