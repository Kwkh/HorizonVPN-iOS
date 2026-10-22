import Testing
import Network
@testable import Horizon

struct NetworkAvailabilityTests {
    @Test @MainActor func onlyAnExplicitlyUnavailablePathBlocksConnection() {
        #expect(NetworkAvailability.availability(for: .unsatisfied) == .offline)
        #expect(NetworkAvailability.availability(for: .satisfied) == .available)
        #expect(NetworkAvailability.availability(for: .requiresConnection) == .available)
        #expect(!NetworkAvailability(monitorSystem: false).isOffline)
    }

    @Test @MainActor func offlineConnectDoesNotPrepareOrStartVPN() async {
        let network = NetworkAvailability(initialStatus: .offline, monitorSystem: false)
        let repository = SubscriptionRepository(storage: MemorySubscriptionStorage())
        let controller = TunnelController(repository: repository, permitsNetwork: false, network: network)
        await controller.connectCurrentProfile()
        #expect(!controller.hasProfile && !controller.isTunnelActive)
        #expect(controller.events.count == 1)
        #expect(controller.message == "当前无网络连接，请检查 Wi-Fi 或蜂窝数据。")
        controller.start()
        #expect(controller.events.count == 2)
        #expect(!controller.canStart)

        network.setPreviewStatus(.available)
        #expect(!network.isOffline)
        #expect(!controller.hasProfile && !controller.isTunnelActive)
        // A restored path never triggers an automatic start or permission request.
        #expect(controller.events.count == 2)
    }
}
