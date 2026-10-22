#if DEBUG
import Foundation
import Hako

/// Exercises the real Swift/Go initialization boundary without starting a service.
/// Uses a refusing platform double: no vault, NE settings, socket or node access.
enum CoreInitializationSelfCheck {
    struct Result: Codable {
        let passed: Bool
        let completedCycles: Int
        let unexpectedNetworkCallbacks: Int
        let failureCode: Int?
    }

    static func run() -> Result {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CoreInitializationCheck", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let platform = RefusingPlatform()
        var cycles = 0
        do {
            try CoreRuntime.setup(in: root)
            let config = try PrototypeConfiguration.prepare(Data(PrototypeSelfCheck.fixture.utf8))
            var error: NSError?
            guard HakoCheckConfig(config.runtimeJSON, &error) else { throw PrototypeError.coreValidation }
            for _ in 0..<3 {
                let service = try CoreRuntime.makeService(platform: platform)
                guard service.status() != "running" else {
                    try? service.close()
                    throw PrototypeError.start
                }
                try service.close()
                try service.close()
                cycles += 1
            }
            return Result(passed: platform.callbackCount == 0, completedCycles: cycles,
                unexpectedNetworkCallbacks: platform.callbackCount, failureCode: nil)
        } catch {
            return Result(passed: false, completedCycles: cycles,
                unexpectedNetworkCallbacks: platform.callbackCount,
                failureCode: (error as? PrototypeError)?.rawValue ?? 0)
        }
    }
}

private final class RefusingPlatform: NSObject, HakoPlatformInterfaceProtocol {
    private let lock = NSLock()
    private var callbacks = 0
    var callbackCount: Int {
        lock.lock(); defer { lock.unlock() }
        return callbacks
    }
    private func refused() -> PrototypeError {
        lock.lock(); callbacks += 1; lock.unlock()
        return .physicalNetwork
    }
    func underNetworkExtension() -> Bool { true }
    func usePlatformAutoDetectControl() -> Bool { true }
    func writeLog(_ message: String?) { }
    func autoDetectControl(_ fd: Int32) throws { throw refused() }
    func startDefaultInterfaceMonitor(_ listener: HakoInterfaceUpdateListenerProtocol?) throws { throw refused() }
    func closeDefaultInterfaceMonitor(_ listener: HakoInterfaceUpdateListenerProtocol?) throws { throw refused() }
    func getInterfaces() throws -> HakoNetworkInterfaceIteratorProtocol { throw refused() }
    func openTun(_ options: HakoTunOptionsProtocol?, ret0_: UnsafeMutablePointer<Int32>?) throws { throw refused() }
}
#endif
