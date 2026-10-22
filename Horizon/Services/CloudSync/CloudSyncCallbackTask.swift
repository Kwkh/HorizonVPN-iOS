import Foundation

/// CloudKit marks its delegate callbacks with task-local state. A plain Task
/// inherits that state even after the callback returns, and CKSyncEngine traps
/// when cancel/fetch/send would reenter its delegate. Escape without inheriting it.
nonisolated enum CloudSyncCallbackTask {
    @discardableResult static func run(_ operation: @escaping @Sendable () async -> Void) -> Task<Void, Never> {
        Task.detached { await operation() }
    }
}
