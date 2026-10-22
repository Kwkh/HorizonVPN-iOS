import Foundation

struct TunnelSnapshot: Codable {
    let coreRunning: Bool
    let packetsFromSystem: UInt64
    let packetsToSystem: UInt64
    let droppedPackets: UInt64
    let memoryBytes: Int64
    let proxyUploadBytes: Int64?
    let proxyDownloadBytes: Int64?
    let bindingSuccesses: UInt64?
    let bindingFailures: UInt64?
    let physicalTransport: String?
}
