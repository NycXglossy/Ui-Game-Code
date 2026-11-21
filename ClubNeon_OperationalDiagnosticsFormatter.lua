--!strict
-- Formats the detailed read-only operational diagnostics response for the admin bridge.
-- Inputs are injected so this module owns no controller state or service connections.
return function(globalCall: any, purchaseEntries: {any}): (boolean, string)
		local ok, snapshot = globalCall("GetGlobalDiagnostics")
		if not ok or typeof(snapshot) ~= "table" then return false, tostring(snapshot or "Diagnostic snapshot is unavailable.") end
		local health = if typeof(snapshot.health) == "table" then snapshot.health else {}
		local recovery = if typeof(snapshot.recovery) == "table" then snapshot.recovery else {}
		local sync = if typeof(snapshot.syncStatus) == "table" then snapshot.syncStatus else {}
		local services = if typeof(snapshot.operationalServices) == "table" then snapshot.operationalServices else {}
		local watchdog = if typeof(services.watchdog) == "table" then services.watchdog else {}
		local watchdogIssues = if typeof(watchdog.issues) == "table" then watchdog.issues else {}
		local watchdogDetail = if #watchdogIssues > 0 then table.concat(watchdogIssues, " | ") else "none reported"
		local serverHealth = if typeof(services.serverHealth) == "table" then services.serverHealth else {}
		local heartbeat = if typeof(serverHealth.heartbeat) == "table" then serverHealth.heartbeat else {}
		local memory = if typeof(serverHealth.memory) == "table" then serverHealth.memory else {}
		local registry = if typeof(services.serviceRegistry) == "table" then services.serviceRegistry else {}
		local registryCounts = if typeof(registry.counts) == "table" then registry.counts else {}
		local healthTransitions = if typeof(health.healthHistory) == "table" then health.healthHistory else {}
		local latestHealthTransition = if #healthTransitions > 0 and typeof(healthTransitions[#healthTransitions]) == "table"
			then healthTransitions[#healthTransitions] else {}
		local errorHistory = if typeof(services.errorHistory) == "table" then services.errorHistory else {}
		local securityHealth = if typeof(services.securityHealth) == "table" then services.securityHealth else {}
		local securityComponents = if typeof(securityHealth.components) == "table" then securityHealth.components else {}
		local observabilityHealth = if typeof(services.observabilityHealth) == "table" then services.observabilityHealth else {}
		local adaptiveLoad = if typeof(services.adaptiveLoad) == "table" then services.adaptiveLoad else {}
		local adaptiveTaskStats = if typeof(adaptiveLoad.taskStats) == "table" then adaptiveLoad.taskStats else {}
		local function adaptiveUsage(name: string): string
			local item = if typeof(adaptiveTaskStats[name]) == "table" then adaptiveTaskStats[name] else {}
			return tostring(item.accepted or 0) .. "/" .. tostring(item.deferred or 0)
		end
		local securityReplay = if typeof(services.securityReplay) == "table" then services.securityReplay else {}
		local safeCall = if typeof(services.safeCall) == "table" then services.safeCall else {}
		local threatIntelligence = if typeof(services.threatIntelligence) == "table" then services.threatIntelligence else {}
		local honeypot = if typeof(services.honeypot) == "table" then services.honeypot else {}
		local clientIntegrity = if typeof(services.clientIntegrityTelemetry) == "table" then services.clientIntegrityTelemetry else {}
		local controller = if typeof(services.controller) == "table" then services.controller else {}
		local purchase = if typeof(controller.purchase) == "table" then controller.purchase else {}
		local moderation = if typeof(controller.moderation) == "table" then controller.moderation else {}
		local controllerPlayback = if typeof(controller.playback) == "table" then controller.playback else {}
		local securityMonitor = if typeof(services.securityMonitor) == "table" then services.securityMonitor else {}
		local resourceGuard = if typeof(securityMonitor.resourceGuard) == "table" then securityMonitor.resourceGuard else {}
		local resourceLanes = if typeof(resourceGuard.lanes) == "table" then resourceGuard.lanes else {}
		local writeLane = if typeof(resourceLanes.MemoryStoreWrite) == "table" then resourceLanes.MemoryStoreWrite else {}
		local readLane = if typeof(resourceLanes.MemoryStoreRead) == "table" then resourceLanes.MemoryStoreRead else {}
		local auditStatus = if typeof(services.audit) == "table" then services.audit else {}
		local storageGuard = if typeof(auditStatus.storageGuard) == "table" then auditStatus.storageGuard else {}
		local characterPhysics = if typeof(services.characterPhysics) == "table" then services.characterPhysics else {}
		local clientTelemetry = if typeof(snapshot.clientTelemetry) == "table" then snapshot.clientTelemetry else {}
		local _, globalOperational = globalCall("GetGlobalOperationalStatus")
		local messaging = if typeof(globalOperational) == "table" and typeof(globalOperational.Messaging) == "table" then globalOperational.Messaging else {}
		local memoryStore = if typeof(services.memoryStore) == "table" then services.memoryStore else {}
		local lines = {
			"ClubMusic Diagnostic Snapshot:",
			"Generated: " .. os.date("!%Y-%m-%d %H:%M:%S UTC", tonumber(snapshot.generatedAt) or os.time()),
			"Global enabled: " .. tostring(snapshot.serviceEnabled == true),
			"Local health: " .. tostring(health.state or "Unavailable") .. " / " .. tostring(health.localState or "Unavailable"),
			"Health dimensions: cross-server " .. tostring(health.crossServerState or "Unavailable")
				.. " | performance " .. tostring(health.performanceState or "Unavailable")
				.. " | watchdog " .. tostring(health.watchdogState or "Unavailable"),
			"Health trend: state age " .. tostring(health.stateDurationSeconds or 0) .. "s"
				.. " | degraded duration " .. tostring(health.degradedDurationSeconds or 0) .. "s"
				.. " | consecutive degraded checks " .. tostring(health.consecutiveDegradedChecks or 0)
				.. " | transitions retained " .. tostring(#healthTransitions) .. "/" .. tostring(health.healthHistoryCapacity or 20)
				.. " | last recovery " .. tostring(health.lastRecoveredAt or "none"),
			"Last health transition: " .. tostring(latestHealthTransition.from or "n/a")
				.. " -> " .. tostring(latestHealthTransition.to or "n/a")
				.. " | " .. tostring(latestHealthTransition.detail or "No transition recorded."),
			"Server runtime: " .. tostring(serverHealth.state or "NotInstalled")
				.. " | average FPS " .. tostring(if typeof(heartbeat.averageFps) == "number" then math.floor(heartbeat.averageFps + 0.5) else "n/a")
				.. " | max frame " .. tostring(math.floor((tonumber(heartbeat.maxFrameMilliseconds) or 0) * 10) / 10) .. "ms"
				.. " | Memory " .. tostring(memory.usageMb or "n/a") .. " MB (" .. tostring(memory.state or "n/a") .. ")"
				.. " | trend " .. tostring(memory.changeSinceOldestSampleMb or "n/a") .. " MB",
			"Service registry: " .. tostring(registry.state or "NotInstalled")
				.. " | total " .. tostring(registry.serviceCount or 0)
				.. " | healthy " .. tostring(registryCounts.Healthy or 0)
				.. " | degraded " .. tostring(registryCounts.Degraded or 0)
				.. " | unavailable " .. tostring(registryCounts.Unavailable or 0)
				.. " | misconfigured " .. tostring(registryCounts.Misconfigured or 0)
				.. " | verified dependencies " .. tostring(registry.dependencyCount or 0),
			"Recovery: " .. tostring(recovery.state or "Unavailable"),
			"Watchdog: " .. tostring(watchdog.state or "Unavailable"),
			"Observability: " .. tostring(observabilityHealth.state or "Unavailable")
				.. " | Adaptive load " .. tostring(adaptiveLoad.mode or adaptiveLoad.state or "NotInstalled")
				.. " | Replay " .. tostring(securityReplay.state or "NotInstalled")
				.. " (" .. tostring(securityReplay.retained or 0) .. "/" .. tostring(securityReplay.capacity or 0) .. ")",
			"Adaptive load trend: mode duration " .. tostring(math.floor((tonumber(adaptiveLoad.currentModeDurationSeconds) or 0) + 0.5)) .. "s"
				.. " | healthy recovery windows " .. tostring(adaptiveLoad.recoveryHealthyWindowStreak or adaptiveLoad.healthyStreak or 0)
				.. " | transitions " .. tostring(adaptiveLoad.transitions or 0)
				.. " | reason " .. string.sub(tostring(adaptiveLoad.lastTransitionReason or "n/a"), 1, 100),
			"Adaptive accepted/deferred (Analytics/Diagnostics/Replay/Threat/Maintenance): "
				.. adaptiveUsage("AnalyticsAggregation") .. " / " .. adaptiveUsage("DiagnosticsSampling") .. " / "
				.. adaptiveUsage("ReplayQueries") .. " / " .. adaptiveUsage("ThreatReviewQueries") .. " / "
				.. adaptiveUsage("BackgroundMaintenance"),
			"SafeCall: " .. tostring(safeCall.calls or 0) .. " calls | failures "
				.. tostring(safeCall.failures or 0) .. " | recovered " .. tostring(safeCall.recovered or 0),
			"Threat intelligence: " .. tostring(threatIntelligence.state or "NotInstalled")
				.. " | review items " .. tostring(threatIntelligence.openReviewItems or 0)
				.. "/" .. tostring(threatIntelligence.maxReviewItems or 0)
				.. " | tracked subjects " .. tostring(threatIntelligence.trackedSubjects or 0)
				.. " | raid reviews " .. tostring(threatIntelligence.raidReviewItems or 0)
				.. " | join window " .. tostring(threatIntelligence.cohortWindowJoins or 0)
				.. " | signaled players " .. tostring(threatIntelligence.cohortSignaledPlayers or 0)
				.. " | unknown codes " .. tostring(threatIntelligence.unknownSignals or 0),
			"Honeypot: " .. tostring(honeypot.state or "NotInstalled")
				.. " | hits " .. tostring(honeypot.totalHits or 0)
				.. " | suppressed " .. tostring(honeypot.suppressedHits or 0)
				.. " | decoys " .. tostring(honeypot.decoyRemoteCount or 0),
			"Client integrity telemetry: " .. tostring(clientIntegrity.state or "NotInstalled")
				.. " | accepted " .. tostring(clientIntegrity.acceptedReports or 0)
				.. " | rejected " .. tostring(clientIntegrity.rejectedReports or 0)
				.. " | duplicate " .. tostring(clientIntegrity.duplicateReports or 0)
				.. " | untrusted=true; enforcement=false",
			"SecurityCore health: " .. tostring(securityHealth.state or "Unavailable")
				.. " (" .. tostring(securityHealth.observedComponents or 0) .. "/" .. tostring(securityHealth.totalComponents or 0) .. " observed)"
				.. " | Auth " .. tostring(securityComponents.authorization or "Unavailable")
				.. " | RateLimit " .. tostring(securityComponents.rateLimit or "Unavailable")
				.. " | Validation " .. tostring(securityComponents.messageValidation or "Unavailable")
				.. " | Audit " .. tostring(securityComponents.audit or "Unavailable")
				.. " | Incidents " .. tostring(securityComponents.incidentResponse or "Unavailable")
				.. " | Physics " .. tostring(securityComponents.characterPhysics or "Unavailable"),
			"Watchdog detail: " .. string.sub(watchdogDetail, 1, 300),
			"Error history: " .. tostring(errorHistory.count or 0) .. "/" .. tostring(errorHistory.maxRecords or 50)
				.. " records | repeats " .. tostring(errorHistory.totalRepeats or 0),
			"Messaging: " .. tostring(messaging.state or "Unavailable")
				.. " | published " .. tostring(messaging.published or 0)
				.. " | failures " .. tostring(messaging.publishFailures or 0)
				.. " | received " .. tostring(messaging.received or 0)
				.. " | rejected " .. tostring(messaging.rejected or 0),
			"MemoryStore limiter fallback: " .. tostring(memoryStore.capacityLimited == true),
			"Purchase: receipts " .. tostring(purchase.receiptCallbacks or 0)
				.. " | granted " .. tostring(purchase.granted or 0)
				.. " | pending " .. tostring(purchase.pending or 0)
				.. " | failures " .. tostring(purchase.failures or 0)
				.. " | duplicates " .. tostring(purchase.duplicates or 0),
			"Moderation lookups: " .. tostring(moderation.totalLookups or 0)
				.. " | success " .. tostring(moderation.successfulLookups or 0)
				.. " | failed/pending " .. tostring(moderation.failedLookups or 0),
			"Playback: " .. tostring(controllerPlayback.backend or "Unavailable")
				.. " | playing " .. tostring(controllerPlayback.playing == true)
				.. " | paused " .. tostring(controllerPlayback.paused == true)
				.. " | queue " .. tostring(controllerPlayback.queueDepth or 0)
				.. " | migration failures " .. tostring(controllerPlayback.migrationFailureCount or 0),
			"Security signals: " .. tostring(securityMonitor.totalSignals or 0)
				.. " | alerts " .. tostring(securityMonitor.alerts or 0)
				.. " | physics " .. tostring(characterPhysics.totalSignals or 0),
			"Movement observation: interval " .. tostring(if typeof(characterPhysics.movementMeasurement) == "table" then characterPhysics.movementMeasurement.sampleIntervalSeconds or "n/a" else "n/a")
				.. "s | samples " .. tostring(if typeof(characterPhysics.movementMeasurement) == "table" then characterPhysics.movementMeasurement.samples or 0 else 0)
				.. " | deferred " .. tostring(if typeof(characterPhysics.movementMeasurement) == "table" then characterPhysics.movementMeasurement.deferredSamples or 0 else 0)
				.. " | detection-only",
			"Resource guards: write " .. tostring(writeLane.active or 0) .. "/" .. tostring(writeLane.limit or 0)
				.. " rejected " .. tostring(writeLane.rejected or 0)
				.. " | read " .. tostring(readLane.active or 0) .. "/" .. tostring(readLane.limit or 0)
				.. " rejected " .. tostring(readLane.rejected or 0)
				.. " | storage circuit open " .. tostring(storageGuard.circuitOpen == true)
				.. " failures " .. tostring(storageGuard.failuresInWindow or 0),
			"Client performance telemetry: " .. tostring(clientTelemetry.state or "Unavailable")
				.. " | local-only, untrusted, not transmitted",
			"Client integrity reports are untrusted dependency observations; absence is not proof of tampering.",
			"Purchase telemetry: " .. tostring(#purchaseEntries) .. " recent server-local event(s):",
		}
		for index = math.max(1, #purchaseEntries - 3), #purchaseEntries do
			local item = purchaseEntries[index]
			table.insert(lines, string.format("Purchase %s | ID %d | %s | %s",
				item.source, item.itemId, item.outcome, string.sub(item.detail, 1, 90)))
		end
		return true, string.sub(table.concat(lines, "\n"), 1, 1900)
	end
	if operation == "OperationalServices" then
		local ok, services = globalCall("GetGlobalOperationalStatus")
		if not ok or typeof(services) ~= "table" then return false, tostring(services or "Operational service status is unavailable.") end
		local keys = {}
		for key in pairs(services) do table.insert(keys, tostring(key)) end
		table.sort(keys)
		local lines = {"ClubMusic Service Status:"}
		for _, key in ipairs(keys) do
			local item = services[key]
			table.insert(lines, key .. ": " .. tostring(if typeof(item) == "table" then item.state or "Unknown" else "Unavailable"))
		end
		return true, string.sub(table.concat(lines, "\n"), 1, 1500)
end
