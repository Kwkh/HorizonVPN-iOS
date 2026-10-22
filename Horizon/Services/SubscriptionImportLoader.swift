import Foundation

/// All entry points converge on PrototypeConfiguration; only HTTPS inputs perform I/O.
enum SubscriptionImportLoader {
    struct Payload { let data: Data; let sourceURL: String?; var usage: SubscriptionDownloader.Usage? = nil }
    static func load(_ input: String, permitsNetwork: Bool, deadline: ContinuousClock.Instant? = nil) async throws -> Payload {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= PrototypeConfiguration.maximumBytes else { throw PrototypeError.invalidFile }
        if text.lowercased().hasPrefix("https://") || text.lowercased().hasPrefix("clash://") {
            guard permitsNetwork else { throw SubscriptionDownloader.Failure.transport }
            let url = try SubscriptionQRCode.link(from: text)
            let response = try await SubscriptionDownloader.fetchResponse(url, deadline: deadline)
            return Payload(data: response.data, sourceURL: url, usage: response.usage)
        }
        return Payload(data: Data(text.utf8), sourceURL: nil)
    }
}
