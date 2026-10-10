import Foundation
import GRDB
import os
import Testing
@testable import BetterHoursCore

private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
private func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

struct LocalStoreTests {
    @Test func blockRoundTrip() async throws {
        let store = try LocalStore.inMemory()
        let project = UUIDv7.generate(), tagA = UUIDv7.generate(), tagB = UUIDv7.generate()
        let block = TimeBlock(title: "Write", notes: "n", projectId: project, tagIds: [tagA, tagB], startAt: at(0), endAt: at(30))
        try await store.save(block)
        let loaded = try await store.blocks(in: DateInterval(start: at(-60), end: at(60)))
        #expect(loaded == [block])
    }

    @Test func updateReplacesFields() async throws {
        let store = try LocalStore.inMemory()
        var block = TimeBlock(title: "A", startAt: at(0), endAt: at(30))
        try await store.save(block)
        block.title = "B"
        block.endAt = at(45)
        try await store.save(block)
        let loaded = try await store.blocks(in: DateInterval(start: at(-60), end: at(60)))
        #expect(loaded == [block])
    }

    @Test func softDeleteHidesFromAllReads() async throws {
        let store = try LocalStore.inMemory()
        let ended = TimeBlock(startAt: at(0), endAt: at(30))
        try await store.save(ended)
        try await store.deleteBlock(id: ended.id)
        #expect(try await store.blocks(in: DateInterval(start: at(-60), end: at(60))).isEmpty)
        #expect(try await store.lastEndedBlock() == nil)

        let running = try await store.startTimer(seed: nil, now: at(40))
        try await store.deleteBlock(id: running.id)
        #expect(try await store.runningBlock() == nil)
    }

    @Test func softDeleteKeepsRowAndMarksDirty() async throws {
        let store = try LocalStore.inMemory()
        let block = TimeBlock(startAt: at(0), endAt: at(30))
        try await store.save(block)
        try await store.deleteBlock(id: block.id)
        let row = try await rawRow(store, "time_block", block.id)
        #expect(row != nil)
        #expect(row?["deleted_at"] as Int64? != nil)
        #expect(row?["dirty"] as Int64? == 1)
    }

    @Test func saveDoesNotUndelete() async throws {
        let store = try LocalStore.inMemory()
        let block = TimeBlock(title: "x", startAt: at(0), endAt: at(30))
        try await store.save(block)
        try await store.deleteBlock(id: block.id)
        try await store.save(block)
        #expect(try await store.blocks(in: DateInterval(start: at(-60), end: at(60))).isEmpty)
    }

    @Test func saveDoesNotUndeleteProjectsOrTags() async throws {
        let store = try LocalStore.inMemory()
        let project = Project(name: "P", color: .blue)
        let tag = Tag(name: "T")
        try await store.save(project)
        try await store.save(tag)
        try await store.deleteProject(id: project.id)
        try await store.deleteTag(id: tag.id)
        try await store.save(project)
        try await store.save(tag)
        #expect(try await store.projects().isEmpty)
        #expect(try await store.tags().isEmpty)
        #expect(try await rawRow(store, "project", project.id)?["deleted_at"] as Int64? != nil)
        #expect(try await rawRow(store, "tag", tag.id)?["deleted_at"] as Int64? != nil)
    }

    @Test func startTimerReturnsStoredMillisecondPrecision() async throws {
        let store = try LocalStore.inMemory()
        let started = try await store.startTimer(seed: nil, now: Date(timeIntervalSince1970: 1_790_000_000.0001))
        #expect(try await store.runningBlock() == started)
    }

    @Test func rangeQueryHandlesStraddlingAndEdges() async throws {
        let store = try LocalStore.inMemory()
        let before = TimeBlock(startAt: at(-30), endAt: at(0))
        let straddleStart = TimeBlock(startAt: at(-30), endAt: at(10))
        let inside = TimeBlock(startAt: at(20), endAt: at(30))
        let straddleEnd = TimeBlock(startAt: at(50), endAt: at(90))
        let after = TimeBlock(startAt: at(60), endAt: at(90))
        let running = TimeBlock(startAt: at(55), endAt: nil)
        for b in [before, straddleStart, inside, straddleEnd, after, running] { try await store.save(b) }
        let loaded = try await store.blocks(in: DateInterval(start: at(0), end: at(60)))
        #expect(loaded.map(\.id) == [straddleStart, inside, straddleEnd, running].map(\.id))
    }

