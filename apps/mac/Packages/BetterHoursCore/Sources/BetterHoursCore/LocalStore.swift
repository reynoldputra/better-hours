import Foundation
import GRDB
import os

public struct StoreError: Error, Equatable, Sendable {
    public var message: String
}

public final class LocalStore: Sendable {
    private let db: any DatabaseWriter
    var testDB: any DatabaseWriter { db }
    private let subscribers = OSAllocatedUnfairLock(initialState: [UUID: AsyncStream<Void>.Continuation]())

    public init(path: URL) throws {
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        db = try DatabasePool(path: path.path)
        try Migrations.makeMigrator().migrate(db)
    }

    private init(queue: DatabaseQueue) throws {
        db = queue
        try Migrations.makeMigrator().migrate(db)
    }

    public static func inMemory() throws -> LocalStore {
        try LocalStore(queue: DatabaseQueue())
    }

    public func changes() -> AsyncStream<Void> {
        let key = UUID()
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        subscribers.withLock { $0[key] = continuation }
        continuation.onTermination = { [weak self] _ in
            self?.subscribers.withLock { _ = $0.removeValue(forKey: key) }
        }
        return stream
    }

    private func notify() {
        let live = subscribers.withLock { Array($0.values) }
        for continuation in live { continuation.yield() }
    }

    private func write<T: Sendable>(_ body: @Sendable @escaping (Database) throws -> T) async throws -> T {
        let value = try await db.write(body)
        notify()
        return value
    }

    private func writeIfChanged(_ body: @Sendable @escaping (Database) throws -> Void) async throws {
        let changed = try await db.write { db in
            try body(db)
            return db.changesCount > 0
        }
        if changed { notify() }
    }

    // MARK: Blocks

