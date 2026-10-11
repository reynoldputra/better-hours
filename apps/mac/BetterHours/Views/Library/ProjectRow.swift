import BetterHoursCore
import SwiftUI

struct ProjectRow: View {
    let project: Project
    let hours: TimeInterval
    let isSelected: Bool
    let isRenaming: Bool
    let select: () -> Void
    let startRename: () -> Void
    let commitRename: (String) async throws -> Void
    let cancelRename: () -> Void
    let setColor: (PaletteColor) -> Void
    let delete: () -> Void

    @State private var hovering = false
    @State private var showingColors = false
    @State private var confirmingDelete = false
    @FocusState private var focus: Part?

    private enum Part: Hashable { case row, rename, delete }

    private var revealed: Bool { hovering || isSelected || focus != nil }

    var body: some View {
        HStack(spacing: 10) {
            swatch
            if isRenaming {
                InlineNameField(initial: project.name, label: "Project name", commit: commitRename, cancel: cancelRename)
            } else {
                Text(project.name).frame(maxWidth: .infinity, alignment: .leading)
                if revealed {
                    actions
                } else {
                    Text(TimeFormat.duration(hours))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .frame(minHeight: 40)
        .background(hovering || isSelected || isRenaming ? Theme.sunken : .clear)
        .overlay {
            if focus == .row { RoundedRectangle(cornerRadius: Radius.control).strokeBorder(Theme.accent, lineWidth: 2).padding(2) }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { hovering = $0 }
        .focusable(!isRenaming)
        .focusEffectDisabled()
        .focused($focus, equals: .row)
        .onKeyPress(.return) {
            guard !isRenaming else { return .ignored }
            startRename()
            return .handled
        }
        .onChange(of: revealed) { _, now in if !now { confirmingDelete = false } }
        .task(id: confirmingDelete) {
            guard confirmingDelete else { return }
            try? await Task.sleep(for: .seconds(4))
            confirmingDelete = false
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(project.name), \(TimeFormat.duration(hours)) this week")
    }

    private var swatch: some View {
        Button { showingColors = true } label: {
            Circle().fill(project.color.ink).frame(width: 16, height: 16)
                .overlay { Circle().strokeBorder(Theme.muted.opacity(hovering ? 0.6 : 0), lineWidth: 1).padding(-3) }
                .contentShape(Circle().inset(by: -4))
        }
        .buttonStyle(PressedOpacityStyle())
        .help("Change colour of \(project.name)")
        .accessibilityLabel("Change colour of \(project.name)")
        .popover(isPresented: $showingColors, arrowEdge: .bottom) {
            ColorSwatchPicker(selected: project.color) { color in
                showingColors = false
                setColor(color)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: Spacing.xs) {
            Button("Rename", action: startRename)
                .focused($focus, equals: .rename)
                .help("Rename \(project.name)")
            Button(role: .destructive) {
                if confirmingDelete { delete() } else { confirmingDelete = true }
            } label: {
                Text(confirmingDelete ? "Click again to delete" : "Delete")
                    .foregroundStyle(confirmingDelete ? Theme.onAccent : Theme.danger)
            }
            .tint(confirmingDelete ? Theme.danger : nil)
            .background {
                if confirmingDelete { RoundedRectangle(cornerRadius: Radius.control).fill(Theme.danger) }
            }
            .focused($focus, equals: .delete)
            .help(confirmingDelete ? "Click again to delete \(project.name)" : "Delete \(project.name)")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

struct NewProjectRow: View {
    let color: PaletteColor
    let commit: (String) async throws -> Void
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(color.ink).frame(width: 16, height: 16)
            InlineNameField(initial: "", label: "New project name", commit: commit, cancel: cancel)
        }
        .padding(.horizontal, Spacing.md)
        .frame(minHeight: 40)
        .background(Theme.sunken)
    }
}
