import Foundation
import Hako
import OSLog

/// Identical initialization policy for the extension and synthetic lifecycle check.
nonisolated enum CoreRuntime {
    static func setup(in root: URL) throws {
        do {
            #if os(macOS)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            #else
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            #endif
            var url = root
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
        } catch {
            throw PrototypeError.coreStorage
        }
        let options = HakoSetupOptions()
        options.basePath = root.path
        options.workingPath = root.path
        options.tempPath = root.appendingPathComponent("tmp").path
        #if HORIZON_NATIVE_MAC
        options.runtimeProfile = "macosPacketTunnel"
        options.memoryLimit = 128 * 1024 * 1024
        #else
        options.runtimeProfile = "iosPacketTunnel"
        options.memoryLimit = 40 * 1024 * 1024 // GC hint, not an OS memory guarantee.
        #endif
        options.ipQueryMode = "config"
        options.tunIPv6Mode = "enabled"
        options.tunMTU = 1280
        options.maxProcs = 2
        options.logMaxLines = 1
        options.privateDiagnostics = true
        options.disablePersistentCache = true
        options.ephemeralPacketTunnel = true
        options.disableClashAPISocket = true // Native bridge + NE messages; no Unix HTTP API.
        var error: NSError?
        guard HakoSetup(options, &error) else { throw PrototypeError.setup }
    }

    static func prepareResources(_ prepared: PrototypeConfiguration.Prepared, validateGeo: Bool = true) throws {
        let logger = Logger(subsystem: "Kenote.Clash.PacketTunnel", category: "resources")
        logger.notice("phase2.resources.install-start memory=\(HakoMemoryFootprint(), privacy: .public)")
        try autoreleasepool {
            try ConfigurationResources.install(prepared.source, in: ConfigurationResources.directory, validateGeo: validateGeo)
        }
        logger.notice("phase2.resources.installed memory=\(HakoMemoryFootprint(), privacy: .public)")
        #if os(iOS) || HORIZON_NATIVE_MAC
        if !validateGeo, try CompiledGeoCache.restore(source: prepared.source, directory: ConfigurationResources.directory,
                                                     storage: KeychainSubscriptionStorage()) {
            logger.notice("phase2.resources.compiled-cache-restored")
            return
        }
        if !validateGeo, try ConfigurationRouting.mode(in: prepared.source) == .smart {
            throw ConfigurationValidation.issue("分流编译缓存缺失，请重新保存分流方案。")
        }
        #endif
        let resources = try ConfigurationSnapshot.read(prepared.source)?.resources ?? []
        var error: NSError?
        // iOS core loads compiled named categories. Never accept a partial compilation as success.
        if resources.contains(where: { $0.key == "geo:geoip:dat" }) {
            let result = HakoPrepareGeoIPCache(prepared.runtimeJSON, true, &error)
            guard error == nil, result.contains(", 0 failed of ") else { throw ConfigurationValidation.issue("GeoIP 分类编译失败；未启用候选版本。") }
        }
        if resources.contains(where: { $0.key == "geo:geoip:mmdb" }) {
            error = nil
            _ = HakoPrepareGeoIPCache(prepared.runtimeJSON, false, &error)
            guard error == nil else { throw ConfigurationValidation.issue("GeoIP 数据库加载失败；未启用候选版本。") }
        }
        if resources.contains(where: { $0.key == "geo:geosite:dat" }) {
            error = nil
            let result = HakoPrepareGeoSiteCache(prepared.runtimeJSON, &error)
            guard error == nil, result.contains(", 0 failed of ") else { throw ConfigurationValidation.issue("GeoSite 分类编译失败；未启用候选版本。") }
        }
        logger.notice("phase2.resources.ready memory=\(HakoMemoryFootprint(), privacy: .public)")
    }

    static func makeService(platform: HakoPlatformInterfaceProtocol) throws -> HakoBoxService {
        var error: NSError?
        guard let service = HakoNewService(platform, &error) else { throw PrototypeError.coreService }
        return service
    }
}
