import Foundation
import Testing
@testable import Horizon

struct CertificateConsentTests {
    @Test @MainActor func importingDoesNotAuthorizeAndExplicitConsentIsContentBound() async throws {
        let repository = SubscriptionRepository(storage: MemorySubscriptionStorage())
        let source = Data(PrototypeSelfCheck.fixture.replacingOccurrences(of: "    up: 10", with: "    skip-cert-verify: true\n    up: 10").utf8)
        let prepared = try PrototypeConfiguration.prepare(source)
        let id = try repository.add(StoredConfiguration(source: source), fileName: "fixture.yaml", nodeCount: 1, groupCount: 1, ruleCount: 1, makeCurrent: true)
        let controller = TunnelController(repository: repository, permitsNetwork: false,
            network: NetworkAvailability(initialStatus: .available, monitorSystem: false))
        await controller.refresh()
        await controller.connectCurrentProfile()
        let request = try #require(controller.certificateApproval)
        #expect(request.id == id && request.nodeCount == 1)
        #expect(!controller.hasProfile && !controller.isTunnelActive)
        #expect(try repository.record(id).certificateConsentDigest == nil)
        controller.dismissCertificateApproval()
        #expect(try repository.record(id).certificateConsentDigest == nil)
        await controller.connectCurrentProfile()
        #expect(controller.certificateApproval != nil)
        await controller.approveCertificates(request)
        #expect(controller.certificateApproval == nil)
        try repository.record(id).requireCertificateConsent(for: prepared)
        #expect(!controller.hasProfile && !controller.isTunnelActive) // Isolated test forbids real VPN.

        let previous = try repository.record(id)
        try repository.replace(id, expected: previous, source: source + Data("\n# revision\n".utf8), choices: previous.choices,
            sourceURL: nil, nodeCount: 1, groupCount: 1, ruleCount: 1)
        await controller.approveCertificates(request) // Stale UI callback cannot authorize new content.
        #expect(try repository.record(id).certificateConsentDigest == nil)
        await controller.connectCurrentProfile()
        #expect(controller.certificateApproval?.digest != request.digest)
        #expect(controller.certificateApproval?.nodeCount == 1)
    }
}
