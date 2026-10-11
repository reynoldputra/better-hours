import BetterHoursCore
import XCTest
@testable import Better_Hours

@MainActor
final class ChangeCounter {
    private(set) var count = 0
    private var task: Task<Void, Never>?

    init(_ store: LocalStore) {
        let stream = store.changes()
        task = Task { @MainActor [weak self] in
            for await _ in stream { self?.count += 1 }
        }
    }

    func settled() async -> Int {
        try? await Task.sleep(for: .milliseconds(150))
        return count
    }

    deinit { task?.cancel() }
}

@MainActor
final class CalendarEditingTests: XCTestCase {
    private var store: LocalStore!
    private var model: CalendarModel!
    private var counter: ChangeCounter!

    override func setUp() async throws {
        store = try await SampleData.seeded()
        model = CalendarModel(store: store, clock: { SampleData.now }, calendar: SampleData.calendar)
        await model.reload()
        counter = ChangeCounter(store)
    }

    private func id(_ title: String) throws -> UUID {
        try XCTUnwrap(model.blocks.first { $0.title == title }?.id)
    }

    private func block(_ title: String) throws -> TimeBlock {
        try XCTUnwrap(model.blocks.first { $0.title == title })
    }

    private func d(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date { SampleData.date(day, hour, minute) }

    // MARK: Create

    func testCreateSnapsAndOpensEditor() async throws {
        let before = model.blocks.count
        model.beginCreate(at: d(6, 14, 3))
        XCTAssertEqual(model.drag?.start, d(6, 14, 5))
        model.updateDrag(to: d(6, 15, 58))
        XCTAssertEqual(model.drag?.end, d(6, 16))
        await model.commitDrag()
        XCTAssertEqual(model.blocks.count, before + 1)
        let created = try XCTUnwrap(model.blocks.first { $0.title.isEmpty })
        XCTAssertEqual(created.startAt, d(6, 14, 5))
        XCTAssertEqual(created.endAt, d(6, 16))
        XCTAssertEqual(model.selectedBlockId, created.id)
        XCTAssertEqual(model.editing?.id, created.id)
        XCTAssertNil(model.drag)
        let events = await counter.settled()
        XCTAssertEqual(events, 1)
    }

    func testCancellingEditorKeepsCreatedBlock() async throws {
        model.beginCreate(at: d(6, 14))
        model.updateDrag(to: d(6, 15))
        await model.commitDrag()
        model.cancelEditor()
        XCTAssertNil(model.editing)
        XCTAssertTrue(model.blocks.contains { $0.startAt == d(6, 14) && $0.endAt == d(6, 15) })
    }

    func testPlainClickCreatesNothingAndClearsSelection() async throws {
        model.select(try id("Docs"))
        let before = model.blocks
        model.beginCreate(at: d(6, 14, 3))
        XCTAssertNil(model.selectedBlockId)
        await model.commitDrag()
        XCTAssertEqual(model.blocks, before)
        XCTAssertNil(model.editing)
        let events = await counter.settled()
        XCTAssertEqual(events, 0)
    }

    func testTooShortCreateDragCreatesNothing() async throws {
        let before = model.blocks.count
        model.beginCreate(at: d(6, 14, 3))
        model.updateDrag(to: d(6, 14, 7))
        await model.commitDrag()
        XCTAssertEqual(model.blocks.count, before)
        let events = await counter.settled()
        XCTAssertEqual(events, 0)
    }

    func testCreateExactMinimumIsAllowed() async throws {
        model.beginCreate(at: d(6, 14, 0))
        model.updateDrag(to: d(6, 14, 5))
        await model.commitDrag()
        XCTAssertTrue(model.blocks.contains { $0.startAt == d(6, 14) && $0.endAt == d(6, 14, 5) })
    }

    func testCreateUpwardAndClampedToItsDay() async throws {
        model.beginCreate(at: d(6, 14))
        model.updateDrag(to: d(6, 13, 31))
        XCTAssertEqual(model.drag?.start, d(6, 13, 30))
        XCTAssertEqual(model.drag?.end, d(6, 14))
        model.updateDrag(to: d(7, 3))
        XCTAssertEqual(model.drag?.start, d(6, 14))
        XCTAssertEqual(model.drag?.end, d(7, 0))
    }

    // MARK: Move

    func testMoveWithinDayKeepsDurationAndGrabOffset() async throws {
        let review = try block("Design review")
        model.beginMove(id: review.id, pointerTime: d(5, 9, 20))
        XCTAssertEqual(model.selectedBlockId, review.id)
        model.updateDrag(to: d(5, 11, 33))
        XCTAssertEqual(model.drag?.start, d(5, 11, 15))
        XCTAssertEqual(model.drag?.end, d(5, 12, 45))
        model.updateDrag(to: d(5, 11, 34))
        await model.commitDrag()
        let moved = try block("Design review")
        XCTAssertEqual(moved.startAt, d(5, 11, 15))
        XCTAssertEqual(moved.endAt, d(5, 12, 45))
        let events = await counter.settled()
        XCTAssertEqual(events, 1)
    }

    func testMoveToAnotherDay() async throws {
        let review = try block("Design review")
        model.beginMove(id: review.id, pointerTime: d(5, 9, 0))
        model.updateDrag(to: d(7, 9, 0))
        model.updateDrag(to: d(9, 8, 0))
        await model.commitDrag()
        let moved = try block("Design review")
        XCTAssertEqual(moved.startAt, d(9, 8))
        XCTAssertEqual(moved.endAt, d(9, 9, 30))
    }

    func testMovingMidnightPieceMovesWholeBlock() async throws {
        let late = TimeBlock(title: "Late", startAt: d(6, 22), endAt: d(7, 2))
        try await store.save(late)
        await model.reload()
        model.beginMove(id: late.id, pointerTime: d(7, 1))
        model.updateDrag(to: d(8, 1))
        await model.commitDrag()
        let moved = try block("Late")
        XCTAssertEqual(moved.startAt, d(7, 22))
        XCTAssertEqual(moved.endAt, d(8, 2))
    }

    func testUnchangedMoveWritesNothing() async throws {
        let review = try block("Design review")
        model.beginMove(id: review.id, pointerTime: d(5, 9, 20))
        model.updateDrag(to: d(5, 11))
        model.updateDrag(to: d(5, 9, 21))
        await model.commitDrag()
        let events = await counter.settled()
        XCTAssertEqual(events, 0)
    }

    func testCancelledDragWritesNothing() async throws {
        let review = try block("Design review")
        model.beginMove(id: review.id, pointerTime: d(5, 9))
        model.updateDrag(to: d(5, 14))
        model.escape()
        XCTAssertNil(model.drag)
        await model.commitDrag()
        XCTAssertEqual(try block("Design review"), review)
        let events = await counter.settled()
        XCTAssertEqual(events, 0)
        XCTAssertEqual(model.selectedBlockId, review.id)
        model.escape()
        XCTAssertNil(model.selectedBlockId)
    }

    // MARK: Resize

    func testResizeEndAndStart() async throws {
        let review = try block("Design review")
        model.beginResize(id: review.id, edge: .end)
        model.updateDrag(to: d(5, 12, 2))
        XCTAssertEqual(model.drag?.end, d(5, 12))
        await model.commitDrag()
        XCTAssertEqual(try block("Design review").endAt, d(5, 12))
        XCTAssertEqual(try block("Design review").startAt, d(5, 9))

        model.beginResize(id: review.id, edge: .start)
        model.updateDrag(to: d(5, 8, 22))
        await model.commitDrag()
        XCTAssertEqual(try block("Design review").startAt, d(5, 8, 20))
        XCTAssertEqual(try block("Design review").endAt, d(5, 12))
    }

    func testResizeClampsToMinimumLength() async throws {
        let review = try block("Design review")
        model.beginResize(id: review.id, edge: .end)
        model.updateDrag(to: d(5, 8))
        XCTAssertEqual(model.drag?.end, d(5, 9, 5))
        model.cancelDrag()
        model.beginResize(id: review.id, edge: .start)
        model.updateDrag(to: d(5, 12))
        XCTAssertEqual(model.drag?.start, d(5, 10, 25))
    }

    // MARK: Running block

    func testRunningBlockCannotResizeEnd() throws {
        model.beginResize(id: try id("Build editor"), edge: .end)
        XCTAssertNil(model.drag)
    }

    func testRunningBlockMovesByStartAndStaysRunning() async throws {
        let running = try block("Build editor")
        model.beginMove(id: running.id, pointerTime: d(8, 11, 10))
        model.updateDrag(to: d(8, 11, 40))
        XCTAssertEqual(model.drag?.start, d(8, 11, 30))
        XCTAssertEqual(model.drag?.end, SampleData.now)
        await model.commitDrag()
        let moved = try block("Build editor")
        XCTAssertEqual(moved.startAt, d(8, 11, 30))
        XCTAssertNil(moved.endAt)
    }

    func testRunningStartCannotReachNow() async throws {
        let running = try block("Build editor")
        model.beginMove(id: running.id, pointerTime: d(8, 11))
        model.updateDrag(to: d(8, 15))
        XCTAssertEqual(model.drag?.start, d(8, 12, 15))
        model.cancelDrag()
        model.beginResize(id: running.id, edge: .start)
        model.updateDrag(to: d(8, 12, 24))
        XCTAssertEqual(model.drag?.start, d(8, 12, 15))
    }

    // MARK: Editor

    func testEditorSaveWritesOnce() async throws {
        let review = try block("Design review")
        model.openEditor(id: review.id)
        XCTAssertEqual(model.editing?.title, "Design review")
        model.editing?.title = "  Review v2 "
        model.editing?.notes = "walkthrough"
        model.editing?.endAt = d(5, 11)
        await model.saveEditor()
        XCTAssertNil(model.editing)
        let saved = try block("Review v2")
        XCTAssertEqual(saved.notes, "walkthrough")
        XCTAssertEqual(saved.endAt, d(5, 11))
        XCTAssertEqual(saved.startAt, d(5, 9))
        let events = await counter.settled()
        XCTAssertEqual(events, 1)
    }

    func testEditorCancelDiscards() async throws {
        let review = try block("Design review")
        model.openEditor(id: review.id)
        model.editing?.title = "Changed"
        model.cancelEditor()
        XCTAssertEqual(try block("Design review"), review)
        let events = await counter.settled()
        XCTAssertEqual(events, 0)
    }

    func testEditorValidationBlocksSave() async throws {
        let review = try block("Design review")
        model.openEditor(id: review.id)
        XCTAssertNil(model.editing?.validationError(now: SampleData.now))
        model.editing?.endAt = d(5, 9)
        XCTAssertEqual(model.editing?.validationError(now: SampleData.now), "End must be after start")
        model.editing?.endAt = d(5, 8)
        XCTAssertEqual(model.editing?.validationError(now: SampleData.now), "End must be after start")
        await model.saveEditor()
        XCTAssertNotNil(model.editing)
        XCTAssertEqual(try block("Design review"), review)
        model.editing?.endAt = d(5, 9, 1)
        XCTAssertNil(model.editing?.validationError(now: SampleData.now))
    }

    func testEditorKeepsSecondsWhenTimesUntouched() async throws {
        let odd = TimeBlock(title: "Odd", startAt: d(6, 8).addingTimeInterval(23), endAt: d(6, 9).addingTimeInterval(41))
        try await store.save(odd)
        await model.reload()
        model.openEditor(id: odd.id)
        model.editing?.title = "Odd 2"
        await model.saveEditor()
        let saved = try block("Odd 2")
        XCTAssertEqual(saved.startAt, odd.startAt)
        XCTAssertEqual(saved.endAt, odd.endAt)
    }

    func testRunningEditorHasNoEndAndValidatesStart() async throws {
        let running = try block("Build editor")
        model.openEditor(id: running.id)
        XCTAssertNil(model.editing?.endAt)
        XCTAssertTrue(model.editing?.isRunning == true)
        model.editing?.startAt = d(8, 12, 24)
        XCTAssertEqual(model.editing?.validationError(now: SampleData.now), "Start must be before now")
        model.editing?.startAt = d(8, 10)
        await model.saveEditor()
        let saved = try block("Build editor")
        XCTAssertEqual(saved.startAt, d(8, 10))
        XCTAssertNil(saved.endAt)
    }

    func testSaveKeepsFieldsChangedElsewhere() async throws {
        let docs = try block("Docs")
        model.openEditor(id: docs.id)
        var renamed = docs
        renamed.title = "Docs v2"
        try await store.save(renamed)
        await model.reload()
        model.editing?.notes = "n"
        await model.saveEditor()
        let saved = try block("Docs v2")
        XCTAssertEqual(saved.notes, "n")
        XCTAssertEqual(saved.startAt, docs.startAt)
    }

    func testFailedSaveKeepsEditorOpen() async throws {
        let docs = try block("Docs")
        model.openEditor(id: docs.id)
        var shortened = docs
        shortened.endAt = d(6, 14)
        try await store.save(shortened)
        await model.reload()
        model.editing?.startAt = d(6, 14, 30)
        await model.saveEditor()
        XCTAssertNotNil(model.editing)
        XCTAssertNotNil(model.writeError)
        XCTAssertEqual(model.editing?.startAt, d(6, 14, 30))
    }

    func testSaveForDeletedBlockClosesEditorWithoutWrite() async throws {
        let docs = try id("Docs")
        model.openEditor(id: docs)
        try await store.deleteBlock(id: docs)
        let before = await counter.settled()
        let draft = model.editing
        await model.reload()
        model.editing = draft
        await model.saveEditor()
        XCTAssertNil(model.editing)
        let after = await counter.settled()
        XCTAssertEqual(before, after)
    }

    func testDragCommitIgnoresBlockChangedMidDrag() async throws {
        let running = try block("Build editor")
        model.beginMove(id: running.id, pointerTime: d(8, 11))
        model.updateDrag(to: d(8, 11, 30))
        _ = try await store.stopTimer(now: SampleData.now)
        await model.reload()
        await model.commitDrag()
        let after = try block("Build editor")
        XCTAssertEqual(after.startAt, running.startAt)
        XCTAssertNotNil(after.endAt)
    }

    func testBlockDeletedMidDragCancelsDrag() async throws {
        let docs = try id("Docs")
        model.beginMove(id: docs, pointerTime: d(6, 14))
        try await store.deleteBlock(id: docs)
        await model.reload()
        XCTAssertNil(model.drag)
        await model.commitDrag()
        XCTAssertFalse(model.blocks.contains { $0.id == docs })
    }

    func testReloadClearsStateForRemovedBlock() async throws {
        let docs = try id("Docs")
        model.openEditor(id: docs)
        model.pendingDeleteId = docs
        try await store.deleteBlock(id: docs)
        await model.reload()
        XCTAssertNil(model.selectedBlockId)
        XCTAssertNil(model.editing)
        XCTAssertNil(model.pendingDeleteId)
    }

    // MARK: Delete

    func testDeleteRemovesBlockAndSelection() async throws {
        let docs = try id("Docs")
        model.select(docs)
        await model.deleteBlock(id: docs)
        XCTAssertFalse(model.blocks.contains { $0.id == docs })
        XCTAssertNil(model.selectedBlockId)
        let events = await counter.settled()
        XCTAssertEqual(events, 1)
    }

    // MARK: Library

    func testCreateProjectPicksFirstUnusedColour() async throws {
        let library = LibraryModel(store: try LocalStore.inMemory(), clock: { SampleData.now }, calendar: SampleData.calendar)
        let first = try await library.createProject(name: " Alpha ")
        XCTAssertEqual(first.name, "Alpha")
        XCTAssertEqual(first.color, .blue)
        let second = try await library.createProject(name: "B")
        XCTAssertEqual(second.color, .orange)

        let seeded = LibraryModel(store: store, clock: { SampleData.now }, calendar: SampleData.calendar)
        let extra = try await seeded.createProject(name: "New")
        XCTAssertEqual(extra.color, .yellow)
    }

    func testCreateProjectWrapsAroundWhenPaletteIsUsed() async throws {
        let library = LibraryModel(store: try LocalStore.inMemory(), clock: { SampleData.now }, calendar: SampleData.calendar)
        for index in 0..<8 { _ = try await library.createProject(name: "P\(index)") }
        let ninth = try await library.createProject(name: "P8")
        XCTAssertEqual(ninth.color, .blue)
    }

    func testCreateTagDeduplicates() async throws {
        let library = LibraryModel(store: try LocalStore.inMemory(), clock: { SampleData.now }, calendar: SampleData.calendar)
        let first = try await library.createTag(name: "Client")
        let second = try await library.createTag(name: "  client ")
        XCTAssertEqual(first, second)
        XCTAssertEqual(library.tags.count, 1)
        let other = try await library.createTag(name: "ux")
        XCTAssertNotEqual(other.id, first.id)
        XCTAssertEqual(library.tags.count, 2)
    }

    func testEmptyNamesAreRejected() async throws {
        let library = LibraryModel(store: try LocalStore.inMemory(), clock: { SampleData.now }, calendar: SampleData.calendar)
        do {
            _ = try await library.createProject(name: "  ")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? LibraryError, .emptyName)
        }
    }

