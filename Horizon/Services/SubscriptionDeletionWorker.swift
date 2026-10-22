import Foundation

/// Deletion commits before UI publication; subsequent maintenance is independent
/// of the controller's busy flag. Repository transactions protect live resources.
/// Only immutable library values return to MainActor; storage work runs off it.
nonisolated enum SubscriptionDeletionWorker {
    static func commit(_ ids: Set<UUID>, repository: SubscriptionRepository) async throws -> SubscriptionIndex {
        try await Task.detached(priority: .userInitiated) {
            try repository.delete(ids, performCleanup: false)
        }.value
    }

    static func cleanup(repository: SubscriptionRepository) async throws -> SubscriptionIndex {
        try await Task.detached(priority: .utility) {
            try repository.cleanup()
        }.value
    }
}
