import Foundation
import Darwin

final class FakeFlow: PacketFlowIO, @unchecked Sendable {
    let lock = NSLock()
    var reader: (@Sendable ([Data], [NSNumber]) -> Void)?
    var writes: [Data] = []
    let readReady = DispatchSemaphore(value: 0)
    let writeReady = DispatchSemaphore(value: 0)
    func readPackets(completionHandler: @escaping @Sendable ([Data], [NSNumber]) -> Void) {
        lock.lock(); reader = completionHandler; lock.unlock(); readReady.signal()
    }
    func writePackets(_ packets: [Data], withProtocols protocols: [NSNumber]) -> Bool {
        lock.lock(); writes.append(contentsOf: packets); lock.unlock(); writeReady.signal(); return true
    }
    func inject(_ packet: Data, family: Int32) {
        precondition(readReady.wait(timeout: .now() + 2) == .success)
        lock.lock(); let callback = reader; reader = nil; lock.unlock()
        callback?([packet], [NSNumber(value: family)])
    }
}

@main struct BridgeChecks {
    static func main() throws {
        for _ in 0..<10 {
            let flow = FakeFlow()
            let bridge = PacketFlowBridge(packetFlow: flow, maxPendingPackets: 8, maxPendingBytes: 4096) { _ in
                fatalError("Unexpected bridge failure with synthetic packets")
            }
            let fd = try bridge.start()
            var ipv4 = Data(repeating: 0, count: 20); ipv4[0] = 0x45
            flow.inject(ipv4, family: AF_INET)
            var ready = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            precondition(poll(&ready, 1, 2000) == 1)
            var bytes = [UInt8](repeating: 0, count: 128)
            let count = recv(fd, &bytes, bytes.count, 0)
            precondition(count == 24 && Array(bytes[0..<4]) == [0, 0, 0, UInt8(AF_INET)])
            precondition(Data(bytes[4..<24]) == ipv4)
            var ipv6 = Data(repeating: 0, count: 40); ipv6[0] = 0x60
            var frame = Data([0, 0, 0, UInt8(AF_INET6)]); frame.append(ipv6)
            let sent = frame.withUnsafeBytes { send(fd, $0.baseAddress, $0.count, 0) }
            precondition(sent == frame.count)
            precondition(flow.writeReady.wait(timeout: .now() + 2) == .success)
            flow.lock.lock(); let delivered = flow.writes; flow.lock.unlock()
            precondition(delivered == [ipv6])
            let stats = bridge.snapshot()
            precondition(stats.packetsFromSystem == 1 && stats.packetsToSystem == 1)
            bridge.stop()
            bridge.stop()
            precondition(fcntl(fd, F_GETFD) == -1 && errno == EBADF)
        }
        print("PASS: 10 synthetic IPv4/IPv6 bridge sessions, framing, counters and descriptor closure; no NE tunnel or external network used")
    }
}
