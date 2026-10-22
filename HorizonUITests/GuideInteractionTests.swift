import XCTest

final class GuideInteractionTests: XCTestCase {
    @MainActor
    func testPartThreePagePullAndNavigation() {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "CLASH_SUBSCRIPTIONS_DEMO": "1",
            "CLASH_STARTUP_AUDIT": "empty",
            "CLASH_STARTUP_STYLE": "horizon",
            "CLASH_FIRST_LAUNCH_PREVIEW": "1"
        ]
        continueAfterFailure = false
        app.launch()
        let welcomeNext = app.buttons["welcome.next"]
        XCTAssertTrue(welcomeNext.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 5) // The welcome title completes before Next accepts taps.
        welcomeNext.tap()
        let next = app.buttons["guide.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["Bring your world"].firstMatch.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 2)
        next.tap()
        XCTAssertTrue(app.descendants(matching: .any)["Choose your path"].firstMatch.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 2)
        next.tap()
        XCTAssertTrue(app.descendants(matching: .any)["Beyond the wall"].firstMatch.waitForExistence(timeout: 5))
        let scene = app.descendants(matching: .any)["guide.pullToContinue"].firstMatch
        XCTAssertTrue(scene.waitForExistence(timeout: 5))
        // Chapter motion must settle before interactive continuation is armed.
        Thread.sleep(forTimeInterval: 2)
        let previous = app.buttons["guide.previous"]

        // Begin below the scene, in the title area. A short drag must return.
        let titleStart = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: app.frame.midX, dy: scene.frame.maxY + 35))
        titleStart.press(forDuration: 0.05,
                         thenDragTo: titleStart.withOffset(CGVector(dx: 0, dy: 30)))
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true AND isHittable == true"), object: previous)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed)
        XCTAssertTrue(scene.exists, "A short pull outside the scene must not enter")
        previous.tap()
        XCTAssertFalse(scene.exists, "The page gesture must preserve the Previous button")
        next.tap()
        XCTAssertTrue(scene.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 2)

        // Begin in the lower text/blank area; travel matches the original scene threshold.
        let lowerStart = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: app.frame.midX, dy: scene.frame.maxY + 110))
        lowerStart.press(forDuration: 0.05,
                         thenDragTo: lowerStart.withOffset(CGVector(dx: 0, dy: scene.frame.height * 0.45)))
        XCTAssertTrue(scene.waitForNonExistence(timeout: 8), "A full pull below the scene must continue")
    }
}
