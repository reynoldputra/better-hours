import BetterHoursCore
import AppKit
import ServiceManagement
import SwiftUI
import XCTest
@testable import Better_Hours

@MainActor
final class SnapshotTests: XCTestCase {
    private static let size = CGSize(width: 1120, height: 720)

    private var outputDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".snapshots", isDirectory: true)
    }

    func testRenderSnapshots() async throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        for mode in [CalendarMode.week, .day] {
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                let store = try await SampleData.seeded()
                let calendar = CalendarModel(store: store, clock: { SampleData.now }, calendar: SampleData.calendar)
                let library = LibraryModel(store: store, clock: { SampleData.now }, calendar: SampleData.calendar)
                let timer = TimerModel(store: store, clock: { SampleData.now }, calendar: SampleData.calendar)
                calendar.setMode(mode)
                await calendar.reload()
                await library.reload()
                await timer.refresh()
                let view = MainWindowView(calendar: calendar, library: library, timer: timer, scrollHour: 8)
                let file = outputDirectory.appendingPathComponent("\(mode == .week ? "week" : "day")-\(name).png")
                try await render(view, appearance: appearance, to: file, size: Self.size)
                let size = try XCTUnwrap(try? Data(contentsOf: file)).count
                XCTAssertGreaterThan(size, 10_000, "\(file.lastPathComponent) looks empty")
            }
        }
    }

    func testRenderInteractionStates() async throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let states: [(String, @MainActor (CalendarModel) throws -> Void)] = [
            ("selected", { model in
                model.select(try XCTUnwrap(model.blocks.first { $0.title == "API schema" }?.id))
            }),
            ("creating", { model in
                model.beginCreate(at: SampleData.date(9, 10, 2))
                model.updateDrag(to: SampleData.date(9, 11, 1))
            }),
            ("moving", { model in
                let id = try XCTUnwrap(model.blocks.first { $0.title == "Design review" }?.id)
                model.beginMove(id: id, pointerTime: SampleData.date(5, 9, 20))
                model.updateDrag(to: SampleData.date(9, 14, 22))
            }),
        ]
        for (state, configure) in states {
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                let store = try await SampleData.seeded()
                let calendar = CalendarModel(store: store, clock: { SampleData.now }, calendar: SampleData.calendar)
                let library = LibraryModel(store: store, clock: { SampleData.now }, calendar: SampleData.calendar)
                let timer = TimerModel(store: store, clock: { SampleData.now }, calendar: SampleData.calendar)
                await calendar.reload()
                await library.reload()
                await timer.refresh()
                try configure(calendar)
                let view = MainWindowView(calendar: calendar, library: library, timer: timer, scrollHour: 8)
                let file = outputDirectory.appendingPathComponent("week-\(state)-\(name).png")
                try await render(view, appearance: appearance, to: file, size: Self.size)
                let size = try XCTUnwrap(try? Data(contentsOf: file)).count
                XCTAssertGreaterThan(size, 10_000, "\(file.lastPathComponent) looks empty")
            }
        }
    }

    func testRenderIdleWindow() async throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let store = try await SampleData.seeded()
            let calendar = CalendarModel(store: store, clock: { SampleData.now }, calendar: SampleData.calendar)
            let library = LibraryModel(store: store, clock: { SampleData.now }, calendar: SampleData.calendar)
            let timer = TimerModel(store: store, clock: { SampleData.now }, calendar: SampleData.calendar)
            await timer.stop()
            await calendar.reload()
            await library.reload()
            let view = MainWindowView(calendar: calendar, library: library, timer: timer, scrollHour: 8)
            let file = outputDirectory.appendingPathComponent("week-idle-\(name).png")
            try await render(view, appearance: appearance, to: file, size: Self.size)
            XCTAssertGreaterThan(try XCTUnwrap(try? Data(contentsOf: file)).count, 10_000)
        }
    }

    func testRenderPopovers() async throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let suiteName = "BetterHoursSnapshots-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        for state in ["running", "idle", "empty", "error", "today"] {
            defaults.set(state == "today" ? "today" : "current", forKey: MenubarDisplay.storageKey)
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                let store = state == "empty" || state == "error" ? try LocalStore.inMemory() : try await SampleData.seeded()
                let library = LibraryModel(store: store, clock: { SampleData.now }, calendar: SampleData.calendar)
                let timer = TimerModel(store: store, clock: { SampleData.now }, calendar: SampleData.calendar)
                if state == "idle" { await timer.stop() }
                if state == "error" {
                    await timer.start(title: "Write docs")
                    await timer.start(title: "Again")
                }
                await library.reload()
                await timer.refresh()
                let view = TimerPopoverView(timer: timer, library: library, calendar: SampleData.calendar, defaults: defaults)
                let file = outputDirectory.appendingPathComponent("popover-\(state)-\(name).png")
                try await render(view, appearance: appearance, to: file, size: nil)
                XCTAssertGreaterThan(try XCTUnwrap(try? Data(contentsOf: file)).count, 3_000)
            }
        }
    }

    func testRenderEditor() async throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let store = try await SampleData.seeded()
            let calendar = CalendarModel(store: store, clock: { SampleData.now }, calendar: SampleData.calendar)
            let library = LibraryModel(store: store, clock: { SampleData.now }, calendar: SampleData.calendar)
            await calendar.reload()
            await library.reload()
            let id = try XCTUnwrap(calendar.blocks.first { $0.title == "Design review" }?.id)
            calendar.openEditor(id: id)
            let draft = try XCTUnwrap(calendar.editing)
            let view = BlockEditorView(calendar: calendar, library: library, initial: draft)
            let file = outputDirectory.appendingPathComponent("editor-\(name).png")
            try await render(view, appearance: appearance, to: file, size: nil)
            XCTAssertGreaterThan(try XCTUnwrap(try? Data(contentsOf: file)).count, 3_000)
        }
    }

    func testRenderLibrary() async throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let seeded = try await SampleData.seeded()
            let library = LibraryModel(store: seeded, clock: { SampleData.now }, calendar: SampleData.calendar)
            await library.reload()
            let backend = try XCTUnwrap(library.projects.first { $0.name == "Backend" }?.id)
            let writing = try XCTUnwrap(library.projects.first { $0.name == "Writing" }?.id)
            let ux = try XCTUnwrap(library.tags.first { $0.name == "ux" }?.id)
            let review = try XCTUnwrap(library.tags.first { $0.name == "review" }?.id)
            let empty = LibraryModel(store: try LocalStore.inMemory(), clock: { SampleData.now }, calendar: SampleData.calendar)
            await empty.reload()
            let cases: [(String, LibraryView)] = [
                ("library", LibraryView(library: library)),
                ("library-editing", LibraryView(library: library, editing: .project(writing), selection: .project(backend))),
                ("library-tags", LibraryView(library: library, editing: .tag(review), selection: .tag(ux))),
                ("library-new", LibraryView(library: library, editing: .newProject)),
                ("library-empty", LibraryView(library: empty)),
            ]
            for (prefix, view) in cases {
                let file = outputDirectory.appendingPathComponent("\(prefix)-\(name).png")
                try await render(view, appearance: appearance, to: file, size: CGSize(width: 560, height: 600))
                XCTAssertGreaterThan(try XCTUnwrap(try? Data(contentsOf: file)).count, 3_000)
            }
        }
    }

    func testRenderSettings() async throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let view = SettingsView(model: LaunchAtLogin(service: FakeLoginItem(status: .notRegistered, failure: "Operation not permitted")))
            view.model.set(true)
            let file = outputDirectory.appendingPathComponent("settings-\(name).png")
            try await render(view, appearance: appearance, to: file, size: nil)
            XCTAssertGreaterThan(try XCTUnwrap(try? Data(contentsOf: file)).count, 3_000)
        }
    }

    func testRenderEmptyWeek() async throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let store = try LocalStore.inMemory()
            let calendar = CalendarModel(store: store, clock: { SampleData.now }, calendar: SampleData.calendar)
            let library = LibraryModel(store: store, clock: { SampleData.now }, calendar: SampleData.calendar)
            let timer = TimerModel(store: store, clock: { SampleData.now }, calendar: SampleData.calendar)
            await calendar.reload()
            await library.reload()
            await timer.refresh()
            let view = MainWindowView(calendar: calendar, library: library, timer: timer, scrollHour: 8)
            let file = outputDirectory.appendingPathComponent("week-empty-\(name).png")
            try await render(view, appearance: appearance, to: file, size: Self.size)
            XCTAssertGreaterThan(try XCTUnwrap(try? Data(contentsOf: file)).count, 10_000)
        }
    }

    private func render(_ view: some View, appearance: NSAppearance.Name, to url: URL, size: CGSize?) async throws {
        let fitted = size ?? NSHostingView(rootView: view).fittingSize
        let host = NSHostingView(rootView: view.frame(width: fitted.width, height: fitted.height))
        let window = ActiveWindow(
            contentRect: CGRect(origin: .zero, size: fitted),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        window.orderBack(nil)
        defer { window.orderOut(nil) }
        for _ in 0..<6 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
        }
        let bounds = host.bounds
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: bounds))
        host.cacheDisplay(in: bounds, to: rep)
        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try data.write(to: url)
    }
}

private final class ActiveWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var isKeyWindow: Bool { true }
}

@MainActor
final class FakeLoginItem: LoginItemService {
    var status: SMAppService.Status
    var failure: String?

    init(status: SMAppService.Status, failure: String? = nil) {
        self.status = status
        self.failure = failure
    }

    func register() throws {
        if let failure { throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: failure]) }
        status = .enabled
    }

    func unregister() throws {
        if let failure { throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: failure]) }
        status = .notRegistered
    }
}