    public func blocks(in range: DateInterval) async throws -> [TimeBlock] {
        let from = Self.ms(range.start), to = Self.ms(range.end)
        return try await db.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM time_block
                WHERE start_at < ? AND (end_at IS NULL OR end_at > ?) AND deleted_at IS NULL
                ORDER BY start_at, id
                """, arguments: [to, from]).map(Self.block)
        }
    }

    public func runningBlock() async throws -> TimeBlock? {
        try await db.read { db in try Self.fetchRunning(db) }
    }

    public func lastEndedBlock() async throws -> TimeBlock? {
        try await db.read { db in
            try Row.fetchOne(db, sql: """
                SELECT * FROM time_block
                WHERE end_at IS NOT NULL AND deleted_at IS NULL
                ORDER BY end_at DESC, start_at DESC LIMIT 1
                """).map(Self.block)
        }
    }

    public func save(_ block: TimeBlock) async throws {
        let now = Self.ms(Date())
        let tagJSON = try Self.encodeTagIds(block.tagIds)
        try await write { db in
            try db.execute(sql: """
                INSERT INTO time_block (id, title, notes, project_id, tag_ids, start_at, end_at, updated_at, dirty)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1)
                ON CONFLICT(id) DO UPDATE SET
                  title = excluded.title, notes = excluded.notes, project_id = excluded.project_id,
                  tag_ids = excluded.tag_ids, start_at = excluded.start_at, end_at = excluded.end_at,
                  updated_at = excluded.updated_at, dirty = 1
                """, arguments: [
                    Self.idText(block.id), block.title, block.notes, block.projectId.map(Self.idText),
                    tagJSON, Self.ms(block.startAt), block.endAt.map(Self.ms), now,
                ])
        }
    }

    public func deleteBlock(id: UUID) async throws {
        try await softDelete(table: "time_block", id: id)
    }

    // MARK: Timer

    public func startTimer(seed: TimerSeed?, now: Date) async throws -> TimeBlock {
        let nowMs = Self.ms(now)
        let block = TimeBlock(
            title: seed?.title ?? "",
            projectId: seed?.projectId,
            tagIds: seed?.tagIds ?? [],
            startAt: Self.date(nowMs))

        let wallMs = Self.ms(Date())
        let tagJSON = try Self.encodeTagIds(block.tagIds)
        try await write { db in
            try db.execute(sql: """
                UPDATE time_block SET end_at = ?, updated_at = ?, dirty = 1
                WHERE end_at IS NULL AND deleted_at IS NULL
                """, arguments: [nowMs, wallMs])
            try db.execute(sql: """
                INSERT INTO time_block (id, title, notes, project_id, tag_ids, start_at, end_at, updated_at, dirty)
                VALUES (?, ?, '', ?, ?, ?, NULL, ?, 1)
                """, arguments: [
                    Self.idText(block.id), block.title, block.projectId.map(Self.idText),
                    tagJSON, nowMs, wallMs,
                ])
        }
        return block
    }

    public func stopTimer(now: Date) async throws -> TimeBlock? {
        let nowMs = Self.ms(now)
        let wallMs = Self.ms(Date())
        let stopped = try await db.write { db -> TimeBlock? in
            guard let running = try Self.fetchRunning(db) else { return nil }
            try db.execute(
                sql: "UPDATE time_block SET end_at = ?, updated_at = ?, dirty = 1 WHERE id = ?",
                arguments: [nowMs, wallMs, Self.idText(running.id)])
            var stopped = running
            stopped.endAt = Self.date(nowMs)
            return stopped
        }
        if stopped != nil { notify() }
        return stopped
    }

    // MARK: Projects

    public func projects() async throws -> [Project] {
        try await db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM project WHERE deleted_at IS NULL ORDER BY name COLLATE NOCASE, id")
                .map(Self.project)
        }
    }

    public func save(_ project: Project) async throws {
        let now = Self.ms(Date())
        try await write { db in
            try db.execute(sql: """
                INSERT INTO project (id, name, color, updated_at, dirty) VALUES (?, ?, ?, ?, 1)
                ON CONFLICT(id) DO UPDATE SET
                  name = excluded.name, color = excluded.color, updated_at = excluded.updated_at, dirty = 1
                """, arguments: [Self.idText(project.id), project.name, project.color.rawValue, now])
        }
    }

    public func deleteProject(id: UUID) async throws {
        try await softDelete(table: "project", id: id)
    }

    // MARK: Tags

    public func tags() async throws -> [Tag] {
        try await db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM tag WHERE deleted_at IS NULL ORDER BY name COLLATE NOCASE, id")
                .map(Self.tag)
        }
    }

    public func save(_ tag: Tag) async throws {
        let now = Self.ms(Date())
        try await write { db in
            try db.execute(sql: """
                INSERT INTO tag (id, name, updated_at, dirty) VALUES (?, ?, ?, 1)
                ON CONFLICT(id) DO UPDATE SET name = excluded.name, updated_at = excluded.updated_at, dirty = 1
                """, arguments: [Self.idText(tag.id), tag.name, now])
        }
    }

    public func deleteTag(id: UUID) async throws {
        try await softDelete(table: "tag", id: id)
    }

    // MARK: Helpers

    private func softDelete(table: String, id: UUID) async throws {
        let now = Self.ms(Date())
        try await writeIfChanged { db in
            try db.execute(
                sql: "UPDATE \(table) SET deleted_at = ?, updated_at = ?, dirty = 1 WHERE id = ? AND deleted_at IS NULL",
                arguments: [now, now, Self.idText(id)])
        }
    }

    private static func fetchRunning(_ db: Database) throws -> TimeBlock? {
        try Row.fetchOne(
            db, sql: "SELECT * FROM time_block WHERE end_at IS NULL AND deleted_at IS NULL"
        ).map(block)
    }

    private static func ms(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    private static func date(_ ms: Int64) -> Date {
        Date(timeIntervalSince1970: Double(ms) / 1000)
    }

    private static func idText(_ id: UUID) -> String { id.uuidString.lowercased() }

    private static func uuid(_ text: String) throws -> UUID {
        guard let id = UUID(uuidString: text) else { throw StoreError(message: "Invalid id in database: \(text)") }
        return id
    }

    private static func encodeTagIds(_ ids: [UUID]) throws -> String {
        let data = try JSONEncoder().encode(ids.map(idText))
        return String(decoding: data, as: UTF8.self)
    }

    private static func block(_ row: Row) throws -> TimeBlock {
        let tagText: String = row["tag_ids"]
        let tagStrings = try JSONDecoder().decode([String].self, from: Data(tagText.utf8))
        let projectText: String? = row["project_id"]
        let startMs: Int64 = row["start_at"]
        let endMs: Int64? = row["end_at"]
        return TimeBlock(
            id: try uuid(row["id"]),
            title: row["title"],
            notes: row["notes"],
            projectId: try projectText.map(uuid),
            tagIds: try tagStrings.map(uuid),
            startAt: date(startMs),
            endAt: endMs.map(date))
    }

    private static func project(_ row: Row) throws -> Project {
        let colorText: String = row["color"]
        guard let color = PaletteColor(rawValue: colorText) else {
            throw StoreError(message: "Unknown palette color: \(colorText)")
        }
        return Project(id: try uuid(row["id"]), name: row["name"], color: color)
    }

    private static func tag(_ row: Row) throws -> Tag {
        Tag(id: try uuid(row["id"]), name: row["name"])
    }
}
