import SwiftUI
import Observation
import NetworkExtension

@MainActor @Observable final class AppSettings {
    enum InterfaceStyle: String, CaseIterable { case classic, horizon }
    enum Language: String, CaseIterable { case system, chinese, english }
    enum Appearance: String, CaseIterable { case dark, light, system }
    enum TrafficMapping: String { case logarithmic, linear }
    enum TrafficScale: Double, CaseIterable {
        case hundredKB = 100_000, oneMB = 1_000_000, tenMB = 10_000_000, hundredMB = 100_000_000
        var label: String {
            switch self {
            case .hundredKB: "100 KB/s"
            case .oneMB: "1 MB/s"
            case .tenMB: "10 MB/s"
            case .hundredMB: "100 MB/s"
            }
        }
    }
    var interfaceStyle: InterfaceStyle { didSet { defaults.set(interfaceStyle.rawValue, forKey: "ui.interfaceStyle") } }
    var isHorizon: Bool { interfaceStyle == .horizon }
    var language: Language { didSet { defaults.set(language.rawValue, forKey: "ui.language") } }
    var appearance: Appearance { didSet { defaults.set(appearance.rawValue, forKey: "ui.appearance") } }
    var globeScale: Double { didSet { defaults.set(globeScale, forKey: "ui.globeScale") } }
    var brickScale: Double { didSet { defaults.set(brickScale, forKey: "ui.brickScale") } }
    var confirmVPNConnection: Bool { didSet { defaults.set(confirmVPNConnection, forKey: "connection.confirmBeforeConnecting") } }
    var showOriginalNames: Bool { didSet { defaults.set(showOriginalNames, forKey: "ui.showOriginalNames") } }
    var liveActivityEnabled: Bool { didSet { defaults.set(liveActivityEnabled, forKey: "connection.liveActivity") } }
    var particles: Bool { didSet { defaults.set(particles, forKey: "ui.particles") } }
    var trafficScale: TrafficScale { didSet { defaults.set(trafficScale.rawValue, forKey: "ui.trafficScale") } }
    var trafficMapping: TrafficMapping { didSet { defaults.set(trafficMapping.rawValue, forKey: "ui.trafficMapping") } }
    @ObservationIgnored private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        liveActivityEnabled = defaults.object(forKey: "connection.liveActivity") as? Bool ?? true
        showOriginalNames = defaults.object(forKey: "ui.showOriginalNames") as? Bool ?? false
        confirmVPNConnection = defaults.object(forKey: "connection.confirmBeforeConnecting") as? Bool ?? true
        interfaceStyle = InterfaceStyle(rawValue: defaults.string(forKey: "ui.interfaceStyle") ?? "horizon") ?? .horizon
        language = Language(rawValue: defaults.string(forKey: "ui.language") ?? "system") ?? .system
        appearance = Appearance(rawValue: defaults.string(forKey: "ui.appearance") ?? "dark") ?? .dark
        let savedGlobeScale = (defaults.object(forKey: "ui.globeScale") as? Double) ?? 1.3
        globeScale = savedGlobeScale.isFinite ? min(2, max(1, savedGlobeScale)) : 1.3
        let savedBrickScale = (defaults.object(forKey: "ui.brickScale") as? Double) ?? 1.5
        brickScale = savedBrickScale.isFinite ? min(3, max(1, savedBrickScale)) : 1.5
        particles = defaults.object(forKey: "ui.particles") as? Bool ?? true
        trafficScale = TrafficScale(rawValue: defaults.double(forKey: "ui.trafficScale")) ?? .oneMB
        // A separate key keeps the user's linear range available when trying the new default.
        trafficMapping = TrafficMapping(rawValue: defaults.string(forKey: "ui.trafficMapping") ?? "") ?? .logarithmic
    }
    var locale: Locale {
        switch language {
        case .system: .current
        case .chinese: Locale(identifier: "zh-Hans")
        case .english: Locale(identifier: "en")
        }
    }
    var colorScheme: ColorScheme? {
        if isHorizon { return .dark }
        return switch appearance { case .dark: .dark; case .light: .light; case .system: nil }
    }
    var isChinese: Bool { locale.language.languageCode?.identifier == "zh" }
    func text(_ chinese: String, _ english: String) -> String { isChinese ? chinese : english }
    func statusText(_ status: NEVPNStatus) -> String {
        switch status {
        case .connected: text("已连接", "Connected")
        case .connecting: text("连接中", "Connecting")
        case .disconnecting: text("断开中", "Disconnecting")
        case .reasserting: text("恢复连接中", "Reconnecting")
        case .disconnected: text("未连接", "Disconnected")
        default: text("未准备", "Not ready")
        }
    }
    func subscriptionSummary(_ item: SubscriptionSummary) -> String {
        text(item.countSummary, item.nodeCount == 0 ? "Legacy configuration · Revalidated on selection" :
             "\(item.nodeCount) nodes · \(item.groupCount) groups · \(item.ruleCount) rules")
    }
    func nodeLabel(_ catalog: ConfigurationCatalog, name: String) -> String {
        if showOriginalNames, catalog.nodes.contains(where: { $0.name == name }) || catalog.groups.contains(where: { $0.name == name }) { return name }
        if isChinese { return catalog.label(for: name) }
        if let index = catalog.nodes.firstIndex(where: { $0.name == name }) {
            return "Node \(index + 1) · \(catalog.nodes[index].kind.uppercased())"
        }
        if let group = catalog.groups.first(where: { $0.name == name }) { return "Group \(group.id + 1)" }
        return name == "DIRECT" ? "Direct" : "Reject"
    }
    func probeLabel(_ catalog: ConfigurationCatalog) -> String {
        catalog.resolvedTarget().map { nodeLabel(catalog, name: $0) } ?? (catalog.groups.contains(where: { $0.name == catalog.matchTarget }) ? text("由策略组自动选择", "Selected by policy group") : text("当前 MATCH 目标为直连或拒绝", "MATCH routes directly or rejects traffic"))
    }
}
