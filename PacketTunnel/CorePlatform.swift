import Foundation
import NetworkExtension
import Hako
import OSLog

/// Go callbacks run on Go threads. Never hold this lock while entering Go or NE.
final class CorePlatform: NSObject, HakoPlatformInterfaceProtocol {
    private weak var provider: PacketTunnelProvider?
    private let condition = NSCondition()
    private let monitor = ApplePhysicalPathMonitor()
    private let logger = Logger(subsystem: "Kenote.Clash.PacketTunnel", category: "platform")
    private var path: PhysicalPathSnapshot?
    private var listener: HakoInterfaceUpdateListenerProtocol?
    private var cancelled = false
    private var bridge: PacketFlowBridge?
    private var tunnelAddresses = Set<String>()
    private var firstStartupFailure: PrototypeError?
    private var bindingSuccesses: UInt64 = 0
    private var bindingFailures: UInt64 = 0

    func networkCounters() -> (successes: UInt64, failures: UInt64, transport: String) {
        condition.lock(); defer { condition.unlock() }
        let kind = path?.interfaceType ?? "none"
        return (bindingSuccesses, bindingFailures, ["wifi", "cellular", "wired"].contains(kind) ? kind : "other")
    }

    var startupFailure: PrototypeError? {
        condition.lock(); defer { condition.unlock() }
        return firstStartupFailure
    }

    init(provider: PacketTunnelProvider) { self.provider = provider }

