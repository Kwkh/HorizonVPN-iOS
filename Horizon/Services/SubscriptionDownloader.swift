import Foundation

/// No disk cache, cookies, saved authentication, response logging or third-party conversion.
nonisolated struct SubscriptionDownloader {
    /// Provider-reported account usage, independent of local VPN traffic counters.
    struct Usage: Codable, Equatable, Sendable {
        let upload: UInt64?
        let download: UInt64?
        let total: UInt64?
        let expiresAt: Date?
        let fetchedAt: Date
        var used: UInt64? {
            guard let upload, let download else { return nil }
            let sum = upload.addingReportingOverflow(download)
            return sum.overflow ? UInt64.max : sum.partialValue
        }
        var remaining: UInt64? {
            guard let used, let total, total > 0 else { return nil }
            return used >= total ? 0 : total - used
        }
        var remainingFraction: Double? {
            guard let remaining, let total else { return nil }
            return min(1, max(0, Double(remaining) / Double(total)))
        }
        static func parse(_ header: String?, now: Date = Date()) -> Usage? {
            guard let header, header.utf8.count <= 4096 else { return nil }
            var fields: [String: UInt64] = [:]
            var seen: Set<String> = []
            for part in header.split(separator: ";") {
                let pair = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard pair.count == 2 else { continue }
                let key = pair[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard ["upload", "download", "total", "expire"].contains(key) else { continue }
                #if os(macOS)
                // Expiry is optional display metadata, independent of byte counters.
                // Providers sometimes use -1/null for no expiry. Do not discard a
                // valid allowance for that sentinel; ambiguous expiry stays unknown.
                if key == "expire" {
                    guard seen.insert(key).inserted else { fields[key] = nil; continue }
                    let value = pair[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }), let number = UInt64(value) {
                        fields[key] = number
                    }
                    continue
                }
                #endif
                // Duplicate or malformed known values are ambiguous; do not invent an allowance.
                guard seen.insert(key).inserted else { return nil }
                let value = pair[1].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }), let number = UInt64(value) else { return nil }
                fields[key] = number
            }
            guard !fields.isEmpty else { return nil }
            let expiry = fields["expire"].flatMap { $0 > 0 && $0 <= 253402300799 ? Date(timeIntervalSince1970: Double($0)) : nil }
            return Usage(upload: fields["upload"], download: fields["download"], total: fields["total"], expiresAt: expiry, fetchedAt: now)
        }
    }
    struct Download: Sendable {
        let data: Data
        let usage: Usage?
    }
    enum Failure: Error, Equatable, CaseIterable {
        case invalidURL, redirect, response, tooLarge, empty, transport
        case timedOut, dns, offline, tls, connectionLost, unreachable
        var englishReason: String {
            switch self {
            case .invalidURL: "A valid HTTPS source is required"
            case .redirect: "HTTPS redirect blocked by the security policy"
            case .response: "The server returned an unsuccessful response"
            case .tooLarge: "Download exceeds the size limit"
            case .empty: "The server returned an empty response"
            case .transport: "Network request failed"
            case .timedOut: "Download timed out"
            case .dns: "Could not resolve the download server"
            case .offline: "Network unavailable or network access not permitted"
            case .tls: "TLS or certificate validation failed"
            case .connectionLost: "Connection lost during download"
            case .unreachable: "Could not connect to the download server"
            }
        }
        var safeReason: String {
            switch self {
            case .invalidURL: "需要有效 HTTPS 来源"
            case .redirect: "HTTPS 跳转被安全策略阻止"
            case .response: "服务器未返回成功响应"
            case .tooLarge: "下载内容超过大小限制"
            case .empty: "服务器返回空内容"
            case .transport: "网络请求失败"
            case .timedOut: "下载超时"
            case .dns: "无法解析下载服务器"
            case .offline: "当前网络不可用或未获网络访问权限"
            case .tls: "下载服务器的 TLS 或证书校验失败"
            case .connectionLost: "下载途中连接中断"
            case .unreachable: "无法连接下载服务器"
            }
        }
    }
    enum Budget {
        case subscription, dependency
        var idleTimeout: TimeInterval { 10 }
        var totalTimeout: TimeInterval { 20 }
    }
    nonisolated static let maximumBytes = PrototypeConfiguration.maximumBytes

    nonisolated static func validatedURL(_ input: String) throws -> URL {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.utf8.count <= 8192, let parts = URLComponents(string: value), parts.scheme?.lowercased() == "https",
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.fragment == nil, let url = parts.url else { throw Failure.invalidURL }
        return url
    }

    @concurrent static func fetch(_ input: String, configuration: URLSessionConfiguration = .ephemeral, maximumBytes: Int = maximumBytes, headers: [String: String] = [:], permitsPublicGeoRedirect: Bool = false, budget: Budget = .subscription, deadline: ContinuousClock.Instant? = nil) async throws -> Data {
        try await fetchResponse(input, configuration: configuration, maximumBytes: maximumBytes, headers: headers,
            permitsPublicGeoRedirect: permitsPublicGeoRedirect, budget: budget, deadline: deadline).data
    }

    @concurrent static func fetchResponse(_ input: String, configuration: URLSessionConfiguration = .ephemeral, maximumBytes: Int = maximumBytes, headers: [String: String] = [:], permitsPublicGeoRedirect: Bool = false, budget: Budget = .subscription, deadline: ContinuousClock.Instant? = nil) async throws -> Download {
        try Task.checkCancellation()
        let url = try validatedURL(input)
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = budget.idleTimeout
        configuration.timeoutIntervalForResource = budget.totalTimeout
        let delegate = RedirectPolicy(origin: url, publicGeo: permitsPublicGeoRedirect && headers.isEmpty && isPublicGeoSource(url))
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.timeoutInterval = budget.idleTimeout
        request.setValue("Clash.Meta/Clash-iOS", forHTTPHeaderField: "User-Agent")
        request.setValue("application/yaml, text/yaml, text/plain", forHTTPHeaderField: "Accept")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let hardDeadline = min(deadline ?? .now.advanced(by: .seconds(budget.totalTimeout)), .now.advanced(by: .seconds(budget.totalTimeout)))
        guard hardDeadline > .now else { throw Failure.timedOut }
        do {
            return try await withThrowingTaskGroup(of: Download.self) { group in
                group.addTask { try await Self.read(request, session: session, maximumBytes: maximumBytes) }
                group.addTask {
                    try await ContinuousClock().sleep(until: hardDeadline)
                    throw Failure.timedOut
                }
                defer { group.cancelAll() }
                return try await group.next()!
            }
        } catch is CancellationError { throw CancellationError() }
        catch let error as Failure { throw error }
        catch {
            if Task.isCancelled { throw CancellationError() }
            throw classify(error)
        }
    }
    private static func read(_ request: URLRequest, session: URLSession, maximumBytes: Int) async throws -> Download {
        try await withTaskCancellationHandler {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw Failure.response }
            if (300..<400).contains(http.statusCode) { throw Failure.redirect }
            guard (200..<300).contains(http.statusCode) else { throw Failure.response }
            guard response.expectedContentLength <= maximumBytes else { throw Failure.tooLarge }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < maximumBytes else { throw Failure.tooLarge }
                data.append(byte)
            }
            try Task.checkCancellation()
            guard !data.isEmpty else { throw Failure.empty }
            let direct = http.value(forHTTPHeaderField: "subscription-userinfo")
            // Object-storage mirrors may prefix custom metadata headers.
            let mirrored = http.allHeaderFields.keys.compactMap { $0 as? String }.sorted().first {
                $0.lowercased().hasSuffix("-subscription-userinfo")
            }.flatMap { http.value(forHTTPHeaderField: $0) }
            return Download(data: data, usage: Usage.parse(direct ?? mirrored))
        } onCancel: {
            // A deadline must also interrupt URLSession while waiting for headers or the next byte.
            session.invalidateAndCancel()
        }
    }

    // Use only the error domain/code. Never retain userInfo, URLs, hostnames or localized descriptions.
    static func classify(_ error: Error) -> Failure {
        let error = error as NSError
        guard error.domain == NSURLErrorDomain else { return .transport }
        switch error.code {
        case NSURLErrorTimedOut: return .timedOut
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: return .dns
        case NSURLErrorNotConnectedToInternet, NSURLErrorDataNotAllowed, NSURLErrorInternationalRoamingOff: return .offline
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateHasBadDate,
             NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasUnknownRoot,
             NSURLErrorServerCertificateNotYetValid, NSURLErrorClientCertificateRejected,
             NSURLErrorClientCertificateRequired: return .tls
        case NSURLErrorNetworkConnectionLost: return .connectionLost
        case NSURLErrorCannotConnectToHost: return .unreachable
        default: return .transport
        }
    }

    static func allowsRedirect(from origin: URL, to target: URL, count: Int) -> Bool {
        count < 5 && target.scheme?.lowercased() == "https" &&
        target.host?.lowercased() == origin.host?.lowercased() &&
        (target.port ?? 443) == (origin.port ?? 443) && target.user == nil && target.password == nil
    }
    // Only the pinned core's public release URLs may cross to GitHub's release CDN.
    // Credential-bearing subscriptions/providers retain strict same-origin redirects.
    nonisolated static func isPublicGeoSource(_ url: URL) -> Bool {
        let names = ["geoip.metadb", "geoip.dat", "geosite.dat"]
        return names.contains { url.absoluteString == "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/" + $0 }
    }
    nonisolated static func allowsPublicGeoRedirect(from origin: URL, to target: URL, count: Int) -> Bool {
        isPublicGeoSource(origin) && count < 5 && target.scheme == "https" &&
            target.host == "release-assets.githubusercontent.com" && (target.port ?? 443) == 443 &&
            target.user == nil && target.password == nil && target.fragment == nil
    }
    private final class RedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        let origin: URL
        let publicGeo: Bool
        // URLSession invokes delegate callbacks on its serial delegate queue.
        private var count = 0
        init(origin: URL, publicGeo: Bool) { self.origin = origin; self.publicGeo = publicGeo }
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            guard let target = request.url, SubscriptionDownloader.allowsRedirect(from: origin, to: target, count: count) || (publicGeo && SubscriptionDownloader.allowsPublicGeoRedirect(from: origin, to: target, count: count)) else {
                completionHandler(nil); return
            }
            count += 1
            completionHandler(request)
        }
    }
}
