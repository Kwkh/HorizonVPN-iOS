import Foundation
import Testing
@testable import Horizon

nonisolated private enum DelegateContext {
    @TaskLocal static var isInsideCallback = false
}

struct CloudSyncCallbackTaskTests {
    @Test func cancellationEscapesDelegateTaskLocalContext() async {
        await DelegateContext.$isInsideCallback.withValue(true) {
            // Reproduce the context inherited by the original Task-based path.
            let inherited = Task { DelegateContext.isInsideCallback }
            #expect(await inherited.value)

            let cancellation = CloudSyncCallbackTask.run {
                #expect(!DelegateContext.isInsideCallback)
                await Task.yield()
                #expect(!DelegateContext.isInsideCallback)
            }
            await cancellation.value
            #expect(DelegateContext.isInsideCallback)
        }
    }

    @Test func parentCancellationDoesNotPreventStoppingTheEngine() async {
        let parent = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            let cancellation = CloudSyncCallbackTask.run {
                #expect(!Task.isCancelled)
                #expect(!DelegateContext.isInsideCallback)
            }
            await cancellation.value
        }
        await parent.value
    }
}