    // MARK: Geometry

    func testHitTestingZonesAndGutter() async throws {
        let geometry = GridGeometry(columns: model.columns, width: Metrics.gutterWidth + 7 * 100)
        let review = try block("Design review")
        let top = 9 * Metrics.hourHeight + 1
        XCTAssertEqual(geometry.hit(at: CGPoint(x: 10, y: top + 10)), .gutter)
        XCTAssertEqual(geometry.hit(at: CGPoint(x: Metrics.gutterWidth + 50, y: top + 30)), .block(id: review.id, zone: .body))
        XCTAssertEqual(geometry.hit(at: CGPoint(x: Metrics.gutterWidth + 50, y: top + 2)), .block(id: review.id, zone: .topEdge))
        let bottom = 10.5 * Metrics.hourHeight - 1
        XCTAssertEqual(geometry.hit(at: CGPoint(x: Metrics.gutterWidth + 50, y: bottom - 2)), .block(id: review.id, zone: .bottomEdge))
        XCTAssertEqual(geometry.hit(at: CGPoint(x: Metrics.gutterWidth + 450, y: top + 30)), .empty)
    }

    func testRunningBlockHasNoBottomEdge() async throws {
        let geometry = GridGeometry(columns: model.columns, width: Metrics.gutterWidth + 7 * 100)
        let running = try block("Build editor")
        let x = Metrics.gutterWidth + 350
        let bottom = GridGeometry.y(SampleData.now, from: d(8, 0)) - 2
        XCTAssertEqual(geometry.hit(at: CGPoint(x: x, y: bottom)), .block(id: running.id, zone: .body))
        XCTAssertEqual(geometry.hit(at: CGPoint(x: x, y: 11 * Metrics.hourHeight + 2)), .block(id: running.id, zone: .topEdge))
    }

    func testPointerTimeMapsDayAndClamps() throws {
        let geometry = GridGeometry(columns: model.columns, width: Metrics.gutterWidth + 700)
        XCTAssertEqual(geometry.time(at: CGPoint(x: Metrics.gutterWidth + 150, y: 10.5 * Metrics.hourHeight)), d(6, 10, 30))
        XCTAssertEqual(geometry.time(at: CGPoint(x: 5000, y: -20)), d(11, 0))
        XCTAssertEqual(geometry.time(at: CGPoint(x: 0, y: 99_999)), d(6, 0))
    }
}
