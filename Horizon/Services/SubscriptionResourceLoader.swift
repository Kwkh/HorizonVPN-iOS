import Foundation
import Hako

/// Import and refresh share one all-or-nothing dependency pipeline. No fallback downloads in the extension.
nonisolated enum SubscriptionResourceLoader {
    static func prepare(_ data: Data, permitsNetwork: Bool,
                        previousSource: Data? = nil, updateGeo: Bool = false,
                        routing: ConfigurationRouting = .subscription, reuseDependencies: Bool = false,
                        deadline: ContinuousClock.Instant = .now.advanced(by: .seconds(30)),
                        bundledDirectory: URL? = nil,
                        fetch: ((ConfigurationResources.Request) async throws -> Data)? = nil) async throws -> Data {
        guard !data.starts(with: ConfigurationSnapshot.prefix) else { throw PrototypeError.invalidFile }
        let document = try routing.apply(ConfigurationInput.read(data, resolveResources: false))
        let requests = try ConfigurationResources.plan(document.root)
        if requests.isEmpty { return data }
        let previous = try previousSource.flatMap { try ConfigurationSnapshot.read($0) }
        let previousPlan = try previous.map { try ConfigurationResources.plan(ConfigurationInput.read(try $0.encoded(), resolveResources: false).root) } ?? []
        var values: [(String, Data)] = [], bytes = 0
        var versions: [String: String] = [:]
        // Serial downloads deliberately bound memory and simultaneous connections.
        for (index, request) in requests.enumerated() {
            try Task.checkCancellation()
            let body: Data
            do {
                if reuseDependencies,
                   previousPlan.contains(where: { $0.key == request.key && $0.url == request.url && $0.headers == request.headers }),
                   let resource = previous?.resources.first(where: { $0.key == request.key }) {
                    body = try ConfigurationResourceStore.load(resource)
                    versions[request.key] = resource.bundledVersion
                } else if let fetch { body = try await fetch(request) }
                else if !updateGeo, request.key.hasPrefix("geo:"), request.headers.isEmpty,
                        URL(string: request.url).map(SubscriptionDownloader.isPublicGeoSource) == true,
                        previousPlan.contains(where: { $0.key == request.key && $0.url == request.url && $0.headers == request.headers }),
                        let resource = previous?.resources.first(where: { $0.key == request.key }) {
                    body = try ConfigurationResourceStore.load(resource)
                    versions[request.key] = resource.bundledVersion
                } else if !updateGeo, let bundled = try BundledGeoData.load(request, directory: bundledDirectory) {
                    body = bundled.data; versions[request.key] = bundled.version
                } else {
                    guard permitsNetwork else { throw ConfigurationValidation.issue("离线模式无法下载自定义来源或 providers；请提供完整的本地配置。") }
                    body = try await SubscriptionDownloader.fetch(request.url, maximumBytes: request.maximumBytes, headers: request.headers, permitsPublicGeoRedirect: request.key.hasPrefix("geo:"), budget: .dependency, deadline: deadline)
                }
            } catch is CancellationError { throw CancellationError() }
            catch let issue as ConfigurationIssue { throw issue }
            catch {
                if Task.isCancelled { throw CancellationError() }
                throw downloadIssue(request, index: index, failure: (error as? SubscriptionDownloader.Failure) ?? .transport)
            }
            guard !body.isEmpty else { throw downloadIssue(request, index: index, failure: .empty) }
            guard body.count <= request.maximumBytes else { throw downloadIssue(request, index: index, failure: .tooLarge) }
            bytes += body.count
            guard bytes <= ConfigurationResourceStore.maximumTotalBytes else { throw ConfigurationValidation.issue("依赖总大小超过 64 MiB。") }
            values.append((request.key, body))
        }
        try Task.checkCancellation()
        return try ConfigurationResourceStore.stage(values, original: data, bundledVersions: versions, routing: routing)
    }
    private static func downloadIssue(_ request: ConfigurationResources.Request, index: Int,
                                      failure: SubscriptionDownloader.Failure) -> ConfigurationIssue {
        let kind: String
        if request.key.hasPrefix("geo:geoip:") { kind = "GeoIP 数据" }
        else if request.key.hasPrefix("geo:geosite:") { kind = "GeoSite 数据" }
        else if request.key.hasPrefix("proxy:") { kind = "节点列表" }
        else if request.key.hasPrefix("rule:") { kind = "规则集" }
        else { kind = "外部数据" }
        let publicSource = request.key.hasPrefix("geo:") && URL(string: request.url).map(SubscriptionDownloader.isPublicGeoSource) == true
        let label = kind + (publicSource ? " / GitHub" : "")
        return ConfigurationValidation.issue("依赖 \(index + 1)（\(label)）：\(failure.safeReason)。现有订阅未改变；请检查当前网络后重试。", .resourceDownload)
    }
    #if os(iOS) || HORIZON_NATIVE_MAC
    static func preflight(_ prepared: PrototypeConfiguration.Prepared) throws {
        // Main App and extension have separate containers/processes. This never starts a core service or VPN.
        let directory = ConfigurationResources.directory
        defer { try? FileManager.default.removeItem(at: directory) }
        try CoreRuntime.setup(in: directory)
        try CoreRuntime.prepareResources(prepared)
        var error: NSError?
        guard HakoCheckConfig(prepared.runtimeJSON, &error) else {
            throw ConfigurationValidation.issue("内核完整预检未通过；字段组合或依赖内容无法运行。旧版保持可用，详细原文不会写入日志。")
        }
        try CompiledGeoCache.publish(source: prepared.source, directory: directory,
            storage: ConfigurationResourceStore.scopedStorage ?? KeychainSubscriptionStorage())
        // Rule/Geo files are only needed for this offline preflight in the main App.
        try? FileManager.default.removeItem(at: directory)
    }
    #endif
}
