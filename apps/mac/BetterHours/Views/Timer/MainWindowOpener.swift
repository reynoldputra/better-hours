import AppKit
import SwiftUI

@MainActor
final class WindowOpener {
    var open: (() -> Void)?

    // The scene id "main" is also the NSWindow identifier, which keeps popovers and alerts out of the check.
    private var mainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == "main" && ($0.isVisible || $0.isMiniaturized) }
    }

    func show() {
        if let window = mainWindow {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            open?()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    var hasMainWindow: Bool { mainWindow != nil }
}

struct MenubarLabelHost: View {
    let timer: TimerModel
    let opener: WindowOpener
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MenubarLabel(timer: timer)
            .task {
                opener.open = { openWindow(id: "main") }
                // Saved window state can leave the app with no window at launch.
                try? await Task.sleep(for: .milliseconds(500))
                if !opener.hasMainWindow { opener.show() }
            }
    }
}

struct MenubarPopoverHost: View {
    let timer: TimerModel
    let library: LibraryModel
    let calendar: Calendar
    let opener: WindowOpener

    var body: some View {
        TimerPopoverView(timer: timer, library: library, calendar: calendar, openMainWindow: { opener.show() })
    }
}
