import BetterHoursCore
import SwiftUI

struct TagPicker: View {
    @Binding var tagIds: [UUID]
    let library: LibraryModel
    let stillOpen: () -> Bool
    @State private var query = ""
    @State private var failure: String?
    @FocusState private var fieldFocused: Bool

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var selected: [Tag] {
        tagIds.compactMap { id in library.tags.first { $0.id == id } }
    }

    private var suggestions: [Tag] {
        let available = library.tags.filter { !tagIds.contains($0.id) }
        let matches = trimmed.isEmpty ? available : available.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
        return Array(matches.prefix(5))
    }

    private var exactMatch: Tag? {
        library.tags.first { $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame }
    }

    private var canCreate: Bool { !trimmed.isEmpty && exactMatch == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            FlowLayout(spacing: 6) {
                ForEach(selected) { tag in
                    TagChip(name: tag.name, style: .removable) { tagIds.removeAll { $0 == tag.id } }
                }
                TextField("Add tag…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(minWidth: 90)
                    .focused($fieldFocused)
                    .onSubmit(commit)
                    .accessibilityLabel("Add tag")
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: Metrics.controlHeight, alignment: .leading)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: Radius.control))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.control)
                    .strokeBorder(fieldFocused ? Theme.accent : Theme.line)
            }
            .overlay {
                if fieldFocused {
                    RoundedRectangle(cornerRadius: Radius.control + 1.5)
                        .strokeBorder(Theme.accentSoft, lineWidth: 3).padding(-1.5)
                }
            }
            if fieldFocused || !trimmed.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(suggestions) { tag in
                        TagChip(name: tag.name, style: .suggestion) { add(tag) }
                    }
                    if canCreate {
                        TagChip(name: "Create “\(trimmed)”", style: .create) { commit() }
                    }
                }
            }
            if let failure {
                Text(failure).font(Fonts.caption).foregroundStyle(Theme.danger)
            }
        }
    }

    private func add(_ tag: Tag) {
        if !tagIds.contains(tag.id) { tagIds.append(tag.id) }
        query = ""
        fieldFocused = true
    }

    private func commit() {
        guard !trimmed.isEmpty else { return }
        if let exactMatch {
            add(exactMatch)
            return
        }
        let name = trimmed
        Task {
            do {
                let tag = try await library.createTag(name: name)
                guard stillOpen() else { return }
                add(tag)
                failure = nil
            } catch {
                failure = "Could not create the tag"
            }
        }
    }
}

struct TagChip: View {
    enum Style { case removable, suggestion, create }

    let name: String
    let style: Style
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(name)
                if style == .removable {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).opacity(hovering ? 1 : 0.55)
                }
            }
            .font(.system(size: 12, weight: style == .suggestion ? .semibold : .medium))
            .foregroundStyle(style == .create ? Theme.muted : style == .suggestion ? Theme.accentText : Theme.text)
            .padding(.leading, 10)
            .padding(.trailing, style == .removable ? 8 : 10)
            .frame(height: 24)
            .background(fill, in: Capsule())
            .overlay {
                if style == .create {
                    Capsule().strokeBorder(Theme.muted, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(style == .removable ? "Remove tag “\(name)”" : style == .create ? name : "Add tag “\(name)”")
        .accessibilityLabel(style == .removable ? "Remove tag \(name)" : style == .create ? name : "Add tag \(name)")
    }

    private var fill: Color {
        switch style {
        case .removable: hovering ? Theme.line : Theme.sunken
        case .suggestion: hovering ? Theme.accentSoft.opacity(0.7) : Theme.accentSoft
        case .create: hovering ? Theme.sunken : .clear
        }
    }
}
