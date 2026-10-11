import XCTest
@testable import Better_Hours

final class TimeEntryTests: XCTestCase {
    private let entry = TimeEntry(calendar: SampleData.calendar)
    private let day = SampleData.date(11, 0)

    private func parsed(_ text: String) -> Date? { entry.parse(text, on: day) }

    func testAcceptedForms() {
        for text in ["9", "930", "9:30", "9.30", "0930", "9 pm", "9:30pm", "09:30", " 9:30 ", "9:30 PM", "9:30 p.m."] {
            let hour = text.lowercased().contains("p") ? 21 : 9
            let minute = text.contains("30") ? 30 : 0
            XCTAssertEqual(parsed(text), SampleData.date(11, hour, minute), text)
        }
        XCTAssertEqual(parsed("9a"), SampleData.date(11, 9))
        XCTAssertEqual(parsed("23:59"), SampleData.date(11, 23, 59))
        XCTAssertEqual(parsed("0"), SampleData.date(11, 0))
    }

    func testRejects() {
        for text in ["25:00", "24:00", "9:75", "abc", "", " ", "9:5", "12345", "9::30", "13pm", "0 pm", "-9", "9:30:00", "pm"] {
            XCTAssertNil(parsed(text), text)
        }
    }

    func testTwelveHourEdges() {
        XCTAssertEqual(parsed("12 am"), SampleData.date(11, 0))
        XCTAssertEqual(parsed("12 pm"), SampleData.date(11, 12))
        XCTAssertEqual(parsed("12:30am"), SampleData.date(11, 0, 30))
        XCTAssertEqual(parsed("12:30pm"), SampleData.date(11, 12, 30))
        XCTAssertEqual(parsed("1 am"), SampleData.date(11, 1))
        XCTAssertEqual(parsed("11:59 pm"), SampleData.date(11, 23, 59))
        XCTAssertEqual(parsed("12"), SampleData.date(11, 12))
    }

    func testParsingKeepsTheGivenDay() {
        XCTAssertEqual(entry.parse("7:15", on: SampleData.date(3, 22, 40)), SampleData.date(3, 7, 15))
    }

    func testFormatFollowsTheCalendarLocale() {
        XCTAssertEqual(entry.format(SampleData.date(11, 9, 5)), "09:05")
        var us = SampleData.calendar
        us.locale = Locale(identifier: "en_US")
        XCTAssertEqual(TimeEntry(calendar: us).format(SampleData.date(11, 21, 5)).replacingOccurrences(of: "\u{202F}", with: " "), "9:05 PM")
    }

    func testSteppingSnapsToFiveMinutesAndCrossesHours() {
        XCTAssertEqual(entry.step(SampleData.date(11, 9, 55), up: true, minutes: 5), SampleData.date(11, 10, 0))
        XCTAssertEqual(entry.step(SampleData.date(11, 10, 0), up: false, minutes: 5), SampleData.date(11, 9, 55))
        XCTAssertEqual(entry.step(SampleData.date(11, 9, 32), up: true, minutes: 5), SampleData.date(11, 9, 35))
        XCTAssertEqual(entry.step(SampleData.date(11, 9, 32), up: false, minutes: 5), SampleData.date(11, 9, 30))
    }

    func testSteppingStaysInsideTheDay() {
        XCTAssertEqual(entry.step(SampleData.date(11, 23, 55), up: true, minutes: 5), SampleData.date(11, 23, 55))
        XCTAssertEqual(entry.step(SampleData.date(11, 0, 0), up: false, minutes: 5), SampleData.date(11, 0, 0))
        XCTAssertEqual(entry.step(SampleData.date(11, 0, 3), up: false, minutes: 5), SampleData.date(11, 0, 0))
    }
}