    @Test func runningBlockOverlapsLaterRange() async throws {
        let store = try LocalStore.inMemory()
        let running = try await store.startTimer(seed: nil, now: at(0))
        let loaded = try await store.blocks(in: DateInterval(start: at(600), end: at(700)))
        #expect(loaded.map(\.id) == [running.id])
    }

    @Test func writesSetUpdatedAtAndDirty() async throws {
        let store = try LocalStore.inMemory()
        let block = TimeBlock(startAt: at(0), endAt: at(30))
        let project = Project(name: "P", color: .teal)
        let tag = Tag(name: "T")
        try await store.save(block)
        try await store.save(project)
        try await store.save(tag)

        let old: Int64 = 1000
        let saves: [(String, UUID, @Sendable () async throws -> Void)] = [
            ("time_block", block.id, { try await store.save(block) }),
            ("project", project.id, { try await store.save(project) }),
            ("tag", tag.id, { try await store.save(tag) }),
        ]
        let deletes: [(String, UUID, @Sendable () async throws -> Void)] = [
            ("time_block", block.id, { try await store.deleteBlock(id: block.id) }),
            ("project", project.id, { try await store.deleteProject(id: project.id) }),
            ("tag", tag.id, { try await store.deleteTag(id: tag.id) }),
        ]
        for (label, cases) in [("save", saves), ("delete", deletes)] {
            for (table, id, action) in cases {
                try await resetSyncColumns(store, table, updatedAt: old)
                try await action()
                let row = try #require(await rawRow(store, table, id))
                #expect(row["dirty"] as Int64? == 1, "\(table) \(label)")
                #expect((row["updated_at"] as Int64? ?? 0) > old, "\(table) \(label) updated_at")
                if label == "delete" {
                    #expect(row["deleted_at"] as Int64? != nil, "\(table) delete")
                }
            }
        }
    }

    @Test func timerWritesSetDirty() async throws {
        let store = try LocalStore.inMemory()
        let first = try await store.startTimer(seed: nil, now: at(0))
        try await clearDirty(store, "time_block")
        _ = try await store.stopTimer(now: at(10))
        #expect(try await rawRow(store, "time_block", first.id)?["dirty"] as Int64? == 1)
        try await clearDirty(store, "time_block")
        let second = try await store.startTimer(seed: nil, now: at(20))
        #expect(try await rawRow(store, "time_block", second.id)?["dirty"] as Int64? == 1)
    }

    @Test func startAndStop() async throws {
        let store = try LocalStore.inMemory()
        let seed = TimerSeed(title: "Focus", projectId: UUIDv7.generate(), tagIds: [UUIDv7.generate()])
        let started = try await store.startTimer(seed: seed, now: at(0))
        #expect(started.startAt == at(0))
        #expect(started.endAt == nil)
        #expect(started.title == "Focus")
        #expect(started.projectId == seed.projectId)
        #expect(started.tagIds == seed.tagIds)
        #expect(try await store.runningBlock() == started)

        let stopped = try #require(await store.stopTimer(now: at(25)))
        #expect(stopped.id == started.id)
        #expect(stopped.endAt == at(25))
        #expect(try await store.runningBlock() == nil)
        #expect(try await store.lastEndedBlock() == stopped)
    }

    @Test func startWithoutSeedIsBlank() async throws {
        let store = try LocalStore.inMemory()
        let block = try await store.startTimer(seed: nil, now: at(0))
        #expect(block.title == "" && block.notes == "" && block.projectId == nil && block.tagIds.isEmpty)
    }

    @Test func stopWithNothingRunningReturnsNil() async throws {
        let store = try LocalStore.inMemory()
        #expect(try await store.stopTimer(now: at(0)) == nil)
    }

    @Test func startWhileRunningEndsPreviousAtNow() async throws {
        let store = try LocalStore.inMemory()
        let first = try await store.startTimer(seed: nil, now: at(0))
        let second = try await store.startTimer(seed: TimerSeed(title: "Next"), now: at(15))
        #expect(try await store.runningBlock()?.id == second.id)
        let ended = try #require(await store.lastEndedBlock())
        #expect(ended.id == first.id)
        #expect(ended.endAt == at(15))
    }

