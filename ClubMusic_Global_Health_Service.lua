--!strict
-- ClubMusic global health monitor.
-- This module observes service state only; it never owns playback or queue data.

local HealthService = {}
HealthService.__index = HealthService

export type Dependencies = {
    isEnabled: () -> boolean,
    getRecoveryStatus: () -> {[string]: any},
    getSyncStatus: () -> {[string]: any},
    apiFolder: Instance,
    queueModule: Instance,
    intervalSeconds: number?,
    reportError: ((string, string, any, Instance?) -> any)?,
}

function HealthService.new(dependencies: Dependencies)
    assert(type(dependencies) == "table", "HealthService requires dependencies")
    assert(type(dependencies.isEnabled) == "function", "HealthService requires isEnabled")
    assert(type(dependencies.getRecoveryStatus) == "function", "HealthService requires getRecoveryStatus")
    assert(type(dependencies.getSyncStatus) == "function", "HealthService requires getSyncStatus")
    assert(typeof(dependencies.apiFolder) == "Instance", "HealthService requires apiFolder")
    assert(typeof(dependencies.queueModule) == "Instance", "HealthService requires queueModule")

    local self = setmetatable({}, HealthService)
    self.dependencies = dependencies
    self.running = false
    self.status = {
        state = "Starting",
        detail = "Health monitor is starting.",
        updatedAt = os.time(),
    }
    self.lastSignature = ""
    return self
end

function HealthService:GetStatus(): {[string]: any}
    return table.clone(self.status)
end

function HealthService:Start(): boolean
    if self.running then return false end
    self.running = true

    task.spawn(function()
        while self.running do
            local dependencies = self.dependencies
            local enabledOk, enabled = pcall(dependencies.isEnabled)
            local recoveryOk, recovery = pcall(dependencies.getRecoveryStatus)
            local syncOk, sync = pcall(dependencies.getSyncStatus)
            local apiReady = dependencies.apiFolder.Parent ~= nil
                and dependencies.apiFolder:FindFirstChild("GlobalEvent") ~= nil
            local queueReady = dependencies.queueModule:IsA("ModuleScript")

            -- Local health is evaluated independently from cross-server availability.
            -- Studio isolation (or an intentional configuration disable) must not make
            -- a healthy local server look unhealthy.
            local localState = "Healthy"
            local localDetails = {}
            if not apiReady then
                localState = "Degraded"
                table.insert(localDetails, "Global API folder or GlobalEvent is unavailable.")
            end
            if not queueReady then
                localState = "Degraded"
                table.insert(localDetails, "Global queue module is missing or has the wrong class.")
            end
            local localDetail = if #localDetails > 0 then table.concat(localDetails, " ")
                else "Local API and queue module checks are healthy."

            -- Preserve the existing aggregate state for compatibility. New fields below
            -- make the local result and cross-server service/sync state explicit.
            local state = "Healthy"
            local details = {}
            local startupPending = false

            if not enabledOk then
                state = "Degraded"
                table.insert(details, "Cross-server enablement status could not be read.")
            elseif enabled ~= true then
                state = "Disabled"
                table.insert(details, "Cross-server features are intentionally isolated or disabled; local server features remain available.")
            end
            if not apiReady then
                state = "Degraded"
                table.insert(details, "Global API folder or GlobalEvent is unavailable.")
            end
            if not queueReady then
                state = "Degraded"
                table.insert(details, "Global queue module is missing or has the wrong class.")
            end
            if not syncOk or type(sync) ~= "table" then
                state = "Degraded"
                table.insert(details, "Cross-server synchronization status is unavailable.")
            elseif sync.state == "Degraded" then
                state = "Degraded"
                table.insert(details, tostring(sync.detail or "Cross-server messaging heartbeat has stopped."))
            elseif sync.state == "Unverified" or sync.state == "Starting" then
                startupPending = true
                table.insert(details, tostring(sync.detail or "No other server has been observed yet; cross-server sync is unverified."))
            end
            if not recoveryOk or type(recovery) ~= "table" then
                state = "Degraded"
                table.insert(details, "Recovery service status is unavailable.")
            elseif recovery.state == "Degraded" then
                state = "Degraded"
                table.insert(details, tostring(recovery.detail or "Queue storage probe has failed."))
            elseif recovery.state == "Starting" then
                startupPending = true
                table.insert(details, tostring(recovery.detail or "Waiting for the first authoritative shared-queue probe."))
            elseif recovery.state == "CatalogChangePending" then
                state = "Degraded"
                table.insert(details, tostring(recovery.detail or "A catalog reservation requires its original operation to be resumed."))
            elseif recovery.state == "Disabled" and state == "Healthy" then
                state = "Disabled"
                table.insert(details, "Cross-server recovery checks are disabled.")
            end

            if state == "Healthy" and startupPending then
                state = "Starting"
            end
            local detail = if #details > 0 then table.concat(details, " ") else "Global API, queue module, and shared queue storage probe are healthy."
            self.status = {
                state = state,
                detail = detail,
                updatedAt = os.time(),
                localState = localState,
                localDetail = localDetail,
                serviceState = if not enabledOk then "Unavailable" else if enabled == true then "Enabled" else "Disabled",
                recoveryState = if recoveryOk and type(recovery) == "table" then recovery.state else "Unavailable",
                recoveryDetail = if recoveryOk and type(recovery) == "table" then tostring(recovery.detail or "") else "Recovery status is unavailable.",
                syncState = if syncOk and type(sync) == "table" then sync.state else "Unavailable",
                syncDetail = if syncOk and type(sync) == "table" then tostring(sync.detail or "") else "Cross-server synchronization status is unavailable.",
                syncStatus = if syncOk and type(sync) == "table" then table.clone(sync) else nil,
            }

            local signature = state .. "|" .. detail
            if signature ~= self.lastSignature then
                self.lastSignature = signature
                if state == "Degraded" and type(dependencies.reportError) == "function" then
                    pcall(dependencies.reportError, "GlobalHealth", "HealthCheck", detail, dependencies.apiFolder)
                end
                if state == "Degraded" then
                    warn("[ClubMusic Global Health] " .. detail)
                else
                    print("[ClubMusic Global Health][" .. state .. "] " .. detail)
                end
            end

            pcall(function()
                dependencies.apiFolder:SetAttribute("HealthStatus", state)
                dependencies.apiFolder:SetAttribute("HealthDetail", detail)
                dependencies.apiFolder:SetAttribute("LocalHealthStatus", localState)
                dependencies.apiFolder:SetAttribute("LocalHealthDetail", localDetail)
                dependencies.apiFolder:SetAttribute("GlobalServiceStatus", self.status.serviceState)
                dependencies.apiFolder:SetAttribute("HealthUpdatedAt", self.status.updatedAt)
                dependencies.apiFolder:SetAttribute("RecoveryStatus", self.status.recoveryState)
                dependencies.apiFolder:SetAttribute("SyncStatus", self.status.syncState)
                dependencies.apiFolder:SetAttribute("SyncDetail", self.status.syncDetail)
                dependencies.apiFolder:SetAttribute("SyncPeerCount", if self.status.syncStatus then self.status.syncStatus.peerCount else 0)
            end)

            task.wait(math.max(10, dependencies.intervalSeconds or 30))
        end
    end)

    return true
end

function HealthService:Stop()
    self.running = false
end

return HealthService
