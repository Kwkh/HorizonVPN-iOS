import NetworkExtension
import OSLog
import Hako

// Mutable core state is confined to lifecycle; platform/cancellation
// access from NE callbacks is protected by lock. Probe results re-enter lifecycle.
final class PacketTunnelProvider: NEPacketTunnelProvider, @unchecked Sendable {
    private let logger = Logger(subsystem: "Kenote.Clash.PacketTunnel", category: "lifecycle")
    private let lifecycle = DispatchQueue(label: "Kenote.Clash.core-lifecycle")
    private let lock = NSLock()
    private var cancellationRequested = false
    private var platform: CorePlatform?
    // Accessed only on lifecycle queue.
    private var service: HakoBoxService?
    private var coreRunning = false
    private var activePrepared: PrototypeConfiguration.Prepared?
    private var activeRules: [String] = []
    private var capture = ConnectionCapture()
    private var captureTimer: DispatchSourceTimer?
    private var dnsInspection: InspectionReply?
    private var activeNode: String?
    private var generation = UUID()
    private var probeRunning = false
    private var activeNodes: [String] = []
    private var configurationID = ""
    private var connectedAt = Date()
    private var batch: BatchProbeRunner?
    private let trafficRecorder = TunnelTrafficRecorder()

    private var probeNode: String? {
        guard let catalog = activePrepared?.catalog else { return nil }
        let choices = RuntimeGroupChoices.sanitize(HakoProxiesJSON(), catalog: catalog) ?? [:]
        return catalog.resolvedTarget(runtimeChoices: RuntimeGroupChoices.names(choices, catalog: catalog))
    }

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        logger.notice("phase2.provider.entered")
        lock.lock(); cancellationRequested = false; lock.unlock()
        lifecycle.async { [self] in
            do {
                guard service == nil,
                      let protocolConfig = protocolConfiguration as? NETunnelProviderProtocol,
                      protocolConfig.providerConfiguration?["purpose"] as? String == PrototypeConfiguration.policyVersion,
                      let stored = try ConfigurationVault.loadRecord() else { throw PrototypeError.missingConfiguration }
                let source = stored.source
                let initial = try PrototypeConfiguration.prepare(source, choices: stored.choices)
                try stored.requireCertificateConsent(for: initial)
                guard !initial.isFixture else { throw PrototypeError.missingConfiguration }
                try checkCancellation()
                logger.notice("phase2.config.accepted")
                try autoreleasepool { try CoreRuntime.setup(in: ConfigurationResources.directory) }
                try CoreRuntime.prepareResources(initial, validateGeo: false)
                logger.notice("phase2.core.setup")
                let bootstrap = initial.needsSystemBootstrap ? try BootstrapResolver.capture() : []
                logger.notice("phase2.bootstrap.captured count=\(bootstrap.count, privacy: .public)")
                let config = try PrototypeConfiguration.prepare(source, bootstrapServers: bootstrap, choices: stored.choices)
                var validationError: NSError?
                guard HakoCheckConfig(config.runtimeJSON, &validationError) else { throw PrototypeError.coreValidation }
                let host = CorePlatform(provider: self)
                lock.lock(); platform = host; lock.unlock()
                try host.preparePath()
                try checkCancellation()
                logger.notice("phase2.physical-path.ready")
                let core = try CoreRuntime.makeService(platform: host)
                service = core
                logger.notice("phase2.core.service-created")
                logger.notice("phase2.core.starting")
                do {
                    try core.start(config.runtimeJSON)
                } catch {
                    // Inspect only in memory; emit one fixed category, never Go error text.
                    let category = CoreStartDiagnostic.classify(error)
                    let reason = CoreStartDiagnostic.systemReason(error)
                    logger.error("phase2.core.start-category=\(category.rawValue, privacy: .public) reason=\(reason, privacy: .public)")
                    throw host.startupFailure ?? PrototypeError.start
                }
                try checkCancellation()
                guard core.status() == "running" else { throw PrototypeError.start }
                // Providers may supply select members; restore choices after the core materializes them.
                for group in config.catalog.groups where group.allowsSelection {
                    if let member = config.catalog.choices[group.name] {
                        var selectionError: NSError?
                        guard HakoSelectProxy(group.name, member, &selectionError) else { throw PrototypeError.start }
                    }
                }
                coreRunning = true
                activePrepared = config
                activeRules = ((try? JSONSerialization.jsonObject(with: Data(config.runtimeJSON.utf8))) as? [String: Any])?["rules"] as? [String] ?? []
                activeNode = config.catalog.groups.contains(where: { $0.name == config.catalog.matchTarget }) ? config.catalog.matchTarget : config.nodeName
                activeNodes = config.catalog.nodes.map(\.name)
                configurationID = RuntimeIdentity.fingerprint(source: stored.source, choices: config.catalog.choices)
                connectedAt = Date()
                trafficRecorder.start(on: lifecycle) { [weak self] in self?.trafficSample() }
                logger.notice("phase2.core.running")
                ConnectionWidgetState.publish(phase: .connected)
                completionHandler(nil)
            } catch {
                let failure = error as? PrototypeError ?? .start
                logger.error("phase2.start.failed code=\(failure.rawValue, privacy: .public)")
                cleanup()
                setTunnelNetworkSettings(nil) { _ in
                    ConnectionWidgetState.publish(phase: .disconnected)
                    completionHandler(failure.tunnelError)
                }
            }
        }
    }

    private func clearCapture() {
        captureTimer?.cancel(); captureTimer = nil; capture.clear()
    }
    private func sampleCapture() {
        let now = ProcessInfo.processInfo.systemUptime
        capture.expire(now: now)
        guard capture.expiresAt != nil else { clearCapture(); return }
        guard capture.running(now: now), let current = activePrepared, coreRunning else { return }
        if let values = CapturedConnection.sanitize(HakoConnectionsJSON(), catalog: current.catalog, rules: activeRules, now: Date()) {
            capture.ingest(values, now: now)
        }
    }
    private func fillCaptureReply(_ reply: inout InspectionReply) {
        let now = ProcessInfo.processInfo.systemUptime
        capture.expire(now: now)
        reply.capture = capture.rows
        reply.captureSecondsRemaining = max(0, Int(ceil((capture.endsAt ?? now) - now)))
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        let requestedAt = ProcessInfo.processInfo.systemUptime
        lock.lock(); cancellationRequested = true; let current = platform; lock.unlock()
        current?.cancelPending()
        lifecycle.async { [self] in
            let queueMilliseconds = Int((ProcessInfo.processInfo.systemUptime - requestedAt) * 1_000)
            logger.notice("phase2.stop.queue ms=\(queueMilliseconds, privacy: .public)")
            cleanup()
            let settingsAt = ProcessInfo.processInfo.systemUptime
            setTunnelNetworkSettings(nil) { _ in
                let settingsMilliseconds = Int((ProcessInfo.processInfo.systemUptime - settingsAt) * 1_000)
                let totalMilliseconds = Int((ProcessInfo.processInfo.systemUptime - requestedAt) * 1_000)
                self.logger.notice("phase2.stop.network-settings ms=\(settingsMilliseconds, privacy: .public)")
                self.logger.notice("phase2.stop.total ms=\(totalMilliseconds, privacy: .public)")
                self.logger.notice("phase2.provider.stopped")
                ConnectionWidgetState.publish(phase: .disconnected)
                completionHandler()
            }
        }
    }
    private func checkCancellation() throws {
        lock.lock(); let stopped = cancellationRequested; lock.unlock()
        if stopped { throw PrototypeError.cancelled }
    }
    private func cleanup() {
        trafficRecorder.stop()
        clearCapture()
        batch?.cancel(); batch = nil
        activeNodes = []; configurationID = ""
        activePrepared = nil; activeRules = []; dnsInspection = nil
        coreRunning = false
        activeNode = nil
        generation = UUID()
        probeRunning = false
        let coreAt = ProcessInfo.processInfo.systemUptime
        try? service?.close()
        service = nil
        let coreMilliseconds = Int((ProcessInfo.processInfo.systemUptime - coreAt) * 1_000)
        logger.notice("phase2.cleanup.core ms=\(coreMilliseconds, privacy: .public)")
        let resourcesAt = ProcessInfo.processInfo.systemUptime
        try? FileManager.default.removeItem(at: ConfigurationResources.directory)
        let resourcesMilliseconds = Int((ProcessInfo.processInfo.systemUptime - resourcesAt) * 1_000)
        logger.notice("phase2.cleanup.resources ms=\(resourcesMilliseconds, privacy: .public)")
        let platformAt = ProcessInfo.processInfo.systemUptime
        lock.lock(); let current = platform; platform = nil; lock.unlock()
        current?.stop()
        let platformMilliseconds = Int((ProcessInfo.processInfo.systemUptime - platformAt) * 1_000)
        logger.notice("phase2.cleanup.platform ms=\(platformMilliseconds, privacy: .public)")
        reasserting = false
    }
    func bridgeFailed() {
        lock.lock(); cancellationRequested = true; let current = platform; lock.unlock()
        current?.cancelPending()
        lifecycle.async { [self] in
            logger.error("phase2.bridge.failed")
            cleanup()
            cancelTunnelWithError(PrototypeError.bridge.tunnelError)
        }
    }
    func physicalPathChanged(ready: Bool) {
        lifecycle.async { [self] in
            guard coreRunning else { return }
            reasserting = !ready
            if !ready { batch?.cancel() }
            logger.notice("phase2.physical-path.ready=\(ready, privacy: .public)")
        }
    }
    private func activityTargetID() -> String {
        ActivityNodePingCommand.targetID(configurationID: configurationID,
            selections: activePrepared.flatMap { RuntimeGroupChoices.sanitize(HakoProxiesJSON(), catalog: $0.catalog) })
    }
    private func trafficSample() -> LiveTelemetry? {
        guard coreRunning else { return nil }
        let totals = try? JSONDecoder().decode(TrafficTotals.self, from: Data(HakoWidgetStatsJSON("").utf8))
        lock.lock(); let network = platform?.networkCounters(); lock.unlock()
        return LiveTelemetry(version: 2, sessionID: generation, configurationID: configurationID,
            sampledAt: Date(), uptime: ProcessInfo.processInfo.systemUptime, connectedAt: connectedAt,
            uploadBytes: totals?.upTotal, downloadBytes: totals?.downTotal,
            coreReady: coreRunning, transport: network?.transport ?? "other")
    }
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        if messageData == Data(TelemetryHistory.command.utf8) {
            lifecycle.async { [self] in
                guard coreRunning else { completionHandler?(nil); return }
                trafficRecorder.catchUp { trafficSample() }
                var samples = trafficRecorder.samples
                if !samples.isEmpty {
                    samples[samples.count - 1].groupSelections = activePrepared.flatMap {
                        RuntimeGroupChoices.sanitize(HakoProxiesJSON(), catalog: $0.catalog)
                    }
                }
                let data = try? JSONEncoder().encode(TelemetryHistory(version: 1, samples: samples))
                completionHandler?(data.flatMap { $0.count <= TelemetryHistory.maximumBytes ? $0 : nil })
            }
            return
        }
        if messageData.count <= 2048,
           let command = try? JSONDecoder().decode(SelectionCommand.self, from: messageData), command.kind == "selection.v1" {
            lifecycle.async { [self] in
                var accepted = false
                if coreRunning, command.sessionID == generation, command.configurationID == configurationID,
                   !probeRunning, let current = activePrepared,
                   current.catalog.groups.indices.contains(command.group) {
                    let group = current.catalog.groups[command.group]
                    if group.allowsSelection, group.members.indices.contains(command.member) {
                        var choices = current.catalog.choices
                        choices[group.name] = group.members[command.member]
                        // Validate first. Runtime configuration itself stays in place; only selector changes.
                        if let updated = try? PrototypeConfiguration.prepare(current.source, choices: choices) {
                            var error: NSError?
                            if HakoSelectProxy(group.name, group.members[command.member], &error) {
                                activePrepared = updated
                                activeNode = updated.catalog.groups.contains(where: { $0.name == updated.catalog.matchTarget }) ? updated.catalog.matchTarget : updated.nodeName
                                configurationID = RuntimeIdentity.fingerprint(source: current.source, choices: choices)
                                dnsInspection = nil
                                clearCapture()
                                accepted = true
                            }
                        }
                    }
                }
                let reply = SelectionReply(requestID: command.requestID, sessionID: generation,
                    configurationID: configurationID, accepted: accepted)
                completionHandler?(try? JSONEncoder().encode(reply))
            }
            return
        }
        if messageData.count <= 2048,
           let command = try? JSONDecoder().decode(InspectionCommand.self, from: messageData), command.kind == "inspection.v1" {
            lifecycle.async { [self] in
                var reply = InspectionReply(requestID: command.requestID, sessionID: generation, configurationID: configurationID)
                guard coreRunning, command.sessionID == generation, command.configurationID == configurationID,
                      let current = activePrepared else { completionHandler?(nil); return }
                switch command.action {
                case .rules:
                    if let observations = RuleObservation.sanitize(HakoConnectionsJSON(), catalog: current.catalog, rules: activeRules) {
                        reply.rules = observations
                    } else { reply.state = "unavailable" }
                case .captureStart:
                    clearCapture()
                    capture.start(now: ProcessInfo.processInfo.systemUptime)
                    let timer = DispatchSource.makeTimerSource(queue: lifecycle)
                    timer.schedule(deadline: .now(), repeating: 1)
                    timer.setEventHandler { [weak self] in self?.sampleCapture() }
                    captureTimer = timer; timer.resume()
                    fillCaptureReply(&reply)
                case .capturePoll:
                    fillCaptureReply(&reply)
                case .captureClear:
                    clearCapture(); reply.capture = []; reply.captureSecondsRemaining = 0
                case .dnsStart:
                    guard let domain = command.domain, DNSStage.validDomain(domain), !probeRunning,
                          batch?.status.phase != .running else {
                        reply.state = "busy"; completionHandler?(try? JSONEncoder().encode(reply)); return
                    }
                    reply.state = "running"; dnsInspection = reply; probeRunning = true
                    let ticket = generation, identity = configurationID, node = probeNode
                    DispatchQueue.global(qos: .utility).async { [self] in
                        let stages = DNSInspection.run(domain: domain, node: node)
                        lifecycle.async { [self] in
                            guard ticket == generation, identity == configurationID else { return }
                            probeRunning = false
                            dnsInspection = InspectionReply(requestID: command.requestID, sessionID: ticket,
                                configurationID: identity, dns: stages)
                        }
                    }
                case .dnsPoll:
                    if let result = dnsInspection, result.requestID == command.requestID { reply = result }
                    else { reply.state = "unavailable" }
                }
                completionHandler?(try? JSONEncoder().encode(reply))
            }
            return
        }
        if messageData == Data("telemetry.v2".utf8) {
            lifecycle.async { [self] in
                guard var sample = trafficSample() else { completionHandler?(nil); return }
                sample.groupSelections = activePrepared.flatMap { RuntimeGroupChoices.sanitize(HakoProxiesJSON(), catalog: $0.catalog) }
                completionHandler?(try? JSONEncoder().encode(sample))
            }
            return
        }
        if messageData.count <= 32768,
           let command = try? JSONDecoder().decode(BatchProbeCommand.self, from: messageData) {
            lifecycle.async { [self] in
                let valid = coreRunning && command.isValid(nodeCount: activeNodes.count,
                    sessionID: generation, configurationID: configurationID, batch: batch?.status)
                var response = BatchProbeStatus(version: command.version, batchID: command.batchID, sessionID: generation,
                    configurationID: configurationID, phase: .unavailable, results: [])
                guard valid else { completionHandler?(try? JSONEncoder().encode(response)); return }
                switch command.action {
                case .start:
                    if let status = batch?.status, command.matches(status) { batch?.renewLease() }
                    else if probeRunning || batch?.status.phase == .running { response.phase = .busy }
                    else {
                        batch = BatchProbeRunner(command: command, names: activeNodes, queue: lifecycle)
                        batch?.start()
                    }
                case .enqueue:
                    if let status = batch?.status, command.matches(status), status.version == 3 {
                        batch?.enqueue(command.nodeIndices ?? [])
                    }
                case .poll:
                    if let status = batch?.status, command.matches(status) { batch?.renewLease() }
                case .cancel:
                    if let status = batch?.status, command.matches(status) { batch?.cancel() }
                }
                if let status = batch?.status, command.matches(status) { response = status }
                completionHandler?(try? JSONEncoder().encode(response))
            }
            return
        }
        let activityPing = messageData.count <= 1024 ? (try? JSONDecoder().decode(ActivityNodePingCommand.self, from: messageData)) : nil
        if messageData == Data("ping.v1".utf8) || activityPing?.kind == "activity-node-ping.v1" {
            lifecycle.async { [self] in
                if let command = activityPing {
                    guard command.sessionID == generation, command.targetID == activityTargetID() else {
                        completionHandler?(nil); return
                    }
                }
                guard coreRunning, let node = activeNode else {
                    completionHandler?(try? JSONEncoder().encode(PingReport(outcome: .unavailable)))
                    return
                }
                guard !probeRunning, batch?.status.phase != .running else {
                    completionHandler?(try? JSONEncoder().encode(PingReport(outcome: .busy)))
                    return
                }
                let ticket = generation
                probeRunning = true
                DispatchQueue.global(qos: .utility).async { [self] in
                    let result = PingReport(coreDelay: HakoURLTestWithTimeout(node, PingReport.testURL, PingReport.timeoutMilliseconds))
                    lifecycle.async { [self] in
                        guard ticket == generation, coreRunning else { completionHandler?(nil); return }
                        probeRunning = false
                        if let command = activityPing, command.targetID != activityTargetID() {
                            completionHandler?(nil); return
                        }
                        completionHandler?(try? JSONEncoder().encode(result))
                    }
                }
            }
            return
        }
        if messageData == Data("connectivity.v1".utf8) {
            lifecycle.async { [self] in
                guard coreRunning, !probeRunning, batch?.status.phase != .running, let node = probeNode else { completionHandler?(nil); return }
                let ticket = generation
                probeRunning = true
                DispatchQueue.global(qos: .utility).async { [self] in
                    let result = ConnectivityProbe.run(nodeName: node)
                    lifecycle.async { [self] in
                        guard ticket == generation, coreRunning else { completionHandler?(nil); return }
                        probeRunning = false
                        logger.notice("phase2.probe nodeHTTPS=\(result.nodeResponded, privacy: .public) dns=\(result.dns.rawValue, privacy: .public)")
                        completionHandler?(try? JSONEncoder().encode(result))
                    }
                }
            }
            return
        }
        guard messageData == Data("snapshot.v1".utf8) else { completionHandler?(nil); return }
        lifecycle.async { [self] in
            lock.lock(); let current = platform; lock.unlock()
            let stats = current?.snapshot()
            // Decode numeric counters only; never forward arbitrary core JSON.
            let outbound = try? JSONDecoder().decode(OutboundCounters.self, from: Data(HakoWidgetStatsJSON("").utf8))
            let network = current?.networkCounters()
            let snapshot = TunnelSnapshot(coreRunning: coreRunning,
                packetsFromSystem: stats?.packetsFromSystem ?? 0,
                packetsToSystem: stats?.packetsToSystem ?? 0,
                droppedPackets: (stats?.droppedToCore ?? 0) + (stats?.droppedToSystem ?? 0),
                memoryBytes: HakoMemoryFootprint(),
                proxyUploadBytes: outbound?.byOutbound.proxy.up,
                proxyDownloadBytes: outbound?.byOutbound.proxy.down,
                bindingSuccesses: network?.successes, bindingFailures: network?.failures,
                physicalTransport: network?.transport)
            completionHandler?(try? JSONEncoder().encode(snapshot))
        }
    }
}

private struct TrafficTotals: Decodable {
    let upTotal: Int64
    let downTotal: Int64
}

private struct OutboundCounters: Decodable {
    struct Bytes: Decodable { let up: Int64; let down: Int64 }
    struct Outbound: Decodable { let proxy: Bytes }
    let byOutbound: Outbound
}
