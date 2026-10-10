import AppKit
import BetterHoursCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct BetterHoursApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var calendar: CalendarModel
    @State private var library: LibraryModel

    init() {
        let store = Self.openStore()
        _calendar = State(initialValue: CalendarModel(store: store, clock: Date.init, calendar: .autoupdatingCurrent))
        _library = State(initialValue: LibraryModel(store: store))
    }

    var body: some Scene {
        Window("Better Hours", id: "main") {
            MainWindowView(calendar: calendar, library: library, leadingInset: 78)
                .frame(minWidth: 900, minHeight: 560)
                .task { await calendar.observeChanges() }
                .task { await calendar.tickClock() }
                .task { await library.observeChanges() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1120, height: 720)
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
