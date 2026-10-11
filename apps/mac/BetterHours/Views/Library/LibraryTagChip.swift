import BetterHoursCore
import SwiftUI

struct LibraryTagChip: View {
    let tag: Tag
    let isSelected: Bool
    let isRenaming: Bool
    let select: () -> Void
    let startRename: () -> Void
    let commitRename: (String) async throws -> Void
    let cancelRename: () -> Void
    let delete: () -> Void

    @State private var hovering = false
    @State private var confirmingDelete = false
    @FocusState private var focus: Part?

    private enum Part: Hashable { case chip, rename, delete }

    private var revealed: Bool { hovering || isSelected || focus != nil }

    var body: some View {
        Group {
            if isRenaming {
                InlineNameField(initial: tag.name, label: "Tag name", commit: commitRename, cancel: cancelRename)
                    .frame(width: 200, alignment: .leading)
            } else {
                chip
            }
        }
        .onChange(of: revealed) { _, now in if !now { confirmingDelete = false } }
        .task(id: confirmingDelete) {
            guard confirmingDelete else { return }
            try? await Task.sleep(for: .seconds(4))
            confirmingDelete = false
        }
    }

    private var chip: some View {
        HStack(spacing: 2) {
            Button(action: select) {
                Text(tag.name)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Theme.accentText : Theme.text)
                    .padding(.leading, 10)
                    .padding(.trailing, revealed ? 4 : 10)
                    .frame(height: 26)
                    .contentShape(Capsule())
            }
            .buttonStyle(PressedOpacityStyle())
            .focused($focus, equals: .chip)
            .accessibilityLabel(tag.name)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            if revealed {
                Button(action: startRename) { Image(systemName: "pencil").frame(width: 20, height: 20) }
                    .focused($focus, equals: .rename)
                    .help("Rename tag “\(tag.name)”")
                    .accessibilityLabel("Rename tag \(tag.name)")
                Button {
                    if confirmingDelete { delete() } else { confirmingDelete = true }
                } label: {
                    if confirmingDelete {
                        Text("Delete?").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.onAccent)
                            .padding(.horizontal, 6).frame(height: 20)
                            .background(Theme.danger, in: Capsule())
                    } else {
                        Image(systemName: "trash").foregroundStyle(Theme.danger).frame(width: 20, height: 20)
                    }
                }
                .focused($focus, equals: .delete)
                .help(confirmingDelete ? "Click again to delete “\(tag.name)”" : "Delete tag “\(tag.name)”")
                .accessibilityLabel(confirmingDelete ? "Confirm delete tag \(tag.name)" : "Delete tag \(tag.name)")
                .padding(.trailing, 4)
            }
        }
        .buttonStyle(.borderless)
        .background(isSelected ? Theme.accentSoft : hovering ? Theme.line : Theme.sunken, in: Capsule())
        .overlay { if focus == .chip { Capsule().strokeBorder(Theme.accent, lineWidth: 2) } }
        .onHover { hovering = $0 }
    }
}

struct NewTagField: View {
    let commit: (String) async throws -> Void
    let cancel: () -> Void

    var body: some View {
        InlineNameField(initial: "", label: "New tag name", commit: commit, cancel: cancel)
            .frame(width: 200, alignment: .leading)
    }
}
