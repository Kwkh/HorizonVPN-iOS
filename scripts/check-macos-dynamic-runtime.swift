import Foundation
import Hako

/// Real Go initialization and callback/cancellation smoke check with no VPN,
/// real subscription, credentials, CloudKit or remote network request.
@main struct DynamicCoreRuntimeCheck {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let options = HakoSetupOptions()
        options.basePath = directory.path
        options.workingPath = directory.path
        options.tempPath = directory.appendingPathComponent("tmp").path
        options.runtimeProfile = "macosPacketTunnel"
        options.memoryLimit = 128 * 1024 * 1024
        options.maxProcs = 2
        options.disablePersistentCache = true
        options.ephemeralPacketTunnel = true
        options.disableClashAPISocket = true
        options.privateDiagnostics = true
        var error: NSError?
        guard HakoSetup(options, &error), error == nil else { fatalError("Go runtime setup failed") }
        let work = DispatchGroup()
        let workers = (0..<5).map { _ in HakoNewCancellableURLTests(5)! }
        for worker in workers {
            work.enter()
            DispatchQueue.global(qos: .utility).async {
                let result = worker.testStandalone("{\"type\":\"__horizon_missing__\",\"name\":\"fixture\"}",
                    url: "http://127.0.0.1:1/", timeoutMillis: 100, unified: false)
                precondition(result < 0)
                worker.cancel()
                work.leave()
            }
        }
        guard work.wait(timeout: .now() + 10) == .success else { fatalError("Native callbacks did not finish") }
        let cancelled = HakoNewCancellableURLTests(5)!
        cancelled.cancel()
        precondition(cancelled.testStandalone("{}", url: "http://127.0.0.1:1/", timeoutMillis: 100, unified: false) < 0)
        print("PASS dynamic Go setup, five concurrent rejected probes, cancellation and process exit: " + HakoGoVersion())
    }
}
