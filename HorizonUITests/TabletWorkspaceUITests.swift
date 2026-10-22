import XCTest

final class TabletWorkspaceUITests: XCTestCase {
    @MainActor
    func testGridsSwitchBrowseAndImportWithoutChangingHome() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment = ["CLASH_SUBSCRIPTIONS_DEMO": "1", "CLASH_STARTUP_AUDIT": "ready", "CLASH_STARTUP_STYLE": "horizon"]
        app.launch()
        let nodesTab = app.buttons["tablet.navigation.nodes"]
        XCTAssertTrue(nodesTab.waitForExistence(timeout: 15)); nodesTab.tap()
        XCTAssertTrue(app.buttons["nodes.select.0"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["nodes.ping.0"].exists)
        XCTAssertEqual(app.tabBars.count, 0)
        capture("iPad node grid")
        app.buttons["tablet.navigation.subscriptions"].tap()
        let choices = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'subscription.choose.'"))
        XCTAssertTrue(choices.firstMatch.waitForExistence(timeout: 8)); XCTAssertEqual(choices.count, 2)
        XCTAssertEqual(choices.element(boundBy: 0).frame.minY, choices.element(boundBy: 1).frame.minY, accuracy: 2, "Wide window must show cards in a row")
        capture("iPad subscription grid")
        let detail = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'subscription.details.'")).element(boundBy: 1)
        detail.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", ", Saved")).firstMatch.waitForExistence(timeout: 8), "Browsing another subscription must not activate it")
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(choices.firstMatch.waitForExistence(timeout: 8))
        app.buttons["subscriptions.importURL"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 8))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(choices.firstMatch.waitForExistence(timeout: 8))
        choices.element(boundBy: 1).tap()
        let switched = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: choices.element(boundBy: 1))
        XCTAssertEqual(XCTWaiter.wait(for: [switched], timeout: 10), .completed)
        app.buttons["tablet.navigation.nodes"].tap()
        XCTAssertTrue(app.buttons["nodes.select.1"].waitForExistence(timeout: 8))
        app.buttons["nodes.select.1"].tap()
        XCTAssertTrue(app.buttons["nodes.ping.1"].exists)
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.buttons["nodes.select.1"].waitForExistence(timeout: 5))
        capture("iPad node grid portrait")
        XCTAssertEqual(app.alerts.count, 0)
        app.buttons["tablet.navigation.home"].tap()
        XCTAssertTrue(app.buttons["tablet.navigation.settings"].waitForExistence(timeout: 5))
        capture("iPad unified navigation home")
        app.buttons["tablet.navigation.settings"].tap()
        let replay = app.buttons["settings.replayIntroduction"]
        if !replay.isHittable { app.swipeUp() }
        XCTAssertTrue(replay.waitForExistence(timeout: 5))
        replay.tap()
        XCTAssertTrue(app.buttons["welcome.next"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["tablet.navigation.settings"].isHittable)
        XCTAssertEqual(app.tabBars.count, 0)
    }
    @MainActor
    func testTabletIntroStagesAndHandoff() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment = ["CLASH_SUBSCRIPTIONS_DEMO": "1", "CLASH_STARTUP_AUDIT": "empty", "CLASH_STARTUP_STYLE": "horizon", "CLASH_FIRST_LAUNCH_PREVIEW": "1"]
        app.launch()
        let welcome = app.buttons["welcome.next"]
        XCTAssertTrue(welcome.waitForExistence(timeout: 15))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true AND hittable == true"), object: welcome)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
        welcome.tap()
        let next = app.buttons["guide.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 2); capture("iPad intro cards")
        next.tap(); Thread.sleep(forTimeInterval: 2); capture("iPad intro nodes")
        next.tap(); Thread.sleep(forTimeInterval: 2); capture("iPad intro wall")
        let scene = app.descendants(matching: .any)["guide.pullToContinue"].firstMatch
        XCTAssertTrue(scene.exists)
        let start = scene.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 220)))
        XCTAssertTrue(scene.waitForNonExistence(timeout: 12))
        let skip = app.buttons["home.skipIntroduction"]
        if skip.waitForExistence(timeout: 2), skip.isHittable { skip.tap() }
        XCTAssertTrue(app.buttons["tablet.navigation.nodes"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.alerts.count, 0)
    }
    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
