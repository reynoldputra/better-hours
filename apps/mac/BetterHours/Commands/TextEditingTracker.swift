import AppKit
import Observation

// Menu key equivalents run before the text system, so ⌘← would never reach a field being edited. Disabling those items while a text view has focus hands the keys back to the responder chain.
@Observable @MainActor
final class TextEditingTracker {
    private(set) var isEditing = false
    private var observer: (any NSObjectProtocol)?

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didUpdateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
    }

    func update() {
        let editing = NSApp.keyWindow?.firstResponder is NSTextView
        if editing != isEditing { isEditing = editing }
    }
}
