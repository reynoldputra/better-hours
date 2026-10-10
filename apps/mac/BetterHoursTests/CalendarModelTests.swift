import BetterHoursCore
import XCTest
@testable import Better_Hours

@MainActor
final class CalendarModelTests: XCTestCase {
    private func model(
        store: LocalStore? = nil,
        calendar: Calendar = SampleData.calendar,
        now: Date = SampleData.now
    ) throws -> CalendarModel {
        CalendarModel(store: try store ?? LocalStore.inMemory(), clock: { now }, calendar: calendar)
    }

    func testWeekRangeStartsOnFirstWeekday() throws {
        let monday = try model()
        XCTAssertEqual(monday.range.start, SampleData.date(5, 0))
        XCTAssertEqual(monday.range.end, SampleData.date(12, 0))
        XCTAssertEqual(monday.days.count, 7)

        var sundayFirst = SampleData.calendar
        sundayFirst.firstWeekday = 1
        let sunday = try model(calendar: sundayFirst)
        XCTAssertEqual(sunday.range.start, SampleData.date(4, 0))
        XCTAssertEqual(sunday.range.end, SampleData.date(11, 0))
    }

    func testDayRangeIsOneDay() throws {
        let day = try model()
        day.setMode(.day)
        XCTAssertEqual(day.range, DateInterval(start: SampleData.date(8, 0), end: SampleData.date(9, 0)))
        XCTAssertEqual(day.days, [SampleData.date(8, 0)])
    }

    func testNavigationMovesByWeekOrDay() throws {
        let model = try model()
        model.goToNext()
        XCTAssertEqual(model.range.start, SampleData.date(12, 0))
        model.goToPrevious()
        model.goToPrevious()
        XCTAssertEqual(model.range.start, SampleData.date(28, 0, month: 9))

        model.goToToday()
        XCTAssertEqual(model.range.start, SampleData.date(5, 0))

        model.setMode(.day)
        model.goToNext()
        XCTAssertEqual(model.range.start, SampleData.date(9, 0))
        model.goToPrevious()
        model.goToPrevious()
        XCTAssertEqual(model.range.start, SampleData.date(7, 0))
        model.goToToday()
        XCTAssertEqual(model.range.start, SampleData.date(8, 0))
    }

    func testTitles() throws {
        let model = try model()
        XCTAssertEqual(model.title, "5 – 11 October 2026")
        model.goToPrevious()
        XCTAssertEqual(model.title, "28 Sep – 4 Oct 2026")
        model.setMode(.day)
        XCTAssertEqual(model.title, "Thursday, 1 October 2026")
    }

    func testInitialScrollHour() throws {
        let model = try model()
        XCTAssertEqual(model.initialScrollHour, 9)
        model.goToNext()
        XCTAssertEqual(model.initialScrollHour, 8)
    }

    func testDayTotalsMatchCanvas() async throws {
        let model = try model(store: try await SampleData.seeded())
        await model.reload()
        let totals = model.columns.map { TimeFormat.duration($0.total) }
        XCTAssertEqual(totals, ["3:30", "4:00", "5:00", "1:54", "0:00", "0:00", "0:00"])
        XCTAssertEqual(model.columns.map(\.isToday), [false, false, false, true, false, false, false])
    }

    func testOverlapGetsSideBySideSlots() async throws {
        let model = try model(store: try await SampleData.seeded())
        await model.reload()
        let wednesday = model.columns[2].pieces
        XCTAssertEqual(wednesday.map(\.block.title), ["Code review", "Email", "Design system"])
        XCTAssertEqual(wednesday.map(\.slot), [ColumnSlot(index: 0, count: 2), ColumnSlot(index: 1, count: 2), ColumnSlot(index: 0, count: 1)])
    }

    func testRunningBlockEndsAtNow() async throws {
        let model = try model(store: try await SampleData.seeded())
        await model.reload()
        let running = try XCTUnwrap(model.columns[3].pieces.last)
        XCTAssertTrue(running.isRunningNow)
        XCTAssertEqual(running.end, SampleData.now)
    }

    func testBlockAcrossMidnightIsSplitPerDay() async throws {
        let store = try LocalStore.inMemory()
        try await store.save(TimeBlock(title: "Late", startAt: SampleData.date(6, 22), endAt: SampleData.date(7, 2)))
        let model = try model(store: store)
        await model.reload()
        XCTAssertEqual(model.columns[1].pieces.map(\.end), [SampleData.date(7, 0)])
        XCTAssertEqual(model.columns[2].pieces.map(\.start), [SampleData.date(7, 0)])
        XCTAssertEqual(model.columns[1].total, 2 * 3600)
        XCTAssertEqual(model.columns[2].total, 2 * 3600)
    }

    func testTotalsUpdateAfterStoreWrite() async throws {
        let store = try await SampleData.seeded()
        let model = try model(store: store)
        let observing = Task { await model.observeChanges() }
        defer { observing.cancel() }
        try await waitUntil { model.columns[4].total == 0 && !model.blocks.isEmpty }

        try await store.save(TimeBlock(title: "Extra", startAt: SampleData.date(9, 9), endAt: SampleData.date(9, 10, 15)))
        try await waitUntil { model.columns[4].total == 75 * 60 }
        XCTAssertEqual(TimeFormat.duration(model.columns[4].total), "1:15")
    }

    func testNavigationLoadsNewRange() async throws {
        let store = try await SampleData.seeded()
        let model = try model(store: store)
        await model.reload()
        model.goToNext()
        await model.reload()
        XCTAssertTrue(model.columns.allSatisfy { $0.pieces.isEmpty })
        model.goToPrevious()
        await model.reload()
        XCTAssertEqual(model.columns.map(\.pieces.count), [3, 2, 3, 2, 0, 0, 0])
    }

    func testMidnightBelongsToOnlyOneDay() throws {
        let midnight = try model(now: SampleData.date(5, 0))
        XCTAssertEqual(midnight.columns.map(\.isToday), [true, false, false, false, false, false, false])
        var sundayFirst = SampleData.calendar
        sundayFirst.firstWeekday = 1
        let sunday = try model(calendar: sundayFirst, now: SampleData.date(5, 0))
        XCTAssertEqual(sunday.columns.map(\.isToday), [false, true, false, false, false, false, false])
    }

    func testShortTouchingBlocksGoSideBySide() async throws {
        let store = try LocalStore.inMemory()
        try await store.save(TimeBlock(title: "A", startAt: SampleData.date(6, 9), endAt: SampleData.date(6, 9, 5)))
        try await store.save(TimeBlock(title: "B", startAt: SampleData.date(6, 9, 5), endAt: SampleData.date(6, 9, 10)))
        try await store.save(TimeBlock(title: "C", startAt: SampleData.date(6, 10), endAt: SampleData.date(6, 11)))
        try await store.save(TimeBlock(title: "D", startAt: SampleData.date(6, 11), endAt: SampleData.date(6, 12)))
        let model = try model(store: store)
        await model.reload()
        let slots = model.columns[1].pieces.map(\.slot)
        XCTAssertEqual(slots.map(\.count), [2, 2, 1, 1])
        XCTAssertNotEqual(slots[0].index, slots[1].index)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("condition not met in time")
    }
}
