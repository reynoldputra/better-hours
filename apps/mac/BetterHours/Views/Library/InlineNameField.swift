import SwiftUI

struct InlineNameField: View {
    let initial: String
    let label: String
    let commit: (String) async throws -> Void
    let cancel: () -> Void

    @State private var text: String
    @State private var error: String?
    @State private var committing = false
    @State private var escaped = false
    @FocusState private var focused: Bool

    init(initial: String, label: String, commit: @escaping (String) async throws -> Void, cancel: @escaping () -> Void) {
        self.initial = initial
        self.label = label
        self.commit = commit
        self.cancel = cancel
        _text = State(initialValue: initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            TextField(label, text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(submit)
                .onExitCommand {
                    escaped = true
                    cancel()
                }
                .onChange(of: text) { _, _ in error = nil }
                .onChange(of: focused) { old, new in if old && !new { focusLeft() } }
                .onAppear { focused = true }
                .accessibilityLabel(label)
            if let error {
                Text(error).font(Fonts.caption).foregroundStyle(Theme.danger)
            }
        }
    }

    // Like Finder: leaving the field commits a valid, changed name and discards anything else.
    private func focusLeft() {
        guard !committing, !escaped else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == initial.trimmingCharacters(in: .whitespacesAndNewlines) {
            cancel()
        } else {
            submit()
        }
    }

    private func submit() {
        guard !committing else { return }
        committing = true
        Task {
            defer { committing = false }
            do {
                try await commit(text)
            } catch LibraryError.emptyName {
                error = "The name cannot be empty."
            } catch LibraryError.duplicateName {
                error = "A tag with that name already exists."
            } catch {
                self.error = "Could not save: \(error.localizedDescription)"
            }
        }
    }
}
