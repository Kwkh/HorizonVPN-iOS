import XCTest

final class WallInteractionTests: XCTestCase {
    @MainActor
    func testLongHoldOwnsDragAndReleaseRestoresScrolling() {
        let app = XCUIApplication()
        app.launchEnvironment["CLASH_HORIZON_PREVIEW"] = "1"
        app.launch()
        let button = app.buttons["home.connection"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        let scroll = app.scrollViews.firstMatch
        let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
        let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        let initialY = button.frame.midY

        start.press(forDuration: 0.65, thenDragTo: end)
        XCTAssertEqual(button.frame.midY, initialY, accuracy: 2, "A held wall drag must not scroll the page")

        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertLessThan(button.frame.midY, initialY - 30, "The next normal drag must scroll without waiting for a hold")
    }
}
