import AppKit
import BetterHoursCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let opener = WindowOpener()

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        opener.show()
        return true
    }
}

@main
struct BetterHoursApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var calendar: CalendarModel
    @State private var library: LibraryModel
    @State private var timer: TimerModel
    private let demo: DemoConfiguration?

    init() {
        let demo = Demo.configuration()
        let store = demo?.store ?? Self.openStore()
        let clock = demo?.clock ?? Date.init
        let calendar = demo?.calendar ?? .autoupdatingCurrent
        self.demo = demo
        let library = LibraryModel(store: store)
        let timer = TimerModel(store: store, clock: clock, calendar: calendar)
        _calendar = State(initialValue: CalendarModel(store: store, clock: clock, calendar: calendar))
        _library = State(initialValue: library)
        _timer = State(initialValue: timer)
        // The menubar must stay live with the main window closed, so these outlive any view.
        Task { await library.observeChanges() }
        Task { await timer.observeChanges() }
    }

    var body: some Scene {
        Window("Better Hours", id: "main") {
            MainWindowView(calendar: calendar, library: library, timer: timer)
                .frame(minWidth: 900, minHeight: 560)
                .task { await calendar.observeChanges() }
                .task { await calendar.tickClock() }
                .task { await demo?.apply(to: calendar) }
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1120, height: 720)

        MenuBarExtra {
            MenubarPopoverHost(
                timer: timer, library: library, calendar: calendar.calendar, opener: delegate.opener
            )
        } label: {
            MenubarLabelHost(timer: timer, opener: delegate.opener)
        }
        .menuBarExtraStyle(.window)
    }

    private static func openStore() -> LocalStore {
        do {
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
                return try LocalStore.inMemory()
            }
            let folder = try FileManager.default
                .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("Better Hours", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return try LocalStore(path: folder.appendingPathComponent("betterhours.sqlite"))
        } catch {
            let alert = NSAlert()
            alert.messageText = "Better Hours cannot open its database"
            alert.informativeText = "\(error)"
            alert.runModal()
            exit(1)
        }
    }
}