    @Test func failedStartRollsBackTheStop() async throws {
        let store = try LocalStore.inMemory()
        let first = try await store.startTimer(seed: nil, now: at(10))
        await #expect(throws: (any Error).self) { _ = try await store.startTimer(seed: nil, now: at(10)) }
        #expect(try await store.runningBlock()?.id == first.id)
    }

    @Test func lastEndedBlockPicksLatestEnd() async throws {
        let store = try LocalStore.inMemory()
        #expect(try await store.lastEndedBlock() == nil)
        let early = TimeBlock(startAt: at(0), endAt: at(100))
        let late = TimeBlock(startAt: at(10), endAt: at(120))
        let earlier = TimeBlock(startAt: at(50), endAt: at(60))
        for b in [late, early, earlier] { try await store.save(b) }
        #expect(try await store.lastEndedBlock()?.id == late.id)
    }

    @Test func projectsAndTags() async throws {
        let store = try LocalStore.inMemory()
        var project = Project(name: "Alpha", color: .blue)
        let other = Project(name: "Beta", color: .gray)
        try await store.save(project)
        try await store.save(other)
        project.name = "Alpha2"
        project.color = .red
        try await store.save(project)
        #expect(try await store.projects() == [project, other])
        try await store.deleteProject(id: other.id)
        #expect(try await store.projects() == [project])

        var tag = Tag(name: "x")
        try await store.save(tag)
        tag.name = "y"
        try await store.save(tag)
        #expect(try await store.tags() == [tag])
        try await store.deleteTag(id: tag.id)
        #expect(try await store.tags().isEmpty)
    }

    @Test func storedFormat() async throws {
        let store = try LocalStore.inMemory()
        let tag = UUIDv7.generate()
        let block = TimeBlock(projectId: UUIDv7.generate(), tagIds: [tag], startAt: Date(timeIntervalSince1970: 1_790_000_000.123), endAt: nil)
        try await store.save(block)
        let row = try #require(await rawRow(store, "time_block", block.id))
        #expect(row["id"] as String? == block.id.uuidString.lowercased())
        #expect(row["start_at"] as Int64? == 1_790_000_000_123)
        #expect(row["tag_ids"] as String? == "[\"\(tag.uuidString.lowercased())\"]")
        #expect(row["project_id"] as String? == block.projectId?.uuidString.lowercased())
    }

