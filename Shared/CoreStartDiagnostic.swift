import Foundation

/// Categories from the pinned core's fixed error prefixes. No source text escapes.
enum CoreStartDiagnostic: String {
    case interfaceMonitor, openTun, tunListener, controlSocket, controlSocketPermissions, panic, unknown

    static func classify(_ error: Error) -> Self {
        let text = (error as NSError).localizedDescription
        if text.hasPrefix("hako: start default interface monitor:") { return .interfaceMonitor }
        if text.hasPrefix("hako: OpenTun:") || text.hasPrefix("hako: start panicked: hako: OpenTun:") { return .openTun }
        if text.hasPrefix("hako: tun listener") { return .tunListener }
        if text.hasPrefix("hako: secure Clash API Unix socket:") { return .controlSocketPermissions }
        if text.hasPrefix("hako: Clash API") { return .controlSocket }
        if text.hasPrefix("hako: start panicked:") { return .panic }
        return .unknown
    }

    static func systemReason(_ error: Error) -> String {
        let text = (error as NSError).localizedDescription.lowercased()
        for (needle, category) in [
            ("operation not permitted", "permission"), ("permission denied", "permission"),
            ("no such file or directory", "missing-file"), ("invalid argument", "invalid-argument"),
            ("address already in use", "address-in-use"), ("file name too long", "path-too-long"),
            ("no buffer space", "buffer-space"), ("not supported", "unsupported")
        ] where text.contains(needle) { return category }
        return "unclassified"
    }
}
