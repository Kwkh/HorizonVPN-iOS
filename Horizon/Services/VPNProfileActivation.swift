import Foundation

/// Re-read system preferences before an explicit start: another VPN can disable
/// an installed profile without changing its protocol/version metadata.
@MainActor enum VPNProfileActivation {
    static func prepare(load: () async throws -> Void,
                        validate: () throws -> Void,
                        isEnabled: () -> Bool,
                        enableAndSave: () async throws -> Void) async throws {
        try await load()
        try Task.checkCancellation()
        try validate()
        if !isEnabled() {
            try await enableAndSave()
            try await load()
            try Task.checkCancellation()
            try validate()
        }
        guard isEnabled() else { throw PrototypeError.start }
    }
}