    @Test func fileBackedStorePersistsAndCreatesDirectories() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bh-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("nested/betterhours.sqlite")
        let block = TimeBlock(title: "kept", startAt: at(0), endAt: at(5))
        do {
            let store = try LocalStore(path: path)
            try await store.save(block)
        }
        let reopened = try LocalStore(path: path)
        #expect(try await reopened.blocks(in: DateInterval(start: at(-1), end: at(10))) == [block])
    }

    // MARK: Database rules

    @Test func secondRunningBlockIsRejected() async throws {
        let store = try LocalStore.inMemory()
        _ = try await store.startTimer(seed: nil, now: at(0))
        await #expect(throws: (any Error).self) {
            try await store.save(TimeBlock(startAt: at(5), endAt: nil))
        }
    }

    @Test func runningIndexIgnoresDeletedRunningBlock() async throws {
        let store = try LocalStore.inMemory()
        let first = try await store.startTimer(seed: nil, now: at(0))
        try await store.deleteBlock(id: first.id)
        try await store.save(TimeBlock(startAt: at(5), endAt: nil))
        #expect(try await store.runningBlock() != nil)
    }

    @Test func endNotAfterStartIsRejected() async throws {
        let store = try LocalStore.inMemory()
        await #expect(throws: (any Error).self) {
            try await store.save(TimeBlock(startAt: at(5), endAt: at(5)))
        }
        await #expect(throws: (any Error).self) {
            try await store.save(TimeBlock(startAt: at(5), endAt: at(1)))
        }
        #expect(try await store.blocks(in: DateInterval(start: at(-60), end: at(60))).isEmpty)
    }

    // MARK: changes()

    @Test func changesFiresOncePerWriteForEverySubscriber() async throws {
        let store = try LocalStore.inMemory()
        let block = TimeBlock(startAt: at(0), endAt: at(5))
        let project = Project(name: "P", color: .blue)
        let tag = Tag(name: "T")
        let writes: [(String, @Sendable () async throws -> Void)] = [
            ("saveBlock", { try await store.save(block) }),
            ("saveProject", { try await store.save(project) }),
            ("saveTag", { try await store.save(tag) }),
            ("deleteBlock", { try await store.deleteBlock(id: block.id) }),
            ("deleteProject", { try await store.deleteProject(id: project.id) }),
            ("deleteTag", { try await store.deleteTag(id: tag.id) }),
            ("startTimer", { _ = try await store.startTimer(seed: nil, now: at(10)) }),
            ("stopTimer", { _ = try await store.stopTimer(now: at(11)) }),
        ]
        let streams = [store.changes(), store.changes()]
        var iterators = streams.map { $0.makeAsyncIterator() }
        for (name, write) in writes {
            try await write()
            for i in iterators.indices {
                #expect(await iterators[i].next() != nil, "\(name) subscriber \(i)")
            }
        }
        let extra = Flag()
        let waiter = Task { _ = await iterators[0].next(); extra.set() }
        try await Task.sleep(for: .milliseconds(100))
        #expect(!extra.value, "extra event beyond one per write")
        waiter.cancel()
    }

    @Test func changesDoesNotFireForNoOpWrites() async throws {
        let store = try LocalStore.inMemory()
        let tag = Tag(name: "T")
        try await store.save(tag)
        try await store.deleteTag(id: tag.id)
        let stream = store.changes()
        _ = try await store.stopTimer(now: at(0))
        try await store.deleteBlock(id: UUIDv7.generate())
        try await store.deleteProject(id: UUIDv7.generate())
        try await store.deleteTag(id: tag.id)
        try await store.save(Tag(name: "marker"))
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()
        let extra = Flag()
        let waiter = Task { _ = await iterator.next(); extra.set() }
        try await Task.sleep(for: .milliseconds(100))
        #expect(!extra.value)
        waiter.cancel()
    }

    @Test func changesDoesNotFireForFailedWrite() async throws {
        let store = try LocalStore.inMemory()
        let stream = store.changes()
        await #expect(throws: (any Error).self) {
            try await store.save(TimeBlock(startAt: at(5), endAt: at(5)))
        }
        try await store.save(Tag(name: "ok"))
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()
        let flag = Flag()
        let waiter = Task { _ = await iterator.next(); flag.set() }
        try await Task.sleep(for: .milliseconds(100))
        #expect(!flag.value)
        waiter.cancel()
    }

    @Test func changesStreamTerminationCleansUp() async throws {
        let store = try LocalStore.inMemory()
        do {
            let stream = store.changes()
            var iterator: AsyncStream<Void>.Iterator? = stream.makeAsyncIterator()
            try await store.save(Tag(name: "1"))
            _ = await iterator?.next()
            iterator = nil
        }
        try await Task.sleep(for: .milliseconds(50))
        try await store.save(Tag(name: "2"))
        let fresh = store.changes()
        try await store.save(Tag(name: "3"))
        var iterator = fresh.makeAsyncIterator()
        #expect(await iterator.next() != nil)
    }

    // MARK: Helpers

    private func rawRow(_ store: LocalStore, _ table: String, _ id: UUID) async throws -> Row? {
        try store.testDB.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM \(table) WHERE id = ?", arguments: [id.uuidString.lowercased()])
        }
    }

    private func resetSyncColumns(_ store: LocalStore, _ table: String, updatedAt: Int64) async throws {
        try await store.testDB.write { db in
            try db.execute(sql: "UPDATE \(table) SET dirty = 0, updated_at = ?", arguments: [updatedAt])
        }
    }

    private func clearDirty(_ store: LocalStore, _ table: String) async throws {
        try await store.testDB.write { db in try db.execute(sql: "UPDATE \(table) SET dirty = 0") }
    }
}

final class Flag: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: false)
    var value: Bool { state.withLock { $0 } }
    func set() { state.withLock { $0 = true } }
}
