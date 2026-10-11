import BetterHoursCore
import SwiftUI

enum LibraryEditing: Equatable {
    case project(UUID), tag(UUID), newProject, newTag
}

enum LibrarySelection: Equatable {
    case project(UUID), tag(UUID)
}

struct LibraryView: View {
    let library: LibraryModel
    @State private var editing: LibraryEditing?
    @State private var selection: LibrarySelection?
    @State private var failure: String?

    init(library: LibraryModel, editing: LibraryEditing? = nil, selection: LibrarySelection? = nil) {
        self.library = library
        _editing = State(initialValue: editing)
        _selection = State(initialValue: selection)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                projectsSection
                tagsSection
                if let failure {
                    Text(failure).font(Fonts.caption).foregroundStyle(Theme.danger)
                }
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { selection = nil }
        }
        .font(Fonts.body)
        .foregroundStyle(Theme.text)
        .background(Theme.background)
        .task {
            while !Task.isCancelled {
                await library.reload()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    // MARK: Projects

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            header("Projects", empty: library.projects.isEmpty && editing != .newProject ? "No projects yet" : nil, newTitle: "New project") {
                editing = .newProject
                selection = nil
            }
            if !library.projects.isEmpty || editing == .newProject {
                VStack(spacing: 0) {
                    ForEach(Array(library.projects.enumerated()), id: \.element.id) { index, project in
                        if index > 0 { Divider() }
                        projectRow(project)
                    }
                    if editing == .newProject {
                        if !library.projects.isEmpty { Divider() }
                        NewProjectRow(color: library.nextProjectColor, commit: { name in
                            _ = try await library.createProject(name: name)
                            editing = nil
                        }, cancel: { editing = nil })
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.line) }
            }
            Text("Hours shown are for this week.").font(Fonts.caption).foregroundStyle(Theme.muted)
        }
    }

    private func projectRow(_ project: Project) -> some View {
        ProjectRow(
            project: project,
            hours: library.weekTotal(of: project.id),
            isSelected: selection == .project(project.id),
            isRenaming: editing == .project(project.id),
            select: { selection = .project(project.id) },
            startRename: {
                selection = .project(project.id)
                editing = .project(project.id)
            },
            commitRename: { name in
                try await library.renameProject(id: project.id, to: name)
                editing = nil
            },
            cancelRename: { editing = nil },
            setColor: { color in attempt { try await library.setProjectColor(id: project.id, color) } },
            delete: { attempt { try await library.deleteProject(id: project.id) } }
        )
    }

    // MARK: Tags

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            header("Tags", empty: library.tags.isEmpty && editing != .newTag ? "No tags yet" : nil, newTitle: "New tag") {
                editing = .newTag
                selection = nil
            }
            if !library.tags.isEmpty || editing == .newTag {
                FlowLayout(spacing: 8) {
                    ForEach(library.tags) { tag in
                        LibraryTagChip(
                            tag: tag,
                            isSelected: selection == .tag(tag.id),
                            isRenaming: editing == .tag(tag.id),
                            select: { selection = selection == .tag(tag.id) ? nil : .tag(tag.id) },
                            startRename: {
                                selection = .tag(tag.id)
                                editing = .tag(tag.id)
                            },
                            commitRename: { name in
                                try await library.renameTag(id: tag.id, to: name)
                                editing = nil
                            },
                            cancelRename: { editing = nil },
                            delete: { attempt { try await library.deleteTag(id: tag.id) } }
                        )
                    }
                    if editing == .newTag {
                        NewTagField(commit: { name in
                            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                            if library.tags.contains(where: { $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame }) {
                                throw LibraryError.duplicateName
                            }
                            _ = try await library.createTag(name: name)
                            editing = nil
                        }, cancel: { editing = nil })
                    }
                }
            }
        }
    }

    // MARK: Pieces

    private func header(_ title: String, empty: String?, newTitle: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: Spacing.sm) {
            Text(title).fontWeight(.semibold)
            Spacer()
            if let empty { Text(empty).foregroundStyle(Theme.muted) }
            Button(newTitle, action: action)
        }
    }

    private func attempt(_ work: @escaping () async throws -> Void) {
        Task {
            do {
                try await work()
                failure = nil
            } catch {
                failure = "Could not save: \(error.localizedDescription)"
            }
        }
    }
}
