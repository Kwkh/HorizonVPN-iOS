import Foundation

/// Only exact, credential-free default URLs map to packaged bytes. Custom sources never fall back.
nonisolated enum BundledGeoData {
    struct Manifest: Decodable {
        struct Asset: Decodable { let key: String; let file: String; let bytes: Int; let sha256: String }
        let version: String
        let assets: [Asset]
    }
    struct Value { let data: Data; let version: String }
    static func load(_ request: ConfigurationResources.Request, directory: URL? = nil) throws -> Value? {
        guard request.headers.isEmpty, request.key.hasPrefix("geo:"),
              let source = URL(string: request.url), SubscriptionDownloader.isPublicGeoSource(source) else { return nil }
        let root = directory ?? Bundle.main.url(forResource: "BundledGeo", withExtension: "json", subdirectory: "GeoData")?.deletingLastPathComponent()
            ?? Bundle.main.url(forResource: "BundledGeo", withExtension: "json")?.deletingLastPathComponent()
        guard let root else { throw ConfigurationValidation.issue("内置 Geo 数据缺失，请重新安装完整构建；未自动改用网络下载。") }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: root.appendingPathComponent("BundledGeo.json")))
        guard let asset = manifest.assets.first(where: { $0.key == request.key && $0.file == source.lastPathComponent }),
              asset.bytes <= request.maximumBytes, !asset.file.contains("/"),
              manifest.version.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil else {
            throw ConfigurationValidation.issue("内置 Geo 数据清单无效。")
        }
        let bytes = try Data(contentsOf: root.appendingPathComponent(asset.file), options: .mappedIfSafe)
        guard bytes.count == asset.bytes, ConfigurationResourceStore.digest(bytes) == asset.sha256 else {
            throw ConfigurationValidation.issue("内置 Geo 数据完整性校验失败，请重新安装完整构建。")
        }
        return Value(data: bytes, version: manifest.version)
    }
}
