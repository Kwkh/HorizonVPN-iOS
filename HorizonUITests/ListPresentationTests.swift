import XCTest

final class ListPresentationTests: XCTestCase {
    @MainActor
    func testSubscriptionNavigationAndSwipeActions() {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "CLASH_SUBSCRIPTIONS_DEMO": "1",
            "CLASH_STARTUP_AUDIT": "ready",
            "CLASH_STARTUP_STYLE": "horizon"
        ]
        continueAfterFailure = false
        app.launch()
        let nodes = app.tabBars.buttons.matching(NSPredicate(format: "label == 'Nodes' OR label == '节点'")).firstMatch
        XCTAssertTrue(nodes.waitForExistence(timeout: 10))
        nodes.tap()
        let configurations = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Configurations' OR label CONTAINS '配置文件'")).firstMatch
        XCTAssertTrue(configurations.waitForExistence(timeout: 5))
        configurations.tap()
        let choices = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'subscription.choose.'"))
        XCTAssertTrue(choices.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(choices.count, 2)
        let secondChoice = choices.element(boundBy: 1)
        let origin = secondChoice.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        origin.press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: -110, dy: 0)))
        let delete = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'subscription.delete.'")).firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "Row projection must retain native swipe actions")
        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "Subscription separators and native swipe action"
        evidence.lifetime = .keepAlways
        add(evidence)
    }
}
