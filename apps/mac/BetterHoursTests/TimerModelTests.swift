import BetterHoursCore
import os
import XCTest
@testable import Better_Hours

@MainActor
final class TimerModelTests: XCTestCase {
    private let calendar = SampleData.calendar
    private let time = OSAllocatedUnfairLock(initialState: SampleData.date(8, 12))

    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 8) { time.withLock { $0 = SampleData.date(day, hour, minute) } }

    private func make(_ store: LocalStore) -> TimerModel {
        let time = time
        return TimerModel(store: store, clock: { time.withLock { $0 } }, calendar: calendar)
    }

    private func allBlocks(_ store: LocalStore) async throws -> [TimeBlock] {
        try await store.blocks(in: DateInterval(start: SampleData.date(1, 0), end: SampleData.date(30, 0)))
            .sorted { $0.startAt < $1.startAt }
    }

    func testIdleWithNoBlocks() async throws {
        let model = make(try LocalStore.inMemory())
        await model.refresh()
        XCTAssertFalse(model.isRunning)
        XCTAssertNil(model.lastEnded)
        XCTAssertEqual(model.elapsed, 0)
        XCTAssertEqual(model.todayTotal, 0)
        XCTAssertEqual(model.weekTotal, 0)
    }

    func testIdleWithLastEndedBlock() async throws {
        let store = try LocalStore.inMemory()
        try await store.save(TimeBlock(title: "Old", startAt: SampleData.date(6, 9), endAt: SampleData.date(6, 10)))
        try await store.save(TimeBlock(title: "Newer", startAt: SampleData.date(7, 9), endAt: SampleData.date(7, 11)))
        let model = make(store)
        await model.refresh()
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(model.lastEnded?.title, "Newer")
        XCTAssertEqual(model.weekTotal, 3 * 3600)
        XCTAssertEqual(model.todayTotal, 0)
    }

    func testStartWithAndWithoutTitle() async throws {
        let store = try LocalStore.inMemory()
        let model = make(store)
        await model.start(title: "  Write docs \n")
        XCTAssertEqual(model.running?.title, "Write docs")
        XCTAssertEqual(model.running?.startAt, SampleData.date(8, 12))
        XCTAssertNil(model.writeError)

        at(12, 5)
        await model.stop()
        at(12, 10)
        await model.start(title: "")
        XCTAssertEqual(model.running?.title, "")
        let stored2 = try await allBlocks(store)
        XCTAssertEqual(stored2.count, 2)
    }

    func testStopEndsTheBlockAndFillsLastEnded() async throws {
        let model = make(try LocalStore.inMemory())
        await model.start(title: "A")
        at(12, 30)
        await model.stop()
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(model.lastEnded?.title, "A")
        XCTAssertEqual(model.lastEnded?.endAt, SampleData.date(8, 12, 30))
        XCTAssertEqual(model.todayTotal, 30 * 60)
        await model.stop()
        XCTAssertNil(model.writeError)
    }

    func testContinueSeedsFromLastAndStartsANewBlock() async throws {
        let store = try LocalStore.inMemory()
        let project = Project(name: "Backend", color: .orange)
        try await store.save(project)
        let tags = [UUID(), UUID()]
        let last = TimeBlock(title: "Build", projectId: project.id, tagIds: tags, startAt: SampleData.date(8, 9), endAt: SampleData.date(8, 10))
        try await store.save(last)
        let model = make(store)
        await model.refresh()
        at(12, 0)
        await model.continueLast()

        let running = try XCTUnwrap(model.running)
        XCTAssertNotEqual(running.id, last.id)
        XCTAssertEqual(running.title, "Build")
        XCTAssertEqual(running.projectId, project.id)
        XCTAssertEqual(running.tagIds, tags)
        XCTAssertEqual(running.startAt, SampleData.date(8, 12))
        let stored = try await allBlocks(store)
        XCTAssertEqual(stored.count, 2)
        XCTAssertEqual(stored.first { $0.id == last.id }?.endAt, SampleData.date(8, 10))
    }

    func testContinueWithoutLastBlockDoesNothing() async throws {
        let store = try LocalStore.inMemory()
        let model = make(store)
        await model.refresh()
        await model.continueLast()
        XCTAssertFalse(model.isRunning)
        XCTAssertNil(model.writeError)
        let stored0 = try await allBlocks(store)
        XCTAssertEqual(stored0.count, 0)
    }

    func testStartWhileRunningEndsThePreviousBlock() async throws {
        let store = try LocalStore.inMemory()
        let model = make(store)
        await model.start(title: "A")
        at(12, 10)
        await model.start(title: "B")
        XCTAssertEqual(model.running?.title, "B")
        let blocks = try await allBlocks(store)
        XCTAssertEqual(blocks.map(\.title), ["A", "B"])
        XCTAssertEqual(blocks[0].endAt, SampleData.date(8, 12, 10))
        XCTAssertNil(blocks[1].endAt)
    }

    func testRenameWritesOnlyWhenTheTitleChanges() async throws {
        let store = try LocalStore.inMemory()
        let model = make(store)
        await model.start(title: "A")
        let events = OSAllocatedUnfairLock(initialState: 0)
        let stream = store.changes()
        let counting = Task { for await _ in stream { events.withLock { $0 += 1 } } }
        defer { counting.cancel() }

        await model.renameRunning("A")
        await model.renameRunning(" A ")
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(events.withLock { $0 }, 0)

        await model.renameRunning("B")
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(events.withLock { $0 }, 1)
        XCTAssertEqual(model.running?.title, "B")
        let current = try await store.runningBlock()
        XCTAssertEqual(current?.title, "B")
    }

    func testRenameAfterStopNeverReopensTheBlock() async throws {
        let store = try LocalStore.inMemory()
        let model = make(store)
        await model.start(title: "A")
        at(12, 5)
        async let stopped: Void = model.stop()
        async let renamed: Void = model.renameRunning("Late")
        _ = await (stopped, renamed)
        let open = try await store.runningBlock()
        XCTAssertNil(open)
        let stored1 = try await allBlocks(store)
        XCTAssertEqual(stored1.count, 1)
    }

    func testSetRunningProject() async throws {
        let store = try LocalStore.inMemory()
        let project = Project(name: "Writing", color: .purple)
        try await store.save(project)
        let model = make(store)
        await model.start(title: "A")
        await model.setRunningProject(project.id)
        XCTAssertEqual(model.running?.projectId, project.id)
        await model.setRunningProject(nil)
        XCTAssertNil(model.running?.projectId)
        let after = try await store.runningBlock()
        XCTAssertNil(after?.projectId)
    }

    func testTotalsIncludeRunningBlockUpToNow() async throws {
        let store = try await SampleData.seeded()
        let model = make(store)
        at(12, 24)
        await model.refresh()
        XCTAssertEqual(model.todayTotal, TimeInterval(114 * 60))
        let expected: TimeInterval = 12_600 + 14_400 + 18_000 + 6_840
        XCTAssertEqual(model.weekTotal, expected)
        XCTAssertEqual(model.elapsed, 84 * 60)

        at(12, 54)
        model.tick()
        XCTAssertEqual(model.elapsed, 114 * 60)
        XCTAssertEqual(model.todayTotal, TimeInterval(144 * 60))
    }

    func testTotalsSplitABlockAcrossMidnight() async throws {
        let store = try LocalStore.inMemory()
        try await store.save(TimeBlock(title: "Late", startAt: SampleData.date(7, 22), endAt: SampleData.date(8, 2)))
        let model = make(store)
        at(9, 0)
        await model.refresh()
        XCTAssertEqual(model.todayTotal, 2 * 3600)
        XCTAssertEqual(model.weekTotal, 4 * 3600)
    }

    func testRunningBlockAcrossMidnightCountsEachDaysPart() async throws {
        let store = try LocalStore.inMemory()
        try await store.save(TimeBlock(title: "Overnight", startAt: SampleData.date(7, 23)))
        let model = make(store)
        at(1, 0, day: 8)
        await model.refresh()
        XCTAssertEqual(model.todayTotal, 3600)
        XCTAssertEqual(model.weekTotal, 2 * 3600)
        XCTAssertEqual(model.elapsed, 2 * 3600)
    }

    func testDoubleStartCreatesOneBlockAndNoError() async throws {
        let store = try LocalStore.inMemory()
        let model = make(store)
        async let first: Void = model.start(title: "A")
        async let second: Void = model.start(title: "A")
        _ = await (first, second)
        let stored1 = try await allBlocks(store)
        XCTAssertEqual(stored1.count, 1)
        XCTAssertNil(model.writeError)
        XCTAssertTrue(model.isRunning)
    }

    func testSameMillisecondRestartReportsAnErrorWithoutCrashing() async throws {
        let store = try LocalStore.inMemory()
        let model = make(store)
        await model.start(title: "A")
        await model.start(title: "B")
        XCTAssertNotNil(model.writeError)
        XCTAssertEqual(model.running?.title, "A")
        let stored1 = try await allBlocks(store)
        XCTAssertEqual(stored1.count, 1)
        model.dismissError()
        XCTAssertNil(model.writeError)
    }

    func testFailedStartKeepsTheDraftTitleAndSuccessClearsIt() async throws {
        let store = try LocalStore.inMemory()
        let model = make(store)
        model.draftTitle = "First"
        await model.startFromDraft()
        XCTAssertEqual(model.draftTitle, "")
        XCTAssertTrue(model.isRunning)

        model.draftTitle = "Second"
        await model.startFromDraft()
        XCTAssertNotNil(model.writeError, "same-millisecond restart fails")
        XCTAssertEqual(model.draftTitle, "Second")
    }

    func testModelFollowsChangesMadeElsewhere() async throws {
        let store = try LocalStore.inMemory()
        let model = make(store)
        let observing = Task { await model.observeChanges() }
        defer { observing.cancel() }

        _ = try await store.startTimer(seed: TimerSeed(title: "Elsewhere", projectId: nil, tagIds: []), now: SampleData.date(8, 11))
        try await waitUntil { model.running?.title == "Elsewhere" }
        XCTAssertEqual(model.elapsed, 3600)

        _ = try await store.stopTimer(now: SampleData.date(8, 11, 30))
        try await waitUntil { !model.isRunning }
        XCTAssertEqual(model.lastEnded?.title, "Elsewhere")
        XCTAssertEqual(model.todayTotal, 30 * 60)
    }

    func testTickerAdvancesWhileRunningStopsAfterStopAndRestartsFromTheStore() async throws {
        let store = try LocalStore.inMemory()
        let model = TimerModel(store: store, clock: Date.init, calendar: calendar, tickInterval: .milliseconds(20))
        let observing = Task { await model.observeChanges() }
        defer { observing.cancel() }

        await model.start(title: "A")
        let first = model.now
        try await waitUntil { model.now > first }

        await model.stop()
        try await Task.sleep(for: .milliseconds(120))
        let frozen = model.now
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(model.now, frozen)

        _ = try await store.startTimer(seed: nil, now: Date())
        try await waitUntil { model.isRunning }
        let restarted = model.now
        try await waitUntil { model.now > restarted }
    }

    func testWeekTotalCountsASundayInTheWeekThatStartsOnSunday() async throws {
        var sundayFirst = calendar
        sundayFirst.firstWeekday = 1
        let store = try LocalStore.inMemory()
        try await store.save(TimeBlock(title: "Sunday", startAt: SampleData.date(4, 10), endAt: SampleData.date(4, 12)))
        try await store.save(TimeBlock(title: "Previous Saturday", startAt: SampleData.date(3, 10), endAt: SampleData.date(3, 11)))
        at(15, 0, day: 8)
        let time = time
        let sunday = TimerModel(store: store, clock: { time.withLock { $0 } }, calendar: sundayFirst)
        await sunday.refresh()
        XCTAssertEqual(sunday.weekTotal, 2 * 3600)

        let monday = make(store)
        await monday.refresh()
        XCTAssertEqual(monday.weekTotal, 0)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("condition not met in time")
    }
}
