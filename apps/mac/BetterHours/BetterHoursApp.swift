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
    private let demo: DemoConfiguration?

    init() {
        let demo = Demo.configuration()
        let store = demo?.store ?? Self.openStore()
        self.demo = demo
        _calendar = State(initialValue: CalendarModel(
            store: store, clock: demo?.clock ?? Date.init, calendar: demo?.calendar ?? .autoupdatingCurrent
        ))
        _library = State(initialValue: LibraryModel(store: store))
    }

    var body: some Scene {
        Window("Better Hours", id: "main") {
            MainWindowView(calendar: calendar, library: library)
                .frame(minWidth: 900, minHeight: 560)
                .task { await calendar.observeChanges() }
                .task { await calendar.tickClock() }
                .task { await library.observeChanges() }
                .task { await demo?.apply(to: calendar) }
        }
        .windowToolbarStyle(.unified)
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
