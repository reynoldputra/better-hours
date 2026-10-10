import BetterHoursCore
import Foundation
import Observation

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
