import XCTest
import AppIntents
import NetworkExtension
@testable import Horizon

@MainActor final class ConnectionWidgetTests: XCTestCase {
    func testConnectionIntentCanStartLiveActivityWithoutOpeningApp() {
        func requireBackgroundActivity<T: LiveActivityIntent & SetValueIntent>(_: T.Type) {
            XCTAssertTrue(T.supportedModes.contains(.background))
            XCTAssertFalse(T.openAppWhenRun)
        }
        requireBackgroundActivity(SetVPNConnectionIntent.self)
    }

    func testUnavailableControllerCannotStartVPNFromWidget() async {
        let service = ConnectionWidgetService()
        let tunnel = TunnelController(permitsNetwork: false)
        service.controller = tunnel
        do {
            try await service.setConnected(true)
            XCTFail("A widget must not bypass profile and configuration setup")
        } catch ConnectionWidgetService.Failure.setupRequired {
            XCTAssertFalse(tunnel.isTunnelActive)
            XCTAssertFalse(tunnel.isBusy)
        } catch { XCTFail("Unexpected error: \(error)") }
        // Failed invocations must release the action gate so setup/retry remains possible.
        do {
            try await service.setConnected(true)
            XCTFail("Expected setup requirement")
        } catch ConnectionWidgetService.Failure.setupRequired { }
        catch { XCTFail("The previous failure left the action gate locked") }
    }

    func testWidgetPresentationContainsNoConfigurationPayload() throws {
        let snapshot = ConnectionWidgetState(phase: .connected, subscription: "Example")
        let data = try JSONEncoder().encode(snapshot)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["phase", "subscription", "updatedAt"])
        XCTAssertEqual(try JSONDecoder().decode(ConnectionWidgetState.self, from: data), snapshot)
    }
}
