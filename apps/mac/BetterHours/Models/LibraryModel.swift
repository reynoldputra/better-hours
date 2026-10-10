import BetterHoursCore
import Foundation
import Observation

enum LibraryError: Error, Equatable {
    case emptyName
}

@Observable @MainActor
final class LibraryModel {
    private(set) var projects: [Project] = []
    private(set) var tags: [Tag] = []
    private(set) var loadError: String?

    private let store: LocalStore

    init(store: LocalStore) {
        self.store = store
    }

    func project(id: UUID?) -> Project? {
        guard let id else { return nil }
        return projects.first { $0.id == id }
    }

    func createProject(name: String) async throws -> Project {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LibraryError.emptyName }
        let existing = try await store.projects()
        let used = Set(existing.map(\.color))
        let all = PaletteColor.allCases
        let color = all.first { !used.contains($0) } ?? all[existing.count % all.count]
        let project = Project(name: trimmed, color: color)
        try await store.save(project)
        await reload()
        return project
    }

    func createTag(name: String) async throws -> Tag {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LibraryError.emptyName }
        if let match = try await store.tags().first(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).compare(trimmed, options: .caseInsensitive) == .orderedSame }) {
            return match
        }
        let tag = Tag(name: trimmed)
        try await store.save(tag)
        await reload()
        return tag
    }

    func reload() async {
        do {
            projects = try await store.projects()
            tags = try await store.tags()
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
