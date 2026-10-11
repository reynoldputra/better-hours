import SwiftUI

struct RunningTitleField: View {
    let timer: TimerModel
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Title", text: $draft)
            .textFieldStyle(.roundedBorder)
            .controlSize(.large)
            .font(Fonts.bodyMedium)
            .focused($focused)
            .accessibilityLabel("Running block title")
            .onSubmit(commit)
            .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            .onChange(of: timer.running?.title, initial: true) { _, title in
                if !focused { draft = title ?? "" }
            }
            .onChange(of: timer.running?.id) { _, _ in draft = timer.running?.title ?? "" }
            .onDisappear(perform: commit)
    }

    private func commit() {
        guard timer.isRunning else { return }
        let title = draft
        Task { await timer.renameRunning(title) }
    }
}
