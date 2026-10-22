import XCTest
import SwiftUI
@testable import Horizon

final class TabletWorkspaceTests: XCTestCase {
    func testGuideContainsTabletStageAndDoesNotAlterPhoneViewport() {
        for width: CGFloat in [390, 744, 1032, 1376] {
            let frame = CGRect(x: 0, y: 52, width: width, height: 430)
            let tablet = HorizonGuideFraming.viewport(frame, tablet: true)
            XCTAssertLessThanOrEqual(tablet.width / tablet.height, 1.15 + 0.001)
            XCTAssertEqual(tablet.midX, frame.midX)
            XCTAssertEqual(tablet.height, frame.height)
            XCTAssertEqual(HorizonGuideFraming.viewport(frame, tablet: false), frame)
        }
    }
    func testAdjacentChapterCannotLeakIntoTabletStage() {
        for chapter in 0...2 {
            for focus in 0...2 {
                XCTAssertEqual(HorizonGuideFraming.visibility(chapter: chapter, focus: Double(focus), tablet: true), chapter == focus ? 1 : 0)
                XCTAssertEqual(HorizonGuideFraming.visibility(chapter: chapter, focus: Double(focus), tablet: false), 1)
            }
        }
        XCTAssertEqual(HorizonGuideFraming.visibility(chapter: 0, focus: 0.5, tablet: true), 0.5)
        XCTAssertEqual(HorizonGuideFraming.visibility(chapter: 1, focus: 0.5, tablet: true), 0.5)
    }
    func testNarrowGridAndAccessibilityDoNotOverflow() {
        typealias Grid = TabletCardGrid<EmptyView, EmptyView>
        XCTAssertEqual(Grid.columnCount(width: 280, accessibility: false), 1)
        XCTAssertEqual(Grid.columnCount(width: 900, accessibility: false), 2)
        XCTAssertEqual(Grid.columnCount(width: 1150, accessibility: false), 3)
        XCTAssertEqual(Grid.columnCount(width: 1150, accessibility: true), 1)
    }
}
