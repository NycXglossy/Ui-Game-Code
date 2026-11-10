--!strict
-- ClubMusic global health monitor.
-- This module observes service state only; it never owns playback or queue data.

local HealthService = {}
HealthService.__index = HealthService

export type Dependencies = {
    isEnabled: () -> boolean,
    getRecoveryStatus: () -> {[string]: any},
    apiFolder: Instance,
    queueModule: Instance,
    intervalSeconds: number?,
    reportError: ((string, string, any, Instance?) -> any)?,
}

function HealthService.new(dependencies: Dependencies)
    assert(type(dependencies) == "table", "HealthService requires dependencies")
    assert(type(dependencies.isEnabled) == "function", "HealthService requires isEnabled")
    assert(type(dependencies.getRecoveryStatus) == "function", "HealthService requires getRecoveryStatus")
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
            local apiReady = dependencies.apiFolder.Parent ~= nil
                and dependencies.apiFolder:FindFirstChild("GlobalEvent") ~= nil
            local queueReady = dependencies.queueModule:IsA("ModuleScript")

            local state = "Healthy"
            local details = {}

            if not enabledOk or enabled ~= true then
                state = "Disabled"
                table.insert(details, "Cross-server service is disabled or unavailable.")
            end
            if not apiReady then
                state = "Degraded"
                table.insert(details, "Global API folder or GlobalEvent is unavailable.")
            end
            if not queueReady then
                state = "Degraded"
                table.insert(details, "Global queue module is missing or has the wrong class.")
            end
            if not recoveryOk or type(recovery) ~= "table" then
                state = "Degraded"
                table.insert(details, "Recovery service status is unavailable.")
            elseif recovery.state == "Degraded" or recovery.state == "Starting" then
                state = "Degraded"
                table.insert(details, tostring(recovery.detail or "Queue storage probe has not recovered."))
            elseif recovery.state == "CatalogChangePending" then
                state = "Degraded"
                table.insert(details, tostring(recovery.detail or "A catalog reservation requires its original operation to be resumed."))
            elseif recovery.state == "Disabled" and state == "Healthy" then
                state = "Disabled"
                table.insert(details, "Cross-server recovery checks are disabled.")
            end

            local detail = if #details > 0 then table.concat(details, " ") else "Global API, queue module, and shared queue storage probe are healthy."
            self.status = {
                state = state,
                detail = detail,
                updatedAt = os.time(),
                recoveryState = if recoveryOk and type(recovery) == "table" then recovery.state else "Unavailable",
            }

            local signature = state .. "|" .. detail
            if signature ~= self.lastSignature then
                self.lastSignature = signature
                if state == "Degraded" and type(dependencies.reportError) == "function" then
                    pcall(dependencies.reportError, "GlobalHealth", "HealthCheck", detail, dependencies.apiFolder)
                end
                if state == "Healthy" then
                    print("[ClubMusic Global Health] " .. detail)
                elseif state ~= "Disabled" then
                    warn("[ClubMusic Global Health] " .. detail)
                else
                    print("[ClubMusic Global Health] " .. detail)
                end
            end

            pcall(function()
                dependencies.apiFolder:SetAttribute("HealthStatus", state)
                dependencies.apiFolder:SetAttribute("HealthDetail", detail)
                dependencies.apiFolder:SetAttribute("HealthUpdatedAt", self.status.updatedAt)
                dependencies.apiFolder:SetAttribute("RecoveryStatus", self.status.recoveryState)
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
