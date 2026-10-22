import Foundation

/// A foreground Internet request gives iOS an opportunity to ask for wireless
/// data access on devices that require it. Its result is not a permission API.
nonisolated enum NetworkAccessCheck {
    enum Result: Equatable { case reachable, unavailable, cancelled }

    static func run(configuration: URLSessionConfiguration = .ephemeral) async -> Result {
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: "https://cp.cloudflare.com/generate_204")!)
        request.httpMethod = "HEAD"
        do {
            let (_, response) = try await session.data(for: request)
            guard !Task.isCancelled else { return .cancelled }
            // Only the intended endpoint's success verifies this one request.
            // Neither success nor failure proves all Wi-Fi/cellular permissions.
            guard let response = response as? HTTPURLResponse,
                  response.url == request.url, response.statusCode == 204 else { return .unavailable }
            return .reachable
        } catch {
            return Task.isCancelled ? .cancelled : .unavailable
        }
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
