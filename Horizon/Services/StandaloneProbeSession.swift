import Foundation
import Hako

/// One cancellable, foreground-only probe lifetime. No VPN service or listeners.
/// Hako's context cancellation and five-slot admission are thread safe.
nonisolated final class StandaloneProbeSession: @unchecked Sendable {
    private let native = HakoNewCancellableURLTests(ProbeAdmissionQueue.limit)
    func cancel() { native?.cancel() }
    func test(node: String, unified: Bool) async -> Int32 {
        guard let native else { return -1 }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async { [self] in
                    continuation.resume(returning: native.testStandalone(node, url: PingReport.testURL,
                        timeoutMillis: PingReport.timeoutMilliseconds, unified: unified))
                }
            }
        } onCancel: { self.cancel() }
    }
    deinit { native?.cancel() }
}
