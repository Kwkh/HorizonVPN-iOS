import Foundation

/// Treat QR payloads as input, never as instructions or URLs to open automatically.
enum SubscriptionQRCode {
    enum Failure: Error { case unsupported, multiple, unreadableImage }

    nonisolated static func link(from payload: String) throws -> String {
        guard payload.utf8.count <= 8192 else { throw Failure.unsupported }
        let value = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidate = value
        if let parts = URLComponents(string: value), parts.scheme?.lowercased() == "clash" {
            guard parts.host?.lowercased() == "install-config", parts.user == nil, parts.password == nil,
                  parts.port == nil, parts.path.isEmpty || parts.path == "/", parts.fragment == nil else { throw Failure.unsupported }
            let links = (parts.queryItems ?? []).filter { $0.name == "url" }
            guard links.count == 1, let nested = links.first?.value else { throw Failure.unsupported }
            candidate = nested
        }
        if !value.lowercased().hasPrefix("clash://"),
           let scheme = URLComponents(string: value)?.scheme?.lowercased(), NodeURI.schemes.contains(scheme) {
            guard (try? NodeURI.parse(value, index: 0)) != nil else { throw Failure.unsupported }
            return value
        }
        guard let url = try? SubscriptionDownloader.validatedURL(candidate) else { throw Failure.unsupported }
        return url.absoluteString
    }

    nonisolated static func uniqueLink(in payloads: [String]) throws -> String {
        let links = Set(payloads.compactMap { try? link(from: $0) })
        guard links.count == 1, let link = links.first else {
            throw links.isEmpty ? Failure.unsupported : Failure.multiple
        }
        return link
    }
}
