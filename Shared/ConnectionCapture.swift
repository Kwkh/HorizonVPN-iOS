import Foundation

/// Only returned during an explicitly requested, bounded diagnostic session.
/// Never includes URLs, ports, process names, content, source addresses or raw errors.
nonisolated struct CapturedConnection: Codable, Identifiable {
    var id: UUID { match.id }
    let match: RuleObservation
    let destination: String?
    let family: String
    let upload: Int64
    let download: Int64
    let observedAt: Date

    static func sanitize(_ json: String, catalog: ConfigurationCatalog, rules: [String], now: Date) -> [Self]? {
        guard let matches = RuleObservation.sanitize(json, catalog: catalog, rules: rules),
              let root = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let entries = root["connections"] as? [[String: Any]] else { return nil }
        var byID: [UUID: [String: Any]] = [:]
        for entry in entries.suffix(60) {
            if let id = (entry["id"] as? String).flatMap(UUID.init(uuidString:)) { byID[id] = entry }
        }
        return matches.suffix(30).compactMap { match in
            guard let entry = byID[match.id] else { return nil }
            let metadata = entry["metadata"] as? [String: Any] ?? [:]
            let host = metadata["host"] as? String ?? ""
            let ip = metadata["destinationIP"] as? String ?? ""
            let validIP = ConfigurationValidation.address(ip, ipv6: ip.contains(":"))
            let destination = DNSStage.validDomain(host) ? host.lowercased() : validIP ? ip : nil
            func count(_ key: String) -> Int64 {
                guard let number = entry[key] as? NSNumber, number.doubleValue.isFinite,
                      number.doubleValue >= 0, number.doubleValue < Double(Int64.max) else { return 0 }
                return number.int64Value
            }
            return .init(match: match, destination: destination, family: validIP ? (ip.contains(":") ? "IPv6" : "IPv4") : "—",
                upload: count("upload"), download: count("download"), observedAt: now)
        }
    }
}

/// Driven by the extension lifecycle queue. Records expire even if the app stays in the background.
nonisolated struct ConnectionCapture {
    private(set) var endsAt: TimeInterval?
    private(set) var expiresAt: TimeInterval?
    private(set) var rows: [CapturedConnection] = []
    mutating func start(now: TimeInterval) { rows = []; endsAt = now + 60; expiresAt = now + 300 }
    mutating func clear() { rows = []; endsAt = nil; expiresAt = nil }
    mutating func expire(now: TimeInterval) {
        if let expiresAt, now >= expiresAt { clear() }
    }
    func running(now: TimeInterval) -> Bool { endsAt.map { now < $0 } ?? false }
    mutating func ingest(_ values: [CapturedConnection], now: TimeInterval) {
        expire(now: now)
        guard running(now: now) else { return }
        // Update existing counters, retain connections that have since closed.
        for value in values {
            if let i = rows.firstIndex(where: { $0.id == value.id }) { rows[i] = value }
            else { rows.append(value) }
        }
        rows = Array(rows.suffix(30))
    }
}
