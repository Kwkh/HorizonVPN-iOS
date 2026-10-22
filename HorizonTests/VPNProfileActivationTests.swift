import XCTest
@testable import Horizon

@MainActor final class VPNProfileActivationTests: XCTestCase {
    func testDisabledStoredProfileIsReloadedEnabledSavedAndReloaded() async throws {
        var cached = true
        var stored = false
        var events: [String] = []
        try await VPNProfileActivation.prepare(load: { events.append("load"); cached = stored },
            validate: { events.append("validate") }, isEnabled: { cached },
            enableAndSave: { events.append("save"); stored = true; cached = true })
        XCTAssertEqual(events, ["load", "validate", "save", "load", "validate"])
        XCTAssertTrue(cached)
    }
    func testEnabledProfileDoesNotWritePreferences() async throws {
        try await VPNProfileActivation.prepare(load: {}, validate: {}, isEnabled: { true },
            enableAndSave: { XCTFail("Already enabled profile must not be saved again") })
    }
    func testInvalidOwnershipCannotBeEnabled() async {
        do {
            try await VPNProfileActivation.prepare(load: {}, validate: { throw PrototypeError.start },
                isEnabled: { false }, enableAndSave: { XCTFail("Invalid profile must not be modified") })
            XCTFail("Expected rejection")
        } catch { }
    }
    func testSaveFailureAndStillDisabledAreNotReportedReady() async {
        for failSave in [true, false] {
            do {
                try await VPNProfileActivation.prepare(load: {}, validate: {}, isEnabled: { false },
                    enableAndSave: { if failSave { throw PrototypeError.start } })
                XCTFail("Must not start a disabled profile")
            } catch { }
        }
    }
}
