import BetterHoursCore
import Foundation
import Observation

enum LibraryError: Error, Equatable {
    case emptyName
    case duplicateName
    case notFound
}

@Observable @MainActor
final class LibraryModel {
    private(set) var projects: [Project] = []
    private(set) var tags: [Tag] = []
    private(set) var loadError: String?
    private(set) var weekTotals: [UUID: TimeInterval] = [:]

    private let store: LocalStore
    private let clock: @Sendable () -> Date
    private let calendar: Calendar

    init(store: LocalStore, clock: @escaping @Sendable () -> Date, calendar: Calendar) {
        self.store = store
        self.clock = clock
        self.calendar = calendar
    }

    var nextProjectColor: PaletteColor { Self.nextColor(after: projects) }

    private static func nextColor(after existing: [Project]) -> PaletteColor {
        let used = Set(existing.map(\.color))
        let all = PaletteColor.allCases
        return all.first { !used.contains($0) } ?? all[existing.count % all.count]
    }

    func weekTotal(of id: UUID) -> TimeInterval { weekTotals[id] ?? 0 }

    func project(id: UUID?) -> Project? {
        guard let id else { return nil }
        return projects.first { $0.id == id }
    }

    func createProject(name: String) async throws -> Project {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LibraryError.emptyName }
        let existing = try await store.projects()
        let project = Project(name: trimmed, color: Self.nextColor(after: existing))
        try await store.save(project)
        await reload()
        return project
    }

    func createTag(name: String) async throws -> Tag {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LibraryError.emptyName }
        if let match = try await store.tags().first(where: { Self.sameName($0.name, trimmed) }) {
            return match
        }
        let tag = Tag(name: trimmed)
        try await store.save(tag)
        await reload()
        return tag
    }

    func renameProject(id: UUID, to name: String) async throws {
        let trimmed = try Self.validated(name)
        guard var project = try await store.projects().first(where: { $0.id == id }) else { throw LibraryError.notFound }
        guard project.name != trimmed else { return }
        project.name = trimmed
        try await store.save(project)
        await reload()
    }

    func setProjectColor(id: UUID, _ color: PaletteColor) async throws {
        guard var project = try await store.projects().first(where: { $0.id == id }) else { throw LibraryError.notFound }
        guard project.color != color else { return }
        project.color = color
        try await store.save(project)
        await reload()
    }

    func deleteProject(id: UUID) async throws {
        try await store.deleteProject(id: id)
        await reload()
    }

    func renameTag(id: UUID, to name: String) async throws {
        let trimmed = try Self.validated(name)
        let all = try await store.tags()
        guard var tag = all.first(where: { $0.id == id }) else { throw LibraryError.notFound }
        guard tag.name != trimmed else { return }
        if all.contains(where: { $0.id != id && Self.sameName($0.name, trimmed) }) { throw LibraryError.duplicateName }
        tag.name = trimmed
        try await store.save(tag)
        await reload()
    }

    func deleteTag(id: UUID) async throws {
        try await store.deleteTag(id: id)
        await reload()
    }

    private static func validated(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LibraryError.emptyName }
        return trimmed
    }

    private static func sameName(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: .whitespacesAndNewlines).compare(b, options: .caseInsensitive) == .orderedSame
    }

    func reload() async {
        do {
            projects = try await store.projects()
            tags = try await store.tags()
            let now = clock()
            let week = calendar.dateInterval(of: .weekOfYear, for: now) ?? DateInterval(start: calendar.startOfDay(for: now), duration: 7 * 86_400)
            let blocks = try await store.blocks(in: week)
            var byProject: [UUID: [TimeBlock]] = [:]
            for block in blocks { if let id = block.projectId { byProject[id, default: []].append(block) } }
            weekTotals = byProject.mapValues { total(of: $0, in: week, now: now) }
            loadError = nil
        } catch {
            loadError = "\(error)"
        }
    }

    func observeChanges() async {
        let changes = store.changes()
        await reload()
        for await _ in changes { await reload() }
    }
}
