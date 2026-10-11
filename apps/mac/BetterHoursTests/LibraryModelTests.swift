import BetterHoursCore
import os
import XCTest
@testable import Better_Hours

@MainActor
final class LibraryModelTests: XCTestCase {
    private var store: LocalStore!
    private var library: LibraryModel!
    private var counter: ChangeCounter!

    override func setUp() async throws {
        store = try await SampleData.seeded()
        library = LibraryModel(store: store, clock: { SampleData.now }, calendar: SampleData.calendar)
        await library.reload()
        counter = ChangeCounter(store)
    }

    private func project(_ name: String) throws -> Project {
        try XCTUnwrap(library.projects.first { $0.name == name })
    }

    private func tag(_ name: String) throws -> Tag {
        try XCTUnwrap(library.tags.first { $0.name == name })
    }


    // MARK: Projects

    func testRenameProjectWritesOnce() async throws {
        let backend = try project("Backend")
        try await library.renameProject(id: backend.id, to: "  Platform ")
        let events = await counter.settled()
        XCTAssertEqual(events, 1)
        XCTAssertEqual(library.projects.first { $0.id == backend.id }?.name, "Platform")
        let stored = try await store.projects()
        XCTAssertEqual(stored.first { $0.id == backend.id }?.name, "Platform")
    }

    func testRenameProjectToSameNameOrEmptyWritesNothing() async throws {
        let backend = try project("Backend")
        try await library.renameProject(id: backend.id, to: " Backend ")
        do {
            try await library.renameProject(id: backend.id, to: "   ")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? LibraryError, .emptyName)
        }
        do {
            try await library.renameProject(id: UUID(), to: "Ghost")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? LibraryError, .notFound)
        }
        let events = await counter.settled()
        XCTAssertEqual(events, 0)
        XCTAssertEqual(try project("Backend").name, "Backend")
    }

    func testSetProjectColourWritesOnceAndSkipsUnchanged() async throws {
        let backend = try project("Backend")
        try await library.setProjectColor(id: backend.id, backend.color)
        var events = await counter.settled()
        XCTAssertEqual(events, 0)
        try await library.setProjectColor(id: backend.id, .red)
        events = await counter.settled()
        XCTAssertEqual(events, 1)
        XCTAssertEqual(try project("Backend").color, .red)
    }

    func testDeleteProjectWritesOnceAndHidesIt() async throws {
        let admin = try project("Admin")
        try await library.deleteProject(id: admin.id)
        let events = await counter.settled()
        XCTAssertEqual(events, 1)
        XCTAssertNil(library.projects.first { $0.id == admin.id })
    }

    // MARK: Tags

    func testRenameTagWritesOnce() async throws {
        let ux = try tag("ux")
        try await library.renameTag(id: ux.id, to: "design")
        let events = await counter.settled()
        XCTAssertEqual(events, 1)
        XCTAssertEqual(try tag("design").id, ux.id)
    }

    func testRenameTagAllowsChangingOnlyTheCase() async throws {
        let ux = try tag("ux")
        try await library.renameTag(id: ux.id, to: "UX")
        let events = await counter.settled()
        XCTAssertEqual(events, 1)
        XCTAssertEqual(try tag("UX").id, ux.id)
    }

    func testRenameTagRejectsEmptyDuplicateAndUnchanged() async throws {
        let ux = try tag("ux")
        try await library.renameTag(id: ux.id, to: "ux")
        do {
            try await library.renameTag(id: ux.id, to: "")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? LibraryError, .emptyName)
        }
        do {
            try await library.renameTag(id: ux.id, to: " CLIENT ")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? LibraryError, .duplicateName)
        }
        let events = await counter.settled()
        XCTAssertEqual(events, 0)
        XCTAssertEqual(library.tags.count, 5)
        XCTAssertEqual(try tag("ux").id, ux.id)
    }

    func testDeleteTagWritesOnce() async throws {
        let review = try tag("review")
        try await library.deleteTag(id: review.id)
        let events = await counter.settled()
        XCTAssertEqual(events, 1)
        XCTAssertNil(library.tags.first { $0.id == review.id })
    }

    // MARK: Week totals

    func testWeekTotalsIncludeTheRunningBlock() throws {
        let hour: TimeInterval = 3600
        XCTAssertEqual(library.weekTotal(of: try project("Website").id), 4.5 * hour)
        XCTAssertEqual(library.weekTotal(of: try project("Writing").id), 1.5 * hour)
        XCTAssertEqual(library.weekTotal(of: try project("Clients").id), 1.5 * hour)
        XCTAssertEqual(library.weekTotal(of: try project("Admin").id), 2 * hour)
        // 2.5h + 1h finished, plus the block running since 11:00 until 12:24.
        XCTAssertEqual(library.weekTotal(of: try project("Backend").id), 4.9 * hour, accuracy: 0.5)
    }

    func testWeekTotalsClipAtTheWeekBoundaries() async throws {
        let empty = try LocalStore.inMemory()
        let project = Project(name: "Edge", color: .blue)
        try await empty.save(project)
        let beforeStart = TimeBlock(projectId: project.id, startAt: SampleData.date(4, 23), endAt: SampleData.date(5, 1))
        let afterEnd = TimeBlock(projectId: project.id, startAt: SampleData.date(11, 23), endAt: SampleData.date(12, 2))
        let outside = TimeBlock(projectId: project.id, startAt: SampleData.date(12, 3), endAt: SampleData.date(12, 4))
        for block in [beforeStart, afterEnd, outside] { try await empty.save(block) }
        let model = LibraryModel(store: empty, clock: { SampleData.now }, calendar: SampleData.calendar)
        await model.reload()
        XCTAssertEqual(model.weekTotal(of: project.id), 2 * 3600)
    }

    func testWeekTotalsFollowTheInjectedClock() async throws {
        let nextWeek = LibraryModel(store: store, clock: { SampleData.date(14, 12) }, calendar: SampleData.calendar)
        await nextWeek.reload()
        XCTAssertEqual(nextWeek.weekTotal(of: try project("Website").id), 0)
    }

    func testRunningBlockGrowsWithTheClock() async throws {
        let box = OSAllocatedUnfairLock(initialState: SampleData.now)
        let model = LibraryModel(store: store, clock: { box.withLock { $0 } }, calendar: SampleData.calendar)
        await model.reload()
        let backend = try project("Backend").id
        let before = model.weekTotal(of: backend)
        box.withLock { $0 = SampleData.now.addingTimeInterval(1800) }
        await model.reload()
        XCTAssertEqual(model.weekTotal(of: backend) - before, 1800, accuracy: 0.5)
    }
}
