import Foundation

// All requests are intercepted. No sockets, system permission prompts or VPN.
final class AccessCheckProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        precondition(request.url?.absoluteString == "https://cp.cloudflare.com/generate_204")
        precondition(request.httpMethod == "HEAD" && request.httpBody == nil)
        precondition(request.value(forHTTPHeaderField: "Authorization") == nil)
        precondition(request.value(forHTTPHeaderField: "Cookie") == nil)
        let scenario = request.value(forHTTPHeaderField: "X-Test-Scenario")!
        if scenario == "wait" { return }
        if scenario == "timeout" {
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
        } else {
            let response = HTTPURLResponse(url: request.url!, statusCode: Int(scenario)!, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() { }
}

@main struct NetworkAccessChecks {
    static func configuration(_ scenario: String) -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AccessCheckProtocol.self]
        config.httpAdditionalHeaders = ["X-Test-Scenario": scenario]
        return config
    }
    static func main() async {
        for (scenario, expected) in [("204", NetworkAccessCheck.Result.reachable), ("200", .unavailable), ("302", .unavailable), ("timeout", .unavailable)] {
            let config = configuration(scenario)
            let result = await NetworkAccessCheck.run(configuration: config)
            precondition(result == expected)
            precondition(config.urlCache == nil && config.urlCredentialStorage == nil && config.httpCookieStorage == nil)
            precondition(!config.httpShouldSetCookies && config.waitsForConnectivity)
            precondition(config.timeoutIntervalForResource == 30)
        }
        let task = Task { await NetworkAccessCheck.run(configuration: configuration("wait")) }
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()
        let cancelled = await task.value
        precondition(cancelled == .cancelled)
        print("Network access: mocked success/non-204/timeout/cancellation and credential-free ephemeral request passed; no network used")
    }
}
