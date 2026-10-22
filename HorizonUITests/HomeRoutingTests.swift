import XCTest

final class HomeRoutingTests: XCTestCase {
    @MainActor
    func testRoutingAppliesDirectlyInBothDirections() {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "CLASH_SUBSCRIPTIONS_DEMO": "1",
            "CLASH_STARTUP_AUDIT": "ready",
            "CLASH_STARTUP_STYLE": "horizon"
        ]
        continueAfterFailure = false
        app.launch()
        let picker = app.segmentedControls["home.routing"]
        XCTAssertTrue(picker.waitForExistence(timeout: 15))
        for _ in 0..<3 where !picker.isHittable { app.swipeUp() }
        let original = picker.buttons.element(boundBy: 0)
        let smart = picker.buttons.element(boundBy: 1)
        XCTAssertTrue(original.isSelected)
        smart.tap()
        let saved = expectation(for: NSPredicate(format: "selected == true"), evaluatedWith: smart)
        wait(for: [saved], timeout: 30)
        XCTAssertTrue(picker.exists, "Home must remain visible without a review or confirmation sheet")
        XCTAssertEqual(app.alerts.count, 0)
        let ready = expectation(for: NSPredicate(format: "value == 'Applied' OR value == '已应用'"), evaluatedWith: picker)
        wait(for: [ready], timeout: 10)
        original.tap()
        let restored = expectation(for: NSPredicate(format: "selected == true"), evaluatedWith: original)
        wait(for: [restored], timeout: 30)
        let finished = expectation(for: NSPredicate(format: "value == 'Applied' OR value == '已应用'"), evaluatedWith: picker)
        wait(for: [finished], timeout: 30)
        XCTAssertTrue(picker.isHittable)
        XCTAssertEqual(app.alerts.count, 0)
        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "Home routing direct application"
        evidence.lifetime = .keepAlways
        add(evidence)
    }
}
