--!strict
-- ClubMusic global recovery coordinator.
-- It retries transient shared-queue reads with bounded backoff. It deliberately
-- never edits queue state or clears catalog reservations automatically.

local RecoveryService = {}
RecoveryService.__index = RecoveryService

export type Dependencies = {
    isEnabled: () -> boolean,
    allowStoreOperation: () -> boolean,
    getSnapshot: () -> (boolean, any?, string?),
    invalidateSnapshot: () -> (),
    initialRetrySeconds: number?,
    maxRetrySeconds: number?,
    reportError: ((string, string, any, Instance?) -> any)?,
}

function RecoveryService.new(dependencies: Dependencies)
    assert(type(dependencies) == "table", "RecoveryService requires dependencies")
    assert(type(dependencies.isEnabled) == "function", "RecoveryService requires isEnabled")
    assert(type(dependencies.allowStoreOperation) == "function", "RecoveryService requires allowStoreOperation")
    assert(type(dependencies.getSnapshot) == "function", "RecoveryService requires getSnapshot")
    assert(type(dependencies.invalidateSnapshot) == "function", "RecoveryService requires invalidateSnapshot")

    local self = setmetatable({}, RecoveryService)
    self.dependencies = dependencies
    self.running = false
    self.retrySeconds = math.max(10, dependencies.initialRetrySeconds or 30)
    self.maxRetrySeconds = math.max(self.retrySeconds, dependencies.maxRetrySeconds or 180)
    self.status = {
        state = "Starting",
        detail = "Waiting for the first authoritative shared-queue probe.",
        updatedAt = os.time(),
        attempts = 0,
    }
    self.lastSignature = ""
    return self
end

function RecoveryService:GetStatus(): {[string]: any}
    return table.clone(self.status)
end

function RecoveryService:_setStatus(state: string, detail: string)
    self.status = {
        state = state,
        detail = detail,
        updatedAt = os.time(),
        attempts = self.status.attempts,
    }
    local signature = state .. "|" .. detail
    if signature ~= self.lastSignature then
        self.lastSignature = signature
        if state == "Degraded" and type(self.dependencies.reportError) == "function" then
            pcall(self.dependencies.reportError, "GlobalRecovery", "SharedQueueProbe", detail, nil)
        end
        if state == "Healthy" then
            print("[ClubMusic Global Recovery] " .. detail)
        elseif state ~= "Disabled" then
            warn("[ClubMusic Global Recovery] " .. detail)
        end
    end
end

function RecoveryService:Start(): boolean
    if self.running then return false end
    self.running = true

    task.spawn(function()
        while self.running do
            local enabledOk, enabled = pcall(self.dependencies.isEnabled)
            if not enabledOk or enabled ~= true then
                self:_setStatus("Disabled", "Cross-server service is disabled; no global recovery operation was attempted.")
                task.wait(60)
                continue
            end

            local budgetOk, budgetAllowed = pcall(self.dependencies.allowStoreOperation)
            if not budgetOk or budgetAllowed ~= true then
                self.status.attempts += 1
                self:_setStatus("Degraded", "Shared storage budget is unavailable; authoritative queue verification will retry.")
                task.wait(self.retrySeconds)
                self.retrySeconds = math.min(self.maxRetrySeconds, self.retrySeconds * 2)
                continue
            end

            local readOk, snapshot, readError = pcall(function()
                self.dependencies.invalidateSnapshot()
                return self.dependencies.getSnapshot()
            end)

            if not readOk or snapshot ~= true then
                self.status.attempts += 1
                self:_setStatus("Degraded", tostring(if readOk then readError or "Shared queue snapshot read failed." else snapshot))
                task.wait(self.retrySeconds)
                self.retrySeconds = math.min(self.maxRetrySeconds, self.retrySeconds * 2)
                continue
            end

            local state = readError
            self.retrySeconds = math.max(10, self.dependencies.initialRetrySeconds or 30)
            if type(state) == "table" and type(state.catalogChangeTrackId) == "string" then
                local kind = if type(state.catalogChangeKind) == "string" then state.catalogChangeKind else "unknown"
                self:_setStatus(
                    "CatalogChangePending",
                    "A " .. kind .. " reservation for track " .. state.catalogChangeTrackId
                        .. " is still pending. Resume the same catalog operation; this service will not clear the reservation automatically."
                )
            else
                self:_setStatus("Healthy", "Authoritative shared queue storage is responding; no pending catalog reservation was found.")
            end

            task.wait(self.retrySeconds)
        end
    end)

    return true
end

function RecoveryService:Stop()
    self.running = false
end

return RecoveryService
