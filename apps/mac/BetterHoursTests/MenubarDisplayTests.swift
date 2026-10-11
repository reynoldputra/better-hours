import XCTest
@testable import Better_Hours

final class MenubarDisplayTests: XCTestCase {
    private func text(_ display: MenubarDisplay, running: Bool, elapsed: TimeInterval, today: TimeInterval) -> String? {
        display.labelText(isRunning: running, elapsed: elapsed, todayTotal: today)
    }

    func testCurrentShowsOnlyTheRunningBlock() {
        XCTAssertNil(text(.current, running: false, elapsed: 0, today: 0))
        XCTAssertNil(text(.current, running: false, elapsed: 0, today: 7200))
        XCTAssertEqual(text(.current, running: true, elapsed: 0, today: 0), "0:00")
        XCTAssertEqual(text(.current, running: true, elapsed: 1800, today: 7200), "0:30")
    }

    func testTodayShowsTheTotalWhetherOrNotRunning() {
        XCTAssertEqual(text(.today, running: false, elapsed: 0, today: 5400), "1:30")
        XCTAssertEqual(text(.today, running: true, elapsed: 600, today: 5400), "1:30")
    }

    func testTodayWithZeroTotal() {
        XCTAssertNil(text(.today, running: false, elapsed: 0, today: 0))
        XCTAssertEqual(text(.today, running: true, elapsed: 0, today: 0), "0:00")
    }

    func testTodayIsLargerThanTheRunningBlock() {
        XCTAssertEqual(text(.today, running: true, elapsed: 900, today: 9000), "2:30")
        XCTAssertEqual(text(.current, running: true, elapsed: 900, today: 9000), "0:15")
    }

    func testStoredValueRoundTrips() {
        XCTAssertEqual(MenubarDisplay(rawValue: "today"), .today)
        XCTAssertEqual(MenubarDisplay.current.rawValue, "current")
        XCTAssertNil(MenubarDisplay(rawValue: "bogus"))
    }
}