    func preparePath() throws {
        monitor.updateHandler = { [weak self] snapshot in
            guard let self else { return }
            self.condition.lock()
            guard !self.cancelled else { self.condition.unlock(); return }
            self.path = snapshot
            let listener = self.listener
            self.condition.broadcast()
            self.condition.unlock()
            self.publish(snapshot, to: listener)
            self.provider?.physicalPathChanged(ready: snapshot.isReady)
        }
        monitor.start(queue: DispatchQueue(label: "Kenote.Clash.physical-path"))
        condition.lock()
        defer { condition.unlock() }
        let deadline = Date(timeIntervalSinceNow: 10)
        while path?.isReady != true && !cancelled {
            if !condition.wait(until: deadline) { throw PrototypeError.physicalNetwork }
        }
        if cancelled { throw PrototypeError.cancelled }
    }
    func cancelPending() {
        condition.lock(); cancelled = true; condition.broadcast(); condition.unlock()
    }
    func stop() {
        cancelPending()
        monitor.cancel()
        condition.lock()
        let old = bridge
        bridge = nil
        listener = nil
        condition.unlock()
        old?.stop()
    }
    func snapshot() -> PacketFlowBridgeSnapshot? {
        condition.lock(); let current = bridge; condition.unlock()
        return current?.snapshot()
    }
    func underNetworkExtension() -> Bool { true }
    func usePlatformAutoDetectControl() -> Bool { true }
    func writeLog(_ message: String?) { /* Raw core text is deliberately discarded. */ }
    func autoDetectControl(_ fd: Int32) throws {
        condition.lock(); let index = path?.isReady == true ? path!.interfaceIndex : 0; let stopped = cancelled; condition.unlock()
        guard index != 0, !stopped else { throw PrototypeError.physicalNetwork }
        do {
            try PhysicalEgressBinding.apply(.bound(index: index), to: fd)
            condition.lock(); bindingSuccesses += 1; condition.unlock()
        } catch {
            condition.lock(); bindingFailures += 1; condition.unlock()
            logger.error("phase2.egress-binding.failed")
            throw PrototypeError.physicalNetwork
        }
    }
    func startDefaultInterfaceMonitor(_ listener: HakoInterfaceUpdateListenerProtocol?) throws {
        condition.lock(); self.listener = listener; let current = path; let stopped = cancelled; condition.unlock()
        guard let current, current.isReady, !stopped else { throw PrototypeError.physicalNetwork }
        publish(current, to: listener)
    }
    func closeDefaultInterfaceMonitor(_ listener: HakoInterfaceUpdateListenerProtocol?) throws {
        condition.lock(); self.listener = nil; condition.unlock()
    }
    private func publish(_ path: PhysicalPathSnapshot, to listener: HakoInterfaceUpdateListenerProtocol?) {
        listener?.updateDefaultInterface(path.interfaceName, interfaceIndex: Int32(clamping: path.interfaceIndex),
            isExpensive: path.expensive, isConstrained: path.constrained,
            supportsIPv4: path.supportsIPv4, supportsIPv6: path.supportsIPv6)
    }
    func getInterfaces() throws -> HakoNetworkInterfaceIteratorProtocol {
        condition.lock(); let current = path; let own = tunnelAddresses; condition.unlock()
        let records = PhysicalInterfaceInventory.build(raw: PhysicalInterfaceInventory.enumerate(),
            available: current?.availableInterfaces ?? [], pathIsExpensive: current?.expensive ?? false,
            defaultInterfaceIndex: current?.interfaceIndex ?? 0, ownTunnelAddresses: own)
        return InterfaceIterator(records.map { record in
            let value = HakoNetworkInterface()
            value.name = record.name
            value.index = Int32(clamping: record.index)
            value.mtu = record.mtu
            value.flags = record.flags.rawValue
            value.type = record.type.rawValue
            value.metered = record.metered
            value.addresses = StringIterator(record.addresses)
            return value
        })
    }
    func openTun(_ options: HakoTunOptionsProtocol?, ret0_: UnsafeMutablePointer<Int32>?) throws {
        logger.notice("phase2.tun.requested")
        do {
            try openPacketTunnel(options, ret0_: ret0_)
        } catch {
            let failure = error as? PrototypeError ?? .bridge
            condition.lock(); firstStartupFailure = firstStartupFailure ?? failure; condition.unlock()
            logger.error("phase2.tun.failed code=\(failure.rawValue, privacy: .public)")
            throw failure
        }
    }
    private func openPacketTunnel(_ options: HakoTunOptionsProtocol?, ret0_: UnsafeMutablePointer<Int32>?) throws {
        guard let options, let provider, let ret0_ else { throw PrototypeError.networkSettings }
        condition.lock(); let stopped = cancelled; condition.unlock()
        guard !stopped else { throw PrototypeError.cancelled }
        let v4 = prefixes(options.getInet4Address())
        let v6 = prefixes(options.getInet6Address())
        let dns = try options.getDNSServerAddress().value
        logger.notice("phase2.tun.options v4=\(v4.count, privacy: .public) v6=\(v6.count, privacy: .public) mtu=\(options.getMTU(), privacy: .public)")
        guard !v4.isEmpty, !v6.isEmpty, options.getMTU() == 1280,
              prefixes(options.getInet4RouteExcludeAddress()).isEmpty,
              prefixes(options.getInet6RouteExcludeAddress()).isEmpty,
              !dns.isEmpty else {
            throw PrototypeError.networkSettings
        }
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        let ipv4 = NEIPv4Settings(addresses: v4.map { $0.address() }, subnetMasks: v4.map { $0.mask() })
        ipv4.includedRoutes = [.default()]
        settings.ipv4Settings = ipv4
        let ipv6 = NEIPv6Settings(addresses: v6.map { $0.address() }, networkPrefixLengths: v6.map { NSNumber(value: $0.prefix()) })
        ipv6.includedRoutes = [.default()]
        settings.ipv6Settings = ipv6
        let resolver = NEDNSSettings(servers: [dns])
        resolver.matchDomains = [""]
        resolver.matchDomainsNoSearch = true
        settings.dnsSettings = resolver
        settings.mtu = 1280
        condition.lock(); tunnelAddresses = Set(v4.map { $0.address() } + v6.map { $0.address() }); condition.unlock()
        // Go's synchronous OpenTun runs off the provider lifecycle queue. Wait
        // for Apple's completion; returning early could install late stale routes.
        let finished = DispatchSemaphore(value: 0)
        var settingsError: Error?
        logger.notice("phase2.tun.settings-requested")
        provider.setTunnelNetworkSettings(settings) { error in settingsError = error; finished.signal() }
        finished.wait()
        guard settingsError == nil else { throw PrototypeError.networkSettings }
        logger.notice("phase2.tun.settings-applied")
        condition.lock(); let wasCancelled = cancelled; condition.unlock()
        guard !wasCancelled else { throw PrototypeError.cancelled }
        let flow = PacketFlowBridge(packetFlow: provider.packetFlow, maxPendingPackets: 256, maxPendingBytes: 512 * 1024) { [weak provider] _ in
            provider?.bridgeFailed()
        }
        let fd = try flow.start()
        logger.notice("phase2.tun.bridge-ready")
        condition.lock(); bridge = flow; condition.unlock()
        ret0_.pointee = fd // Hako duplicates this descriptor; bridge owns the original.
    }
    private func prefixes(_ iterator: HakoRoutePrefixIteratorProtocol?) -> [HakoRoutePrefix] {
        guard let iterator else { return [] }
        var result: [HakoRoutePrefix] = []
        while iterator.hasNext(), result.count < 16 {
            if let next = iterator.next() { result.append(next) } else { break }
        }
        return result
    }
}

private final class StringIterator: NSObject, HakoStringIteratorProtocol {
    private var values: [String]; private var index = 0
    init(_ values: [String]) { self.values = values }
    func hasNext() -> Bool { index < values.count }
    func len() -> Int32 { Int32(values.count) }
    func next() -> String { guard hasNext() else { return "" }; defer { index += 1 }; return values[index] }
}
private final class InterfaceIterator: NSObject, HakoNetworkInterfaceIteratorProtocol {
    private var values: [HakoNetworkInterface]; private var index = 0
    init(_ values: [HakoNetworkInterface]) { self.values = values }
    func hasNext() -> Bool { index < values.count }
    func len() -> Int32 { Int32(values.count) }
    func next() -> HakoNetworkInterface? { guard hasNext() else { return nil }; defer { index += 1 }; return values[index] }
}
