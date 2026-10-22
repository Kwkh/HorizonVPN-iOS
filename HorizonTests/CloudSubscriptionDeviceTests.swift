import CloudKit
import Foundation
import NetworkExtension
import XCTest
@testable import Horizon

/// Explicitly opt-in, stateful Development-only checks across two real devices.
/// Uses the real protected library. Run only after permission to upload its contents.
/// Every mutation targets the uniquely marked fictional subscription, never a user's entry.
@MainActor final class CloudSubscriptionDeviceTests: XCTestCase {
    private struct CheckFailure: Error { let check: String }
    private struct Report: Codable {
        var phase: String
        var run: String
        var fixtureID: UUID?
        var passed = false
        var status = "not-started"
        var entries = 0
        var reviews = 0
        var blocked = 0
        var checks: [String] = []
        var failure: String?
    }

    func testDevelopmentRoundTripPhase() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["HORIZON_CLOUD_DEVICE_CHECK"] == "AUTHORIZED",
              let phase = environment["HORIZON_CLOUD_DEVICE_PHASE"],
              let runText = environment["HORIZON_CLOUD_DEVICE_RUN"],
              let run = UUID(uuidString: runText) else {
            throw XCTSkip("Manual real-device CloudKit check requires explicit authorization and a run ID")
        }
        guard CloudSyncScope.environment == "Development" else { throw XCTSkip("Never run against Production") }
        let managers = try await NETunnelProviderManager.loadAllFromPreferences().filter {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == "Kenote.Clash.PacketTunnel"
        }
        for manager in managers where ![.invalid, .disconnected].contains(manager.connection.status) {
            manager.connection.stopVPNTunnel()
        }
        for _ in 0..<30 where managers.contains(where: { ![.invalid, .disconnected].contains($0.connection.status) }) {
            try await Task.sleep(for: .seconds(1))
        }
        guard managers.allSatisfy({ [.invalid, .disconnected].contains($0.connection.status) }) else {
            throw CheckFailure(check: "VPN did not disconnect before integration checks")
        }
        // RootTabView must not run a second sync engine concurrently with this test.
        guard !UserDefaults.standard.bool(forKey: "cloudSync.enabled") else {
            throw CheckFailure(check: "Disable automatic sync before manual integration checks")
        }
        let repository = ConfigurationVault.repository
        let before = try repository.library()
        let active = try before.activeID.map { try repository.record($0) }
        let title = "HORIZON Sync Check " + String(run.uuidString.prefix(8))
        let renamed = title + " Renamed"
        let sourceURL = "https://sync-check.example.invalid/sub?token=FICTIONAL"
        let resourceBytes = Data("payload:\n  - sync-check.example.invalid\n".utf8)
        let original = Data((PrototypeSelfCheck.fixture.replacingOccurrences(of: "rules: [\"MATCH,TEST-SELECT\"]", with: """
        rule-providers:
          CloudCheck: {type: http, behavior: domain, url: 'https://sync-check.example.invalid/rules.yaml'}
        rules: ['RULE-SET,CloudCheck,TEST-SELECT', 'MATCH,TEST-SELECT']
        """) + "\n# HORIZON-CLOUD-CHECK: " + run.uuidString + "\n").utf8)
        var report = Report(phase: phase, run: run.uuidString,
                            fixtureID: environment["HORIZON_CLOUD_DEVICE_FIXTURE_ID"].flatMap(UUID.init(uuidString:)))
        let engine = SubscriptionCloudSyncEngine(repository: repository)
        func require(_ condition: Bool, _ name: String) throws {
            guard condition else { throw CheckFailure(check: name) }
            report.checks.append(name)
        }
        func verifyLocal(_ id: UUID, expectedTitle: String) throws -> Bool {
            guard let summary = try repository.index()?.entries.first(where: { $0.id == id }),
                  summary.title == expectedTitle else { return false }
            let record = try repository.record(id)
            try require(try ConfigurationSnapshot.original(record.source) == original, "original-bytes-identical")
            try require(record.sourceURL == sourceURL, "fictional-source-url-identical")
            let resource = ConfigurationSnapshot.Resource(key: "rule:CloudCheck",
                digest: ConfigurationResourceStore.digest(resourceBytes), bytes: resourceBytes.count)
            try require(try ConfigurationResourceStore.load(resource, storage: repository.storage) == resourceBytes,
                        "provider-bytes-identical")
            return true
        }
        func serverVersion(_ id: UUID) async throws -> CloudSubscriptionVersion? {
            let zone = CKRecordZone.ID(zoneName: "PersonalSubscriptionsV1")
            let recordID = CKRecord.ID(recordName: "s-" + id.uuidString, zoneID: zone)
            do {
                let record = try await CKContainer(identifier: SubscriptionCloudSyncEngine.containerIdentifier)
                    .privateCloudDatabase.record(for: recordID)
                try require(record["payload"] == nil, "payload-not-plaintext")
                guard let payload = record.encryptedValues["payload"] as? Data else {
                    throw CheckFailure(check: "missing-encrypted-payload")
                }
                let value = try JSONDecoder().decode(CloudSubscriptionVersion.self, from: payload)
                try value.validate()
                return value
            } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound { return nil }
        }
        do {
            if phase == "publish" {
                let source = try ConfigurationResourceStore.stage([("rule:CloudCheck", resourceBytes)], original: original)
                defer { ConfigurationResourceStore.discardPending() }
                var record = StoredConfiguration(source: source)
                record.sourceURL = sourceURL
                report.fixtureID = try repository.add(record, fileName: "Horizon-sync-check.yaml", displayTitle: title,
                    nodeCount: 1, groupCount: 1, ruleCount: 2, makeCurrent: false)
            }
            guard let id = report.fixtureID else { throw CheckFailure(check: "missing-fixture-id") }
            if phase == "rename" || phase == "delete" {
                try require(try verifyLocal(id, expectedTitle: phase == "rename" ? title : renamed), "fixture-identity-verified")
                try require(try repository.index()?.activeID != id, "fixture-not-selected")
                if phase == "rename" { try repository.rename(id, title: renamed) }
                else { _ = try repository.delete([id]) }
            }
            var state = await engine.connect()
            var matched = false
            for attempt in 0..<12 {
                if attempt > 0 {
                    try await Task.sleep(for: .seconds(3))
                    state = await engine.tick(sendNow: true)
                }
                report.status = String(describing: state.status)
                report.reviews = state.reviews.count; report.blocked = state.blockedCount
                guard ![.noAccount, .accountChanged, .configuration, .quota].contains(state.status) else {
                    throw CheckFailure(check: "cloud-status-" + report.status)
                }
                if phase == "delete" || phase == "receive-delete" {
                    matched = try await serverVersion(id)?.deleted == true
                        && !(try repository.index()?.entries.contains(where: { $0.id == id }) ?? false)
                } else {
                    let expected = phase == "rename" || phase == "receive-rename" ? renamed : title
                    matched = try await serverVersion(id)?.title == expected && verifyLocal(id, expectedTitle: expected)
                }
                if matched { break }
            }
            try require(matched, "phase-converged")
            try require(try repository.index()?.activeID == before.activeID, "current-subscription-unchanged")
            if let id = before.activeID, let active {
                let after = try repository.record(id)
                try require(after.source == active.source && after.choices == active.choices
                    && after.certificateConsentDigest == active.certificateConsentDigest,
                    "current-content-choices-consent-unchanged")
            }
            report.entries = try repository.index()?.entries.count ?? 0
            report.passed = true
            await engine.stop()
            try save(report)
            // The operator's explicit opt-in covers leaving the normal feature on.
            // Only enable after the final fictional deletion has converged safely.
            if environment["HORIZON_CLOUD_DEVICE_ENABLE_ON_SUCCESS"] == "1",
               phase == "delete" || phase == "receive-delete" {
                UserDefaults.standard.set(true, forKey: "cloudSync.enabled")
            }
        } catch {
            await engine.stop()
            if let error = error as? CheckFailure { report.failure = error.check }
            else if let error = error as? CKError { report.failure = "CKError-" + String(error.code.rawValue) }
            else { report.failure = String(reflecting: type(of: error)) }
            try? save(report)
            XCTFail("Device CloudKit check failed: " + (report.failure ?? "unknown"))
        }
    }

    private func save(_ report: Report) throws {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try JSONEncoder().encode(report).write(to: directory.appendingPathComponent("cloud-device-check.json"), options: .atomic)
    }
}
