import AppKit
import BetterHoursCore
import SwiftUI

struct BlockEditorView: View {
    let calendar: CalendarModel
    let library: LibraryModel
    private let blockId: UUID
    @State private var lastKnown: DraftBox

    @FocusState private var titleFocused: Bool
    @FocusState private var newProjectFocused: Bool
    @State private var creatingProject = false
    @State private var newProjectName = ""
    @State private var projectFailure: String?
    @State private var confirmingDelete = false

    private enum ProjectChoice: Hashable {
        case none, project(UUID), new
    }

    init(calendar: CalendarModel, library: LibraryModel, initial: EditorDraft) {
        self.calendar = calendar
        self.library = library
        blockId = initial.id
        _lastKnown = State(initialValue: DraftBox(initial))
    }

    // Never a force-unwrapping binding: the popover keeps reading it while it dismisses after editing becomes nil.
    private var draftBinding: Binding<EditorDraft> {
        Binding(
            get: {
                if let live = calendar.editing, live.id == blockId { lastKnown.value = live }
                return lastKnown.value
            },
            set: { value in
                lastKnown.value = value
                if calendar.editing?.id == blockId { calendar.editing = value }
            }
        )
    }

    var body: some View {
        content(draftBinding)
    }

    private func content(_ draft: Binding<EditorDraft>) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Edit block").font(Fonts.heading)
            field("Title") {
                TextField("What did you work on?", text: draft.title)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .focused($titleFocused)
            }
            field("Project") { projectPicker(draft) }
            field("Tags") { TagPicker(tagIds: draft.tagIds, library: library, stillOpen: { [calendar, id = blockId] in calendar.editing?.id == id }) }
            times(draft)
            field("Notes") {
                TextEditor(text: draft.notes)
                    .font(Fonts.body)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 4)
                    .frame(height: 88)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: Radius.control))
                    .overlay { RoundedRectangle(cornerRadius: Radius.control).strokeBorder(Theme.line) }
                    .accessibilityLabel("Notes")
            }
            buttons(draft.wrappedValue)
        }
        .padding(Spacing.lg)
        .frame(width: 380)
        .background(Theme.background)
        .tint(Theme.accent)
        .environment(\.calendar, calendar.calendar)
        .environment(\.timeZone, calendar.calendar.timeZone)
        .task {
            try? await Task.sleep(for: .milliseconds(60))
            titleFocused = true
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label).font(Fonts.caption).foregroundStyle(Theme.muted)
            content()
        }
    }

    // MARK: Project

    private func projectPicker(_ draft: Binding<EditorDraft>) -> some View {
        let choice = Binding<ProjectChoice>(
            get: {
                if creatingProject { return .new }
                return draft.wrappedValue.projectId.map(ProjectChoice.project) ?? .none
            },
            set: { value in
                switch value {
                case .none:
                    creatingProject = false
                    draft.wrappedValue.projectId = nil
                case .project(let id):
                    creatingProject = false
                    draft.wrappedValue.projectId = id
                case .new:
                    creatingProject = true
                    projectFailure = nil
                    Task { @MainActor in newProjectFocused = true }
                }
            }
        )
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            Picker("Project", selection: choice) {
                Text("No project").tag(ProjectChoice.none)
                if !library.projects.isEmpty { Divider() }
                ForEach(library.projects) { project in
                    Label { Text(project.name) } icon: { ProjectDot.image(project.color) }
                        .tag(ProjectChoice.project(project.id))
                }
                Divider()
                Text("New project…").tag(ProjectChoice.new)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.large)
            .frame(maxWidth: .infinity, alignment: .leading)
            if creatingProject {
                HStack(spacing: Spacing.sm) {
                    TextField("Project name", text: $newProjectName)
                        .textFieldStyle(.roundedBorder)
                        .focused($newProjectFocused)
                        .onSubmit { createProject(draft) }
                    Button("Create") { createProject(draft) }
                        .disabled(newProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let projectFailure {
                    Text(projectFailure).font(Fonts.caption).foregroundStyle(Theme.danger)
                }
            }
        }
    }

    private func createProject(_ draft: Binding<EditorDraft>) {
        let name = newProjectName
        let blockId = draft.wrappedValue.id
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        Task {
            do {
                let project = try await library.createProject(name: name)
                guard calendar.editing?.id == blockId else { return }
                draft.wrappedValue.projectId = project.id
                creatingProject = false
                newProjectName = ""
            } catch {
                projectFailure = "Could not create the project"
            }
        }
    }

    // MARK: Times

    private func times(_ draft: Binding<EditorDraft>) -> some View {
        let error = draft.wrappedValue.validationError(now: calendar.now)
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            field("When") { WhenRow(draft: draft, calendar: calendar.calendar, now: calendar.now) }
            if let error {
                Text(error).font(Fonts.caption).foregroundStyle(Theme.danger)
            }
        }
    }

    // MARK: Buttons

    private func buttons(_ draft: EditorDraft) -> some View {
        HStack(spacing: Spacing.sm) {
            deleteButton(draft.id)
            Spacer()
            Button("Cancel") { calendar.cancelEditor() }
                .keyboardShortcut(.cancelAction)
                .controlSize(.large)
            Button("Save") { Task { await calendar.saveEditor() } }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(draft.validationError(now: calendar.now) != nil)
        }
        .padding(.top, Spacing.xs)
    }

    private func deleteButton(_ id: UUID) -> some View {
        Button {
            if confirmingDelete {
                Task { await calendar.deleteBlock(id: id) }
            } else {
                confirmingDelete = true
                Task {
                    try? await Task.sleep(for: .seconds(4))
                    confirmingDelete = false
                }
            }
        } label: {
            Text(confirmingDelete ? "Delete block" : "Delete")
                .fontWeight(confirmingDelete ? .semibold : .medium)
                .foregroundStyle(confirmingDelete ? Theme.background : Theme.danger)
                .padding(.horizontal, Spacing.xs)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(confirmingDelete ? Theme.danger : nil)
        .background {
            if confirmingDelete { RoundedRectangle(cornerRadius: Radius.control).fill(Theme.danger) }
        }
        .help(confirmingDelete ? "Click again to delete this block" : "Delete this block")
    }
}

enum ProjectDot {
    @MainActor
    static func image(_ color: PaletteColor) -> Image {
        let name = "Project\(color.assetName)Ink"
        let size = NSSize(width: 10, height: 10)
        let image = NSImage(size: size, flipped: false) { rect in
            (NSColor(named: name) ?? .gray).setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        image.isTemplate = false
        return Image(nsImage: image)
    }
}

private final class DraftBox {
    var value: EditorDraft
    init(_ value: EditorDraft) { self.value = value }
}
