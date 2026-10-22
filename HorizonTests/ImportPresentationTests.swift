import Foundation
import Testing
@testable import Horizon

@MainActor @Suite(.serialized) struct ImportPresentationTests {
    @Test func successfulSaveKeepsPreviewUntilSheetDismisses() async throws {
        let repository = SubscriptionRepository(storage: MemorySubscriptionStorage())
        let tunnel = TunnelController(repository: repository, permitsNetwork: false,
            network: NetworkAvailability(initialStatus: .available, monitorSystem: false))
        await tunnel.refresh()
        let source = Data(PrototypeSelfCheck.fixture.utf8)
        #expect(await tunnel.prepareDownloadedImport(source, title: "Import preview"))
        let preview = try #require(tunnel.importPreview)
        #expect(await tunnel.confirmImport(makeCurrent: true))
        // URL-import's conditional page must remain the confirmation page while dismissing.
        #expect(tunnel.importPreview?.id == preview.id)
        #expect(tunnel.subscriptions.count == 1 && tunnel.activeSubscriptionID != nil)
        #expect(!tunnel.isTunnelActive && !tunnel.hasProfile)
        // Pending content was consumed, preventing a duplicate save while dismissal is in flight.
        #expect(await tunnel.confirmImport(makeCurrent: true) == false)
        tunnel.cancelImport()
        #expect(tunnel.importPreview == nil)
        #expect(tunnel.subscriptions.count == 1)
    }
}
