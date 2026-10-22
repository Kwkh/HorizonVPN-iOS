import Foundation

final class DownloadFixture: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        if path == "/waiting" { return }
        let failures = ["/failure": NSURLErrorTimedOut, "/dns": NSURLErrorCannotFindHost,
                        "/offline": NSURLErrorNotConnectedToInternet, "/tls": NSURLErrorServerCertificateUntrusted,
                        "/lost": NSURLErrorNetworkConnectionLost, "/unreachable": NSURLErrorCannotConnectToHost]
        if let code = failures[path] {
            client?.urlProtocol(self, didFailWithError: NSError(domain: NSURLErrorDomain, code: code,
                userInfo: [NSURLErrorFailingURLErrorKey: request.url!]))
            return
        }
        let body = path == "/empty" ? Data() : path == "/large" ? Data(repeating: 65, count: SubscriptionDownloader.maximumBytes + 1) : Data("proxies: []".utf8)
        let status = path == "/status" ? 403 : path == "/redirect" ? 302 : 200
        var headers = path == "/declared-large" ? ["Content-Length": "9999999"] : [:]
        if path == "/usage" { headers["Subscription-Userinfo"] = "upload=100; download=200; total=1000; expire=2000000000" }
        if path == "/mirrored-usage" { headers["X-Amz-Meta-Subscription-Userinfo"] = "upload=100; download=200; total=1000" }
        if path == "/bad-usage" { headers["Subscription-Userinfo"] = "upload=oops; download=200; total=1000" }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        if path != "/bodywaiting" { client?.urlProtocolDidFinishLoading(self) }
    }
    override func stopLoading() { }
}
@main struct DownloadCheck {
    static func main() async throws {
        for invalid in ["http://example.invalid/config", "vmess://example", "https://user:pass@example.invalid/a", "https://example.invalid/a#token", "abc"] {
            do { _ = try SubscriptionDownloader.validatedURL(invalid); fatalError("invalid URL accepted") }
            catch SubscriptionDownloader.Failure.invalidURL { }
        }
        let origin = try SubscriptionDownloader.validatedURL(" https://example.invalid/a?token=FAKE ")
        precondition(SubscriptionDownloader.allowsRedirect(from: origin, to: URL(string:"https://example.invalid/b")!, count:0))
        for target in ["http://example.invalid/b", "https://other.invalid/b", "https://example.invalid:444/b", "https://user:pass@example.invalid/b"] {
            precondition(!SubscriptionDownloader.allowsRedirect(from: origin, to: URL(string:target)!, count:0))
        }
        precondition(!SubscriptionDownloader.allowsRedirect(from: origin, to: origin, count:5))
        let publicGeo = URL(string: "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat")!
        let asset = URL(string: "https://release-assets.githubusercontent.com/fixture?token=FICTIONAL")!
        precondition(SubscriptionDownloader.allowsPublicGeoRedirect(from: publicGeo, to: asset, count: 0))
        precondition(!SubscriptionDownloader.allowsRedirect(from: publicGeo, to: asset, count: 0))
        for source in [origin, URL(string: publicGeo.absoluteString + "?token=FICTIONAL")!, URL(string: "https://github.com/private/release")!] {
            precondition(!SubscriptionDownloader.allowsPublicGeoRedirect(from: source, to: asset, count: 0))
        }
        for target in ["http://release-assets.githubusercontent.com/a", "https://other.invalid/a", "https://release-assets.githubusercontent.com.evil.invalid/a", "https://user:pass@release-assets.githubusercontent.com/a"] {
            precondition(!SubscriptionDownloader.allowsPublicGeoRedirect(from: publicGeo, to: URL(string: target)!, count: 0))
        }
        precondition(!SubscriptionDownloader.allowsPublicGeoRedirect(from: publicGeo, to: asset, count: 5))
        func fetch(_ path: String) async throws -> Data {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [DownloadFixture.self]
            return try await SubscriptionDownloader.fetch("https://example.invalid/" + path + "?token=FAKE", configuration: config)
        }
        for path in ["usage", "mirrored-usage", "bad-usage", "good"] {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [DownloadFixture.self]
            let response = try await SubscriptionDownloader.fetchResponse("https://example.invalid/" + path, configuration: config)
            precondition(response.data == Data("proxies: []".utf8))
            precondition(response.usage?.remaining == (["usage", "mirrored-usage"].contains(path) ? 700 : nil))
        }
        let parse = SubscriptionDownloader.Usage.parse
        precondition(parse(" TOTAL = 1000 ; Download=200; UPLOAD=100; extra=ignored", Date())?.remaining == 700)
        precondition(parse("upload=600; download=500; total=1000", Date())?.remaining == 0)
        precondition(parse("upload=0; download=0; total=0", Date())?.remaining == nil)
        precondition(parse("download=200; total=1000", Date())?.remaining == nil)
        precondition(parse("upload=18446744073709551615; download=1; total=1000", Date())?.remaining == 0)
        for header in ["", "upload=-1; download=0; total=1000", "upload=1; upload=2", "total=NaN", "total=18446744073709551616", "upload=+1", String(repeating: "x", count: 4097)] {
            precondition(parse(header, Date()) == nil)
        }
        print("PASS provider allowance headers, mirror prefixes, invalid/missing values and overflow; legacy fetch body unchanged")
        let good = try await fetch("good")
        precondition(good == Data("proxies: []".utf8))
        for (path, expected) in [("empty", SubscriptionDownloader.Failure.empty), ("large", .tooLarge), ("declared-large", .tooLarge), ("status", .response), ("redirect", .redirect), ("failure", .timedOut), ("dns", .dns), ("offline", .offline), ("tls", .tls), ("lost", .connectionLost), ("unreachable", .unreachable)] {
            do { _ = try await fetch(path); fatalError("expected rejection") }
            catch let error as SubscriptionDownloader.Failure { precondition(error == expected) }
        }
        let dependencyConfig = URLSessionConfiguration.ephemeral
        dependencyConfig.protocolClasses = [DownloadFixture.self]
        _ = try await SubscriptionDownloader.fetch(origin.absoluteString, configuration: dependencyConfig, budget: .dependency)
        precondition(dependencyConfig.timeoutIntervalForRequest == 10 && dependencyConfig.timeoutIntervalForResource == 20)
        let subscriptionConfig = URLSessionConfiguration.ephemeral
        subscriptionConfig.protocolClasses = [DownloadFixture.self]
        _ = try await SubscriptionDownloader.fetch(origin.absoluteString, configuration: subscriptionConfig)
        precondition(subscriptionConfig.timeoutIntervalForRequest == 10 && subscriptionConfig.timeoutIntervalForResource == 20)
        let raw = NSError(domain: "private", code: NSURLErrorTimedOut, userInfo: [NSLocalizedDescriptionKey: "FICTIONAL-SECRET"])
        precondition(SubscriptionDownloader.classify(raw) == .transport)
        precondition(!SubscriptionDownloader.classify(raw).safeReason.contains("FICTIONAL-SECRET"))
        let stalledConfig = URLSessionConfiguration.ephemeral
        stalledConfig.protocolClasses = [DownloadFixture.self]
        let start = ContinuousClock.now
        do {
            _ = try await SubscriptionDownloader.fetch("https://example.invalid/waiting", configuration: stalledConfig,
                deadline: start.advanced(by: .milliseconds(150)))
            fatalError("deadline did not stop stalled headers")
        } catch SubscriptionDownloader.Failure.timedOut { }
        precondition(start.duration(to: .now) < .seconds(2))
        let stalledBody = URLSessionConfiguration.ephemeral
        stalledBody.protocolClasses = [DownloadFixture.self]
        let bodyStart = ContinuousClock.now
        do {
            _ = try await SubscriptionDownloader.fetch("https://example.invalid/bodywaiting", configuration: stalledBody,
                deadline: bodyStart.advanced(by: .milliseconds(150)))
            fatalError("deadline did not stop stalled body")
        } catch SubscriptionDownloader.Failure.timedOut { }
        precondition(bodyStart.duration(to: .now) < .seconds(2))
        let pending = Task { try await fetch("waiting") }
        try await Task.sleep(for: .milliseconds(100))
        pending.cancel()
        do { _ = try await pending.value; fatalError("cancel expected") } catch is CancellationError { }
        print("PASS: HTTPS validation, redirect policy, bounded payload, HTTP failures, sanitized errors and cancellation; no network used")
    }
}
